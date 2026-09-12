import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../audio/format_support.dart';
import 'database.dart';
import 'library_repository.dart';
import 'metadata/metadata_reader.dart';

const _coverArtBaseNames = ['cover', 'folder', 'album', 'front', 'albumart'];
const _coverArtExtensions = ['jpg', 'jpeg', 'png'];

/// Result of a scan: every supported file matched (whether newly indexed or
/// already present in the library) plus how many were actually new. Callers
/// that need to act on the exact files involved (e.g. adding them straight
/// into a playlist) use [allPaths]; callers that just need a status message
/// use [addedCount].
class ScanResult {
  final List<String> allPaths;
  final int addedCount;

  const ScanResult(this.allPaths, this.addedCount);
}

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
  /// batch scan or refresh; it's simply left as-is (or, when [forceRescan]
  /// and the file no longer exists on disk at all, removed from the
  /// library — a dead entry can never play regardless of its metadata).
  ///
  /// Returns whether the file was newly added (always false when
  /// [forceRescan] updates or removes an existing row).
  Future<bool> _indexFile(String path, {bool forceRescan = false}) async {
    try {
      final alreadyIndexed = await repository.trackExists(path);
      if (alreadyIndexed && !forceRescan) return false;

      if (forceRescan && !await File(path).exists()) {
        await repository.deleteTrackByPath(path);
        return false;
      }

      final ext = p.extension(path).replaceFirst('.', '').toLowerCase();
      final metadata = await readTrackMetadata(path);
      final title = metadata.title ?? p.basenameWithoutExtension(path);

      final id = await repository.upsertTrack(TracksCompanion.insert(
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
        durationMs: metadata.durationMs != null ? Value(metadata.durationMs) : const Value.absent(),
        lyrics: metadata.lyrics != null ? Value(metadata.lyrics) : const Value.absent(),
      ));

      // Embedded art (ID3 APIC / FLAC PICTURE) takes priority; many FLAC
      // rips ship art as a plain cover.jpg/folder.jpg next to the audio
      // instead of embedding it, so that's the fallback.
      final artwork = metadata.artwork ?? await _findExternalArtwork(path);
      if (artwork != null) {
        final artPath = await _saveArtwork(id, artwork);
        if (artPath != null) {
          await repository.setAlbumArtPath(id, artPath);
        }
      }

      return !alreadyIndexed;
    } catch (_) {
      return false;
    }
  }

  Future<Uint8List?> _findExternalArtwork(String audioFilePath) async {
    try {
      final dir = Directory(p.dirname(audioFilePath));
      if (!await dir.exists()) return null;

      await for (final entity in dir.list(followLinks: false)) {
        if (entity is! File) continue;
        final base = p.basenameWithoutExtension(entity.path).toLowerCase();
        final ext = p.extension(entity.path).replaceFirst('.', '').toLowerCase();
        if (_coverArtBaseNames.contains(base) && _coverArtExtensions.contains(ext)) {
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

  Future<ScanResult> scanDirectory(String directoryPath, {bool forceRescan = false}) async {
    final dir = Directory(directoryPath);
    if (!await dir.exists()) return const ScanResult([], 0);

    final allPaths = <String>[];
    var added = 0;
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      if (!isSupportedMediaFile(entity.path)) continue;
      allPaths.add(entity.path);
      if (await _indexFile(entity.path, forceRescan: forceRescan)) added++;
    }
    return ScanResult(allPaths, added);
  }

  /// Indexes an explicit list of individually-picked files (as opposed to
  /// walking a whole folder).
  Future<ScanResult> scanFiles(List<String> filePaths, {bool forceRescan = false}) async {
    final supported = filePaths.where(isSupportedMediaFile).toList();
    var added = 0;
    for (final path in supported) {
      if (await _indexFile(path, forceRescan: forceRescan)) added++;
    }
    return ScanResult(supported, added);
  }

  /// Re-parses every already-indexed file's metadata and overwrites the
  /// stored title/artist/album/art — for picking up real tags on tracks
  /// that were scanned before this feature existed (or before a format had
  /// a reader), and for repairing tracks left stale by any past bug,
  /// without the user ever having to delete and re-add them by hand.
  /// Tracks whose file no longer exists on disk are removed outright.
  Future<RefreshResult> refreshAllMetadata() async {
    final paths = await repository.getAllFilePaths();
    var removed = 0;
    for (final path in paths) {
      if (!await File(path).exists()) {
        await repository.deleteTrackByPath(path);
        removed++;
        continue;
      }
      await _indexFile(path, forceRescan: true);
    }
    return RefreshResult(processed: paths.length, removed: removed);
  }
}

class RefreshResult {
  final int processed;
  final int removed;

  const RefreshResult({required this.processed, required this.removed});
}
