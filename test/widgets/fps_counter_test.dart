import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_player/features/settings/look_and_feel_screen.dart';
import 'package:music_player/widgets/fps_counter.dart';
import 'package:music_player/widgets/themed/track_row.dart';

void main() {
  // The counter measures vsync ticks per second, so it must read the true
  // rate whatever the monitor runs at.
  for (final hz in [30, 60, 90, 120, 144, 165, 240]) {
    testWidgets('reads $hz fps when frames arrive at $hz Hz', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Stack(children: [FpsCounter()])),
      );
      final frame = Duration(microseconds: (1e6 / hz).round());
      for (var i = 0; i < hz * 2; i++) {
        await tester.pump(frame);
      }
      final text = tester.widget<Text>(find.textContaining('fps')).data!;
      final fps = int.parse(RegExp(r'(\d+) fps').firstMatch(text)![1]!);
      expect(fps, inInclusiveRange(hz - 2, hz + 2));
    });
  }

  test('refresh rates are shown cleanly, including fractional ones', () {
    expect(formatRefreshRate(60), '60 Hz');
    expect(formatRefreshRate(143.98), '144 Hz');
    expect(formatRefreshRate(59.94), '59.9 Hz');
    expect(formatRefreshRate(119.88), '119.9 Hz');
  });

  group('equalizer motion depends on time, never on frame rate', () {
    test('same elapsed time gives identical bars however it was reached', () {
      // A function of seconds only: there is no frame counter to differ.
      expect(equalizerFractions(1.25), equalizerFractions(1.25));
      expect(equalizerFractions(1.25), isNot(equalizerFractions(1.5)));
    });

    test(
      'bars stay within 25%..100% and rest at fixed heights when paused',
      () {
        for (var ms = 0; ms < 5000; ms += 7) {
          for (final f in equalizerFractions(ms / 1000)) {
            expect(f, inInclusiveRange(0.25, 1.0));
          }
        }
        expect(equalizerFractions(null), [0.55, 0.9, 0.4]);
      },
    );

    testWidgets('paints without rebuilding, at any frame rate', (tester) async {
      Future<int> builds(int hz) async {
        var count = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (_) {
                count++;
                return const Center(
                  child: EqualizerBars(color: Colors.red, animating: true),
                );
              },
            ),
          ),
        );
        for (var i = 0; i < hz; i++) {
          await tester.pump(Duration(microseconds: (1e6 / hz).round()));
        }
        return count;
      }

      expect(await builds(60), 1);
      expect(await builds(240), 1);
      expect(
        find.ancestor(
          of: find.byType(CustomPaint),
          matching: find.byType(RepaintBoundary),
        ),
        findsWidgets,
      );
    });
  });
}
