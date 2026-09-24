import 'package:flutter/material.dart';

import 'custom_theme_data.dart';
import 'theme_model.dart';
import 'vesper_palette.dart';

/// Starter presets shown in the theme editor's library alongside anything
/// the user has saved — remixable starting points rather than fixed
/// choices, since duplicating one and editing the copy is the normal flow.
final List<CustomThemeData> builtInPresets = [
  CustomThemeData(
    id: 'preset-light',
    name: 'Vesper Dawn',
    colors: vesperDawnColors,
    typography: const AppTypography(
      fontFamily: sansFontFamily,
      headerSize: 22,
      headerWeight: FontWeight.w600,
      bodySize: 15,
      bodyWeight: FontWeight.w400,
      lyricsSize: 17,
      lyricsWeight: FontWeight.w400,
    ),
    shapes: const AppShapes(cornerRadius: 14, borderWidth: 1, cardElevation: 0),
  ),
  CustomThemeData(
    id: 'preset-midnight',
    name: 'Midnight',
    colors: const AppColorScheme(
      background: Color(0xFF0A0E1A),
      surface: Color(0xFF141A2E),
      primary: Color(0xFF5B8DEF),
      accent: Color(0xFF4FD1C5),
      textPrimary: Color(0xFFEDEFF7),
      textSecondary: Color(0xFF8891A8),
      progressBar: Color(0xFF5B8DEF),
      progressBarTrack: Color(0xFF262E45),
      controlActive: Color(0xFFEDEFF7),
      controlInactive: Color(0xFF565F78),
      error: Color(0xFFE5637A),
    ),
    typography: const AppTypography(
      fontFamily: sansFontFamily,
      headerSize: 22,
      headerWeight: FontWeight.w700,
      bodySize: 15,
      bodyWeight: FontWeight.w400,
      lyricsSize: 17,
      lyricsWeight: FontWeight.w400,
    ),
    shapes: const AppShapes(cornerRadius: 16, borderWidth: 1, cardElevation: 0),
  ),
  CustomThemeData(
    id: 'preset-sunset',
    name: 'Sunset',
    colors: const AppColorScheme(
      background: Color(0xFF1F1512),
      surface: Color(0xFF2C1E19),
      primary: Color(0xFFFF8A5B),
      accent: Color(0xFFFFC145),
      textPrimary: Color(0xFFFFF3EA),
      textSecondary: Color(0xFFC2A292),
      progressBar: Color(0xFFFF8A5B),
      progressBarTrack: Color(0xFF4A342C),
      controlActive: Color(0xFFFFF3EA),
      controlInactive: Color(0xFF8A6F62),
      error: Color(0xFFE85D5D),
    ),
    typography: const AppTypography(
      fontFamily: sansFontFamily,
      headerSize: 22,
      headerWeight: FontWeight.w600,
      bodySize: 15,
      bodyWeight: FontWeight.w400,
      lyricsSize: 17,
      lyricsWeight: FontWeight.w400,
    ),
    shapes: const AppShapes(cornerRadius: 20, borderWidth: 1, cardElevation: 0),
  ),
  CustomThemeData(
    id: 'preset-mono',
    name: 'Mono',
    colors: const AppColorScheme(
      background: Color(0xFF111111),
      surface: Color(0xFF1C1C1C),
      primary: Color(0xFFE0E0E0),
      accent: Color(0xFFBDBDBD),
      textPrimary: Color(0xFFF5F5F5),
      textSecondary: Color(0xFF9E9E9E),
      progressBar: Color(0xFFE0E0E0),
      progressBarTrack: Color(0xFF3A3A3A),
      controlActive: Color(0xFFF5F5F5),
      controlInactive: Color(0xFF6E6E6E),
      error: Color(0xFFEF5350),
    ),
    typography: const AppTypography(
      fontFamily: sansFontFamily,
      headerSize: 21,
      headerWeight: FontWeight.w500,
      bodySize: 14,
      bodyWeight: FontWeight.w400,
      lyricsSize: 16,
      lyricsWeight: FontWeight.w400,
    ),
    shapes: const AppShapes(cornerRadius: 4, borderWidth: 1, cardElevation: 0),
  ),
];
