import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:music_player/core/library/database.dart';
import 'package:music_player/core/playback/playback_controller.dart';
import 'package:music_player/features/now_playing/disc_player_view.dart';

class _FakePlayback extends PlaybackController {
  final PlaybackState initial;
  final volumes = <double>[];
  final seeks = <Duration>[];
  final jumps = <int>[];
  _FakePlayback(this.initial);

  @override
  PlaybackState build() => initial;

  void push(PlaybackState s) => state = s;

  @override
  Future<void> setVolume(double volume) async {
    volumes.add(volume);
    state = state.copyWith(volume: volume);
  }

  @override
  Future<void> seek(Duration position) async => seeks.add(position);

  @override
  Future<void> jumpToOrderIndex(int orderIndex) async => jumps.add(orderIndex);
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

PlaybackState _state({
  bool isPlaying = false,
  Duration? position,
  double volume = 1.0,
}) {
  final queue = [_track(1), _track(2)];
  return PlaybackState(
    currentTrack: queue.first,
    queue: queue,
    order: const [0, 1],
    orderIndex: 0,
    isPlaying: isPlaying,
    duration: const Duration(minutes: 3),
    position: position ?? Duration.zero,
    volume: volume,
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

    testWidgets('the soft copy is a small, cached copy of the face', (
      tester,
    ) async {
      final cache = DiscFaceCache();
      addTearDown(cache.dispose);
      const red = Color(0xFFFF0000);
      expect(cache.soft, isNull, reason: 'no face yet');

      final art = _art(const Color(0xFF00FF00));
      addTearDown(art.dispose);
      cache.resolve(art, radius: 100, pixelRatio: 1, tint: red);
      final soft = cache.soft;
      expect(soft!.width, 32);
      expect(cache.soft, same(soft), reason: 'made once per face');

      final other = _art(const Color(0xFF00FFFF));
      addTearDown(other.dispose);
      cache.resolve(other, radius: 100, pixelRatio: 1, tint: red);
      expect(cache.soft, isNot(same(soft)), reason: 'a new cover, a new copy');
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
    testWidgets('uses no live blur', (tester) async {
      await _pump(tester, _state(isPlaying: true));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(ImageFiltered), findsNothing);
      expect(find.byType(BackdropFilter), findsNothing);
    });

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

  group('OLED volume slider', () {
    testWidgets('replaces the song slider and shows the current volume', (
      tester,
    ) async {
      await _pump(tester, _state(volume: 0.6));
      await tester.pumpAndSettle();
      final slider = tester.widget<Slider>(find.byType(Slider));
      expect(slider.divisions, isNull, reason: 'not the old song picker');
      expect(slider.value, 0.6);
      expect(find.byIcon(Icons.volume_down), findsOneWidget);
      expect(find.byIcon(Icons.volume_up), findsOneWidget);
    });

    testWidgets('changes the volume live while dragging', (tester) async {
      final fake = await _pump(tester, _state(volume: 0.5));
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(Slider)),
      );
      for (var i = 0; i < 5; i++) {
        await gesture.moveBy(const Offset(-20, 0));
        await tester.pump();
      }
      final duringDrag = fake.volumes.length;
      expect(duringDrag, greaterThan(1), reason: 'live, not only on release');
      await gesture.up();
      await tester.pump();
      expect(fake.volumes.last, lessThan(0.5));
      expect(
        tester.widget<Slider>(find.byType(Slider)).value,
        fake.volumes.last,
      );
    });

    testWidgets('follows volume changes made elsewhere', (tester) async {
      final fake = await _pump(tester, _state(volume: 0.8));
      await tester.pumpAndSettle();
      fake.push(_state(volume: 0.2));
      await tester.pump();
      expect(tester.widget<Slider>(find.byType(Slider)).value, 0.2);
    });

    testWidgets('tapping a song still plays it', (tester) async {
      final fake = await _pump(tester, _state());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Song 2'));
      expect(fake.jumps, [1]);
    });

    testWidgets('dragging the disc still seeks', (tester) async {
      final fake = await _pump(tester, _state());
      await tester.pumpAndSettle();
      final disc = find.byWidgetPredicate(
        (w) => w is Semantics && (w.properties.label ?? '').startsWith('Disc'),
      );
      final centre = tester.getCenter(disc);
      // A quarter turn clockwise, starting at 3 o'clock.
      final gesture = await tester.startGesture(centre + const Offset(100, 0));
      for (var i = 1; i <= 10; i++) {
        final a = i / 10 * math.pi / 2;
        await gesture.moveTo(
          centre + Offset(math.cos(a) * 100, math.sin(a) * 100),
        );
        await tester.pump();
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(fake.seeks, hasLength(1));
      expect(fake.seeks.single, greaterThan(const Duration(seconds: 5)));
    });
  });

  group('OLED seek bar', () {
    final bar = find.byKey(const ValueKey('disc-seek-bar'));

    /// The point [fraction] of the way along the bar, vertically centred.
    Offset along(WidgetTester tester, double fraction) {
      final rect = tester.getRect(bar);
      return Offset(rect.left + rect.width * fraction, rect.center.dy);
    }

    Matcher near(Duration d) => predicate<Duration>(
      (x) => (x - d).abs() < const Duration(seconds: 2),
      'within 2 s of $d',
    );

    testWidgets('a tap jumps to that point in the song', (tester) async {
      final fake = await _pump(tester, _state());
      await tester.pumpAndSettle();
      await tester.tapAt(along(tester, 0.25));
      await tester.pump();
      expect(fake.seeks, [near(const Duration(seconds: 45))]);
    });

    testWidgets('a drag previews live and seeks once on release', (
      tester,
    ) async {
      final fake = await _pump(tester, _state(isPlaying: true));
      await tester.pump();
      final gesture = await tester.startGesture(along(tester, 0.1));
      for (var i = 1; i <= 8; i++) {
        await gesture.moveTo(along(tester, 0.1 + i * 0.05));
        await tester.pump();
      }
      // The clock (and hidden scrub label) follow the finger...
      expect(find.text('1:30'), findsNWidgets(2));
      expect(fake.seeks, isEmpty, reason: 'nothing seeks mid-drag');
      // ...and a position tick arriving mid-drag doesn't yank it back.
      fake.push(_state(isPlaying: true, position: const Duration(seconds: 5)));
      await tester.pump();
      expect(find.text('1:30'), findsNWidgets(2));
      // The disc stays out of scrub mode: its big scrub label is hidden.
      expect(
        tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
        0,
      );

      await gesture.up();
      await tester.pump();
      expect(fake.seeks, [near(const Duration(seconds: 90))]);

      // Once the seek has landed, position ticks drive the clock again.
      fake.push(_state(isPlaying: true, position: const Duration(seconds: 91)));
      await tester.pump();
      expect(find.text('1:31'), findsNWidgets(2));
    });

    testWidgets('inactive with nothing playing', (tester) async {
      await _pump(tester, const PlaybackState());
      await tester.pumpAndSettle();
      expect(bar, findsNothing);
    });
  });

  group('album entrance', () {
    /// A song on album [album]; like the real scanner, every song has its
    /// own cover file. Those files don't exist here, which makes the
    /// entrance the "soft" one: the player fades in out of focus.
    Track song(int id, int? album, {String? tag}) => _track(id).copyWith(
      albumId: Value(album),
      album: Value(tag ?? 'Record'),
      albumArtPath: Value('/nowhere/$id.art'),
    );

    PlaybackState playing(Track t, List<Track> queue) => PlaybackState(
      currentTrack: t,
      queue: queue,
      order: [for (var i = 0; i < queue.length; i++) i],
      orderIndex: queue.indexOf(t),
      duration: const Duration(minutes: 3),
    );

    /// Lets the cover-mood lookup (real file I/O) finish, then starts any
    /// entrance it triggers.
    Future<void> lookUpCover(WidgetTester tester) async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }

    /// The soft entrance fades the whole player in (the blur itself is now
    /// faked on the disc face), so a part-transparent player means it's
    /// running. The keys' own disabled fade wraps no Transform.
    bool blurring(WidgetTester tester) => tester
        .widgetList<Opacity>(find.byType(Opacity))
        .any((w) => w.opacity < 1 && w.child is Transform);

    testWidgets('plays when opening, then not when skipping within the album, '
        'and again for a new album', (tester) async {
      final a1 = song(1, 10), a2 = song(2, 10), b1 = song(3, 20);
      final queue = [a1, a2, b1];
      final fake = await _pump(tester, playing(a1, queue));
      await lookUpCover(tester);
      expect(blurring(tester), isTrue, reason: 'opening the album');
      await tester.pumpAndSettle();
      expect(blurring(tester), isFalse);

      fake.push(playing(a2, queue));
      await lookUpCover(tester);
      expect(blurring(tester), isFalse, reason: 'same album, new cover file');
      await tester.pump();
      expect(
        tester.binding.hasScheduledFrame,
        isFalse,
        reason: 'no spin kick or animation: the paused disc stays still',
      );

      fake.push(playing(b1, queue));
      await lookUpCover(tester);
      expect(blurring(tester), isTrue, reason: 'a different album');
      await tester.pumpAndSettle();
    });

    testWidgets('songs without an album id match by their album tag', (
      tester,
    ) async {
      final x1 = song(1, null, tag: 'Loose'), x2 = song(2, null, tag: 'Loose');
      final y1 = song(3, null, tag: 'Other');
      final queue = [x1, x2, y1];
      final fake = await _pump(tester, playing(x1, queue));
      await lookUpCover(tester);
      await tester.pumpAndSettle();

      fake.push(playing(x2, queue));
      await lookUpCover(tester);
      expect(blurring(tester), isFalse, reason: 'same album tag');

      fake.push(playing(y1, queue));
      await lookUpCover(tester);
      expect(blurring(tester), isTrue, reason: 'different album tag');
      await tester.pumpAndSettle();
    });
  });
}
