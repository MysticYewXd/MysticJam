import 'package:flutter/material.dart';
import 'theme_model.dart';
import 'vesper_palette.dart';

/// The built-in default: Vesper Dusk.
const AppTheme defaultTheme = AppTheme(
  name: 'Vesper Dusk',
  author: 'MysticJam',
  colors: vesperDuskColors,
  typography: AppTypography(
    fontFamily: sansFontFamily,
    headerSize: 22,
    headerWeight: FontWeight.w600,
    bodySize: 15,
    bodyWeight: FontWeight.w400,
    lyricsSize: 17,
    lyricsWeight: FontWeight.w400,
  ),
  shapes: AppShapes(cornerRadius: 14, borderWidth: 1, cardElevation: 0),
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
