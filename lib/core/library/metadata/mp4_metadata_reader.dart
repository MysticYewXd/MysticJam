import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'track_metadata.dart';
import 'year_parser.dart';

const _tagTitle = '©nam';
const _tagArtist = '©ART';
const _tagAlbum = '©alb';
const _tagCover = 'covr';
const _tagGenre = '©gen';
const _tagTrackNumber = 'trkn';
const _tagAlbumArtist = 'aART';
const _tagYear = '©day';

/// Reads iTunes-style metadata from an M4A/AAC file's MP4 atom tree — pure
/// Dart. MP4 is a tree of size-prefixed "atoms"/"boxes"; the tags live at
/// moov/udta/meta/ilst, each as a named child atom wrapping a nested `data`
/// atom holding the actual value.
///
/// Spec (informal but accurate): https://developer.apple.com/library/archive/documentation/QuickTime/QTFF/Metadata/Metadata.html
Future<ParsedMetadata> readMp4Metadata(String filePath) async {
  RandomAccessFile? raf;
  try {
    raf = await File(filePath).open();
    final fileLength = await raf.length();

    final moov = await _findTopLevelBox(raf, fileLength, 'moov');
    if (moov == null) return ParsedMetadata.empty;

    final udta = _findChildBox(moov, 'udta');
    if (udta == null) return ParsedMetadata.empty;

    final meta = _findChildBox(udta, 'meta');
    if (meta == null) return ParsedMetadata.empty;

    // Unlike most boxes, 'meta' has a 4-byte version/flags field before its
    // children (it's a "full box").
    final metaChildren = meta.length > 4
        ? Uint8List.sublistView(meta, 4)
        : meta;
    final ilst = _findChildBox(metaChildren, 'ilst');
    if (ilst == null) return ParsedMetadata.empty;

    return ParsedMetadata(
      title: _findIlstString(ilst, _tagTitle),
      artist: _findIlstString(ilst, _tagArtist),
      album: _findIlstString(ilst, _tagAlbum),
      artwork: _findIlstBytes(ilst, _tagCover),
      // ©gen is the modern free-text genre atom used by current taggers.
      // There's also a legacy binary 'gnre' atom (an index into the ID3v1
      // genre table) some older files use instead — not read here, since
      // supporting it would mean either embedding that table locally or
      // reaching into dart_tags' unexported internals (see the same
      // decision in id3_metadata_reader.dart's genre handling).
      genre: _findIlstString(ilst, _tagGenre),
      trackNumber: _findIlstTrackNumber(ilst),
      albumArtist: _findIlstString(ilst, _tagAlbumArtist),
      year: parseLeadingYear(_findIlstString(ilst, _tagYear)),
    );
  } catch (_) {
    // Malformed/unreadable file shouldn't block indexing — the scanner
    // falls back to the filename, same as any untagged file.
    return ParsedMetadata.empty;
  } finally {
    await raf?.close();
  }
}

/// Walks top-level boxes via file seeks (never reading the whole file into
/// memory — 'mdat', the actual audio data, can be gigabytes) until [type]
/// is found, then reads just that box's payload.
Future<Uint8List?> _findTopLevelBox(
  RandomAccessFile raf,
  int fileLength,
  String type,
) async {
  var pos = 0;
  await raf.setPosition(0);

  while (pos + 8 <= fileLength) {
    final header = await raf.read(8);
    if (header.length < 8) return null;

    var size = ByteData.sublistView(header).getUint32(0, Endian.big);
    final boxType = String.fromCharCodes(header.sublist(4, 8));
    var headerSize = 8;

    if (size == 1) {
      // 64-bit "largesize" extension.
      final ext = await raf.read(8);
      if (ext.length < 8) return null;
      size = ByteData.sublistView(ext).getUint64(0, Endian.big);
      headerSize = 16;
    }
    if (size < headerSize) return null;

    if (boxType == type) {
      final payloadSize = size - headerSize;
      final data = await raf.read(payloadSize);
      return data.length == payloadSize ? data : null;
    }

    pos += size;
    await raf.setPosition(pos);
  }
  return null;
}

/// Walks child boxes of an in-memory buffer (moov/udta/meta/ilst are all
/// small — unlike top-level boxes, safe to hold and scan in memory).
Uint8List? _findChildBox(Uint8List data, String type) {
  var offset = 0;
  while (offset + 8 <= data.length) {
    var size = ByteData.sublistView(
      data,
      offset,
      offset + 4,
    ).getUint32(0, Endian.big);
    final boxType = String.fromCharCodes(data.sublist(offset + 4, offset + 8));
    var headerSize = 8;

    if (size == 1) {
      if (offset + 16 > data.length) return null;
      size = ByteData.sublistView(
        data,
        offset + 8,
        offset + 16,
      ).getUint64(0, Endian.big);
      headerSize = 16;
    }
    if (size < headerSize || offset + size > data.length) return null;

    if (boxType == type) {
      return Uint8List.sublistView(data, offset + headerSize, offset + size);
    }
    offset += size;
  }
  return null;
}

Uint8List? _findIlstValue(Uint8List ilst, String tag) {
  final tagBox = _findChildBox(ilst, tag);
  if (tagBox == null) return null;
  final dataBox = _findChildBox(tagBox, 'data');
  // 'data' atom: 4-byte type indicator + 4-byte locale, then the value.
  if (dataBox == null || dataBox.length <= 8) return null;
  return Uint8List.sublistView(dataBox, 8);
}

String? _findIlstString(Uint8List ilst, String tag) {
  final bytes = _findIlstValue(ilst, tag);
  if (bytes == null || bytes.isEmpty) return null;
  final value = utf8.decode(bytes, allowMalformed: true).trim();
  return value.isEmpty ? null : value;
}

Uint8List? _findIlstBytes(Uint8List ilst, String tag) {
  final bytes = _findIlstValue(ilst, tag);
  return (bytes == null || bytes.isEmpty) ? null : bytes;
}

/// trkn's data payload is binary, not text: 2 reserved bytes, a 16-bit
/// big-endian track number, a 16-bit big-endian total-track count, then 2
/// more reserved bytes (8 bytes total in the common case — some encoders
/// omit the trailing reserved pair, so only the first 4 are required here).
int? _findIlstTrackNumber(Uint8List ilst) {
  final bytes = _findIlstValue(ilst, _tagTrackNumber);
  if (bytes == null || bytes.length < 4) return null;
  final trackNumber = ByteData.sublistView(
    bytes,
    2,
    4,
  ).getUint16(0, Endian.big);
  return trackNumber == 0 ? null : trackNumber;
}
