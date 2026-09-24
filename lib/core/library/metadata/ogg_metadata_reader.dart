import 'dart:io';
import 'dart:typed_data';

import 'track_metadata.dart';
import 'track_number_parser.dart';
import 'vorbis_comment_parser.dart';
import 'year_parser.dart';

/// Reads Vorbis-comment metadata and cover art from an OGG-container file
/// (Vorbis or Opus audio) — pure Dart. OGG wraps its packets in a page
/// framing that has to be demuxed first; the comment packet inside carries
/// the exact same Vorbis-comment structure FLAC uses, just prefixed with a
/// short format-specific header ("vorbis" or "OpusTags").
///
/// Spec: https://xiph.org/ogg/doc/framing.html
Future<ParsedMetadata> readOggMetadata(String filePath) async {
  RandomAccessFile? raf;
  try {
    raf = await File(filePath).open();

    // The comment packet is always in one of the first couple of pages
    // (right after the identification header) — no need to read further.
    for (var pageIndex = 0; pageIndex < 6; pageIndex++) {
      final page = await _readOggPage(raf);
      if (page == null) break;

      Uint8List? commentPayload;
      if (page.length > 7 &&
          page[0] == 0x03 &&
          String.fromCharCodes(page.sublist(1, 7)) == 'vorbis') {
        commentPayload = Uint8List.sublistView(page, 7);
      } else if (page.length > 8 &&
          String.fromCharCodes(page.sublist(0, 8)) == 'OpusTags') {
        commentPayload = Uint8List.sublistView(page, 8);
      }

      if (commentPayload != null) {
        final comments = parseVorbisComments(commentPayload);
        return ParsedMetadata(
          title: comments['TITLE'],
          artist: comments['ARTIST'],
          album: comments['ALBUM'],
          artwork: extractPictureFromComments(comments),
          genre: comments['GENRE'],
          trackNumber: parseLeadingTrackNumber(comments['TRACKNUMBER']),
          albumArtist: comments['ALBUMARTIST'] ?? comments['ALBUM ARTIST'],
          year: parseLeadingYear(comments['DATE'] ?? comments['YEAR']),
        );
      }
    }
    return ParsedMetadata.empty;
  } catch (_) {
    // Malformed/unreadable file shouldn't block indexing — the scanner
    // falls back to the filename, same as any untagged file.
    return ParsedMetadata.empty;
  } finally {
    await raf?.close();
  }
}

/// Reads one Ogg page and returns its payload (the concatenation of all
/// segments listed in the page's segment table). Returns null at EOF or on
/// a malformed page.
Future<Uint8List?> _readOggPage(RandomAccessFile raf) async {
  // Fixed portion of the page header, up to and including the segment count.
  final fixedHeader = await raf.read(27);
  if (fixedHeader.length < 27) return null;
  if (String.fromCharCodes(fixedHeader.sublist(0, 4)) != 'OggS') return null;

  final pageSegments = fixedHeader[26];
  final segmentTable = await raf.read(pageSegments);
  if (segmentTable.length < pageSegments) return null;

  final dataLength = segmentTable.fold<int>(0, (sum, b) => sum + b);
  final data = await raf.read(dataLength);
  if (data.length < dataLength) return null;

  return data;
}
