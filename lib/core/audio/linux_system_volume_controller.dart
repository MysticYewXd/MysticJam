import 'dart:async';
import 'dart:io';

import 'system_volume_controller.dart';

/// Linux implementation via `wpctl` (PipeWire/WirePlumber's CLI). Verified
/// against this machine's actual audio stack — PipeWire owns the volume the
/// desktop's own indicator shows, which raw ALSA mixer calls do not
/// necessarily match. No practical low-effort way to watch for external
/// changes here, so [volumeChanges] stays empty — PlaybackController.
/// refreshVolume() (called when Now Playing opens) is what catches up with
/// volume changes made outside the app.
class LinuxSystemVolumeController implements SystemVolumeController {
  static const _sink = '@DEFAULT_AUDIO_SINK@';

  @override
  Future<double> getVolume() async {
    try {
      final result = await Process.run('wpctl', ['get-volume', _sink]);
      if (result.exitCode != 0) return 1.0;
      final match = RegExp(r'([\d.]+)').firstMatch(result.stdout.toString());
      if (match == null) return 1.0;
      return double.parse(match.group(1)!).clamp(0.0, 1.0);
    } catch (_) {
      return 1.0;
    }
  }

  @override
  Future<void> setVolume(double volume) async {
    final clamped = volume.clamp(0.0, 1.0);
    try {
      await Process.run('wpctl', ['set-volume', _sink, clamped.toStringAsFixed(2)]);
    } catch (_) {
      // wpctl unavailable on this system; fail quietly rather than crash playback UI.
    }
  }

  @override
  Stream<double> get volumeChanges => const Stream.empty();

  @override
  void dispose() {}
}
