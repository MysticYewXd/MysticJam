import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../core/library/database.dart';
import '../../core/library/library_providers.dart';
import '../../core/library/metadata/lrc_parser.dart';
import '../../core/playback/playback_controller.dart';
import '../../core/settings/app_settings.dart';
import '../../core/theme/theme_model.dart';
import '../../core/theme/theme_provider.dart';

TextAlign lyricsTextAlign(LyricsAlign a) => switch (a) {
  LyricsAlign.left => TextAlign.left,
  LyricsAlign.center => TextAlign.center,
  LyricsAlign.right => TextAlign.right,
};

Alignment lyricsScaleAlignment(LyricsAlign a) => switch (a) {
  LyricsAlign.left => Alignment.centerLeft,
  LyricsAlign.center => Alignment.center,
  LyricsAlign.right => Alignment.centerRight,
};

/// One lyric line's text style, shared with the Look & Feel preview so the
/// settings show exactly what the lyrics screen will render.
TextStyle lyricsTextStyle(AppTheme theme, UiPrefs ui) => TextStyle(
  color: theme.colors.textPrimary,
  fontSize: ui.lyricsFontSize,
  fontWeight: FontWeight.w600,
  height: ui.lyricsLineSpacing,
);

/// Lyrics for the currently playing track. Synced lyrics come first: the
/// track's own `.lrc` sidecar, or — only when it has none — a one-time lookup
/// on lrclib.net (see onlineLyricsProvider), which is stored so later visits
/// stay offline. Synced lines highlight and auto-scroll with playback, and a
/// tap on a line seeks there. Without synced lyrics it falls back to plain
/// ID3 lyrics, then to "no lyrics".
class LyricsScreen extends ConsumerWidget {
  final Track track;

  const LyricsScreen({super.key, required this.track});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    var lrc = track.syncedLyrics;
    var lookingUp = false;
    if (lrc == null && ref.watch(uiPrefsProvider).lyricsOnlineLookup) {
      final online = ref.watch(onlineLyricsProvider(track));
      lookingUp = online.isLoading;
      lrc = online.valueOrNull;
    }
    final lines = lrc == null ? const <LyricLine>[] : parseLrc(lrc);

    return Scaffold(
      backgroundColor: theme.colors.background,
      appBar: AppBar(
        title: Text(
          track.title,
          style: TextStyle(color: theme.colors.textPrimary),
        ),
      ),
      body: lines.isNotEmpty
          ? _SyncedLyricsView(lines: lines)
          : lookingUp
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: theme.colors.primary),
                  const SizedBox(height: 16),
                  Text(
                    'Looking up lyrics online…',
                    style: TextStyle(color: theme.colors.textSecondary),
                  ),
                ],
              ),
            )
          : _PlainLyricsView(text: track.lyrics),
    );
  }
}

class _PlainLyricsView extends ConsumerWidget {
  final String? text;

  const _PlainLyricsView({required this.text});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    final ui = ref.watch(uiPrefsProvider);
    if (text == null || text!.trim().isEmpty) {
      return Center(
        child: Text(
          'No lyrics found for this track',
          style: TextStyle(color: theme.colors.textSecondary),
        ),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: SizedBox(
        width: double.infinity,
        child: Text(
          text!.trim(),
          textAlign: lyricsTextAlign(ui.lyricsAlign),
          style: lyricsTextStyle(
            theme,
            ui,
          ).copyWith(fontWeight: theme.typography.lyricsWeight),
        ),
      ),
    );
  }
}

class _SyncedLyricsView extends ConsumerStatefulWidget {
  final List<LyricLine> lines;

  const _SyncedLyricsView({required this.lines});

  @override
  ConsumerState<_SyncedLyricsView> createState() => _SyncedLyricsViewState();
}

class _SyncedLyricsViewState extends ConsumerState<_SyncedLyricsView> {
  final _scroll = ItemScrollController();
  int? _lastActive;

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final ui = ref.watch(uiPrefsProvider);
    final position = ref.watch(
      playbackControllerProvider.select((s) => s.position),
    );
    final controller = ref.read(playbackControllerProvider.notifier);
    final active = activeLyricIndex(widget.lines, position);

    // First build jumps straight to the current line (initialScrollIndex);
    // after that, animate whenever the active line changes.
    if (ui.lyricsAutoScroll &&
        _lastActive != null &&
        active != _lastActive &&
        active >= 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.isAttached) {
          _scroll.scrollTo(
            index: active,
            alignment: 0.35,
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutCubic,
          );
        }
      });
    }
    final firstBuild = _lastActive == null;
    _lastActive = active;

    return ScrollablePositionedList.builder(
      itemScrollController: _scroll,
      initialScrollIndex: firstBuild && active > 0 ? active : 0,
      initialAlignment: 0.35,
      padding: const EdgeInsets.symmetric(vertical: 120, horizontal: 24),
      itemCount: widget.lines.length,
      itemBuilder: (context, index) {
        final line = widget.lines[index];
        final isActive = index == active;
        return InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: ui.lyricsTapToSeek ? () => controller.seek(line.time) : null,
          child: AnimatedOpacity(
            opacity: isActive ? 1 : ui.lyricsInactiveOpacity,
            duration: const Duration(milliseconds: 250),
            child: AnimatedScale(
              scale: isActive ? 1 : 0.92,
              alignment: lyricsScaleAlignment(ui.lyricsAlign),
              duration: const Duration(milliseconds: 250),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: SizedBox(
                  width: double.infinity,
                  child: Text(
                    line.text,
                    textAlign: lyricsTextAlign(ui.lyricsAlign),
                    style: lyricsTextStyle(theme, ui),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
