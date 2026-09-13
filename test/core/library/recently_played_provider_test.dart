import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:music_player/core/library/database.dart';
import 'package:music_player/core/library/library_providers.dart';
import 'package:music_player/core/settings/app_settings.dart';

class _FakePathProviderPlatform extends PathProviderPlatform {
  final String path;
  _FakePathProviderPlatform(this.path);

  @override
  Future<String?> getApplicationSupportPath() async => path;
}

/// Waits for the next update to [tracksProvider] — used instead of the
/// deprecated .stream accessor (removed in Riverpod 3.0).
Future<void> _waitForNextTracksUpdate(ProviderContainer container) {
  final completer = Completer<void>();
  late final ProviderSubscription<Object?> sub;
  sub = container.listen(tracksProvider, (previous, next) {
    completer.complete();
    sub.close();
  });
  return completer.future;
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync(
      'mysticjam_recently_played_test_',
    );
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test('resolves recently-played ids to tracks, preserving order', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);

    final repo = container.read(libraryRepositoryProvider);
    final id1 = await repo.upsertTrack(
      TracksCompanion.insert(filePath: '/a.mp3', title: 'A', format: 'mp3'),
    );
    final id2 = await repo.upsertTrack(
      TracksCompanion.insert(filePath: '/b.mp3', title: 'B', format: 'mp3'),
    );

    final settings = container.read(appSettingsProvider.notifier);
    await settings.ready;
    await settings.recordTrackStarted(id1);
    await settings.recordTrackStarted(id2);
    // recordTrackStarted puts the most-recent first — id2 then id1.

    // tracksProvider is a StreamProvider backed by a Drift watch query;
    // give it a chance to settle before reading the derived provider.
    await container.read(tracksProvider.future);

    final result = container.read(recentlyPlayedTracksProvider);
    expect(result.value?.map((t) => t.id).toList(), [id2, id1]);
  });

  test(
    'a track deleted from the library drops out on its own (self-healing)',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      addTearDown(container.dispose);

      final repo = container.read(libraryRepositoryProvider);
      final id1 = await repo.upsertTrack(
        TracksCompanion.insert(filePath: '/a.mp3', title: 'A', format: 'mp3'),
      );
      final id2 = await repo.upsertTrack(
        TracksCompanion.insert(filePath: '/b.mp3', title: 'B', format: 'mp3'),
      );
      final settings = container.read(appSettingsProvider.notifier);
      await settings.ready;
      await settings.recordTrackStarted(id1);
      await settings.recordTrackStarted(id2);

      await container.read(tracksProvider.future);
      expect(container.read(recentlyPlayedTracksProvider).value?.length, 2);

      final nextUpdate = _waitForNextTracksUpdate(container);
      await repo.deleteTrack(id1);
      await nextUpdate;

      final result = container.read(recentlyPlayedTracksProvider);
      expect(
        result.value?.map((t) => t.id).toList(),
        [id2],
        reason: 'the deleted track must not still appear',
      );
    },
  );
}
