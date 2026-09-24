import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format_duration.dart';
import '../../core/playback/playback_controller.dart';
import '../../core/theme/album_palette.dart';
import '../../core/theme/theme_provider.dart';
import '../../widgets/themed/round_buttons.dart';
import '../../widgets/themed/themed_icon.dart';
import '../../widgets/themed/themed_progress_bar.dart';
import '../../widgets/themed/themed_volume_slider.dart';
import '../../widgets/themed/track_art.dart';
import 'lyrics_screen.dart';
import 'queue_screen.dart';

class NowPlayingScreen extends ConsumerStatefulWidget {
  const NowPlayingScreen({super.key});

  @override
  ConsumerState<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends ConsumerState<NowPlayingScreen> {
  Timer? _volumePoll;
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // Linux has no push-based "system volume changed externally" event (see
    // LinuxSystemVolumeController), so poll while this screen is open to
    // pick up changes made via hardware keys or the OS volume control.
    // Harmless on Android too — a local getVolume() call is cheap, and the
    // live listener there already covers most cases; this is just a backstop.
    _volumePoll = Timer.periodic(const Duration(seconds: 1), (_) {
      ref.read(playbackControllerProvider.notifier).refreshVolume();
    });
  }

  @override
  void dispose() {
    _volumePoll?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The whole screen re-themes from the playing track's album art. Widgets
    // below read themeProvider, so it's overridden for this subtree only.
    final theme = ref.watch(albumAdaptedThemeProvider);
    final playback = ref.watch(playbackControllerProvider);
    final controller = ref.read(playbackControllerProvider.notifier);
    final track = playback.currentTrack;

    return ProviderScope(
      overrides: [themeProvider.overrideWithValue(theme)],
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color.lerp(theme.colors.background, theme.colors.primary, 0.22)!,
              theme.colors.background,
            ],
          ),
        ),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            actions: [
              if (track != null)
                IconButton(
                  tooltip: 'Lyrics',
                  icon: const ThemedIcon(ThemedIconSlot.lyrics),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => LyricsScreen(track: track),
                    ),
                  ),
                ),
              IconButton(
                tooltip: 'Queue',
                icon: const ThemedIcon(ThemedIconSlot.playlist),
                onPressed: () => Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => const QueueScreen())),
              ),
            ],
          ),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // Everything below scales off the smaller of the two window
                  // dimensions, so shrinking the window either way — narrow or
                  // short — shrinks art/text/controls together instead of
                  // overflowing or requiring a "magic" window size.
                  final shortestSide = math.min(
                    constraints.maxWidth,
                    constraints.maxHeight,
                  );
                  // Lower floor than before (was 0.45) — this screen packs a lot
                  // vertically (art, title, progress, transport row, volume),
                  // and at the old floor a short/minimized window would push the
                  // volume slider below the fold with no visible way to reach it
                  // short of resizing the window. Shrinking further before that
                  // point, plus the Scrollbar below, means every control stays
                  // reachable at any window size.
                  final scale = (shortestSide / 480).clamp(0.3, 1.0);

                  final artSize = math
                      .min(
                        constraints.maxWidth * 0.85,
                        constraints.maxHeight * 0.4,
                      )
                      .clamp(40.0, 320.0);
                  final playSize = (64 * scale).clamp(44.0, 64.0);
                  final controlSize = (40 * scale).clamp(30.0, 40.0);
                  final titleSize = (38 * scale).clamp(20.0, 38.0);
                  final labelSize = (12 * scale).clamp(9.0, 12.0);
                  final artistSize = (15 * scale).clamp(11.0, 15.0);
                  final timeSize = (11 * scale).clamp(9.0, 11.0);
                  double gap(double value) => value * scale;

                  return Scrollbar(
                    controller: _scrollController,
                    thumbVisibility: true,
                    child: Center(
                      child: SingleChildScrollView(
                        controller: _scrollController,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'NOW PLAYING',
                              style: TextStyle(
                                fontSize: labelSize,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 2,
                                color: theme.colors.textSecondary,
                              ),
                            ),
                            SizedBox(height: gap(24)),
                            Container(
                              width: artSize,
                              height: artSize,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(
                                  theme.shapes.cornerRadius * 1.5,
                                ),
                                // Blur is one of the more GPU-expensive paint ops in
                                // Flutter's renderer — kept minimal since this
                                // screen has to redraw on every window resize, and
                                // this app targets low-power integrated GPUs too.
                                boxShadow: [
                                  BoxShadow(
                                    color: theme.colors.primary.withValues(
                                      alpha: 0.35,
                                    ),
                                    blurRadius: 24,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: TrackArt(
                                albumArtPath: track?.albumArtPath,
                                size: artSize,
                                borderRadius: theme.shapes.cornerRadius * 1.5,
                                iconSizeFraction: 0.4,
                              ),
                            ),
                            SizedBox(height: gap(36)),
                            Text(
                              track?.title ?? 'Nothing playing',
                              style: theme.typography.display(
                                titleSize,
                                color: theme.colors.textPrimary,
                                height: 1.1,
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (track?.artist != null) ...[
                              SizedBox(height: gap(6)),
                              Text(
                                track!.artist!,
                                style: TextStyle(
                                  color: theme.colors.textSecondary,
                                  fontSize: artistSize,
                                ),
                              ),
                            ],
                            SizedBox(height: gap(28)),
                            ThemedProgressBar(
                              position: playback.position,
                              duration: playback.duration,
                              onSeek: controller.seek,
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Flexible(
                                    child: Text(
                                      formatDuration(playback.position),
                                      style: TextStyle(
                                        color: theme.colors.textSecondary,
                                        fontSize: timeSize,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Flexible(
                                    child: Text(
                                      formatDuration(playback.duration),
                                      textAlign: TextAlign.end,
                                      style: TextStyle(
                                        color: theme.colors.textSecondary,
                                        fontSize: timeSize,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(height: gap(20)),
                            // Horizontal scroll is a last-resort safety net, not
                            // the primary strategy — the scale-based sizing above
                            // should keep this fitting unscrolled in virtually all
                            // real window sizes, but this guarantees it can never
                            // overflow even if it doesn't.
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  RoundIconButton(
                                    slot: ThemedIconSlot.shuffle,
                                    tooltip: 'Shuffle',
                                    diameter: controlSize,
                                    active: playback.shuffleEnabled,
                                    onPressed: controller.toggleShuffle,
                                  ),
                                  SizedBox(width: gap(12)),
                                  RoundIconButton(
                                    slot: ThemedIconSlot.previous,
                                    tooltip: 'Previous',
                                    diameter: controlSize,
                                    onPressed: playback.hasPrevious
                                        ? controller.previous
                                        : null,
                                  ),
                                  SizedBox(width: gap(16)),
                                  PlayButton(
                                    playing: playback.isPlaying,
                                    diameter: playSize,
                                    onPressed: controller.togglePlayPause,
                                  ),
                                  SizedBox(width: gap(16)),
                                  RoundIconButton(
                                    slot: ThemedIconSlot.next,
                                    tooltip: 'Next',
                                    diameter: controlSize,
                                    onPressed: playback.hasNext
                                        ? controller.next
                                        : null,
                                  ),
                                  SizedBox(width: gap(12)),
                                  RoundIconButton(
                                    slot:
                                        playback.repeatMode ==
                                            PlayerRepeatMode.one
                                        ? ThemedIconSlot.repeatOne
                                        : ThemedIconSlot.repeat,
                                    tooltip: 'Repeat',
                                    diameter: controlSize,
                                    active:
                                        playback.repeatMode !=
                                        PlayerRepeatMode.off,
                                    onPressed: controller.cycleRepeatMode,
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(height: gap(32)),
                            ThemedVolumeSlider(
                              value: playback.volume,
                              onChangeEnd: controller.setVolume,
                            ),
                            SizedBox(height: gap(16)),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
