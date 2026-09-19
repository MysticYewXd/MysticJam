import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/custom_theme_data.dart';
import '../../core/theme/theme_library.dart';
import '../../core/theme/theme_model.dart';
import '../../core/theme/theme_provider.dart';
import 'color_field.dart';

const _weightOptions = <String, FontWeight>{
  'Light': FontWeight.w300,
  'Regular': FontWeight.w400,
  'Medium': FontWeight.w500,
  'Semi Bold': FontWeight.w600,
  'Bold': FontWeight.w700,
  'Black': FontWeight.w900,
};

/// Edits a single [CustomThemeData] in place with a live preview mocking up
/// a track row and the now-playing title, so color/typography/shape changes
/// are visible immediately rather than only after switching themes.
class ThemeDetailEditorScreen extends ConsumerStatefulWidget {
  final CustomThemeData draft;

  /// Whether [draft] already exists in the saved library (Save overwrites)
  /// versus being a fresh duplicate-from-preset/new theme (Save creates).
  final bool isNew;

  const ThemeDetailEditorScreen({
    super.key,
    required this.draft,
    required this.isNew,
  });

  @override
  ConsumerState<ThemeDetailEditorScreen> createState() =>
      _ThemeDetailEditorScreenState();
}

class _ThemeDetailEditorScreenState
    extends ConsumerState<ThemeDetailEditorScreen> {
  late CustomThemeData _draft;
  late TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _draft = widget.draft;
    _nameController = TextEditingController(text: _draft.name);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _update({
    AppColorScheme? colors,
    AppTypography? typography,
    AppShapes? shapes,
  }) {
    setState(() {
      _draft = _draft.copyWith(
        colors: colors,
        typography: typography,
        shapes: shapes,
      );
    });
  }

  Future<void> _save() async {
    final named = _draft.copyWith(
      name: _nameController.text.trim().isEmpty
          ? 'Untitled'
          : _nameController.text.trim(),
    );
    final library = ref.read(themeLibraryProvider.notifier);
    if (widget.isNew) {
      final saved = await library.createTheme(named);
      setState(() => _draft = saved);
    } else {
      await library.updateTheme(named);
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final baseTheme = ref.watch(themeProvider);
    // The live preview always reflects _draft directly (not the app-wide
    // active theme), so edits show up instantly without publishing them
    // globally until Save is pressed.
    final previewTheme = AppTheme(
      name: _draft.name,
      author: baseTheme.author,
      colors: _draft.colors,
      typography: _draft.typography,
      shapes: _draft.shapes,
      layout: baseTheme.layout,
      icons: baseTheme.icons,
      animations: baseTheme.animations,
      assets: baseTheme.assets,
    );

    return Scaffold(
      backgroundColor: baseTheme.colors.background,
      appBar: AppBar(
        title: Text(widget.isNew ? 'New Theme' : 'Edit Theme'),
        actions: [TextButton(onPressed: _save, child: const Text('Save'))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _nameController,
            style: TextStyle(color: baseTheme.colors.textPrimary),
            decoration: const InputDecoration(labelText: 'Theme name'),
          ),
          const SizedBox(height: 20),
          _PreviewCard(theme: previewTheme),
          const SizedBox(height: 24),
          _SectionLabel('Colors', theme: baseTheme),
          ColorField(
            label: 'Background',
            value: _draft.colors.background,
            theme: baseTheme,
            onChanged: (c) => _update(colors: _colorsWith(background: c)),
          ),
          ColorField(
            label: 'Surface',
            value: _draft.colors.surface,
            theme: baseTheme,
            onChanged: (c) => _update(colors: _colorsWith(surface: c)),
          ),
          ColorField(
            label: 'Primary',
            value: _draft.colors.primary,
            theme: baseTheme,
            onChanged: (c) => _update(
              colors: _colorsWith(primary: c, progressBar: c),
            ),
          ),
          ColorField(
            label: 'Accent',
            value: _draft.colors.accent,
            theme: baseTheme,
            onChanged: (c) => _update(colors: _colorsWith(accent: c)),
          ),
          ColorField(
            label: 'Text (primary)',
            value: _draft.colors.textPrimary,
            theme: baseTheme,
            onChanged: (c) => _update(
              colors: _colorsWith(textPrimary: c, controlActive: c),
            ),
          ),
          ColorField(
            label: 'Text (secondary)',
            value: _draft.colors.textSecondary,
            theme: baseTheme,
            onChanged: (c) => _update(
              colors: _colorsWith(textSecondary: c, controlInactive: c),
            ),
          ),
          ColorField(
            label: 'Progress track',
            value: _draft.colors.progressBarTrack,
            theme: baseTheme,
            onChanged: (c) => _update(colors: _colorsWith(progressBarTrack: c)),
          ),
          ColorField(
            label: 'Error',
            value: _draft.colors.error,
            theme: baseTheme,
            onChanged: (c) => _update(colors: _colorsWith(error: c)),
          ),
          const SizedBox(height: 24),
          _SectionLabel('Typography', theme: baseTheme),
          _SizeSlider(
            label: 'Header size',
            value: _draft.typography.headerSize,
            min: 16,
            max: 32,
            theme: baseTheme,
            onChanged: (v) =>
                _update(typography: _typographyWith(headerSize: v)),
          ),
          _WeightDropdown(
            label: 'Header weight',
            value: _draft.typography.headerWeight,
            theme: baseTheme,
            onChanged: (w) =>
                _update(typography: _typographyWith(headerWeight: w)),
          ),
          _SizeSlider(
            label: 'Body size',
            value: _draft.typography.bodySize,
            min: 11,
            max: 20,
            theme: baseTheme,
            onChanged: (v) => _update(typography: _typographyWith(bodySize: v)),
          ),
          _WeightDropdown(
            label: 'Body weight',
            value: _draft.typography.bodyWeight,
            theme: baseTheme,
            onChanged: (w) =>
                _update(typography: _typographyWith(bodyWeight: w)),
          ),
          _SizeSlider(
            label: 'Lyrics size',
            value: _draft.typography.lyricsSize,
            min: 12,
            max: 24,
            theme: baseTheme,
            onChanged: (v) =>
                _update(typography: _typographyWith(lyricsSize: v)),
          ),
          const SizedBox(height: 24),
          _SectionLabel('Shape', theme: baseTheme),
          _SizeSlider(
            label: 'Corner radius',
            value: _draft.shapes.cornerRadius,
            min: 0,
            max: 28,
            theme: baseTheme,
            onChanged: (v) => _update(
              shapes: AppShapes(
                cornerRadius: v,
                borderWidth: _draft.shapes.borderWidth,
                cardElevation: _draft.shapes.cardElevation,
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  AppColorScheme _colorsWith({
    Color? background,
    Color? surface,
    Color? primary,
    Color? accent,
    Color? textPrimary,
    Color? textSecondary,
    Color? progressBar,
    Color? progressBarTrack,
    Color? controlActive,
    Color? controlInactive,
    Color? error,
  }) {
    return _draft.colors.copyWith(
      background: background,
      surface: surface,
      primary: primary,
      accent: accent,
      textPrimary: textPrimary,
      textSecondary: textSecondary,
      progressBar: progressBar,
      progressBarTrack: progressBarTrack,
      controlActive: controlActive,
      controlInactive: controlInactive,
      error: error,
    );
  }

  AppTypography _typographyWith({
    double? headerSize,
    FontWeight? headerWeight,
    double? bodySize,
    FontWeight? bodyWeight,
    double? lyricsSize,
    FontWeight? lyricsWeight,
  }) {
    final t = _draft.typography;
    return AppTypography(
      fontFamily: t.fontFamily,
      displayFamily: t.displayFamily,
      headerSize: headerSize ?? t.headerSize,
      headerWeight: headerWeight ?? t.headerWeight,
      bodySize: bodySize ?? t.bodySize,
      bodyWeight: bodyWeight ?? t.bodyWeight,
      lyricsSize: lyricsSize ?? t.lyricsSize,
      lyricsWeight: lyricsWeight ?? t.lyricsWeight,
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  final AppTheme theme;
  const _SectionLabel(this.text, {required this.theme});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
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

class _SizeSlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final AppTheme theme;
  final ValueChanged<double> onChanged;

  const _SizeSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.theme,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: TextStyle(color: theme.colors.textPrimary, fontSize: 13),
          ),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            activeColor: theme.colors.primary,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 28,
          child: Text(
            value.round().toString(),
            style: TextStyle(color: theme.colors.textSecondary, fontSize: 12),
          ),
        ),
      ],
    );
  }
}

class _WeightDropdown extends StatelessWidget {
  final String label;
  final FontWeight value;
  final AppTheme theme;
  final ValueChanged<FontWeight> onChanged;

  const _WeightDropdown({
    required this.label,
    required this.value,
    required this.theme,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: TextStyle(color: theme.colors.textPrimary, fontSize: 13),
          ),
        ),
        Expanded(
          child: DropdownButton<FontWeight>(
            value: value,
            isExpanded: true,
            dropdownColor: theme.colors.surface,
            style: TextStyle(color: theme.colors.textPrimary),
            items: _weightOptions.entries
                .map(
                  (e) => DropdownMenuItem(value: e.value, child: Text(e.key)),
                )
                .toList(),
            onChanged: (w) {
              if (w != null) onChanged(w);
            },
          ),
        ),
      ],
    );
  }
}

class _PreviewCard extends StatelessWidget {
  final AppTheme theme;
  const _PreviewCard({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colors.surface,
        borderRadius: BorderRadius.circular(theme.shapes.cornerRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            theme.name.isEmpty ? 'Preview' : theme.name,
            style: TextStyle(
              color: theme.colors.textPrimary,
              fontSize: theme.typography.headerSize,
              fontWeight: theme.typography.headerWeight,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Now playing preview',
            style: TextStyle(
              color: theme.colors.textSecondary,
              fontSize: theme.typography.bodySize,
            ),
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: 0.4,
              color: theme.colors.progressBar,
              backgroundColor: theme.colors.progressBarTrack,
              minHeight: 4,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(Icons.skip_previous, color: theme.colors.controlActive),
              const SizedBox(width: 12),
              Icon(
                Icons.play_circle_fill,
                color: theme.colors.primary,
                size: 36,
              ),
              const SizedBox(width: 12),
              Icon(Icons.skip_next, color: theme.colors.controlInactive),
              const Spacer(),
              Icon(Icons.error_outline, color: theme.colors.error, size: 18),
            ],
          ),
        ],
      ),
    );
  }
}
