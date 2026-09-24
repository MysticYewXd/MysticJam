import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:music_player/core/playback/playback_controller.dart';
import 'package:music_player/core/undo/last_undo_provider.dart';
import 'package:music_player/widgets/app_shortcuts.dart';

class _Recorder extends PlaybackController {
  final PlaybackState initial;
  final List<String> calls;
  _Recorder(this.initial, this.calls);

  @override
  PlaybackState build() => initial;
  @override
  Future<void> togglePlayPause() async => calls.add('toggle');
  @override
  Future<void> next() async => calls.add('next');
  @override
  Future<void> previous() async => calls.add('previous');
  @override
  Future<void> seek(Duration p) async => calls.add('seek ${p.inSeconds}');
  @override
  Future<void> setVolume(double v) async =>
      calls.add('volume ${v.toStringAsFixed(2)}');
}

void main() {
  late List<String> calls;

  Future<void> pump(
    WidgetTester tester, {
    Duration position = const Duration(seconds: 10),
    Duration duration = const Duration(seconds: 100),
    double volume = 0.5,
    Widget body = const SizedBox.expand(),
    List<Override> overrides = const [],
  }) async {
    calls = [];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playbackControllerProvider.overrideWith(
            () => _Recorder(
              PlaybackState(
                position: position,
                duration: duration,
                volume: volume,
              ),
              calls,
            ),
          ),
          ...overrides,
        ],
        child: MaterialApp(
          home: Scaffold(body: body),
          builder: (context, child) => AppShortcuts(child: child!),
        ),
      ),
    );
  }

  testWidgets('Space toggles play/pause', (tester) async {
    await pump(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(calls, ['toggle']);
  });

  testWidgets('Left/Right seek by 5s and stay inside the track', (
    tester,
  ) async {
    await pump(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    expect(calls, ['seek 15', 'seek 5']);
  });

  testWidgets('seeking clamps at the start of the track', (tester) async {
    await pump(tester, position: const Duration(seconds: 2));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    expect(calls, ['seek 0']);
  });

  testWidgets('seeking clamps at the end of the track', (tester) async {
    await pump(tester, position: const Duration(seconds: 98));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    expect(calls, ['seek 100']);
  });

  testWidgets('Ctrl+Left/Right skip tracks', (tester) async {
    await pump(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(calls, ['next', 'previous']);
  });

  testWidgets('Ctrl+Up/Down change volume by 5% and stay within 0..1', (
    tester,
  ) async {
    await pump(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(calls, ['volume 0.55', 'volume 0.45']);
  });

  testWidgets('volume never goes above 100%', (tester) async {
    await pump(tester, volume: 0.98);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(calls, ['volume 1.00']);
  });

  testWidgets('media keys control playback', (tester) async {
    await pump(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.mediaPlayPause);
    await tester.sendKeyEvent(LogicalKeyboardKey.mediaTrackNext);
    await tester.sendKeyEvent(LogicalKeyboardKey.mediaTrackPrevious);
    expect(calls, ['toggle', 'next', 'previous']);
  });

  testWidgets('typing in a text field is left alone', (tester) async {
    final controller = TextEditingController(text: 'ab');
    addTearDown(controller.dispose);
    await pump(
      tester,
      body: TextField(controller: controller, autofocus: true),
    );
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    expect(calls, isEmpty);
  });

  testWidgets('Space types a space in a text field instead of pausing', (
    tester,
  ) async {
    await pump(tester, body: const TextField(autofocus: true));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'a');
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(calls, isEmpty);
  });

  testWidgets('Ctrl+Z still runs the last undo, once', (tester) async {
    var undone = 0;
    await pump(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(Scaffold)),
    );
    container.read(lastUndoActionProvider.notifier).state = () => undone++;

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(undone, 1);
  });
}
