import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/library/library_providers.dart';
import '../../core/theme/theme_provider.dart';
import '../../widgets/themed/themed_card.dart';
import '../../widgets/themed/themed_icon.dart';
import '../now_playing/mini_player.dart';
import 'playlist_actions.dart';
import 'playlist_detail_screen.dart';

class PlaylistsScreen extends ConsumerWidget {
  const PlaylistsScreen({super.key});

  Future<void> _createPlaylist(BuildContext context, WidgetRef ref) async {
    final name = await promptPlaylistName(context);
    if (name != null && name.isNotEmpty) {
      await ref.read(libraryRepositoryProvider).createPlaylist(name);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    final playlistsAsync = ref.watch(playlistsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Playlists',
          style: TextStyle(color: theme.colors.textPrimary),
        ),
      ),
      body: Column(
        children: [
          const MiniPlayer(),
          Expanded(
            child: playlistsAsync.when(
              data: (playlists) {
                if (playlists.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'No playlists yet',
                          style: TextStyle(color: theme.colors.textSecondary),
                        ),
                        const SizedBox(height: 16),
                        TextButton.icon(
                          onPressed: () => _createPlaylist(context, ref),
                          icon: ThemedIcon(
                            ThemedIconSlot.playlistAdd,
                            color: theme.colors.primary,
                          ),
                          label: Text(
                            'Create Playlist',
                            style: TextStyle(color: theme.colors.primary),
                          ),
                        ),
                      ],
                    ),
                  );
                }
                return ListView.builder(
                  itemCount: playlists.length,
                  itemBuilder: (context, index) {
                    final playlist = playlists[index];
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      child: GestureDetector(
                        onSecondaryTapDown: (details) =>
                            showPlaylistContextMenu(
                              context: context,
                              ref: ref,
                              playlist: playlist,
                              position: details.globalPosition,
                            ),
                        // No right-click on touch/Android — long-press reaches the
                        // same menu so rename/delete are still possible there.
                        onLongPressStart: (details) => showPlaylistContextMenu(
                          context: context,
                          ref: ref,
                          playlist: playlist,
                          position: details.globalPosition,
                        ),
                        child: ThemedCard(
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  PlaylistDetailScreen(playlist: playlist),
                            ),
                          ),
                          child: Row(
                            children: [
                              ThemedIcon(
                                ThemedIconSlot.playlist,
                                color: theme.colors.textSecondary,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  playlist.name,
                                  style: TextStyle(
                                    color: theme.colors.textPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, stack) => Center(child: Text('Error: $err')),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        // Explicit heroTag: HomeShell keeps every tab mounted at once via
        // IndexedStack, so any two FABs sharing the default tag collide.
        heroTag: 'playlistsScreenFab',
        backgroundColor: theme.colors.primary,
        onPressed: () => _createPlaylist(context, ref),
        child: const ThemedIcon(ThemedIconSlot.playlistAdd),
      ),
    );
  }
}
