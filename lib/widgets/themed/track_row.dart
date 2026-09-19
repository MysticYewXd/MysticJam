import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format_duration.dart';
import '../../core/library/database.dart';
import '../../core/playback/playback_controller.dart';
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

class _TrackRowState extends ConsumerState<TrackRow> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
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
                if (widget.showFormat) ...[
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

/// Three-bar equalizer glyph. Bars move only while [animating]; when paused
/// they rest at fixed heights, so the playing row is still identifiable.
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
  Duration _elapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((d) => setState(() => _elapsed = d));
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
    super.dispose();
  }

  static const _rest = [0.55, 0.9, 0.4];
  static const _speed = [5.1, 6.3, 4.2];

  @override
  Widget build(BuildContext context) {
    final t = _elapsed.inMilliseconds / 1000;
    return SizedBox(
      height: widget.height,
      width: 16,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (var i = 0; i < 3; i++)
            Container(
              width: 4,
              height:
                  widget.height *
                  (widget.animating
                      ? 0.25 + 0.75 * (0.5 + 0.5 * math.sin(t * _speed[i] + i))
                      : _rest[i]),
              decoration: BoxDecoration(
                color: widget.color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
        ],
      ),
    );
  }
}
