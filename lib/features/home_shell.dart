import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/theme_provider.dart';
import '../widgets/themed/themed_icon.dart';
import 'albums/albums_screen.dart';
import 'library/library_screen.dart';
import 'now_playing/mini_player.dart';
import 'playlists/playlists_screen.dart';

/// Root navigation shell: Library/Albums/Playlists tabs with a persistent
/// MiniPlayer docked above the tab bar, so playback stays visible and
/// controllable no matter which tab is active.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _tabIndex = 0;

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);

    return Scaffold(
      body: IndexedStack(
        index: _tabIndex,
        children: const [
          LibraryScreen(),
          AlbumsScreen(),
          PlaylistsScreen(),
        ],
      ),
      bottomNavigationBar: Container(
        // MiniPlayer floats as its own card with margin — this background
        // is what shows through that margin, giving it visible separation
        // instead of merging flush into the nav bar below it.
        color: theme.colors.background,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const MiniPlayer(),
            NavigationBar(
              // Default NavigationBar height (80) + MiniPlayer's fixed 64
              // overflows the bottomNavigationBar slot at extreme window
              // heights — an explicit smaller height leaves enough margin.
              height: 60,
              backgroundColor: theme.colors.surface,
              selectedIndex: _tabIndex,
              onDestinationSelected: (i) => setState(() => _tabIndex = i),
              destinations: const [
                NavigationDestination(icon: ThemedIcon(ThemedIconSlot.library), label: 'Library'),
                NavigationDestination(icon: ThemedIcon(ThemedIconSlot.album), label: 'Albums'),
                NavigationDestination(icon: ThemedIcon(ThemedIconSlot.playlist), label: 'Playlists'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
