import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'custom_theme_data.dart';
import 'theme_presets.dart';

class ThemeLibraryState {
  /// User-saved custom themes only — built-in presets are never persisted,
  /// they're baked into the app (see theme_presets.dart) so they always
  /// show up in the picker without needing a first-run seed step.
  final List<CustomThemeData> savedThemes;

  /// Null means "use the built-in default theme" — the normal starting
  /// state, and what a user picking "Default" in the picker sets it back to.
  final String? activeThemeId;

  const ThemeLibraryState({this.savedThemes = const [], this.activeThemeId});

  ThemeLibraryState copyWith({List<CustomThemeData>? savedThemes, String? Function()? activeThemeId}) {
    return ThemeLibraryState(
      savedThemes: savedThemes ?? this.savedThemes,
      activeThemeId: activeThemeId != null ? activeThemeId() : this.activeThemeId,
    );
  }
}

/// Owns the set of saved custom themes plus which one (if any) is active,
/// persisted as a single JSON file so it survives restarts. Kept separate
/// from ThemeProvider's derived AppTheme (see theme_provider.dart) so
/// screens that just need "the current look" don't have to know custom
/// themes exist at all.
class ThemeLibraryNotifier extends Notifier<ThemeLibraryState> {
  static const _fileName = 'custom_themes.json';

  @override
  ThemeLibraryState build() {
    _load();
    return const ThemeLibraryState();
  }

  Future<File> _themeFile() async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, _fileName));
  }

  Future<void> _load() async {
    try {
      final file = await _themeFile();
      if (!await file.exists()) return;
      final raw = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final themesJson = (raw['savedThemes'] as List).cast<Map<String, dynamic>>();
      state = ThemeLibraryState(
        savedThemes: themesJson.map(CustomThemeData.fromJson).toList(),
        activeThemeId: raw['activeThemeId'] as String?,
      );
    } catch (_) {
      // Missing/corrupt state file just means "start fresh" — never block
      // the app on a theme-persistence failure.
    }
  }

  Future<void> _persist() async {
    try {
      final file = await _themeFile();
      final raw = {
        'savedThemes': state.savedThemes.map((t) => t.toJson()).toList(),
        'activeThemeId': state.activeThemeId,
      };
      await file.writeAsString(jsonEncode(raw));
    } catch (_) {
      // Best-effort — a failed save just means the change doesn't survive
      // a restart, not worth surfacing as an error mid-edit.
    }
  }

  String _newId() => 'theme-${DateTime.now().microsecondsSinceEpoch}';

  /// Saves [data] as a new theme under a fresh id (ignoring whatever id it
  /// already carries — used when duplicating a preset or another saved
  /// theme) and makes it active.
  Future<CustomThemeData> createTheme(CustomThemeData data) async {
    final saved = CustomThemeData(
      id: _newId(),
      name: data.name,
      colors: data.colors,
      typography: data.typography,
      shapes: data.shapes,
    );
    state = state.copyWith(
      savedThemes: [...state.savedThemes, saved],
      activeThemeId: () => saved.id,
    );
    await _persist();
    return saved;
  }

  /// Overwrites an already-saved theme in place (same id) — used by the
  /// editor's Save button once a theme has been created, so further edits
  /// don't pile up duplicate entries.
  Future<void> updateTheme(CustomThemeData data) async {
    final index = state.savedThemes.indexWhere((t) => t.id == data.id);
    if (index == -1) return;
    final updated = [...state.savedThemes];
    updated[index] = data;
    state = state.copyWith(savedThemes: updated);
    await _persist();
  }

  Future<void> deleteTheme(String id) async {
    state = state.copyWith(
      savedThemes: state.savedThemes.where((t) => t.id != id).toList(),
      activeThemeId: () => state.activeThemeId == id ? null : state.activeThemeId,
    );
    await _persist();
  }

  /// Pass null to fall back to the built-in default theme.
  Future<void> setActiveTheme(String? id) async {
    state = state.copyWith(activeThemeId: () => id);
    await _persist();
  }
}

final themeLibraryProvider = NotifierProvider<ThemeLibraryNotifier, ThemeLibraryState>(
  ThemeLibraryNotifier.new,
);

/// The currently active custom theme's colors/typography/shapes merged onto
/// [defaultTheme] — icons/layout/animations/assets always come from the
/// base theme (see CustomThemeData's doc comment for why). Null when no
/// custom theme is active, meaning "just use defaultTheme unmodified".
CustomThemeData? activeCustomTheme(ThemeLibraryState state) {
  final id = state.activeThemeId;
  if (id == null) return null;
  for (final theme in state.savedThemes) {
    if (theme.id == id) return theme;
  }
  // A preset can be applied directly (without duplicating it into the
  // saved list first) — e.g. picking it straight from the picker.
  for (final theme in builtInPresets) {
    if (theme.id == id) return theme;
  }
  return null;
}
