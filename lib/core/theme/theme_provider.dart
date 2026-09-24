import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'custom_theme_data.dart';
import 'default_theme.dart';
import 'theme_library.dart';
import 'theme_model.dart';

/// Merges [override]'s colors/typography/shapes onto [base], keeping
/// everything else (icons/layout/animations/assets) from [base] — see
/// CustomThemeData's doc comment for why those aren't user-customizable.
AppTheme _mergeTheme(AppTheme base, CustomThemeData override) {
  return AppTheme(
    name: override.name,
    author: base.author,
    colors: override.colors,
    typography: override.typography,
    shapes: override.shapes,
    layout: base.layout,
    icons: base.icons,
    animations: base.animations,
    assets: base.assets,
  );
}

/// The active [AppTheme] — [defaultTheme] with the active custom theme (if
/// any) merged on top. Every themed widget reads through this, never a
/// hardcoded Color or Icons.* constant. Derived from [themeLibraryProvider]
/// rather than owning its own state, so the theme editor's
/// create/update/delete/activate calls are the single source of truth.
final themeProvider = Provider<AppTheme>((ref) {
  final libraryState = ref.watch(themeLibraryProvider);
  final override = activeCustomTheme(libraryState);
  return override == null ? defaultTheme : _mergeTheme(defaultTheme, override);
});

/// Derives Flutter's [ThemeData] from the active [AppTheme] so built-in
/// widgets (dialogs, snackbars, scrollbars, text selection) stay visually
/// consistent with custom Themed* widgets without a second source of truth.
final materialThemeDataProvider = Provider<ThemeData>((ref) {
  final theme = ref.watch(themeProvider);
  return _buildThemeData(theme);
});

ThemeData _buildThemeData(AppTheme t) {
  // Themes aren't all dark by definition anymore (see the Light preset) —
  // base the Material brightness on the actual background color so text
  // selection, dialog scrims, and any other brightness-driven default
  // Material picks stay legible instead of assuming dark unconditionally.
  final brightness = ThemeData.estimateBrightnessForColor(t.colors.background);
  final colorSchemeBase = brightness == Brightness.dark
      ? const ColorScheme.dark()
      : const ColorScheme.light();
  final colorScheme = colorSchemeBase.copyWith(
    surface: t.colors.surface,
    primary: t.colors.primary,
    secondary: t.colors.accent,
    error: t.colors.error,
    onSurface: t.colors.textPrimary,
    onPrimary: t.colors.onPrimary,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    scaffoldBackgroundColor: t.colors.background,
    colorScheme: colorScheme,
    fontFamily: t.typography.fontFamily,
    textTheme: TextTheme(
      headlineSmall: TextStyle(
        fontSize: t.typography.headerSize,
        fontWeight: t.typography.headerWeight,
        color: t.colors.textPrimary,
      ),
      bodyMedium: TextStyle(
        fontSize: t.typography.bodySize,
        fontWeight: t.typography.bodyWeight,
        color: t.colors.textPrimary,
      ),
      bodySmall: TextStyle(
        fontSize: t.typography.bodySize,
        fontWeight: t.typography.bodyWeight,
        color: t.colors.textSecondary,
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      titleTextStyle: t.typography.display(24, color: t.colors.textPrimary),
      iconTheme: IconThemeData(color: t.colors.textPrimary),
    ),
    cardTheme: CardThemeData(
      color: t.colors.surface,
      elevation: t.shapes.cardElevation,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(t.shapes.cornerRadius),
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: t.colors.progressBar,
      linearTrackColor: t.colors.progressBarTrack,
    ),
    // Without this, snackbars (delete confirmations, the Undo action, scan
    // results) fall back to Flutter's own light-grey default regardless of
    // the active theme — jarring against a dark theme and easy to misread.
    snackBarTheme: SnackBarThemeData(
      backgroundColor: t.colors.surface,
      contentTextStyle: TextStyle(color: t.colors.textPrimary),
      actionTextColor: t.colors.primary,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(t.shapes.cornerRadius),
      ),
    ),
  );
}
