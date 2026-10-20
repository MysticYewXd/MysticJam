import 'dart:async';
import 'dart:convert';
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

/// Stands in for the running `pactl subscribe` wrapper: the test writes
/// event lines, and can see whether the app closed its input (which is how
/// the wrapper is told to stop pactl).
class _FakePactl implements Process {
  final _out = StreamController<List<int>>();
  final _in = StreamController<List<int>>();
  late final IOSink _stdin = IOSink(_in);
  bool killed = false;
  bool inputClosed = false;

  _FakePactl() {
    _in.stream.listen(null, onDone: () => inputClosed = true);
  }

  void event(String line) => _out.add(utf8.encode('$line\n'));

  @override
  Stream<List<int>> get stdout => _out.stream;
  @override
  Stream<List<int>> get stderr => const Stream.empty();
  @override
  Future<int> get exitCode => Completer<int>().future;
  @override
  int get pid => 4242;
  @override
  IOSink get stdin => _stdin;
  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killed = true;
    _out.close();
    return true;
  }
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

  group('following outside changes (pactl subscribe)', () {
    late _FakePactl pactl;
    late List<double> reported;
    late StreamSubscription<double> listening;
    var starts = 0;

    /// Waits past the settle delay and any echo deferral (test timings).
    Future<void> settle() =>
        Future<void>.delayed(const Duration(milliseconds: 150));

    int volumeReads() =>
        wpctl.calls.where((c) => c.first == 'get-volume').length;

    setUp(() async {
      pactl = _FakePactl();
      starts = 0;
      reported = [];
      controller = LinuxSystemVolumeController.withRunner(
        wpctl.call,
        start: (exe, args) async {
          expect(exe, 'sh');
          expect(args, ['-c', LinuxSystemVolumeController.subscribeScript]);
          starts++;
          return pactl;
        },
      );
      listening = controller.volumeChanges.listen(reported.add);
      await pumpEventQueue();
    });

    tearDown(() async {
      await listening.cancel();
      controller.dispose();
    });

    test('an outside change reaches the sliders', () async {
      expect(starts, 1);
      wpctl.stdout = 'Volume: 0.40\n';
      pactl.event("Event 'change' on sink #51");
      await settle();
      expect(reported, [0.40]);
    });

    test('unrelated events are ignored', () async {
      pactl
        ..event("Event 'change' on client #707")
        ..event("Event 'new' on sink-input #12")
        ..event("Event 'change' on card #47");
      await settle();
      expect(volumeReads(), 0);
      expect(reported, isEmpty);
    });

    test('holding a volume key is read once', () async {
      wpctl.stdout = 'Volume: 0.70\n';
      for (var i = 0; i < 5; i++) {
        pactl.event("Event 'change' on sink #51");
      }
      await settle();
      expect(volumeReads(), 1);
      expect(reported, [0.70]);
    });

    test('the app\'s own change does not echo back', () async {
      final done = controller.setVolume(0.3);
      await pumpEventQueue();
      // Events for our own change arrive while it is still being applied.
      wpctl.stdout = 'Volume: 0.30\n';
      pactl.event("Event 'change' on sink #51");
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await wpctl.finishOne();
      await done;
      pactl.event("Event 'change' on sink #51");
      await settle();
      expect(reported, isEmpty);
    });

    test('mid-drag, a stale reading never pulls the slider back', () async {
      final first = controller.setVolume(0.3);
      await pumpEventQueue();
      await wpctl.finishOne();
      await first;
      // The drag moves on to 0.60, which is still being applied while the
      // system (and so a read) would still say 0.30.
      wpctl.stdout = 'Volume: 0.30\n';
      final second = controller.setVolume(0.6);
      await pumpEventQueue();
      pactl.event("Event 'change' on sink #51");
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(reported, isEmpty, reason: 'nothing read while applying');
      wpctl.stdout = 'Volume: 0.60\n';
      await wpctl.finishOne();
      await second;
      await settle();
      expect(reported, isEmpty, reason: 'and the settled value is ours');
    });

    test('an outside change right after our own is still caught', () async {
      final done = controller.setVolume(0.3);
      await pumpEventQueue();
      await wpctl.finishOne();
      await done;
      // Within the echo window: deferred, not dropped.
      wpctl.stdout = 'Volume: 0.55\n';
      pactl.event("Event 'change' on sink #51");
      await settle();
      expect(reported, [0.55]);
    });

    test(
      'stopping listening closes the wrapper\'s input, never kills it',
      () async {
        await listening.cancel();
        await pumpEventQueue();
        expect(pactl.inputClosed, isTrue);
        expect(
          pactl.killed,
          isFalse,
          reason: 'a killed shell would skip the trap that stops pactl',
        );
      },
    );

    test('the wrapper runs pactl and stops it when its input ends', () {
      const script = LinuxSystemVolumeController.subscribeScript;
      expect(script, contains('pactl subscribe &'));
      expect(script, contains("trap 'kill \$p"));
      expect(script, endsWith('cat >/dev/null'));
    });
  });

  test('without pactl it stays silent and setting still works', () async {
    final c = LinuxSystemVolumeController.withRunner(
      wpctl.call,
      start: (_, _) async => throw const ProcessException('pactl', []),
    );
    final reported = <double>[];
    final sub = c.volumeChanges.listen(reported.add);
    await pumpEventQueue();
    final done = c.setVolume(0.2);
    await pumpEventQueue();
    await wpctl.finishOne();
    await done;
    expect(wpctl.sentVolumes, ['0.20']);
    expect(reported, isEmpty);
    await sub.cancel();
    c.dispose();
  });
}
