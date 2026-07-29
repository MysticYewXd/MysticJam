import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/theme_provider.dart';
import '../widgets/themed/themed_icon.dart';
import 'library/library_screen.dart';
import 'now_playing/mini_player.dart';
import 'playlists/playlists_screen.dart';

/// Root navigation shell: Library/Playlists tabs with a persistent
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
          PlaylistsScreen(),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const MiniPlayer(),
          NavigationBar(
            backgroundColor: theme.colors.surface,
            selectedIndex: _tabIndex,
            onDestinationSelected: (i) => setState(() => _tabIndex = i),
            destinations: const [
              NavigationDestination(icon: ThemedIcon(ThemedIconSlot.library), label: 'Library'),
              NavigationDestination(icon: ThemedIcon(ThemedIconSlot.playlist), label: 'Playlists'),
            ],
          ),
        ],
      ),
    );
  }
}
