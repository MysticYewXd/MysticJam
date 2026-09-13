import 'dart:io';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import 'package:music_player/core/library/database.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('mysticjam_migration_test_');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  /// Hand-writes a database matching exactly what schemaVersion 4 produced
  /// (see database.dart's migration history: playlists/playlistTracks from
  /// <2, albumArtPath from <3, lyrics from <4 — no genre/trackNumber yet),
  /// then seeds one track row and stamps PRAGMA user_version = 4, exactly
  /// as a real v4 install's database would look on disk.
  void seedV4Database(String path) {
    final db = sqlite3.sqlite3.open(path);
    try {
      db.execute('''
        CREATE TABLE tracks (
          id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
          file_path TEXT NOT NULL UNIQUE,
          title TEXT NOT NULL,
          artist TEXT NULL,
          album TEXT NULL,
          duration_ms INTEGER NULL,
          format TEXT NOT NULL,
          date_added INTEGER NOT NULL,
          album_art_path TEXT NULL,
          lyrics TEXT NULL
        );
      ''');
      db.execute('''
        CREATE TABLE playlists (
          id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          date_created INTEGER NOT NULL
        );
      ''');
      db.execute('''
        CREATE TABLE playlist_tracks (
          id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
          playlist_id INTEGER NOT NULL REFERENCES playlists (id),
          track_id INTEGER NOT NULL REFERENCES tracks (id),
          position INTEGER NOT NULL
        );
      ''');
      db.execute(
        'INSERT INTO tracks (file_path, title, artist, album, format, date_added, lyrics) '
        'VALUES (?, ?, ?, ?, ?, ?, ?);',
        [
          '/music/old-song.mp3',
          'Old Song',
          'Old Artist',
          'Old Album',
          'mp3',
          DateTime(2025, 1, 1).millisecondsSinceEpoch,
          'la la la',
        ],
      );
      db.execute('INSERT INTO playlists (name, date_created) VALUES (?, ?);', [
        'Old Playlist',
        DateTime(2025, 1, 1).millisecondsSinceEpoch,
      ]);
      db.execute(
        'INSERT INTO playlist_tracks (playlist_id, track_id, position) VALUES (1, 1, 0);',
      );
      db.execute('PRAGMA user_version = 4;');
    } finally {
      db.close();
    }
  }

  test(
    'migrating from v4 to v5 adds genre/trackNumber and preserves existing data',
    () async {
      final dbPath = p.join(tempDir.path, 'migration.sqlite');
      seedV4Database(dbPath);

      // Opening via the real AppDatabase triggers Drift's actual
      // onUpgrade(4, 5) path against this file — not a synthetic substitute.
      final db = AppDatabase.forTesting(NativeDatabase(File(dbPath)));
      addTearDown(db.close);

      final tracks = await db.select(db.tracks).get();
      expect(
        tracks.length,
        1,
        reason: 'the pre-existing track must survive the migration',
      );
      expect(tracks.first.title, 'Old Song');
      expect(tracks.first.artist, 'Old Artist');
      expect(tracks.first.album, 'Old Album');
      expect(
        tracks.first.lyrics,
        'la la la',
        reason: 'a column added in an earlier migration must also survive',
      );
      expect(
        tracks.first.genre,
        isNull,
        reason: 'new column defaults to null on pre-existing rows',
      );
      expect(tracks.first.trackNumber, isNull);

      final playlists = await db.select(db.playlists).get();
      expect(
        playlists.length,
        1,
        reason: 'unrelated tables must be untouched by this migration',
      );
      final playlistTracks = await db.select(db.playlistTracks).get();
      expect(playlistTracks.length, 1);
    },
  );

  test('the new columns are writable and queryable after migration', () async {
    final dbPath = p.join(tempDir.path, 'migration2.sqlite');
    seedV4Database(dbPath);

    final db = AppDatabase.forTesting(NativeDatabase(File(dbPath)));
    addTearDown(db.close);

    final track = await db.select(db.tracks).getSingle();
    await (db.update(db.tracks)..where((t) => t.id.equals(track.id))).write(
      const TracksCompanion(genre: Value('Rock'), trackNumber: Value(3)),
    );

    final updated = await db.select(db.tracks).getSingle();
    expect(updated.genre, 'Rock');
    expect(updated.trackNumber, 3);
  });

  test(
    'a fresh (onCreate) database already has the v5 columns available',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      final id = await db
          .into(db.tracks)
          .insert(
            TracksCompanion.insert(
              filePath: '/music/new-song.mp3',
              title: 'New Song',
              format: 'flac',
              genre: const Value('Jazz'),
              trackNumber: const Value(7),
            ),
          );

      final track = await (db.select(
        db.tracks,
      )..where((t) => t.id.equals(id))).getSingle();
      expect(track.genre, 'Jazz');
      expect(track.trackNumber, 7);
    },
  );
}
