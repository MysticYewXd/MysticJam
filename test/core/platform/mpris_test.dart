import 'package:dbus/dbus.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:music_player/core/library/database.dart';
import 'package:music_player/core/platform/mpris.dart';
import 'package:music_player/core/playback/playback_controller.dart';

const _player = 'org.mpris.MediaPlayer2.Player';

class _Recorder extends PlaybackController {
  final List<String> calls;
  PlaybackState current;
  _Recorder(this.current, this.calls);

  @override
  PlaybackState build() => current;
  @override
  Future<void> togglePlayPause() async => calls.add('toggle');
  @override
  Future<void> next() async => calls.add('next');
  @override
  Future<void> previous() async => calls.add('previous');
  @override
  Future<void> seek(Duration p) async => calls.add('seek ${p.inMilliseconds}');
  @override
  Future<void> setVolume(double v) async => calls.add('volume $v');
  @override
  void toggleShuffle() => calls.add('shuffle');
  @override
  void cycleRepeatMode() {
    calls.add('cycle');
    current = current.copyWith(
      repeatMode: switch (current.repeatMode) {
        PlayerRepeatMode.off => PlayerRepeatMode.all,
        PlayerRepeatMode.all => PlayerRepeatMode.one,
        PlayerRepeatMode.one => PlayerRepeatMode.off,
      },
    );
  }
}

Track _track({String? art}) => Track(
  id: 7,
  filePath: '/m/7.flac',
  title: 'Song',
  artist: 'Artist',
  album: 'Album',
  format: 'flac',
  dateAdded: DateTime(2025),
  albumArtPath: art,
);

void main() {
  late List<String> calls;
  late _Recorder recorder;
  late MprisObject object;

  void setUpWith(PlaybackState state) {
    calls = [];
    recorder = _Recorder(state, calls);
    object = MprisObject(() => recorder.current, () => recorder);
  }

  DBusMethodCall call(String name, [List<DBusValue> args = const []]) =>
      DBusMethodCall(
        sender: ':1.1',
        interface: _player,
        name: name,
        values: args,
      );

  Future<DBusValue> get(String name) async {
    final r =
        await object.getProperty(_player, name) as DBusMethodSuccessResponse;
    return (r.values.single as DBusVariant).value;
  }

  final playing = PlaybackState(
    currentTrack: _track(art: '/art/7.art'),
    isPlaying: true,
    position: const Duration(seconds: 30),
    duration: const Duration(seconds: 200),
    volume: 0.4,
    queue: [_track(), _track()],
    order: const [0, 1],
    orderIndex: 0,
  );

  test('status is Stopped with no track, Playing/Paused with one', () async {
    setUpWith(const PlaybackState());
    expect((await get('PlaybackStatus')).asString(), 'Stopped');
    expect((await get('CanPlay')).asBoolean(), isFalse);

    setUpWith(playing);
    expect((await get('PlaybackStatus')).asString(), 'Playing');
    setUpWith(playing.copyWith(isPlaying: false));
    expect((await get('PlaybackStatus')).asString(), 'Paused');
  });

  test(
    'metadata carries title, artist, album, length, art and track id',
    () async {
      setUpWith(playing);
      final md = (await get('Metadata')).asStringVariantDict();
      expect(md['xesam:title']!.asString(), 'Song');
      expect(md['xesam:artist']!.asStringArray().toList(), ['Artist']);
      expect(md['xesam:album']!.asString(), 'Album');
      expect(md['mpris:length']!.asInt64(), 200 * 1000000);
      expect(md['mpris:artUrl']!.asString(), 'file:///art/7.art');
      expect(
        md['mpris:trackid']!.asObjectPath().value,
        '/org/mysticjam/track/7',
      );
    },
  );

  test('position and volume are reported in the units MPRIS expects', () async {
    setUpWith(playing);
    expect((await get('Position')).asInt64(), 30 * 1000000);
    expect((await get('Volume')).asDouble(), 0.4);
    expect(MprisObject.loopStatus(PlayerRepeatMode.one), 'Track');
    expect(MprisObject.loopStatus(PlayerRepeatMode.all), 'Playlist');
    expect(MprisObject.loopStatus(PlayerRepeatMode.off), 'None');
  });

  test('transport methods drive the controller', () async {
    setUpWith(playing);
    await object.handleMethodCall(call('Next'));
    await object.handleMethodCall(call('Previous'));
    await object.handleMethodCall(call('PlayPause'));
    await object.handleMethodCall(call('Pause')); // playing -> toggles
    await object.handleMethodCall(call('Play')); // already playing -> no-op
    expect(calls, ['next', 'previous', 'toggle', 'toggle']);
  });

  test('Play/Pause/PlayPause do nothing with no track loaded', () async {
    setUpWith(const PlaybackState());
    await object.handleMethodCall(call('Play'));
    await object.handleMethodCall(call('PlayPause'));
    expect(calls, isEmpty);
  });

  test(
    'Seek is relative and clamped; SetPosition needs the current track id',
    () async {
      setUpWith(playing);
      await object.handleMethodCall(call('Seek', [DBusInt64(10 * 1000000)]));
      await object.handleMethodCall(call('Seek', [DBusInt64(-99 * 1000000)]));
      await object.handleMethodCall(call('Seek', [DBusInt64(999 * 1000000)]));
      expect(calls, ['seek 40000', 'seek 0', 'seek 200000']);

      calls.clear();
      await object.handleMethodCall(
        call('SetPosition', [MprisObject.trackPath(7), DBusInt64(5 * 1000000)]),
      );
      await object.handleMethodCall(
        call('SetPosition', [
          MprisObject.trackPath(99),
          DBusInt64(5 * 1000000),
        ]),
      );
      expect(calls, ['seek 5000']);
    },
  );

  test('writable properties: volume, shuffle, loop status', () async {
    setUpWith(playing);
    await object.setProperty(_player, 'Volume', DBusDouble(2.0));
    await object.setProperty(_player, 'Shuffle', DBusBoolean(true));
    await object.setProperty(_player, 'LoopStatus', DBusString('Track'));
    expect(calls, ['volume 1.0', 'shuffle', 'cycle', 'cycle']);
  });

  test('read-only and unknown things are refused, not ignored', () async {
    setUpWith(playing);
    expect(
      await object.setProperty(_player, 'Position', DBusInt64(1)),
      isA<DBusMethodErrorResponse>(),
    );
    expect(
      await object.getProperty(_player, 'Nope'),
      isA<DBusMethodErrorResponse>(),
    );
    expect(
      await object.getProperty('x.y', 'Nope'),
      isA<DBusMethodErrorResponse>(),
    );
    expect(
      await object.handleMethodCall(call('Explode')),
      isA<DBusMethodErrorResponse>(),
    );
  });

  test('only properties that changed are reported, never Position', () async {
    setUpWith(playing);
    final before = object.playerProperties();
    recorder.current = playing.copyWith(
      isPlaying: false,
      position: const Duration(seconds: 90),
    );
    final changed = object.changedPlayerProperties(before);
    expect(changed.keys, ['PlaybackStatus']);
    expect(changed['PlaybackStatus'], DBusString('Paused'));
  });

  test(
    'root interface identifies the app and does not claim to quit or raise',
    () async {
      setUpWith(const PlaybackState());
      final r =
          await object.getProperty('org.mpris.MediaPlayer2', 'Identity')
              as DBusMethodSuccessResponse;
      expect((r.values.single as DBusVariant).value.asString(), 'MysticJam');
      final all =
          await object.getAllProperties('org.mpris.MediaPlayer2')
              as DBusMethodSuccessResponse;
      final props = all.values.single.asStringVariantDict();
      expect(props['CanQuit']!.asBoolean(), isFalse);
      expect(props['CanRaise']!.asBoolean(), isFalse);
    },
  );

  group('malformed local D-Bus input is rejected, never thrown', () {
    test('SetProperty with the wrong value type returns InvalidArgs', () async {
      setUpWith(playing);
      final r = await object.setProperty(_player, 'Volume', DBusString('loud'));
      expect(r, isA<DBusMethodErrorResponse>());
      expect((r as DBusMethodErrorResponse).errorName, contains('InvalidArgs'));
      expect(calls, isEmpty);
    });

    test(
      'Seek with no arguments returns InvalidArgs instead of throwing',
      () async {
        setUpWith(playing);
        final r = await object.handleMethodCall(call('Seek', const []));
        expect(r, isA<DBusMethodErrorResponse>());
        expect(calls, isEmpty);
      },
    );

    test('Seek with a non-integer argument returns InvalidArgs', () async {
      setUpWith(playing);
      final r = await object.handleMethodCall(call('Seek', [DBusString('x')]));
      expect(r, isA<DBusMethodErrorResponse>());
      expect(calls, isEmpty);
    });

    test('SetPosition with one missing argument returns InvalidArgs', () async {
      setUpWith(playing);
      final r = await object.handleMethodCall(
        call('SetPosition', [MprisObject.trackPath(7)]),
      );
      expect(r, isA<DBusMethodErrorResponse>());
      expect(calls, isEmpty);
    });

    test('LoopStatus set to garbage does not loop forever or crash', () async {
      setUpWith(playing);
      final r = await object.setProperty(
        _player,
        'LoopStatus',
        DBusString('???'),
      );
      expect(r, isA<DBusMethodSuccessResponse>());
      expect(calls.length, lessThanOrEqualTo(3));
    });
  });
}
