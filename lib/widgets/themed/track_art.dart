import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/theme_provider.dart';

/// Shows a track's embedded album art if one was extracted at scan time,
/// falling back to the themed placeholder icon otherwise (no art, or the
/// cached art file is missing/corrupt).
class TrackArt extends ConsumerWidget {
  final String? albumArtPath;
  final double size;
  final double borderRadius;
  final double iconSizeFraction;

  const TrackArt({
    super.key,
    required this.albumArtPath,
    required this.size,
    this.borderRadius = 8,
    this.iconSizeFraction = 0.5,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    final path = albumArtPath;

    final placeholder = Icon(
      theme.icons.library,
      size: size * iconSizeFraction,
      color: theme.colors.textSecondary,
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: Container(
        width: size,
        height: size,
        color: theme.colors.surface,
        child: path == null
            ? placeholder
            : Image.file(
                File(path),
                fit: BoxFit.cover,
                // Decode at thumbnail size instead of full resolution — a long
                // list would otherwise hold every cover at full size in memory.
                cacheWidth: size <= 120 ? (size * 2).round() : null,
                errorBuilder: (context, error, stackTrace) => placeholder,
              ),
      ),
    );
  }
}
