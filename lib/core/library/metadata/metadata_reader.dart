import 'package:path/path.dart' as p;

import 'ape_metadata_reader.dart';
import 'flac_metadata_reader.dart';
import 'id3_metadata_reader.dart';
import 'mp4_metadata_reader.dart';
import 'ogg_metadata_reader.dart';
import 'track_metadata.dart';
import 'wma_metadata_reader.dart';

/// Routes to the right pure-Dart tag reader by extension. Formats without a
/// reader (video containers) simply get no metadata — the scanner already
/// falls back to the filename for those, exactly as it did before this
/// feature existed.
Future<ParsedMetadata> readTrackMetadata(String filePath) async {
  final ext = p.extension(filePath).replaceFirst('.', '').toLowerCase();
  switch (ext) {
    case 'mp3':
      return readId3Metadata(filePath);
    case 'flac':
      return readFlacMetadata(filePath);
    case 'ogg':
    case 'opus':
      return readOggMetadata(filePath);
    case 'm4a':
    case 'aac':
      return readMp4Metadata(filePath);
    case 'ape':
      return readApeMetadata(filePath);
    case 'wma':
      return readWmaMetadata(filePath);
    default:
      return ParsedMetadata.empty;
  }
}
