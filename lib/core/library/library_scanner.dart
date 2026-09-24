import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../audio/format_support.dart';
import '../logging/app_log.dart';
import 'album_grouping.dart';
import 'database.dart';
import 'library_repository.dart';
import 'metadata/metadata_reader.dart';

const _coverArtBaseNames = ['cover', 'folder', 'album', 'front', 'albumart'];
const _coverArtExtensions = ['jpg', 'jpeg', 'png'];

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
enum _IndexOutcome { added, unchanged, removed, failed }

/// Indexes supported media files into the library — either by walking a
/// folder tree, or from an explicit list of individually-picked files.
/// Reads real tags (ID3/FLAC, see core/library/metadata/) where a reader
/// exists for the format; falls back to the filename for title otherwise,
/// same as before this feature existed.
class LibraryScanner {
  final LibraryRepository repository;

  LibraryScanner(this.repository);

  /// Indexes [path]. Normally skips files already in the library — pass
  /// [forceRescan] to re-parse and overwrite an existing entry instead (used
  /// by "Refresh Metadata" to pick up tags for tracks indexed before this
  /// feature existed, or before a given format had a reader).
  ///
  /// Never throws — one corrupt/unreadable file must not abort a whole
  /// batch scan or refresh; the outcome is reported instead (see
  /// [_IndexOutcome.failed]) rather than silently discarded.
  Future<_IndexOutcome> _indexFile(
    String path, {
    bool forceRescan = false,
  }) async {
    try {
      final alreadyIndexed = await repository.trackExists(path);
      if (alreadyIndexed && !forceRescan) return _IndexOutcome.unchanged;

      if (forceRescan && !await File(path).exists()) {
        await repository.deleteTrackByPath(path);
        return _IndexOutcome.removed;
      }

      final ext = p.extension(path).replaceFirst('.', '').toLowerCase();
      final metadata = await readTrackMetadata(path);
      final title = metadata.title ?? p.basenameWithoutExtension(path);
      final syncedLyrics = await _findLrcSidecar(path);

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
        ),
      );

      // Embedded art (ID3 APIC / FLAC PICTURE) takes priority; many FLAC
      // rips ship art as a plain cover.jpg/folder.jpg next to the audio
      // instead of embedding it, so that's the fallback.
      final artwork = metadata.artwork ?? await _findExternalArtwork(path);
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
        final synced = await _findLrcSidecar(path);
        final plain = (await readTrackMetadata(path)).lyrics;
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

  /// Reads `<same name>.lrc` next to [audioFilePath], if it exists — a
  /// straight sibling-file check, not a directory listing, since (unlike
  /// cover art) an LRC file's own name always matches the track it's for.
  /// Case-insensitive extension, since rippers/taggers disagree on `.lrc`
  /// vs `.LRC`. Returns the raw file content for [parseLrc] to read later,
  /// not pre-parsed — see Tracks.syncedLyrics.
  Future<String?> _findLrcSidecar(String audioFilePath) async {
    final base = p.withoutExtension(audioFilePath);
    for (final candidate in ['$base.lrc', '$base.LRC']) {
      try {
        final file = File(candidate);
        if (await file.exists()) {
          final content = await file.readAsString();
          if (content.trim().isNotEmpty) return content;
          return null;
        }
      } catch (_) {
        // Unreadable sidecar (permissions, bad encoding) — not fatal, the
        // track still gets indexed without synced lyrics.
      }
    }
    return null;
  }

  Future<Uint8List?> _findExternalArtwork(String audioFilePath) async {
    try {
      final dir = Directory(p.dirname(audioFilePath));
      if (!await dir.exists()) return null;

      await for (final entity in dir.list(followLinks: false)) {
        if (entity is! File) continue;
        final base = p.basenameWithoutExtension(entity.path).toLowerCase();
        final ext = p
            .extension(entity.path)
            .replaceFirst('.', '')
            .toLowerCase();
        if (_coverArtBaseNames.contains(base) &&
            _coverArtExtensions.contains(ext)) {
          final bytes = await entity.readAsBytes();
          if (bytes.isNotEmpty) return bytes;
        }
      }
    } catch (_) {
      // No cover file, or the directory couldn't be listed — not fatal.
    }
    return null;
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
    var batch = <String>[];

    Future<void> flushBatch() async {
      if (batch.isEmpty) return;
      await repository.db.transaction(() async {
        for (final path in batch) {
          // Checked per-file, not just once per batch: onProgress (where a
          // caller's cancellationToken.cancel() actually gets called) fires
          // from inside this same loop, and a batch can hold up to
          // _batchSize files — a between-batches-only check would let an
          // entire small scan finish before a cancellation requested during
          // its own progress callback ever took effect.
          if (cancellationToken?.isCancelled ?? false) {
            wasCancelled = true;
            return;
          }
          final outcome = await _indexFile(path, forceRescan: forceRescan);
          if (outcome == _IndexOutcome.added) added++;
          if (outcome == _IndexOutcome.failed) failedPaths.add(path);
          processed++;
          onProgress?.call(processed);
        }
      });
      batch = [];
    }

    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (wasCancelled || (cancellationToken?.isCancelled ?? false)) {
        wasCancelled = true;
        break;
      }
      if (entity is! File) continue;
      if (!isSupportedMediaFile(entity.path)) continue;
      // Duplicate handling: a symlink cycle or a case-insensitive filesystem
      // quirk could otherwise surface the same real path twice in one walk.
      if (!seenPaths.add(entity.path)) continue;

      allPaths.add(entity.path);
      batch.add(entity.path);
      if (batch.length >= _batchSize) await flushBatch();
    }
    if (!wasCancelled) await flushBatch();

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
      final batch = supported.skip(i).take(_batchSize);
      await repository.db.transaction(() async {
        for (final path in batch) {
          // See scanDirectory's flushBatch for why this is checked per-file.
          if (cancellationToken?.isCancelled ?? false) {
            wasCancelled = true;
            return;
          }
          final outcome = await _indexFile(path, forceRescan: forceRescan);
          if (outcome == _IndexOutcome.added) added++;
          if (outcome == _IndexOutcome.failed) failedPaths.add(path);
          processed++;
          onProgress?.call(processed);
        }
      });
    }

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
  Future<RefreshResult> refreshAllMetadata({
    ScanCancellationToken? cancellationToken,
    void Function(int processed, int total)? onProgress,
  }) async {
    final paths = await repository.getAllFilePaths();
    var removed = 0;
    var processed = 0;
    var wasCancelled = false;

    for (var i = 0; i < paths.length; i += _batchSize) {
      if (wasCancelled || (cancellationToken?.isCancelled ?? false)) {
        wasCancelled = true;
        break;
      }
      final batch = paths.skip(i).take(_batchSize);
      await repository.db.transaction(() async {
        for (final path in batch) {
          // See scanDirectory's flushBatch for why this is checked per-file.
          if (cancellationToken?.isCancelled ?? false) {
            wasCancelled = true;
            return;
          }
          final outcome = await _indexFile(path, forceRescan: true);
          if (outcome == _IndexOutcome.removed) removed++;
          processed++;
          onProgress?.call(processed, paths.length);
        }
      });
    }

    return RefreshResult(
      processed: processed,
      removed: removed,
      wasCancelled: wasCancelled,
    );
  }
}

class RefreshResult {
  final int processed;
  final int removed;
  final bool wasCancelled;

  const RefreshResult({
    required this.processed,
    required this.removed,
    this.wasCancelled = false,
  });
}
