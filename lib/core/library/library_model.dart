import 'package:drift/drift.dart';

/// An album as identified by embedded tags (see album_grouping.dart) — its
/// own entity so the Albums screen can query and join instead of
/// re-deriving groups from every track's text on each render.
class Albums extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Normalized (album, album-artist) identity, unique — this is what stops
  /// same-titled albums by different artists from merging, and what lets
  /// scanning find-or-create an album without duplicates. See
  /// albumKeyFor() for exactly how it's built.
  TextColumn get groupKey => text().unique()();

  TextColumn get title => text()();

  /// Album-level artist for display; null for the Unknown Album bucket.
  TextColumn get artist => text().nullable()();

  IntColumn get year => integer().nullable()();

  /// Cover image for the album (path into the album_art cache), taken from
  /// the first scanned track that has embedded/adjacent art. Null = none
  /// found yet.
  TextColumn get coverArtPath => text().nullable()();
}

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

  /// The album this track belongs to. Nullable so tracks indexed before
  /// albums existed (or mid-migration) are valid until (re)grouped; a track
  /// with no usable album tag points at the Unknown Album row, not null.
  IntColumn get albumId => integer().nullable().references(Albums, #id)();

  /// Album-artist tag exactly as written — kept alongside [albumId] (rather
  /// than only on Albums) so a track can be re-grouped from its own stored
  /// tags, e.g. after the user fixes a mis-tagged file in a future tag
  /// editor, without re-reading the file.
  TextColumn get albumArtist => text().nullable()();

  /// Release year from the tags, null if unknown.
  IntColumn get year => integer().nullable()();

  /// Raw contents of a same-named `.lrc` sidecar file found next to the
  /// track at scan time (e.g. `song.mp3` + `song.lrc`), if one exists.
  /// Stored raw rather than pre-parsed so a future LRC format tweak only
  /// needs a new parser, not a re-scan — see metadata/lrc_parser.dart for
  /// how it's read. Separate from [lyrics] (ID3 USLT), which is unsynced
  /// and comes from the audio file itself, not a sidecar.
  TextColumn get syncedLyrics => text().nullable()();
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
