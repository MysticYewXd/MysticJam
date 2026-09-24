import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/theme_provider.dart';
import 'themed_icon.dart';

/// Vesper round icon button (transport row, favourite/more, queue): rests in
/// the muted text colour, brightens and gets a soft ground on hover, and shows
/// in the primary colour when [active] (a toggled-on shuffle/repeat). Icons
/// come from [ThemedIconSlot] so themes can still swap them; [tooltip] doubles
/// as the accessibility label.
class RoundIconButton extends ConsumerStatefulWidget {
  final ThemedIconSlot slot;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool active;
  final double diameter;
  final double? iconSize;

  const RoundIconButton({
    super.key,
    required this.slot,
    required this.tooltip,
    required this.onPressed,
    this.active = false,
    this.diameter = 40,
    this.iconSize,
  });

  @override
  ConsumerState<RoundIconButton> createState() => _RoundIconButtonState();
}

class _RoundIconButtonState extends ConsumerState<RoundIconButton> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final enabled = widget.onPressed != null;
    final color = !enabled
        ? theme.colors.controlInactive.withValues(alpha: 0.45)
        : widget.active
        ? theme.colors.primary
        : _hovered
        ? theme.colors.controlActive
        : theme.colors.controlInactive;

    return Tooltip(
      message: widget.tooltip,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: widget.tooltip,
        toggled: widget.active,
        onTap: widget.onPressed,
        excludeSemantics: true,
        child: InkResponse(
          onTap: widget.onPressed,
          onHover: (v) => setState(() => _hovered = v),
          onFocusChange: (v) => setState(() => _focused = v),
          customBorder: const CircleBorder(),
          highlightShape: BoxShape.circle,
          containedInkWell: true,
          hoverColor: Colors.transparent,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            width: widget.diameter,
            height: widget.diameter,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: enabled && (_hovered || _focused)
                  ? theme.colors.progressBarTrack
                  : Colors.transparent,
              border: _focused
                  ? Border.all(color: theme.colors.accent, width: 2)
                  : null,
            ),
            child: Center(
              child: ThemedIcon(
                widget.slot,
                size: widget.iconSize ?? widget.diameter * 0.55,
                color: color,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Vesper play/pause button: the one filled, glowing circle in a view. The
/// glyph cross-fades between play and pause.
class PlayButton extends ConsumerStatefulWidget {
  final bool playing;
  final VoidCallback? onPressed;
  final double diameter;

  const PlayButton({
    super.key,
    required this.playing,
    required this.onPressed,
    this.diameter = 64,
  });

  @override
  ConsumerState<PlayButton> createState() => _PlayButtonState();
}

class _PlayButtonState extends ConsumerState<PlayButton> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final label = widget.playing ? 'Pause' : 'Play';

    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        onTap: widget.onPressed,
        excludeSemantics: true,
        child: AnimatedScale(
          scale: _hovered ? 1.06 : 1.0,
          duration: const Duration(milliseconds: 140),
          child: InkResponse(
            onTap: widget.onPressed,
            onHover: (v) => setState(() => _hovered = v),
            onFocusChange: (v) => setState(() => _focused = v),
            customBorder: const CircleBorder(),
            highlightShape: BoxShape.circle,
            containedInkWell: true,
            child: Container(
              width: widget.diameter,
              height: widget.diameter,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colors.primary,
                border: _focused
                    ? Border.all(color: theme.colors.accent, width: 2)
                    : null,
                boxShadow: [
                  BoxShadow(
                    color: theme.colors.primary.withValues(alpha: 0.25),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 150),
                transitionBuilder: (child, animation) =>
                    ScaleTransition(scale: animation, child: child),
                child: ThemedIcon(
                  widget.playing ? ThemedIconSlot.pause : ThemedIconSlot.play,
                  key: ValueKey(widget.playing),
                  size: widget.diameter * 0.5,
                  color: theme.colors.onPrimary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
