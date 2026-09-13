import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'library_model.dart';

part 'database.g.dart';

@DriftDatabase(tables: [Tracks, Playlists, PlaylistTracks])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.createTable(playlists);
        await m.createTable(playlistTracks);
      }
      if (from < 3) {
        await m.addColumn(tracks, tracks.albumArtPath);
      }
      if (from < 4) {
        await m.addColumn(tracks, tracks.lyrics);
      }
      if (from < 5) {
        // Both nullable, both default to NULL on the existing rows —
        // preserves every already-indexed track exactly as it was;
        // genre/trackNumber just read as "unknown" until the next
        // "Refresh Metadata" re-parses each file and fills them in.
        await m.addColumn(tracks, tracks.genre);
        await m.addColumn(tracks, tracks.trackNumber);
      }
    },
  );

  static QueryExecutor _openConnection() {
    return LazyDatabase(() async {
      final dir = await getApplicationSupportDirectory();
      final file = File(p.join(dir.path, 'music_player.sqlite'));
      return NativeDatabase.createInBackground(file);
    });
  }
}
