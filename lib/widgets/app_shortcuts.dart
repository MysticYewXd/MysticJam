import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/playback/playback_controller.dart';
import '../core/undo/last_undo_provider.dart';

/// App-wide keyboard shortcuts. Sits above the Navigator (see app.dart's
/// MaterialApp.builder) so they work on every screen, including pushed ones
/// like Now Playing.
///
///   Space            play / pause
///   Left / Right     seek -5s / +5s
///   Ctrl+Left/Right  previous / next track
///   Ctrl+Up/Down     volume +5% / -5%
///   Ctrl+Z           undo last delete
///   Media keys       play-pause / next / previous (only if the desktop
///                    passes them to the app — most hand them to MPRIS)
///
/// A plain Shortcuts binding would swallow the key even while typing in a
/// search box, so this is a Focus handler that steps aside when a text
/// field has focus (Ctrl+Z aside — the field handles its own undo first).
class AppShortcuts extends ConsumerWidget {
  final Widget child;

  const AppShortcuts({super.key, required this.child});

  static const seekStep = Duration(seconds: 5);
  static const volumeStep = 0.05;

  static bool _typingInTextField() {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null) return false;
    return context.widget is EditableText ||
        context.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  KeyEventResult _onKey(WidgetRef ref, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    final playback = ref.read(playbackControllerProvider.notifier);
    final state = ref.read(playbackControllerProvider);
    final isDown = event is KeyDownEvent;

    if (ctrl && key == LogicalKeyboardKey.keyZ) {
      if (isDown) performLastUndo(ref);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.mediaPlayPause) {
      if (isDown) playback.togglePlayPause();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.mediaTrackNext) {
      if (isDown) playback.next();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.mediaTrackPrevious) {
      if (isDown) playback.previous();
      return KeyEventResult.handled;
    }

    final isMine =
        key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight ||
        (ctrl &&
            (key == LogicalKeyboardKey.arrowUp ||
                key == LogicalKeyboardKey.arrowDown));
    if (!isMine || _typingInTextField()) return KeyEventResult.ignored;

    if (key == LogicalKeyboardKey.space) {
      if (isDown) playback.togglePlayPause();
    } else if (ctrl && key == LogicalKeyboardKey.arrowLeft) {
      if (isDown) playback.previous();
    } else if (ctrl && key == LogicalKeyboardKey.arrowRight) {
      if (isDown) playback.next();
    } else if (ctrl && key == LogicalKeyboardKey.arrowUp) {
      playback.setVolume((state.volume + volumeStep).clamp(0.0, 1.0));
    } else if (ctrl && key == LogicalKeyboardKey.arrowDown) {
      playback.setVolume((state.volume - volumeStep).clamp(0.0, 1.0));
    } else if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight) {
      final forward = key == LogicalKeyboardKey.arrowRight;
      final target = state.position + (forward ? seekStep : -seekStep);
      final max = state.duration > Duration.zero ? state.duration : target;
      playback.seek(
        target < Duration.zero ? Duration.zero : (target > max ? max : target),
      );
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (_, event) => _onKey(ref, event),
      child: child,
    );
  }
}
