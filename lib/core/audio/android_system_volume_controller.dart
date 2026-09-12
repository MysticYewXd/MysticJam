import 'dart:async';

import 'package:volume_controller/volume_controller.dart';

import 'system_volume_controller.dart';

/// Android implementation via the `volume_controller` plugin, which talks to
/// AudioManager's STREAM_MUSIC directly — the real system media volume.
class AndroidSystemVolumeController implements SystemVolumeController {
  AndroidSystemVolumeController() {
    // Don't pop the OS volume HUD every time the in-app slider moves.
    VolumeController.instance.showSystemUI = false;
  }

  StreamController<double>? _changes;

  @override
  Future<double> getVolume() => VolumeController.instance.getVolume();

  @override
  Future<void> setVolume(double volume) => VolumeController.instance.setVolume(volume.clamp(0.0, 1.0));

  @override
  Stream<double> get volumeChanges {
    _changes ??= StreamController<double>.broadcast(
      onListen: () {
        VolumeController.instance.addListener(
          (v) => _changes?.add(v),
          fetchInitialVolume: false,
        );
      },
      onCancel: () => VolumeController.instance.removeListener(),
    );
    return _changes!.stream;
  }

  @override
  void dispose() {
    VolumeController.instance.removeListener();
    _changes?.close();
  }
}
