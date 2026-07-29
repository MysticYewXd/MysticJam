import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'default_theme.dart';
import 'theme_model.dart';

/// Holds the active [AppTheme]. Every themed widget reads through this —
/// never a hardcoded Color or Icons.* constant.
class ThemeNotifier extends Notifier<AppTheme> {
  @override
  AppTheme build() => defaultTheme;

  void setTheme(AppTheme theme) => state = theme;
}

final themeProvider = NotifierProvider<ThemeNotifier, AppTheme>(ThemeNotifier.new);

/// Derives Flutter's [ThemeData] from the active [AppTheme] so built-in
/// widgets (dialogs, snackbars, scrollbars, text selection) stay visually
/// consistent with custom Themed* widgets without a second source of truth.
final materialThemeDataProvider = Provider<ThemeData>((ref) {
  final theme = ref.watch(themeProvider);
  return _buildThemeData(theme);
});

ThemeData _buildThemeData(AppTheme t) {
  final colorScheme = ColorScheme.dark(
    surface: t.colors.surface,
    primary: t.colors.primary,
    secondary: t.colors.accent,
    error: t.colors.error,
    onSurface: t.colors.textPrimary,
    onPrimary: t.colors.textPrimary,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
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
  );
}
