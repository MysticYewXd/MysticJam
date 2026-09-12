import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/library/database.dart';
import '../../core/theme/theme_provider.dart';

/// Plain-text lyrics view for the currently playing track (ID3 USLT frame —
/// unsynchronised, so no per-line highlighting/scrolling with playback).
class LyricsScreen extends ConsumerWidget {
  final Track track;

  const LyricsScreen({super.key, required this.track});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    final lyrics = track.lyrics;

    return Scaffold(
      backgroundColor: theme.colors.background,
      appBar: AppBar(
        title: Text(track.title, style: TextStyle(color: theme.colors.textPrimary)),
      ),
      body: (lyrics == null || lyrics.trim().isEmpty)
          ? Center(
              child: Text(
                'No lyrics found for this track',
                style: TextStyle(color: theme.colors.textSecondary),
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Text(
                lyrics.trim(),
                style: TextStyle(
                  color: theme.colors.textPrimary,
                  fontSize: theme.typography.lyricsSize,
                  fontWeight: theme.typography.lyricsWeight,
                  height: 1.6,
                ),
              ),
            ),
    );
  }
}
