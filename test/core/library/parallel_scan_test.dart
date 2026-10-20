import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:music_player/core/library/database.dart';
import 'package:music_player/core/library/library_repository.dart';
import 'package:music_player/core/library/library_scanner.dart';
import 'package:music_player/core/library/track_file_reader.dart';

import '../../helpers/flac_fixture.dart';
import '../../helpers/rust_lib.dart';

class _SupportDir extends PathProviderPlatform {
  final String path;
  _SupportDir(this.path);

  @override
  Future<String?> getApplicationSupportPath() async => path;
}

/// Tiny ffmpeg-tagged files (rust/tests/fixtures/make_fixtures.sh).
String _fixture(String name) =>
    p.join(Directory.current.path, 'rust', 'tests', 'fixtures', name);

const _formats = ['flac', 'mp3', 'm4a', 'mp4', 'ogg', 'opus', 'wma'];

void main() {
  setUpAll(loadRustLib);

  late Directory music;
  late Directory support;
  late AppDatabase db;
  late LibraryScanner scanner;

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    music = Directory.systemTemp.createTempSync('mysticjam_par_music_');
    support = Directory.systemTemp.createTempSync('mysticjam_par_app_');
    PathProviderPlatform.instance = _SupportDir(support.path);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    scanner = LibraryScanner(LibraryRepository(db));
  });

  tearDown(() async {
    await db.close();
    for (final d in [music, support]) {
      if (d.existsSync()) d.deleteSync(recursive: true);
    }
  });

  /// One copy of each format's fixture, in its own folder.
  List<String> addEveryFormat() => [
    for (final ext in _formats)
      () {
        final dir = Directory(p.join(music.path, ext))..createSync();
        return File(
          _fixture('tagged.$ext'),
        ).copySync(p.join(dir.path, 'song.$ext')).path;
      }(),
  ];

  test('batch reading: one result per path, same as reading singly', () async {
    final paths = addEveryFormat();
    final broken = File(p.join(music.path, 'broken.flac'))
      ..writeAsStringSync('not audio');
    final all = [...paths, broken.path];

    final batch = await readTrackFiles(all);
    expect(batch.keys, unorderedEquals(all));
    for (final path in paths) {
      final single = await readTrackFile(path);
      expect(batch[path]!.metadata.title, single.metadata.title, reason: path);
      expect(batch[path]!.metadata.lyrics, single.metadata.lyrics);
      expect(batch[path]!.metadata.title, 'Fixture Title', reason: path);
    }
    expect(batch[broken.path]!.metadata.title, isNull, reason: 'fallback');
  });

  test('a folder scan stores tags and lyrics for every format', () async {
    addEveryFormat();
    final result = await scanner.scanDirectory(music.path);

    expect(result.addedCount, _formats.length);
    expect(result.failedPaths, isEmpty);
    final tracks = await db.select(db.tracks).get();
    expect(tracks.map((t) => t.format), unorderedEquals(_formats));
    for (final t in tracks) {
      expect(t.title, 'Fixture Title', reason: t.format);
      expect(t.lyrics, 'Plain line one\nPlain line two', reason: t.format);
    }
  });

  test('a rescan skips everything already in the library', () async {
    addEveryFormat();
    await scanner.scanDirectory(music.path);
    final again = await scanner.scanDirectory(music.path);
    expect(again.addedCount, 0);
    expect(again.allPaths, hasLength(_formats.length));
  });

  test('a cancel lands mid-chunk, not at the end of a batch', () async {
    for (var i = 0; i < 100; i++) {
      File(
        p.join(music.path, 'track_$i.flac'),
      ).writeAsBytesSync(buildFlac(['TITLE=Track $i']));
    }
    final token = ScanCancellationToken();
    final result = await scanner.scanDirectory(
      music.path,
      cancellationToken: token,
      onProgress: (processed) {
        if (processed == 40) token.cancel();
      },
    );
    expect(result.wasCancelled, isTrue);
    expect(result.addedCount, 40, reason: 'stops at the next file');
  });

  test('an unreadable folder is skipped instead of ending the scan', () async {
    addEveryFormat();
    final locked = Directory(p.join(music.path, 'locked'))..createSync();
    File(
      p.join(locked.path, 'hidden.flac'),
    ).writeAsBytesSync(buildFlac(['TITLE=Hidden']));
    await Process.run('chmod', ['000', locked.path]);
    addTearDown(() => Process.run('chmod', ['755', locked.path]));

    final result = await scanner.scanDirectory(music.path);
    expect(result.addedCount, _formats.length);
  }, skip: Platform.isWindows ? 'chmod is POSIX-only' : null);
}
