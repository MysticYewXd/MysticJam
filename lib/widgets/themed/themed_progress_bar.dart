import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/theme_provider.dart';

class ThemedProgressBar extends ConsumerWidget {
  final Duration position;
  final Duration duration;
  final ValueChanged<Duration>? onSeek;

  const ThemedProgressBar({
    super.key,
    required this.position,
    required this.duration,
    this.onSeek,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    final totalMs = duration.inMilliseconds <= 0 ? 1 : duration.inMilliseconds;
    final value = (position.inMilliseconds / totalMs).clamp(0.0, 1.0);
    return SliderTheme(
      data: SliderThemeData(
        activeTrackColor: theme.colors.progressBar,
        inactiveTrackColor: theme.colors.progressBarTrack,
        thumbColor: theme.colors.progressBar,
        overlayShape: SliderComponentShape.noOverlay,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
        trackHeight: 2,
      ),
      child: Slider(
        value: value,
        onChanged: onSeek == null
            ? null
            : (v) => onSeek!(Duration(milliseconds: (v * totalMs).round())),
      ),
    );
  }
}
