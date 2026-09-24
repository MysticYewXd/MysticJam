/// Controls the OS-level output volume — deliberately separate from
/// [AudioEngine]'s volume methods, which only ever adjusted this app's
/// internal software gain. The Now Playing volume slider drives this instead,
/// so moving it changes the system volume the same way the OS's own control
/// would, on both Linux and Android.
abstract class SystemVolumeController {
  /// Current system volume, 0.0 (silent) to 1.0 (max).
  Future<double> getVolume();

  Future<void> setVolume(double volume);

  /// Emits when the system volume changes from outside the app (hardware
  /// keys, OS volume UI, another app). Not all platforms can watch for this
  /// cheaply — an empty stream is a valid implementation.
  Stream<double> get volumeChanges;

  void dispose();
}
