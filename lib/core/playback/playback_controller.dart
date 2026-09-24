import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../audio/audio_engine.dart';
import '../audio/audio_engine_provider.dart';
import '../audio/system_volume_provider.dart';
import '../library/database.dart';
import '../library/library_providers.dart';
import '../logging/app_log.dart';
import '../settings/app_settings.dart';

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

  /// Message from the engine's error stream (bad/missing/corrupt file,
  /// unsupported codec, etc.) for whatever's currently loaded — null means
  /// no error. Cleared automatically the next time a different track starts
  /// opening (see PlaybackController._playAtOrderIndex), so a stale error
  /// never lingers once playback has actually moved on.
  final String? errorMessage;

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
    this.errorMessage,
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
    // Nullable-setter idiom (same as ThemeLibraryState.copyWith's
    // activeThemeId) since this is the one field that genuinely needs to be
    // clearable back to null — plain `errorMessage ?? this.errorMessage`
    // could never clear an existing error.
    String? Function()? errorMessage,
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
      errorMessage: errorMessage != null ? errorMessage() : this.errorMessage,
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
  StreamSubscription<String>? _errorSub;

  // Tracks whose real duration we've already written this session, so a
  // format without a cheap tag-based duration (i.e. anything but FLAC)
  // doesn't get the same value re-persisted on every durationStream tick.
  final Set<int> _durationPersistedForTrackId = {};

  // Captured once in build() rather than calling ref.read(appSettingsProvider
  // .notifier) at each use site — reading a *different* provider from inside
  // an onDispose callback is unsafe (Riverpod doesn't guarantee dispose
  // order between providers during container teardown, and this exact
  // pattern threw "Tried to read a provider from a ProviderContainer that
  // was already disposed" in tests). Holding a plain reference sidesteps
  // that entirely — the notifier object itself is still valid to call
  // methods on even once its own provider is disposing.
  late final AppSettingsNotifier _settings;

  AudioEngine get _engine => ref.read(audioEngineProvider);

  @override
  PlaybackState build() {
    _settings = ref.read(appSettingsProvider.notifier);

    _positionSub = _engine.positionStream.listen((pos) {
      state = state.copyWith(position: pos);
      final track = state.currentTrack;
      if (track != null) {
        _settings.updatePosition(track.id, pos.inMilliseconds);
      }
    });
    _durationSub = _engine.durationStream.listen((dur) {
      state = state.copyWith(duration: dur);
      _maybePersistDuration(dur);
    });
    _playingSub = _engine.playingStream.listen((playing) {
      state = state.copyWith(isPlaying: playing);
      // "Save immediately on pause" — position ticks are throttled (see
      // AppSettingsNotifier.updatePosition), but a pause is a discrete,
      // infrequent event where the user very plausibly is about to close
      // the app, so it bypasses the throttle.
      if (!playing) {
        _settings.flushPositionNow();
      }
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
    // Previously unhandled — the engine already reports bad/missing/corrupt
    // files here (see MediaKitAudioEngine.errorStream), but nothing was
    // listening, so a failed open() silently did nothing visible. Surfacing
    // it as state lets the UI show something instead of a track that just
    // never starts.
    _errorSub = _engine.errorStream.listen((message) {
      AppLog.warn('playback', 'engine error', {'detail': message});
      state = state.copyWith(errorMessage: () => message);
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
      _errorSub?.cancel();
      // Best-effort final write — this can't be awaited from a synchronous
      // dispose callback, so it's a race against process exit. Losing the
      // last few seconds of position on a hard/forced quit is an accepted
      // gap (see Phase 2 report), not something solvable without an
      // OS-level "about to quit" hook, which is out of scope here.
      _settings.flushPositionNow();
    });

    // Fire-and-forget: build() must return PlaybackState synchronously, so
    // restoring shuffle/repeat/last-track happens asynchronously once
    // AppSettingsNotifier's disk read completes, rather than blocking
    // startup on it.
    _attemptResume();

    return const PlaybackState();
  }

  /// Restores shuffle/repeat immediately once settings have loaded, then —
  /// if there's a remembered last track — attempts to resume it. Does NOT
  /// resume if the track's row was deleted from the library or its file no
  /// longer exists on disk, and clears the stale remembered track in that
  /// case so future launches stop trying. Restores only the single track
  /// (queue: [track]) rather than whatever multi-track context it was
  /// originally played from (a playlist, the whole library, etc.) — that
  /// context isn't persisted, since doing so would mean tracking entire
  /// track-id lists just for this; next()/previous() have nothing to move
  /// to until the user starts a new queue normally.
  Future<void> _attemptResume() async {
    await _settings.ready;
    final settings = ref.read(appSettingsProvider);

    state = state.copyWith(
      shuffleEnabled: settings.shuffleEnabled,
      repeatMode: _parseRepeatMode(settings.repeatMode),
    );

    final trackId = settings.lastTrackId;
    if (trackId == null) return;

    final track = await ref
        .read(libraryRepositoryProvider)
        .getTrackById(trackId);
    if (track == null || !await File(track.filePath).exists()) {
      await _settings.clearLastTrack();
      return;
    }

    final maxMs = track.durationMs;
    final clampedMs = maxMs != null
        ? settings.lastPositionMs.clamp(0, maxMs)
        : (settings.lastPositionMs < 0 ? 0 : settings.lastPositionMs);

    state = state.copyWith(
      currentTrack: track,
      queue: [track],
      order: const [0],
      orderIndex: 0,
      position: Duration(milliseconds: clampedMs),
    );
    // play: false — resuming on launch should never start audio
    // unexpectedly; the track is loaded and seeked, ready for the user to
    // press play themselves.
    await _engine.open(track.filePath, play: false);
    await _engine.seek(Duration(milliseconds: clampedMs));
  }

  PlayerRepeatMode _parseRepeatMode(String value) {
    for (final mode in PlayerRepeatMode.values) {
      if (mode.name == value) return mode;
    }
    return PlayerRepeatMode.off;
  }

  List<int> _sequentialOrder(int length) =>
      List<int>.generate(length, (i) => i);

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
    // Clear any stale error from a previous track before this one has a
    // chance to report its own — a fresh open() attempt should never keep
    // showing an error from something else entirely.
    state = state.copyWith(errorMessage: () => null);
    // "Save immediately on track change" — fire-and-forget, no need to
    // block opening the track on this write completing.
    unawaited(_settings.recordTrackStarted(track.id));
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
        state.orderIndex >= 0 && state.orderIndex < state.order.length
        ? state.order[state.orderIndex]
        : null;
    final newOrderIndex = currentTrackIndex != null
        ? newOrder.indexOf(currentTrackIndex)
        : state.orderIndex;

    state = state.copyWith(order: newOrder, orderIndex: newOrderIndex);
  }

  /// Removes the track at [orderPosition] — a position within the play
  /// order, same addressing as [reorderQueue], not a raw index into
  /// [PlaybackState.queue]. If it's the currently playing track, playback
  /// automatically advances to whatever now sits at that position (the
  /// track that was next, since removal shifts everything after it back by
  /// one slot) — or stops entirely if the queue becomes empty. Removing any
  /// other track just adjusts [PlaybackState.orderIndex] so playback keeps
  /// pointing at the same track it already was.
  ///
  /// Added for Phase 1 test coverage — the prompt this was written against
  /// asked for "removing the currently playing track" tests, but no
  /// queue-removal method existed yet; this is the minimal one needed for
  /// that to mean anything. No UI calls this yet (the Queue screen only
  /// supports reordering).
  Future<void> removeFromQueue(int orderPosition) async {
    if (orderPosition < 0 || orderPosition >= state.order.length) return;

    final removingCurrent = orderPosition == state.orderIndex;
    final newOrder = List<int>.from(state.order)..removeAt(orderPosition);

    if (newOrder.isEmpty) {
      await _engine.stop();
      state = const PlaybackState();
      await _settings.clearLastTrack();
      return;
    }

    final int newOrderIndex;
    if (removingCurrent) {
      // Whatever was at the next position now sits at this same slot index,
      // since removeAt already shifted everything after it back by one —
      // wrap to the start if we removed the last position.
      newOrderIndex = orderPosition < newOrder.length ? orderPosition : 0;
    } else if (orderPosition < state.orderIndex) {
      newOrderIndex = state.orderIndex - 1;
    } else {
      newOrderIndex = state.orderIndex;
    }

    state = state.copyWith(order: newOrder, orderIndex: newOrderIndex);
    if (removingCurrent) {
      await _playAtOrderIndex(newOrderIndex);
    }
  }

  /// Toggles shuffle, regenerating the play order once (not on every track
  /// change) while keeping the currently-playing track in place.
  void toggleShuffle() {
    final enabled = !state.shuffleEnabled;
    unawaited(_settings.setShuffleEnabled(enabled));
    if (state.queue.isEmpty) {
      state = state.copyWith(shuffleEnabled: enabled);
      return;
    }
    final currentTrackIndex = state.order.isNotEmpty && state.orderIndex >= 0
        ? state.order[state.orderIndex]
        : 0;
    final newOrder = enabled
        ? _shuffledOrderKeeping(state.queue.length, currentTrackIndex)
        : _sequentialOrder(state.queue.length);
    final newOrderIndex = newOrder.indexOf(currentTrackIndex);
    state = state.copyWith(
      shuffleEnabled: enabled,
      order: newOrder,
      orderIndex: newOrderIndex,
    );
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
    unawaited(_settings.setRepeatMode(mode.name));
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
    ref
        .read(libraryRepositoryProvider)
        .setTrackDuration(track.id, duration.inMilliseconds);
  }
}

final playbackControllerProvider =
    NotifierProvider<PlaybackController, PlaybackState>(PlaybackController.new);
