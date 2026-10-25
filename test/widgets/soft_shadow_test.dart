import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:music_player/widgets/soft_shadow.dart';

void main() {
  testWidgets('draws layered rounded rects on a cached layer, no blur', (
    tester,
  ) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SoftShadow(
            color: Color(0x59000000),
            blurRadius: 24,
            offset: Offset(0, 8),
            borderRadius: 12,
            child: SizedBox.square(dimension: 100),
          ),
        ),
      ),
    );

    final layer = find.descendant(
      of: find.byType(SoftShadow),
      matching: find.byType(CustomPaint),
    );
    expect(
      find.ancestor(of: layer, matching: find.byType(RepaintBoundary)),
      findsWidgets,
    );
    var expectation = paints;
    for (var i = 0; i < 8; i++) {
      expectation = expectation..rrect();
    }
    expect(tester.renderObject(layer), expectation);
    expect(
      tester.renderObject(layer),
      isNot(paints..something((m, _) => m == #drawPaint)),
    );
  });

  test('repaints only when what it draws changes', () {
    SoftShadowPainter p({double blur = 10}) => SoftShadowPainter(
      color: const Color(0x4D000000),
      blurRadius: blur,
      offset: const Offset(0, 4),
      borderRadius: 8,
    );
    expect(p().shouldRepaint(p()), isFalse);
    expect(p().shouldRepaint(p(blur: 12)), isTrue);
  });
}
