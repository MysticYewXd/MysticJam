import 'package:audio_service/audio_service.dart' as svc;
import 'package:flutter_test/flutter_test.dart';
import 'package:music_player/core/library/database.dart';
import 'package:music_player/core/platform/android_media_session.dart';
import 'package:music_player/core/playback/playback_controller.dart';

Track _track({int id = 1, int? durationMs}) => Track(
  id: id,
  filePath: '/m/$id.flac',
  title: 'Song $id',
  artist: 'Artist',
  album: 'Record',
  albumArtPath: '/art/$id.jpg',
  durationMs: durationMs,
  format: 'flac',
  dateAdded: DateTime(2025),
);

/// Records the controller calls the handler makes, and applies the ones
/// that change state, so handlers that loop on state (repeat) can be tested.
class _FakeController extends Fake implements PlaybackController {
  @override
  PlaybackState state;
  final calls = <String>[];

  _FakeController(this.state);

  @override
  Future<void> togglePlayPause() async {
    calls.add('toggle');
    state = state.copyWith(isPlaying: !state.isPlaying);
  }

  @override
  Future<void> seek(Duration position) async =>
      calls.add('seek ${position.inSeconds}');

  @override
  Future<void> next() async => calls.add('next');

  @override
  Future<void> previous() async => calls.add('previous');

  @override
  void toggleShuffle() {
    calls.add('shuffle');
    state = state.copyWith(shuffleEnabled: !state.shuffleEnabled);
  }

  @override
  void cycleRepeatMode() {
    calls.add('repeat');
    state = state.copyWith(
      repeatMode: switch (state.repeatMode) {
        PlayerRepeatMode.off => PlayerRepeatMode.all,
        PlayerRepeatMode.all => PlayerRepeatMode.one,
        PlayerRepeatMode.one => PlayerRepeatMode.off,
      },
    );
  }
}

PlaybackState _playing({int orderIndex = 0, bool isPlaying = true}) {
  final queue = [_track(id: 1), _track(id: 2), _track(id: 3)];
  return PlaybackState(
    currentTrack: queue[orderIndex],
    queue: queue,
    order: const [0, 1, 2],
    orderIndex: orderIndex,
    isPlaying: isPlaying,
    duration: const Duration(minutes: 3),
  );
}

void main() {
  group('mediaItemFor', () {
    test('is null with nothing loaded', () {
      expect(MysticJamAudioHandler.mediaItemFor(const PlaybackState()), isNull);
    });

    test('carries the track tags, art and engine duration', () {
      final item = MysticJamAudioHandler.mediaItemFor(_playing())!;
      expect(item.id, '1');
      expect(item.title, 'Song 1');
      expect(item.artist, 'Artist');
      expect(item.album, 'Record');
      expect(item.artUri, Uri.file('/art/1.jpg'));
      expect(item.duration, const Duration(minutes: 3));
    });

    test('falls back to the stored duration before the engine reports one', () {
      final t = _track(durationMs: 90000);
      final item = MysticJamAudioHandler.mediaItemFor(
        PlaybackState(currentTrack: t, queue: [t], order: const [0]),
      )!;
      expect(item.duration, const Duration(seconds: 90));
    });
  });

  group('playbackStateFor', () {
    test('idle with nothing loaded, so the notification goes away', () {
      final s = MysticJamAudioHandler.playbackStateFor(const PlaybackState());
      expect(s.processingState, svc.AudioProcessingState.idle);
    });

    test('first track: no previous button, pause shown while playing', () {
      final s = MysticJamAudioHandler.playbackStateFor(_playing());
      expect(s.processingState, svc.AudioProcessingState.ready);
      expect(s.controls, [svc.MediaControl.pause, svc.MediaControl.skipToNext]);
      expect(s.androidCompactActionIndices, [0, 1]);
    });

    test('middle track paused: previous, play, next', () {
      final s = MysticJamAudioHandler.playbackStateFor(
        _playing(orderIndex: 1, isPlaying: false),
      );
      expect(s.controls, [
        svc.MediaControl.skipToPrevious,
        svc.MediaControl.play,
        svc.MediaControl.skipToNext,
      ]);
      expect(s.playing, isFalse);
    });

    test('maps repeat and shuffle', () {
      final s = MysticJamAudioHandler.playbackStateFor(
        const PlaybackState(
          repeatMode: PlayerRepeatMode.one,
          shuffleEnabled: true,
        ),
      );
      expect(s.repeatMode, svc.AudioServiceRepeatMode.one);
      expect(s.shuffleMode, svc.AudioServiceShuffleMode.all);
    });
  });

  group('sync', () {
    late MysticJamAudioHandler handler;
    late List<svc.PlaybackState> pushed;

    setUp(() {
      handler = MysticJamAudioHandler(
        () => throw UnimplementedError(),
        () => throw UnimplementedError(),
      );
      pushed = [];
      handler.playbackState.skip(1).listen(pushed.add);
    });

    test('ignores ordinary position ticks', () async {
      final s = _playing();
      handler.sync(s);
      handler.sync(s.copyWith(position: const Duration(milliseconds: 500)));
      await pumpEventQueue();
      expect(pushed, hasLength(1));
    });

    test('pushes a seek and a track change', () async {
      final s = _playing();
      handler.sync(s);
      handler.sync(s.copyWith(position: const Duration(minutes: 2)));
      handler.sync(_playing(orderIndex: 1));
      await pumpEventQueue();
      expect(pushed, hasLength(3));
      expect(handler.mediaItem.value?.id, '2');
    });
  });

  group('controls', () {
    late _FakeController fake;
    late MysticJamAudioHandler handler;

    void start(PlaybackState s) {
      fake = _FakeController(s);
      handler = MysticJamAudioHandler(() => fake.state, () => fake);
    }

    test(
      'play and pause only toggle when they would change something',
      () async {
        start(_playing());
        await handler.play();
        expect(fake.calls, isEmpty, reason: 'already playing');
        await handler.pause();
        await handler.pause();
        expect(fake.calls, ['toggle'], reason: 'second pause is a no-op');
        await handler.play();
        expect(fake.calls, ['toggle', 'toggle']);
      },
    );

    test('play does nothing with no track loaded', () async {
      start(const PlaybackState());
      await handler.play();
      expect(fake.calls, isEmpty);
    });

    test('stop pauses and rewinds', () async {
      start(_playing());
      await handler.stop();
      expect(fake.calls, ['toggle', 'seek 0']);
    });

    test('seek, next and previous go straight to the controller', () async {
      start(_playing());
      await handler.seek(const Duration(seconds: 42));
      await handler.skipToNext();
      await handler.skipToPrevious();
      expect(fake.calls, ['seek 42', 'next', 'previous']);
    });

    test('shuffle toggles only when the requested mode differs', () async {
      start(_playing());
      await handler.setShuffleMode(svc.AudioServiceShuffleMode.none);
      expect(fake.calls, isEmpty);
      await handler.setShuffleMode(svc.AudioServiceShuffleMode.all);
      await handler.setShuffleMode(svc.AudioServiceShuffleMode.group);
      expect(fake.calls, ['shuffle'], reason: 'group counts as shuffled');
    });

    test('repeat cycles until the requested mode is reached', () async {
      start(_playing());
      await handler.setRepeatMode(svc.AudioServiceRepeatMode.one);
      expect(fake.state.repeatMode, PlayerRepeatMode.one);
      expect(fake.calls, ['repeat', 'repeat']);
      fake.calls.clear();
      await handler.setRepeatMode(svc.AudioServiceRepeatMode.none);
      expect(fake.state.repeatMode, PlayerRepeatMode.off);
      expect(fake.calls, ['repeat']);
    });

    test(
      'an unsupported repeat mode (group) leaves the mode unchanged',
      () async {
        start(_playing());
        await handler.setRepeatMode(svc.AudioServiceRepeatMode.group);
        expect(fake.state.repeatMode, PlayerRepeatMode.off);
      },
    );
  });
}
