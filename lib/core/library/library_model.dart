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
}

/// A user-created, named ordered collection of tracks. Playback queues are
/// scoped to a playlist so playing one song doesn't pull in the whole library.
class Playlists extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  DateTimeColumn get dateCreated => dateTime().withDefault(currentDateAndTime)();
}

/// Join table preserving explicit track order within a playlist.
class PlaylistTracks extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get playlistId => integer().references(Playlists, #id)();
  IntColumn get trackId => integer().references(Tracks, #id)();
  IntColumn get position => integer()();
}
