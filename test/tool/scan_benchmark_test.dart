import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import '../../tool/scan_benchmark/benchmark.dart';
import '../helpers/flac_fixture.dart';
import '../helpers/rust_lib.dart';

/// Stands in for the app's real support directory; the benchmark must never
/// write cover art (or anything else) through it.
class _RealSupportDir extends PathProviderPlatform {
  final String path;
  _RealSupportDir(this.path);

  @override
  Future<String?> getApplicationSupportPath() async => path;
}

Map<String, int> _listing(Directory dir) => {
  for (final e in dir.listSync(recursive: true))
    if (e is File) p.relative(e.path, from: dir.path): e.lengthSync(),
};

void main() {
  setUpAll(loadRustLib);

  late Directory music;
  late Directory realSupport;
  late Directory out;

  setUp(() {
    music = Directory.systemTemp.createTempSync('mysticjam_bench_music_');
    realSupport = Directory.systemTemp.createTempSync('mysticjam_bench_app_');
    out = Directory.systemTemp.createTempSync('mysticjam_bench_out_');
    PathProviderPlatform.instance = _RealSupportDir(realSupport.path);

    void flac(String rel, List<String> comments) {
      final f = File(p.join(music.path, rel))..createSync(recursive: true);
      f.writeAsBytesSync(buildFlac(comments));
    }

    flac('A/1.flac', ['TITLE=One', 'ALBUM=Record', 'ARTIST=Band', 'DATE=2001']);
    flac('A/2.flac', ['TITLE=Two', 'ALBUM=Record', 'ARTIST=Band']);
    flac('B/3.flac', ['TITLE=Three', 'LYRICS=Hello lyrics']);
    File(p.join(music.path, 'A/2.lrc')).writeAsStringSync('[00:01.00]Line');
    File(p.join(music.path, 'A/cover.jpg')).writeAsBytesSync([1, 2, 3, 4]);
    File(p.join(music.path, 'notes.txt')).writeAsStringSync('not media');
  });

  tearDown(() {
    for (final d in [music, realSupport, out]) {
      d.deleteSync(recursive: true);
    }
  });

  test('times every run and counts files per format', () async {
    final report = await runBenchmark(music.path, runs: 2);
    expect(report.fullScanMs, hasLength(2));
    expect(report.formats.keys, ['flac']);
    expect(report.formats['flac']!.files, 3);
    expect(report.summary(), contains('reading all files'));
    expect(report.snapshot, hasLength(3));
    expect(report.failedPaths, isEmpty);
  });

  test('snapshots what the scanner stored', () async {
    final report = await runBenchmark(music.path, runs: 1);
    final byTitle = {for (final s in report.snapshot) s.title: s};

    expect(byTitle['One']!.album, 'Record');
    expect(byTitle['One']!.artist, 'Band');
    expect(byTitle['One']!.year, 2001);
    expect(byTitle['Two']!.syncedLyrics, '[00:01.00]Line');
    // Folder cover art is found for songs next to cover.jpg.
    expect(byTitle['One']!.artworkBytes, 4);
    expect(byTitle['Three']!.artworkBytes, isNull);
    // Embedded FLAC lyrics: read since the Rust reader (the Dart FLAC
    // reader ignored them).
    expect(byTitle['Three']!.lyrics, 'Hello lyrics');
    expect(report.withSyncedLyrics, 1);
    expect(report.withEmbeddedLyrics, 1);
  });

  test('is read-only: the music folder and app data are untouched', () async {
    final musicBefore = _listing(music);
    await runBenchmark(music.path, runs: 2);
    expect(_listing(music), musicBefore);
    expect(_listing(realSupport), isEmpty, reason: 'no art written there');
    expect(
      PathProviderPlatform.instance,
      isA<_RealSupportDir>(),
      reason: 'the redirect is undone afterwards',
    );
  });

  test('report files are written and the snapshot reads back', () async {
    final report = await runBenchmark(music.path, runs: 1);
    writeReport(report, out.path);
    for (final f in ['report.json', 'snapshot.json', 'summary.txt']) {
      expect(File(p.join(out.path, f)).existsSync(), isTrue, reason: f);
    }
    expect(readSnapshot(p.join(out.path, 'snapshot.json')), report.snapshot);
    expect(report.summary(), contains('flac'));
  });

  test('snapshot comparison separates gains from changes', () {
    const old = FileSnapshot(path: '/m/a.flac', format: 'flac', title: 'A');
    const same = FileSnapshot(path: '/m/b.flac', format: 'flac', title: 'B');
    const gone = FileSnapshot(path: '/m/c.flac', format: 'flac', title: 'C');
    const gained = FileSnapshot(
      path: '/m/a.flac',
      format: 'flac',
      title: 'A',
      lyrics: 'New words',
    );
    const renamed = FileSnapshot(
      path: '/m/b.flac',
      format: 'flac',
      title: 'Bee',
    );
    const extra = FileSnapshot(path: '/m/d.flac', format: 'flac', title: 'D');

    final diff = compareSnapshots([old, same, gone], [gained, renamed, extra]);
    expect(diff.gains, ['lyrics: a.flac -> New words']);
    expect(diff.changes, [
      'title: b.flac: B -> Bee',
      'missing file: /m/c.flac',
      'added file: /m/d.flac',
    ]);
    expect(compareSnapshots([old], [old]).changes, isEmpty);
    expect(diff.summary(), contains('Gains: 1 (lyrics 1)'));
  });
}
