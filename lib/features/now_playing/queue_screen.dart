import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/playback/playback_controller.dart';
import '../../core/theme/theme_provider.dart';
import '../../widgets/themed/themed_icon.dart';
import '../../widgets/themed/track_art.dart';

/// Shows the current play queue in play order, with the now-playing track
/// highlighted. Drag to reorder — reordering never restarts or skips
/// whatever is currently playing (see PlaybackController.reorderQueue).
class QueueScreen extends ConsumerWidget {
  const QueueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    final playback = ref.watch(playbackControllerProvider);
    final controller = ref.read(playbackControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: Text('Queue', style: TextStyle(color: theme.colors.textPrimary)),
      ),
      body: playback.order.isEmpty
          ? Center(
              child: Text('Nothing queued', style: TextStyle(color: theme.colors.textSecondary)),
            )
          : ReorderableListView.builder(
              itemCount: playback.order.length,
              onReorderItem: controller.reorderQueue,
              itemBuilder: (context, i) {
                final track = playback.queue[playback.order[i]];
                final isCurrent = i == playback.orderIndex;
                return ListTile(
                  key: ValueKey(track.id),
                  leading: TrackArt(
                    albumArtPath: track.albumArtPath,
                    size: 40,
                    borderRadius: theme.shapes.cornerRadius * 0.6,
                  ),
                  title: Text(
                    track.title,
                    style: TextStyle(
                      color: isCurrent ? theme.colors.primary : theme.colors.textPrimary,
                      fontWeight: isCurrent ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                  subtitle: track.artist != null
                      ? Text(track.artist!, style: TextStyle(color: theme.colors.textSecondary))
                      : null,
                  trailing: isCurrent
                      ? ThemedIcon(
                          playback.isPlaying ? ThemedIconSlot.pause : ThemedIconSlot.play,
                          color: theme.colors.primary,
                          size: 18,
                        )
                      : null,
                );
              },
            ),
    );
  }
}
