import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/playback/playback_controller.dart';
import '../../core/theme/theme_provider.dart';
import '../../widgets/themed/themed_icon.dart';
import 'now_playing_screen.dart';

/// Persistent bar showing the current track, visible from every top-level
/// screen. Tapping it opens the full Now Playing screen WITHOUT re-issuing
/// a play command — this is the fix for "re-clicking a song restarts it":
/// once something is playing, this is how you get back to it.
class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    final playback = ref.watch(playbackControllerProvider);
    final controller = ref.read(playbackControllerProvider.notifier);
    final track = playback.currentTrack;

    if (track == null) return const SizedBox.shrink();

    return Material(
      color: theme.colors.surface,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const NowPlayingScreen()),
        ),
        child: SizedBox(
          height: 64,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
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
    );
  }
}
