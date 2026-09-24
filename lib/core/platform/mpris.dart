import 'dart:async';
import 'dart:io';

import 'package:dbus/dbus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../logging/app_log.dart';
import '../playback/playback_controller.dart';

const _busName = 'org.mpris.MediaPlayer2.MysticJam';
const _rootIface = 'org.mpris.MediaPlayer2';
const _playerIface = 'org.mpris.MediaPlayer2.Player';
const _noTrack = '/org/mpris/MediaPlayer2/TrackList/NoTrack';

/// Exposes playback on the Linux session bus as an MPRIS player, so the
/// desktop's media widget, media keys, lock screen and tools like playerctl
/// can see and control it. Talks to [PlaybackController] only through the
/// two accessors it is given, which keeps it testable without a bus.
class MprisObject extends DBusObject {
  final PlaybackState Function() _state;
  final PlaybackController Function() _controller;

  MprisObject(this._state, this._controller)
    : super(DBusObjectPath('/org/mpris/MediaPlayer2'));

  static String loopStatus(PlayerRepeatMode m) => switch (m) {
    PlayerRepeatMode.off => 'None',
    PlayerRepeatMode.one => 'Track',
    PlayerRepeatMode.all => 'Playlist',
  };

  static String playbackStatus(PlaybackState s) =>
      s.currentTrack == null ? 'Stopped' : (s.isPlaying ? 'Playing' : 'Paused');

  static int _micros(Duration d) => d.inMicroseconds;

  static DBusObjectPath trackPath(int id) =>
      DBusObjectPath('/org/mysticjam/track/$id');

  Map<String, DBusValue> _metadata(PlaybackState s) {
    final t = s.currentTrack;
    if (t == null) return {'mpris:trackid': DBusObjectPath(_noTrack)};
    return {
      'mpris:trackid': trackPath(t.id),
      if (s.duration > Duration.zero)
        'mpris:length': DBusInt64(_micros(s.duration)),
      'xesam:title': DBusString(t.title),
      if (t.artist != null) 'xesam:artist': DBusArray.string([t.artist!]),
      if (t.album != null) 'xesam:album': DBusString(t.album!),
      if (t.albumArtPath != null)
        'mpris:artUrl': DBusString(Uri.file(t.albumArtPath!).toString()),
    };
  }

  /// Every property of both interfaces as it is right now.
  Map<String, DBusValue> rootProperties() => {
    'CanQuit': DBusBoolean(false),
    'CanRaise': DBusBoolean(false),
    'HasTrackList': DBusBoolean(false),
    'Identity': DBusString('MysticJam'),
    'DesktopEntry': DBusString('mysticjam'),
    'SupportedUriSchemes': DBusArray.string(['file']),
    'SupportedMimeTypes': DBusArray.string([]),
  };

  Map<String, DBusValue> playerProperties() {
    final s = _state();
    final has = s.currentTrack != null;
    return {
      'PlaybackStatus': DBusString(playbackStatus(s)),
      'LoopStatus': DBusString(loopStatus(s.repeatMode)),
      'Rate': DBusDouble(1.0),
      'MinimumRate': DBusDouble(1.0),
      'MaximumRate': DBusDouble(1.0),
      'Shuffle': DBusBoolean(s.shuffleEnabled),
      'Metadata': DBusDict.stringVariant(_metadata(s)),
      'Volume': DBusDouble(s.volume),
      'Position': DBusInt64(_micros(s.position)),
      'CanGoNext': DBusBoolean(s.hasNext),
      'CanGoPrevious': DBusBoolean(s.hasPrevious),
      'CanPlay': DBusBoolean(has),
      'CanPause': DBusBoolean(has),
      'CanSeek': DBusBoolean(has),
      'CanControl': DBusBoolean(true),
    };
  }

  /// Properties whose value differs between [before] and now — what goes in
  /// a PropertiesChanged signal. Position is left out on purpose: the spec
  /// says clients read it on demand rather than being notified of every tick.
  Map<String, DBusValue> changedPlayerProperties(
    Map<String, DBusValue> before,
  ) {
    final now = playerProperties()..remove('Position');
    return {
      for (final e in now.entries)
        if (before[e.key] != e.value) e.key: e.value,
    };
  }

  @override
  Future<DBusMethodResponse> getProperty(String interface, String name) async {
    final props = switch (interface) {
      _rootIface => rootProperties(),
      _playerIface => playerProperties(),
      _ => null,
    };
    if (props == null) return DBusMethodErrorResponse.unknownInterface();
    final value = props[name];
    return value == null
        ? DBusMethodErrorResponse.unknownProperty()
        : DBusGetPropertyResponse(value);
  }

  @override
  Future<DBusMethodResponse> getAllProperties(String interface) async =>
      DBusGetAllPropertiesResponse(switch (interface) {
        _rootIface => rootProperties(),
        _playerIface => playerProperties(),
        _ => {},
      });

  @override
  Future<DBusMethodResponse> setProperty(
    String interface,
    String name,
    DBusValue value,
  ) async {
    if (interface != _playerIface) {
      return DBusMethodErrorResponse.propertyReadOnly();
    }
    // Any process on the session bus can call this — the value's type isn't
    // guaranteed to match the property, so the as*() casts below can throw.
    // That must turn into a normal D-Bus error reply, not an uncaught
    // exception inside the dbus package's message loop (which has no
    // try/catch of its own around this call and would otherwise leave the
    // caller hanging on a request that never gets a response).
    try {
      final c = _controller();
      final s = _state();
      switch (name) {
        case 'Volume':
          await c.setVolume(value.asDouble().clamp(0.0, 1.0));
        case 'Shuffle':
          if (value.asBoolean() != s.shuffleEnabled) c.toggleShuffle();
        case 'LoopStatus':
          final want = value.asString();
          // The controller only cycles off -> all -> one; at most 2 steps.
          for (
            var i = 0;
            i < 3 && loopStatus(_state().repeatMode) != want;
            i++
          ) {
            c.cycleRepeatMode();
          }
        default:
          return DBusMethodErrorResponse.propertyReadOnly();
      }
      return DBusMethodSuccessResponse();
    } catch (_) {
      return DBusMethodErrorResponse.invalidArgs();
    }
  }

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall methodCall) async {
    try {
      return await _handleMethodCall(methodCall);
    } catch (_) {
      // Same reasoning as setProperty: a caller sending Seek/SetPosition
      // with missing or wrongly-typed arguments must get InvalidArgs, not
      // silently break the reply.
      return DBusMethodErrorResponse.invalidArgs();
    }
  }

  Future<DBusMethodResponse> _handleMethodCall(
    DBusMethodCall methodCall,
  ) async {
    final c = _controller();
    final s = _state();
    if (methodCall.interface == _rootIface) {
      return methodCall.name == 'Raise' || methodCall.name == 'Quit'
          ? DBusMethodSuccessResponse()
          : DBusMethodErrorResponse.unknownMethod();
    }
    if (methodCall.interface != _playerIface) {
      return DBusMethodErrorResponse.unknownInterface();
    }
    switch (methodCall.name) {
      case 'Next':
        await c.next();
      case 'Previous':
        await c.previous();
      case 'Play':
        if (!s.isPlaying && s.currentTrack != null) await c.togglePlayPause();
      case 'Pause':
        if (s.isPlaying) await c.togglePlayPause();
      case 'PlayPause':
        if (s.currentTrack != null) await c.togglePlayPause();
      case 'Stop':
        if (s.isPlaying) await c.togglePlayPause();
        if (s.currentTrack != null) await c.seek(Duration.zero);
      case 'Seek':
        final target =
            s.position + Duration(microseconds: methodCall.values[0].asInt64());
        await c.seek(_clamp(target, s.duration));
      case 'SetPosition':
        final id = s.currentTrack?.id;
        if (id != null &&
            methodCall.values[0].asObjectPath() == trackPath(id)) {
          await c.seek(
            _clamp(
              Duration(microseconds: methodCall.values[1].asInt64()),
              s.duration,
            ),
          );
        }
      case 'OpenUri':
        break;
      default:
        return DBusMethodErrorResponse.unknownMethod();
    }
    return DBusMethodSuccessResponse();
  }

  static Duration _clamp(Duration d, Duration max) {
    if (d < Duration.zero) return Duration.zero;
    return max > Duration.zero && d > max ? max : d;
  }
}

/// Publishes [MprisObject] on the session bus for as long as the app runs
/// and pushes PropertiesChanged whenever playback state changes. Linux only;
/// with no session bus (or a name clash) it quietly does nothing — MPRIS is
/// a convenience, never a reason for the app to fail.
final mprisProvider = Provider<void>((ref) {
  if (!Platform.isLinux) return;
  final object = MprisObject(
    () => ref.read(playbackControllerProvider),
    () => ref.read(playbackControllerProvider.notifier),
  );
  final client = DBusClient.session();
  var closed = false;
  ref.onDispose(() {
    closed = true;
    client.close();
  });

  () async {
    try {
      await client.registerObject(object);
      final reply = await client.requestName(_busName);
      if (reply != DBusRequestNameReply.primaryOwner) {
        AppLog.warn('mpris', 'bus name not acquired', {'reply': reply});
        return;
      }
      AppLog.info('mpris', 'registered');
    } catch (e) {
      AppLog.warn('mpris', 'unavailable', {'error': e.runtimeType});
      return;
    }
    var last = object.playerProperties();
    ref.listen(playbackControllerProvider, (_, _) {
      if (closed) return;
      final changed = object.changedPlayerProperties(last);
      if (changed.isEmpty) return;
      last = {...last, ...changed};
      object.emitPropertiesChanged(_playerIface, changedProperties: changed);
    });
  }();
});
