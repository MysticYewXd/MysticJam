import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../audio/audio_engine.dart';
import '../audio/audio_engine_provider.dart';
import '../library/database.dart';

class PlaybackState {
  final Track? currentTrack;
  final List<Track> queue;
  final int queueIndex;
  final bool isPlaying;
  final Duration position;
  final Duration duration;
  final double volume;

  const PlaybackState({
    this.currentTrack,
    this.queue = const [],
    this.queueIndex = -1,
    this.isPlaying = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.volume = 1.0,
  });

  bool get hasNext => queueIndex >= 0 && queueIndex < queue.length - 1;

  bool get hasPrevious => queueIndex > 0;

  PlaybackState copyWith({
    Track? currentTrack,
    List<Track>? queue,
    int? queueIndex,
    bool? isPlaying,
    Duration? position,
    Duration? duration,
    double? volume,
  }) {
    return PlaybackState(
      currentTrack: currentTrack ?? this.currentTrack,
      queue: queue ?? this.queue,
      queueIndex: queueIndex ?? this.queueIndex,
      isPlaying: isPlaying ?? this.isPlaying,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      volume: volume ?? this.volume,
    );
  }
}

/// Bridges the raw [AudioEngine] streams into app-level playback state and
/// exposes the actions screens call (play/pause/seek/next/previous).
///
/// Playback is queue-based: playing a track always happens in the context of
/// a list (the whole library, a playlist, or a single-track queue), which is
/// what makes next/previous meaningful and keeps playlists from "mixing"
/// with unrelated library taps.
class PlaybackController extends Notifier<PlaybackState> {
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<bool>? _playingSub;
  StreamSubscription<bool>? _completedSub;
  StreamSubscription<double>? _volumeSub;

  AudioEngine get _engine => ref.read(audioEngineProvider);

  @override
  PlaybackState build() {
    _positionSub = _engine.positionStream.listen((pos) {
      state = state.copyWith(position: pos);
    });
    _durationSub = _engine.durationStream.listen((dur) {
      state = state.copyWith(duration: dur);
    });
    _playingSub = _engine.playingStream.listen((playing) {
      state = state.copyWith(isPlaying: playing);
    });
    _volumeSub = _engine.volumeStream.listen((volume) {
      state = state.copyWith(volume: volume);
    });
    _completedSub = _engine.completedStream.listen((completed) {
      if (completed && state.hasNext) next();
    });
    ref.onDispose(() {
      _positionSub?.cancel();
      _durationSub?.cancel();
      _playingSub?.cancel();
      _completedSub?.cancel();
      _volumeSub?.cancel();
    });
    return const PlaybackState();
  }

  /// Plays [queue] starting at [startIndex]. If the requested track is
  /// already the one loaded, this resumes/keeps it in place rather than
  /// restarting playback from zero — re-tapping the same song (or the same
  /// song surfacing in a different list) never rewinds it.
  Future<void> playFromQueue(List<Track> queue, int startIndex) async {
    if (startIndex < 0 || startIndex >= queue.length) return;
    final track = queue[startIndex];
    final isSameTrack = state.currentTrack?.id == track.id;

    state = state.copyWith(queue: queue, queueIndex: startIndex, currentTrack: track);

    if (isSameTrack) {
      if (!state.isPlaying) await _engine.play();
      return;
    }
    await _engine.open(track.filePath);
  }

  Future<void> playSingle(Track track) => playFromQueue([track], 0);

  Future<void> next() async {
    if (!state.hasNext) return;
    await playFromQueue(state.queue, state.queueIndex + 1);
  }

  Future<void> previous() async {
    if (!state.hasPrevious) return;
    await playFromQueue(state.queue, state.queueIndex - 1);
  }

  Future<void> togglePlayPause() async {
    if (state.isPlaying) {
      await _engine.pause();
    } else {
      await _engine.play();
    }
  }

  Future<void> seek(Duration position) => _engine.seek(position);

  Future<void> setVolume(double volume) => _engine.setVolume(volume);
}

final playbackControllerProvider =
    NotifierProvider<PlaybackController, PlaybackState>(PlaybackController.new);
