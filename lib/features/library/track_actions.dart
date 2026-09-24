import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/library/database.dart';
import '../../core/library/library_providers.dart';
import '../../core/theme/theme_provider.dart';
import '../../core/undo/last_undo_provider.dart';
import '../../widgets/confirm_dialog.dart';
import '../playlists/playlist_actions.dart';

/// Deletes [track], capturing which playlists it belonged to first so the
/// snackbar's Undo action can put it back (as a new row — its old id isn't
/// reused, but it lands back in the same playlists). Shared by both the
/// Shift+right-click instant-delete path and the confirmed "Remove from
/// Library" menu action.
Future<void> _deleteTrackWithUndo(
  BuildContext context,
  WidgetRef ref,
  Track track,
) async {
  final repo = ref.read(libraryRepositoryProvider);
  final playlistIds = await repo.getPlaylistIdsForTrack(track.id);
  await repo.deleteTrack(track.id);
  if (!context.mounted) return;

  void undo() => repo.restoreTrack(track, playlistIds);
  // Also reachable via Ctrl+Z (see last_undo_provider.dart/app.dart) — the
  // snackbar button and the shortcut both consume the same pending action.
  ref.read(lastUndoActionProvider.notifier).state = undo;

  // clearSnackBars (not just showSnackBar) so rapid successive deletes
  // replace the message immediately instead of queuing behind each
  // other's multi-second display duration.
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        content: Text('Deleted "${track.title}"'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => performLastUndo(ref),
        ),
      ),
    );
}

/// Right-click (desktop) context menu for a track row: Play / Add to
/// Playlist / Remove, in the same spot Apple Music puts theirs. Pass
/// [onRemoveFromPlaylist] when the row is inside a playlist (not the plain
/// Library) to also offer removing just from that playlist.
///
/// Holding Shift while right-clicking skips the menu and the confirmation
/// dialog entirely, deleting the track from the library immediately — a
/// fast path for anyone who doesn't want to confirm every single deletion.
/// Undo is always available on the snackbar either way.
void showTrackContextMenu({
  required BuildContext context,
  required WidgetRef ref,
  required Track track,
  required Offset position,
  required VoidCallback onPlay,
  VoidCallback? onRemoveFromPlaylist,
}) {
  if (HardwareKeyboard.instance.isShiftPressed) {
    _deleteTrackWithUndo(context, ref, track);
    return;
  }

  final theme = ref.read(themeProvider);
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;

  showMenu<_TrackMenuAction>(
    context: context,
    color: theme.colors.surface,
    position: RelativeRect.fromRect(
      position & const Size(1, 1),
      Offset.zero & overlay.size,
    ),
    items: [
      PopupMenuItem(
        value: _TrackMenuAction.play,
        child: Text('Play', style: TextStyle(color: theme.colors.textPrimary)),
      ),
      PopupMenuItem(
        value: _TrackMenuAction.addToPlaylist,
        child: Text(
          'Add to Playlist…',
          style: TextStyle(color: theme.colors.textPrimary),
        ),
      ),
      if (onRemoveFromPlaylist != null)
        PopupMenuItem(
          value: _TrackMenuAction.removeFromPlaylist,
          child: Text(
            'Remove from Playlist',
            style: TextStyle(color: theme.colors.textPrimary),
          ),
        ),
      PopupMenuItem(
        value: _TrackMenuAction.removeFromLibrary,
        child: Text(
          'Remove from Library',
          style: TextStyle(color: theme.colors.error),
        ),
      ),
    ],
  ).then((action) async {
    if (!context.mounted || action == null) return;
    switch (action) {
      case _TrackMenuAction.play:
        onPlay();
      case _TrackMenuAction.addToPlaylist:
        showAddToPlaylistSheet(context, ref, [track]);
      case _TrackMenuAction.removeFromPlaylist:
        onRemoveFromPlaylist?.call();
      case _TrackMenuAction.removeFromLibrary:
        final confirmed = await confirmDestructiveAction(
          context,
          ref,
          title: 'Remove from Library?',
          message:
              '"${track.title}" will be removed from your library and any playlists. The file on disk is not deleted.',
        );
        if (confirmed && context.mounted) {
          await _deleteTrackWithUndo(context, ref, track);
        }
    }
  });
}

enum _TrackMenuAction {
  play,
  addToPlaylist,
  removeFromPlaylist,
  removeFromLibrary,
}
