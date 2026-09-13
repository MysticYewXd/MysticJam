import 'package:flutter_riverpod/flutter_riverpod.dart';

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
