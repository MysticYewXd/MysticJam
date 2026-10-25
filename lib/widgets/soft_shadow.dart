import 'package:flutter/material.dart';

/// A shadow that looks blurred without a blur: [_steps] rounded rects, each
/// a little bigger and fainter, drawn once onto their own cached layer. A
/// real BoxShadow blur is costly on weak integrated GPUs every time the area
/// around it repaints. Matches a `BoxShadow(color, blurRadius, offset)`
/// under a box with [borderRadius] closely enough to swap one for the other.
class SoftShadow extends StatelessWidget {
  final Color color;
  final double blurRadius;
  final Offset offset;
  final double borderRadius;
  final Widget child;

  const SoftShadow({
    super.key,
    required this.color,
    required this.blurRadius,
    this.offset = Offset.zero,
    required this.borderRadius,
    required this.child,
  });

  @override
  Widget build(BuildContext context) => Stack(
    clipBehavior: Clip.none,
    children: [
      Positioned.fill(
        child: RepaintBoundary(
          child: CustomPaint(
            painter: SoftShadowPainter(
              color: color,
              blurRadius: blurRadius,
              offset: offset,
              borderRadius: borderRadius,
            ),
          ),
        ),
      ),
      child,
    ],
  );
}

const _steps = 8;

@visibleForTesting
class SoftShadowPainter extends CustomPainter {
  final Color color;
  final double blurRadius;
  final Offset offset;
  final double borderRadius;

  SoftShadowPainter({
    required this.color,
    required this.blurRadius,
    required this.offset,
    required this.borderRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final box = (offset & size);
    // Layers grow from half the blur inside the box to the full blur
    // outside it; where they overlap they add up to about [color]'s alpha,
    // and fade towards the edge the way a Gaussian blur does.
    final paint = Paint()..color = color.withValues(alpha: color.a / _steps);
    for (var i = 0; i < _steps; i++) {
      final grow = blurRadius * (-0.5 + 1.5 * i / (_steps - 1));
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          box.inflate(grow),
          Radius.circular((borderRadius + grow).clamp(0, double.infinity)),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(SoftShadowPainter old) =>
      old.color != color ||
      old.blurRadius != blurRadius ||
      old.offset != offset ||
      old.borderRadius != borderRadius;
}
