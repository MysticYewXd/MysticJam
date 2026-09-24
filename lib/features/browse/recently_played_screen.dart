import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format_duration.dart';
import '../../core/library/database.dart';
import '../../core/library/library_providers.dart';
import '../../core/playback/playback_controller.dart';
import '../../core/theme/theme_provider.dart';
import '../../widgets/themed/themed_icon.dart';
import '../../widgets/themed/track_art.dart';
import '../library/track_actions.dart';
import '../now_playing/now_playing_screen.dart';
import '../playlists/playlist_actions.dart';

/// Most-recently-played first — backed by AppSettingsState.recentlyPlayedTrackIds
/// (see core/settings/app_settings.dart), which is recorded every time a
/// genuinely different track starts playing. Unlike the other browse
/// screens this isn't grouped/alphabetical — order itself is the point.
class RecentlyPlayedScreen extends ConsumerWidget {
  const RecentlyPlayedScreen({super.key});

  void _playTrack(
    BuildContext context,
    WidgetRef ref,
    List<Track> tracks,
    int index,
  ) {
    final controller = ref.read(playbackControllerProvider.notifier);
    controller.playFromQueue(tracks, index);
    controller.refreshVolume();
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const NowPlayingScreen()));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    final tracksAsync = ref.watch(recentlyPlayedTracksProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Recently Played',
          style: TextStyle(color: theme.colors.textPrimary),
        ),
      ),
      body: tracksAsync.when(
        data: (tracks) {
          if (tracks.isEmpty) {
            return Center(
              child: Text(
                'Nothing played yet',
                style: TextStyle(color: theme.colors.textSecondary),
              ),
            );
          }
          return ListView.builder(
            itemCount: tracks.length,
            itemBuilder: (context, index) {
              final track = tracks[index];
              return GestureDetector(
                onSecondaryTapDown: (details) => showTrackContextMenu(
                  context: context,
                  ref: ref,
                  track: track,
                  position: details.globalPosition,
                  onPlay: () => _playTrack(context, ref, tracks, index),
                ),
                child: ListTile(
                  leading: TrackArt(
                    albumArtPath: track.albumArtPath,
                    size: 40,
                    borderRadius: theme.shapes.cornerRadius * 0.6,
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
                  onTap: () => _playTrack(context, ref, tracks, index),
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
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err')),
      ),
    );
  }
}
