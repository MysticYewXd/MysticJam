import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/theme_provider.dart';

/// Fixed icon slots — mirrors [IconSet]. Screens reference a slot, never a
/// concrete Icons.* constant, so a theme can override every icon in the app.
enum ThemedIconSlot {
  play,
  pause,
  next,
  previous,
  shuffle,
  repeat,
  repeatOne,
  library,
  settings,
  playlist,
  folderAdd,
  fileAdd,
  search,
  volumeUp,
  volumeDown,
  playlistAdd,
  removeFromPlaylist,
  close,
  refresh,
  selectAll,
  delete,
  lyrics,
  album,
  artist,
  genre,
  folder,
  recentlyPlayed,
  browse,
}

class ThemedIcon extends ConsumerWidget {
  final ThemedIconSlot slot;
  final double? size;
  final Color? color;

  const ThemedIcon(this.slot, {super.key, this.size, this.color});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    final icons = theme.icons;
    final data = switch (slot) {
      ThemedIconSlot.play => icons.play,
      ThemedIconSlot.pause => icons.pause,
      ThemedIconSlot.next => icons.next,
      ThemedIconSlot.previous => icons.previous,
      ThemedIconSlot.shuffle => icons.shuffle,
      ThemedIconSlot.repeat => icons.repeat,
      ThemedIconSlot.repeatOne => icons.repeatOne,
      ThemedIconSlot.library => icons.library,
      ThemedIconSlot.settings => icons.settings,
      ThemedIconSlot.playlist => icons.playlist,
      ThemedIconSlot.folderAdd => icons.folderAdd,
      ThemedIconSlot.fileAdd => icons.fileAdd,
      ThemedIconSlot.search => icons.search,
      ThemedIconSlot.volumeUp => icons.volumeUp,
      ThemedIconSlot.volumeDown => icons.volumeDown,
      ThemedIconSlot.playlistAdd => icons.playlistAdd,
      ThemedIconSlot.removeFromPlaylist => icons.removeFromPlaylist,
      ThemedIconSlot.close => icons.close,
      ThemedIconSlot.refresh => icons.refresh,
      ThemedIconSlot.selectAll => icons.selectAll,
      ThemedIconSlot.delete => icons.delete,
      ThemedIconSlot.lyrics => icons.lyrics,
      ThemedIconSlot.album => icons.album,
      ThemedIconSlot.artist => icons.artist,
      ThemedIconSlot.genre => icons.genre,
      ThemedIconSlot.folder => icons.folder,
      ThemedIconSlot.recentlyPlayed => icons.recentlyPlayed,
      ThemedIconSlot.browse => icons.browse,
    };
    return Icon(data, size: size, color: color ?? theme.colors.controlActive);
  }
}
