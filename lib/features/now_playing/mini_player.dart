import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/playback/playback_controller.dart';
import '../../core/theme/theme_provider.dart';
import '../../widgets/themed/themed_icon.dart';
import '../../widgets/themed/track_art.dart';
import 'now_playing_screen.dart';

/// Shows the current track, meant to sit in a Scaffold's
/// bottomNavigationBar slot on every screen where playback should stay
/// visible/controllable. Tapping it opens the full Now Playing screen
/// WITHOUT re-issuing a play command — this is the fix for "re-clicking a
/// song restarts it": once something is playing, this is how you get back
/// to it. Floats as its own rounded, shadowed card (Apple-Music-style)
/// rather than merging flush into whatever's below it.
class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    final playback = ref.watch(playbackControllerProvider);
    final controller = ref.read(playbackControllerProvider.notifier);
    final track = playback.currentTrack;

    if (track == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      decoration: BoxDecoration(
        color: theme.colors.surface,
        borderRadius: BorderRadius.circular(theme.shapes.cornerRadius),
        // Blur is one of the more GPU-expensive paint ops in Flutter's
        // renderer, and this bar redraws on every window resize — kept
        // minimal since this app targets low-power integrated GPUs too.
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            controller.refreshVolume();
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const NowPlayingScreen()),
            );
          },
          child: SizedBox(
            height: 60,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  TrackArt(
                    albumArtPath: track.albumArtPath,
                    size: 40,
                    borderRadius: theme.shapes.cornerRadius * 0.6,
                    iconSizeFraction: 0.5,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: theme.colors.textPrimary, fontWeight: FontWeight.w600),
                        ),
                        if (track.artist != null)
                          Text(
                            track.artist!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: theme.colors.textSecondary, fontSize: 12),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: ThemedIcon(playback.isPlaying ? ThemedIconSlot.pause : ThemedIconSlot.play),
                    onPressed: controller.togglePlayPause,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
