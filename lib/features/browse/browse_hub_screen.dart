import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/theme/theme_provider.dart';
import '../../widgets/themed/themed_icon.dart';
import '../now_playing/mini_player.dart';
import 'grouped_browse_screen.dart';
import 'recently_played_screen.dart';

/// Landing screen for the browse features added in Phase 5 — Artists,
/// Genres, Folders, Recently Played. Kept as its own small hub (rather than
/// adding 4 more items to the Dock) so the primary navigation stays
/// uncluttered; this is the Dock's 4th destination.
class BrowseHubScreen extends ConsumerWidget {
  const BrowseHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Browse',
          style: TextStyle(color: theme.colors.textPrimary),
        ),
      ),
      body: Column(
        children: [
          const MiniPlayer(),
          Expanded(
            child: ListView(
              children: [
                ListTile(
                  leading: ThemedIcon(
                    ThemedIconSlot.artist,
                    color: theme.colors.textSecondary,
                  ),
                  title: Text(
                    'Artists',
                    style: TextStyle(color: theme.colors.textPrimary),
                  ),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => GroupedBrowseScreen(
                        title: 'Artists',
                        rowIcon: ThemedIconSlot.artist,
                        keyOf: (track) => track.artist,
                        unknownLabel: 'Unknown Artist',
                        countLabel: (n) => '$n track${n == 1 ? '' : 's'}',
                      ),
                    ),
                  ),
                ),
                ListTile(
                  leading: ThemedIcon(
                    ThemedIconSlot.genre,
                    color: theme.colors.textSecondary,
                  ),
                  title: Text(
                    'Genres',
                    style: TextStyle(color: theme.colors.textPrimary),
                  ),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => GroupedBrowseScreen(
                        title: 'Genres',
                        rowIcon: ThemedIconSlot.genre,
                        keyOf: (track) => track.genre,
                        unknownLabel: 'Unknown Genre',
                        countLabel: (n) => '$n track${n == 1 ? '' : 's'}',
                      ),
                    ),
                  ),
                ),
                ListTile(
                  leading: ThemedIcon(
                    ThemedIconSlot.folder,
                    color: theme.colors.textSecondary,
                  ),
                  title: Text(
                    'Folders',
                    style: TextStyle(color: theme.colors.textPrimary),
                  ),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => GroupedBrowseScreen(
                        title: 'Folders',
                        rowIcon: ThemedIconSlot.folder,
                        // Full parent directory as the key (uniqueness — see
                        // GroupedBrowseScreen's _Group doc comment), just the
                        // last path segment as what's actually shown.
                        keyOf: (track) => p.dirname(track.filePath),
                        displayLabel: (key) => p.basename(key),
                        unknownLabel: 'Unknown Folder',
                        countLabel: (n) => '$n track${n == 1 ? '' : 's'}',
                      ),
                    ),
                  ),
                ),
                ListTile(
                  leading: ThemedIcon(
                    ThemedIconSlot.recentlyPlayed,
                    color: theme.colors.textSecondary,
                  ),
                  title: Text(
                    'Recently Played',
                    style: TextStyle(color: theme.colors.textPrimary),
                  ),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const RecentlyPlayedScreen(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
