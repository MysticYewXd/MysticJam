import 'dart:convert';
import 'dart:typed_data';

/// Builds a minimal but structurally valid FLAC file holding just the given
/// Vorbis comments ("KEY=value" strings) — a STREAMINFO block followed by a
/// last VORBIS_COMMENT block, no audio frames. Enough for
/// readFlacMetadata()/the scanner to read real tags from a real file on
/// disk, which untagged garbage bytes can't exercise.
///
/// Framing per the FLAC spec: each metadata block is a 1-byte header (last-
/// block flag in the top bit, block type in the low 7) plus a 3-byte
/// big-endian length; the Vorbis comment block's own inner lengths are
/// little-endian.
Uint8List buildFlac(List<String> comments) {
  final out = BytesBuilder();
  out.add(ascii.encode('fLaC'));

  // STREAMINFO (type 0, not last), 34 bytes. Zeroed: sample rate 0 makes the
  // reader report no duration, which is fine for tag tests.
  out.add([0x00, 0x00, 0x00, 0x22]);
  out.add(Uint8List(34));

  final body = BytesBuilder();
  void addLe32(int v) => body.add(
    (ByteData(4)..setUint32(0, v, Endian.little)).buffer.asUint8List(),
  );
  final vendor = utf8.encode('mysticjam-test');
  addLe32(vendor.length);
  body.add(vendor);
  addLe32(comments.length);
  for (final c in comments) {
    final bytes = utf8.encode(c);
    addLe32(bytes.length);
    body.add(bytes);
  }
  final commentBytes = body.toBytes();

  // VORBIS_COMMENT (type 4) with the last-block flag set.
  out.add([
    0x80 | 0x04,
    (commentBytes.length >> 16) & 0xFF,
    (commentBytes.length >> 8) & 0xFF,
    commentBytes.length & 0xFF,
  ]);
  out.add(commentBytes);
  return out.toBytes();
}
