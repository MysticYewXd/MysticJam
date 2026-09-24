import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/library/database.dart';
import '../../core/library/library_providers.dart';
import '../../core/theme/theme_provider.dart';
import '../../widgets/themed/themed_icon.dart';
import '../../widgets/themed/themed_search_bar.dart';
import 'group_detail_screen.dart';

class _Group {
  /// The grouping key (must be unique per bucket — e.g. a folder's full
  /// path, so two different "Greatest Hits" folders under different
  /// artists never merge).
  final String key;

  /// What's actually shown in the row — usually the same as [key]
  /// (artists, genres), but Folders shows just the last path segment
  /// while still keying/sorting by the full path for correctness.
  final String label;

  final List<Track> tracks;
  _Group(this.key, this.label, this.tracks);
}

/// Generic "group the library by some text key and browse it" screen —
/// used for Artists, Genres, and Folders alike (see BrowseHubScreen). Each
/// is just a different [keyOf]/[unknownLabel]/icon over the same searchable
/// list -> GroupDetailScreen flow, so one implementation covers all three
/// instead of three near-identical copies.
class GroupedBrowseScreen extends ConsumerStatefulWidget {
  final String title;
  final ThemedIconSlot rowIcon;
  final String? Function(Track track) keyOf;
  final String unknownLabel;
  final String Function(int count) countLabel;

  /// Maps a grouping key to what's displayed — identity by default. See
  /// [_Group]'s doc comment for why Folders needs this distinct from the key.
  final String Function(String key)? displayLabel;

  const GroupedBrowseScreen({
    super.key,
    required this.title,
    required this.rowIcon,
    required this.keyOf,
    required this.unknownLabel,
    required this.countLabel,
    this.displayLabel,
  });

  @override
  ConsumerState<GroupedBrowseScreen> createState() =>
      _GroupedBrowseScreenState();
}

class _GroupedBrowseScreenState extends ConsumerState<GroupedBrowseScreen> {
  String _query = '';

  List<_Group> _groupTracks(List<Track> tracks) {
    final byKey = <String, List<Track>>{};
    for (final track in tracks) {
      final rawKey = widget.keyOf(track)?.trim();
      final key = (rawKey == null || rawKey.isEmpty)
          ? widget.unknownLabel
          : rawKey;
      byKey.putIfAbsent(key, () => []).add(track);
    }
    final groups =
        byKey.entries
            .map(
              (e) => _Group(
                e.key,
                widget.displayLabel?.call(e.key) ?? e.key,
                e.value,
              ),
            )
            .toList()
          ..sort((a, b) => a.label.compareTo(b.label));
    return groups;
  }

  List<_Group> _filter(List<_Group> groups) {
    if (_query.isEmpty) return groups;
    final q = _query.toLowerCase();
    return groups.where((g) => g.label.toLowerCase().contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final tracksAsync = ref.watch(tracksProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.title,
          style: TextStyle(color: theme.colors.textPrimary),
        ),
      ),
      body: tracksAsync.when(
        data: (allTracks) {
          if (allTracks.isEmpty) {
            return Center(
              child: Text(
                'No tracks yet',
                style: TextStyle(color: theme.colors.textSecondary),
              ),
            );
          }

          final groups = _filter(_groupTracks(allTracks));

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                child: ThemedSearchBar(
                  hintText: 'Search ${widget.title.toLowerCase()}',
                  onChanged: (value) => setState(() => _query = value),
                ),
              ),
              Expanded(
                child: groups.isEmpty
                    ? Center(
                        child: Text(
                          'No matches',
                          style: TextStyle(color: theme.colors.textSecondary),
                        ),
                      )
                    : ListView.builder(
                        itemCount: groups.length,
                        itemBuilder: (context, index) {
                          final group = groups[index];
                          return ListTile(
                            leading: ThemedIcon(
                              widget.rowIcon,
                              color: theme.colors.textSecondary,
                            ),
                            title: Text(
                              group.label,
                              style: TextStyle(color: theme.colors.textPrimary),
                            ),
                            subtitle: Text(
                              widget.countLabel(group.tracks.length),
                              style: TextStyle(
                                color: theme.colors.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => GroupDetailScreen(
                                  title: group.label,
                                  tracks: group.tracks,
                                ),
                              ),
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
