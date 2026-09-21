import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/theme_provider.dart';
import 'themed_icon.dart';

/// One entry in a [Dock] — a themed icon slot plus what it does when tapped.
class DockItem {
  final ThemedIconSlot slot;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const DockItem({
    required this.slot,
    required this.label,
    required this.selected,
    required this.onTap,
  });
}

/// A floating, macOS-style dock: icons magnify as the mouse passes near
/// them, based on horizontal distance from the pointer to each icon's own
/// center — ported from the magicui/Framer Motion web version the user
/// shared, using Flutter's implicit animations (AnimatedContainer) instead
/// of a spring physics library, since there's no equivalent dependency
/// already in this project worth pulling in for one widget.
///
/// The magnification effect is inherently mouse-driven — MouseRegion has no
/// touch equivalent — so on Android (no hover) this simply renders as a
/// static row of equally-sized, fully tappable icons; nothing is lost
/// there, the effect is purely a desktop nicety.
class Dock extends ConsumerStatefulWidget {
  final List<DockItem> items;
  final double baseSize;
  final double magnifiedSize;
  final double influenceDistance;

  const Dock({
    super.key,
    required this.items,
    this.baseSize = 54,
    this.magnifiedSize = 92,
    this.influenceDistance = 130,
  });

  @override
  ConsumerState<Dock> createState() => _DockState();
}

class _DockState extends ConsumerState<Dock> {
  // Global (screen) pointer X — matches the web version tracking `pageX`.
  // Infinity means "not hovering", which naturally collapses every icon's
  // distance calc back down to its base size.
  final ValueNotifier<double> _mouseX = ValueNotifier(double.infinity);

  @override
  void dispose() {
    _mouseX.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);

    // Resting pill height: just enough around a resting-size icon (see
    // _DockIcon's own 8px vertical padding + icon + 3px gap + 4px dot).
    // Previously the whole pill was sized to always fit the *magnified*
    // icon height, which meant a large, visibly empty strip above the
    // icons whenever nothing was hovered — obvious and ugly on a wide
    // desktop window. The real macOS dock stays a fixed, modest height at
    // rest; magnified icons rise up and overlap *above* the pill instead
    // of the whole pill growing to accommodate them.
    final restPillHeight = widget.baseSize + 26;
    // Generous outer bound so a magnified icon (plus its own padding/gap/
    // dot) always has room to render without being clipped or overflowing
    // — this box is invisible (no background of its own), so being taller
    // than it needs costs nothing visually, unlike the old pill height.
    final maxIconHeight = widget.magnifiedSize + 40;

    // Separate layer: hover magnification repaints only the dock, and the
    // page's own animations don't repaint it.
    return RepaintBoundary(
      child: MouseRegion(
        onHover: (event) {
          // This region is taller than the visible pill (extra headroom for
          // magnified icons to rise into, see maxIconHeight below) — without
          // this gate, the dock started magnifying as soon as the cursor
          // entered that empty reserved space above the pill, well before it
          // actually reached the dock. Only the pill's own vertical band, at
          // the bottom of this region, should count as "on the dock".
          final onPill =
              event.localPosition.dy >= maxIconHeight - restPillHeight;
          _mouseX.value = onPill ? event.position.dx : double.infinity;
        },
        onExit: (_) => _mouseX.value = double.infinity,
        child: SizedBox(
          height: maxIconHeight,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.bottomCenter,
            children: [
              // The glass pill itself — fixed resting height, bottom-anchored
              // in the Stack so it sits right under the icons regardless of
              // how tall the transparent Stack above it is.
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.35),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                      child: Container(
                        height: restPillHeight,
                        decoration: BoxDecoration(
                          color: theme.colors.surface.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.08),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // Icons sit above the pill in the Stack (not inside its
              // ClipRRect), so a magnified icon can visually overlap the
              // pill's top edge instead of being clipped by it.
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                // Three icons at base size need ~190px of width — narrower
                // than that (a narrow/minimized window) and the Row can't
                // fit them, which overflowed rather than resizing since the
                // icons themselves have a fixed minimum size. A horizontal
                // scroll is the same safety net used for Now Playing's
                // transport-controls row for the identical problem: it never
                // overflows, it just becomes scrollable at extreme widths.
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (final item in widget.items)
                        _DockIcon(
                          key: ValueKey(item.slot),
                          item: item,
                          mouseX: _mouseX,
                          baseSize: widget.baseSize,
                          magnifiedSize: widget.magnifiedSize,
                          influenceDistance: widget.influenceDistance,
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DockIcon extends ConsumerStatefulWidget {
  final DockItem item;
  final ValueNotifier<double> mouseX;
  final double baseSize;
  final double magnifiedSize;
  final double influenceDistance;

  const _DockIcon({
    super.key,
    required this.item,
    required this.mouseX,
    required this.baseSize,
    required this.magnifiedSize,
    required this.influenceDistance,
  });

  @override
  ConsumerState<_DockIcon> createState() => _DockIconState();
}

class _DockIconState extends ConsumerState<_DockIcon> {
  final _boxKey = GlobalKey();

  double _sizeFor(double mouseX) {
    if (!mouseX.isFinite) return widget.baseSize;

    final renderBox = _boxKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.attached) return widget.baseSize;

    final centerX =
        renderBox.localToGlobal(Offset.zero).dx + renderBox.size.width / 2;
    final distance = (mouseX - centerX).abs();
    if (distance >= widget.influenceDistance) return widget.baseSize;

    // Linear falloff from magnifiedSize at distance 0 to baseSize at the
    // edge of influenceDistance — the same shape as the web version's
    // [-distance, 0, distance] -> [size, magnification, size] interpolation.
    final t = 1 - (distance / widget.influenceDistance);
    return widget.baseSize + (widget.magnifiedSize - widget.baseSize) * t;
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);

    return ValueListenableBuilder<double>(
      valueListenable: widget.mouseX,
      builder: (context, mouseX, _) {
        final size = _sizeFor(mouseX);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: GestureDetector(
            onTap: widget.item.onTap,
            child: Tooltip(
              message: widget.item.label,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedContainer(
                    key: _boxKey,
                    duration: const Duration(milliseconds: 150),
                    curve: Curves.easeOut,
                    width: size,
                    height: size,
                    decoration: BoxDecoration(
                      color: widget.item.selected
                          ? theme.colors.primary.withValues(alpha: 0.18)
                          : Colors.transparent,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: ThemedIcon(
                        widget.item.slot,
                        size: size * 0.5,
                        color: widget.item.selected
                            ? theme.colors.primary
                            : theme.colors.controlActive,
                      ),
                    ),
                  ),
                  const SizedBox(height: 3),
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 150),
                    opacity: widget.item.selected ? 1 : 0,
                    child: Container(
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(
                        color: theme.colors.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
