import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:music_player/core/library/database.dart';
import 'package:music_player/core/library/library_repository.dart';
import 'package:music_player/core/library/library_scanner.dart';
import 'package:music_player/core/library/metadata/lrc_parser.dart';
import 'package:music_player/core/logging/app_log.dart';

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
  late AppDatabase db;
  late LibraryRepository repo;
  late LibraryScanner scanner;

  setUp(() {
    musicDir = Directory.systemTemp.createTempSync('mysticjam_lrc_music_');
    supportDir = Directory.systemTemp.createTempSync('mysticjam_lrc_support_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(supportDir.path);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = LibraryRepository(db);
    scanner = LibraryScanner(repo);
  });

  tearDown(() {
    musicDir.deleteSync(recursive: true);
    supportDir.deleteSync(recursive: true);
    db.close();
  });

  String writeAudio(
    String name, [
    List<String> comments = const ['TITLE=Song'],
  ]) {
    final f = File('${musicDir.path}/$name')
      ..writeAsBytesSync(buildFlac(comments));
    return f.path;
  }

  Future<Track> trackAt(String path) =>
      (db.select(db.tracks)..where((t) => t.filePath.equals(path))).getSingle();

  test('a same-named .lrc sidecar is picked up and stored raw', () async {
    final audio = writeAudio('song.flac');
    File(
      '${musicDir.path}/song.lrc',
    ).writeAsStringSync('[00:01.00]Hello\n[00:05.00]World');

    await scanner.scanDirectory(musicDir.path);

    final track = await trackAt(audio);
    expect(track.syncedLyrics, isNotNull);
    final lines = parseLrc(track.syncedLyrics!);
    expect(lines.map((l) => l.text), ['Hello', 'World']);
  });

  test('a track with no .lrc file gets no synced lyrics', () async {
    final audio = writeAudio('nolyrics.flac');

    await scanner.scanDirectory(musicDir.path);

    final track = await trackAt(audio);
    expect(track.syncedLyrics, isNull);
  });

  test('an .lrc file only matches its own same-named track', () async {
    writeAudio('a.flac');
    final b = writeAudio('b.flac');
    File('${musicDir.path}/a.lrc').writeAsStringSync('[00:01.00]For A only');

    await scanner.scanDirectory(musicDir.path);

    final trackB = await trackAt(b);
    expect(trackB.syncedLyrics, isNull);
  });

  test('an empty or whitespace-only .lrc file counts as no lyrics', () async {
    final audio = writeAudio('empty.flac');
    File('${musicDir.path}/empty.lrc').writeAsStringSync('   \n  \n');

    await scanner.scanDirectory(musicDir.path);

    final track = await trackAt(audio);
    expect(track.syncedLyrics, isNull);
  });

  test('an .LRC (uppercase extension) sidecar is also found', () async {
    final audio = writeAudio('upper.flac');
    File('${musicDir.path}/upper.LRC').writeAsStringSync('[00:01.00]Shout');

    await scanner.scanDirectory(musicDir.path);

    final track = await trackAt(audio);
    expect(track.syncedLyrics, isNotNull);
  });

  test(
    'rescanLyrics picks up an .lrc added after the track was indexed',
    () async {
      final audio = writeAudio('later.flac');
      await scanner.scanDirectory(musicDir.path);
      expect((await trackAt(audio)).syncedLyrics, isNull);

      File('${musicDir.path}/later.lrc').writeAsStringSync('[00:01.00]Late');
      final updated = await scanner.rescanLyrics();

      expect(updated, 1);
      expect((await trackAt(audio)).syncedLyrics, contains('Late'));
    },
  );

  test(
    'rescanLyrics keeps lyrics that have no .lrc file (e.g. fetched online)',
    () async {
      final audio = writeAudio('online.flac');
      await scanner.scanDirectory(musicDir.path);
      final id = (await trackAt(audio)).id;
      await repo.setSyncedLyrics(id, '[00:01.00]From the web');

      final updated = await scanner.rescanLyrics();

      expect(updated, 0);
      expect((await trackAt(audio)).syncedLyrics, '[00:01.00]From the web');
    },
  );

  test(
    'rescanLyrics skips files that no longer exist and reports progress',
    () async {
      final audio = writeAudio('gone.flac');
      await scanner.scanDirectory(musicDir.path);
      File(audio).deleteSync();

      final calls = <(int, int)>[];
      final updated = await scanner.rescanLyrics(
        onProgress: (d, t) => calls.add((d, t)),
      );

      expect(updated, 0);
      expect(calls, [(1, 1)]);
    },
  );

  test('a scan logs counts and timing but never file names', () async {
    final lines = <String>[];
    AppLog.testSink = lines.add;
    addTearDown(() => AppLog.testSink = null);
    writeAudio('My Very Private Song.flac');

    await scanner.scanDirectory(musicDir.path);

    final line = lines.singleWhere((l) => l.contains('"tag":"scan"'));
    expect(line, contains('"added":1'));
    expect(line, contains('"failed":0'));
    expect(line, isNot(contains('Private')));
    expect(line, isNot(contains(musicDir.path)));
  });
}
