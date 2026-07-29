import 'dart:io';

import 'package:path/path.dart' as p;

import '../audio/format_support.dart';
import 'database.dart';
import 'library_repository.dart';

/// Walks a folder tree and indexes every supported media file into the
/// library. Metadata is filename-derived for now — proper tag/art parsing
/// (ID3, FLAC tags, embedded art) is playback-polish work, not v1 scope.
class LibraryScanner {
  final LibraryRepository repository;

  LibraryScanner(this.repository);

  /// Returns the number of newly-added tracks.
  Future<int> scanDirectory(String directoryPath) async {
    final dir = Directory(directoryPath);
    if (!await dir.exists()) return 0;

    var added = 0;
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final path = entity.path;
      if (!isSupportedMediaFile(path)) continue;
      if (await repository.trackExists(path)) continue;

      final ext = p.extension(path).replaceFirst('.', '').toLowerCase();
      final title = p.basenameWithoutExtension(path);

      await repository.upsertTrack(TracksCompanion.insert(
        filePath: path,
        title: title,
        format: ext,
      ));
      added++;
    }
    return added;
  }
}
