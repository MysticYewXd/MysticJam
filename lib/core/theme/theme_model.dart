import 'package:flutter/material.dart';

/// Which now-playing layout a theme selects. Capped at two variants by design —
/// every additional variant multiplies the cost of every future now-playing feature.
enum NowPlayingLayout { compact, fullArt }

/// Which library browsing layout a theme selects.
enum LibraryLayout { list, grid }

/// Curated animation primitives themes may choose between. Deliberately not
/// extensible to arbitrary scripting — themes only ever pick from this set.
enum AnimationPrimitive { fade, slide, scale, morph, crossfade }

class AppColorScheme {
  final Color background;
  final Color surface;
  final Color primary;
  final Color accent;
  final Color textPrimary;
  final Color textSecondary;
  final Color progressBar;
  final Color progressBarTrack;
  final Color controlActive;
  final Color controlInactive;
  final Color error;

  const AppColorScheme({
    required this.background,
    required this.surface,
    required this.primary,
    required this.accent,
    required this.textPrimary,
    required this.textSecondary,
    required this.progressBar,
    required this.progressBarTrack,
    required this.controlActive,
    required this.controlInactive,
    required this.error,
  });
}

class AppTypography {
  final String fontFamily;
  final double headerSize;
  final FontWeight headerWeight;
  final double bodySize;
  final FontWeight bodyWeight;
  final double lyricsSize;
  final FontWeight lyricsWeight;

  const AppTypography({
    required this.fontFamily,
    required this.headerSize,
    required this.headerWeight,
    required this.bodySize,
    required this.bodyWeight,
    required this.lyricsSize,
    required this.lyricsWeight,
  });
}

class AppShapes {
  final double cornerRadius;
  final double borderWidth;
  final double cardElevation;

  const AppShapes({
    required this.cornerRadius,
    required this.borderWidth,
    required this.cardElevation,
  });
}

class AppLayout {
  final NowPlayingLayout nowPlaying;
  final LibraryLayout library;

  const AppLayout({required this.nowPlaying, required this.library});
}

/// Fixed icon slots a theme may override. Anything left null falls back to
/// the default Material icon for that slot — themes never need to supply all of them.
class IconSet {
  final IconData play;
  final IconData pause;
  final IconData next;
  final IconData previous;
  final IconData shuffle;
  final IconData repeat;
  final IconData repeatOne;
  final IconData library;
  final IconData settings;
  final IconData playlist;
  final IconData folderAdd;
  final IconData fileAdd;
  final IconData search;
  final IconData volumeUp;
  final IconData volumeDown;
  final IconData playlistAdd;
  final IconData removeFromPlaylist;
  final IconData close;
  final IconData refresh;
  final IconData selectAll;
  final IconData delete;
  final IconData lyrics;
  final IconData album;
  final IconData artist;
  final IconData genre;
  final IconData folder;
  final IconData recentlyPlayed;
  final IconData browse;

  const IconSet({
    this.play = Icons.play_arrow,
    this.pause = Icons.pause,
    this.next = Icons.fast_forward,
    this.previous = Icons.fast_rewind,
    this.shuffle = Icons.shuffle,
    this.repeat = Icons.repeat,
    this.repeatOne = Icons.repeat_one,
    this.library = Icons.library_music,
    this.settings = Icons.settings,
    this.playlist = Icons.queue_music,
    this.folderAdd = Icons.create_new_folder,
    this.fileAdd = Icons.audio_file,
    this.search = Icons.search,
    this.volumeUp = Icons.volume_up,
    this.volumeDown = Icons.volume_down,
    this.playlistAdd = Icons.playlist_add,
    this.removeFromPlaylist = Icons.remove_circle_outline,
    this.close = Icons.close,
    this.refresh = Icons.refresh,
    this.selectAll = Icons.select_all,
    this.delete = Icons.delete_outline,
    this.lyrics = Icons.lyrics_outlined,
    this.album = Icons.album,
    this.artist = Icons.person_outline,
    this.genre = Icons.category_outlined,
    this.folder = Icons.folder_outlined,
    this.recentlyPlayed = Icons.history,
    this.browse = Icons.explore_outlined,
  });
}

class AnimationConfig {
  final AnimationPrimitive primitive;
  final Duration duration;
  final Curve curve;

  const AnimationConfig({
    required this.primitive,
    required this.duration,
    required this.curve,
  });
}

/// Optional bundled visual assets (background images, art frames, textures).
/// Paths are asset keys resolved through the theme loader; null means "unset".
class ThemeAssets {
  final String? backgroundImage;
  final String? artFrame;
  final String? texture;

  const ThemeAssets({this.backgroundImage, this.artFrame, this.texture});
}

/// The Dart-side mirror of a theme.json package. This is the single source of
/// truth for app styling — screens must never read hardcoded colors/icons,
/// only this model via ThemeProvider.
class AppTheme {
  final String name;
  final String author;
  final AppColorScheme colors;
  final AppTypography typography;
  final AppShapes shapes;
  final AppLayout layout;
  final IconSet icons;
  final AnimationConfig animations;
  final ThemeAssets assets;

  const AppTheme({
    required this.name,
    required this.author,
    required this.colors,
    required this.typography,
    required this.shapes,
    required this.layout,
    required this.icons,
    required this.animations,
    required this.assets,
  });
}
