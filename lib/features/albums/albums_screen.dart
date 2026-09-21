import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/library/library_providers.dart';
import '../../core/library/library_repository.dart';
import '../../core/theme/theme_provider.dart';
import '../../widgets/themed/themed_card.dart';
import '../../widgets/themed/themed_search_bar.dart';
import '../../widgets/themed/track_art.dart';
import '../now_playing/mini_player.dart';
import 'album_detail_screen.dart';

/// Grid of every album — a companion to LibraryScreen's artist-grouped view.
/// Queries [albumsProvider] (a join over the Albums/Tracks tables, see
/// LibraryRepository.watchAlbums), not a re-derivation from raw track tags —
/// grouping lives in the database now, this just displays it. Tracks with no
/// usable album tag land in the shared "Unknown Album" bucket rather than
/// being dropped.
class AlbumsScreen extends ConsumerStatefulWidget {
  const AlbumsScreen({super.key});

  @override
  ConsumerState<AlbumsScreen> createState() => _AlbumsScreenState();
}

class _AlbumsScreenState extends ConsumerState<AlbumsScreen> {
  String _query = '';

  List<AlbumWithTracks> _filter(List<AlbumWithTracks> albums) {
    if (_query.isEmpty) return albums;
    final q = _query.toLowerCase();
    return albums.where((a) => a.title.toLowerCase().contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final albumsAsync = ref.watch(albumsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Albums',
          style: TextStyle(color: theme.colors.textPrimary),
        ),
      ),
      body: albumsAsync.when(
        data: (allAlbums) {
          if (allAlbums.isEmpty) {
            return Center(
              child: Text(
                'No albums yet',
                style: TextStyle(color: theme.colors.textSecondary),
              ),
            );
          }

          final albums = _filter(allAlbums);

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                child: ThemedSearchBar(
                  hintText: 'Search albums',
                  onChanged: (value) => setState(() => _query = value),
                ),
              ),
              const MiniPlayer(),
              Expanded(
                child: albums.isEmpty
                    ? Center(
                        child: Text(
                          'No matches',
                          style: TextStyle(color: theme.colors.textSecondary),
                        ),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.all(12),
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 180,
                              mainAxisSpacing: 12,
                              crossAxisSpacing: 12,
                              // Was 0.78 — too tight for the image + two lines of
                              // text + card padding, overflowing by a few px at
                              // some grid widths. Lower ratio means a taller
                              // cell for the same width.
                              childAspectRatio: 0.68,
                            ),
                        itemCount: albums.length,
                        itemBuilder: (context, index) {
                          final album = albums[index];
                          return ThemedCard(
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => AlbumDetailScreen(album: album),
                              ),
                            ),
                            padding: const EdgeInsets.all(8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                AspectRatio(
                                  aspectRatio: 1,
                                  child: LayoutBuilder(
                                    builder: (context, constraints) => TrackArt(
                                      albumArtPath: album.coverArtPath,
                                      size: constraints.maxWidth,
                                      borderRadius:
                                          theme.shapes.cornerRadius * 0.8,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  album.title,
                                  style: theme.typography.display(
                                    14,
                                    color: theme.colors.textPrimary,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  '${album.tracks.length} track${album.tracks.length == 1 ? '' : 's'}',
                                  style: TextStyle(
                                    color: theme.colors.textFaint,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err')),
      ),
    );
  }
}
