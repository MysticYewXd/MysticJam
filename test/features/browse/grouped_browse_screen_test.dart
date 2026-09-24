import 'dart:io';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:music_player/core/audio/audio_engine.dart';
import 'package:music_player/core/audio/audio_engine_provider.dart';
import 'package:music_player/core/audio/system_volume_controller.dart';
import 'package:music_player/core/audio/system_volume_provider.dart';
import 'package:music_player/core/library/database.dart';
import 'package:music_player/core/library/library_providers.dart';
import 'package:music_player/core/library/library_repository.dart';
import 'package:music_player/features/browse/grouped_browse_screen.dart';
import 'package:music_player/widgets/themed/themed_icon.dart';

class _FakeAudioEngine implements AudioEngine {
  @override
  Future<void> init() async {}
  @override
  Future<void> open(String filePath, {bool play = true}) async {}
  @override
  Future<void> play() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> seek(Duration position) async {}
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> dispose() async {}
  @override
  Stream<Duration> get positionStream => const Stream.empty();
  @override
  Stream<Duration> get durationStream => const Stream.empty();
  @override
  Stream<bool> get playingStream => const Stream.empty();
  @override
  Stream<bool> get completedStream => const Stream.empty();
  @override
  Stream<String> get errorStream => const Stream.empty();
  @override
  Stream<double> get volumeStream => const Stream.empty();
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

class _FakePathProviderPlatform extends PathProviderPlatform {
  final String path;
  _FakePathProviderPlatform(this.path);

  @override
  Future<String?> getApplicationSupportPath() async => path;
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync(
      'mysticjam_grouped_browse_test_',
    );
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  Future<void> pumpArtistsScreen(WidgetTester tester, AppDatabase db) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          audioEngineProvider.overrideWithValue(_FakeAudioEngine()),
          systemVolumeControllerProvider.overrideWithValue(
            _FakeSystemVolumeController(),
          ),
        ],
        child: MaterialApp(
          home: GroupedBrowseScreen(
            title: 'Artists',
            rowIcon: ThemedIconSlot.artist,
            keyOf: (track) => track.artist,
            unknownLabel: 'Unknown Artist',
            countLabel: (n) => '$n track${n == 1 ? '' : 's'}',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('groups tracks by artist, sorted alphabetically, with counts', (
    tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repo = LibraryRepository(db);
    await repo.upsertTrack(
      TracksCompanion.insert(
        filePath: '/1.mp3',
        title: 'Song 1',
        format: 'mp3',
        artist: const Value('Zeta'),
      ),
    );
    await repo.upsertTrack(
      TracksCompanion.insert(
        filePath: '/2.mp3',
        title: 'Song 2',
        format: 'mp3',
        artist: const Value('Alpha'),
      ),
    );
    await repo.upsertTrack(
      TracksCompanion.insert(
        filePath: '/3.mp3',
        title: 'Song 3',
        format: 'mp3',
        artist: const Value('Alpha'),
      ),
    );

    await pumpArtistsScreen(tester, db);

    final alphaFinder = find.text('Alpha');
    final zetaFinder = find.text('Zeta');
    expect(alphaFinder, findsOneWidget);
    expect(zetaFinder, findsOneWidget);
    expect(find.text('2 tracks'), findsOneWidget, reason: 'Alpha has 2 tracks');
    expect(
      find.text('1 track'),
      findsOneWidget,
      reason: 'Zeta has 1 track (singular)',
    );

    // Alphabetical: Alpha's Y position must be above Zeta's.
    final alphaY = tester.getTopLeft(alphaFinder).dy;
    final zetaY = tester.getTopLeft(zetaFinder).dy;
    expect(alphaY, lessThan(zetaY));

    await db.close();
  });

  testWidgets('tracks with no artist tag are bucketed under Unknown Artist', (
    tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repo = LibraryRepository(db);
    await repo.upsertTrack(
      TracksCompanion.insert(
        filePath: '/1.mp3',
        title: 'Song 1',
        format: 'mp3',
      ),
    );

    await pumpArtistsScreen(tester, db);

    expect(find.text('Unknown Artist'), findsOneWidget);

    await db.close();
  });

  testWidgets('search filters the group list by label', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repo = LibraryRepository(db);
    await repo.upsertTrack(
      TracksCompanion.insert(
        filePath: '/1.mp3',
        title: 'Song 1',
        format: 'mp3',
        artist: const Value('Beatles'),
      ),
    );
    await repo.upsertTrack(
      TracksCompanion.insert(
        filePath: '/2.mp3',
        title: 'Song 2',
        format: 'mp3',
        artist: const Value('Queen'),
      ),
    );

    await pumpArtistsScreen(tester, db);
    expect(find.text('Beatles'), findsOneWidget);
    expect(find.text('Queen'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'quee');
    await tester.pumpAndSettle();

    expect(find.text('Queen'), findsOneWidget);
    expect(find.text('Beatles'), findsNothing);

    await db.close();
  });

  testWidgets('tapping a group navigates to its track list', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repo = LibraryRepository(db);
    await repo.upsertTrack(
      TracksCompanion.insert(
        filePath: '/1.mp3',
        title: 'Bohemian Rhapsody',
        format: 'mp3',
        artist: const Value('Queen'),
      ),
    );

    await pumpArtistsScreen(tester, db);
    await tester.tap(find.text('Queen'));
    await tester.pumpAndSettle();

    expect(find.text('Bohemian Rhapsody'), findsOneWidget);

    await db.close();
  });
}
