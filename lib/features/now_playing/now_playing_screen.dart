import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/playback/playback_controller.dart';
import '../../core/theme/theme_provider.dart';
import '../../widgets/themed/themed_icon.dart';
import '../../widgets/themed/themed_progress_bar.dart';
import '../../widgets/themed/themed_volume_slider.dart';

class NowPlayingScreen extends ConsumerWidget {
  const NowPlayingScreen({super.key});

  String _format(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    final playback = ref.watch(playbackControllerProvider);
    final controller = ref.read(playbackControllerProvider.notifier);
    final track = playback.currentTrack;

    return Scaffold(
      backgroundColor: theme.colors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Center(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'NOW PLAYING',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 2,
                      color: theme.colors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 24),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final size = constraints.maxWidth.clamp(0, 340).toDouble();
                      return Container(
                        width: size,
                        height: size,
                        decoration: BoxDecoration(
                          color: theme.colors.surface,
                          borderRadius: BorderRadius.circular(theme.shapes.cornerRadius * 1.5),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.3),
                              blurRadius: 24,
                              offset: const Offset(0, 12),
                            ),
                          ],
                        ),
                        child: Icon(
                          theme.icons.library,
                          size: size * 0.4,
                          color: theme.colors.textSecondary,
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 36),
                  Text(
                    track?.title ?? 'Nothing playing',
                    style: TextStyle(
                      fontSize: theme.typography.headerSize + 2,
                      fontWeight: theme.typography.headerWeight,
                      color: theme.colors.textPrimary,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (track?.artist != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      track!.artist!,
                      style: TextStyle(color: theme.colors.textSecondary, fontSize: 15),
                    ),
                  ],
                  const SizedBox(height: 28),
                  ThemedProgressBar(
                    position: playback.position,
                    duration: playback.duration,
                    onSeek: controller.seek,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _format(playback.position),
                          style: TextStyle(color: theme.colors.textSecondary, fontSize: 11),
                        ),
                        Text(
                          _format(playback.duration),
                          style: TextStyle(color: theme.colors.textSecondary, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton(
                        iconSize: 36,
                        icon: ThemedIcon(
                          ThemedIconSlot.previous,
                          color: playback.hasPrevious
                              ? theme.colors.controlActive
                              : theme.colors.controlInactive,
                        ),
                        onPressed: playback.hasPrevious ? controller.previous : null,
                      ),
                      IconButton(
                        iconSize: 68,
                        icon: ThemedIcon(
                          playback.isPlaying ? ThemedIconSlot.pause : ThemedIconSlot.play,
                        ),
                        onPressed: controller.togglePlayPause,
                      ),
                      IconButton(
                        iconSize: 36,
                        icon: ThemedIcon(
                          ThemedIconSlot.next,
                          color: playback.hasNext
                              ? theme.colors.controlActive
                              : theme.colors.controlInactive,
                        ),
                        onPressed: playback.hasNext ? controller.next : null,
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  ThemedVolumeSlider(
                    value: playback.volume,
                    onChanged: controller.setVolume,
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
