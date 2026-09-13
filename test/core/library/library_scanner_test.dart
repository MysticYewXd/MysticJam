import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:music_player/core/library/database.dart';
import 'package:music_player/core/library/library_repository.dart';
import 'package:music_player/core/library/library_scanner.dart';

/// Throws from upsertTrack for any path containing [triggerSubstring] —
/// used to force a genuine, controlled failure through _indexFile's own
/// try/catch, the same way a real database-level error (disk full, locked
/// file, corruption) would. Metadata-parsing failures don't reach this far
/// in practice since every reader already catches its own errors and
/// returns ParsedMetadata.empty rather than throwing (see
/// core/library/metadata/*_reader.dart) — this double exists specifically
/// to exercise the failure-reporting *path*, not to simulate a bad tag file.
class _ThrowingRepository extends LibraryRepository {
  final String triggerSubstring;
  _ThrowingRepository(super.db, this.triggerSubstring);

  @override
  Future<int> upsertTrack(TracksCompanion entry) {
    final path = entry.filePath.value;
    if (path.contains(triggerSubstring)) {
      throw Exception('simulated database failure for $path');
    }
    return super.upsertTrack(entry);
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('mysticjam_scanner_test_');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  void writeFile(String name, {int bytes = 512}) {
    File(
      '${tempDir.path}/$name',
    ).writeAsBytesSync(List<int>.generate(bytes, (i) => i % 256));
  }

  group('basic scanning (post-batching refactor)', () {
    test('scanDirectory finds and adds every supported file', () async {
      writeFile('a.mp3');
      writeFile('b.flac');
      writeFile('c.txt'); // unsupported — must be ignored

      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final scanner = LibraryScanner(LibraryRepository(db));

      final result = await scanner.scanDirectory(tempDir.path);

      expect(result.addedCount, 2);
      expect(result.allPaths.length, 2);
      expect(result.failedPaths, isEmpty);
      expect(result.wasCancelled, isFalse);
    });

    test('a second scan of the same folder adds nothing new', () async {
      writeFile('a.mp3');
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final scanner = LibraryScanner(LibraryRepository(db));
      await scanner.scanDirectory(tempDir.path);

      final result = await scanner.scanDirectory(tempDir.path);

      expect(result.addedCount, 0);
      expect(result.allPaths.length, 1);
    });

    test('batching across multiple batches still finds every file', () async {
      // More than one batch's worth (_batchSize is 200) — this is the
      // actual regression risk from Phase 4's batching change: a
      // fencepost error could silently drop the last partial batch.
      for (var i = 0; i < 450; i++) {
        writeFile('track_$i.mp3', bytes: 64);
      }
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final scanner = LibraryScanner(LibraryRepository(db));

      final result = await scanner.scanDirectory(tempDir.path);

      expect(result.addedCount, 450);
      expect(result.allPaths.length, 450);
    });
  });

  group('progress reporting', () {
    test(
      'onProgress is called once per file, ending at the total count',
      () async {
        for (var i = 0; i < 15; i++) {
          writeFile('track_$i.mp3', bytes: 64);
        }
        final db = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(db.close);
        final scanner = LibraryScanner(LibraryRepository(db));
        final progressValues = <int>[];

        await scanner.scanDirectory(
          tempDir.path,
          onProgress: progressValues.add,
        );

        expect(progressValues.length, 15);
        expect(progressValues.last, 15);
        expect(
          progressValues,
          List<int>.generate(15, (i) => i + 1),
          reason: 'strictly increasing, one per file',
        );
      },
    );

    test('refreshAllMetadata reports (processed, total) pairs', () async {
      for (var i = 0; i < 5; i++) {
        writeFile('track_$i.mp3', bytes: 64);
      }
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final scanner = LibraryScanner(LibraryRepository(db));
      await scanner.scanDirectory(tempDir.path);
      final progressPairs = <(int, int)>[];

      await scanner.refreshAllMetadata(
        onProgress: (p, t) => progressPairs.add((p, t)),
      );

      expect(progressPairs.length, 5);
      expect(
        progressPairs.every((pair) => pair.$2 == 5),
        isTrue,
        reason: 'total is known upfront for a refresh',
      );
      expect(progressPairs.last.$1, 5);
    });
  });

  group('cancellation', () {
    test(
      'stopping partway through reports wasCancelled and a partial count',
      () async {
        for (var i = 0; i < 50; i++) {
          writeFile('track_$i.mp3', bytes: 64);
        }
        final db = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(db.close);
        final scanner = LibraryScanner(LibraryRepository(db));
        final token = ScanCancellationToken();

        final result = await scanner.scanDirectory(
          tempDir.path,
          cancellationToken: token,
          onProgress: (processed) {
            if (processed >= 10) token.cancel();
          },
        );

        expect(result.wasCancelled, isTrue);
        expect(result.addedCount, lessThan(50));
        expect(result.addedCount, greaterThanOrEqualTo(10));
      },
    );

    test('a cancelled scan can be resumed by scanning again', () async {
      for (var i = 0; i < 30; i++) {
        writeFile('track_$i.mp3', bytes: 64);
      }
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final scanner = LibraryScanner(LibraryRepository(db));
      final token = ScanCancellationToken();
      await scanner.scanDirectory(
        tempDir.path,
        cancellationToken: token,
        onProgress: (processed) {
          if (processed >= 5) token.cancel();
        },
      );

      final resumed = await scanner.scanDirectory(tempDir.path);

      expect(
        resumed.addedCount,
        30 - 5,
        reason: 'only the files not yet indexed get added on the resume scan',
      );
    });
  });

  group('duplicate handling', () {
    test(
      'scanFiles with the same path listed twice only processes it once',
      () async {
        writeFile('a.mp3');
        final path = '${tempDir.path}/a.mp3';
        final db = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(db.close);
        final scanner = LibraryScanner(LibraryRepository(db));

        final result = await scanner.scanFiles([path, path, path]);

        expect(result.addedCount, 1);
        expect(result.allPaths, [path]);
      },
    );
  });

  group('missing-file handling', () {
    test('refreshAllMetadata removes a track whose file was deleted', () async {
      writeFile('a.mp3');
      final path = '${tempDir.path}/a.mp3';
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = LibraryRepository(db);
      final scanner = LibraryScanner(repo);
      await scanner.scanDirectory(tempDir.path);
      File(path).deleteSync();

      final result = await scanner.refreshAllMetadata();

      expect(result.removed, 1);
      expect(await repo.trackExists(path), isFalse);
    });
  });

  group('error reporting', () {
    test(
      'one failing file is reported in failedPaths without blocking the rest of its batch',
      () async {
        writeFile('good_1.mp3', bytes: 64);
        writeFile('bad.mp3', bytes: 64);
        writeFile('good_2.mp3', bytes: 64);
        final db = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(db.close);
        final repo = _ThrowingRepository(db, 'bad.mp3');
        final scanner = LibraryScanner(repo);

        final result = await scanner.scanDirectory(tempDir.path);

        expect(result.failedPaths.length, 1);
        expect(result.failedPaths.first, contains('bad.mp3'));
        expect(
          result.addedCount,
          2,
          reason:
              'the other two files in the same batch/transaction must still be '
              'committed — one failure must not roll back the whole batch',
        );
        expect(await repo.trackExists('${tempDir.path}/good_1.mp3'), isTrue);
        expect(await repo.trackExists('${tempDir.path}/good_2.mp3'), isTrue);
        expect(await repo.trackExists('${tempDir.path}/bad.mp3'), isFalse);
      },
    );
  });
}
