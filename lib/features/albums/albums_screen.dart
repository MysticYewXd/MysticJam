import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/library/database.dart';
import '../../core/library/library_providers.dart';
import '../../core/theme/theme_provider.dart';
import '../../widgets/themed/themed_card.dart';
import '../../widgets/themed/themed_search_bar.dart';
import '../now_playing/mini_player.dart';
import '../../widgets/themed/track_art.dart';
import 'album_detail_screen.dart';

class _Album {
  final String name;
  final List<Track> tracks;
  _Album(this.name, this.tracks);
}

/// Groups the library by album — a companion to LibraryScreen's
/// artist-grouped view. Tracks with no album tag are bucketed together
/// under "Unknown Album" rather than dropped.
class AlbumsScreen extends ConsumerStatefulWidget {
  const AlbumsScreen({super.key});

  @override
  ConsumerState<AlbumsScreen> createState() => _AlbumsScreenState();
}

class _AlbumsScreenState extends ConsumerState<AlbumsScreen> {
  String _query = '';

  List<_Album> _groupByAlbum(List<Track> tracks) {
    final byAlbum = <String, List<Track>>{};
    for (final track in tracks) {
      final album = track.album?.trim();
      final label = (album == null || album.isEmpty) ? 'Unknown Album' : album;
      byAlbum.putIfAbsent(label, () => []).add(track);
    }
    final albums = byAlbum.entries.map((e) => _Album(e.key, e.value)).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return albums;
  }

  List<_Album> _filter(List<_Album> albums) {
    if (_query.isEmpty) return albums;
    final q = _query.toLowerCase();
    return albums.where((a) => a.name.toLowerCase().contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final tracksAsync = ref.watch(tracksProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Albums',
          style: TextStyle(color: theme.colors.textPrimary),
        ),
      ),
      body: tracksAsync.when(
        data: (allTracks) {
          if (allTracks.isEmpty) {
            return Center(
              child: Text(
                'No albums yet',
                style: TextStyle(color: theme.colors.textSecondary),
              ),
            );
          }

          final albums = _filter(_groupByAlbum(allTracks));

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
                          final artPath = album.tracks
                              .firstWhere(
                                (t) => t.albumArtPath != null,
                                orElse: () => album.tracks.first,
                              )
                              .albumArtPath;
                          return ThemedCard(
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => AlbumDetailScreen(
                                  album: album.name,
                                  tracks: album.tracks,
                                ),
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
                                      albumArtPath: artPath,
                                      size: constraints.maxWidth,
                                      borderRadius:
                                          theme.shapes.cornerRadius * 0.8,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  album.name,
                                  style: TextStyle(
                                    color: theme.colors.textPrimary,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  '${album.tracks.length} track${album.tracks.length == 1 ? '' : 's'}',
                                  style: TextStyle(
                                    color: theme.colors.textSecondary,
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
