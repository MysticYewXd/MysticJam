import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'system_volume_controller.dart';

/// Runs a command, like [Process.run]. Swappable so tests can stand in for
/// `wpctl`.
typedef ProcessRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);

/// Linux implementation via `wpctl` (PipeWire/WirePlumber's CLI). Verified
/// against this machine's actual audio stack — PipeWire owns the volume the
/// desktop's own indicator shows, which raw ALSA mixer calls do not
/// necessarily match. No practical low-effort way to watch for external
/// changes here, so [volumeChanges] stays empty — PlaybackController.
/// refreshVolume() (called when Now Playing opens) is what catches up with
/// volume changes made outside the app.
class LinuxSystemVolumeController implements SystemVolumeController {
  static const _sink = '@DEFAULT_AUDIO_SINK@';

  final ProcessRunner _run;

  LinuxSystemVolumeController() : _run = Process.run;

  @visibleForTesting
  LinuxSystemVolumeController.withRunner(this._run);

  /// The newest volume not yet handed to `wpctl`. Only the latest is kept:
  /// a value superseded while a call was running is never sent.
  double? _pending;

  /// The loop sending [_pending], while one is running.
  Future<void>? _sending;

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
        try {
          await _run('wpctl', ['set-volume', _sink, volume.toStringAsFixed(2)]);
        } catch (_) {
          // wpctl unavailable on this system; fail quietly rather than crash playback UI.
        }
      }
    } finally {
      _sending = null;
    }
  }

  @override
  Stream<double> get volumeChanges => const Stream.empty();

  @override
  void dispose() {}
}
