import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format_duration.dart';
import '../../core/library/database.dart';
import '../../core/playback/playback_controller.dart';
import '../../core/theme/theme_provider.dart';
import '../../widgets/themed/themed_icon.dart';
import '../library/track_actions.dart';
import '../now_playing/now_playing_screen.dart';
import '../playlists/playlist_actions.dart';

/// Plain track-list detail screen shared by every "browse by X" group tap —
/// an artist, a genre, or a folder all just mean "here are the tracks in
/// this bucket", so one screen covers all three instead of three
/// near-identical copies.
class GroupDetailScreen extends ConsumerWidget {
  final String title;
  final List<Track> tracks;

  const GroupDetailScreen({
    super.key,
    required this.title,
    required this.tracks,
  });

  void _playTrack(BuildContext context, WidgetRef ref, int index) {
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

    return Scaffold(
      appBar: AppBar(
        title: Text(title, style: TextStyle(color: theme.colors.textPrimary)),
      ),
      body: tracks.isEmpty
          ? Center(
              child: Text(
                'No tracks',
                style: TextStyle(color: theme.colors.textSecondary),
              ),
            )
          : ListView.builder(
              itemCount: tracks.length,
              itemBuilder: (context, index) {
                final track = tracks[index];
                return GestureDetector(
                  onSecondaryTapDown: (details) => showTrackContextMenu(
                    context: context,
                    ref: ref,
                    track: track,
                    position: details.globalPosition,
                    onPlay: () => _playTrack(context, ref, index),
                  ),
                  child: ListTile(
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
                    onTap: () => _playTrack(context, ref, index),
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
    );
  }
}
