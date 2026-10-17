import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The most recent deletion's undo action, if it hasn't been consumed yet —
/// set right after a track/playlist delete (alongside the snackbar's own
/// Undo button, see track_actions.dart/playlist_actions.dart), and read by
/// the app-wide Ctrl+Z shortcut (see widgets/app_shortcuts.dart) so undo isn't only reachable
/// by clicking the snackbar before it disappears.
final lastUndoActionProvider = StateProvider<VoidCallback?>((ref) => null);

/// Runs the pending undo action (if any) and clears it, so Ctrl+Z twice in a
/// row doesn't restore the same deleted item again — a second press with
/// nothing new to undo is simply a no-op.
void performLastUndo(WidgetRef ref) {
  final action = ref.read(lastUndoActionProvider);
  if (action == null) return;
  ref.read(lastUndoActionProvider.notifier).state = null;
  action();
}
