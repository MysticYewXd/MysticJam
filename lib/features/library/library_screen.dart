import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/library/database.dart';
import '../../core/library/library_providers.dart';
import '../../core/playback/playback_controller.dart';
import '../../core/theme/theme_provider.dart';
import '../../widgets/themed/themed_button.dart';
import '../../widgets/themed/themed_card.dart';
import '../../widgets/themed/themed_icon.dart';
import '../../widgets/themed/themed_search_bar.dart';
import '../now_playing/now_playing_screen.dart';
import '../playlists/playlist_actions.dart';
import 'track_actions.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  bool _scanning = false;
  String _query = '';

  Future<void> _pickAndScanFolder() async {
    final path = await FilePicker.getDirectoryPath();
    if (path == null) return;

    setState(() => _scanning = true);
    try {
      final scanner = ref.read(libraryScannerProvider);
      final added = await scanner.scanDirectory(path);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Added $added tracks')),
        );
      }
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  List<Track> _filter(List<Track> tracks) {
    if (_query.isEmpty) return tracks;
    final q = _query.toLowerCase();
    return tracks
        .where((t) => t.title.toLowerCase().contains(q) || (t.artist?.toLowerCase().contains(q) ?? false))
        .toList();
  }

  void _playTrack(List<Track> queue, int index) {
    ref.read(playbackControllerProvider.notifier).playFromQueue(queue, index);
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const NowPlayingScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final tracksAsync = ref.watch(tracksProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text('Library', style: TextStyle(color: theme.colors.textPrimary)),
        actions: [
          IconButton(
            tooltip: 'Add Folder',
            icon: _scanning
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: theme.colors.textPrimary),
                  )
                : const ThemedIcon(ThemedIconSlot.folderAdd),
            onPressed: _scanning ? null : _pickAndScanFolder,
          ),
          IconButton(
            icon: const ThemedIcon(ThemedIconSlot.settings),
            onPressed: () {},
          ),
        ],
      ),
      body: tracksAsync.when(
        data: (allTracks) {
          if (allTracks.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'No tracks yet',
                    style: TextStyle(color: theme.colors.textSecondary),
                  ),
                  const SizedBox(height: 16),
                  ThemedButton(
                    label: _scanning ? 'Scanning...' : 'Add Folder',
                    icon: theme.icons.folderAdd,
                    onPressed: _scanning ? null : _pickAndScanFolder,
                  ),
                ],
              ),
            );
          }

          final filtered = _filter(allTracks);

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                child: ThemedSearchBar(
                  hintText: 'Search library',
                  onChanged: (value) => setState(() => _query = value),
                ),
              ),
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Text('No matches', style: TextStyle(color: theme.colors.textSecondary)),
                      )
                    : ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final track = filtered[index];
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            child: GestureDetector(
                              onSecondaryTapDown: (details) => showTrackContextMenu(
                                context: context,
                                ref: ref,
                                track: track,
                                position: details.globalPosition,
                                onPlay: () => _playTrack(filtered, index),
                              ),
                              child: ThemedCard(
                                // Queue is the currently filtered/visible list, so
                                // next/previous walk through what's on screen —
                                // and re-tapping the already-playing track just
                                // resumes it instead of restarting from zero.
                                onTap: () => _playTrack(filtered, index),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(track.title, style: TextStyle(color: theme.colors.textPrimary)),
                                          if (track.artist != null)
                                            Text(
                                              track.artist!,
                                              style: TextStyle(color: theme.colors.textSecondary, fontSize: 12),
                                            ),
                                        ],
                                      ),
                                    ),
                                    Text(
                                      track.format.toUpperCase(),
                                      style: TextStyle(color: theme.colors.textSecondary, fontSize: 11),
                                    ),
                                    IconButton(
                                      icon: ThemedIcon(ThemedIconSlot.playlistAdd, color: theme.colors.textSecondary),
                                      onPressed: () => showAddToPlaylistSheet(context, ref, track),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err')),
      ),
    );
  }
}
