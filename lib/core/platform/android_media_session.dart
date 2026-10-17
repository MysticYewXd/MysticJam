import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart' as svc;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../playback/playback_controller.dart';

/// Android's counterpart to the Linux MPRIS bridge (see mpris.dart): mirrors
/// playback into an Android media session via audio_service, which gives
/// the lock-screen / notification controls, Bluetooth and headset buttons,
/// and the foreground service that keeps playback alive in the background.
///
/// Like MprisObject it reaches [PlaybackController] only through the two
/// accessors it is given, so it can be tested without a platform channel.
class MysticJamAudioHandler extends svc.BaseAudioHandler with svc.SeekHandler {
  final PlaybackState Function() _state;
  final PlaybackController Function() _controller;

  MysticJamAudioHandler(this._state, this._controller);

  static svc.AudioServiceRepeatMode repeatModeOf(PlayerRepeatMode m) =>
      switch (m) {
        PlayerRepeatMode.off => svc.AudioServiceRepeatMode.none,
        PlayerRepeatMode.one => svc.AudioServiceRepeatMode.one,
        PlayerRepeatMode.all => svc.AudioServiceRepeatMode.all,
      };

  static svc.MediaItem? mediaItemFor(PlaybackState s) {
    final t = s.currentTrack;
    if (t == null) return null;
    final known = t.durationMs == null
        ? null
        : Duration(milliseconds: t.durationMs!);
    return svc.MediaItem(
      id: '${t.id}',
      title: t.title,
      artist: t.artist,
      album: t.album,
      duration: s.duration > Duration.zero ? s.duration : known,
      artUri: t.albumArtPath == null ? null : Uri.file(t.albumArtPath!),
    );
  }

  static svc.PlaybackState playbackStateFor(PlaybackState s) {
    final controls = [
      if (s.hasPrevious) svc.MediaControl.skipToPrevious,
      s.isPlaying ? svc.MediaControl.pause : svc.MediaControl.play,
      if (s.hasNext) svc.MediaControl.skipToNext,
    ];
    return svc.PlaybackState(
      controls: controls,
      systemActions: const {svc.MediaAction.seek},
      androidCompactActionIndices: [
        for (var i = 0; i < controls.length; i++) i,
      ],
      // Idle tells audio_service there is nothing to show, which drops the
      // notification and lets the foreground service stop.
      processingState: s.currentTrack == null
          ? svc.AudioProcessingState.idle
          : svc.AudioProcessingState.ready,
      playing: s.isPlaying,
      updatePosition: s.position,
      repeatMode: repeatModeOf(s.repeatMode),
      shuffleMode: s.shuffleEnabled
          ? svc.AudioServiceShuffleMode.all
          : svc.AudioServiceShuffleMode.none,
    );
  }

  /// Everything the session shows except position, which Android
  /// extrapolates on its own from the last update — the same reason MPRIS
  /// leaves Position out of PropertiesChanged.
  static Object _signature(PlaybackState s) => (
    s.currentTrack?.id,
    s.isPlaying,
    s.duration,
    s.repeatMode,
    s.shuffleEnabled,
    s.hasNext,
    s.hasPrevious,
  );

  Object? _lastSignature;

  /// Pushes [s] to the session when something visible changed, or when the
  /// position drifted from where Android would extrapolate it (a seek).
  void sync(PlaybackState s) {
    final signature = _signature(s);
    final drift = (playbackState.value.position - s.position).abs();
    if (signature == _lastSignature && drift < const Duration(seconds: 2)) {
      return;
    }
    if (signature != _lastSignature) mediaItem.add(mediaItemFor(s));
    _lastSignature = signature;
    playbackState.add(playbackStateFor(s));
  }

  @override
  Future<void> play() async {
    final s = _state();
    if (!s.isPlaying && s.currentTrack != null) {
      await _controller().togglePlayPause();
    }
  }

  @override
  Future<void> pause() async {
    if (_state().isPlaying) await _controller().togglePlayPause();
  }

  @override
  Future<void> stop() async {
    await pause();
    if (_state().currentTrack != null) await _controller().seek(Duration.zero);
  }

  @override
  Future<void> seek(Duration position) => _controller().seek(position);

  @override
  Future<void> skipToNext() => _controller().next();

  @override
  Future<void> skipToPrevious() => _controller().previous();

  @override
  Future<void> setShuffleMode(svc.AudioServiceShuffleMode shuffleMode) async {
    final want = shuffleMode != svc.AudioServiceShuffleMode.none;
    if (want != _state().shuffleEnabled) _controller().toggleShuffle();
  }

  @override
  Future<void> setRepeatMode(svc.AudioServiceRepeatMode repeatMode) async {
    // The controller only cycles off -> all -> one; at most 2 steps.
    for (
      var i = 0;
      i < 3 && repeatModeOf(_state().repeatMode) != repeatMode;
      i++
    ) {
      _controller().cycleRepeatMode();
    }
  }
}

/// Starts the Android media session for as long as the app runs. Android
/// only; if audio_service fails to start, playback still works in the
/// foreground — the session is a convenience, never a reason to fail.
final androidMediaSessionProvider = Provider<void>((ref) {
  if (!Platform.isAndroid) return;
  final handler = MysticJamAudioHandler(
    () => ref.read(playbackControllerProvider),
    () => ref.read(playbackControllerProvider.notifier),
  );

  () async {
    try {
      await svc.AudioService.init(
        builder: () => handler,
        config: const svc.AudioServiceConfig(
          androidNotificationChannelId: 'com.musicplayer.music_player.playback',
          androidNotificationChannelName: 'Playback',
          // Stay in the foreground while paused: Android 12+ refuses to
          // restart a foreground service from the background, which would
          // break resuming from the lock screen or a headset button.
          androidStopForegroundOnPause: false,
        ),
      );
    } catch (_) {
      return;
    }
    handler.sync(ref.read(playbackControllerProvider));
    ref.listen(playbackControllerProvider, (_, next) => handler.sync(next));
  }();
});
