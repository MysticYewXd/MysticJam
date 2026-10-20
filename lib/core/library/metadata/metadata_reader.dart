import 'package:path/path.dart' as p;

import 'track_metadata.dart';
import 'wma_metadata_reader.dart';

/// Tags for the formats the Rust reader (rust/src/api/track.rs) can't
/// handle: WMA has a Dart reader; anything else (video containers, or a file
/// Rust failed on) gets no metadata, and the scanner falls back to the
/// filename for the title.
Future<ParsedMetadata> readTrackMetadata(String filePath) async {
  final ext = p.extension(filePath).replaceFirst('.', '').toLowerCase();
  return ext == 'wma' ? readWmaMetadata(filePath) : ParsedMetadata.empty;
}
