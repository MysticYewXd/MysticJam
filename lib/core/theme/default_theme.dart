import 'package:flutter/material.dart';
import 'theme_model.dart';

/// The single built-in theme. Ships until the theme editor/marketplace exist.
const AppTheme defaultTheme = AppTheme(
  name: 'Default',
  author: 'Music Player',
  colors: AppColorScheme(
    background: Color(0xFF121212),
    surface: Color(0xFF1E1E1E),
    primary: Color(0xFF6C63FF),
    accent: Color(0xFF03DAC6),
    textPrimary: Color(0xFFF5F5F5),
    textSecondary: Color(0xFFAAAAAA),
    progressBar: Color(0xFF6C63FF),
    progressBarTrack: Color(0xFF3A3A3A),
    controlActive: Color(0xFFF5F5F5),
    controlInactive: Color(0xFF888888),
    error: Color(0xFFCF6679),
  ),
  typography: AppTypography(
    fontFamily: 'Roboto',
    headerSize: 22,
    headerWeight: FontWeight.w600,
    bodySize: 15,
    bodyWeight: FontWeight.w400,
    lyricsSize: 17,
    lyricsWeight: FontWeight.w400,
  ),
  shapes: AppShapes(
    cornerRadius: 12,
    borderWidth: 1,
    cardElevation: 0,
  ),
  layout: AppLayout(
    nowPlaying: NowPlayingLayout.fullArt,
    library: LibraryLayout.list,
  ),
  icons: IconSet(),
  animations: AnimationConfig(
    primitive: AnimationPrimitive.fade,
    duration: Duration(milliseconds: 200),
    curve: Curves.easeInOut,
  ),
  assets: ThemeAssets(),
);
