import 'dart:typed_data';

/// Metadata parsed directly from a media file's embedded tags. Every field
/// is nullable — the scanner falls back to the filename for [title] when
/// tags don't provide one, and simply leaves the rest unset when a
/// format/file has none. [durationMs] is only ever populated by readers
/// that can get it essentially for free from a header field (e.g. FLAC's
/// STREAMINFO) — formats without one stay null here and get filled in
/// lazily from actual playback instead (see PlaybackController).
class ParsedMetadata {
  final String? title;
  final String? artist;
  final String? album;
  final Uint8List? artwork;
  final int? durationMs;
  final String? lyrics;
  final String? genre;

  /// The album-level artist ("Various Artists" on a compilation, the
  /// headline act on a record with guest features) — distinct from
  /// [artist], which is per-track. Null when the file has no such tag; see
  /// album_grouping.dart for how grouping falls back to [artist] then.
  final String? albumArtist;

  /// Release year (parsed from the tag's date field), null if unknown.
  final int? year;

  /// The track's position within its album (e.g. 5 from "5/12") — null when
  /// the format/file has no such tag, not 0. See Tracks.trackNumber in
  /// library_model.dart for why 0 is never used as an "unknown" sentinel.
  final int? trackNumber;

  const ParsedMetadata({
    this.title,
    this.artist,
    this.album,
    this.artwork,
    this.durationMs,
    this.lyrics,
    this.genre,
    this.trackNumber,
    this.albumArtist,
    this.year,
  });

  static const empty = ParsedMetadata();
}
