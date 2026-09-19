import 'package:flutter/material.dart';

import 'theme_model.dart';

/// A user-created or built-in-preset theme override — a JSON-serializable
/// subset of [AppTheme] covering colors/typography/shapes only. Icons,
/// layout, animations and assets always come from [defaultTheme]; letting
/// users override those too would multiply the editor's surface area for
/// comparatively little payoff over just re-coloring/re-sizing the existing
/// look. See ThemeLibraryNotifier.activeAppTheme for how this merges onto
/// the base theme.
class CustomThemeData {
  final String id;
  final String name;
  final AppColorScheme colors;
  final AppTypography typography;
  final AppShapes shapes;

  const CustomThemeData({
    required this.id,
    required this.name,
    required this.colors,
    required this.typography,
    required this.shapes,
  });

  CustomThemeData copyWith({
    String? name,
    AppColorScheme? colors,
    AppTypography? typography,
    AppShapes? shapes,
  }) {
    return CustomThemeData(
      id: id,
      name: name ?? this.name,
      colors: colors ?? this.colors,
      typography: typography ?? this.typography,
      shapes: shapes ?? this.shapes,
    );
  }

  factory CustomThemeData.fromAppTheme(String id, String name, AppTheme base) {
    return CustomThemeData(
      id: id,
      name: name,
      colors: base.colors,
      typography: base.typography,
      shapes: base.shapes,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'colors': {
      'background': colors.background.toARGB32(),
      'surface': colors.surface.toARGB32(),
      'primary': colors.primary.toARGB32(),
      'accent': colors.accent.toARGB32(),
      'textPrimary': colors.textPrimary.toARGB32(),
      'textSecondary': colors.textSecondary.toARGB32(),
      'progressBar': colors.progressBar.toARGB32(),
      'progressBarTrack': colors.progressBarTrack.toARGB32(),
      'controlActive': colors.controlActive.toARGB32(),
      'controlInactive': colors.controlInactive.toARGB32(),
      'error': colors.error.toARGB32(),
      for (final e in colors.explicitExtras.entries) e.key: e.value.toARGB32(),
    },
    'typography': {
      'fontFamily': typography.fontFamily,
      'headerSize': typography.headerSize,
      'headerWeight': FontWeight.values.indexOf(typography.headerWeight),
      'bodySize': typography.bodySize,
      'bodyWeight': FontWeight.values.indexOf(typography.bodyWeight),
      'lyricsSize': typography.lyricsSize,
      'lyricsWeight': FontWeight.values.indexOf(typography.lyricsWeight),
    },
    'shapes': {
      'cornerRadius': shapes.cornerRadius,
      'borderWidth': shapes.borderWidth,
      'cardElevation': shapes.cardElevation,
    },
  };

  factory CustomThemeData.fromJson(Map<String, dynamic> json) {
    final c = json['colors'] as Map<String, dynamic>;
    final t = json['typography'] as Map<String, dynamic>;
    final s = json['shapes'] as Map<String, dynamic>;

    Color color(String key) => Color(c[key] as int);
    Color? optionalColor(String key) =>
        c[key] is int ? Color(c[key] as int) : null;
    FontWeight weight(String key) =>
        FontWeight.values[(t[key] as int).clamp(0, 8)];

    return CustomThemeData(
      id: json['id'] as String,
      name: json['name'] as String,
      colors: AppColorScheme(
        background: color('background'),
        surface: color('surface'),
        primary: color('primary'),
        accent: color('accent'),
        textPrimary: color('textPrimary'),
        textSecondary: color('textSecondary'),
        progressBar: color('progressBar'),
        progressBarTrack: color('progressBarTrack'),
        controlActive: color('controlActive'),
        controlInactive: color('controlInactive'),
        error: color('error'),
        chrome: optionalColor('chrome'),
        line: optionalColor('line'),
        onPrimary: optionalColor('onPrimary'),
        accentSoft: optionalColor('accentSoft'),
        textFaint: optionalColor('textFaint'),
      ),
      typography: AppTypography(
        // Themes saved before the Vesper fonts shipped name Roboto, which the
        // app never bundled; they get the new sans so they match the rest.
        fontFamily: t['fontFamily'] == 'Roboto'
            ? sansFontFamily
            : t['fontFamily'] as String,
        displayFamily: (t['displayFamily'] as String?) ?? displayFontFamily,
        headerSize: (t['headerSize'] as num).toDouble(),
        headerWeight: weight('headerWeight'),
        bodySize: (t['bodySize'] as num).toDouble(),
        bodyWeight: weight('bodyWeight'),
        lyricsSize: (t['lyricsSize'] as num).toDouble(),
        lyricsWeight: weight('lyricsWeight'),
      ),
      shapes: AppShapes(
        cornerRadius: (s['cornerRadius'] as num).toDouble(),
        borderWidth: (s['borderWidth'] as num).toDouble(),
        cardElevation: (s['cardElevation'] as num).toDouble(),
      ),
    );
  }
}
