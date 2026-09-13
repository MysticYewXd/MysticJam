import 'package:drift/drift.dart';

/// Indexed local tracks. One row per playable file discovered by the scanner
/// (audio files and audio extracted from video containers alike).
class Tracks extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get filePath => text().unique()();
  TextColumn get title => text()();
  TextColumn get artist => text().nullable()();
  TextColumn get album => text().nullable()();
  IntColumn get durationMs => integer().nullable()();
  TextColumn get format => text()();
  DateTimeColumn get dateAdded => dateTime().withDefault(currentDateAndTime)();

  /// Path to a cached image file extracted from the track's embedded
  /// artwork (ID3 APIC / FLAC PICTURE block), if any. Extracted once at
  /// scan time, not re-checked on subsequent scans.
  TextColumn get albumArtPath => text().nullable()();

  /// Embedded lyrics (ID3 USLT frame), if the file has any. Plain text,
  /// unsynchronised — no per-line timestamps.
  TextColumn get lyrics => text().nullable()();

  /// Free-text genre from the file's tags (e.g. "Rock") — null means the
  /// format/file had no genre tag, never an empty/placeholder string. Not
  /// normalized against a fixed genre list; whatever the tagger wrote is
  /// stored as-is.
  TextColumn get genre => text().nullable()();

  /// Track's position within its album (from e.g. ID3 TRCK, Vorbis
  /// TRACKNUMBER). Null means unknown — never 0, which is why this isn't a
  /// plain non-nullable int with a 0 default: 0 would be indistinguishable
  /// from "actually track zero" (rare but real, e.g. some hidden-track
  /// releases) and would sort ahead of every real track number if used as
  /// an "unknown" sentinel.
  IntColumn get trackNumber => integer().nullable()();
}

/// A user-created, named ordered collection of tracks. Playback queues are
/// scoped to a playlist so playing one song doesn't pull in the whole library.
class Playlists extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  DateTimeColumn get dateCreated =>
      dateTime().withDefault(currentDateAndTime)();
}

/// Join table preserving explicit track order within a playlist.
class PlaylistTracks extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get playlistId => integer().references(Playlists, #id)();
  IntColumn get trackId => integer().references(Tracks, #id)();
  IntColumn get position => integer()();
}
