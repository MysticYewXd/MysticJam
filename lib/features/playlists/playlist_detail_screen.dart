import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format_duration.dart';
import '../../core/library/database.dart';
import '../../core/library/library_providers.dart';
import '../../core/playback/playback_controller.dart';
import '../../core/theme/theme_provider.dart';
import '../../widgets/themed/themed_icon.dart';
import '../../widgets/themed/themed_search_bar.dart';
import '../library/track_actions.dart';
import '../now_playing/mini_player.dart';
import '../now_playing/now_playing_screen.dart';
import 'add_tracks_to_playlist_screen.dart';

class PlaylistDetailScreen extends ConsumerStatefulWidget {
  final Playlist playlist;

  const PlaylistDetailScreen({super.key, required this.playlist});

  @override
  ConsumerState<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends ConsumerState<PlaylistDetailScreen> {
  String _query = '';

  List<Track> _filter(List<Track> tracks) {
    if (_query.isEmpty) return tracks;
    final q = _query.toLowerCase();
    return tracks
        .where((t) => t.title.toLowerCase().contains(q) || (t.artist?.toLowerCase().contains(q) ?? false))
        .toList();
  }

  void _playTrack(List<Track> fullQueue, Track track) {
    // Queue the FULL (unfiltered) playlist so next/previous walk the whole
    // playlist regardless of an active search filter.
    final fullIndex = fullQueue.indexOf(track);
    final controller = ref.read(playbackControllerProvider.notifier);
    controller.playFromQueue(fullQueue, fullIndex);
    controller.refreshVolume();
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const NowPlayingScreen()),
    );
  }

  // onReorderItem (unlike the older, now-deprecated onReorder) already
  // adjusts newIndex for the removed item, so no manual index-shift needed.
  void _reorder(List<Track> tracks, int oldIndex, int newIndex) {
    final ids = tracks.map((t) => t.id).toList();
    final movedId = ids.removeAt(oldIndex);
    ids.insert(newIndex, movedId);
    ref.read(libraryRepositoryProvider).setPlaylistTrackOrder(widget.playlist.id, ids);
  }

  Widget _trackTile(BuildContext context, Track track, List<Track> fullQueue) {
    final theme = ref.watch(themeProvider);
    return GestureDetector(
      key: ValueKey(track.id),
      onSecondaryTapDown: (details) => showTrackContextMenu(
        context: context,
        ref: ref,
        track: track,
        position: details.globalPosition,
        onPlay: () => _playTrack(fullQueue, track),
        onRemoveFromPlaylist: () =>
            ref.read(libraryRepositoryProvider).removeTrackFromPlaylist(widget.playlist.id, track.id),
      ),
      child: ListTile(
        title: Text(track.title, style: TextStyle(color: theme.colors.textPrimary)),
        subtitle: track.artist != null
            ? Text(track.artist!, style: TextStyle(color: theme.colors.textSecondary))
            : null,
        onTap: () => _playTrack(fullQueue, track),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (track.durationMs != null) ...[
              Text(
                formatDuration(Duration(milliseconds: track.durationMs!)),
                style: TextStyle(color: theme.colors.textSecondary, fontSize: 11),
              ),
              const SizedBox(width: 8),
            ],
            IconButton(
              icon: ThemedIcon(ThemedIconSlot.removeFromPlaylist, color: theme.colors.textSecondary),
              onPressed: () =>
                  ref.read(libraryRepositoryProvider).removeTrackFromPlaylist(widget.playlist.id, track.id),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final tracksAsync = ref.watch(playlistTracksProvider(widget.playlist.id));

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.playlist.name, style: TextStyle(color: theme.colors.textPrimary)),
        actions: [
          IconButton(
            tooltip: 'Add Songs',
            icon: const ThemedIcon(ThemedIconSlot.playlistAdd),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => AddTracksToPlaylistScreen(playlist: widget.playlist)),
            ),
          ),
        ],
      ),
      // Without this, pushing this screen covers HomeShell's own
      // bottomNavigationBar entirely — the mini-player would vanish until
      // navigating back out, instead of staying visible like every other screen.
      bottomNavigationBar: const MiniPlayer(),
      body: tracksAsync.when(
        data: (tracks) {
          final filtered = _filter(tracks);
          final isFiltering = _query.isNotEmpty;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                child: ThemedSearchBar(
                  hintText: 'Search in ${widget.playlist.name}',
                  onChanged: (value) => setState(() => _query = value),
                ),
              ),
              if (!isFiltering && tracks.length > 1)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Drag to reorder',
                      style: TextStyle(color: theme.colors.textSecondary, fontSize: 11),
                    ),
                  ),
                ),
              Expanded(
                child: tracks.isEmpty
                    ? Center(
                        child: Text('No tracks in this playlist yet',
                            style: TextStyle(color: theme.colors.textSecondary)),
                      )
                    : filtered.isEmpty
                        ? Center(
                            child: Text('No matches', style: TextStyle(color: theme.colors.textSecondary)),
                          )
                        // Reordering only makes sense against the full,
                        // unfiltered playlist order — fall back to a plain
                        // list while a search is active.
                        : isFiltering
                            ? ListView.builder(
                                itemCount: filtered.length,
                                itemBuilder: (context, index) =>
                                    _trackTile(context, filtered[index], tracks),
                              )
                            : ReorderableListView.builder(
                                itemCount: tracks.length,
                                onReorderItem: (oldIndex, newIndex) => _reorder(tracks, oldIndex, newIndex),
                                itemBuilder: (context, index) =>
                                    _trackTile(context, tracks[index], tracks),
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
