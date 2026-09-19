import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/custom_theme_data.dart';
import '../../core/theme/default_theme.dart';
import '../../core/theme/theme_library.dart';
import '../../core/theme/theme_model.dart';
import '../../core/theme/theme_presets.dart';
import '../../core/theme/theme_provider.dart';
import '../../widgets/confirm_dialog.dart';
import 'theme_detail_editor_screen.dart';

/// Theme picker/library: the built-in Default, the built-in presets, and
/// anything the user has saved. Tapping a row applies it immediately app-
/// wide (themeProvider watches themeLibraryProvider, see theme_provider.dart)
/// — there's no separate "Apply" step. Presets can't be edited in place;
/// editing one duplicates it into a new saved theme first, same as most
/// "starting point" preset systems.
class ThemeEditorScreen extends ConsumerWidget {
  const ThemeEditorScreen({super.key});

  Future<void> _editPreset(BuildContext context, WidgetRef ref, CustomThemeData preset) async {
    final draft = CustomThemeData(
      id: 'draft',
      name: '${preset.name} copy',
      colors: preset.colors,
      typography: preset.typography,
      shapes: preset.shapes,
    );
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ThemeDetailEditorScreen(draft: draft, isNew: true)),
    );
  }

  Future<void> _editSaved(BuildContext context, CustomThemeData saved) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ThemeDetailEditorScreen(draft: saved, isNew: false)),
    );
  }

  Future<void> _deleteSaved(BuildContext context, WidgetRef ref, CustomThemeData saved) async {
    final confirmed = await confirmDestructiveAction(
      context,
      ref,
      title: 'Delete Theme?',
      message: '"${saved.name}" will be deleted. If it\'s the active theme, the app reverts to Default.',
    );
    if (confirmed) {
      await ref.read(themeLibraryProvider.notifier).deleteTheme(saved.id);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    final libraryState = ref.watch(themeLibraryProvider);
    final library = ref.read(themeLibraryProvider.notifier);

    return Scaffold(
      backgroundColor: theme.colors.background,
      appBar: AppBar(
        title: Text('Themes', style: TextStyle(color: theme.colors.textPrimary)),
        actions: [
          IconButton(
            tooltip: 'New Theme',
            icon: Icon(Icons.add, color: theme.colors.textPrimary),
            onPressed: () async {
              final draft = CustomThemeData.fromAppTheme('draft', 'My Theme', theme);
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => ThemeDetailEditorScreen(draft: draft, isNew: true)),
              );
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _SectionHeader('Built-in', theme: theme),
          _ThemeRow(
            name: 'Vesper Dusk',
            colors: defaultTheme.colors,
            selected: libraryState.activeThemeId == null,
            theme: theme,
            onTap: () => library.setActiveTheme(null),
          ),
          for (final preset in builtInPresets)
            _ThemeRow(
              name: preset.name,
              colors: preset.colors,
              selected: libraryState.activeThemeId == preset.id,
              theme: theme,
              onTap: () => library.setActiveTheme(preset.id),
              onEdit: () => _editPreset(context, ref, preset),
            ),
          if (libraryState.savedThemes.isNotEmpty) ...[
            _SectionHeader('My Themes', theme: theme),
            for (final saved in libraryState.savedThemes)
              _ThemeRow(
                name: saved.name,
                colors: saved.colors,
                selected: libraryState.activeThemeId == saved.id,
                theme: theme,
                onTap: () => library.setActiveTheme(saved.id),
                onEdit: () => _editSaved(context, saved),
                onDelete: () => _deleteSaved(context, ref, saved),
              ),
          ],
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  final AppTheme theme;
  const _SectionHeader(this.text, {required this.theme});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          color: theme.colors.textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1,
        ),
      ),
    );
  }
}

class _ThemeRow extends StatelessWidget {
  final String name;
  final AppColorScheme colors;
  final bool selected;
  final AppTheme theme;
  final VoidCallback onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const _ThemeRow({
    required this.name,
    required this.colors,
    required this.selected,
    required this.theme,
    required this.onTap,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: colors.primary,
          shape: BoxShape.circle,
          border: Border.all(color: colors.background, width: 2),
        ),
      ),
      title: Text(name, style: TextStyle(color: theme.colors.textPrimary)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (selected) Icon(Icons.check_circle, color: theme.colors.primary, size: 20),
          if (onEdit != null)
            IconButton(
              icon: Icon(Icons.edit_outlined, color: theme.colors.textSecondary, size: 20),
              onPressed: onEdit,
            ),
          if (onDelete != null)
            IconButton(
              icon: Icon(Icons.delete_outline, color: theme.colors.error, size: 20),
              onPressed: onDelete,
            ),
        ],
      ),
    );
  }
}
