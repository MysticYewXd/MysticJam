import 'dart:convert';
import 'dart:typed_data';

/// Parses a Vorbis comment block's payload — shared by FLAC (whose
/// metadata blocks use this format directly) and OGG/Opus (whose comment
/// header packet wraps the exact same structure after a format-specific
/// prefix). Lengths here are little-endian, unlike FLAC's own big-endian
/// block framing — a well-known quirk, since Vorbis comments were designed
/// independently of any particular container.
Map<String, String> parseVorbisComments(Uint8List data) {
  final result = <String, String>{};
  try {
    final bd = ByteData.sublistView(data);
    var offset = 0;

    final vendorLength = bd.getUint32(offset, Endian.little);
    offset += 4 + vendorLength;

    final commentCount = bd.getUint32(offset, Endian.little);
    offset += 4;

    for (var i = 0; i < commentCount && offset + 4 <= data.length; i++) {
      final commentLength = bd.getUint32(offset, Endian.little);
      offset += 4;
      if (offset + commentLength > data.length) break;

      final comment = utf8.decode(
        data.sublist(offset, offset + commentLength),
        allowMalformed: true,
      );
      offset += commentLength;

      final eq = comment.indexOf('=');
      if (eq <= 0) continue;
      result[comment.substring(0, eq).toUpperCase()] = comment.substring(
        eq + 1,
      );
    }
  } catch (_) {
    // Return whatever was parsed before the block turned out malformed.
  }
  return result;
}

/// Parses a FLAC-style PICTURE block payload — used directly for FLAC's own
/// PICTURE metadata block, and also for the (big-endian, base64-encoded)
/// `METADATA_BLOCK_PICTURE` Vorbis comment some OGG/Opus/FLAC taggers use
/// to embed art via the comment mechanism instead of a native picture block.
Uint8List? parseFlacPictureBlock(Uint8List data) {
  try {
    final bd = ByteData.sublistView(data);
    var offset =
        4; // picture type — not needed, always take the first picture found

    final mimeLength = bd.getUint32(offset, Endian.big);
    offset += 4 + mimeLength;

    final descLength = bd.getUint32(offset, Endian.big);
    offset += 4 + descLength;

    offset += 16; // width, height, color depth, colors used — 4 bytes each

    final dataLength = bd.getUint32(offset, Endian.big);
    offset += 4;

    if (offset + dataLength > data.length) return null;
    return Uint8List.sublistView(data, offset, offset + dataLength);
  } catch (_) {
    return null;
  }
}

/// Extracts embedded art from a Vorbis comment map's `METADATA_BLOCK_PICTURE`
/// field, if present — the base64-encoded FLAC-picture-block convention used
/// by OGG/Opus (which have no native picture block of their own) and some
/// FLAC taggers as an alternative to a real PICTURE metadata block.
Uint8List? extractPictureFromComments(Map<String, String> comments) {
  final encoded = comments['METADATA_BLOCK_PICTURE'];
  if (encoded == null) return null;
  try {
    return parseFlacPictureBlock(base64.decode(encoded));
  } catch (_) {
    return null;
  }
}
