import 'package:drift/drift.dart';

import 'album_grouping.dart';
import 'database.dart';

/// An album row plus its tracks, joined and grouped in one query — the
/// Albums screen queries this instead of re-deriving groups from
/// [Track.album] text itself. [id] is -1 for the rare track that briefly has
/// no [Track.albumId] (mid-scan, before [LibraryRepository.backfillAlbumGroups]
/// has run) rather than dropping it from the list.
class AlbumWithTracks {
  final int id;
  final String title;
  final String? artist;
  final int? year;
  final String? coverArtPath;
  final List<Track> tracks;

  const AlbumWithTracks({
    required this.id,
    required this.title,
    required this.artist,
    required this.year,
    required this.coverArtPath,
    required this.tracks,
  });
}

/// Thin query layer over [AppDatabase] — the rest of the app talks to the
/// library through this, never through raw Drift queries.
class LibraryRepository {
  final AppDatabase db;

  LibraryRepository(this.db);

  /// Sorted by artist then title, so the library reads as grouped-by-artist
  /// rather than one flat alphabetical-by-title list with every artist
  /// interleaved.
  Stream<List<Track>> watchAllTracks() {
    return (db.select(db.tracks)..orderBy([
          (t) => OrderingTerm(expression: t.artist),
          (t) => OrderingTerm(expression: t.title),
        ]))
        .watch();
  }

  /// Albums joined with their tracks, sorted by title — the Albums screen's
  /// data source. A track whose [Track.albumId] doesn't (yet) resolve to a
  /// row — only possible for the moment between a track being inserted and
  /// [backfillAlbumGroups] catching up on app start — is still included,
  /// grouped under a synthetic id of -1 with the Unknown Album title, rather
  /// than silently vanishing from the screen.
  Stream<List<AlbumWithTracks>> watchAlbums() {
    final query = db.select(db.tracks).join([
      leftOuterJoin(db.albums, db.albums.id.equalsExp(db.tracks.albumId)),
    ]);
    return query.watch().map((rows) {
      final tracksByKey = <int, List<Track>>{};
      final albumByKey = <int, Album>{};
      for (final row in rows) {
        final track = row.readTable(db.tracks);
        final album = row.readTableOrNull(db.albums);
        final key = album?.id ?? -1;
        if (album != null) albumByKey[key] = album;
        tracksByKey.putIfAbsent(key, () => []).add(track);
      }
      final result = tracksByKey.entries.map((entry) {
        final album = albumByKey[entry.key];
        final tracks = entry.value;
        final fallbackArt = tracks
            .firstWhere(
              (t) => t.albumArtPath != null,
              orElse: () => tracks.first,
            )
            .albumArtPath;
        return AlbumWithTracks(
          id: entry.key,
          title: album?.title ?? unknownAlbumTitle,
          artist: album?.artist,
          year: album?.year,
          coverArtPath: album?.coverArtPath ?? fallbackArt,
          tracks: tracks,
        );
      }).toList()..sort((a, b) => a.title.compareTo(b.title));
      return result;
    });
  }

  /// Regroups any track left over from before album grouping existed (a
  /// null [Track.albumId]) using its already-stored tags — no re-scan of the
  /// file itself needed, since the tags were captured at scan time. Safe to
  /// call on every app start: a no-op once every track has an albumId, and
  /// idempotent against concurrent scans because [findOrCreateAlbum] is
  /// itself race-safe.
  Future<void> backfillAlbumGroups() async {
    final orphans = await (db.select(
      db.tracks,
    )..where((t) => t.albumId.isNull())).get();
    if (orphans.isEmpty) return;

    await db.transaction(() async {
      for (final track in orphans) {
        final albumId = await findOrCreateAlbum(
          albumKeyFor(
            album: track.album,
            albumArtist: track.albumArtist,
            artist: track.artist,
          ),
          year: track.year,
        );
        await (db.update(db.tracks)..where((t) => t.id.equals(track.id))).write(
          TracksCompanion(albumId: Value(albumId)),
        );
        if (track.albumArtPath != null) {
          await setAlbumCoverIfMissing(albumId, track.albumArtPath!);
        }
      }
    });
  }

  Future<bool> trackExists(String filePath) async {
    final row = await (db.select(
      db.tracks,
    )..where((t) => t.filePath.equals(filePath))).getSingleOrNull();
    return row != null;
  }

  /// Looks up a track by its stable row id — used to resume the last
  /// played track on startup (see AppSettingsState.lastTrackId), since a
  /// filePath alone wouldn't survive the track being renamed/moved.
  Future<Track?> getTrackById(int id) {
    return (db.select(
      db.tracks,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  /// Every currently-indexed file path — used to force a metadata re-scan
  /// of tracks that were indexed before tag parsing existed (or before a
  /// new format reader was added), since the normal scan skips anything
  /// it already recognizes as indexed.
  Future<List<String>> getAllFilePaths() async {
    final rows = await db.select(db.tracks).get();
    return rows.map((t) => t.filePath).toList();
  }

  /// Looks up the track ids currently indexed for [filePaths] — used to add
  /// just-scanned files straight into a playlist without a separate
  /// find-and-select step.
  Future<List<int>> getTrackIdsForPaths(List<String> filePaths) async {
    if (filePaths.isEmpty) return [];
    final rows = await (db.select(
      db.tracks,
    )..where((t) => t.filePath.isIn(filePaths))).get();
    return rows.map((t) => t.id).toList();
  }

  /// Returns the row id — needed so the scanner can save extracted artwork
  /// against the right track right after inserting it.
  ///
  /// Explicit onConflict target is required here: filePath is a unique
  /// column but not the primary key, and Drift's plain
  /// insertOnConflictUpdate() only detects conflicts on the primary key by
  /// default — it would otherwise let the raw SQLite UNIQUE constraint
  /// error surface uncaught whenever a path is re-inserted (e.g. a forced
  /// metadata refresh). insertReturning is used instead of the int-returning
  /// insertOnConflictUpdate() because that method's returned id is
  /// documented as unreliable specifically on the conflict/update path.
  Future<int> upsertTrack(TracksCompanion entry) async {
    final track = await db
        .into(db.tracks)
        .insertReturning(
          entry,
          onConflict: DoUpdate((old) => entry, target: [db.tracks.filePath]),
        );
    return track.id;
  }

  /// Returns the id of the album for [key], creating it on first sight.
  /// Race-safe against the unique groupKey (insert-or-ignore, then read
  /// back) so concurrent/repeated scans can never produce duplicate albums.
  /// [year] only ever fills in a missing year — it never overwrites one
  /// already set — and is ignored for the Unknown Album bucket, where a
  /// single "year" would be meaningless across unrelated files.
  Future<int> findOrCreateAlbum(AlbumKey key, {int? year}) async {
    await db
        .into(db.albums)
        .insert(
          AlbumsCompanion.insert(
            groupKey: key.groupKey,
            title: key.title,
            artist: Value(key.artist),
            year: Value(key.isUnknown ? null : year),
          ),
          mode: InsertMode.insertOrIgnore,
        );
    final album = await (db.select(
      db.albums,
    )..where((a) => a.groupKey.equals(key.groupKey))).getSingle();
    if (album.year == null && year != null && !key.isUnknown) {
      await (db.update(db.albums)..where((a) => a.id.equals(album.id))).write(
        AlbumsCompanion(year: Value(year)),
      );
    }
    return album.id;
  }

  /// Gives the album a cover if it doesn't have one yet — first track with
  /// art wins, later tracks never replace it.
  Future<void> setAlbumCoverIfMissing(int albumId, String coverArtPath) {
    return (db.update(db.albums)
          ..where((a) => a.id.equals(albumId) & a.coverArtPath.isNull()))
        .write(AlbumsCompanion(coverArtPath: Value(coverArtPath)));
  }

  Future<void> setSyncedLyrics(int id, String lrc) {
    return (db.update(db.tracks)..where((t) => t.id.equals(id))).write(
      TracksCompanion(syncedLyrics: Value(lrc)),
    );
  }

  /// Applies lyrics found by a rescan, keyed by file path; a null field
  /// leaves that column as it was.
  Future<void> setLyricsForPaths(
    Map<String, ({String? plain, String? synced})> byPath,
  ) {
    return db.transaction(() async {
      for (final e in byPath.entries) {
        await (db.update(
          db.tracks,
        )..where((t) => t.filePath.equals(e.key))).write(
          TracksCompanion(
            lyrics: e.value.plain != null
                ? Value(e.value.plain)
                : const Value.absent(),
            syncedLyrics: e.value.synced != null
                ? Value(e.value.synced)
                : const Value.absent(),
          ),
        );
      }
    });
  }

  Future<void> setAlbumArtPath(int id, String path) {
    return (db.update(db.tracks)..where((t) => t.id.equals(id))).write(
      TracksCompanion(albumArtPath: Value(path)),
    );
  }

  /// Called from PlaybackController the first time a track's real duration
  /// becomes known from actual playback — for formats whose tag reader
  /// can't get duration essentially for free (unlike FLAC's STREAMINFO),
  /// this is how they end up with one at all, without an expensive
  /// dedicated probe-every-file scan step.
  Future<void> setTrackDuration(int id, int durationMs) {
    return (db.update(db.tracks)..where((t) => t.id.equals(id))).write(
      TracksCompanion(durationMs: Value(durationMs)),
    );
  }

  Future<void> deleteTrack(int id) async {
    final track = await getTrackById(id);
    // Clean up any playlist memberships too, or they'd be orphaned rows
    // pointing at a track that no longer exists.
    await (db.delete(
      db.playlistTracks,
    )..where((pt) => pt.trackId.equals(id))).go();
    await (db.delete(db.tracks)..where((t) => t.id.equals(id))).go();
    if (track?.albumId != null) await _deleteAlbumIfEmpty(track!.albumId!);
  }

  /// Removes an album row once its last track is gone — otherwise deleting
  /// every song from an album would leave an empty, permanently-orphaned
  /// row behind. Never touches the shared Unknown Album bucket: an "empty"
  /// Unknown Album just means every remaining track happens to be tagged,
  /// not that the bucket itself should disappear.
  Future<void> _deleteAlbumIfEmpty(int albumId) async {
    final remaining =
        await (db.select(db.tracks)
              ..where((t) => t.albumId.equals(albumId))
              ..limit(1))
            .getSingleOrNull();
    if (remaining != null) return;
    await (db.delete(db.albums)..where(
          (a) =>
              a.id.equals(albumId) &
              a.groupKey.equals(unknownAlbumGroupKey).not(),
        ))
        .go();
  }

  Future<void> deleteTrackByPath(String filePath) async {
    final row = await (db.select(
      db.tracks,
    )..where((t) => t.filePath.equals(filePath))).getSingleOrNull();
    if (row == null) return;
    await deleteTrack(row.id);
  }

  /// Which playlists [trackId] currently belongs to — captured before a
  /// delete so Undo can put the track back where it was.
  Future<List<int>> getPlaylistIdsForTrack(int trackId) async {
    final rows = await (db.select(
      db.playlistTracks,
    )..where((pt) => pt.trackId.equals(trackId))).get();
    return rows.map((pt) => pt.playlistId).toList();
  }

  /// Re-inserts a track (a fresh row/id — its old id isn't reused) and puts
  /// it back in [playlistIds], for Undo after a deletion. Playlist entries
  /// go to the end of each playlist rather than their exact prior position,
  /// which is a reasonable trade for how much simpler it keeps this.
  Future<void> restoreTrack(Track track, List<int> playlistIds) async {
    final newId = await upsertTrack(
      TracksCompanion.insert(
        filePath: track.filePath,
        title: track.title,
        artist: Value(track.artist),
        album: Value(track.album),
        format: track.format,
        durationMs: track.durationMs != null
            ? Value(track.durationMs)
            : const Value.absent(),
        albumArtPath: track.albumArtPath != null
            ? Value(track.albumArtPath)
            : const Value.absent(),
        lyrics: track.lyrics != null
            ? Value(track.lyrics)
            : const Value.absent(),
        albumId: track.albumId != null
            ? Value(track.albumId)
            : const Value.absent(),
        albumArtist: track.albumArtist != null
            ? Value(track.albumArtist)
            : const Value.absent(),
        year: track.year != null ? Value(track.year) : const Value.absent(),
        genre: track.genre != null ? Value(track.genre) : const Value.absent(),
        trackNumber: track.trackNumber != null
            ? Value(track.trackNumber)
            : const Value.absent(),
        syncedLyrics: track.syncedLyrics != null
            ? Value(track.syncedLyrics)
            : const Value.absent(),
      ),
    );
    for (final playlistId in playlistIds) {
      await addTrackToPlaylist(playlistId, newId);
    }
  }

  Future<void> clearAll() {
    return db.delete(db.tracks).go();
  }

  /// Wipes tracks, playlists, and playlist memberships — a full reset, used
  /// by Settings' "Clear Library" (playlists left behind would just be
  /// empty shells otherwise).
  Future<void> clearEverything() async {
    await db.delete(db.playlistTracks).go();
    await db.delete(db.playlists).go();
    await db.delete(db.tracks).go();
    await db.delete(db.albums).go();
  }

  Stream<List<Playlist>> watchPlaylists() {
    return (db.select(
      db.playlists,
    )..orderBy([(p) => OrderingTerm(expression: p.name)])).watch();
  }

  Future<int> createPlaylist(String name) {
    return db.into(db.playlists).insert(PlaylistsCompanion.insert(name: name));
  }

  Future<void> renamePlaylist(int id, String name) {
    return (db.update(db.playlists)..where((p) => p.id.equals(id))).write(
      PlaylistsCompanion(name: Value(name)),
    );
  }

  Future<void> deletePlaylist(int id) async {
    await (db.delete(
      db.playlistTracks,
    )..where((pt) => pt.playlistId.equals(id))).go();
    await (db.delete(db.playlists)..where((p) => p.id.equals(id))).go();
  }

  /// Track ids in a playlist's exact order — captured before a delete so
  /// Undo can rebuild the playlist with the same songs in the same order.
  Future<List<int>> getPlaylistTrackIdsInOrder(int playlistId) async {
    final query = db.select(db.playlistTracks)
      ..where((pt) => pt.playlistId.equals(playlistId))
      ..orderBy([(pt) => OrderingTerm(expression: pt.position)]);
    final rows = await query.get();
    return rows.map((r) => r.trackId).toList();
  }

  /// Recreates a deleted playlist — for Undo. A fresh id; [trackIds] order
  /// is preserved exactly since addTracksToPlaylist appends in list order.
  Future<void> restorePlaylist(String name, List<int> trackIds) async {
    final newPlaylistId = await createPlaylist(name);
    await addTracksToPlaylist(newPlaylistId, trackIds);
  }

  /// Appends [trackId] to the end of the playlist. No-op if already present.
  Future<void> addTrackToPlaylist(int playlistId, int trackId) async {
    final existing =
        await (db.select(db.playlistTracks)..where(
              (pt) =>
                  pt.playlistId.equals(playlistId) & pt.trackId.equals(trackId),
            ))
            .getSingleOrNull();
    if (existing != null) return;

    final countExpr = db.playlistTracks.id.count();
    final countQuery = db.selectOnly(db.playlistTracks)
      ..addColumns([countExpr])
      ..where(db.playlistTracks.playlistId.equals(playlistId));
    final countRow = await countQuery.getSingle();
    final position = countRow.read(countExpr) ?? 0;

    await db
        .into(db.playlistTracks)
        .insert(
          PlaylistTracksCompanion.insert(
            playlistId: playlistId,
            trackId: trackId,
            position: position,
          ),
        );
  }

  /// Appends all of [trackIds] to the end of the playlist in one
  /// transaction, preserving order and skipping any already present.
  Future<void> addTracksToPlaylist(int playlistId, List<int> trackIds) async {
    await db.transaction(() async {
      final countExpr = db.playlistTracks.id.count();
      final countQuery = db.selectOnly(db.playlistTracks)
        ..addColumns([countExpr])
        ..where(db.playlistTracks.playlistId.equals(playlistId));
      final countRow = await countQuery.getSingle();
      var position = countRow.read(countExpr) ?? 0;

      for (final trackId in trackIds) {
        final existing =
            await (db.select(db.playlistTracks)..where(
                  (pt) =>
                      pt.playlistId.equals(playlistId) &
                      pt.trackId.equals(trackId),
                ))
                .getSingleOrNull();
        if (existing != null) continue;

        await db
            .into(db.playlistTracks)
            .insert(
              PlaylistTracksCompanion.insert(
                playlistId: playlistId,
                trackId: trackId,
                position: position,
              ),
            );
        position++;
      }
    });
  }

  /// Rewrites every track's position in the playlist to match
  /// [orderedTrackIds] — used after a drag-to-reorder.
  Future<void> setPlaylistTrackOrder(
    int playlistId,
    List<int> orderedTrackIds,
  ) async {
    await db.transaction(() async {
      for (var i = 0; i < orderedTrackIds.length; i++) {
        await (db.update(db.playlistTracks)..where(
              (pt) =>
                  pt.playlistId.equals(playlistId) &
                  pt.trackId.equals(orderedTrackIds[i]),
            ))
            .write(PlaylistTracksCompanion(position: Value(i)));
      }
    });
  }

  Future<void> removeTrackFromPlaylist(int playlistId, int trackId) {
    return (db.delete(db.playlistTracks)..where(
          (pt) => pt.playlistId.equals(playlistId) & pt.trackId.equals(trackId),
        ))
        .go();
  }

  Stream<List<Track>> watchPlaylistTracks(int playlistId) {
    final query =
        db.select(db.playlistTracks).join([
            innerJoin(
              db.tracks,
              db.tracks.id.equalsExp(db.playlistTracks.trackId),
            ),
          ])
          ..where(db.playlistTracks.playlistId.equals(playlistId))
          ..orderBy([OrderingTerm(expression: db.playlistTracks.position)]);
    return query.watch().map(
      (rows) => rows.map((row) => row.readTable(db.tracks)).toList(),
    );
  }
}
