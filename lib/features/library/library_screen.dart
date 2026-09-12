import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/format_support.dart';
import '../../core/format_duration.dart';
import '../../core/library/database.dart';
import '../../core/library/library_providers.dart';
import '../../core/playback/playback_controller.dart';
import '../../core/theme/theme_provider.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/themed/themed_button.dart';
import '../../widgets/themed/themed_card.dart';
import '../../widgets/themed/themed_icon.dart';
import '../../widgets/themed/themed_search_bar.dart';
import '../now_playing/now_playing_screen.dart';
import '../playlists/playlist_actions.dart';
import '../settings/settings_screen.dart';
import 'track_actions.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

/// A row in the grouped library list — either an artist section header or a
/// track, with [queueIndex] preserved so tapping still queues correctly
/// against the flat (ungrouped) track list.
sealed class _LibraryRow {}

class _ArtistHeaderRow extends _LibraryRow {
  final String artist;
  _ArtistHeaderRow(this.artist);
}

class _TrackRow extends _LibraryRow {
  final Track track;
  final int queueIndex;
  _TrackRow(this.track, this.queueIndex);
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  bool _scanning = false;
  String _query = '';
  bool _selectionMode = false;
  final Set<int> _selectedTrackIds = {};

  /// Re-parses metadata for every already-indexed track — needed because a
  /// normal scan skips files it already recognizes, so tracks added before
  /// tag parsing existed (or before a format had a reader) never pick up
  /// real tags just by re-scanning the same folder. Also repairs tracks
  /// left stale by any past bug and removes ones whose file is gone, all
  /// without the user manually deleting and re-adding anything.
  Future<void> _refreshMetadata() async {
    setState(() => _scanning = true);
    try {
      final scanner = ref.read(libraryScannerProvider);
      final result = await scanner.refreshAllMetadata();
      if (mounted) {
        final base = 'Refreshed ${result.processed} track${result.processed == 1 ? '' : 's'}';
        final message = result.removed > 0 ? '$base (${result.removed} removed — file not found)' : base;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _pickAndScanFolder() async {
    final path = await FilePicker.getDirectoryPath();
    if (path == null) return;
    // The picker dialog can stay open indefinitely waiting on the user — if
    // this screen got disposed while it was open, setState below would
    // throw on a defunct State.
    if (!mounted) return;

    setState(() => _scanning = true);
    try {
      final scanner = ref.read(libraryScannerProvider);
      final result = await scanner.scanDirectory(path);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Added ${result.addedCount} tracks')),
        );
      }
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  /// Picks individual audio/video files directly, as opposed to importing a
  /// whole folder — for grabbing one or two specific songs from anywhere on
  /// disk without a bulk folder scan.
  Future<void> _pickAndScanFiles() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: allSupportedExtensions.toList(),
      allowMultiple: true,
    );
    if (result == null) return;
    final paths = result.files.map((f) => f.path).whereType<String>().toList();
    if (paths.isEmpty) return;
    if (!mounted) return;

    setState(() => _scanning = true);
    try {
      final scanner = ref.read(libraryScannerProvider);
      final scanResult = await scanner.scanFiles(paths);
      if (mounted) {
        final message = scanResult.addedCount == 0
            ? 'Already in your library — nothing new to add'
            : 'Added ${scanResult.addedCount} track${scanResult.addedCount == 1 ? '' : 's'}';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  List<Track> _filter(List<Track> tracks) {
    if (_query.isEmpty) return tracks;
    final q = _query.toLowerCase();
    return tracks
        .where((t) => t.title.toLowerCase().contains(q) || (t.artist?.toLowerCase().contains(q) ?? false))
        .toList();
  }

  /// [tracks] is already sorted artist-then-title (see
  /// LibraryRepository.watchAllTracks) — this just inserts a header row
  /// whenever the artist changes, so browsing reads as grouped sections
  /// instead of one flat interleaved list.
  List<_LibraryRow> _groupByArtist(List<Track> tracks) {
    final rows = <_LibraryRow>[];
    String? lastArtist;
    for (var i = 0; i < tracks.length; i++) {
      final artist = tracks[i].artist?.trim();
      final label = (artist == null || artist.isEmpty) ? 'Unknown Artist' : artist;
      if (label != lastArtist) {
        rows.add(_ArtistHeaderRow(label));
        lastArtist = label;
      }
      rows.add(_TrackRow(tracks[i], i));
    }
    return rows;
  }

  void _playTrack(List<Track> queue, int index) {
    final controller = ref.read(playbackControllerProvider.notifier);
    controller.playFromQueue(queue, index);
    controller.refreshVolume();
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const NowPlayingScreen()),
    );
  }

  void _enterSelectionMode(int trackId) {
    setState(() {
      _selectionMode = true;
      _selectedTrackIds.add(trackId);
    });
  }

  void _toggleSelection(int trackId) {
    setState(() {
      if (!_selectedTrackIds.add(trackId)) {
        _selectedTrackIds.remove(trackId);
      }
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selectedTrackIds.clear();
    });
  }

  void _addSelectedToPlaylist(List<Track> allTracks) {
    final selected = allTracks.where((t) => _selectedTrackIds.contains(t.id)).toList();
    showAddToPlaylistSheet(context, ref, selected);
    _exitSelectionMode();
  }

  /// Toggles between selecting every currently visible (filtered) track and
  /// clearing the selection — so bulk actions don't require tapping each
  /// song one by one.
  void _toggleSelectAll(List<Track> visibleTracks) {
    setState(() {
      final allSelected =
          visibleTracks.isNotEmpty && visibleTracks.every((t) => _selectedTrackIds.contains(t.id));
      if (allSelected) {
        _selectedTrackIds.clear();
      } else {
        _selectedTrackIds.addAll(visibleTracks.map((t) => t.id));
      }
    });
  }

  Future<void> _deleteSelected() async {
    final count = _selectedTrackIds.length;
    if (count == 0) return;

    final confirmed = await confirmDestructiveAction(
      context,
      ref,
      title: 'Remove $count Song${count == 1 ? '' : 's'}?',
      message: 'These songs will be removed from your library and any playlists. '
          'Files on disk are not deleted.',
    );
    if (!confirmed) return;

    final repo = ref.read(libraryRepositoryProvider);
    for (final id in _selectedTrackIds.toList()) {
      await repo.deleteTrack(id);
    }
    if (mounted) _exitSelectionMode();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final tracksAsync = ref.watch(tracksProvider);
    final visibleTracks = _filter(tracksAsync.value ?? const []);

    return Scaffold(
      appBar: _selectionMode
          ? AppBar(
              leading: IconButton(
                icon: const ThemedIcon(ThemedIconSlot.close),
                onPressed: _exitSelectionMode,
              ),
              title: Text(
                '${_selectedTrackIds.length} selected',
                style: TextStyle(color: theme.colors.textPrimary),
              ),
              actions: [
                IconButton(
                  tooltip: 'Select All',
                  icon: const ThemedIcon(ThemedIconSlot.selectAll),
                  onPressed: () => _toggleSelectAll(visibleTracks),
                ),
                IconButton(
                  tooltip: 'Add to Playlist',
                  icon: ThemedIcon(
                    ThemedIconSlot.playlistAdd,
                    color: _selectedTrackIds.isEmpty
                        ? theme.colors.controlInactive
                        : theme.colors.controlActive,
                  ),
                  onPressed: _selectedTrackIds.isEmpty
                      ? null
                      : () => _addSelectedToPlaylist(tracksAsync.value ?? const []),
                ),
                IconButton(
                  tooltip: 'Delete',
                  icon: ThemedIcon(
                    ThemedIconSlot.delete,
                    color: _selectedTrackIds.isEmpty
                        ? theme.colors.controlInactive
                        : theme.colors.error,
                  ),
                  onPressed: _selectedTrackIds.isEmpty ? null : _deleteSelected,
                ),
              ],
            )
          : AppBar(
              title: Text('Library', style: TextStyle(color: theme.colors.textPrimary)),
              actions: [
                IconButton(
                  tooltip: 'Refresh Metadata',
                  icon: const ThemedIcon(ThemedIconSlot.refresh),
                  onPressed: _scanning ? null : _refreshMetadata,
                ),
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
                IconButton(
                  icon: const ThemedIcon(ThemedIconSlot.settings),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  ),
                ),
              ],
            ),
      body: tracksAsync.when(
        data: (allTracks) {
          if (allTracks.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'No tracks yet',
                    style: TextStyle(color: theme.colors.textSecondary),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ThemedButton(
                        label: 'Add Files',
                        icon: theme.icons.fileAdd,
                        onPressed: _scanning ? null : _pickAndScanFiles,
                      ),
                      const SizedBox(width: 12),
                      ThemedButton(
                        label: _scanning ? 'Scanning...' : 'Add Folder',
                        icon: theme.icons.folderAdd,
                        onPressed: _scanning ? null : _pickAndScanFolder,
                      ),
                    ],
                  ),
                ],
              ),
            );
          }

          final filtered = _filter(allTracks);
          final rows = _groupByArtist(filtered);

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
                        itemCount: rows.length,
                        itemBuilder: (context, rowIndex) {
                          final row = rows[rowIndex];

                          if (row is _ArtistHeaderRow) {
                            return Padding(
                              padding: EdgeInsets.fromLTRB(16, rowIndex == 0 ? 12 : 20, 16, 6),
                              child: Text(
                                row.artist.toUpperCase(),
                                style: TextStyle(
                                  color: theme.colors.textSecondary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1,
                                ),
                              ),
                            );
                          }

                          final track = (row as _TrackRow).track;
                          final index = row.queueIndex;
                          final selected = _selectedTrackIds.contains(track.id);
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            child: GestureDetector(
                              onSecondaryTapDown: _selectionMode
                                  ? null
                                  : (details) => showTrackContextMenu(
                                        context: context,
                                        ref: ref,
                                        track: track,
                                        position: details.globalPosition,
                                        onPlay: () => _playTrack(filtered, index),
                                      ),
                              onLongPress: _selectionMode ? null : () => _enterSelectionMode(track.id),
                              child: ThemedCard(
                                // Queue is the currently filtered/visible list, so
                                // next/previous walk through what's on screen —
                                // and re-tapping the already-playing track just
                                // resumes it instead of restarting from zero.
                                onTap: _selectionMode
                                    ? () => _toggleSelection(track.id)
                                    : () => _playTrack(filtered, index),
                                child: Row(
                                  children: [
                                    if (_selectionMode)
                                      Checkbox(
                                        value: selected,
                                        activeColor: theme.colors.primary,
                                        onChanged: (_) => _toggleSelection(track.id),
                                      ),
                                    Expanded(
                                      child: Text(track.title, style: TextStyle(color: theme.colors.textPrimary)),
                                    ),
                                    if (track.durationMs != null) ...[
                                      Text(
                                        formatDuration(Duration(milliseconds: track.durationMs!)),
                                        style: TextStyle(color: theme.colors.textSecondary, fontSize: 11),
                                      ),
                                      const SizedBox(width: 8),
                                    ],
                                    Text(
                                      track.format.toUpperCase(),
                                      style: TextStyle(color: theme.colors.textSecondary, fontSize: 11),
                                    ),
                                    if (!_selectionMode)
                                      IconButton(
                                        icon: ThemedIcon(ThemedIconSlot.playlistAdd, color: theme.colors.textSecondary),
                                        onPressed: () => showAddToPlaylistSheet(context, ref, [track]),
                                      ),
                                  ],
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
