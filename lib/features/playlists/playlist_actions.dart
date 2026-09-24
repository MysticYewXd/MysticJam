import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/library/database.dart';
import '../../core/library/library_providers.dart';
import '../../core/theme/theme_provider.dart';
import '../../core/undo/last_undo_provider.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/themed/themed_icon.dart';

Future<String?> promptPlaylistName(
  BuildContext context, {
  String title = 'New Playlist',
  String? initialValue,
  String confirmLabel = 'Create',
}) {
  final controller = TextEditingController(text: initialValue);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(hintText: 'Playlist name'),
        onSubmitted: (value) => Navigator.pop(ctx, value.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, controller.text.trim()),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
}

enum _PlaylistMenuAction { rename, delete }

/// Deletes [playlist], capturing its track order first so the snackbar's
/// Undo action can recreate it (as a new playlist — its old id isn't
/// reused, but with the same name and songs in the same order).
Future<void> _deletePlaylistWithUndo(
  BuildContext context,
  WidgetRef ref,
  Playlist playlist,
) async {
  final repo = ref.read(libraryRepositoryProvider);
  final trackIds = await repo.getPlaylistTrackIdsInOrder(playlist.id);
  await repo.deletePlaylist(playlist.id);
  if (!context.mounted) return;

  void undo() => repo.restorePlaylist(playlist.name, trackIds);
  ref.read(lastUndoActionProvider.notifier).state = undo;

  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        content: Text('Deleted playlist "${playlist.name}"'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => performLastUndo(ref),
        ),
      ),
    );
}

/// Right-click (desktop) context menu for a playlist: Rename / Delete.
///
/// Holding Shift while right-clicking skips the menu and the confirmation
/// dialog entirely, deleting the playlist immediately — a fast path for
/// anyone who doesn't want to confirm every single deletion. Undo is always
/// available on the snackbar either way.
void showPlaylistContextMenu({
  required BuildContext context,
  required WidgetRef ref,
  required Playlist playlist,
  required Offset position,
}) {
  if (HardwareKeyboard.instance.isShiftPressed) {
    _deletePlaylistWithUndo(context, ref, playlist);
    return;
  }

  final theme = ref.read(themeProvider);
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;

  showMenu<_PlaylistMenuAction>(
    context: context,
    color: theme.colors.surface,
    position: RelativeRect.fromRect(
      position & const Size(1, 1),
      Offset.zero & overlay.size,
    ),
    items: [
      PopupMenuItem(
        value: _PlaylistMenuAction.rename,
        child: Text(
          'Rename',
          style: TextStyle(color: theme.colors.textPrimary),
        ),
      ),
      PopupMenuItem(
        value: _PlaylistMenuAction.delete,
        child: Text(
          'Delete Playlist',
          style: TextStyle(color: theme.colors.error),
        ),
      ),
    ],
  ).then((action) async {
    if (!context.mounted || action == null) return;
    switch (action) {
      case _PlaylistMenuAction.rename:
        final name = await promptPlaylistName(
          context,
          title: 'Rename Playlist',
          initialValue: playlist.name,
          confirmLabel: 'Rename',
        );
        if (name != null && name.isNotEmpty) {
          await ref
              .read(libraryRepositoryProvider)
              .renamePlaylist(playlist.id, name);
        }
      case _PlaylistMenuAction.delete:
        if (!context.mounted) return;
        final confirmed = await confirmDestructiveAction(
          context,
          ref,
          title: 'Delete Playlist?',
          message:
              '"${playlist.name}" will be deleted. Songs stay in your library.',
        );
        if (confirmed && context.mounted) {
          await _deletePlaylistWithUndo(context, ref, playlist);
        }
    }
  });
}

/// Bottom sheet letting the user add [tracks] (one or many) to an existing
/// playlist, or create a new one on the spot.
void showAddToPlaylistSheet(
  BuildContext context,
  WidgetRef ref,
  List<Track> tracks,
) {
  final theme = ref.read(themeProvider);
  final trackIds = tracks.map((t) => t.id).toList();
  showModalBottomSheet(
    context: context,
    backgroundColor: theme.colors.surface,
    builder: (sheetContext) {
      return Consumer(
        builder: (context, ref, _) {
          final playlistsAsync = ref.watch(playlistsProvider);
          return SafeArea(
            child: playlistsAsync.when(
              data: (playlists) => ListView(
                shrinkWrap: true,
                children: [
                  ListTile(
                    leading: ThemedIcon(
                      ThemedIconSlot.playlistAdd,
                      color: theme.colors.primary,
                    ),
                    title: Text(
                      'New playlist',
                      style: TextStyle(color: theme.colors.textPrimary),
                    ),
                    onTap: () async {
                      Navigator.pop(sheetContext);
                      final name = await promptPlaylistName(context);
                      if (name != null && name.isNotEmpty) {
                        final repo = ref.read(libraryRepositoryProvider);
                        final id = await repo.createPlaylist(name);
                        await repo.addTracksToPlaylist(id, trackIds);
                      }
                    },
                  ),
                  ...playlists.map(
                    (playlist) => ListTile(
                      leading: ThemedIcon(
                        ThemedIconSlot.playlist,
                        color: theme.colors.textSecondary,
                      ),
                      title: Text(
                        playlist.name,
                        style: TextStyle(color: theme.colors.textPrimary),
                      ),
                      onTap: () async {
                        Navigator.pop(sheetContext);
                        await ref
                            .read(libraryRepositoryProvider)
                            .addTracksToPlaylist(playlist.id, trackIds);
                      },
                    ),
                  ),
                ],
              ),
              loading: () => const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (err, stack) => Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Error: $err',
                  style: TextStyle(color: theme.colors.error),
                ),
              ),
            ),
          );
        },
      );
    },
  );
}
