import 'package:flutter/material.dart';

import 'theme_model.dart';

// Vesper design-system palettes (mysticjam/tokens.json), mapped onto the
// app's colour slots: surface-0 -> background, surface-1 -> chrome,
// surface-2 -> surface, surface-3 -> progressBarTrack, lavender -> primary,
// ember -> accent/progressBar, rose -> error.

const AppColorScheme vesperDuskColors = AppColorScheme(
  background: Color(0xFF15162A),
  surface: Color(0xFF25274A),
  primary: Color(0xFFB9AAF2),
  accent: Color(0xFFF4B58E),
  textPrimary: Color(0xFFEFECF8),
  textSecondary: Color(0xFFB9B9D6),
  progressBar: Color(0xFFF4B58E),
  progressBarTrack: Color(0xFF2F3157),
  controlActive: Color(0xFFEFECF8),
  controlInactive: Color(0xFFB9B9D6),
  error: Color(0xFFF0A0B4),
  chrome: Color(0xFF1C1D36),
  line: Color(0xFF3A3C66),
  onPrimary: Color(0xFF191534),
  accentSoft: Color(0x2EB9AAF2),
  textFaint: Color(0xFF9A9BC0),
);

const AppColorScheme vesperDawnColors = AppColorScheme(
  background: Color(0xFFF6F1F6),
  surface: Color(0xFFFBF8FC),
  primary: Color(0xFF5A47C0),
  accent: Color(0xFFA34A1F),
  textPrimary: Color(0xFF231F3F),
  textSecondary: Color(0xFF524E78),
  progressBar: Color(0xFFA34A1F),
  progressBarTrack: Color(0xFFE2DAE9),
  controlActive: Color(0xFF231F3F),
  controlInactive: Color(0xFF524E78),
  error: Color(0xFFA8355A),
  chrome: Color(0xFFEEE7F1),
  line: Color(0xFFD6CCE0),
  onPrimary: Color(0xFFFFFFFF),
  accentSoft: Color(0x1F5A47C0),
  textFaint: Color(0xFF5D5883),
);
