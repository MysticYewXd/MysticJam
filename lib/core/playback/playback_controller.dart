import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../audio/audio_engine.dart';
import '../audio/audio_engine_provider.dart';
import '../audio/system_volume_provider.dart';
import '../library/database.dart';
import '../library/library_providers.dart';

enum PlayerRepeatMode { off, all, one }

class PlaybackState {
  final Track? currentTrack;
  final List<Track> queue;

  /// Play order, as indices into [queue]. Identity order
  /// (0, 1, 2, ...) when shuffle is off; a stable shuffled permutation
  /// when shuffle is on — regenerated only when shuffle is toggled or a new
  /// queue starts playing, never on every next()/previous() call.
  final List<int> order;

  /// Position within [order] — NOT an index into [queue] directly.
  final int orderIndex;

  final bool shuffleEnabled;
  final PlayerRepeatMode repeatMode;
  final bool isPlaying;
  final Duration position;
  final Duration duration;
  final double volume;

  const PlaybackState({
    this.currentTrack,
    this.queue = const [],
    this.order = const [],
    this.orderIndex = -1,
    this.shuffleEnabled = false,
    this.repeatMode = PlayerRepeatMode.off,
    this.isPlaying = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.volume = 1.0,
  });

  bool get hasNext {
    if (order.isEmpty) return false;
    if (repeatMode == PlayerRepeatMode.all) return true;
    return orderIndex < order.length - 1;
  }

  bool get hasPrevious {
    if (order.isEmpty) return false;
    if (repeatMode == PlayerRepeatMode.all) return true;
    return orderIndex > 0;
  }

  PlaybackState copyWith({
    Track? currentTrack,
    List<Track>? queue,
    List<int>? order,
    int? orderIndex,
    bool? shuffleEnabled,
    PlayerRepeatMode? repeatMode,
    bool? isPlaying,
    Duration? position,
    Duration? duration,
    double? volume,
  }) {
    return PlaybackState(
      currentTrack: currentTrack ?? this.currentTrack,
      queue: queue ?? this.queue,
      order: order ?? this.order,
      orderIndex: orderIndex ?? this.orderIndex,
      shuffleEnabled: shuffleEnabled ?? this.shuffleEnabled,
      repeatMode: repeatMode ?? this.repeatMode,
      isPlaying: isPlaying ?? this.isPlaying,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      volume: volume ?? this.volume,
    );
  }
}

/// Bridges the raw [AudioEngine] streams into app-level playback state and
/// exposes the actions screens call (play/pause/seek/next/previous/shuffle/repeat).
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

  // Tracks whose real duration we've already written this session, so a
  // format without a cheap tag-based duration (i.e. anything but FLAC)
  // doesn't get the same value re-persisted on every durationStream tick.
  final Set<int> _durationPersistedForTrackId = {};

  AudioEngine get _engine => ref.read(audioEngineProvider);

  @override
  PlaybackState build() {
    _positionSub = _engine.positionStream.listen((pos) {
      state = state.copyWith(position: pos);
    });
    _durationSub = _engine.durationStream.listen((dur) {
      state = state.copyWith(duration: dur);
      _maybePersistDuration(dur);
    });
    _playingSub = _engine.playingStream.listen((playing) {
      state = state.copyWith(isPlaying: playing);
    });
    _completedSub = _engine.completedStream.listen((completed) {
      if (!completed) return;
      if (state.repeatMode == PlayerRepeatMode.one) {
        _engine.seek(Duration.zero);
        _engine.play();
        return;
      }
      if (state.hasNext) next();
    });

    final volumeController = ref.read(systemVolumeControllerProvider);
    // Live external changes (hardware keys, OS volume UI) — Android only for
    // now; Linux has no cheap way to watch for these, see
    // LinuxSystemVolumeController.
    _volumeSub = volumeController.volumeChanges.listen((volume) {
      state = state.copyWith(volume: volume);
    });
    // Seed the slider from whatever the system volume actually is right now.
    volumeController.getVolume().then((volume) {
      state = state.copyWith(volume: volume);
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

  List<int> _sequentialOrder(int length) => List<int>.generate(length, (i) => i);

  List<int> _shuffledOrderKeeping(int length, int keepFirst) {
    final rest = _sequentialOrder(length)..remove(keepFirst);
    rest.shuffle();
    return [keepFirst, ...rest];
  }

  /// Plays [queue] starting at [startIndex]. If the requested track is
  /// already the one loaded, this resumes/keeps it in place rather than
  /// restarting playback from zero — re-tapping the same song (or the same
  /// song surfacing in a different list) never rewinds it.
  Future<void> playFromQueue(List<Track> queue, int startIndex) async {
    if (startIndex < 0 || startIndex >= queue.length) return;
    final order = state.shuffleEnabled
        ? _shuffledOrderKeeping(queue.length, startIndex)
        : _sequentialOrder(queue.length);
    // _shuffledOrderKeeping always places startIndex at position 0, but the
    // sequential order does not — find where startIndex actually landed
    // instead of assuming 0, or the wrong track plays whenever shuffle is off.
    final orderIndex = order.indexOf(startIndex);
    state = state.copyWith(queue: queue, order: order, orderIndex: orderIndex);
    await _playAtOrderIndex(orderIndex);
  }

  Future<void> playSingle(Track track) => playFromQueue([track], 0);

  /// Moves to a position within the CURRENT order/queue without rebuilding
  /// it — used by next()/previous() so shuffle order stays stable across
  /// track changes instead of re-shuffling every time.
  Future<void> _playAtOrderIndex(int newOrderIndex) async {
    if (newOrderIndex < 0 || newOrderIndex >= state.order.length) return;
    final trackIndex = state.order[newOrderIndex];
    final track = state.queue[trackIndex];
    final isSameTrack = state.currentTrack?.id == track.id;

    state = state.copyWith(orderIndex: newOrderIndex, currentTrack: track);

    if (isSameTrack) {
      if (!state.isPlaying) await _engine.play();
      return;
    }
    await _engine.open(track.filePath);
  }

  Future<void> next() async {
    if (state.order.isEmpty) return;
    var newIndex = state.orderIndex + 1;
    if (newIndex >= state.order.length) {
      if (state.repeatMode != PlayerRepeatMode.all) return;
      newIndex = 0;
    }
    await _playAtOrderIndex(newIndex);
  }

  Future<void> previous() async {
    if (state.order.isEmpty) return;
    var newIndex = state.orderIndex - 1;
    if (newIndex < 0) {
      if (state.repeatMode != PlayerRepeatMode.all) return;
      newIndex = state.order.length - 1;
    }
    await _playAtOrderIndex(newIndex);
  }

  /// Reorders the play queue (drag-to-reorder in the Queue screen). Meant
  /// for ReorderableListView's onReorderItem, which — unlike the older,
  /// now-deprecated onReorder — already adjusts newIndex for the removed
  /// item, so no manual index-shift is needed here. Keeps pointing at the
  /// same actual track afterward even though its position in the order may
  /// have changed, so reordering never skips or restarts whatever is
  /// currently playing.
  void reorderQueue(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= state.order.length) return;
    if (newIndex < 0 || newIndex > state.order.length) return;

    final newOrder = List<int>.from(state.order);
    final movedTrackIndex = newOrder.removeAt(oldIndex);
    newOrder.insert(newIndex, movedTrackIndex);

    final currentTrackIndex =
        state.orderIndex >= 0 && state.orderIndex < state.order.length ? state.order[state.orderIndex] : null;
    final newOrderIndex = currentTrackIndex != null ? newOrder.indexOf(currentTrackIndex) : state.orderIndex;

    state = state.copyWith(order: newOrder, orderIndex: newOrderIndex);
  }

  /// Toggles shuffle, regenerating the play order once (not on every track
  /// change) while keeping the currently-playing track in place.
  void toggleShuffle() {
    final enabled = !state.shuffleEnabled;
    if (state.queue.isEmpty) {
      state = state.copyWith(shuffleEnabled: enabled);
      return;
    }
    final currentTrackIndex =
        state.order.isNotEmpty && state.orderIndex >= 0 ? state.order[state.orderIndex] : 0;
    final newOrder = enabled
        ? _shuffledOrderKeeping(state.queue.length, currentTrackIndex)
        : _sequentialOrder(state.queue.length);
    final newOrderIndex = newOrder.indexOf(currentTrackIndex);
    state = state.copyWith(shuffleEnabled: enabled, order: newOrder, orderIndex: newOrderIndex);
  }

  /// Cycles off -> repeat all -> repeat one -> off, matching the common
  /// player convention.
  void cycleRepeatMode() {
    final mode = switch (state.repeatMode) {
      PlayerRepeatMode.off => PlayerRepeatMode.all,
      PlayerRepeatMode.all => PlayerRepeatMode.one,
      PlayerRepeatMode.one => PlayerRepeatMode.off,
    };
    state = state.copyWith(repeatMode: mode);
  }

  Future<void> togglePlayPause() async {
    if (state.isPlaying) {
      await _engine.pause();
    } else {
      await _engine.play();
    }
  }

  Future<void> seek(Duration position) => _engine.seek(position);

  /// Sets the OS-level system volume (not this app's internal gain) so the
  /// in-app slider and the system's own volume stay in lockstep.
  Future<void> setVolume(double volume) async {
    state = state.copyWith(volume: volume);
    await ref.read(systemVolumeControllerProvider).setVolume(volume);
  }

  /// Re-reads the system volume. Platforms without a live change stream
  /// (Linux) only pick up external changes (OS tray, etc.) when this is
  /// called — every "open Now Playing" call site does so on navigation.
  Future<void> refreshVolume() async {
    final volume = await ref.read(systemVolumeControllerProvider).getVolume();
    state = state.copyWith(volume: volume);
  }

  /// Most formats' tag readers can't get duration for free the way FLAC's
  /// STREAMINFO does — this fills it in lazily from actual playback instead,
  /// the first time a real duration becomes available, so track lists
  /// gradually learn durations just from normal listening.
  void _maybePersistDuration(Duration duration) {
    final track = state.currentTrack;
    if (track == null) return;
    if (duration <= Duration.zero) return;
    if (track.durationMs != null) return;
    if (!_durationPersistedForTrackId.add(track.id)) return;
    ref.read(libraryRepositoryProvider).setTrackDuration(track.id, duration.inMilliseconds);
  }
}

final playbackControllerProvider =
    NotifierProvider<PlaybackController, PlaybackState>(PlaybackController.new);
