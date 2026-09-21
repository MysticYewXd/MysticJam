import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:music_player/core/library/album_grouping.dart';
import 'package:music_player/core/library/database.dart';
import 'package:music_player/core/library/library_repository.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late LibraryRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = LibraryRepository(db);
  });

  tearDown(() => db.close());

  Future<int> addTrack({
    required String path,
    String title = 'Song',
    String? artist,
    String? album,
    String? albumArtist,
    int? year,
    String? albumArtPath,
  }) async {
    final albumKey = album == null
        ? null
        : await repo.findOrCreateAlbum(
            albumKeyFor(album: album, albumArtist: albumArtist, artist: artist),
            year: year,
          );
    return repo.upsertTrack(
      TracksCompanion.insert(
        filePath: path,
        title: title,
        artist: Value(artist),
        album: Value(album),
        format: 'flac',
        albumId: albumKey != null ? Value(albumKey) : const Value.absent(),
        albumArtist: Value(albumArtist),
        year: Value(year),
        albumArtPath: albumArtPath != null
            ? Value(albumArtPath)
            : const Value.absent(),
      ),
    );
  }

  group('watchAlbums', () {
    test('groups tracks by their album, one row per album', () async {
      final id = await addTrack(
        path: '/a.flac',
        album: 'Record',
        albumArtist: 'Band',
        year: 2020,
        albumArtPath: '/art/1.jpg',
      );
      await addTrack(path: '/b.flac', album: 'Record', albumArtist: 'Band');
      // Set the second track's albumId to the same album as the first.
      final firstTrack = await repo.getTrackById(id);
      await (db.update(db.tracks)..where((t) => t.filePath.equals('/b.flac')))
          .write(TracksCompanion(albumId: Value(firstTrack!.albumId)));

      final albums = await repo.watchAlbums().first;
      expect(albums, hasLength(1));
      expect(albums.single.title, 'Record');
      expect(albums.single.artist, 'Band');
      expect(albums.single.year, 2020);
      expect(albums.single.coverArtPath, '/art/1.jpg');
      expect(albums.single.tracks, hasLength(2));
    });

    test('sorted alphabetically by title', () async {
      await addTrack(path: '/z.flac', album: 'Zeta');
      await addTrack(path: '/a.flac', album: 'Alpha');

      final albums = await repo.watchAlbums().first;
      expect(albums.map((a) => a.title), ['Alpha', 'Zeta']);
    });

    test(
      'a track that briefly has no albumId is still shown, under -1',
      () async {
        await repo.upsertTrack(
          TracksCompanion.insert(
            filePath: '/orphan.flac',
            title: 'Orphan',
            format: 'flac',
          ),
        );
        final albums = await repo.watchAlbums().first;
        expect(albums, hasLength(1));
        expect(albums.single.id, -1);
        expect(albums.single.tracks.single.filePath, '/orphan.flac');
      },
    );
  });

  group('backfillAlbumGroups', () {
    test(
      'regroups tracks left with a null albumId from their stored tags',
      () async {
        await repo.upsertTrack(
          TracksCompanion.insert(
            filePath: '/old.flac',
            title: 'Old Song',
            artist: const Value('Artist'),
            album: const Value('Old Album'),
            format: 'flac',
          ),
        );

        await repo.backfillAlbumGroups();

        final track = await (db.select(
          db.tracks,
        )..where((t) => t.filePath.equals('/old.flac'))).getSingle();
        expect(track.albumId, isNotNull);

        final album = await (db.select(
          db.albums,
        )..where((a) => a.id.equals(track.albumId!))).getSingle();
        expect(album.title, 'Old Album');
        expect(album.artist, 'Artist');
      },
    );

    test(
      'tracks with no album tag land in the shared Unknown Album bucket',
      () async {
        await repo.upsertTrack(
          TracksCompanion.insert(
            filePath: '/untagged.flac',
            title: 'No Tags',
            format: 'flac',
          ),
        );
        await repo.backfillAlbumGroups();

        final albums = await repo.watchAlbums().first;
        expect(albums.single.title, unknownAlbumTitle);
      },
    );

    test('is a no-op once every track already has an albumId', () async {
      await addTrack(path: '/a.flac', album: 'Record');
      final before = await db.select(db.albums).get();

      await repo.backfillAlbumGroups();

      final after = await db.select(db.albums).get();
      expect(after.length, before.length);
    });

    test(
      'two tracks sharing tags backfill into the same album, not two',
      () async {
        await repo.upsertTrack(
          TracksCompanion.insert(
            filePath: '/1.flac',
            title: 'One',
            album: const Value('Shared'),
            albumArtist: const Value('Band'),
            format: 'flac',
          ),
        );
        await repo.upsertTrack(
          TracksCompanion.insert(
            filePath: '/2.flac',
            title: 'Two',
            album: const Value('Shared'),
            albumArtist: const Value('Band'),
            format: 'flac',
          ),
        );

        await repo.backfillAlbumGroups();

        final albums = await db.select(db.albums).get();
        expect(albums, hasLength(1));
      },
    );
  });

  group('deleteTrack orphan cleanup', () {
    test('deletes the album once its last track is gone', () async {
      final id = await addTrack(path: '/only.flac', album: 'Solo');
      final track = await repo.getTrackById(id);
      final albumId = track!.albumId!;

      await repo.deleteTrack(id);

      final album = await (db.select(
        db.albums,
      )..where((a) => a.id.equals(albumId))).getSingleOrNull();
      expect(album, isNull);
    });

    test('keeps the album while another track still references it', () async {
      final id1 = await addTrack(path: '/1.flac', album: 'Duo');
      final track1 = await repo.getTrackById(id1);
      final albumId = track1!.albumId!;
      await repo.upsertTrack(
        TracksCompanion.insert(
          filePath: '/2.flac',
          title: 'Two',
          format: 'flac',
          albumId: Value(albumId),
        ),
      );

      await repo.deleteTrack(id1);

      final album = await (db.select(
        db.albums,
      )..where((a) => a.id.equals(albumId))).getSingleOrNull();
      expect(album, isNotNull);
    });

    test('never deletes the shared Unknown Album bucket', () async {
      final id = await repo.upsertTrack(
        TracksCompanion.insert(
          filePath: '/untagged.flac',
          title: 'No Tags',
          format: 'flac',
        ),
      );
      await repo.backfillAlbumGroups();
      final track = await repo.getTrackById(id);

      await repo.deleteTrack(id);

      final album = await (db.select(
        db.albums,
      )..where((a) => a.id.equals(track!.albumId!))).getSingleOrNull();
      expect(album, isNotNull);
      expect(album!.groupKey, unknownAlbumGroupKey);
    });
  });
}
