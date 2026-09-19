import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../widgets/themed/dock.dart';
import '../widgets/themed/themed_icon.dart';
import 'albums/albums_screen.dart';
import 'browse/browse_hub_screen.dart';
import 'library/library_screen.dart';
import 'playlists/playlists_screen.dart';

/// Root navigation shell: Library/Albums/Playlists/Browse tabs over a
/// magnifying Dock (macOS-style — icons grow as the mouse passes near them;
/// see widgets/themed/dock.dart). Each tab shows the MiniPlayer at the top
/// of its own body (under the search bar where there is one) so playback
/// stays visible and controllable no matter which tab is active.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _tabIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Stack instead of bottomNavigationBar — a real macOS dock floats
      // directly over the desktop with content scrolling underneath, not
      // sitting in its own flat-colored strip. Using bottomNavigationBar
      // meant wrapping the dock in a solid Container just to keep it
      // separated from the Scaffold body, and that container's edge is
      // exactly what read as an unwanted bar under the dock.
      body: Stack(
        children: [
          IndexedStack(
            index: _tabIndex,
            children: const [
              LibraryScreen(),
              AlbumsScreen(),
              PlaylistsScreen(),
              BrowseHubScreen(),
            ],
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Dock(
                      items: [
                        DockItem(
                          slot: ThemedIconSlot.library,
                          label: 'Library',
                          selected: _tabIndex == 0,
                          onTap: () => setState(() => _tabIndex = 0),
                        ),
                        DockItem(
                          slot: ThemedIconSlot.album,
                          label: 'Albums',
                          selected: _tabIndex == 1,
                          onTap: () => setState(() => _tabIndex = 1),
                        ),
                        DockItem(
                          slot: ThemedIconSlot.playlist,
                          label: 'Playlists',
                          selected: _tabIndex == 2,
                          onTap: () => setState(() => _tabIndex = 2),
                        ),
                        DockItem(
                          slot: ThemedIconSlot.browse,
                          label: 'Browse',
                          selected: _tabIndex == 3,
                          onTap: () => setState(() => _tabIndex = 3),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
