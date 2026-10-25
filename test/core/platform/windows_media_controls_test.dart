import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:music_player/core/library/database.dart';
import 'package:music_player/core/platform/windows_media_controls.dart';
import 'package:music_player/core/playback/playback_controller.dart';

/// Records what the media controls ask playback to do.
class _FakePlayback extends PlaybackController {
  final PlaybackState initial;
  final calls = <String>[];
  _FakePlayback(this.initial);

  @override
  PlaybackState build() => initial;

  void push(PlaybackState s) => state = s;

  @override
  Future<void> togglePlayPause() async => calls.add('toggle');

  @override
  Future<void> next() async => calls.add('next');

  @override
  Future<void> previous() async => calls.add('previous');

  @override
  Future<void> seek(Duration position) async =>
      calls.add('seek ${position.inSeconds}');
}

Track _track(int id) => Track(
  id: id,
  filePath: '/m/$id.flac',
  title: 'Song $id',
  artist: 'Artist',
  album: 'Record',
  albumArtPath: '/art/$id.art',
  format: 'flac',
  dateAdded: DateTime(2025),
);

final _queue = [_track(1), _track(2), _track(3)];

PlaybackState _state({
  int index = 1,
  bool playing = false,
  Duration position = Duration.zero,
}) => PlaybackState(
  currentTrack: _queue[index],
  queue: _queue,
  order: const [0, 1, 2],
  orderIndex: index,
  isPlaying: playing,
  duration: const Duration(minutes: 3),
  position: position,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<MethodCall> sent;
  setUp(() {
    sent = [];
    messenger.setMockMethodCallHandler(mediaControlsChannel, (call) async {
      sent.add(call);
      return null;
    });
  });
  tearDown(
    () => messenger.setMockMethodCallHandler(mediaControlsChannel, null),
  );

  /// Starts the media controls on [initial], as on Windows unless
  /// [enabled] is false.
  (ProviderContainer, _FakePlayback) start(
    PlaybackState initial, {
    bool enabled = true,
  }) {
    final fake = _FakePlayback(initial);
    final container = ProviderContainer(
      overrides: [
        playbackControllerProvider.overrideWith(() => fake),
        windowsMediaControlsEnabledProvider.overrideWithValue(enabled),
      ],
    );
    addTearDown(container.dispose);
    container.read(windowsMediaControlsProvider);
    return (container, fake);
  }

  /// A button press or seek coming from Windows.
  Future<void> fromWindows(String method, Object arguments) =>
      messenger.handlePlatformMessage(
        mediaControlsChannel.name,
        const StandardMethodCodec().encodeMethodCall(
          MethodCall(method, arguments),
        ),
        (_) {},
      );

  test('sends what is playing straight away', () async {
    start(_state(playing: true, position: const Duration(seconds: 7)));
    await pumpEventQueue();

    expect(sent.single.method, 'update');
    expect(sent.single.arguments, {
      'hasTrack': true,
      'title': 'Song 2',
      'artist': 'Artist',
      'album': 'Record',
      'artPath': '/art/2.art',
      'playing': true,
      'canNext': true,
      'canPrevious': true,
      'positionMs': 7000,
      'durationMs': 180000,
    });
  });

  test('updates on song and play changes, not on position ticks', () async {
    final (_, fake) = start(_state());
    await pumpEventQueue();
    sent.clear();

    fake.push(_state(position: const Duration(seconds: 5)));
    fake.push(_state(position: const Duration(seconds: 6)));
    await pumpEventQueue();
    expect(sent, isEmpty, reason: 'position alone is not sent');

    fake.push(_state(playing: true, position: const Duration(seconds: 6)));
    await pumpEventQueue();
    expect((sent.single.arguments as Map)['playing'], isTrue);

    fake.push(_state(index: 2));
    await pumpEventQueue();
    expect((sent.last.arguments as Map)['title'], 'Song 3');
    expect((sent.last.arguments as Map)['canNext'], isFalse);
  });

  test('tells Windows when nothing is playing', () async {
    start(const PlaybackState());
    await pumpEventQueue();

    expect((sent.single.arguments as Map)['hasTrack'], isFalse);
  });

  test('media buttons control playback', () async {
    final (_, fake) = start(_state());
    await pumpEventQueue();

    await fromWindows('button', 'play');
    await fromWindows('button', 'pause');
    fake.push(_state(playing: true));
    await fromWindows('button', 'pause');
    await fromWindows('button', 'play');
    await fromWindows('button', 'next');
    await fromWindows('button', 'previous');
    await fromWindows('seek', 42000);

    expect(fake.calls, [
      'toggle', // play while paused
      // pause while paused: nothing
      'toggle', // pause while playing
      // play while playing: nothing
      'next',
      'previous',
      'seek 42',
    ]);
  });

  test('next and previous do nothing at the ends of the queue', () async {
    final (_, fake) = start(_state(index: 2));
    await pumpEventQueue();

    await fromWindows('button', 'next');
    fake.push(_state(index: 0));
    await fromWindows('button', 'previous');

    expect(fake.calls, isEmpty);
  });

  test('does nothing when not on Windows', () async {
    final (_, fake) = start(_state(), enabled: false);
    await pumpEventQueue();
    await fromWindows('button', 'play');

    expect(sent, isEmpty);
    expect(fake.calls, isEmpty);
  });
}
