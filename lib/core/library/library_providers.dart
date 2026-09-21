import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../lyrics/lrclib_client.dart';
import '../settings/app_settings.dart';
import 'database.dart';
import 'library_repository.dart';
import 'library_scanner.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final libraryRepositoryProvider = Provider<LibraryRepository>((ref) {
  return LibraryRepository(ref.watch(databaseProvider));
});

final libraryScannerProvider = Provider<LibraryScanner>((ref) {
  return LibraryScanner(ref.watch(libraryRepositoryProvider));
});

final tracksProvider = StreamProvider<List<Track>>((ref) {
  return ref.watch(libraryRepositoryProvider).watchAllTracks();
});

final albumsProvider = StreamProvider<List<AlbumWithTracks>>((ref) {
  return ref.watch(libraryRepositoryProvider).watchAlbums();
});

/// Regroups any pre-existing track that predates album grouping (see
/// LibraryRepository.backfillAlbumGroups). Watched once from HomeShell so it
/// runs a single time per app launch; [albumsProvider] picks up the result
/// automatically since it's a live stream.
final albumBackfillProvider = FutureProvider<void>((ref) {
  return ref.watch(libraryRepositoryProvider).backfillAlbumGroups();
});

final playlistsProvider = StreamProvider<List<Playlist>>((ref) {
  return ref.watch(libraryRepositoryProvider).watchPlaylists();
});

final playlistTracksProvider = StreamProvider.family<List<Track>, int>((
  ref,
  playlistId,
) {
  return ref.watch(libraryRepositoryProvider).watchPlaylistTracks(playlistId);
});

/// Resolves AppSettingsState.recentlyPlayedTrackIds (just ids, most-recent
/// first — see core/settings/app_settings.dart) against the live track
/// list, preserving that order. Self-healing: watching tracksProvider means
/// a track deleted from the library simply drops out of this list on its
/// own, rather than needing separate cleanup logic in AppSettingsNotifier.
final recentlyPlayedTracksProvider = Provider<AsyncValue<List<Track>>>((ref) {
  final ids = ref.watch(appSettingsProvider).recentlyPlayedTrackIds;
  final tracksAsync = ref.watch(tracksProvider);
  return tracksAsync.whenData((allTracks) {
    final byId = {for (final t in allTracks) t.id: t};
    return ids.map((id) => byId[id]).whereType<Track>().toList();
  });
});

/// Synced lyrics for [track] when it has none locally: uses what's already
/// stored (e.g. fetched on an earlier visit — the Track passed in can be a
/// stale copy from before that), otherwise asks lrclib.net once and stores
/// the answer. autoDispose so a failed lookup is retried the next time the
/// Lyrics screen opens.
final onlineLyricsProvider = FutureProvider.autoDispose.family<String?, Track>((
  ref,
  track,
) async {
  final repo = ref.read(libraryRepositoryProvider);
  final stored = (await repo.getTrackById(track.id))?.syncedLyrics;
  if (stored != null) return stored;

  final artist = track.artist;
  if (artist == null) return null;
  final ms = track.durationMs;
  final lrc = await fetchSyncedLyrics(
    artist: artist,
    title: track.title,
    durationSec: ms == null ? null : (ms / 1000).round(),
  );
  if (lrc != null) await repo.setSyncedLyrics(track.id, lrc);
  return lrc;
});
