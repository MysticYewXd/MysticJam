import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/library/database.dart';
import '../../core/library/library_repository.dart';
import '../../core/playback/playback_controller.dart';
import '../../core/theme/theme_provider.dart';
import '../../widgets/themed/themed_icon.dart';
import '../../widgets/themed/track_art.dart';
import '../library/track_actions.dart';
import '../now_playing/now_playing_screen.dart';
import '../playlists/playlist_actions.dart';
import '../../widgets/themed/round_buttons.dart';
import '../../widgets/themed/track_row.dart';

/// Track listing for a single album — [album] is already-grouped, joined
/// data from LibraryRepository.watchAlbums (see AlbumsScreen), so this is
/// read-only, no reordering.
class AlbumDetailScreen extends ConsumerWidget {
  final AlbumWithTracks album;

  const AlbumDetailScreen({super.key, required this.album});

  /// Sorted by track number when known, with untagged tracks (no number at
  /// all) pushed to the end rather than sorted as if they were "track 0" —
  /// previously this screen just showed whatever order the library's own
  /// artist/title sort happened to produce, which rarely matched the
  /// album's actual sequence.
  List<Track> _sortedTracks() {
    final sorted = [...album.tracks];
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
    final subtitleParts = [
      if (album.artist != null) album.artist!,
      if (album.year != null) album.year.toString(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(
          album.title,
          style: TextStyle(color: theme.colors.textPrimary),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                TrackArt(
                  albumArtPath: album.coverArtPath,
                  size: 72,
                  borderRadius: theme.shapes.cornerRadius,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        album.title,
                        style: theme.typography.display(
                          28,
                          color: theme.colors.textPrimary,
                          height: 1.15,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      if (subtitleParts.isNotEmpty)
                        Text(
                          subtitleParts.join(' · '),
                          style: TextStyle(
                            color: theme.colors.textSecondary,
                            fontSize: 13,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      Text(
                        '${album.tracks.length} track${album.tracks.length == 1 ? '' : 's'}',
                        style: TextStyle(
                          color: theme.colors.textFaint,
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
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 2,
                    ),
                    child: TrackRow(
                      track: track,
                      subtitle: track.artist,
                      showFormat: false,
                      leading: SizedBox(
                        width: 28,
                        child: Text(
                          track.trackNumber?.toString() ?? '–',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: theme.colors.textFaint,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      onTap: () =>
                          _playTrack(context, ref, orderedTracks, index),
                      actions: [
                        RoundIconButton(
                          slot: ThemedIconSlot.playlistAdd,
                          tooltip: 'Add to playlist',
                          diameter: 36,
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
