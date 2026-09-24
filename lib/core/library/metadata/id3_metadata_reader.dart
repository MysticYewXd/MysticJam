import 'dart:io';
import 'dart:typed_data';

import 'package:dart_tags/dart_tags.dart';

import 'track_metadata.dart';
import 'track_number_parser.dart';
import 'year_parser.dart';

/// Reads ID3 tags (v1.1 and v2.x) from an MP3 file via package:dart_tags —
/// pure Dart, no native dependency. ID3v2 is preferred when both are present
/// since it's richer (full-length fields, embedded art); ID3v1 only fills
/// in whatever ID3v2 didn't provide.
Future<ParsedMetadata> readId3Metadata(String filePath) async {
  try {
    final bytes = await File(filePath).readAsBytes();
    final results = await TagProcessor().getTagsFromByteArray(
      Future.value(bytes),
    );

    String? title;
    String? artist;
    String? album;
    Uint8List? artwork;
    String? lyrics;
    String? genre;
    int? trackNumber;
    String? albumArtist;
    int? year;

    // getTagsFromByteArray runs id3v1 then id3v2 by default — reversed so
    // id3v2's richer values win via ??=, with id3v1 only filling gaps.
    for (final tag in results.reversed) {
      final t = tag.tags;
      title ??= _nonEmpty(t['title']);
      artist ??= _nonEmpty(t['artist']);
      album ??= _nonEmpty(t['album']);
      // ID3v1's genre is always a plain name from its fixed table; ID3v2's
      // TCON can be either plain text ("Rock", the modern convention) or
      // the legacy "(17)" / "(17)Rock" bracketed-number format some older
      // taggers still write. Only the trailing text (if any) is kept for
      // the legacy form — resolving a bare "(17)" to a genre name would
      // need ID3v1's genre table, which dart_tags doesn't expose publicly.
      genre ??= _normalizeGenre(t['genre']);
      trackNumber ??= parseLeadingTrackNumber(_nonEmpty(t['track']));
      // dart_tags exposes a handful of frames under short names ('year' for
      // TYER) and everything else under its raw 4-character frame id — so
      // album artist arrives as 'TPE2', and ID3v2.4's date frame as 'TDRC'
      // (TYER was dropped from 2.4), both verified against dart_tags'
      // frame-key mapping rather than assumed.
      albumArtist ??= _nonEmpty(t['TPE2']);
      year ??= parseLeadingYear(_nonEmpty(t['year']) ?? _nonEmpty(t['TDRC']));

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

    return ParsedMetadata(
      title: title,
      artist: artist,
      album: album,
      artwork: artwork,
      lyrics: lyrics,
      genre: genre,
      trackNumber: trackNumber,
      albumArtist: albumArtist,
      year: year,
    );
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

final _legacyGenreBracket = RegExp(r'^\((\d+)\)\s*');

String? _normalizeGenre(dynamic value) {
  final raw = _nonEmpty(value);
  if (raw == null) return null;
  final withoutBracket = raw.replaceFirst(_legacyGenreBracket, '').trim();
  // A bare "(17)" with nothing else strips down to empty — better to keep
  // the original bracketed form than to silently discard the only value
  // present, since we can't resolve the number to a name here.
  return withoutBracket.isEmpty ? raw : withoutBracket;
}
