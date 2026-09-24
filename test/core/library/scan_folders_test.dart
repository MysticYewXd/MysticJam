import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:music_player/core/library/database.dart';
import 'package:music_player/core/library/library_repository.dart';
import 'package:music_player/core/library/library_scanner.dart';

import '../../helpers/flac_fixture.dart';

class _FakePathProvider extends PathProviderPlatform {
  final String path;
  _FakePathProvider(this.path);
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory root;
  late Directory support;
  late AppDatabase db;
  late LibraryScanner scanner;

  setUp(() {
    root = Directory.systemTemp.createTempSync('mysticjam_folders_');
    support = Directory.systemTemp.createTempSync('mysticjam_folders_sup_');
    PathProviderPlatform.instance = _FakePathProvider(support.path);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    scanner = LibraryScanner(LibraryRepository(db));
  });

  tearDown(() async {
    await db.close();
    root.deleteSync(recursive: true);
    support.deleteSync(recursive: true);
  });

  String song(String relative) {
    final f = File('${root.path}/$relative')
      ..createSync(recursive: true)
      ..writeAsBytesSync(buildFlac(['TITLE=Song']));
    return f.path;
  }

  test(
    'songs added to an already-scanned folder are found; known ones are not re-added',
    () async {
      song('Music/Old Album/one.flac');
      song('Music/Old Album/two.flac');
      await scanner.scanDirectory('${root.path}/Music');

      song('Music/New Album/three.flac');
      song('Music/New Album/four.flac');
      final result = await scanner.scanFolders(['${root.path}/Music']);

      expect(result.addedCount, 2);
      expect((await db.select(db.tracks).get()).length, 4);
    },
  );

  test(
    'a new album under the outer folder is found even when a nested folder is also remembered',
    () async {
      song('Flac-Songs/BULLY/a.flac');
      await scanner.scanDirectory('${root.path}/Flac-Songs');
      song('Flac-Songs/Brand New/b.flac');

      final result = await scanner.scanFolders([
        '${root.path}/Flac-Songs/BULLY',
        '${root.path}/Flac-Songs',
      ]);

      expect(result.addedCount, 1);
    },
  );

  test('scanning again with nothing new adds nothing', () async {
    song('M/a.flac');
    await scanner.scanFolders(['${root.path}/M']);
    final second = await scanner.scanFolders(['${root.path}/M']);
    expect(second.addedCount, 0);
    expect(second.wasCancelled, isFalse);
  });

  test(
    'a remembered folder that no longer exists is ignored, others still scan',
    () async {
      song('Here/a.flac');
      final result = await scanner.scanFolders([
        '${root.path}/Unplugged Drive',
        '${root.path}/Here',
      ]);
      expect(result.addedCount, 1);
    },
  );

  test('no remembered folders is a no-op', () async {
    final result = await scanner.scanFolders(const []);
    expect(result.addedCount, 0);
    expect(result.allPaths, isEmpty);
  });

  test('a cancelled scan stops and reports it', () async {
    song('M/a.flac');
    final token = ScanCancellationToken()..cancel();
    final result = await scanner.scanFolders([
      '${root.path}/M',
    ], cancellationToken: token);
    expect(result.wasCancelled, isTrue);
    expect(result.addedCount, 0);
  });

  group('outermostFolders', () {
    test(
      'removes nested folders and duplicates, ignoring trailing slashes',
      () {
        expect(
          outermostFolders(['/m/a/b', '/m/a/', '/m/a', '/m/c']),
          unorderedEquals(['/m/a', '/m/c']),
        );
      },
    );

    test('folders that only share a name prefix are both kept', () {
      expect(
        outermostFolders(['/music/rock', '/music/rock-classics']),
        unorderedEquals(['/music/rock', '/music/rock-classics']),
      );
    });

    test(
      'empty in, empty out',
      () => expect(outermostFolders(const []), isEmpty),
    );
  });
}
