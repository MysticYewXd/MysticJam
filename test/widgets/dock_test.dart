import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:music_player/widgets/themed/dock.dart';
import 'package:music_player/widgets/themed/themed_icon.dart';

Widget _host() => const ProviderScope(
  child: MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.bottomCenter,
        child: Dock(
          items: [
            DockItem(
              slot: ThemedIconSlot.library,
              label: 'Library',
              selected: true,
              onTap: _noop,
            ),
            DockItem(
              slot: ThemedIconSlot.album,
              label: 'Albums',
              selected: false,
              onTap: _noop,
            ),
          ],
        ),
      ),
    ),
  ),
);

void _noop() {}

double _firstIconSize(WidgetTester tester) {
  final box = tester.widget<AnimatedContainer>(
    find.byType(AnimatedContainer).first,
  );
  return box.constraints!.maxWidth;
}

void main() {
  testWidgets(
    'hovering the empty space above the pill does not magnify icons',
    (tester) async {
      await tester.pumpWidget(_host());
      final restSize = _firstIconSize(tester);

      final dockTopLeft = tester.getTopLeft(find.byType(Dock));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      // A few pixels below the Dock's own top edge — inside its reserved
      // magnification headroom, above the visible pill.
      await mouse.moveTo(dockTopLeft + const Offset(30, 10));
      await tester.pumpAndSettle();

      expect(_firstIconSize(tester), restSize);
    },
  );

  testWidgets('hovering directly over the pill magnifies the nearest icon', (
    tester,
  ) async {
    await tester.pumpWidget(_host());
    final restSize = _firstIconSize(tester);
    final iconCenter = tester.getCenter(find.byType(AnimatedContainer).first);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(iconCenter);
    await tester.pumpAndSettle();

    expect(_firstIconSize(tester), greaterThan(restSize));
  });

  testWidgets('leaving the dock resets icons to rest size', (tester) async {
    await tester.pumpWidget(_host());
    final restSize = _firstIconSize(tester);
    final iconCenter = tester.getCenter(find.byType(AnimatedContainer).first);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(iconCenter);
    await tester.pumpAndSettle();
    expect(_firstIconSize(tester), greaterThan(restSize));

    await mouse.moveTo(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(_firstIconSize(tester), restSize);
  });
}
