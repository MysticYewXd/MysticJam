import 'package:flutter/services.dart';

/// Talks to the native window (linux/runner/my_application.cc).
const appWindowChannel = MethodChannel('com.musicplayer.music_player/window');

/// Brings the app window to the front — e.g. when the desktop's media widget
/// asks MPRIS to "Raise" the player. Never throws: with no native side
/// (other platforms, tests) it simply does nothing.
Future<void> raiseAppWindow() async {
  try {
    await appWindowChannel.invokeMethod<void>('raise');
  } catch (_) {
    // MissingPluginException or PlatformException: nothing to raise.
  }
}
