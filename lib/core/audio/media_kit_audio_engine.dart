import 'package:media_kit/media_kit.dart';
import 'audio_engine.dart';

/// media_kit (libmpv/FFmpeg) implementation of [AudioEngine]. Covers every
/// format in format_support.dart natively on both Linux and Android.
class MediaKitAudioEngine implements AudioEngine {
  late final Player _player;

  @override
  Future<void> init() async {
    _player = Player();
  }

  @override
  Future<void> open(String filePath, {bool play = true}) {
    // Media() normalizes plain filesystem paths (and Android content:// URIs)
    // internally — do not hand-build a file:// URI, it would mis-encode spaces.
    return _player.open(Media(filePath), play: play);
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume.clamp(0.0, 1.0) * 100);

  @override
  Future<void> dispose() => _player.dispose();

  @override
  Stream<Duration> get positionStream => _player.stream.position;

  @override
  Stream<Duration> get durationStream => _player.stream.duration;

  @override
  Stream<bool> get playingStream => _player.stream.playing;

  @override
  Stream<bool> get completedStream => _player.stream.completed;

  @override
  Stream<String> get errorStream => _player.stream.error;

  @override
  Stream<double> get volumeStream => _player.stream.volume.map((v) => (v / 100).clamp(0.0, 1.0));
}
