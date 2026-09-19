import 'package:flutter/material.dart';

/// Which now-playing layout a theme selects. Capped at two variants by design —
/// every additional variant multiplies the cost of every future now-playing feature.
enum NowPlayingLayout { compact, fullArt }

/// Which library browsing layout a theme selects.
enum LibraryLayout { list, grid }

/// Curated animation primitives themes may choose between. Deliberately not
/// extensible to arbitrary scripting — themes only ever pick from this set.
enum AnimationPrimitive { fade, slide, scale, morph, crossfade }

// ignore_for_file: prefer_initializing_formals
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

  // Optional refinements for richer palettes (e.g. Vesper). Themes saved
  // before these existed leave them null and get a value derived from the
  // core slots, so old JSON keeps loading and looking sensible.
  final Color? _chrome;
  final Color? _line;
  final Color? _onPrimary;
  final Color? _accentSoft;
  final Color? _textFaint;

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
    Color? chrome,
    Color? line,
    Color? onPrimary,
    Color? accentSoft,
    Color? textFaint,
  }) : _chrome = chrome,
       _line = line,
       _onPrimary = onPrimary,
       _accentSoft = accentSoft,
       _textFaint = textFaint;

  /// Persistent chrome (dock, player bar) sitting on [background].
  Color get chrome => _chrome ?? surface;

  /// Decorative hairline between rows and panels.
  Color get line => _line ?? textSecondary.withValues(alpha: 0.18);

  /// Icon/text colour drawn on a [primary] fill.
  Color get onPrimary =>
      _onPrimary ??
      (ThemeData.estimateBrightnessForColor(primary) == Brightness.dark
          ? const Color(0xFFFFFFFF)
          : const Color(0xFF111111));

  /// Translucent wash for selected/hovered rows.
  Color get accentSoft => _accentSoft ?? primary.withValues(alpha: 0.18);

  /// Tertiary text: durations, track numbers, captions.
  Color get textFaint => _textFaint ?? textSecondary.withValues(alpha: 0.85);

  /// The optional slots the theme set explicitly, keyed for JSON storage.
  Map<String, Color> get explicitExtras => {
    if (_chrome != null) 'chrome': _chrome,
    if (_line != null) 'line': _line,
    if (_onPrimary != null) 'onPrimary': _onPrimary,
    if (_accentSoft != null) 'accentSoft': _accentSoft,
    if (_textFaint != null) 'textFaint': _textFaint,
  };

  AppColorScheme copyWith({
    Color? background,
    Color? surface,
    Color? primary,
    Color? accent,
    Color? textPrimary,
    Color? textSecondary,
    Color? progressBar,
    Color? progressBarTrack,
    Color? controlActive,
    Color? controlInactive,
    Color? error,
  }) {
    return AppColorScheme(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      primary: primary ?? this.primary,
      accent: accent ?? this.accent,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      progressBar: progressBar ?? this.progressBar,
      progressBarTrack: progressBarTrack ?? this.progressBarTrack,
      controlActive: controlActive ?? this.controlActive,
      controlInactive: controlInactive ?? this.controlInactive,
      error: error ?? this.error,
      chrome: _chrome,
      line: _line,
      onPrimary: _onPrimary,
      accentSoft: _accentSoft,
      textFaint: _textFaint,
    );
  }
}

/// The Vesper families bundled under assets/fonts.
const String sansFontFamily = 'DM Sans';
const String displayFontFamily = 'Fraunces';

class AppTypography {
  final String fontFamily;

  /// Serif used for titles and headings (the Vesper display styles).
  final String displayFamily;
  final double headerSize;
  final FontWeight headerWeight;
  final double bodySize;
  final FontWeight bodyWeight;
  final double lyricsSize;
  final FontWeight lyricsWeight;

  const AppTypography({
    required this.fontFamily,
    this.displayFamily = displayFontFamily,
    required this.headerSize,
    required this.headerWeight,
    required this.bodySize,
    required this.bodyWeight,
    required this.lyricsSize,
    required this.lyricsWeight,
  });

  /// A Vesper display style (Fraunces, medium). Only weight 500 is bundled,
  /// so it isn't parameterised — asking for bolder would make the engine
  /// synthesise a fake bold.
  TextStyle display(double size, {required Color color, double? height}) =>
      TextStyle(
        fontFamily: displayFamily,
        fontSize: size,
        fontWeight: FontWeight.w500,
        height: height,
        color: color,
      );
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
