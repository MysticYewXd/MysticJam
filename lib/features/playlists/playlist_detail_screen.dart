import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/library/database.dart';
import '../../core/library/library_providers.dart';
import '../../core/playback/playback_controller.dart';
import '../../core/theme/theme_provider.dart';
import '../../widgets/themed/themed_icon.dart';
import '../../widgets/themed/themed_search_bar.dart';
import '../library/track_actions.dart';
import '../now_playing/now_playing_screen.dart';

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
    ref.read(playbackControllerProvider.notifier).playFromQueue(fullQueue, fullIndex);
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const NowPlayingScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final tracksAsync = ref.watch(playlistTracksProvider(widget.playlist.id));

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.playlist.name, style: TextStyle(color: theme.colors.textPrimary)),
      ),
      body: tracksAsync.when(
        data: (tracks) {
          final filtered = _filter(tracks);
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                child: ThemedSearchBar(
                  hintText: 'Search in ${widget.playlist.name}',
                  onChanged: (value) => setState(() => _query = value),
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
                        : ListView.builder(
                            itemCount: filtered.length,
                            itemBuilder: (context, index) {
                              final track = filtered[index];
                              return GestureDetector(
                                onSecondaryTapDown: (details) => showTrackContextMenu(
                                  context: context,
                                  ref: ref,
                                  track: track,
                                  position: details.globalPosition,
                                  onPlay: () => _playTrack(tracks, track),
                                ),
                                child: ListTile(
                                  title: Text(track.title, style: TextStyle(color: theme.colors.textPrimary)),
                                  subtitle: track.artist != null
                                      ? Text(track.artist!, style: TextStyle(color: theme.colors.textSecondary))
                                      : null,
                                  onTap: () => _playTrack(tracks, track),
                                  trailing: IconButton(
                                    icon: ThemedIcon(ThemedIconSlot.removeFromPlaylist,
                                        color: theme.colors.textSecondary),
                                    onPressed: () => ref
                                        .read(libraryRepositoryProvider)
                                        .removeTrackFromPlaylist(widget.playlist.id, track.id),
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
