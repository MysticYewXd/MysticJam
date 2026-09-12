import 'dart:io';
import 'dart:typed_data';

import 'package:dart_tags/dart_tags.dart';

import 'track_metadata.dart';

/// Reads ID3 tags (v1.1 and v2.x) from an MP3 file via package:dart_tags —
/// pure Dart, no native dependency. ID3v2 is preferred when both are present
/// since it's richer (full-length fields, embedded art); ID3v1 only fills
/// in whatever ID3v2 didn't provide.
Future<ParsedMetadata> readId3Metadata(String filePath) async {
  try {
    final bytes = await File(filePath).readAsBytes();
    final results = await TagProcessor().getTagsFromByteArray(Future.value(bytes));

    String? title;
    String? artist;
    String? album;
    Uint8List? artwork;
    String? lyrics;

    // getTagsFromByteArray runs id3v1 then id3v2 by default — reversed so
    // id3v2's richer values win via ??=, with id3v1 only filling gaps.
    for (final tag in results.reversed) {
      final t = tag.tags;
      title ??= _nonEmpty(t['title']);
      artist ??= _nonEmpty(t['artist']);
      album ??= _nonEmpty(t['album']);

      if (artwork == null) {
        final pictures = t['picture'];
        if (pictures is Map && pictures.isNotEmpty) {
          final pic = pictures.values.first;
          if (pic is AttachedPicture && pic.imageData.isNotEmpty) {
            artwork = Uint8List.fromList(pic.imageData);
          }
        }
      }

      if (lyrics == null) {
        final lyricsMap = t['lyrics'];
        if (lyricsMap is Map && lyricsMap.isNotEmpty) {
          final entry = lyricsMap.values.first;
          if (entry is UnSyncLyric) {
            lyrics = _nonEmpty(entry.lyrics);
          }
        }
      }
    }

    return ParsedMetadata(title: title, artist: artist, album: album, artwork: artwork, lyrics: lyrics);
  } catch (_) {
    // Corrupt/unreadable tags shouldn't block indexing — the scanner falls
    // back to the filename, same as any untagged file.
    return ParsedMetadata.empty;
  }
}

String? _nonEmpty(dynamic value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
