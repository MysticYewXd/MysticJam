import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/library/database.dart';
import '../../core/library/library_providers.dart';
import '../../core/theme/theme_provider.dart';
import '../../widgets/themed/themed_icon.dart';

Future<String?> promptPlaylistName(BuildContext context) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('New Playlist'),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(hintText: 'Playlist name'),
        onSubmitted: (value) => Navigator.pop(ctx, value.trim()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.pop(ctx, controller.text.trim()),
          child: const Text('Create'),
        ),
      ],
    ),
  );
}

/// Bottom sheet letting the user add [track] to an existing playlist, or
/// create a new one on the spot.
void showAddToPlaylistSheet(BuildContext context, WidgetRef ref, Track track) {
  final theme = ref.read(themeProvider);
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
                    leading: ThemedIcon(ThemedIconSlot.playlistAdd, color: theme.colors.primary),
                    title: Text('New playlist', style: TextStyle(color: theme.colors.textPrimary)),
                    onTap: () async {
                      Navigator.pop(sheetContext);
                      final name = await promptPlaylistName(context);
                      if (name != null && name.isNotEmpty) {
                        final repo = ref.read(libraryRepositoryProvider);
                        final id = await repo.createPlaylist(name);
                        await repo.addTrackToPlaylist(id, track.id);
                      }
                    },
                  ),
                  ...playlists.map(
                    (playlist) => ListTile(
                      leading: ThemedIcon(ThemedIconSlot.playlist, color: theme.colors.textSecondary),
                      title: Text(playlist.name, style: TextStyle(color: theme.colors.textPrimary)),
                      onTap: () async {
                        Navigator.pop(sheetContext);
                        await ref
                            .read(libraryRepositoryProvider)
                            .addTrackToPlaylist(playlist.id, track.id);
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
                child: Text('Error: $err', style: TextStyle(color: theme.colors.error)),
              ),
            ),
          );
        },
      );
    },
  );
}
