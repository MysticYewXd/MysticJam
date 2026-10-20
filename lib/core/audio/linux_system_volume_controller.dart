import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'system_volume_controller.dart';

/// Runs a command, like [Process.run]. Swappable so tests can stand in for
/// `wpctl`.
typedef ProcessRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);

/// Starts a long-running command, like [Process.start]. Swappable so tests
/// can stand in for `pactl subscribe`.
typedef ProcessStarter =
    Future<Process> Function(String executable, List<String> arguments);

/// Linux implementation via `wpctl` (PipeWire/WirePlumber's CLI). Verified
/// against this machine's actual audio stack — PipeWire owns the volume the
/// desktop's own indicator shows, which raw ALSA mixer calls do not
/// necessarily match.
///
/// Changes made outside the app (volume keys, the desktop's volume control)
/// arrive through `pactl subscribe`, which prints an event the moment a
/// sink changes — no polling. Without pactl, [volumeChanges] stays silent
/// and PlaybackController.refreshVolume() (called when Now Playing opens)
/// is what catches up.
class LinuxSystemVolumeController implements SystemVolumeController {
  static const _sink = '@DEFAULT_AUDIO_SINK@';

  final ProcessRunner _run;
  final ProcessStarter _start;

  /// Batches a burst of events (holding a volume key) into one read.
  final Duration _settle;

  /// How long after the app's own change its echo may still arrive.
  final Duration _echoWindow;

  LinuxSystemVolumeController()
    : _run = Process.run,
      _start = Process.start,
      _settle = const Duration(milliseconds: 80),
      _echoWindow = const Duration(milliseconds: 400);

  @visibleForTesting
  LinuxSystemVolumeController.withRunner(
    this._run, {
    ProcessStarter? start,
    Duration settleDelay = const Duration(milliseconds: 10),
    Duration echoDelay = const Duration(milliseconds: 50),
  }) : _start = start ?? _noSubscriber,
       _settle = settleDelay,
       _echoWindow = echoDelay;

  static Future<Process> _noSubscriber(String _, List<String> _) =>
      Future.error(const ProcessException('pactl', [], 'not in tests'));

  /// Runs `pactl subscribe` so that it ends together with the app, however
  /// the app ends (closed, killed or crashed): the shell waits on its input,
  /// a pipe from the app that the system closes when the app's process
  /// goes; then its exit trap stops pactl. A tidy shutdown closes that pipe
  /// itself — killing the shell instead would skip the trap.
  @visibleForTesting
  static const subscribeScript =
      "pactl subscribe & p=\$!; trap 'kill \$p 2>/dev/null' EXIT; "
      'cat >/dev/null';

  /// The newest volume not yet handed to `wpctl`. Only the latest is kept:
  /// a value superseded while a call was running is never sent.
  double? _pending;

  /// The loop sending [_pending], while one is running.
  Future<void>? _sending;

  /// The volume the app believes is set (what it last set, or last reported),
  /// as wpctl stores it: two decimals.
  double? _known;
  DateTime _lastOwnChange = DateTime.fromMillisecondsSinceEpoch(0);

  StreamController<double>? _changes;
  Process? _subscriber;
  StreamSubscription<String>? _events;
  Timer? _readTimer;
  bool _disposed = false;

  @override
  Future<double> getVolume() async {
    try {
      final result = await _run('wpctl', ['get-volume', _sink]);
      if (result.exitCode != 0) return 1.0;
      final match = RegExp(r'([\d.]+)').firstMatch(result.stdout.toString());
      if (match == null) return 1.0;
      return double.parse(match.group(1)!).clamp(0.0, 1.0);
    } catch (_) {
      return 1.0;
    }
  }

  /// Safe to call on every tick of a slider drag. Each call is one `wpctl`
  /// process, and parallel ones can finish out of order and leave the volume
  /// at an older value — so calls run one at a time, and whatever arrives
  /// meanwhile collapses into the single newest value, sent next. The
  /// returned future completes once [volume] (or a newer value) is applied.
  @override
  Future<void> setVolume(double volume) {
    _pending = volume.clamp(0.0, 1.0);
    return _sending ??= _drain();
  }

  Future<void> _drain() async {
    try {
      while (_pending != null) {
        final volume = _pending!;
        _pending = null;
        final text = volume.toStringAsFixed(2);
        _known = double.parse(text);
        try {
          await _run('wpctl', ['set-volume', _sink, text]);
        } catch (_) {
          // wpctl unavailable on this system; fail quietly rather than crash playback UI.
        }
        _lastOwnChange = DateTime.now();
      }
    } finally {
      _sending = null;
    }
  }

  /// Volume changes made outside the app. The `pactl subscribe` process runs
  /// only while something listens.
  @override
  Stream<double> get volumeChanges =>
      (_changes ??= StreamController<double>.broadcast(
        onListen: _subscribe,
        onCancel: _unsubscribe,
      )).stream;

  Future<void> _subscribe() async {
    try {
      final process = await _start('sh', ['-c', subscribeScript]);
      if (_disposed || !(_changes?.hasListener ?? false)) {
        unawaited(process.stdin.close().catchError((Object _) {}));
        return;
      }
      _subscriber = process;
      unawaited(process.stderr.drain<void>());
      _events = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            // "Event 'change' on sink #51" for a volume change; "on server"
            // when the default output device itself changes.
            if (line.contains("'change' on sink") ||
                line.contains("'change' on server")) {
              _scheduleRead(_settle);
            }
          });
    } catch (_) {
      // No pactl (or no PulseAudio-compatible server): no live updates.
    }
  }

  void _scheduleRead(Duration delay) {
    _readTimer?.cancel();
    _readTimer = Timer(delay, _readAndReport);
  }

  Future<void> _readAndReport() async {
    // The app's own changes come back as events too. While one is still
    // being applied (or has only just been), reading now could catch an
    // older value mid-drag and make the slider jump back — so wait, then
    // read once it has settled.
    final sinceOwn = DateTime.now().difference(_lastOwnChange);
    if (_sending != null || sinceOwn < _echoWindow) {
      _scheduleRead(_echoWindow - sinceOwn + _settle);
      return;
    }
    final volume = await getVolume();
    final known = _known;
    if (known != null && (volume - known).abs() < 0.005) return;
    _known = volume;
    final changes = _changes;
    if (!_disposed && changes != null && !changes.isClosed) {
      changes.add(volume);
    }
  }

  void _unsubscribe() {
    _readTimer?.cancel();
    _events?.cancel();
    _events = null;
    // Ends the shell's wait, so its trap stops pactl (see subscribeScript).
    final subscriber = _subscriber;
    _subscriber = null;
    if (subscriber != null) {
      unawaited(subscriber.stdin.close().catchError((Object _) {}));
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _unsubscribe();
    _changes?.close();
  }
}
