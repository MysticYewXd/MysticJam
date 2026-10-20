import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:music_player/widgets/themed/themed_volume_slider.dart';

/// Hosts the slider the way Now Playing does: the value comes from outside
/// (the playback state) and every change is fed straight back into it.
class _Host extends StatefulWidget {
  final ValueNotifier<double> volume;
  final List<double> changes;
  const _Host(this.volume, this.changes);

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<double>(
    valueListenable: widget.volume,
    builder: (context, v, _) => ThemedVolumeSlider(
      value: v,
      onChanged: (next) {
        widget.changes.add(next);
        widget.volume.value = next;
      },
    ),
  );
}

void main() {
  late ValueNotifier<double> volume;
  late List<double> changes;

  Future<void> pump(WidgetTester tester) async {
    volume = ValueNotifier(0.5);
    changes = [];
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(width: 400, child: _Host(volume, changes)),
          ),
        ),
      ),
    );
  }

  testWidgets('changes the volume during the drag, not only on release', (
    tester,
  ) async {
    await pump(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(Slider)),
    );
    for (var i = 0; i < 5; i++) {
      await gesture.moveBy(const Offset(-20, 0));
      await tester.pump();
    }
    final duringDrag = changes.length;
    await gesture.up();
    await tester.pump();

    expect(duringDrag, greaterThan(1));
    expect(changes.last, lessThan(0.5));
    expect(tester.widget<Slider>(find.byType(Slider)).value, changes.last);
  });

  testWidgets('follows volume changes made elsewhere', (tester) async {
    await pump(tester);
    volume.value = 0.2;
    await tester.pump();
    expect(tester.widget<Slider>(find.byType(Slider)).value, 0.2);
    expect(changes, isEmpty, reason: 'no change is sent back');
  });
}
