import 'package:drift/drift.dart';

import 'database.dart';

/// Thin query layer over [AppDatabase] — the rest of the app talks to the
/// library through this, never through raw Drift queries.
class LibraryRepository {
  final AppDatabase db;

  LibraryRepository(this.db);

  /// Sorted by artist then title, so the library reads as grouped-by-artist
  /// rather than one flat alphabetical-by-title list with every artist
  /// interleaved.
  Stream<List<Track>> watchAllTracks() {
    return (db.select(db.tracks)
          ..orderBy([
            (t) => OrderingTerm(expression: t.artist),
            (t) => OrderingTerm(expression: t.title),
          ]))
        .watch();
  }

  Future<bool> trackExists(String filePath) async {
    final row = await (db.select(db.tracks)
          ..where((t) => t.filePath.equals(filePath)))
        .getSingleOrNull();
    return row != null;
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
    final rows = await (db.select(db.tracks)..where((t) => t.filePath.isIn(filePaths))).get();
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
    final track = await db.into(db.tracks).insertReturning(
          entry,
          onConflict: DoUpdate((old) => entry, target: [db.tracks.filePath]),
        );
    return track.id;
  }

  Future<void> setAlbumArtPath(int id, String path) {
    return (db.update(db.tracks)..where((t) => t.id.equals(id)))
        .write(TracksCompanion(albumArtPath: Value(path)));
  }

  /// Called from PlaybackController the first time a track's real duration
  /// becomes known from actual playback — for formats whose tag reader
  /// can't get duration essentially for free (unlike FLAC's STREAMINFO),
  /// this is how they end up with one at all, without an expensive
  /// dedicated probe-every-file scan step.
  Future<void> setTrackDuration(int id, int durationMs) {
    return (db.update(db.tracks)..where((t) => t.id.equals(id)))
        .write(TracksCompanion(durationMs: Value(durationMs)));
  }

  Future<void> deleteTrack(int id) async {
    // Clean up any playlist memberships too, or they'd be orphaned rows
    // pointing at a track that no longer exists.
    await (db.delete(db.playlistTracks)..where((pt) => pt.trackId.equals(id))).go();
    await (db.delete(db.tracks)..where((t) => t.id.equals(id))).go();
  }

  Future<void> deleteTrackByPath(String filePath) async {
    final row = await (db.select(db.tracks)..where((t) => t.filePath.equals(filePath))).getSingleOrNull();
    if (row == null) return;
    await deleteTrack(row.id);
  }

  /// Which playlists [trackId] currently belongs to — captured before a
  /// delete so Undo can put the track back where it was.
  Future<List<int>> getPlaylistIdsForTrack(int trackId) async {
    final rows = await (db.select(db.playlistTracks)..where((pt) => pt.trackId.equals(trackId))).get();
    return rows.map((pt) => pt.playlistId).toList();
  }

  /// Re-inserts a track (a fresh row/id — its old id isn't reused) and puts
  /// it back in [playlistIds], for Undo after a deletion. Playlist entries
  /// go to the end of each playlist rather than their exact prior position,
  /// which is a reasonable trade for how much simpler it keeps this.
  Future<void> restoreTrack(Track track, List<int> playlistIds) async {
    final newId = await upsertTrack(TracksCompanion.insert(
      filePath: track.filePath,
      title: track.title,
      artist: Value(track.artist),
      album: Value(track.album),
      format: track.format,
      durationMs: track.durationMs != null ? Value(track.durationMs) : const Value.absent(),
      albumArtPath: track.albumArtPath != null ? Value(track.albumArtPath) : const Value.absent(),
      lyrics: track.lyrics != null ? Value(track.lyrics) : const Value.absent(),
    ));
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
  }

  Stream<List<Playlist>> watchPlaylists() {
    return (db.select(db.playlists)
          ..orderBy([(p) => OrderingTerm(expression: p.name)]))
        .watch();
  }

  Future<int> createPlaylist(String name) {
    return db.into(db.playlists).insert(PlaylistsCompanion.insert(name: name));
  }

  Future<void> renamePlaylist(int id, String name) {
    return (db.update(db.playlists)..where((p) => p.id.equals(id)))
        .write(PlaylistsCompanion(name: Value(name)));
  }

  Future<void> deletePlaylist(int id) async {
    await (db.delete(db.playlistTracks)..where((pt) => pt.playlistId.equals(id))).go();
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
    final existing = await (db.select(db.playlistTracks)
          ..where((pt) => pt.playlistId.equals(playlistId) & pt.trackId.equals(trackId)))
        .getSingleOrNull();
    if (existing != null) return;

    final countExpr = db.playlistTracks.id.count();
    final countQuery = db.selectOnly(db.playlistTracks)
      ..addColumns([countExpr])
      ..where(db.playlistTracks.playlistId.equals(playlistId));
    final countRow = await countQuery.getSingle();
    final position = countRow.read(countExpr) ?? 0;

    await db.into(db.playlistTracks).insert(PlaylistTracksCompanion.insert(
          playlistId: playlistId,
          trackId: trackId,
          position: position,
        ));
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
        final existing = await (db.select(db.playlistTracks)
              ..where((pt) => pt.playlistId.equals(playlistId) & pt.trackId.equals(trackId)))
            .getSingleOrNull();
        if (existing != null) continue;

        await db.into(db.playlistTracks).insert(PlaylistTracksCompanion.insert(
              playlistId: playlistId,
              trackId: trackId,
              position: position,
            ));
        position++;
      }
    });
  }

  /// Rewrites every track's position in the playlist to match
  /// [orderedTrackIds] — used after a drag-to-reorder.
  Future<void> setPlaylistTrackOrder(int playlistId, List<int> orderedTrackIds) async {
    await db.transaction(() async {
      for (var i = 0; i < orderedTrackIds.length; i++) {
        await (db.update(db.playlistTracks)
              ..where((pt) => pt.playlistId.equals(playlistId) & pt.trackId.equals(orderedTrackIds[i])))
            .write(PlaylistTracksCompanion(position: Value(i)));
      }
    });
  }

  Future<void> removeTrackFromPlaylist(int playlistId, int trackId) {
    return (db.delete(db.playlistTracks)
          ..where((pt) => pt.playlistId.equals(playlistId) & pt.trackId.equals(trackId)))
        .go();
  }

  Stream<List<Track>> watchPlaylistTracks(int playlistId) {
    final query = db.select(db.playlistTracks).join([
      innerJoin(db.tracks, db.tracks.id.equalsExp(db.playlistTracks.trackId)),
    ])
      ..where(db.playlistTracks.playlistId.equals(playlistId))
      ..orderBy([OrderingTerm(expression: db.playlistTracks.position)]);
    return query.watch().map((rows) => rows.map((row) => row.readTable(db.tracks)).toList());
  }
}
