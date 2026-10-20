import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:music_player/core/library/database.dart';
import 'package:music_player/core/playback/playback_controller.dart';
import 'package:music_player/features/now_playing/queue_screen.dart';

Track _track(int id) => Track(
  id: id,
  filePath: '/m/$id.flac',
  title: 'Song $id',
  format: 'flac',
  dateAdded: DateTime(2025),
);

/// Records queue edits and applies removals, so the screen can be checked
/// both for what it asks for and for how it then looks.
class _FakePlayback extends PlaybackController {
  final PlaybackState initial;
  final removed = <int>[];
  final reorders = <(int, int)>[];
  _FakePlayback(this.initial);

  @override
  PlaybackState build() => initial;

  @override
  Future<void> removeFromQueue(int orderPosition) async {
    removed.add(orderPosition);
    final order = List<int>.from(state.order)..removeAt(orderPosition);
    state = state.copyWith(
      order: order,
      orderIndex: orderPosition < state.orderIndex
          ? state.orderIndex - 1
          : state.orderIndex,
    );
  }

  @override
  void reorderQueue(int oldIndex, int newIndex) =>
      reorders.add((oldIndex, newIndex));
}

PlaybackState _queue({int playing = 0}) {
  final queue = [_track(1), _track(2), _track(3)];
  return PlaybackState(
    currentTrack: queue[playing],
    queue: queue,
    order: const [0, 1, 2],
    orderIndex: playing,
  );
}

Future<_FakePlayback> _pump(WidgetTester tester, PlaybackState state) async {
  final fake = _FakePlayback(state);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [playbackControllerProvider.overrideWith(() => fake)],
      child: const MaterialApp(home: QueueScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return fake;
}

Finder _removeButtonFor(String title) => find.descendant(
  of: find.widgetWithText(ListTile, title),
  matching: find.byTooltip('Remove from queue'),
);

void main() {
  testWidgets('every row has a remove button and a drag handle', (
    tester,
  ) async {
    await _pump(tester, _queue());
    expect(find.byTooltip('Remove from queue'), findsNWidgets(3));
    expect(find.byIcon(Icons.drag_handle), findsNWidgets(3));
  });

  testWidgets('✕ removes that row\'s song and the list updates', (
    tester,
  ) async {
    final fake = await _pump(tester, _queue());
    await tester.tap(_removeButtonFor('Song 2'));
    await tester.pumpAndSettle();

    expect(fake.removed, [1]);
    expect(find.text('Song 2'), findsNothing);
    expect(find.text('Song 1'), findsOneWidget);
    expect(find.text('Song 3'), findsOneWidget);
  });

  testWidgets('the playing song can be removed too', (tester) async {
    final fake = await _pump(tester, _queue(playing: 2));
    await tester.tap(_removeButtonFor('Song 3'));
    await tester.pumpAndSettle();
    expect(fake.removed, [2]);
  });

  testWidgets('dragging the handle still reorders', (tester) async {
    final fake = await _pump(tester, _queue());
    final handle = find.descendant(
      of: find.widgetWithText(ListTile, 'Song 1'),
      matching: find.byIcon(Icons.drag_handle),
    );
    final rowHeight = tester.getSize(find.byType(ListTile).first).height;
    final gesture = await tester.startGesture(tester.getCenter(handle));
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(Offset(0, rowHeight * 0.25));
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(fake.reorders, isNotEmpty);
    expect(fake.reorders.single.$1, 0);
  });
}
