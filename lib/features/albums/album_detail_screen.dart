import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format_duration.dart';
import '../../core/library/database.dart';
import '../../core/playback/playback_controller.dart';
import '../../core/theme/theme_provider.dart';
import '../../widgets/themed/themed_icon.dart';
import '../../widgets/themed/track_art.dart';
import '../library/track_actions.dart';
import '../now_playing/now_playing_screen.dart';
import '../playlists/playlist_actions.dart';

/// Track listing for a single album — [tracks] are already the album's
/// tracks (passed in from AlbumsScreen's grouping), so this is read-only,
/// no reordering.
class AlbumDetailScreen extends ConsumerWidget {
  final String album;
  final List<Track> tracks;

  const AlbumDetailScreen({
    super.key,
    required this.album,
    required this.tracks,
  });

  /// Sorted by track number when known, with untagged tracks (no number at
  /// all) pushed to the end rather than sorted as if they were "track 0" —
  /// previously this screen just showed whatever order the library's own
  /// artist/title sort happened to produce, which rarely matched the
  /// album's actual sequence.
  List<Track> _sortedTracks() {
    final sorted = [...tracks];
    sorted.sort((a, b) {
      final an = a.trackNumber;
      final bn = b.trackNumber;
      if (an == null && bn == null) return 0;
      if (an == null) return 1;
      if (bn == null) return -1;
      return an.compareTo(bn);
    });
    return sorted;
  }

  void _playTrack(
    BuildContext context,
    WidgetRef ref,
    List<Track> orderedTracks,
    int index,
  ) {
    final controller = ref.read(playbackControllerProvider.notifier);
    controller.playFromQueue(orderedTracks, index);
    controller.refreshVolume();
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const NowPlayingScreen()));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    final orderedTracks = _sortedTracks();
    final artPath = tracks
        .firstWhere((t) => t.albumArtPath != null, orElse: () => tracks.first)
        .albumArtPath;

    return Scaffold(
      appBar: AppBar(
        title: Text(album, style: TextStyle(color: theme.colors.textPrimary)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                TrackArt(
                  albumArtPath: artPath,
                  size: 72,
                  borderRadius: theme.shapes.cornerRadius,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        album,
                        style: TextStyle(
                          color: theme.colors.textPrimary,
                          fontSize: theme.typography.headerSize - 2,
                          fontWeight: theme.typography.headerWeight,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${tracks.length} track${tracks.length == 1 ? '' : 's'}',
                        style: TextStyle(
                          color: theme.colors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: orderedTracks.length,
              itemBuilder: (context, index) {
                final track = orderedTracks[index];
                return GestureDetector(
                  onSecondaryTapDown: (details) => showTrackContextMenu(
                    context: context,
                    ref: ref,
                    track: track,
                    position: details.globalPosition,
                    onPlay: () =>
                        _playTrack(context, ref, orderedTracks, index),
                  ),
                  child: ListTile(
                    leading: SizedBox(
                      width: 24,
                      child: Text(
                        track.trackNumber?.toString() ?? '–',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: theme.colors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    title: Text(
                      track.title,
                      style: TextStyle(color: theme.colors.textPrimary),
                    ),
                    subtitle: track.artist != null
                        ? Text(
                            track.artist!,
                            style: TextStyle(color: theme.colors.textSecondary),
                          )
                        : null,
                    onTap: () => _playTrack(context, ref, orderedTracks, index),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (track.durationMs != null) ...[
                          Text(
                            formatDuration(
                              Duration(milliseconds: track.durationMs!),
                            ),
                            style: TextStyle(
                              color: theme.colors.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        IconButton(
                          icon: ThemedIcon(
                            ThemedIconSlot.playlistAdd,
                            color: theme.colors.textSecondary,
                          ),
                          onPressed: () =>
                              showAddToPlaylistSheet(context, ref, [track]),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
