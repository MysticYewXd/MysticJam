import 'dart:io';
import 'dart:typed_data';

import 'track_metadata.dart';
import 'track_number_parser.dart';
import 'year_parser.dart';

// ASF object GUIDs, in the mixed-endian byte order the format actually
// stores them in (first 3 fields little-endian, last 8 bytes as-is) rather
// than the usual big-endian display order a GUID string is written in.
final _headerObjectGuid = Uint8List.fromList([
  0x30,
  0x26,
  0xB2,
  0x75,
  0x8E,
  0x66,
  0xCF,
  0x11,
  0xA6,
  0xD9,
  0x00,
  0xAA,
  0x00,
  0x62,
  0xCE,
  0x6C,
]);
final _contentDescriptionGuid = Uint8List.fromList([
  0x33,
  0x26,
  0xB2,
  0x75,
  0x8E,
  0x66,
  0xCF,
  0x11,
  0xA6,
  0xD9,
  0x00,
  0xAA,
  0x00,
  0x62,
  0xCE,
  0x6C,
]);
final _extendedContentDescriptionGuid = Uint8List.fromList([
  0x40,
  0xA4,
  0xD0,
  0xD2,
  0x07,
  0xE3,
  0xD2,
  0x11,
  0x97,
  0xF0,
  0x00,
  0xA0,
  0xC9,
  0x5E,
  0xA8,
  0x50,
]);

bool _guidEquals(Uint8List a, Uint8List b) {
  for (var i = 0; i < 16; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Reads title/artist/album from a WMA file's ASF header — the two objects
/// that matter are the Content Description Object (title/author/copyright,
/// each a simple length-prefixed field) and the Extended Content
/// Description Object (arbitrary WM/* name-value pairs, which is where
/// WM/AlbumTitle lives). Embedded art (WM/Picture, a binary extended
/// content descriptor) isn't extracted — ASF's mixed-endian GUIDs and
/// nested object walking are already the most complex reader in this app;
/// art is left as a possible future addition rather than adding to that.
Future<ParsedMetadata> readWmaMetadata(String filePath) async {
  try {
    final file = File(filePath);
    final length = await file.length();
    if (length < 30) return ParsedMetadata.empty;

    final raf = await file.open();
    try {
      final preamble = await raf.read(30);
      if (!_guidEquals(
        Uint8List.sublistView(preamble, 0, 16),
        _headerObjectGuid,
      )) {
        return ParsedMetadata.empty;
      }
      final preambleBd = ByteData.sublistView(preamble);
      final headerObjectCount = preambleBd.getUint32(24, Endian.little);

      var pos = 30;
      String? title;
      String? artist;
      String? album;
      String? genre;
      int? trackNumber;
      String? albumArtist;
      int? year;

      for (var i = 0; i < headerObjectCount && pos + 24 <= length; i++) {
        await raf.setPosition(pos);
        final objHeader = await raf.read(24);
        final guid = Uint8List.sublistView(objHeader, 0, 16);
        final objSize = ByteData.sublistView(
          objHeader,
        ).getUint64(16, Endian.little);
        final dataSize = objSize - 24;
        if (dataSize < 0 || pos + objSize > length) break;

        if (_guidEquals(guid, _contentDescriptionGuid)) {
          final data = await raf.read(dataSize);
          final fields = _parseContentDescription(data);
          title ??= fields.$1;
          artist ??= fields.$2;
        } else if (_guidEquals(guid, _extendedContentDescriptionGuid)) {
          final data = await raf.read(dataSize);
          final tags = _parseExtendedContentDescription(data);
          album ??= _nonEmpty(tags['WM/ALBUMTITLE']);
          genre ??= _nonEmpty(tags['WM/GENRE']);
          // WM/TrackNumber is sometimes written as a DWORD instead of a
          // string depending on the tagging tool — _parseExtendedContentDescription
          // only captures string-typed (type 0) descriptors (see its doc
          // comment), so a DWORD-typed track number isn't picked up here.
          // Documented limitation, not a bug: this reader is already the
          // most scoped-down of the eight formats supported.
          trackNumber ??= parseLeadingTrackNumber(tags['WM/TRACKNUMBER']);
          albumArtist ??= _nonEmpty(tags['WM/ALBUMARTIST']);
          year ??= parseLeadingYear(tags['WM/YEAR']);
        }

        pos += objSize;
      }

      return ParsedMetadata(
        title: title,
        artist: artist,
        album: album,
        genre: genre,
        trackNumber: trackNumber,
        albumArtist: albumArtist,
        year: year,
      );
    } finally {
      await raf.close();
    }
  } catch (_) {
    return ParsedMetadata.empty;
  }
}

/// Content Description Object: five UTF-16LE fields (title, author,
/// copyright, description, rating), each preceded by its own 2-byte
/// length — read sequentially since there's no per-field offset table.
/// Only title and author (artist) are used here.
(String?, String?) _parseContentDescription(Uint8List data) {
  try {
    final bd = ByteData.sublistView(data);
    final titleLen = bd.getUint16(0, Endian.little);
    final authorLen = bd.getUint16(2, Endian.little);
    var offset = 10; // past the five 2-byte length fields
    final title = _decodeUtf16Le(data, offset, titleLen);
    offset += titleLen;
    final author = _decodeUtf16Le(data, offset, authorLen);
    return (_nonEmpty(title), _nonEmpty(author));
  } catch (_) {
    return (null, null);
  }
}

/// Extended Content Description Object: a count, then that many
/// (name, type, value) descriptors — name and (for type 0) value are
/// UTF-16LE; non-string types (byte array/bool/dword/qword/word) are
/// skipped since this reader only cares about text fields like
/// WM/AlbumTitle.
Map<String, String> _parseExtendedContentDescription(Uint8List data) {
  final result = <String, String>{};
  try {
    final bd = ByteData.sublistView(data);
    final count = bd.getUint16(0, Endian.little);
    var offset = 2;

    for (var i = 0; i < count && offset + 2 <= data.length; i++) {
      final nameLen = bd.getUint16(offset, Endian.little);
      offset += 2;
      if (offset + nameLen > data.length) break;
      final name = (_decodeUtf16Le(data, offset, nameLen) ?? '').toUpperCase();
      offset += nameLen;

      if (offset + 4 > data.length) break;
      final valueType = bd.getUint16(offset, Endian.little);
      final valueLen = bd.getUint16(offset + 2, Endian.little);
      offset += 4;
      if (offset + valueLen > data.length) break;

      if (valueType == 0) {
        final value = _decodeUtf16Le(data, offset, valueLen);
        if (value != null && name.isNotEmpty) result[name] = value;
      }
      offset += valueLen;
    }
  } catch (_) {
    // Return whatever was parsed before the block turned out malformed.
  }
  return result;
}

String? _decodeUtf16Le(Uint8List data, int offset, int byteLength) {
  if (byteLength <= 0 || offset + byteLength > data.length) return null;
  final units = <int>[];
  for (var i = offset; i + 1 < offset + byteLength; i += 2) {
    units.add(data[i] | (data[i + 1] << 8));
  }
  // ASF strings are null-terminated within their declared length - trim the
  // trailing NUL (and anything after it, defensively) rather than decoding
  // it as a literal character.
  final nullIndex = units.indexOf(0);
  final trimmed = nullIndex == -1 ? units : units.sublist(0, nullIndex);
  return String.fromCharCodes(trimmed);
}

String? _nonEmpty(String? value) {
  if (value == null) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
