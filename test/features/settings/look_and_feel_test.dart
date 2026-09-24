import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:music_player/core/library/database.dart';
import 'package:music_player/core/library/library_providers.dart';
import 'package:music_player/core/settings/app_settings.dart';
import 'package:music_player/features/settings/look_and_feel_screen.dart';

class _FakePathProvider extends PathProviderPlatform {
  final String path;
  _FakePathProvider(this.path);
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('mysticjam_laf_');
    PathProviderPlatform.instance = _FakePathProvider(dir.path);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<ProviderContainer> pump(WidgetTester tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: LookAndFeelScreen()),
      ),
    );
    return container;
  }

  testWidgets('choosing Middle updates the lyrics position', (tester) async {
    final container = await pump(tester);
    expect(container.read(uiPrefsProvider).lyricsAlign, LyricsAlign.left);

    await tester.tap(find.text('Middle'));
    await tester.pumpAndSettle();
    expect(container.read(uiPrefsProvider).lyricsAlign, LyricsAlign.center);
  });

  testWidgets('toggles flip their preference', (tester) async {
    final container = await pump(tester);
    await tester.tap(find.text('Look up missing lyrics online'));
    await tester.pumpAndSettle();
    expect(container.read(uiPrefsProvider).lyricsOnlineLookup, isFalse);

    await tester.tap(find.text('Show FPS counter'));
    await tester.pumpAndSettle();
    expect(container.read(uiPrefsProvider).showFps, isTrue);
  });

  testWidgets('shows the monitor refresh rate', (tester) async {
    await pump(tester);
    expect(find.textContaining('60 Hz'), findsOneWidget);
  });

  testWidgets('Rescan lyrics reports how many songs it found', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Rescan lyrics'));
    await tester.pumpAndSettle();
    expect(find.textContaining('found lyrics for 0 tracks'), findsOneWidget);
  });
}
