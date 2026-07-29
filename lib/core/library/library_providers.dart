import 'package:flutter_riverpod/flutter_riverpod.dart';

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

final playlistTracksProvider = StreamProvider.family<List<Track>, int>((ref, playlistId) {
  return ref.watch(libraryRepositoryProvider).watchPlaylistTracks(playlistId);
});
