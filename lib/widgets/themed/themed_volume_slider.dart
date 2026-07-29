import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/theme_provider.dart';
import 'themed_icon.dart';

/// A horizontal volume control, Apple-Music-style — sits inline on the
/// Now Playing screen so volume never requires the hardware keys.
class ThemedVolumeSlider extends ConsumerWidget {
  final double value;
  final ValueChanged<double> onChanged;

  const ThemedVolumeSlider({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    return Row(
      children: [
        ThemedIcon(ThemedIconSlot.volumeDown, size: 18, color: theme.colors.textSecondary),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              activeTrackColor: theme.colors.progressBar,
              inactiveTrackColor: theme.colors.progressBarTrack,
              thumbColor: theme.colors.progressBar,
              overlayShape: SliderComponentShape.noOverlay,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              trackHeight: 2,
            ),
            child: Slider(
              value: value.clamp(0.0, 1.0),
              onChanged: onChanged,
            ),
          ),
        ),
        ThemedIcon(ThemedIconSlot.volumeUp, size: 18, color: theme.colors.textSecondary),
      ],
    );
  }
}
