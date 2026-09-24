import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:music_player/core/settings/app_settings.dart';

/// Points getApplicationSupportDirectory() at a real temp directory instead
/// of a platform channel — the officially supported way to test
/// path_provider-dependent code (extend PathProviderPlatform, override the
/// one method used, install via PathProviderPlatform.instance). Without
/// this, AppSettingsNotifier's own try/catch would silently swallow every
/// file operation as "platform channel unavailable", which is fine for
/// PlaybackController's own tests (they don't care about persistence) but
/// useless for testing persistence itself.
class _FakePathProviderPlatform extends PathProviderPlatform {
  final String path;
  _FakePathProviderPlatform(this.path);

  @override
  Future<String?> getApplicationSupportPath() async => path;
}

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('mysticjam_settings_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  File settingsFile() => File(p.join(tempDir.path, 'app_settings.json'));

  ProviderContainer container() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    return c;
  }

  group('loading', () {
    test('with no existing file, starts from defaults without error', () async {
      final c = container();
      await c.read(appSettingsProvider.notifier).ready;

      final state = c.read(appSettingsProvider);
      expect(state.shuffleEnabled, isFalse);
      expect(state.repeatMode, 'off');
      expect(state.lastTrackId, isNull);
    });

    test(
      'a corrupted file falls back to defaults instead of crashing',
      () async {
        await settingsFile().writeAsString('{not valid json!!');

        final c = container();
        await c.read(appSettingsProvider.notifier).ready;

        final state = c.read(appSettingsProvider);
        expect(state, isA<AppSettingsState>());
        expect(state.lastTrackId, isNull);
      },
    );

    test('loads back previously persisted values', () async {
      await settingsFile().writeAsString(
        jsonEncode({
          'shuffleEnabled': true,
          'repeatMode': 'all',
          'lastTrackId': 42,
          'lastPositionMs': 15000,
          'recentlyPlayedTrackIds': [42, 7],
          'importedFolders': ['/music/rock'],
        }),
      );

      final c = container();
      await c.read(appSettingsProvider.notifier).ready;

      final state = c.read(appSettingsProvider);
      expect(state.shuffleEnabled, isTrue);
      expect(state.repeatMode, 'all');
      expect(state.lastTrackId, 42);
      expect(state.lastPositionMs, 15000);
      expect(state.recentlyPlayedTrackIds, [42, 7]);
      expect(state.importedFolders, ['/music/rock']);
    });
  });

  group('atomic writes', () {
    test('persisting leaves only the final file, no leftover .tmp', () async {
      final c = container();
      await c.read(appSettingsProvider.notifier).ready;

      await c.read(appSettingsProvider.notifier).setShuffleEnabled(true);

      expect(await settingsFile().exists(), isTrue);
      expect(await File('${settingsFile().path}.tmp').exists(), isFalse);
      final saved = jsonDecode(await settingsFile().readAsString()) as Map;
      expect(saved['shuffleEnabled'], isTrue);
    });
  });

  group('shuffle and repeat', () {
    test('setShuffleEnabled updates state and persists immediately', () async {
      final c = container();
      await c.read(appSettingsProvider.notifier).ready;

      await c.read(appSettingsProvider.notifier).setShuffleEnabled(true);

      expect(c.read(appSettingsProvider).shuffleEnabled, isTrue);
      final saved = jsonDecode(await settingsFile().readAsString()) as Map;
      expect(saved['shuffleEnabled'], isTrue);
    });

    test('setRepeatMode updates state and persists immediately', () async {
      final c = container();
      await c.read(appSettingsProvider.notifier).ready;

      await c.read(appSettingsProvider.notifier).setRepeatMode('one');

      expect(c.read(appSettingsProvider).repeatMode, 'one');
      final saved = jsonDecode(await settingsFile().readAsString()) as Map;
      expect(saved['repeatMode'], 'one');
    });
  });

  group('track started / recently played', () {
    test('recordTrackStarted sets lastTrackId and resets position', () async {
      final c = container();
      final notifier = c.read(appSettingsProvider.notifier);
      await notifier.ready;
      notifier.updatePosition(1, 9000);

      await notifier.recordTrackStarted(5);

      expect(c.read(appSettingsProvider).lastTrackId, 5);
      expect(c.read(appSettingsProvider).lastPositionMs, 0);
    });

    test(
      'recently played is most-recent-first and de-duplicates repeats',
      () async {
        final c = container();
        final notifier = c.read(appSettingsProvider.notifier);
        await notifier.ready;

        await notifier.recordTrackStarted(1);
        await notifier.recordTrackStarted(2);
        await notifier.recordTrackStarted(
          1,
        ); // replayed — should move to front, not duplicate

        expect(c.read(appSettingsProvider).recentlyPlayedTrackIds, [1, 2]);
      },
    );

    test('recently played is capped at 50 entries', () async {
      final c = container();
      final notifier = c.read(appSettingsProvider.notifier);
      await notifier.ready;

      for (var id = 1; id <= 55; id++) {
        await notifier.recordTrackStarted(id);
      }

      final ids = c.read(appSettingsProvider).recentlyPlayedTrackIds;
      expect(ids.length, 50);
      expect(ids.first, 55, reason: 'most recently played stays at the front');
    });
  });

  group('throttled position writes', () {
    test(
      'updatePosition updates in-memory state without writing to disk immediately',
      () async {
        final c = container();
        final notifier = c.read(appSettingsProvider.notifier);
        await notifier.ready;
        await notifier.recordTrackStarted(
          3,
        ); // writes once, establishing lastTrackId = 3
        final beforeContent = await settingsFile().readAsString();

        notifier.updatePosition(3, 12345);

        expect(
          c.read(appSettingsProvider).lastPositionMs,
          12345,
          reason: 'in-memory state updates immediately',
        );
        final afterContent = await settingsFile().readAsString();
        expect(
          afterContent,
          beforeContent,
          reason: 'disk write is throttled, not immediate',
        );
      },
    );

    test(
      'flushPositionNow writes the throttled position immediately',
      () async {
        final c = container();
        final notifier = c.read(appSettingsProvider.notifier);
        await notifier.ready;
        await notifier.recordTrackStarted(3);

        notifier.updatePosition(3, 12345);
        await notifier.flushPositionNow();

        final saved = jsonDecode(await settingsFile().readAsString()) as Map;
        expect(saved['lastPositionMs'], 12345);
      },
    );

    test(
      'a position tick for a track that is no longer current is ignored',
      () async {
        final c = container();
        final notifier = c.read(appSettingsProvider.notifier);
        await notifier.ready;
        await notifier.recordTrackStarted(3);

        notifier.updatePosition(999, 50000); // stale tick from a previous track

        expect(c.read(appSettingsProvider).lastPositionMs, 0);
      },
    );
  });

  group('imported folders', () {
    test('addImportedFolder appends and persists', () async {
      final c = container();
      final notifier = c.read(appSettingsProvider.notifier);
      await notifier.ready;

      await notifier.addImportedFolder('/music/jazz');

      expect(c.read(appSettingsProvider).importedFolders, ['/music/jazz']);
      final saved = jsonDecode(await settingsFile().readAsString()) as Map;
      expect(saved['importedFolders'], ['/music/jazz']);
    });

    test('adding the same folder twice does not duplicate it', () async {
      final c = container();
      final notifier = c.read(appSettingsProvider.notifier);
      await notifier.ready;

      await notifier.addImportedFolder('/music/jazz');
      await notifier.addImportedFolder('/music/jazz');

      expect(c.read(appSettingsProvider).importedFolders, ['/music/jazz']);
    });
  });

  group('clearLastTrack', () {
    test('resets lastTrackId and lastPositionMs, keeps other fields', () async {
      final c = container();
      final notifier = c.read(appSettingsProvider.notifier);
      await notifier.ready;
      await notifier.setShuffleEnabled(true);
      await notifier.recordTrackStarted(9);
      notifier.updatePosition(9, 8000);
      await notifier.flushPositionNow();

      await notifier.clearLastTrack();

      final state = c.read(appSettingsProvider);
      expect(state.lastTrackId, isNull);
      expect(state.lastPositionMs, 0);
      expect(
        state.shuffleEnabled,
        isTrue,
        reason: 'unrelated fields must be untouched',
      );
    });
  });
}
