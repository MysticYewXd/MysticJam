import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/theme_provider.dart';
import 'themed_icon.dart';

/// A horizontal volume control, Apple-Music-style — sits inline on the
/// Now Playing screen so volume never requires the hardware keys.
///
/// Changes the system volume live, on every tick of a drag. That's safe
/// even though each change can be a subprocess on Linux: the volume
/// controller runs one at a time and collapses a fast drag into the newest
/// value (see LinuxSystemVolumeController.setVolume), so the volume always
/// ends where the slider was released.
class ThemedVolumeSlider extends ConsumerWidget {
  final double value;
  final ValueChanged<double> onChanged;

  const ThemedVolumeSlider({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);

    return Row(
      children: [
        ThemedIcon(
          ThemedIconSlot.volumeDown,
          size: 18,
          color: theme.colors.textSecondary,
        ),
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
            child: Slider(value: value.clamp(0.0, 1.0), onChanged: onChanged),
          ),
        ),
        ThemedIcon(
          ThemedIconSlot.volumeUp,
          size: 18,
          color: theme.colors.textSecondary,
        ),
      ],
    );
  }
}
