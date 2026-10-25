import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../playback/playback_controller.dart';

/// Talks to Windows' media controls (windows/runner/media_controls.cpp).
const mediaControlsChannel = MethodChannel(
  'com.musicplayer.music_player/media_controls',
);

/// Whether to run the Windows media controls — overridden in tests, which
/// run on Linux.
@visibleForTesting
final windowsMediaControlsEnabledProvider = Provider<bool>(
  (_) => Platform.isWindows,
);

/// What Windows' media flyout shows for [s].
@visibleForTesting
Map<String, Object?> mediaControlsUpdate(PlaybackState s) {
  final t = s.currentTrack;
  return {
    'hasTrack': t != null,
    'title': t?.title ?? '',
    'artist': t?.artist ?? '',
    'album': t?.album ?? '',
    'artPath': t?.albumArtPath ?? '',
    'playing': s.isPlaying,
    'canNext': s.hasNext,
    'canPrevious': s.hasPrevious,
    'positionMs': s.position.inMilliseconds,
    'durationMs': s.duration.inMilliseconds,
  };
}

/// Shows playback in Windows' media flyout and on the media keys (the
/// Windows side of what mpris.dart does on Linux). Sends an update when the
/// song, play state or next/previous change; position ticks alone are not
/// sent, as they arrive several times a second. Windows only; elsewhere, or
/// with no native side, it does nothing.
final windowsMediaControlsProvider = Provider<void>((ref) {
  if (!ref.watch(windowsMediaControlsEnabledProvider)) return;
  final controller = ref.read(playbackControllerProvider.notifier);

  Future<void> send(PlaybackState s) async {
    try {
      await mediaControlsChannel.invokeMethod<void>(
        'update',
        mediaControlsUpdate(s),
      );
    } catch (_) {
      // MissingPluginException or PlatformException: no media controls.
    }
  }

  ref.listen(
    playbackControllerProvider.select(
      (s) =>
          (s.currentTrack, s.isPlaying, s.hasNext, s.hasPrevious, s.duration),
    ),
    (_, _) => send(ref.read(playbackControllerProvider)),
    fireImmediately: true,
  );

  mediaControlsChannel.setMethodCallHandler((call) async {
    final s = ref.read(playbackControllerProvider);
    switch (call.method) {
      case 'button':
        switch (call.arguments) {
          case 'play':
            if (!s.isPlaying && s.currentTrack != null) {
              await controller.togglePlayPause();
            }
          case 'pause' || 'stop':
            if (s.isPlaying) await controller.togglePlayPause();
          case 'next':
            if (s.hasNext) await controller.next();
          case 'previous':
            if (s.hasPrevious) await controller.previous();
        }
      case 'seek':
        final ms = call.arguments;
        if (ms is int && s.currentTrack != null) {
          await controller.seek(Duration(milliseconds: ms));
        }
    }
  });
  ref.onDispose(() => mediaControlsChannel.setMethodCallHandler(null));
});
