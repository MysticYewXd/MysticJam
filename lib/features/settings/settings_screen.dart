import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/library/library_providers.dart';
import '../../core/theme/theme_library.dart';
import '../../core/theme/theme_provider.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/themed/themed_icon.dart';
import '../theme_editor/theme_editor_screen.dart';
import 'look_and_feel_screen.dart';

const _lightPresetId = 'preset-light';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Widget _sectionHeader(BuildContext context, WidgetRef ref, String label) {
    final theme = ref.watch(themeProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: theme.colors.textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1,
        ),
      ),
    );
  }

  Future<void> _clearLibrary(BuildContext context, WidgetRef ref) async {
    final confirmed = await confirmDestructiveAction(
      context,
      ref,
      title: 'Clear Library?',
      message:
          'Every song and playlist will be removed. This cannot be undone. '
          'Files on disk are not deleted.',
      confirmLabel: 'Clear',
    );
    if (!confirmed) return;
    await ref.read(libraryRepositoryProvider).clearEverything();
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Library cleared')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    final activeThemeId = ref.watch(themeLibraryProvider).activeThemeId;
    final isLight = activeThemeId == _lightPresetId;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Settings',
          style: TextStyle(color: theme.colors.textPrimary),
        ),
      ),
      body: ListView(
        children: [
          _sectionHeader(context, ref, 'About'),
          ListTile(
            leading: ThemedIcon(
              ThemedIconSlot.library,
              color: theme.colors.textSecondary,
            ),
            title: Text(
              'MysticJam',
              style: TextStyle(color: theme.colors.textPrimary),
            ),
            subtitle: Text(
              'Local-only music player — no accounts, no streaming.',
              style: TextStyle(color: theme.colors.textSecondary),
            ),
          ),
          ListTile(
            leading: ThemedIcon(
              ThemedIconSlot.fileAdd,
              color: theme.colors.textSecondary,
            ),
            title: Text(
              'Supported formats',
              style: TextStyle(color: theme.colors.textPrimary),
            ),
            subtitle: Text(
              'MP3, AAC/M4A, FLAC, WAV, OGG, Opus, WMA, APE, plus audio from '
              'MP4/MKV/WEBM/MOV/AVI. Real tags (artist/album/art) for MP3, FLAC, '
              'OGG, Opus, M4A/AAC, APE and WMA — WAV and video containers use '
              'the filename.',
              style: TextStyle(color: theme.colors.textSecondary),
            ),
          ),
          const Divider(),
          _sectionHeader(context, ref, 'Appearance'),
          SwitchListTile(
            secondary: Icon(
              isLight ? Icons.light_mode : Icons.dark_mode,
              color: theme.colors.textSecondary,
            ),
            title: Text(
              'Light Mode',
              style: TextStyle(color: theme.colors.textPrimary),
            ),
            subtitle: Text(
              isLight ? 'True white background' : 'Dark background (default)',
              style: TextStyle(color: theme.colors.textSecondary),
            ),
            activeThumbColor: theme.colors.primary,
            value: isLight,
            onChanged: (value) => ref
                .read(themeLibraryProvider.notifier)
                .setActiveTheme(value ? _lightPresetId : null),
          ),
          ListTile(
            leading: Icon(
              Icons.palette_outlined,
              color: theme.colors.textSecondary,
            ),
            title: Text(
              'Themes',
              style: TextStyle(color: theme.colors.textPrimary),
            ),
            subtitle: Text(
              'Pick a built-in theme or build your own — colors, typography and shape.',
              style: TextStyle(color: theme.colors.textSecondary),
            ),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ThemeEditorScreen()),
            ),
          ),
          ListTile(
            leading: Icon(Icons.tune, color: theme.colors.textSecondary),
            title: Text(
              'Look & Feel',
              style: TextStyle(color: theme.colors.textPrimary),
            ),
            subtitle: Text(
              'Lyrics, lists, player colours and display options.',
              style: TextStyle(color: theme.colors.textSecondary),
            ),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const LookAndFeelScreen()),
            ),
          ),
          const Divider(),
          _sectionHeader(context, ref, 'Library'),
          ListTile(
            leading: ThemedIcon(
              ThemedIconSlot.delete,
              color: theme.colors.error,
            ),
            title: Text(
              'Clear Library',
              style: TextStyle(color: theme.colors.error),
            ),
            subtitle: Text(
              'Removes every song and playlist. Files on disk are not deleted.',
              style: TextStyle(color: theme.colors.textSecondary),
            ),
            onTap: () => _clearLibrary(context, ref),
          ),
        ],
      ),
    );
  }
}
