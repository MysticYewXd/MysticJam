import 'dart:io';
import 'dart:typed_data';

import 'track_metadata.dart';
import 'track_number_parser.dart';
import 'vorbis_comment_parser.dart';
import 'year_parser.dart';

/// Reads Vorbis-comment metadata, cover art, and exact duration directly
/// from a FLAC file's metadata blocks — pure Dart, hand-rolled since no
/// pure-Dart FLAC tag library exists on pub.dev. FLAC's own block framing
/// is big-endian; the Vorbis comment block's internal lengths are
/// little-endian, a well-known quirk (Vorbis comments were designed
/// independently of FLAC's container).
///
/// Spec: https://xiph.org/flac/format.html#metadata_block
Future<ParsedMetadata> readFlacMetadata(String filePath) async {
  RandomAccessFile? raf;
  try {
    raf = await File(filePath).open();

    final magic = await raf.read(4);
    if (magic.length != 4 || String.fromCharCodes(magic) != 'fLaC') {
      return ParsedMetadata.empty;
    }

    String? title;
    String? artist;
    String? album;
    Uint8List? artwork;
    int? durationMs;
    String? genre;
    int? trackNumber;
    String? albumArtist;
    int? year;

    while (true) {
      final header = await raf.read(4);
      if (header.length < 4) break;

      final isLast = (header[0] & 0x80) != 0;
      final blockType = header[0] & 0x7F;
      final length = (header[1] << 16) | (header[2] << 8) | header[3];

      final body = await raf.read(length);
      if (body.length < length) break;

      if (blockType == 0) {
        durationMs = _parseStreamInfoDurationMs(body);
      } else if (blockType == 4) {
        final comments = parseVorbisComments(body);
        title ??= comments['TITLE'];
        artist ??= comments['ARTIST'];
        album ??= comments['ALBUM'];
        artwork ??= extractPictureFromComments(comments);
        genre ??= comments['GENRE'];
        trackNumber ??= parseLeadingTrackNumber(comments['TRACKNUMBER']);
        albumArtist ??= comments['ALBUMARTIST'] ?? comments['ALBUM ARTIST'];
        year ??= parseLeadingYear(comments['DATE'] ?? comments['YEAR']);
      } else if (blockType == 6 && artwork == null) {
        artwork = parseFlacPictureBlock(body);
      }

      if (isLast) break;
    }

    return ParsedMetadata(
      title: title,
      artist: artist,
      album: album,
      artwork: artwork,
      durationMs: durationMs,
      genre: genre,
      trackNumber: trackNumber,
      albumArtist: albumArtist,
      year: year,
    );
  } catch (_) {
    // Malformed/unreadable file shouldn't block indexing — the scanner
    // falls back to the filename, same as any untagged file.
    return ParsedMetadata.empty;
  } finally {
    await raf?.close();
  }
}

/// STREAMINFO (mandatory first block, type 0) always carries exact sample
/// rate and total sample count, so duration is exact and free — no need to
/// decode any audio.
int? _parseStreamInfoDurationMs(Uint8List data) {
  try {
    if (data.length < 18) return null;
    // Bytes 10-17: sample_rate(20 bits) | channels-1(3) | bits_per_sample-1(5) | total_samples(36 bits)
    final packed = ByteData.sublistView(data, 10, 18).getUint64(0, Endian.big);
    final sampleRate = (packed >> 44) & 0xFFFFF;
    final totalSamples = packed & 0xFFFFFFFFF;
    if (sampleRate == 0) return null;
    return (totalSamples * 1000) ~/ sampleRate;
  } catch (_) {
    return null;
  }
}
