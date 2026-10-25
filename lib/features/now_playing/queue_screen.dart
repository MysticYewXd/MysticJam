import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/playback/playback_controller.dart';
import '../../core/theme/theme_provider.dart';
import '../../widgets/themed/themed_icon.dart';
import '../../widgets/themed/track_art.dart';

/// Shows the current play queue in play order, with the now-playing track
/// highlighted. Drag the handle to reorder — reordering never restarts or
/// skips whatever is currently playing (see PlaybackController.reorderQueue)
/// — or tap ✕ to remove a song; removing the playing song moves on to the
/// next one (see PlaybackController.removeFromQueue).
class QueueScreen extends ConsumerWidget {
  const QueueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    // Everything but position. Lists compare by identity, which is right:
    // the controller replaces them rather than mutating.
    final (order, queue, orderIndex, isPlaying) = ref.watch(
      playbackControllerProvider.select(
        (s) => (s.order, s.queue, s.orderIndex, s.isPlaying),
      ),
    );
    final controller = ref.read(playbackControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: Text('Queue', style: TextStyle(color: theme.colors.textPrimary)),
      ),
      body: order.isEmpty
          ? Center(
              child: Text(
                'Nothing queued',
                style: TextStyle(color: theme.colors.textSecondary),
              ),
            )
          : ReorderableListView.builder(
              itemCount: order.length,
              onReorderItem: controller.reorderQueue,
              // Each row has its own handle next to the remove button; the
              // automatic desktop handle would sit on top of that button.
              buildDefaultDragHandles: false,
              itemBuilder: (context, i) {
                final track = queue[order[i]];
                final isCurrent = i == orderIndex;
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
                      color: isCurrent
                          ? theme.colors.primary
                          : theme.colors.textPrimary,
                      fontWeight: isCurrent
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
                  subtitle: track.artist != null
                      ? Text(
                          track.artist!,
                          style: TextStyle(color: theme.colors.textSecondary),
                        )
                      : null,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isCurrent)
                        ThemedIcon(
                          isPlaying
                              ? ThemedIconSlot.pause
                              : ThemedIconSlot.play,
                          color: theme.colors.primary,
                          size: 18,
                        ),
                      IconButton(
                        tooltip: 'Remove from queue',
                        icon: ThemedIcon(
                          ThemedIconSlot.close,
                          color: theme.colors.textSecondary,
                          size: 18,
                        ),
                        onPressed: () => controller.removeFromQueue(i),
                      ),
                      ReorderableDragStartListener(
                        index: i,
                        child: Tooltip(
                          message: 'Drag to reorder',
                          child: MouseRegion(
                            cursor: SystemMouseCursors.grab,
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Icon(
                                Icons.drag_handle,
                                color: theme.colors.textSecondary,
                                size: 20,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
