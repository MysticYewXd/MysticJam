import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:music_player/core/audio/audio_engine.dart';
import 'package:music_player/core/audio/audio_engine_provider.dart';
import 'package:music_player/core/audio/system_volume_controller.dart';
import 'package:music_player/core/audio/system_volume_provider.dart';
import 'package:music_player/core/library/database.dart';
import 'package:music_player/core/library/library_providers.dart';
import 'package:music_player/core/library/library_repository.dart';
import 'package:music_player/core/playback/playback_controller.dart';
import 'package:music_player/core/settings/app_settings.dart';

/// A controllable fake — unlike widget_test.dart's minimal Stream.empty()
/// version, tests here need to push events (playing/error/completed) on
/// demand to drive PlaybackController through specific scenarios.
class _FakeAudioEngine implements AudioEngine {
  final _position = StreamController<Duration>.broadcast();
  final _duration = StreamController<Duration>.broadcast();
  final _playing = StreamController<bool>.broadcast();
  final _completed = StreamController<bool>.broadcast();
  final _error = StreamController<String>.broadcast();
  final _volume = StreamController<double>.broadcast();

  final List<String> openedPaths = [];
  final List<Duration> seekedPositions = [];
  int stopCount = 0;

  /// When set, the next open() call reports this error on errorStream
  /// instead of "succeeding" — simulates a missing/corrupt file.
  String? failNextOpenWith;

  @override
  Future<void> init() async {}

  @override
  Future<void> open(String filePath, {bool play = true}) async {
    openedPaths.add(filePath);
    final failure = failNextOpenWith;
    if (failure != null) {
      failNextOpenWith = null;
      _error.add(failure);
      return;
    }
    _playing.add(play);
  }

  @override
  Future<void> play() async => _playing.add(true);

  @override
  Future<void> pause() async => _playing.add(false);

  @override
  Future<void> stop() async {
    stopCount++;
    _playing.add(false);
  }

  @override
  Future<void> seek(Duration position) async => seekedPositions.add(position);

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> dispose() async {
    await _position.close();
    await _duration.close();
    await _playing.close();
    await _completed.close();
    await _error.close();
    await _volume.close();
  }

  @override
  Stream<Duration> get positionStream => _position.stream;

  @override
  Stream<Duration> get durationStream => _duration.stream;

  @override
  Stream<bool> get playingStream => _playing.stream;

  @override
  Stream<bool> get completedStream => _completed.stream;

  @override
  Stream<String> get errorStream => _error.stream;

  @override
  Stream<double> get volumeStream => _volume.stream;

  void emitCompleted() => _completed.add(true);
}

class _FakeSystemVolumeController implements SystemVolumeController {
  @override
  Future<double> getVolume() async => 1.0;

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Stream<double> get volumeChanges => const Stream.empty();

  @override
  void dispose() {}
}

Track _track(int id, {String? path}) {
  return Track(
    id: id,
    filePath: path ?? '/music/track-$id.mp3',
    title: 'Track $id',
    format: 'mp3',
    dateAdded: DateTime(2026, 1, 1),
  );
}

void main() {
  // Each test opens its own fresh in-memory AppDatabase — drift's own
  // multi-instance heuristic otherwise warns about this as a possible
  // race condition, which doesn't apply here since every instance has its
  // own independent NativeDatabase.memory() connection.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late _FakeAudioEngine engine;
  late ProviderContainer container;

  setUp(() {
    engine = _FakeAudioEngine();
    container = ProviderContainer(
      overrides: [
        audioEngineProvider.overrideWithValue(engine),
        systemVolumeControllerProvider.overrideWithValue(
          _FakeSystemVolumeController(),
        ),
        // Duration-persistence writes go through the repository — a real
        // in-memory DB avoids needing a fake repository just for this.
        databaseProvider.overrideWithValue(
          AppDatabase.forTesting(NativeDatabase.memory()),
        ),
      ],
    );
    addTearDown(container.dispose);
  });

  PlaybackController controller() =>
      container.read(playbackControllerProvider.notifier);
  PlaybackState state() => container.read(playbackControllerProvider);

  group('play and pause', () {
    test('togglePlayPause plays when paused', () async {
      final tracks = [_track(1)];
      await controller().playFromQueue(tracks, 0);
      engine._playing.add(false); // simulate engine reporting paused
      // Broadcast StreamController.add() delivers on a microtask, not
      // synchronously — without yielding here, togglePlayPause()'s
      // synchronous `state.isPlaying` check below would still see the
      // stale value from before this emission.
      await Future<void>.delayed(Duration.zero);

      await controller().togglePlayPause();

      expect(state().isPlaying, isTrue);
    });

    test('togglePlayPause pauses when playing', () async {
      final tracks = [_track(1)];
      await controller().playFromQueue(tracks, 0);
      engine._playing.add(true);
      await Future<void>.delayed(Duration.zero);

      await controller().togglePlayPause();

      expect(state().isPlaying, isFalse);
    });

    test(
      're-playing the already-current track resumes instead of reopening',
      () async {
        final tracks = [_track(1), _track(2)];
        await controller().playFromQueue(tracks, 0);
        engine._playing.add(false);
        await Future<void>.delayed(Duration.zero);
        engine.openedPaths.clear();

        await controller().playFromQueue(tracks, 0);

        expect(
          engine.openedPaths,
          isEmpty,
          reason: 'should resume, not re-open the same track',
        );
        expect(state().isPlaying, isTrue);
      },
    );
  });

  group('queue insertion and removal', () {
    test('playFromQueue populates queue and order', () async {
      final tracks = [_track(1), _track(2), _track(3)];
      await controller().playFromQueue(tracks, 1);

      expect(state().queue, tracks);
      expect(state().order, [0, 1, 2]);
      expect(state().currentTrack?.id, 2);
    });

    test(
      'removeFromQueue drops a non-current track and keeps playing the same one',
      () async {
        final tracks = [_track(1), _track(2), _track(3)];
        await controller().playFromQueue(tracks, 0);

        await controller().removeFromQueue(2); // remove track 3, not playing

        expect(state().order, [0, 1]);
        expect(state().currentTrack?.id, 1);
        expect(engine.stopCount, 0);
      },
    );

    test('removeFromQueue on an out-of-range position is a no-op', () async {
      final tracks = [_track(1)];
      await controller().playFromQueue(tracks, 0);
      final before = state();

      await controller().removeFromQueue(5);

      expect(state().order, before.order);
    });
  });

  group('next and previous', () {
    test('next moves to the following track and opens it', () async {
      final tracks = [_track(1), _track(2), _track(3)];
      await controller().playFromQueue(tracks, 0);
      engine.openedPaths.clear();

      await controller().next();

      expect(state().currentTrack?.id, 2);
      expect(engine.openedPaths, [tracks[1].filePath]);
    });

    test('previous moves to the preceding track', () async {
      final tracks = [_track(1), _track(2), _track(3)];
      await controller().playFromQueue(tracks, 2);
      engine.openedPaths.clear();

      await controller().previous();

      expect(state().currentTrack?.id, 2);
    });

    test('next does nothing past the end when repeat is off', () async {
      final tracks = [_track(1), _track(2)];
      await controller().playFromQueue(tracks, 1);
      engine.openedPaths.clear();

      await controller().next();

      expect(state().currentTrack?.id, 2, reason: 'stays on the last track');
      expect(engine.openedPaths, isEmpty);
    });

    test('previous does nothing before the start when repeat is off', () async {
      final tracks = [_track(1), _track(2)];
      await controller().playFromQueue(tracks, 0);
      engine.openedPaths.clear();

      await controller().previous();

      expect(state().currentTrack?.id, 1);
      expect(engine.openedPaths, isEmpty);
    });
  });

  group('shuffle behavior', () {
    test(
      'toggling shuffle on keeps the current track first in the new order',
      () async {
        final tracks = [_track(1), _track(2), _track(3), _track(4)];
        await controller().playFromQueue(tracks, 2); // track 3 playing

        controller().toggleShuffle();

        expect(state().shuffleEnabled, isTrue);
        expect(
          state().order[state().orderIndex],
          2,
          reason: 'order entry at orderIndex still points at track 3',
        );
        expect(
          state().currentTrack?.id,
          3,
          reason: 'shuffling must not change what is currently playing',
        );
        // Order is a permutation of every queue index exactly once.
        expect(state().order..sort(), [0, 1, 2, 3]);
      },
    );

    test(
      'toggling shuffle off restores sequential order, keeping the current track',
      () async {
        final tracks = [_track(1), _track(2), _track(3)];
        await controller().playFromQueue(tracks, 1);
        controller().toggleShuffle();

        controller().toggleShuffle();

        expect(state().shuffleEnabled, isFalse);
        expect(state().order, [0, 1, 2]);
        expect(state().currentTrack?.id, 2);
      },
    );
  });

  group('repeat-one', () {
    test(
      'track completing seeks to zero and replays instead of advancing',
      () async {
        final tracks = [_track(1), _track(2)];
        await controller().playFromQueue(tracks, 0);
        controller().cycleRepeatMode(); // off -> all
        controller().cycleRepeatMode(); // all -> one
        engine.openedPaths.clear();

        engine.emitCompleted();
        await Future<void>.delayed(Duration.zero);

        expect(
          state().currentTrack?.id,
          1,
          reason: 'repeat-one must not advance to the next track',
        );
        expect(engine.seekedPositions, contains(Duration.zero));
        expect(engine.openedPaths, isEmpty);
      },
    );
  });

  group('repeat-all', () {
    test('next wraps from the last track back to the first', () async {
      final tracks = [_track(1), _track(2), _track(3)];
      await controller().playFromQueue(tracks, 2);
      controller().cycleRepeatMode(); // off -> all

      await controller().next();

      expect(state().currentTrack?.id, 1);
    });

    test('previous wraps from the first track back to the last', () async {
      final tracks = [_track(1), _track(2), _track(3)];
      await controller().playFromQueue(tracks, 0);
      controller().cycleRepeatMode(); // off -> all

      await controller().previous();

      expect(state().currentTrack?.id, 3);
    });

    test('completing the last track advances to the first', () async {
      final tracks = [_track(1), _track(2)];
      await controller().playFromQueue(tracks, 1);
      controller().cycleRepeatMode(); // off -> all

      engine.emitCompleted();
      await Future<void>.delayed(Duration.zero);

      expect(state().currentTrack?.id, 1);
    });
  });

  group('removing the currently playing track', () {
    test('advances automatically to what now occupies that position', () async {
      final tracks = [_track(1), _track(2), _track(3)];
      await controller().playFromQueue(tracks, 0);
      engine.openedPaths.clear();

      await controller().removeFromQueue(
        0,
      ); // remove the currently-playing track

      expect(state().order.length, 2);
      expect(
        state().currentTrack?.id,
        2,
        reason: 'track 2 shifts into the vacated slot and starts playing',
      );
      expect(engine.openedPaths, [tracks[1].filePath]);
    });

    test(
      'removing the only track stops playback and resets to empty state',
      () async {
        final tracks = [_track(1)];
        await controller().playFromQueue(tracks, 0);

        await controller().removeFromQueue(0);

        expect(engine.stopCount, 1);
        expect(state().currentTrack, isNull);
        expect(state().order, isEmpty);
      },
    );

    test(
      'removing the last position wraps playback to the first remaining track',
      () async {
        final tracks = [_track(1), _track(2), _track(3)];
        await controller().playFromQueue(
          tracks,
          2,
        ); // playing track 3, last position
        engine.openedPaths.clear();

        await controller().removeFromQueue(2);

        expect(state().currentTrack?.id, 1);
        expect(engine.openedPaths, [tracks[0].filePath]);
      },
    );
  });

  group('empty queues', () {
    test('next on an empty queue does nothing', () async {
      await controller().next();

      expect(state().currentTrack, isNull);
      expect(engine.openedPaths, isEmpty);
    });

    test('previous on an empty queue does nothing', () async {
      await controller().previous();

      expect(state().currentTrack, isNull);
    });

    test(
      'playFromQueue with an out-of-range start index does nothing',
      () async {
        await controller().playFromQueue([_track(1)], 5);

        expect(state().currentTrack, isNull);
        expect(engine.openedPaths, isEmpty);
      },
    );

    test('playFromQueue with an empty list does nothing', () async {
      await controller().playFromQueue(const [], 0);

      expect(state().currentTrack, isNull);
    });
  });

  group('missing or deleted audio files / playback errors', () {
    test('a failed open() surfaces its message as errorMessage', () async {
      engine.failNextOpenWith = 'No such file or directory';

      await controller().playFromQueue([_track(1)], 0);

      expect(state().errorMessage, 'No such file or directory');
    });

    test(
      'a stale error is cleared once a different track opens successfully',
      () async {
        final tracks = [_track(1), _track(2)];
        engine.failNextOpenWith = 'file not found';
        await controller().playFromQueue(tracks, 0);
        expect(state().errorMessage, isNotNull);

        await controller().next();

        expect(state().errorMessage, isNull);
      },
    );

    test(
      'an error on the current track does not itself change currentTrack',
      () async {
        engine.failNextOpenWith = 'codec not supported';
        final tracks = [_track(1)];

        await controller().playFromQueue(tracks, 0);

        expect(
          state().currentTrack?.id,
          1,
          reason: 'the attempted track stays "current" even though it failed',
        );
        expect(state().errorMessage, 'codec not supported');
      },
    );
  });

  group('resume-on-restart', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('mysticjam_resume_test_');
      PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    ProviderContainer sessionContainer(
      AppDatabase db,
      _FakeAudioEngine sessionEngine,
    ) {
      final c = ProviderContainer(
        overrides: [
          audioEngineProvider.overrideWithValue(sessionEngine),
          systemVolumeControllerProvider.overrideWithValue(
            _FakeSystemVolumeController(),
          ),
          databaseProvider.overrideWithValue(db),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    test(
      'resumes the last track at its saved position on a fresh container',
      () async {
        final db = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(db.close);
        final musicFile = File(p.join(tempDir.path, 'song.mp3'))
          ..writeAsStringSync('fake audio bytes');
        final repo = LibraryRepository(db);
        final trackId = await repo.upsertTrack(
          TracksCompanion.insert(
            filePath: musicFile.path,
            title: 'Resumable Song',
            format: 'mp3',
            durationMs: const Value(200000),
          ),
        );
        final track = (await repo.getTrackById(trackId))!;

        // Session 1: play partway through, then the app "closes".
        final engine1 = _FakeAudioEngine();
        final container1 = sessionContainer(db, engine1);
        await container1
            .read(playbackControllerProvider.notifier)
            .playFromQueue([track], 0);
        engine1._position.add(const Duration(milliseconds: 45000));
        await Future<void>.delayed(Duration.zero);
        await container1.read(appSettingsProvider.notifier).flushPositionNow();

        // Session 2: a brand new container/PlaybackController, same DB and
        // same on-disk settings file — simulates relaunching the app.
        final engine2 = _FakeAudioEngine();
        final container2 = sessionContainer(db, engine2);
        container2.read(playbackControllerProvider); // trigger build()
        // build() kicks off resume as fire-and-forget; settings load + repo
        // lookup + File.exists + engine open/seek are all fast in-memory/temp
        // operations, so a short real delay is enough for it to settle.
        await Future<void>.delayed(const Duration(milliseconds: 100));

        final state = container2.read(playbackControllerProvider);
        expect(state.currentTrack?.id, trackId);
        expect(engine2.openedPaths, [musicFile.path]);
        expect(
          engine2.seekedPositions,
          contains(const Duration(milliseconds: 45000)),
        );
      },
    );

    test(
      'does not resume a track whose file no longer exists, and clears the stale setting',
      () async {
        final db = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(db.close);
        final missingPath = p.join(
          tempDir.path,
          'deleted-song.mp3',
        ); // never created
        final repo = LibraryRepository(db);
        final trackId = await repo.upsertTrack(
          TracksCompanion.insert(
            filePath: missingPath,
            title: 'Gone Song',
            format: 'mp3',
          ),
        );

        final settingsContainer = ProviderContainer();
        addTearDown(settingsContainer.dispose);
        final settings = settingsContainer.read(appSettingsProvider.notifier);
        await settings.ready;
        await settings.recordTrackStarted(trackId);

        final engine = _FakeAudioEngine();
        final container = sessionContainer(db, engine);
        container.read(playbackControllerProvider);
        await Future<void>.delayed(const Duration(milliseconds: 100));

        expect(container.read(playbackControllerProvider).currentTrack, isNull);
        expect(engine.openedPaths, isEmpty);
      },
    );

    test(
      'clamps a saved position beyond the track\'s known duration',
      () async {
        final db = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(db.close);
        final musicFile = File(p.join(tempDir.path, 'short-song.mp3'))
          ..writeAsStringSync('x');
        final repo = LibraryRepository(db);
        final trackId = await repo.upsertTrack(
          TracksCompanion.insert(
            filePath: musicFile.path,
            title: 'Short Song',
            format: 'mp3',
            durationMs: const Value(10000), // 10s track
          ),
        );

        final settingsContainer = ProviderContainer();
        addTearDown(settingsContainer.dispose);
        final settings = settingsContainer.read(appSettingsProvider.notifier);
        await settings.ready;
        await settings.recordTrackStarted(trackId);
        settings.updatePosition(trackId, 999999); // far beyond the 10s duration
        await settings.flushPositionNow();

        final engine = _FakeAudioEngine();
        final container = sessionContainer(db, engine);
        container.read(playbackControllerProvider);
        await Future<void>.delayed(const Duration(milliseconds: 100));

        expect(
          engine.seekedPositions,
          contains(const Duration(milliseconds: 10000)),
        );
      },
    );

    test(
      'with no saved track, shuffle/repeat still restore and playback stays idle',
      () async {
        final settingsContainer = ProviderContainer();
        addTearDown(settingsContainer.dispose);
        final settings = settingsContainer.read(appSettingsProvider.notifier);
        await settings.ready;
        await settings.setShuffleEnabled(true);
        await settings.setRepeatMode('all');

        final db = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(db.close);
        final engine = _FakeAudioEngine();
        final container = sessionContainer(db, engine);
        container.read(playbackControllerProvider);
        await Future<void>.delayed(const Duration(milliseconds: 100));

        final state = container.read(playbackControllerProvider);
        expect(state.currentTrack, isNull);
        expect(state.shuffleEnabled, isTrue);
        expect(state.repeatMode, PlayerRepeatMode.all);
        expect(engine.openedPaths, isEmpty);
      },
    );
  });
}

/// Points getApplicationSupportDirectory() at a real temp directory — same
/// pattern and same justification as app_settings_test.dart's copy: the
/// officially supported way to test path_provider-dependent code without a
/// platform channel.
class _FakePathProviderPlatform extends PathProviderPlatform {
  final String path;
  _FakePathProviderPlatform(this.path);

  @override
  Future<String?> getApplicationSupportPath() async => path;
}
