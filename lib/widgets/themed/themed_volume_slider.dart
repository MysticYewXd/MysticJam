import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/theme_provider.dart';
import 'themed_icon.dart';

/// A horizontal volume control, Apple-Music-style — sits inline on the
/// Now Playing screen so volume never requires the hardware keys.
///
/// The system-volume commit only fires on [onChangeEnd], once per gesture —
/// firing it on every [onChanged] tick (once per pixel of drag) spawns one
/// subprocess call per tick with no ordering guarantee, so whichever call
/// happens to finish last "wins", not the one matching where you released
/// the slider. Dragging is still smooth because drag position is tracked
/// locally and shown immediately, independent of that commit.
class ThemedVolumeSlider extends ConsumerStatefulWidget {
  final double value;
  final ValueChanged<double> onChangeEnd;

  const ThemedVolumeSlider({super.key, required this.value, required this.onChangeEnd});

  @override
  ConsumerState<ThemedVolumeSlider> createState() => _ThemedVolumeSliderState();
}

class _ThemedVolumeSliderState extends ConsumerState<ThemedVolumeSlider> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final displayValue = (_dragValue ?? widget.value).clamp(0.0, 1.0);

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
              value: displayValue,
              onChanged: (v) => setState(() => _dragValue = v),
              onChangeEnd: (v) {
                setState(() => _dragValue = null);
                widget.onChangeEnd(v);
              },
            ),
          ),
        ),
        ThemedIcon(ThemedIconSlot.volumeUp, size: 18, color: theme.colors.textSecondary),
      ],
    );
  }
}
