import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:music_player/core/library/album_grouping.dart';
import 'package:music_player/core/library/database.dart';
import 'package:music_player/core/library/library_repository.dart';
import 'package:music_player/core/library/library_scanner.dart';
import 'package:music_player/core/library/metadata/flac_metadata_reader.dart';

import '../../helpers/flac_fixture.dart';

class _FakePathProviderPlatform extends PathProviderPlatform {
  final String path;
  _FakePathProviderPlatform(this.path);
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory musicDir;
  late Directory supportDir;

  setUp(() {
    musicDir = Directory.systemTemp.createTempSync('mysticjam_albums_music_');
    supportDir = Directory.systemTemp.createTempSync(
      'mysticjam_albums_support_',
    );
    PathProviderPlatform.instance = _FakePathProviderPlatform(supportDir.path);
  });

  tearDown(() {
    musicDir.deleteSync(recursive: true);
    supportDir.deleteSync(recursive: true);
  });

  String write(String name, List<String> comments) {
    final f = File('${musicDir.path}/$name')
      ..writeAsBytesSync(buildFlac(comments));
    return f.path;
  }

  group('reading the new tags', () {
    test(
      'FLAC: album artist and year are extracted (DATE as full ISO date)',
      () async {
        final path = write('a.flac', [
          'TITLE=Song',
          'ALBUM=Record',
          'ALBUMARTIST=Various Artists',
          'DATE=2019-05-03',
        ]);

        final meta = await readFlacMetadata(path);

        expect(meta.albumArtist, 'Various Artists');
        expect(meta.year, 2019);
      },
    );

    test(
      'FLAC: accepts the "ALBUM ARTIST" spelling and a YEAR field',
      () async {
        final path = write('a.flac', ['ALBUM ARTIST=Someone', 'YEAR=1984']);

        final meta = await readFlacMetadata(path);

        expect(meta.albumArtist, 'Someone');
        expect(meta.year, 1984);
      },
    );

    test('FLAC: absent tags stay null rather than empty/zero', () async {
      final path = write('a.flac', ['TITLE=Just a title']);

      final meta = await readFlacMetadata(path);

      expect(meta.albumArtist, isNull);
      expect(meta.year, isNull);
    });
  });

  group('scanner assigns albums from tags, not folders', () {
    late AppDatabase db;
    late LibraryRepository repo;
    late LibraryScanner scanner;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repo = LibraryRepository(db);
      scanner = LibraryScanner(repo);
    });

    tearDown(() => db.close());

    Future<Track> trackAt(String path) => (db.select(
      db.tracks,
    )..where((t) => t.filePath.equals(path))).getSingle();

    test('mixed albums sharing ONE folder are separated correctly', () async {
      final a1 = write('a1.flac', [
        'TITLE=One',
        'ALBUM=Greatest Hits',
        'ALBUMARTIST=Artist A',
        'DATE=2001',
      ]);
      final b1 = write('b1.flac', [
        'TITLE=Two',
        'ALBUM=Greatest Hits',
        'ALBUMARTIST=Artist B',
        'DATE=1999',
      ]);
      // Same album as a1 despite different casing / stray whitespace.
      final a2 = write('a2.flac', [
        'TITLE=Three',
        'ALBUM=greatest  hits',
        'ALBUMARTIST=artist a ',
      ]);
      final other = write('o1.flac', [
        'TITLE=Four',
        'ALBUM=Other Record',
        'ARTIST=Solo Act',
      ]);

      final result = await scanner.scanDirectory(musicDir.path);

      expect(result.addedCount, 4);
      final ta1 = await trackAt(a1);
      final tb1 = await trackAt(b1);
      final ta2 = await trackAt(a2);
      final to = await trackAt(other);

      expect(ta1.albumId, isNotNull);
      expect(
        ta1.albumId,
        ta2.albumId,
        reason: 'same album + album artist merge',
      );
      expect(
        ta1.albumId,
        isNot(tb1.albumId),
        reason: 'same title, different album artist: separate',
      );
      expect(to.albumId, isNot(ta1.albumId));

      final albums = await db.select(db.albums).get();
      expect(albums.length, 3);
      final a = albums.firstWhere((x) => x.id == ta1.albumId);
      expect(a.title, 'Greatest Hits');
      expect(a.artist, 'Artist A');
      expect(a.year, 2001, reason: 'album year comes from its tracks');
      final other0 = albums.firstWhere((x) => x.id == to.albumId);
      expect(
        other0.artist,
        'Solo Act',
        reason: 'falls back to the track artist',
      );
    });

    test('one album spread across two folders stays one album', () async {
      final sub = Directory('${musicDir.path}/disc2')..createSync();
      final p1 = write('t1.flac', ['ALBUM=Double Album', 'ALBUMARTIST=Band']);
      final p2 = File('${sub.path}/t2.flac')
        ..writeAsBytesSync(
          buildFlac(['ALBUM=Double Album', 'ALBUMARTIST=Band']),
        );

      await scanner.scanDirectory(musicDir.path);

      expect((await trackAt(p1)).albumId, (await trackAt(p2.path)).albumId);
      expect((await db.select(db.albums).get()).length, 1);
    });

    test(
      'missing or blank album tags fall into the single Unknown Album bucket',
      () async {
        final untagged = write('u1.flac', ['TITLE=No album tag']);
        final blank = write('u2.flac', [
          'TITLE=Blank',
          'ALBUM=   ',
          'ALBUMARTIST=Someone',
        ]);
        final garbage = File('${musicDir.path}/broken.mp3')
          ..writeAsBytesSync(List.filled(64, 7));

        await scanner.scanDirectory(musicDir.path);

        final ids = {
          (await trackAt(untagged)).albumId,
          (await trackAt(blank)).albumId,
          (await trackAt(garbage.path)).albumId,
        };
        expect(ids.length, 1, reason: 'all three land in one shared bucket');
        final unknown = await (db.select(
          db.albums,
        )..where((a) => a.id.equals(ids.single!))).getSingle();
        expect(unknown.title, unknownAlbumTitle);
        expect(unknown.groupKey, unknownAlbumGroupKey);
        expect(unknown.artist, isNull);
      },
    );

    test(
      'tag values are kept on the track so it can be re-grouped later',
      () async {
        final path = write('a.flac', [
          'ALBUM=Record',
          'ALBUMARTIST=Band',
          'DATE=2010-01-01',
        ]);

        await scanner.scanDirectory(musicDir.path);

        final t = await trackAt(path);
        expect(t.album, 'Record');
        expect(t.albumArtist, 'Band');
        expect(t.year, 2010);
      },
    );

    test('re-scanning does not create duplicate albums', () async {
      write('a.flac', ['ALBUM=Record', 'ALBUMARTIST=Band']);
      await scanner.scanDirectory(musicDir.path);

      await scanner.refreshAllMetadata();
      await scanner.scanDirectory(musicDir.path);

      expect((await db.select(db.albums).get()).length, 1);
    });

    test(
      'album cover comes from the first track with art and is never replaced',
      () async {
        // Adjacent cover.jpg is the art source scanning falls back to.
        File('${musicDir.path}/cover.jpg').writeAsBytesSync([1, 2, 3, 4]);
        final p1 = write('t1.flac', ['ALBUM=Record', 'ALBUMARTIST=Band']);

        await scanner.scanDirectory(musicDir.path);

        final t = await trackAt(p1);
        final album = await (db.select(
          db.albums,
        )..where((a) => a.id.equals(t.albumId!))).getSingle();
        expect(album.coverArtPath, isNotNull);
        final firstCover = album.coverArtPath;

        await repo.setAlbumCoverIfMissing(album.id, '/some/other/path.art');
        final after = await (db.select(
          db.albums,
        )..where((a) => a.id.equals(album.id))).getSingle();
        expect(after.coverArtPath, firstCover);
      },
    );
  });
}
