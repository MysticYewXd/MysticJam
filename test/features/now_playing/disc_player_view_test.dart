import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:music_player/core/library/database.dart';
import 'package:music_player/core/playback/playback_controller.dart';
import 'package:music_player/features/now_playing/disc_player_view.dart';

class _FakePlayback extends PlaybackController {
  final PlaybackState initial;
  _FakePlayback(this.initial);

  @override
  PlaybackState build() => initial;

  void push(PlaybackState s) => state = s;
}

Track _track(int id) => Track(
  id: id,
  filePath: '/m/$id.flac',
  title: 'Song $id',
  artist: 'Artist',
  album: 'Record',
  format: 'flac',
  dateAdded: DateTime(2025),
);

PlaybackState _state({bool isPlaying = false, Duration? position}) {
  final queue = [_track(1), _track(2)];
  return PlaybackState(
    currentTrack: queue.first,
    queue: queue,
    order: const [0, 1],
    orderIndex: 0,
    isPlaying: isPlaying,
    duration: const Duration(minutes: 3),
    position: position ?? Duration.zero,
  );
}

/// A small solid square, standing in for a decoded cover.
ui.Image _art(Color color) {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(color, BlendMode.src);
  final picture = recorder.endRecording();
  final image = picture.toImageSync(8, 8);
  picture.dispose();
  return image;
}

Future<_FakePlayback> _pump(WidgetTester tester, PlaybackState initial) async {
  tester.view.physicalSize = const Size(480, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final fake = _FakePlayback(initial);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [playbackControllerProvider.overrideWith(() => fake)],
      child: const MaterialApp(home: Scaffold(body: DiscPlayerView())),
    ),
  );
  return fake;
}

void main() {
  group('DiscFaceCache', () {
    testWidgets('reuses the texture within a size bucket', (tester) async {
      final cache = DiscFaceCache();
      addTearDown(cache.dispose);
      const red = Color(0xFFFF0000);

      final a = cache.resolve(null, radius: 100, pixelRatio: 1, tint: red);
      expect(a!.width, 256, reason: '200 px rounds up to the next 64 px step');
      expect(
        cache.resolve(null, radius: 100, pixelRatio: 1, tint: red),
        same(a),
      );
      expect(
        cache.resolve(null, radius: 110, pixelRatio: 1, tint: red),
        same(a),
        reason: '220 px is still in the 256 px bucket',
      );

      final b = cache.resolve(null, radius: 140, pixelRatio: 1, tint: red);
      expect(b, isNot(same(a)));
      expect(b!.width, 320);
      expect(
        cache.resolve(null, radius: 70, pixelRatio: 2, tint: red)!.width,
        320,
        reason: 'pixel ratio counts towards the size',
      );
    });

    testWidgets('the tint only matters when there is no cover', (tester) async {
      final cache = DiscFaceCache();
      addTearDown(cache.dispose);
      const red = Color(0xFFFF0000);
      const blue = Color(0xFF0000FF);

      final silver = cache.resolve(null, radius: 100, pixelRatio: 1, tint: red);
      expect(
        cache.resolve(null, radius: 100, pixelRatio: 1, tint: blue),
        isNot(same(silver)),
      );

      final art = _art(const Color(0xFF00FF00));
      addTearDown(art.dispose);
      final cover = cache.resolve(art, radius: 100, pixelRatio: 1, tint: red);
      expect(
        cache.resolve(art, radius: 100, pixelRatio: 1, tint: blue),
        same(cover),
      );

      final other = _art(const Color(0xFF00FFFF));
      addTearDown(other.dispose);
      expect(
        cache.resolve(other, radius: 100, pixelRatio: 1, tint: red),
        isNot(same(cover)),
        reason: 'a new cover re-bakes',
      );
    });

    testWidgets('no texture for a disc with no room', (tester) async {
      final cache = DiscFaceCache();
      expect(
        cache.resolve(
          null,
          radius: 0,
          pixelRatio: 1,
          tint: const Color(0xFFFF0000),
        ),
        isNull,
      );
    });
  });

  group('DiscPlayerView', () {
    testWidgets('a paused disc stops producing frames once it settles', (
      tester,
    ) async {
      final fake = await _pump(tester, _state(isPlaying: true));
      await tester.pump(const Duration(seconds: 1));
      expect(tester.binding.hasScheduledFrame, isTrue, reason: 'spinning');

      fake.push(_state());
      // Times out if the spin ticker keeps running while paused.
      await tester.pumpAndSettle();
      expect(tester.binding.hasScheduledFrame, isFalse);

      fake.push(_state(isPlaying: true));
      await tester.pump();
      expect(
        tester.binding.hasScheduledFrame,
        isTrue,
        reason: 'pressing play starts it again',
      );
    });

    testWidgets('position ticks update the OLED clock and scrub label', (
      tester,
    ) async {
      final fake = await _pump(tester, _state());
      await tester.pumpAndSettle();
      // The OLED clock, plus the scrub label (hidden until you drag).
      expect(find.text('0:00'), findsNWidgets(2));

      fake.push(_state(position: const Duration(seconds: 42)));
      await tester.pump();
      expect(find.text('0:42'), findsNWidgets(2));
      expect(find.text('0:00'), findsNothing);
      expect(find.text('Song 1'), findsOneWidget);
    });
  });
}
