import 'package:dbus/dbus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_player/core/library/database.dart';
import 'package:music_player/core/platform/mpris.dart';
import 'package:music_player/core/playback/playback_controller.dart';

const _player = 'org.mpris.MediaPlayer2.Player';
const _root = 'org.mpris.MediaPlayer2';

Track _track(int id) => Track(
  id: id,
  filePath: '/m/$id.flac',
  title: 'Song $id',
  artist: 'Artist',
  album: 'Record',
  albumArtPath: '/art/$id.jpg',
  format: 'flac',
  dateAdded: DateTime(2025),
);

PlaybackState _playing({
  int orderIndex = 0,
  bool isPlaying = true,
  Duration position = const Duration(seconds: 30),
}) {
  final queue = [_track(1), _track(2), _track(3)];
  return PlaybackState(
    currentTrack: queue[orderIndex],
    queue: queue,
    order: const [0, 1, 2],
    orderIndex: orderIndex,
    isPlaying: isPlaying,
    position: position,
    duration: const Duration(minutes: 3),
    volume: 0.5,
  );
}

/// Records the controller calls MPRIS makes and applies the ones that change
/// state, so handlers that loop on state (LoopStatus) can be tested.
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
  Future<void> setVolume(double volume) async {
    calls.add('volume $volume');
    state = state.copyWith(volume: volume);
  }

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

void main() {
  late _FakeController fake;
  late MprisObject mpris;

  void start(PlaybackState s) {
    fake = _FakeController(s);
    mpris = MprisObject(() => fake.state, () => fake);
  }

  Future<DBusMethodResponse> call(
    String name, [
    List<DBusValue> values = const [],
    String interface = _player,
  ]) => mpris.handleMethodCall(
    DBusMethodCall(
      sender: ':1.42',
      interface: interface,
      name: name,
      values: values,
    ),
  );

  group('properties', () {
    test('nothing loaded reads as stopped with no track', () {
      start(const PlaybackState());
      final p = mpris.playerProperties();
      expect(p['PlaybackStatus'], DBusString('Stopped'));
      expect(p['CanPlay'], DBusBoolean(false));
      final meta = (p['Metadata']! as DBusDict).children;
      expect(
        meta[DBusString('mpris:trackid')],
        DBusVariant(
          DBusObjectPath('/org/mpris/MediaPlayer2/TrackList/NoTrack'),
        ),
      );
    });

    test('a playing track shows status, metadata and position', () {
      start(_playing(orderIndex: 1));
      final p = mpris.playerProperties();
      expect(p['PlaybackStatus'], DBusString('Playing'));
      expect(p['Position'], DBusInt64(30 * 1000000));
      expect(p['Volume'], DBusDouble(0.5));
      expect(p['CanGoNext'], DBusBoolean(true));
      expect(p['CanGoPrevious'], DBusBoolean(true));
      final meta = (p['Metadata']! as DBusDict).children;
      expect(
        meta[DBusString('xesam:title')],
        DBusVariant(DBusString('Song 2')),
      );
      expect(
        meta[DBusString('xesam:album')],
        DBusVariant(DBusString('Record')),
      );
      expect(
        meta[DBusString('mpris:trackid')],
        DBusVariant(MprisObject.trackPath(2)),
      );
      expect(
        meta[DBusString('mpris:length')],
        DBusVariant(DBusInt64(180 * 1000000)),
      );
      expect(
        meta[DBusString('mpris:artUrl')],
        DBusVariant(DBusString('file:///art/2.jpg')),
      );
    });

    test('loop status maps every repeat mode', () {
      expect(MprisObject.loopStatus(PlayerRepeatMode.off), 'None');
      expect(MprisObject.loopStatus(PlayerRepeatMode.one), 'Track');
      expect(MprisObject.loopStatus(PlayerRepeatMode.all), 'Playlist');
    });

    test('only changed properties are announced, never Position', () {
      start(_playing());
      final before = mpris.playerProperties();
      fake.state = fake.state.copyWith(position: const Duration(seconds: 31));
      expect(mpris.changedPlayerProperties(before), isEmpty);
      fake.state = fake.state.copyWith(isPlaying: false);
      expect(mpris.changedPlayerProperties(before).keys, ['PlaybackStatus']);
    });

    test('identifies itself as MysticJam', () {
      start(const PlaybackState());
      expect(mpris.rootProperties()['Identity'], DBusString('MysticJam'));
    });
  });

  group('methods', () {
    test(
      'PlayPause toggles; Play and Pause only when they change it',
      () async {
        start(_playing());
        await call('Play');
        expect(fake.calls, isEmpty, reason: 'already playing');
        await call('PlayPause');
        await call('Pause');
        expect(fake.calls, ['toggle'], reason: 'Pause while paused is a no-op');
        await call('Play');
        expect(fake.calls, ['toggle', 'toggle']);
      },
    );

    test('PlayPause does nothing with no track loaded', () async {
      start(const PlaybackState());
      await call('PlayPause');
      expect(fake.calls, isEmpty);
    });

    test('Stop pauses and rewinds', () async {
      start(_playing());
      await call('Stop');
      expect(fake.calls, ['toggle', 'seek 0']);
    });

    test('Next and Previous go to the controller', () async {
      start(_playing());
      await call('Next');
      await call('Previous');
      expect(fake.calls, ['next', 'previous']);
    });

    test('Seek is relative to the current position and clamped', () async {
      start(_playing());
      await call('Seek', [DBusInt64(15 * 1000000)]);
      await call('Seek', [DBusInt64(-60 * 1000000)]);
      await call('Seek', [DBusInt64(999 * 1000000)]);
      expect(fake.calls, ['seek 45', 'seek 0', 'seek 180']);
    });

    test('SetPosition only applies to the current track', () async {
      start(_playing(orderIndex: 1));
      await call('SetPosition', [
        MprisObject.trackPath(1),
        DBusInt64(60 * 1000000),
      ]);
      expect(fake.calls, isEmpty, reason: 'stale track id');
      await call('SetPosition', [
        MprisObject.trackPath(2),
        DBusInt64(60 * 1000000),
      ]);
      expect(fake.calls, ['seek 60']);
    });

    test('unknown methods and interfaces are errors', () async {
      start(_playing());
      expect(await call('Explode'), isA<DBusMethodErrorResponse>());
      expect(
        await call('Next', const [], 'org.example.Nope'),
        isA<DBusMethodErrorResponse>(),
      );
    });

    test('CanRaise is false without a way to raise the window', () {
      start(_playing());
      expect(mpris.rootProperties()['CanRaise'], DBusBoolean(false));
    });

    test('with one, CanRaise is true and Raise calls it', () async {
      var raised = 0;
      fake = _FakeController(_playing());
      mpris = MprisObject(
        () => fake.state,
        () => fake,
        onRaise: () async => raised++,
      );
      expect(mpris.rootProperties()['CanRaise'], DBusBoolean(true));
      expect(
        await call('Raise', const [], _root),
        isA<DBusMethodSuccessResponse>(),
      );
      expect(raised, 1);
      expect(fake.calls, isEmpty, reason: 'playback untouched');
    });

    test('Raise and Quit on the root interface are accepted', () async {
      start(_playing());
      expect(
        await call('Raise', const [], _root),
        isA<DBusMethodSuccessResponse>(),
      );
      expect(fake.calls, isEmpty);
    });
  });

  group('setting properties', () {
    test('Volume is clamped to 0..1', () async {
      start(_playing());
      await mpris.setProperty(_player, 'Volume', DBusDouble(1.4));
      expect(fake.calls, ['volume 1.0']);
    });

    test('Shuffle toggles only when it differs', () async {
      start(_playing());
      await mpris.setProperty(_player, 'Shuffle', DBusBoolean(false));
      expect(fake.calls, isEmpty);
      await mpris.setProperty(_player, 'Shuffle', DBusBoolean(true));
      expect(fake.calls, ['shuffle']);
    });

    test('LoopStatus cycles until it matches', () async {
      start(_playing());
      await mpris.setProperty(_player, 'LoopStatus', DBusString('Track'));
      expect(fake.state.repeatMode, PlayerRepeatMode.one);
      await mpris.setProperty(_player, 'LoopStatus', DBusString('None'));
      expect(fake.state.repeatMode, PlayerRepeatMode.off);
    });

    test('read-only properties and the root interface refuse writes', () async {
      start(_playing());
      expect(
        await mpris.setProperty(_player, 'PlaybackStatus', DBusString('x')),
        isA<DBusMethodErrorResponse>(),
      );
      expect(
        await mpris.setProperty(_root, 'Identity', DBusString('x')),
        isA<DBusMethodErrorResponse>(),
      );
    });

    test('getProperty rejects unknown names and interfaces', () async {
      start(_playing());
      expect(
        await mpris.getProperty(_player, 'Nope'),
        isA<DBusMethodErrorResponse>(),
      );
      expect(
        await mpris.getProperty('org.example.Nope', 'Volume'),
        isA<DBusMethodErrorResponse>(),
      );
      final ok = await mpris.getProperty(_player, 'Volume');
      expect((ok as DBusGetPropertyResponse).values, [
        DBusVariant(DBusDouble(0.5)),
      ]);
    });
  });
}
