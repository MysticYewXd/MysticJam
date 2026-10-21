import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../audio/format_support.dart';
import 'album_grouping.dart';
import 'database.dart';
import 'library_repository.dart';
import '../../src/rust/api/scan.dart' as rust;
import '../logging/app_log.dart';
import 'track_file_reader.dart';

/// How many files' worth of database writes get wrapped into one
/// transaction. Chosen from Phase 4's benchmark: an unbatched scan of 501
/// small files took ~238ms/file (dominated by one fsync-backed commit per
/// file against the real on-disk SQLite file); batching collapses that to
/// one commit per [_batchSize] files. Kept well under the full scan size
/// (rather than one giant transaction for the whole library) so
/// cancellation and progress reporting stay responsive — a batch in
/// progress still has to finish, but 200 files' worth is a bounded, short
/// wait either way.
const _batchSize = 200;

/// How many files are read in parallel (in Rust, across all CPU cores)
/// before being saved. Much smaller than [_batchSize] because a read result
/// holds the cover art in memory, often hundreds of KB per song; 32 keeps
/// every core busy while capping that at a few tens of MB.
const _readChunkSize = 32;

/// Bump whenever reading tags, covers or lyrics changes in a way old
/// results should pick up: every stored stamp then stops matching, so the
/// next "Refresh Metadata" re-reads every song once.
const scanReaderVersion = 1;

/// Same names the Rust reader looks for (rust/src/sidecar.rs), matched
/// case-insensitively.
const _coverNames = {'cover', 'folder', 'album', 'front', 'albumart'};
const _coverExtensions = {'.jpg', '.jpeg', '.png'};

/// A fingerprint of everything a read of [audioPath] depends on: the file's
/// size and modified time, its `.lrc` sidecar's, and the folder cover
/// images' — so a refresh can tell an unchanged song apart without reading
/// it. Null when the file is gone. [coverStamps] caches the cover part per
/// folder for the length of one scan, so a folder is listed only once.
@visibleForTesting
Future<String?> scanStampFor(
  String audioPath, {
  Map<String, Future<String>>? coverStamps,
}) async {
  final audio = await File(audioPath).stat();
  if (audio.type != FileSystemEntityType.file) return null;
  String part(FileStat s) => s.type == FileSystemEntityType.file
      ? '${s.size}@${s.modified.millisecondsSinceEpoch}'
      : '-';
  final base = p.withoutExtension(audioPath);
  final lrc = [
    part(await File('$base.lrc').stat()),
    part(await File('$base.LRC').stat()),
  ].join(',');
  final dir = p.dirname(audioPath);
  final covers = await (coverStamps ?? {}).putIfAbsent(
    dir,
    () => _coverStampOf(dir),
  );
  return 'v$scanReaderVersion|${part(audio)}|$lrc|$covers';
}

Future<String> _coverStampOf(String dir) async {
  final found = <String>[];
  try {
    await for (final entry in Directory(dir).list(followLinks: false)) {
      final name = p.basename(entry.path);
      final ext = p.extension(name).toLowerCase();
      if (!_coverExtensions.contains(ext) ||
          !_coverNames.contains(p.withoutExtension(name).toLowerCase())) {
        continue;
      }
      final s = await entry.stat();
      if (s.type == FileSystemEntityType.file) {
        found.add('$name:${s.size}@${s.modified.millisecondsSinceEpoch}');
      }
    }
  } catch (_) {
    // An unreadable folder just gets an empty cover part.
  }
  found.sort();
  return found.join(',');
}

/// Lets a caller ask an in-progress scan to stop early — checked once per
/// file, so cancellation takes effect within roughly one file's processing
/// time, not instantly, but well within a single batch.
class ScanCancellationToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

/// Result of a scan: every supported file matched (whether newly indexed or
/// already present in the library) plus how many were actually new. Callers
/// that need to act on the exact files involved (e.g. adding them straight
/// into a playlist) use [allPaths]; callers that just need a status message
/// use [addedCount]. [failedPaths] is populated whenever a file couldn't be
/// indexed (unreadable, corrupt, permission denied, etc.) — previously
/// these were silently swallowed with no way for the UI to know anything
/// had gone wrong at all. [wasCancelled] is true when a [ScanCancellationToken]
/// stopped the scan before it reached every file.
class ScanResult {
  final List<String> allPaths;
  final int addedCount;
  final List<String> failedPaths;
  final bool wasCancelled;

  const ScanResult(
    this.allPaths,
    this.addedCount, {
    this.failedPaths = const [],
    this.wasCancelled = false,
  });
}

/// Outcome of indexing a single file — richer than a plain bool so the
/// scanner can tell "added" apart from "failed" apart from "already
/// present, nothing to do", instead of collapsing all three into one
/// boolean the way this used to work.
///
/// [skipped] is a refresh's "not re-read: its stamp still matches".
enum _IndexOutcome { added, unchanged, skipped, removed, failed }

/// Indexes supported media files into the library — either by walking a
/// folder tree, or from an explicit list of individually-picked files.
/// Reads tags, cover art and lyrics through readTrackFile (Rust, with a
/// Dart reader for WMA); falls back to the filename for the title when a
/// file has none.
class LibraryScanner {
  final LibraryRepository repository;

  LibraryScanner(this.repository);

  /// Indexes [batch] inside one database transaction. Normally skips files
  /// already in the library — pass [forceRescan] to re-parse and overwrite
  /// existing entries instead (used by "Refresh Metadata"), which also
  /// removes tracks whose file is gone. With [skipUnchanged] as well, a
  /// file whose scan stamp still matches the stored one isn't re-read.
  ///
  /// Files are read [_readChunkSize] at a time, in parallel (see
  /// readTrackFiles), then saved one by one; [onIndexed] runs after each
  /// file is saved. [cancellationToken] is checked before every file, so a
  /// cancel requested from inside [onIndexed] takes effect at the next one.
  /// Returns true if it was cancelled.
  ///
  /// Never throws — one corrupt/unreadable file must not abort a whole
  /// batch scan or refresh; its outcome is reported as
  /// [_IndexOutcome.failed] instead.
  Future<bool> _indexBatch(
    List<String> batch, {
    required bool forceRescan,
    bool skipUnchanged = false,
    required ScanCancellationToken? cancellationToken,
    required void Function(String path, _IndexOutcome outcome) onIndexed,
  }) async {
    final coverStamps = <String, Future<String>>{};
    var cancelled = false;
    bool stop() => cancelled = cancellationToken?.isCancelled ?? false;
    await repository.db.transaction(() async {
      for (var i = 0; i < batch.length; i += _readChunkSize) {
        if (stop()) return;
        final chunk = batch.sublist(
          i,
          (i + _readChunkSize).clamp(0, batch.length),
        );

        // Work out what needs reading before reading anything. The stamp
        // is taken before the read, so a file changing mid-read just gets
        // re-read next time.
        final decided = <String, _IndexOutcome>{};
        final alreadyIndexed = <String>{};
        final stamps = <String, String?>{};
        final toRead = <String>[];
        for (final path in chunk) {
          try {
            final known = await repository.scanStampOf(path);
            if (known.exists && !forceRescan) {
              decided[path] = _IndexOutcome.unchanged;
              continue;
            }
            final stamp = await scanStampFor(path, coverStamps: coverStamps);
            if (forceRescan && stamp == null) {
              await repository.deleteTrackByPath(path);
              decided[path] = _IndexOutcome.removed;
            } else if (skipUnchanged && stamp != null && stamp == known.stamp) {
              decided[path] = _IndexOutcome.skipped;
            } else {
              if (known.exists) alreadyIndexed.add(path);
              stamps[path] = stamp;
              toRead.add(path);
            }
          } catch (_) {
            decided[path] = _IndexOutcome.failed;
          }
        }

        final read = await readTrackFiles(toRead);
        for (final path in chunk) {
          if (stop()) return;
          final outcome =
              decided[path] ??
              await _store(
                path,
                read[path]!,
                stamp: stamps[path],
                alreadyIndexed: alreadyIndexed.contains(path),
              );
          onIndexed(path, outcome);
        }
      }
    });
    return cancelled;
  }

  /// Saves one read file: its album, track row and cover art.
  Future<_IndexOutcome> _store(
    String path,
    TrackFileData file, {
    required String? stamp,
    required bool alreadyIndexed,
  }) async {
    try {
      final ext = p.extension(path).replaceFirst('.', '').toLowerCase();
      final metadata = file.metadata;
      final title = metadata.title ?? p.basenameWithoutExtension(path);
      final syncedLyrics = file.syncedLyrics;

      // Album membership comes from the tags alone (see albumKeyFor) — never
      // the folder — and falls back to the Unknown Album bucket when the
      // tags are missing/unreadable, so every indexed track has an album.
      final albumId = await repository.findOrCreateAlbum(
        albumKeyFor(
          album: metadata.album,
          albumArtist: metadata.albumArtist,
          artist: metadata.artist,
        ),
        year: metadata.year,
      );

      final id = await repository.upsertTrack(
        TracksCompanion.insert(
          filePath: path,
          title: title,
          artist: Value(metadata.artist),
          album: Value(metadata.album),
          format: ext,
          // Value.absent() (not Value(null)) when a reader has no duration —
          // on a forced re-scan this must leave an existing duration alone
          // rather than wiping out one already learned from actual playback
          // (see PlaybackController), since most formats' tag readers can't
          // get duration for free the way FLAC's STREAMINFO does.
          durationMs: metadata.durationMs != null
              ? Value(metadata.durationMs)
              : const Value.absent(),
          lyrics: metadata.lyrics != null
              ? Value(metadata.lyrics)
              : const Value.absent(),
          albumId: Value(albumId),
          albumArtist: Value(metadata.albumArtist),
          year: Value(metadata.year),
          genre: metadata.genre != null
              ? Value(metadata.genre)
              : const Value.absent(),
          trackNumber: metadata.trackNumber != null
              ? Value(metadata.trackNumber)
              : const Value.absent(),
          syncedLyrics: syncedLyrics != null
              ? Value(syncedLyrics)
              : const Value.absent(),
          scanStamp: Value(stamp),
        ),
      );

      // Embedded art, else a cover.jpg/folder.jpg next to the audio (see
      // readTrackFile).
      final artwork = metadata.artwork;
      if (artwork != null) {
        final artPath = await _saveArtwork(id, artwork);
        if (artPath != null) {
          await repository.setAlbumArtPath(id, artPath);
          await repository.setAlbumCoverIfMissing(albumId, artPath);
        }
      }

      return alreadyIndexed ? _IndexOutcome.unchanged : _IndexOutcome.added;
    } catch (_) {
      return _IndexOutcome.failed;
    }
  }

  /// Re-reads only the lyrics of every indexed track: embedded lyrics tags
  /// and the `.lrc` sidecar next to each file. Existing lyrics are only ever
  /// replaced, never cleared — the synced column also holds lyrics fetched
  /// online, which a rescan must not throw away just because no `.lrc` file
  /// exists. Reads first (reporting progress), then writes everything in one
  /// transaction, since unbatched per-file writes are ~140x slower (see
  /// [_batchSize]). Returns how many tracks now have a lyrics update.
  Future<int> rescanLyrics({
    void Function(int done, int total)? onProgress,
  }) async {
    final paths = await repository.getAllFilePaths();
    final found = <String, ({String? plain, String? synced})>{};
    for (var i = 0; i < paths.length; i++) {
      final path = paths[i];
      if (await File(path).exists()) {
        final file = await readTrackFile(path);
        final synced = file.syncedLyrics;
        final plain = file.metadata.lyrics;
        if (synced != null || plain != null) {
          found[path] = (plain: plain, synced: synced);
        }
      }
      onProgress?.call(i + 1, paths.length);
    }
    await repository.setLyricsForPaths(found);
    AppLog.info('scan', 'lyrics rescan finished', {
      'checked': paths.length,
      'found': found.length,
    });
    return found.length;
  }

  Future<String?> _saveArtwork(int trackId, Uint8List bytes) async {
    try {
      final supportDir = await getApplicationSupportDirectory();
      final artDir = Directory(p.join(supportDir.path, 'album_art'));
      if (!await artDir.exists()) await artDir.create(recursive: true);
      final file = File(p.join(artDir.path, '$trackId.art'));
      await file.writeAsBytes(bytes);
      return file.path;
    } catch (_) {
      // Missing art is a cosmetic loss, not worth failing the whole scan over.
      return null;
    }
  }

  /// Indexes every supported file in [directoryPath] in [_batchSize]-sized
  /// batches, each batch wrapped in one database transaction — see
  /// [_batchSize]'s doc comment for why this matters (measured ~140x
  /// per-file speedup over one commit per file). [onProgress], if given, is
  /// called after every file with the running count (no fixed total — a
  /// streaming directory walk doesn't know how many files exist ahead of
  /// time without a wasted separate pass). [cancellationToken], if
  /// cancelled, stops the scan after the current batch and returns whatever
  /// was processed so far via [ScanResult.wasCancelled].
  Future<ScanResult> scanDirectory(
    String directoryPath, {
    bool forceRescan = false,
    ScanCancellationToken? cancellationToken,
    void Function(int processed)? onProgress,
  }) async {
    final clock = Stopwatch()..start();
    final dir = Directory(directoryPath);
    if (!await dir.exists()) return const ScanResult([], 0);

    final allPaths = <String>[];
    final failedPaths = <String>[];
    final seenPaths = <String>{};
    var added = 0;
    var processed = 0;
    var wasCancelled = false;

    // Rust walks the folder and streams paths in batches (sorted by name,
    // so "first-seen wins" for album title casing and cover art is
    // deterministic). Leaving the loop cancels the stream, which stops the
    // walk.
    final batches = rust.walkMediaFiles(
      root: directoryPath,
      extensions: allSupportedExtensions.toList(),
      batchSize: _batchSize,
    );
    await for (final found in batches) {
      if (cancellationToken?.isCancelled ?? false) {
        wasCancelled = true;
        break;
      }
      // Duplicate handling: a case-insensitive filesystem quirk could
      // otherwise surface the same path twice in one walk.
      final batch = [
        for (final path in found)
          if (seenPaths.add(path)) path,
      ];
      allPaths.addAll(batch);
      wasCancelled = await _indexBatch(
        batch,
        forceRescan: forceRescan,
        cancellationToken: cancellationToken,
        onIndexed: (path, outcome) {
          if (outcome == _IndexOutcome.added) added++;
          if (outcome == _IndexOutcome.failed) failedPaths.add(path);
          processed++;
          onProgress?.call(processed);
        },
      );
      if (wasCancelled) break;
    }
    // Even after a cancel: songs may already have moved to new albums.
    if (forceRescan) await repository.deleteEmptyAlbums();

    return _logged(
      'folder',
      clock,
      ScanResult(
        allPaths,
        added,
        failedPaths: failedPaths,
        wasCancelled: wasCancelled,
      ),
    );
  }

  /// Counts and timing only — never which files (see AppLog).
  ScanResult _logged(String kind, Stopwatch clock, ScanResult r) {
    AppLog.info('scan', 'finished', {
      'kind': kind,
      'matched': r.allPaths.length,
      'added': r.addedCount,
      'failed': r.failedPaths.length,
      'cancelled': r.wasCancelled,
      'ms': clock.elapsedMilliseconds,
    });
    return r;
  }

  /// Indexes an explicit list of individually-picked files (as opposed to
  /// walking a whole folder). Same batching/cancellation/progress/failure
  /// reporting as [scanDirectory].
  Future<ScanResult> scanFiles(
    List<String> filePaths, {
    bool forceRescan = false,
    ScanCancellationToken? cancellationToken,
    void Function(int processed)? onProgress,
  }) async {
    final clock = Stopwatch()..start();
    final supported = <String>[];
    final seenPaths = <String>{};
    for (final path in filePaths.where(isSupportedMediaFile)) {
      if (seenPaths.add(path)) supported.add(path);
    }

    final failedPaths = <String>[];
    var added = 0;
    var processed = 0;
    var wasCancelled = false;

    for (var i = 0; i < supported.length; i += _batchSize) {
      if (wasCancelled || (cancellationToken?.isCancelled ?? false)) {
        wasCancelled = true;
        break;
      }
      wasCancelled = await _indexBatch(
        supported.skip(i).take(_batchSize).toList(),
        forceRescan: forceRescan,
        cancellationToken: cancellationToken,
        onIndexed: (path, outcome) {
          if (outcome == _IndexOutcome.added) added++;
          if (outcome == _IndexOutcome.failed) failedPaths.add(path);
          processed++;
          onProgress?.call(processed);
        },
      );
    }

    if (forceRescan) await repository.deleteEmptyAlbums();

    return _logged(
      'files',
      clock,
      ScanResult(
        supported,
        added,
        failedPaths: failedPaths,
        wasCancelled: wasCancelled,
      ),
    );
  }

  /// Re-parses every already-indexed file's metadata and overwrites the
  /// stored title/artist/album/art — for picking up real tags on tracks
  /// that were scanned before this feature existed (or before a format had
  /// a reader), and for repairing tracks left stale by any past bug,
  /// without the user ever having to delete and re-add them by hand.
  /// Tracks whose file no longer exists on disk are removed outright.
  /// [onProgress] gets a real (processed, total) pair here — unlike
  /// [scanDirectory], the full path list is already known upfront.
  ///
  /// Afterwards each of [folders] (the ones added through "Add Folder") is
  /// walked for songs that arrived since, which are added like a normal
  /// scan would. Folders that are gone (an unplugged drive) are skipped.
  ///
  /// Songs whose scan stamp (see [scanStampFor]) hasn't changed since they
  /// were last read are skipped instead of re-read.
  Future<RefreshResult> refreshAllMetadata({
    List<String> folders = const [],
    ScanCancellationToken? cancellationToken,
    void Function(int processed, int total)? onProgress,
  }) async {
    final clock = Stopwatch()..start();
    final paths = await repository.getAllFilePaths();
    var removed = 0;
    var processed = 0;
    var added = 0;
    var failed = 0;
    var skipped = 0;
    var wasCancelled = false;

    for (var i = 0; i < paths.length; i += _batchSize) {
      if (wasCancelled || (cancellationToken?.isCancelled ?? false)) {
        wasCancelled = true;
        break;
      }
      wasCancelled = await _indexBatch(
        paths.skip(i).take(_batchSize).toList(),
        forceRescan: true,
        skipUnchanged: true,
        cancellationToken: cancellationToken,
        onIndexed: (path, outcome) {
          if (outcome == _IndexOutcome.removed) removed++;
          if (outcome == _IndexOutcome.skipped) skipped++;
          processed++;
          onProgress?.call(processed, paths.length);
        },
      );
    }

    // Runs after the refresh so new songs aren't read twice; files already
    // in the library are skipped by the scan.
    for (final folder in folders) {
      if (wasCancelled || (cancellationToken?.isCancelled ?? false)) {
        wasCancelled = true;
        break;
      }
      final found = await scanDirectory(
        folder,
        cancellationToken: cancellationToken,
      );
      added += found.addedCount;
      failed += found.failedPaths.length;
      wasCancelled = found.wasCancelled;
    }

    // Songs whose tags changed have moved to other albums; drop the albums
    // they left empty (even after a cancel).
    final emptied = await repository.deleteEmptyAlbums();
    AppLog.info('scan', 'refresh finished', {
      'processed': processed,
      'removed': removed,
      'skipped': skipped,
      'added': added,
      'failed': failed,
      'emptyAlbumsRemoved': emptied,
      'cancelled': wasCancelled,
      'ms': clock.elapsedMilliseconds,
    });

    return RefreshResult(
      processed: processed,
      removed: removed,
      skipped: skipped,
      added: added,
      failed: failed,
      wasCancelled: wasCancelled,
    );
  }
}

class RefreshResult {
  final int processed;
  final int removed;

  /// Songs not re-read because they hadn't changed (part of [processed]).
  final int skipped;

  /// New songs found in the saved folders.
  final int added;

  /// New songs that couldn't be read.
  final int failed;
  final bool wasCancelled;

  const RefreshResult({
    required this.processed,
    required this.removed,
    this.skipped = 0,
    this.added = 0,
    this.failed = 0,
    this.wasCancelled = false,
  });
}
