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
      expect(tracks.first.albumId, isNull);
      expect(tracks.first.albumArtist, isNull);
      expect(tracks.first.year, isNull);
      expect(await db.select(db.albums).get(), isEmpty);

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

  /// Same idea as [seedV4Database], for a v5 install: tracks already have
  /// genre/track_number (added in the v4->v5 step) but no album columns and
  /// no albums table yet.
  void seedV5Database(String path) {
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
          lyrics TEXT NULL,
          genre TEXT NULL,
          track_number INTEGER NULL
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
        'INSERT INTO tracks (file_path, title, artist, album, format, date_added, genre, track_number, album_art_path) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);',
        [
          '/music/kept.flac',
          'Kept Song',
          'Kept Artist',
          'Kept Album',
          'flac',
          DateTime(2025, 6, 1).millisecondsSinceEpoch,
          'Jazz',
          4,
          '/cache/1.art',
        ],
      );
      db.execute('INSERT INTO playlists (name, date_created) VALUES (?, ?);', [
        'Mine',
        DateTime(2025, 6, 1).millisecondsSinceEpoch,
      ]);
      db.execute(
        'INSERT INTO playlist_tracks (playlist_id, track_id, position) VALUES (1, 1, 0);',
      );
      db.execute('PRAGMA user_version = 5;');
    } finally {
      db.close();
    }
  }

  test(
    'migrating from v5 to v6 adds albums and keeps every existing value',
    () async {
      final dbPath = p.join(tempDir.path, 'migration_v5.sqlite');
      seedV5Database(dbPath);

      final db = AppDatabase.forTesting(NativeDatabase(File(dbPath)));
      addTearDown(db.close);

      final track = await db.select(db.tracks).getSingle();
      expect(track.title, 'Kept Song');
      expect(track.artist, 'Kept Artist');
      expect(
        track.album,
        'Kept Album',
        reason: 'the raw album tag text must survive',
      );
      expect(
        track.genre,
        'Jazz',
        reason: 'columns from the previous migration survive too',
      );
      expect(track.trackNumber, 4);
      expect(track.albumArtPath, '/cache/1.art');
      expect(track.albumId, isNull, reason: 'not grouped until re-scanned');
      expect(track.albumArtist, isNull);
      expect(track.year, isNull);

      expect(await db.select(db.albums).get(), isEmpty);
      expect((await db.select(db.playlists).get()).length, 1);
      expect((await db.select(db.playlistTracks).get()).length, 1);
    },
  );

  test(
    'after migrating to v6 an album can be created and a track linked to it',
    () async {
      final dbPath = p.join(tempDir.path, 'migration_v5_link.sqlite');
      seedV5Database(dbPath);
      final db = AppDatabase.forTesting(NativeDatabase(File(dbPath)));
      addTearDown(db.close);

      final albumId = await db
          .into(db.albums)
          .insert(
            AlbumsCompanion.insert(
              groupKey: 'kept album\u001fkept artist',
              title: 'Kept Album',
              artist: const Value('Kept Artist'),
            ),
          );
      await (db.update(db.tracks)..where((t) => t.id.equals(1))).write(
        TracksCompanion(
          albumId: Value(albumId),
          albumArtist: const Value('Kept Artist'),
          year: const Value(2020),
        ),
      );

      final joined = await (db.select(
        db.tracks,
      )..where((t) => t.albumId.equals(albumId))).getSingle();
      expect(joined.year, 2020);
      expect(joined.albumArtist, 'Kept Artist');
    },
  );

  test(
    'albums.groupKey is unique so the same album cannot be created twice',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      await db
          .into(db.albums)
          .insert(AlbumsCompanion.insert(groupKey: 'k', title: 'A'));

      expect(
        () => db
            .into(db.albums)
            .insert(AlbumsCompanion.insert(groupKey: 'k', title: 'B')),
        throwsA(anything),
      );
    },
  );

  /// Same idea again, for a v6 install: albums exist and tracks are already
  /// grouped, but there's no synced-lyrics column yet.
  void seedV6Database(String path) {
    final db = sqlite3.sqlite3.open(path);
    try {
      db.execute('''
        CREATE TABLE albums (
          id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
          group_key TEXT NOT NULL UNIQUE,
          title TEXT NOT NULL,
          artist TEXT NULL,
          year INTEGER NULL,
          cover_art_path TEXT NULL
        );
      ''');
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
          lyrics TEXT NULL,
          genre TEXT NULL,
          track_number INTEGER NULL,
          album_id INTEGER NULL REFERENCES albums (id),
          album_artist TEXT NULL,
          year INTEGER NULL
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
        'INSERT INTO albums (group_key, title, artist, year) VALUES (?, ?, ?, ?);',
        ['kept album\u001fkept artist', 'Kept Album', 'Kept Artist', 2020],
      );
      db.execute(
        'INSERT INTO tracks (file_path, title, artist, album, format, date_added, album_id, album_artist, year) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);',
        [
          '/music/kept.flac',
          'Kept Song',
          'Kept Artist',
          'Kept Album',
          'flac',
          DateTime(2025, 6, 1).millisecondsSinceEpoch,
          1,
          'Kept Artist',
          2020,
        ],
      );
      db.execute('PRAGMA user_version = 6;');
    } finally {
      db.close();
    }
  }

  test(
    'migrating from v6 to v7 adds synced lyrics and keeps grouping intact',
    () async {
      final dbPath = p.join(tempDir.path, 'migration_v6.sqlite');
      seedV6Database(dbPath);

      final db = AppDatabase.forTesting(NativeDatabase(File(dbPath)));
      addTearDown(db.close);

      final track = await db.select(db.tracks).getSingle();
      expect(track.title, 'Kept Song');
      expect(track.albumArtist, 'Kept Artist');
      expect(track.year, 2020);
      expect(
        track.syncedLyrics,
        isNull,
        reason: 'new column defaults to null on pre-existing rows',
      );

      final album = await db.select(db.albums).getSingle();
      expect(album.title, 'Kept Album');
      expect(track.albumId, album.id);
    },
  );

  test(
    'synced lyrics are writable and queryable after migrating to v7',
    () async {
      final dbPath = p.join(tempDir.path, 'migration_v6_lyrics.sqlite');
      seedV6Database(dbPath);
      final db = AppDatabase.forTesting(NativeDatabase(File(dbPath)));
      addTearDown(db.close);

      final track = await db.select(db.tracks).getSingle();
      await (db.update(db.tracks)..where((t) => t.id.equals(track.id))).write(
        const TracksCompanion(syncedLyrics: Value('[00:01.00]Hello')),
      );

      final updated = await db.select(db.tracks).getSingle();
      expect(updated.syncedLyrics, '[00:01.00]Hello');
    },
  );

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
