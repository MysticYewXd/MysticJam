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
  int get schemaVersion => 4;

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
