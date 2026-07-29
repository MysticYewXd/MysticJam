/// Abstract playback backend. Kept separate from any specific package so the
/// engine (currently media_kit) can be swapped later without touching UI or
/// playback-state code — e.g. if background-playback/MediaSession ergonomics
/// ever force a switch to just_audio for a subset of formats.
abstract class AudioEngine {
  Future<void> init();

  Future<void> open(String filePath, {bool play = true});

  Future<void> play();

  Future<void> pause();

  Future<void> stop();

  Future<void> seek(Duration position);

  /// 0.0 (silent) to 1.0 (full volume).
  Future<void> setVolume(double volume);

  Future<void> dispose();

  Stream<Duration> get positionStream;

  Stream<Duration> get durationStream;

  Stream<bool> get playingStream;

  Stream<bool> get completedStream;

  Stream<String> get errorStream;

  /// 0.0 (silent) to 1.0 (full volume).
  Stream<double> get volumeStream;
}
