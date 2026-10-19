/// Read-only benchmark of library scanning: times the real [LibraryScanner]
/// on a music folder and snapshots exactly what it stored for every file —
/// the baseline the Rust scanner is checked against (speed and results).
///
/// Never touches the user's library or the app's real data: each run scans
/// into a fresh in-memory database, and cover art (which the scanner saves
/// under the app support directory) is redirected to a temporary folder.
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:music_player/core/audio/format_support.dart';
import 'package:music_player/core/library/database.dart';
import 'package:music_player/core/library/library_repository.dart';
import 'package:music_player/core/library/library_scanner.dart';
import 'package:music_player/core/library/metadata/metadata_reader.dart';

/// Sends the scanner's cover-art writes to [path] instead of the app's real
/// support directory.
class _RedirectedSupportDir extends PathProviderPlatform {
  final String path;
  _RedirectedSupportDir(this.path);

  @override
  Future<String?> getApplicationSupportPath() async => path;
}

/// What the scanner stored for one file. Field-for-field what a later
/// scanner must reproduce (lyrics may only be gained, never lost).
class FileSnapshot {
  final String path;
  final String format;
  final String title;
  final String? artist;
  final String? album;
  final String? albumArtist;
  final int? year;
  final int? trackNumber;
  final String? genre;
  final int? durationMs;
  final String? lyrics;
  final String? syncedLyrics;

  /// Size in bytes of the saved cover art, or null if none was found.
  final int? artworkBytes;

  const FileSnapshot({
    required this.path,
    required this.format,
    required this.title,
    this.artist,
    this.album,
    this.albumArtist,
    this.year,
    this.trackNumber,
    this.genre,
    this.durationMs,
    this.lyrics,
    this.syncedLyrics,
    this.artworkBytes,
  });

  Map<String, Object?> toJson() => {
    'path': path,
    'format': format,
    'title': title,
    'artist': artist,
    'album': album,
    'albumArtist': albumArtist,
    'year': year,
    'trackNumber': trackNumber,
    'genre': genre,
    'durationMs': durationMs,
    'lyrics': lyrics,
    'syncedLyrics': syncedLyrics,
    'artworkBytes': artworkBytes,
  };

  factory FileSnapshot.fromJson(Map<String, Object?> j) => FileSnapshot(
    path: j['path']! as String,
    format: j['format']! as String,
    title: j['title']! as String,
    artist: j['artist'] as String?,
    album: j['album'] as String?,
    albumArtist: j['albumArtist'] as String?,
    year: j['year'] as int?,
    trackNumber: j['trackNumber'] as int?,
    genre: j['genre'] as String?,
    durationMs: j['durationMs'] as int?,
    lyrics: j['lyrics'] as String?,
    syncedLyrics: j['syncedLyrics'] as String?,
    artworkBytes: j['artworkBytes'] as int?,
  );

  @override
  bool operator ==(Object other) =>
      other is FileSnapshot &&
      jsonEncode(toJson()) == jsonEncode(other.toJson());

  @override
  int get hashCode => jsonEncode(toJson()).hashCode;
}

/// Tag-reading cost for one format, measured on its own (no database).
class FormatTiming {
  final int files;
  final int tagReadMs;
  const FormatTiming(this.files, this.tagReadMs);

  Map<String, Object?> toJson() => {'files': files, 'tagReadMs': tagReadMs};
}

class BenchmarkReport {
  final String musicDir;
  final int cpuCount;

  /// Wall time of each full scan (walk + tags + art + lyrics + database).
  final List<int> fullScanMs;

  /// Time to walk the folder and find the supported files.
  final int walkMs;
  final Map<String, FormatTiming> formats;
  final List<FileSnapshot> snapshot;
  final List<String> failedPaths;

  const BenchmarkReport({
    required this.musicDir,
    required this.cpuCount,
    required this.fullScanMs,
    required this.walkMs,
    required this.formats,
    required this.snapshot,
    required this.failedPaths,
  });

  int get withEmbeddedLyrics => snapshot.where((s) => s.lyrics != null).length;
  int get withSyncedLyrics =>
      snapshot.where((s) => s.syncedLyrics != null).length;
  int get withAnyLyrics =>
      snapshot.where((s) => s.lyrics != null || s.syncedLyrics != null).length;
  int get withArtwork => snapshot.where((s) => s.artworkBytes != null).length;

  Map<String, Object?> toJson() => {
    'musicDir': musicDir,
    'cpuCount': cpuCount,
    'fullScanMs': fullScanMs,
    'walkMs': walkMs,
    'formats': {for (final e in formats.entries) e.key: e.value.toJson()},
    'files': snapshot.length,
    'failed': failedPaths,
    'lyrics': {
      'embedded': withEmbeddedLyrics,
      'synced': withSyncedLyrics,
      'any': withAnyLyrics,
    },
    'artwork': withArtwork,
  };

  /// A short human-readable summary.
  String summary() {
    final b = StringBuffer()
      ..writeln('Scan benchmark: $musicDir')
      ..writeln('  files: ${snapshot.length}  (failed: ${failedPaths.length})')
      ..writeln('  full scan runs (ms): ${fullScanMs.join(', ')}')
      ..writeln('  folder walk (ms): $walkMs')
      ..writeln('  tag reading by format:');
    for (final e in formats.entries) {
      final f = e.value;
      final per = f.files == 0 ? 0 : f.tagReadMs / f.files;
      b.writeln(
        '    ${e.key.padRight(5)} ${f.files} files, ${f.tagReadMs} ms '
        '(${per.toStringAsFixed(2)} ms/file)',
      );
    }
    b
      ..writeln(
        '  lyrics: embedded $withEmbeddedLyrics, synced (.lrc) '
        '$withSyncedLyrics, any $withAnyLyrics of ${snapshot.length}',
      )
      ..writeln('  cover art: $withArtwork of ${snapshot.length}');
    return b.toString();
  }
}

String _format(String path) =>
    p.extension(path).replaceFirst('.', '').toLowerCase();

/// Runs the benchmark on [musicDir]: [runs] full scans (the first may be
/// slower if the files aren't in the OS cache yet), one timed folder walk,
/// and one timed tag-reading pass per format. The snapshot comes from the
/// last full scan's database.
Future<BenchmarkReport> runBenchmark(String musicDir, {int runs = 3}) async {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final scratch = Directory.systemTemp.createTempSync('mysticjam_bench_');
  final previousPlatform = PathProviderPlatform.instance;
  try {
    // Folder walk on its own.
    final walk = Stopwatch()..start();
    final files = <String>[];
    await for (final e in Directory(
      musicDir,
    ).list(recursive: true, followLinks: false)) {
      if (e is File && isSupportedMediaFile(e.path)) files.add(e.path);
    }
    walk.stop();
    files.sort();

    // Tag reading on its own, per format.
    final byFormat = <String, List<String>>{};
    for (final f in files) {
      byFormat.putIfAbsent(_format(f), () => []).add(f);
    }
    final formats = <String, FormatTiming>{};
    for (final e
        in (byFormat.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key)))) {
      final sw = Stopwatch()..start();
      for (final f in e.value) {
        await readTrackMetadata(f);
      }
      sw.stop();
      formats[e.key] = FormatTiming(e.value.length, sw.elapsedMilliseconds);
    }

    // Full scans through the real scanner.
    final scanMs = <int>[];
    late List<FileSnapshot> snapshot;
    late List<String> failed;
    for (var run = 0; run < runs; run++) {
      final artRoot = Directory(p.join(scratch.path, 'run$run'))..createSync();
      PathProviderPlatform.instance = _RedirectedSupportDir(artRoot.path);
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      try {
        final scanner = LibraryScanner(LibraryRepository(db));
        final sw = Stopwatch()..start();
        final result = await scanner.scanDirectory(musicDir);
        sw.stop();
        scanMs.add(sw.elapsedMilliseconds);
        failed = result.failedPaths;
        if (run == runs - 1) snapshot = await _snapshot(db);
      } finally {
        await db.close();
      }
    }

    return BenchmarkReport(
      musicDir: musicDir,
      cpuCount: Platform.numberOfProcessors,
      fullScanMs: scanMs,
      walkMs: walk.elapsedMilliseconds,
      formats: formats,
      snapshot: snapshot,
      failedPaths: failed,
    );
  } finally {
    PathProviderPlatform.instance = previousPlatform;
    scratch.deleteSync(recursive: true);
  }
}

Future<List<FileSnapshot>> _snapshot(AppDatabase db) async {
  final albums = {
    for (final a in await db.select(db.albums).get()) a.id: a.title,
  };
  final tracks = await db.select(db.tracks).get();
  tracks.sort((a, b) => a.filePath.compareTo(b.filePath));
  return [
    for (final t in tracks)
      FileSnapshot(
        path: t.filePath,
        format: t.format,
        title: t.title,
        artist: t.artist,
        // The album the scanner grouped it under (tag-based), falling back
        // to the raw album tag.
        album: albums[t.albumId] ?? t.album,
        albumArtist: t.albumArtist,
        year: t.year,
        trackNumber: t.trackNumber,
        genre: t.genre,
        durationMs: t.durationMs,
        lyrics: t.lyrics,
        syncedLyrics: t.syncedLyrics,
        artworkBytes: t.albumArtPath == null
            ? null
            : File(t.albumArtPath!).lengthSync(),
      ),
  ];
}

/// Writes `report.json`, `snapshot.json` and `summary.txt` into [outDir].
void writeReport(BenchmarkReport report, String outDir) {
  final dir = Directory(outDir)..createSync(recursive: true);
  const enc = JsonEncoder.withIndent('  ');
  File(
    p.join(dir.path, 'report.json'),
  ).writeAsStringSync(enc.convert(report.toJson()));
  File(p.join(dir.path, 'snapshot.json')).writeAsStringSync(
    enc.convert([for (final s in report.snapshot) s.toJson()]),
  );
  File(p.join(dir.path, 'summary.txt')).writeAsStringSync(report.summary());
}

/// Reads a `snapshot.json` written by [writeReport].
List<FileSnapshot> readSnapshot(String path) => [
  for (final j in jsonDecode(File(path).readAsStringSync()) as List)
    FileSnapshot.fromJson((j as Map).cast<String, Object?>()),
];
