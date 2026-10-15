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
import 'metadata/track_metadata.dart';

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

/// How many files are read from disk at once inside a batch. Tag reading is
/// almost all waiting on I/O, so overlapping a handful of reads keeps the
/// disk busy instead of reading one file, parsing it, writing it, and only
/// then starting the next. Database writes stay strictly one at a time.
const _readConcurrency = 8;

/// Everything read from disk for one file, gathered before any database
/// write so the reads for several files can run concurrently.
class _FileRead {
  final ParsedMetadata metadata;
  final String? syncedLyrics;
  final Uint8List? externalArtwork;
  const _FileRead(this.metadata, this.syncedLyrics, this.externalArtwork);

  /// Marker for a file whose read threw (see [LibraryScanner._writeFile]).
  /// Non-const on purpose, so the two markers are distinct instances.
  static final failed = _FileRead(ParsedMetadata.empty, null, null);

  /// Marker for a file a forced re-scan found missing from disk.
  static final gone = _FileRead(ParsedMetadata.empty, null, null);
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

/// Drops duplicates and any folder that sits inside another folder in
/// [folders], so each part of the disk is walked once.
List<String> outermostFolders(Iterable<String> folders) {
  final unique = folders.map(p.normalize).toSet().toList();
  return [
    for (final f in unique)
      if (!unique.any((other) => other != f && p.isWithin(other, f))) f,
  ];
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

  /// Folder-art lookups for the current scan, keyed by directory. Holding
  /// the Future (not the bytes) means concurrent reads of tracks in the
  /// same album share one directory listing. Cleared between batches so a
  /// large library doesn't keep every album's cover in memory.
  final _folderArtCache = <String, Future<Uint8List?>>{};

  /// Cached album_art directory, resolved once instead of once per track.
  Future<String?>? _artDirPath;

  /// Reads [paths] in chunks of [_readConcurrency] and indexes each one in
  /// order, calling [onIndexed] after every file. Must run inside a
  /// transaction (see [_batchSize]). [known] holds every path already in
  /// the library, loaded once per scan rather than queried per file.
  /// Returns false if [cancellationToken] stopped it partway.
  Future<bool> _indexBatch(
    List<String> paths, {
    required Set<String> known,
    required bool forceRescan,
    ScanCancellationToken? cancellationToken,
    required void Function(String path, _IndexOutcome outcome) onIndexed,
  }) async {
    try {
      for (var i = 0; i < paths.length; i += _readConcurrency) {
        // Checked per chunk and per file, not just once per batch: onIndexed
        // (where a caller's cancellationToken.cancel() actually gets called)
        // fires from inside this same loop, and a batch can hold up to
        // _batchSize files — a between-batches-only check would let an
        // entire small scan finish before a cancellation requested during
        // its own progress callback ever took effect.
        if (cancellationToken?.isCancelled ?? false) return false;
        final chunk = paths.skip(i).take(_readConcurrency).toList();
        final reads = await Future.wait([
          for (final path in chunk)
            _readFile(
              path,
              known: known,
              forceRescan: forceRescan,
            ).then<_FileRead?>(
              (read) => read,
              onError: (Object _) => _FileRead.failed,
            ),
        ]);
        for (var j = 0; j < chunk.length; j++) {
          if (cancellationToken?.isCancelled ?? false) return false;
          final path = chunk[j];
          final outcome = await _writeFile(
            path,
            reads[j],
            alreadyIndexed: known.contains(path),
          );
          if (outcome == _IndexOutcome.added) known.add(path);
          if (outcome == _IndexOutcome.removed) known.remove(path);
          onIndexed(path, outcome);
        }
      }
      return true;
    } finally {
      _folderArtCache.clear();
    }
  }

  /// The disk-reading half of indexing [path]. Returns null when the file
  /// is already indexed and this isn't a forced re-scan, and
  /// [_FileRead.gone] when a forced re-scan finds it missing. A read that
  /// throws is mapped to [_FileRead.failed] by [_indexBatch].
  Future<_FileRead?> _readFile(
    String path, {
    required Set<String> known,
    required bool forceRescan,
  }) async {
    if (known.contains(path) && !forceRescan) return null;
    if (forceRescan && !await File(path).exists()) return _FileRead.gone;

    final reads = await Future.wait<Object?>([
      readTrackMetadata(path),
      _findLrcSidecar(path),
    ]);
    final metadata = reads[0] as ParsedMetadata;
    // Embedded art (ID3 APIC / FLAC PICTURE) takes priority; many FLAC
    // rips ship art as a plain cover.jpg/folder.jpg next to the audio
    // instead of embedding it, so that's the fallback.
    final externalArt = metadata.artwork == null
        ? await _folderArtCache.putIfAbsent(
            p.dirname(path),
            () => _findExternalArtwork(path),
          )
        : null;
    return _FileRead(metadata, reads[1] as String?, externalArt);
  }

  /// The database half of indexing [path]. Normally skips files already in
  /// the library — on a forced re-scan (used by "Refresh Metadata" to pick
  /// up tags for tracks indexed before this feature existed, or before a
  /// given format had a reader) it overwrites the existing entry instead,
  /// or removes it when the file is gone.
  ///
  /// Never throws — one corrupt/unreadable file must not abort a whole
  /// batch scan or refresh; the outcome is reported instead (see
  /// [_IndexOutcome.failed]) rather than silently discarded.
  Future<_IndexOutcome> _writeFile(
    String path,
    _FileRead? read, {
    required bool alreadyIndexed,
  }) async {
    if (read == null) return _IndexOutcome.unchanged;
    if (identical(read, _FileRead.failed)) return _IndexOutcome.failed;
    try {
      if (identical(read, _FileRead.gone)) {
        await repository.deleteTrackByPath(path);
        return _IndexOutcome.removed;
      }

      final metadata = read.metadata;
      final ext = p.extension(path).replaceFirst('.', '').toLowerCase();
      final title = metadata.title ?? p.basenameWithoutExtension(path);
      final syncedLyrics = read.syncedLyrics;

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

      final artwork = metadata.artwork ?? read.externalArtwork;
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
    for (var i = 0; i < paths.length; i += _readConcurrency) {
      final chunk = paths.skip(i).take(_readConcurrency).toList();
      final results = await Future.wait([
        for (final path in chunk) _readLyrics(path),
      ]);
      for (var j = 0; j < chunk.length; j++) {
        final r = results[j];
        if (r != null) found[chunk[j]] = r;
      }
      onProgress?.call(i + chunk.length, paths.length);
    }
    await repository.setLyricsForPaths(found);
    AppLog.info('scan', 'lyrics rescan finished', {
      'checked': paths.length,
      'found': found.length,
    });
    return found.length;
  }

  Future<({String? plain, String? synced})?> _readLyrics(String path) async {
    if (!await File(path).exists()) return null;
    final synced = await _findLrcSidecar(path);
    final plain = (await readTrackMetadata(path)).lyrics;
    if (synced == null && plain == null) return null;
    return (plain: plain, synced: synced);
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

  Future<String?> _resolveArtDir() async {
    try {
      final supportDir = await getApplicationSupportDirectory();
      final artDir = Directory(p.join(supportDir.path, 'album_art'));
      await artDir.create(recursive: true);
      return artDir.path;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _saveArtwork(int trackId, Uint8List bytes) async {
    try {
      var dirPath = await (_artDirPath ??= _resolveArtDir());
      if (dirPath == null || !Directory(dirPath).existsSync()) {
        // First attempt failed, or the folder was deleted mid-session —
        // try again rather than losing art for the rest of the session.
        dirPath = await (_artDirPath = _resolveArtDir());
        if (dirPath == null) return null;
      }
      final file = File(p.join(dirPath, '$trackId.art'));
      await file.writeAsBytes(bytes);
      return file.path;
    } catch (_) {
      // Missing art is a cosmetic loss, not worth failing the whole scan over.
      return null;
    }
  }

  /// Looks for songs not yet in the library inside every folder the user has
  /// added before (AppSettingsState.importedFolders) — this is what makes
  /// "rescan" pick up albums copied into an existing music folder since it was
  /// first added. Known files are skipped, so it's cheap to run repeatedly.
  /// A folder nested inside another listed one is skipped (scanning the outer
  /// one already covers it), and folders that no longer exist (an unplugged
  /// drive) are ignored rather than treated as an error.
  Future<ScanResult> scanFolders(
    Iterable<String> folders, {
    ScanCancellationToken? cancellationToken,
    void Function(int processed)? onProgress,
  }) async {
    final roots = outermostFolders(folders);
    final allPaths = <String>[];
    final failedPaths = <String>[];
    var added = 0;
    var wasCancelled = false;

    for (final root in roots) {
      if (cancellationToken?.isCancelled ?? false) {
        wasCancelled = true;
        break;
      }
      final result = await scanDirectory(
        root,
        cancellationToken: cancellationToken,
        onProgress: onProgress,
      );
      allPaths.addAll(result.allPaths);
      failedPaths.addAll(result.failedPaths);
      added += result.addedCount;
      if (result.wasCancelled) {
        wasCancelled = true;
        break;
      }
    }
    return ScanResult(
      allPaths,
      added,
      failedPaths: failedPaths,
      wasCancelled: wasCancelled,
    );
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

    final known = (await repository.getAllFilePaths()).toSet();

    Future<void> flushBatch() async {
      if (batch.isEmpty) return;
      await repository.db.transaction(() async {
        final finished = await _indexBatch(
          batch,
          known: known,
          forceRescan: forceRescan,
          cancellationToken: cancellationToken,
          onIndexed: (path, outcome) {
            if (outcome == _IndexOutcome.added) added++;
            if (outcome == _IndexOutcome.failed) failedPaths.add(path);
            processed++;
            onProgress?.call(processed);
          },
        );
        if (!finished) wasCancelled = true;
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

    final known = supported.isEmpty
        ? <String>{}
        : (await repository.getAllFilePaths()).toSet();

    for (var i = 0; i < supported.length; i += _batchSize) {
      if (wasCancelled || (cancellationToken?.isCancelled ?? false)) {
        wasCancelled = true;
        break;
      }
      final batch = supported.skip(i).take(_batchSize).toList();
      await repository.db.transaction(() async {
        final finished = await _indexBatch(
          batch,
          known: known,
          forceRescan: forceRescan,
          cancellationToken: cancellationToken,
          onIndexed: (path, outcome) {
            if (outcome == _IndexOutcome.added) added++;
            if (outcome == _IndexOutcome.failed) failedPaths.add(path);
            processed++;
            onProgress?.call(processed);
          },
        );
        if (!finished) wasCancelled = true;
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

    final known = paths.toSet();

    for (var i = 0; i < paths.length; i += _batchSize) {
      if (wasCancelled || (cancellationToken?.isCancelled ?? false)) {
        wasCancelled = true;
        break;
      }
      final batch = paths.skip(i).take(_batchSize).toList();
      await repository.db.transaction(() async {
        final finished = await _indexBatch(
          batch,
          known: known,
          forceRescan: true,
          cancellationToken: cancellationToken,
          onIndexed: (path, outcome) {
            if (outcome == _IndexOutcome.removed) removed++;
            processed++;
            onProgress?.call(processed, paths.length);
          },
        );
        if (!finished) wasCancelled = true;
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
