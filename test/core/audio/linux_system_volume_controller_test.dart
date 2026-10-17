import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_player/core/audio/linux_system_volume_controller.dart';

/// Stands in for `wpctl`: records each call and holds it open until the
/// test completes it, so overlapping calls can be observed.
class _FakeWpctl {
  final calls = <List<String>>[];
  final _open = <Completer<ProcessResult>>[];
  int running = 0;
  int maxRunning = 0;
  bool fail = false;
  String stdout = '';

  Future<ProcessResult> call(String exe, List<String> args) async {
    expect(exe, 'wpctl');
    calls.add(args);
    if (fail) throw const ProcessException('wpctl', [], 'not found');
    if (args.first == 'get-volume') return ProcessResult(0, 0, stdout, '');
    running++;
    maxRunning = running > maxRunning ? running : maxRunning;
    final c = Completer<ProcessResult>();
    _open.add(c);
    try {
      return await c.future;
    } finally {
      running--;
    }
  }

  /// Finishes the oldest running call and lets the controller react.
  Future<void> finishOne() async {
    _open.removeAt(0).complete(ProcessResult(0, 0, '', ''));
    await pumpEventQueue();
  }

  List<String> get sentVolumes => [
    for (final a in calls)
      if (a.first == 'set-volume') a.last,
  ];
}

void main() {
  late _FakeWpctl wpctl;
  late LinuxSystemVolumeController controller;

  setUp(() {
    wpctl = _FakeWpctl();
    controller = LinuxSystemVolumeController.withRunner(wpctl.call);
  });

  test('a single change is sent straight away', () async {
    final done = controller.setVolume(0.42);
    await pumpEventQueue();
    expect(wpctl.sentVolumes, ['0.42']);
    await wpctl.finishOne();
    await done;
  });

  test(
    'a fast drag sends one at a time and ends on the newest value',
    () async {
      final first = controller.setVolume(0.1);
      await pumpEventQueue();
      // A drag keeps going while the first wpctl is still running.
      final middle = controller.setVolume(0.2);
      controller.setVolume(0.3);
      final last = controller.setVolume(0.4);
      await pumpEventQueue();
      expect(wpctl.sentVolumes, ['0.10'], reason: 'nothing sent in parallel');

      await wpctl.finishOne();
      expect(wpctl.sentVolumes, [
        '0.10',
        '0.40',
      ], reason: 'superseded values are skipped');
      await wpctl.finishOne();
      await Future.wait([first, middle, last]);
      expect(wpctl.maxRunning, 1);
    },
  );

  test('a new change after things settle is sent again', () async {
    controller.setVolume(0.5);
    await pumpEventQueue();
    await wpctl.finishOne();
    controller.setVolume(0.6);
    await pumpEventQueue();
    expect(wpctl.sentVolumes, ['0.50', '0.60']);
    await wpctl.finishOne();
  });

  test('values are clamped to 0..1', () async {
    controller.setVolume(1.7);
    await pumpEventQueue();
    expect(wpctl.sentVolumes, ['1.00']);
    await wpctl.finishOne();
  });

  test(
    'a missing wpctl fails quietly and later changes still go out',
    () async {
      wpctl.fail = true;
      await controller.setVolume(0.3);
      wpctl.fail = false;
      controller.setVolume(0.7);
      await pumpEventQueue();
      expect(wpctl.sentVolumes, ['0.30', '0.70']);
      await wpctl.finishOne();
    },
  );

  test('getVolume reads the level wpctl reports', () async {
    wpctl.stdout = 'Volume: 0.35\n';
    expect(await controller.getVolume(), 0.35);
  });
}
