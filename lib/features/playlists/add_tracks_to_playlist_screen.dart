import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/format_support.dart';
import '../../core/library/database.dart';
import '../../core/library/library_providers.dart';
import '../../core/theme/theme_provider.dart';
import '../../widgets/themed/themed_icon.dart';
import '../../widgets/themed/themed_search_bar.dart';

/// Full-library picker with multi-select checkboxes, opened from within an
/// already-open playlist so adding songs doesn't require going back out to
/// the Library screen first.
class AddTracksToPlaylistScreen extends ConsumerStatefulWidget {
  final Playlist playlist;

  const AddTracksToPlaylistScreen({super.key, required this.playlist});

  @override
  ConsumerState<AddTracksToPlaylistScreen> createState() => _AddTracksToPlaylistScreenState();
}

class _AddTracksToPlaylistScreenState extends ConsumerState<AddTracksToPlaylistScreen> {
  String _query = '';
  bool _scanning = false;
  final Set<int> _selectedTrackIds = {};

  List<Track> _filter(List<Track> tracks) {
    if (_query.isEmpty) return tracks;
    final q = _query.toLowerCase();
    return tracks
        .where((t) => t.title.toLowerCase().contains(q) || (t.artist?.toLowerCase().contains(q) ?? false))
        .toList();
  }

  /// Scans [paths], then adds every one of them straight into this playlist
  /// — whether they were brand-new to the library or already indexed
  /// elsewhere. This is the whole point of scanning from inside a playlist
  /// instead of the Library screen: no separate find-and-checkbox step after.
  Future<void> _addScannedPathsToPlaylist(List<String> paths, {required int addedCount}) async {
    if (paths.isEmpty) return;
    final repo = ref.read(libraryRepositoryProvider);
    final trackIds = await repo.getTrackIdsForPaths(paths);
    await repo.addTracksToPlaylist(widget.playlist.id, trackIds);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Added ${trackIds.length} song${trackIds.length == 1 ? '' : 's'} to ${widget.playlist.name}'
            '${addedCount > 0 ? ' ($addedCount new to library)' : ''}',
          ),
        ),
      );
    }
  }

  Future<void> _pickAndScanFolder() async {
    final path = await FilePicker.getDirectoryPath();
    if (path == null) return;
    // The picker dialog can stay open indefinitely waiting on the user — if
    // this screen got disposed (navigated away) while it was open, setState
    // below would throw on a defunct State.
    if (!mounted) return;

    setState(() => _scanning = true);
    try {
      final scanner = ref.read(libraryScannerProvider);
      final result = await scanner.scanDirectory(path);
      await _addScannedPathsToPlaylist(result.allPaths, addedCount: result.addedCount);
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  /// Picks individual audio/video files directly, as opposed to importing a
  /// whole folder — for grabbing one or two specific songs from anywhere on
  /// disk without a bulk folder scan.
  Future<void> _pickAndScanFiles() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: allSupportedExtensions.toList(),
      allowMultiple: true,
    );
    if (picked == null) return;
    final paths = picked.files.map((f) => f.path).whereType<String>().toList();
    if (paths.isEmpty) return;
    if (!mounted) return;

    setState(() => _scanning = true);
    try {
      final scanner = ref.read(libraryScannerProvider);
      final result = await scanner.scanFiles(paths);
      await _addScannedPathsToPlaylist(result.allPaths, addedCount: result.addedCount);
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _addSelected() async {
    if (_selectedTrackIds.isEmpty) return;
    await ref
        .read(libraryRepositoryProvider)
        .addTracksToPlaylist(widget.playlist.id, _selectedTrackIds.toList());
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final tracksAsync = ref.watch(tracksProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _selectedTrackIds.isEmpty
              ? 'Add to ${widget.playlist.name}'
              : '${_selectedTrackIds.length} selected',
          style: TextStyle(color: theme.colors.textPrimary),
        ),
        actions: [
          IconButton(
            tooltip: 'Add Files',
            icon: const ThemedIcon(ThemedIconSlot.fileAdd),
            onPressed: _scanning ? null : _pickAndScanFiles,
          ),
          IconButton(
            tooltip: 'Add Folder',
            icon: _scanning
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: theme.colors.textPrimary),
                  )
                : const ThemedIcon(ThemedIconSlot.folderAdd),
            onPressed: _scanning ? null : _pickAndScanFolder,
          ),
          TextButton(
            onPressed: _selectedTrackIds.isEmpty ? null : _addSelected,
            child: Text(
              'Add',
              style: TextStyle(
                color: _selectedTrackIds.isEmpty ? theme.colors.controlInactive : theme.colors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      body: tracksAsync.when(
        data: (allTracks) {
          if (allTracks.isEmpty) {
            return Center(
              child: Text('No tracks in your library yet', style: TextStyle(color: theme.colors.textSecondary)),
            );
          }
          final filtered = _filter(allTracks);
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                child: ThemedSearchBar(
                  hintText: 'Search library',
                  onChanged: (value) => setState(() => _query = value),
                ),
              ),
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Text('No matches', style: TextStyle(color: theme.colors.textSecondary)),
                      )
                    : ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final track = filtered[index];
                          final selected = _selectedTrackIds.contains(track.id);
                          return CheckboxListTile(
                            value: selected,
                            activeColor: theme.colors.primary,
                            onChanged: (_) => setState(() {
                              if (!_selectedTrackIds.add(track.id)) {
                                _selectedTrackIds.remove(track.id);
                              }
                            }),
                            title: Text(track.title, style: TextStyle(color: theme.colors.textPrimary)),
                            subtitle: track.artist != null
                                ? Text(track.artist!, style: TextStyle(color: theme.colors.textSecondary))
                                : null,
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
