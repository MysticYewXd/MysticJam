import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'track_metadata.dart';
import 'track_number_parser.dart';
import 'year_parser.dart';

const _apeTagPreamble = 'APETAGEX';
const _apeFooterSize = 32;

/// Reads an APEv2 tag — used by Monkey's Audio (.ape) and sometimes tacked
/// onto MP3/WV files too. Unlike ID3v2 (header-first) or Vorbis comments
/// (embedded in the stream), APEv2 tags live in a footer at the very end of
/// the file: a 32-byte footer identifies the tag and gives its total size,
/// which is how far back from EOF to seek to find the first item. Items are
/// then read forward from there. No binary/picture item support — cover art
/// in APEv2 is rare enough (a "Cover Art (Front)" binary item) not to be
/// worth the extra parsing for v1 of this reader.
Future<ParsedMetadata> readApeMetadata(String filePath) async {
  try {
    final file = File(filePath);
    final length = await file.length();
    if (length < _apeFooterSize) return ParsedMetadata.empty;

    final raf = await file.open();
    try {
      await raf.setPosition(length - _apeFooterSize);
      final footer = await raf.read(_apeFooterSize);
      final preamble = ascii.decode(footer.sublist(0, 8), allowInvalid: true);
      if (preamble != _apeTagPreamble) return ParsedMetadata.empty;

      final footerBd = ByteData.sublistView(footer);
      // Footer layout: 8-byte preamble, 4-byte version, 4-byte tag size
      // (everything after the header, including this footer, but NOT
      // including a possible 32-byte header at the tag's start), 4-byte
      // item count, 4-byte flags, 8 reserved bytes.
      final tagSize = footerBd.getUint32(8, Endian.little);
      final itemCount = footerBd.getUint32(12, Endian.little);

      final tagStart = length - tagSize;
      if (tagStart < 0) return ParsedMetadata.empty;
      await raf.setPosition(tagStart);
      final itemsLength = tagSize - _apeFooterSize;
      if (itemsLength <= 0) return ParsedMetadata.empty;
      final itemsBytes = await raf.read(itemsLength);

      final tags = _parseItems(itemsBytes, itemCount);
      return ParsedMetadata(
        title: _nonEmpty(tags['TITLE']),
        artist: _nonEmpty(tags['ARTIST']),
        album: _nonEmpty(tags['ALBUM']),
        genre: _nonEmpty(tags['GENRE']),
        trackNumber: parseLeadingTrackNumber(tags['TRACK']),
        albumArtist: _nonEmpty(tags['ALBUM ARTIST'] ?? tags['ALBUMARTIST']),
        year: parseLeadingYear(tags['YEAR']),
      );
    } finally {
      await raf.close();
    }
  } catch (_) {
    return ParsedMetadata.empty;
  }
}

Map<String, String> _parseItems(Uint8List data, int itemCount) {
  final result = <String, String>{};
  final bd = ByteData.sublistView(data);
  var offset = 0;

  for (var i = 0; i < itemCount && offset + 8 <= data.length; i++) {
    final valueLength = bd.getUint32(offset, Endian.little);
    final flags = bd.getUint32(offset + 4, Endian.little);
    offset += 8;

    final keyEnd = data.indexOf(0x00, offset);
    if (keyEnd == -1) break;
    final key = ascii
        .decode(data.sublist(offset, keyEnd), allowInvalid: true)
        .toUpperCase();
    offset = keyEnd + 1;

    if (offset + valueLength > data.length) break;
    // Item type is flags bits 1-2; 0 = UTF-8 text, which is all this reader
    // cares about — binary/locator items (cover art, external links) are
    // skipped since their "value" isn't text.
    final itemType = (flags >> 1) & 0x3;
    if (itemType == 0) {
      result[key] = utf8.decode(
        data.sublist(offset, offset + valueLength),
        allowMalformed: true,
      );
    }
    offset += valueLength;
  }
  return result;
}

String? _nonEmpty(String? value) {
  if (value == null) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
