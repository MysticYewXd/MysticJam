/// Runs the scan benchmark as a compiled (profile) build, so its timings
/// are comparable with the shipped app:
///
///   flutter run --profile -d linux -t tool/scan_benchmark/main.dart \
///     --dart-define=MUSIC_DIR=/path/to/music \
///     --dart-define=OUT=/abs/path/build/scan_benchmark
///
/// Writes report.json, snapshot.json and summary.txt into OUT, prints the
/// summary and exits. With --dart-define=BASELINE=/path/snapshot.json it also
/// compares against that earlier snapshot and writes diff.txt. Read-only:
/// see benchmark.dart.
library;

import 'dart:io';

import 'package:flutter/widgets.dart';

import 'package:music_player/src/rust/frb_generated.dart';

import 'benchmark.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  const musicDir = String.fromEnvironment('MUSIC_DIR');
  const outDir = String.fromEnvironment('OUT');
  const runs = int.fromEnvironment('RUNS', defaultValue: 3);
  if (musicDir.isEmpty || outDir.isEmpty) {
    stderr.writeln(
      'Pass --dart-define=MUSIC_DIR=... and --dart-define=OUT=...',
    );
    exit(64);
  }
  final report = await runBenchmark(musicDir, runs: runs);
  writeReport(report, outDir);
  stdout.writeln(report.summary());
  const baseline = String.fromEnvironment('BASELINE');
  if (baseline.isNotEmpty) {
    final diff = compareSnapshots(readSnapshot(baseline), report.snapshot);
    File('$outDir/diff.txt').writeAsStringSync(diff.summary(maxGains: 1000));
    stdout.writeln(diff.summary());
  }
  exit(0);
}
