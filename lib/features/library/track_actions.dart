import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/library/database.dart';
import '../../core/theme/theme_provider.dart';
import '../playlists/playlist_actions.dart';

/// Right-click (desktop) context menu for a track row: Play / Add to
/// Playlist, in the same spot Apple Music puts theirs.
void showTrackContextMenu({
  required BuildContext context,
  required WidgetRef ref,
  required Track track,
  required Offset position,
  required VoidCallback onPlay,
}) {
  final theme = ref.read(themeProvider);
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;

  showMenu<_TrackMenuAction>(
    context: context,
    color: theme.colors.surface,
    position: RelativeRect.fromRect(
      position & const Size(1, 1),
      Offset.zero & overlay.size,
    ),
    items: [
      PopupMenuItem(
        value: _TrackMenuAction.play,
        child: Text('Play', style: TextStyle(color: theme.colors.textPrimary)),
      ),
      PopupMenuItem(
        value: _TrackMenuAction.addToPlaylist,
        child: Text('Add to Playlist…', style: TextStyle(color: theme.colors.textPrimary)),
      ),
    ],
  ).then((action) {
    if (!context.mounted || action == null) return;
    switch (action) {
      case _TrackMenuAction.play:
        onPlay();
      case _TrackMenuAction.addToPlaylist:
        showAddToPlaylistSheet(context, ref, track);
    }
  });
}

enum _TrackMenuAction { play, addToPlaylist }
