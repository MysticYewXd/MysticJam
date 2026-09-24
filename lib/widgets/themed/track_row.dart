import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format_duration.dart';
import '../../core/library/database.dart';
import '../../core/playback/playback_controller.dart';
import '../../core/settings/app_settings.dart';
import '../../core/theme/theme_provider.dart';
import 'track_art.dart';

/// Vesper track row: art thumbnail, title over subtitle, duration, and
/// hover-only actions. The playing row gets an accent wash, an accent title
/// and animated equalizer bars over its art; hovering any row lifts it onto
/// the surface colour. No dividers and a fixed height, as the spec asks.
class TrackRow extends ConsumerStatefulWidget {
  final Track track;
  final String? subtitle;
  final VoidCallback onTap;

  /// Shown before the art (selection checkboxes).
  final Widget? leading;

  /// Revealed on hover/focus and always shown on the playing row.
  final List<Widget> actions;
  final bool showFormat;

  const TrackRow({
    super.key,
    required this.track,
    required this.onTap,
    this.subtitle,
    this.leading,
    this.actions = const [],
    this.showFormat = true,
  });

  static const height = 60.0;

  @override
  ConsumerState<TrackRow> createState() => _TrackRowState();
}

bool _hasLyrics(Track t) =>
    t.syncedLyrics != null || (t.lyrics?.trim().isNotEmpty ?? false);

class _TrackRowState extends ConsumerState<TrackRow> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final ui = ref.watch(uiPrefsProvider);
    final track = widget.track;
    final isCurrent = ref.watch(
      playbackControllerProvider.select((s) => s.currentTrack?.id == track.id),
    );
    final isPlaying =
        isCurrent &&
        ref.watch(playbackControllerProvider.select((s) => s.isPlaying));
    final radius = BorderRadius.circular(theme.shapes.cornerRadius);
    final showActions = _hovered || _focused || isCurrent;

    final background = isCurrent
        ? theme.colors.accentSoft
        : (_hovered || _focused)
        ? theme.colors.surface
        : Colors.transparent;

    final timeStyle = TextStyle(
      color: theme.colors.textFaint,
      fontSize: 13,
      fontWeight: FontWeight.w500,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return Semantics(
      button: true,
      selected: isCurrent,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        height: TrackRow.height,
        decoration: BoxDecoration(color: background, borderRadius: radius),
        child: InkWell(
          onTap: widget.onTap,
          onHover: (v) => setState(() => _hovered = v),
          onFocusChange: (v) => setState(() => _focused = v),
          borderRadius: radius,
          hoverColor: Colors.transparent,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                if (widget.leading != null) widget.leading!,
                Stack(
                  alignment: Alignment.center,
                  children: [
                    TrackArt(
                      albumArtPath: track.albumArtPath,
                      size: 44,
                      borderRadius: 8,
                    ),
                    if (isCurrent)
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: EqualizerBars(
                            color: theme.colors.accent,
                            animating: isPlaying,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isCurrent
                              ? theme.colors.primary
                              : theme.colors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (widget.subtitle != null)
                        Text(
                          widget.subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: theme.colors.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                    ],
                  ),
                ),
                if (ui.showLyricsIcon && _hasLyrics(track)) ...[
                  Tooltip(
                    message: track.syncedLyrics != null
                        ? 'Synced lyrics'
                        : 'Lyrics',
                    child: Icon(
                      theme.icons.lyrics,
                      size: 16,
                      color: theme.colors.textFaint,
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                if (widget.showFormat && ui.showFormatTag) ...[
                  Text(
                    track.format.toUpperCase(),
                    style: TextStyle(
                      color: theme.colors.textFaint,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                if (track.durationMs != null)
                  Text(
                    formatDuration(Duration(milliseconds: track.durationMs!)),
                    style: timeStyle,
                  ),
                if (widget.actions.isNotEmpty)
                  Opacity(
                    opacity: showActions ? 1 : 0,
                    // Kept in the tree (just invisible) so the row never
                    // reflows on hover.
                    child: IgnorePointer(
                      ignoring: !showActions,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [const SizedBox(width: 4), ...widget.actions],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Bar heights (0..1 of the glyph height) for the equalizer at [seconds] of
/// animation, or the resting shape when [seconds] is null. A pure function of
/// elapsed time — never of frame count — so the motion looks the same at 30,
/// 60, 144 or 240 Hz.
List<double> equalizerFractions(double? seconds) {
  const rest = [0.55, 0.9, 0.4];
  const speed = [5.1, 6.3, 4.2];
  if (seconds == null) return rest;
  return [
    for (var i = 0; i < 3; i++)
      0.25 + 0.75 * (0.5 + 0.5 * math.sin(seconds * speed[i] + i)),
  ];
}

/// Three-bar equalizer glyph. Bars move only while [animating]; when paused
/// they rest at fixed heights, so the playing row is still identifiable.
/// Painted straight from a time notifier inside its own repaint boundary, so
/// a new frame repaints just these bars — no widget rebuild, and nothing
/// around them, however high the refresh rate.
class EqualizerBars extends StatefulWidget {
  final Color color;
  final bool animating;
  final double height;

  const EqualizerBars({
    super.key,
    required this.color,
    required this.animating,
    this.height = 18,
  });

  @override
  State<EqualizerBars> createState() => _EqualizerBarsState();
}

class _EqualizerBarsState extends State<EqualizerBars>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _seconds = ValueNotifier<double>(0);

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((d) => _seconds.value = d.inMicroseconds / 1e6);
    if (widget.animating) _ticker.start();
  }

  @override
  void didUpdateWidget(EqualizerBars old) {
    super.didUpdateWidget(old);
    if (widget.animating && !_ticker.isActive) {
      _ticker.start();
    } else if (!widget.animating && _ticker.isActive) {
      _ticker.stop();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _seconds.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        size: Size(16, widget.height),
        painter: _EqualizerPainter(
          _seconds,
          animating: widget.animating,
          color: widget.color,
        ),
      ),
    );
  }
}

class _EqualizerPainter extends CustomPainter {
  final ValueNotifier<double> seconds;
  final bool animating;
  final Color color;

  _EqualizerPainter(
    this.seconds, {
    required this.animating,
    required this.color,
  }) : super(repaint: seconds);

  @override
  void paint(Canvas canvas, Size size) {
    final fractions = equalizerFractions(animating ? seconds.value : null);
    final paint = Paint()..color = color;
    const barWidth = 4.0;
    final gap = (size.width - 3 * barWidth) / 2;
    for (var i = 0; i < 3; i++) {
      final h = size.height * fractions[i];
      final x = i * (barWidth + gap);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, size.height - h, barWidth, h),
          const Radius.circular(2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_EqualizerPainter old) =>
      old.animating != animating || old.color != color;
}
