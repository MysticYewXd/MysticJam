import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:music_player/core/library/database.dart';
import 'package:music_player/core/library/library_providers.dart';
import 'package:music_player/core/library/library_repository.dart';
import 'package:music_player/core/library/library_scanner.dart';
import 'package:music_player/features/library/library_drop_target.dart';

import '../../helpers/flac_fixture.dart';

class _FakePathProvider extends PathProviderPlatform {
  final String path;
  _FakePathProvider(this.path);
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

Future<void> _send(WidgetTester tester, String method, [Object? args]) async {
  const codec = StandardMethodCodec();
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'desktop_drop',
    codec.encodeMethodCall(MethodCall(method, args)),
    (_) {},
  );
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory root;
  late Directory support;
  late AppDatabase db;
  late LibraryScanner scanner;

  setUp(() {
    root = Directory.systemTemp.createTempSync('mysticjam_drop_');
    support = Directory.systemTemp.createTempSync('mysticjam_drop_support_');
    PathProviderPlatform.instance = _FakePathProvider(support.path);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    scanner = LibraryScanner(LibraryRepository(db));
  });

  tearDown(() async {
    await db.close();
    root.deleteSync(recursive: true);
    support.deleteSync(recursive: true);
  });

  String audio(String relative) {
    final f = File('${root.path}/$relative')
      ..createSync(recursive: true)
      ..writeAsBytesSync(buildFlac(['TITLE=Song']));
    return f.path;
  }

  group('importDroppedPaths', () {
    test('a dropped folder is scanned recursively', () async {
      audio('album/one.flac');
      audio('album/deeper/two.flac');
      final result = await importDroppedPaths(scanner, ['${root.path}/album']);
      expect(result.added, 2);
      expect(result.failed, 0);
    });

    test(
      'loose files, unsupported files and missing paths are handled',
      () async {
        final good = audio('a.flac');
        final notMusic = File('${root.path}/notes.txt')
          ..writeAsStringSync('hi');
        final result = await importDroppedPaths(scanner, [
          good,
          notMusic.path,
          '${root.path}/does-not-exist.flac',
        ]);
        expect(result.added, 1);
      },
    );

    test(
      'a folder and a file dropped together are both added; folders reported',
      () async {
        audio('dir/x.flac');
        final loose = audio('loose.flac');
        final folders = <String>[];
        final result = await importDroppedPaths(scanner, [
          '${root.path}/dir',
          loose,
        ], onFolderImported: folders.add);
        expect(result.added, 2);
        expect(folders, ['${root.path}/dir']);
      },
    );

    test('dropping the same music again adds nothing', () async {
      audio('again.flac');
      await importDroppedPaths(scanner, ['${root.path}/again.flac']);
      final second = await importDroppedPaths(scanner, [
        '${root.path}/again.flac',
      ]);
      expect(second.added, 0);
    });
  });

  group('LibraryDropTarget', () {
    Future<void> pump(WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [libraryScannerProvider.overrideWithValue(scanner)],
          child: const MaterialApp(
            home: Scaffold(body: LibraryDropTarget(child: SizedBox.expand())),
          ),
        ),
      );
    }

    testWidgets(
      'shows a hint while dragging over, hides it when the drag leaves',
      (tester) async {
        await pump(tester);
        expect(find.textContaining('Drop music'), findsNothing);

        await _send(tester, 'entered', [100.0, 100.0]);
        await tester.pump();
        expect(find.textContaining('Drop music'), findsOneWidget);

        await _send(tester, 'exited');
        await tester.pump();
        expect(find.textContaining('Drop music'), findsNothing);
      },
    );

    testWidgets('dropping a song adds it and confirms', (tester) async {
      final song = audio('drop.flac');
      await pump(tester);

      await _send(tester, 'entered', [100.0, 100.0]);
      await tester.pump();
      await tester.runAsync(() async {
        await _send(tester, 'performOperation', [song]);
        await Future<void>.delayed(const Duration(milliseconds: 500));
      });
      await tester.pump();

      expect(find.textContaining('Added 1 song'), findsOneWidget);
      expect(find.textContaining('Drop music'), findsNothing);
      expect(
        await tester.runAsync(() => scanner.repository.trackExists(song)),
        isTrue,
      );
    });

    testWidgets('dropping non-music says nothing new was found', (
      tester,
    ) async {
      final txt = File('${root.path}/a.txt')..writeAsStringSync('x');
      await pump(tester);
      await _send(tester, 'entered', [100.0, 100.0]);
      await tester.runAsync(() async {
        await _send(tester, 'performOperation', [txt.path]);
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
      expect(find.textContaining('No new songs'), findsOneWidget);
    });
  });
}
