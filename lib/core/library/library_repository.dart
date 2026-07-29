import 'package:drift/drift.dart';

import 'database.dart';

/// Thin query layer over [AppDatabase] — the rest of the app talks to the
/// library through this, never through raw Drift queries.
class LibraryRepository {
  final AppDatabase db;

  LibraryRepository(this.db);

  Stream<List<Track>> watchAllTracks() {
    return (db.select(db.tracks)
          ..orderBy([(t) => OrderingTerm(expression: t.title)]))
        .watch();
  }

  Future<bool> trackExists(String filePath) async {
    final row = await (db.select(db.tracks)
          ..where((t) => t.filePath.equals(filePath)))
        .getSingleOrNull();
    return row != null;
  }

  Future<void> upsertTrack(TracksCompanion entry) {
    return db.into(db.tracks).insertOnConflictUpdate(entry);
  }

  Future<void> deleteTrack(int id) {
    return (db.delete(db.tracks)..where((t) => t.id.equals(id))).go();
  }

  Future<void> clearAll() {
    return db.delete(db.tracks).go();
  }

  Stream<List<Playlist>> watchPlaylists() {
    return (db.select(db.playlists)
          ..orderBy([(p) => OrderingTerm(expression: p.name)]))
        .watch();
  }

  Future<int> createPlaylist(String name) {
    return db.into(db.playlists).insert(PlaylistsCompanion.insert(name: name));
  }

  Future<void> deletePlaylist(int id) async {
    await (db.delete(db.playlistTracks)..where((pt) => pt.playlistId.equals(id))).go();
    await (db.delete(db.playlists)..where((p) => p.id.equals(id))).go();
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
