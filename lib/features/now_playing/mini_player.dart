import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/library/database.dart';
import '../../core/playback/playback_controller.dart';
import '../../core/theme/album_palette.dart';
import '../../core/theme/theme_model.dart';
import '../../core/theme/theme_provider.dart';
import '../../widgets/themed/round_buttons.dart';
import '../../widgets/themed/themed_icon.dart';
import '../../widgets/themed/track_art.dart';
import 'now_playing_screen.dart';

/// Shows the current track, meant to sit in a Scaffold's
/// bottomNavigationBar slot on every screen where playback should stay
/// visible/controllable. Tapping it opens the full Now Playing screen
/// WITHOUT re-issuing a play command — this is the fix for "re-clicking a
/// song restarts it": once something is playing, this is how you get back
/// to it. Floats as its own rounded, shadowed card (Apple-Music-style)
/// rather than merging flush into whatever's below it.
class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(albumAdaptedThemeProvider);
    final track = ref.watch(
      playbackControllerProvider.select((s) => s.currentTrack),
    );

    if (track == null) return const SizedBox.shrink();

    // Child widgets below (RoundIconButton, PlayButton, ThemedIcon, TrackArt)
    // read themeProvider directly rather than taking a theme parameter, so
    // without this override they'd render the plain active theme instead of
    // following the album-adapted one this widget itself uses — see
    // NowPlayingScreen, which does the same for the same reason.
    // Its progress line animates continuously while playing; the boundary
    // keeps each frame's repaint to this card instead of the whole page.
    return RepaintBoundary(
      child: ProviderScope(
        overrides: [themeProvider.overrideWithValue(theme)],
        child: _MiniPlayerCard(track: track, theme: theme),
      ),
    );
  }
}

class _MiniPlayerCard extends ConsumerWidget {
  final Track track;
  final AppTheme theme;

  const _MiniPlayerCard({required this.track, required this.theme});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playback = ref.watch(playbackControllerProvider);
    final controller = ref.read(playbackControllerProvider.notifier);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
      margin: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      decoration: BoxDecoration(
        color: theme.colors.chrome,
        borderRadius: BorderRadius.circular(theme.shapes.cornerRadius * 1.5),
        // A little more presence than before (was blurRadius 4/alpha 0.2) —
        // matches the same "floating glass" family as the Dock beneath it
        // (see widgets/themed/dock.dart) rather than reading as a flat card
        // with a token shadow, which is part of why this looked like it was
        // just hanging in empty space with nothing grounding it. Still far
        // lighter than the Dock's own BackdropFilter blur — this card is
        // static (no blurred background), so it doesn't need to compete for
        // GPU budget the way the Dock's live blur does.
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            controller.refreshVolume();
            Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const NowPlayingScreen()));
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 60,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      TrackArt(
                        albumArtPath: track.albumArtPath,
                        size: 40,
                        borderRadius: theme.shapes.cornerRadius * 0.6,
                        iconSizeFraction: 0.5,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              track.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.typography.display(
                                17,
                                color: theme.colors.textPrimary,
                              ),
                            ),
                            if (track.artist != null)
                              Text(
                                track.artist!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: theme.colors.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                          ],
                        ),
                      ),
                      RoundIconButton(
                        slot: ThemedIconSlot.previous,
                        tooltip: 'Previous',
                        diameter: 36,
                        onPressed: playback.hasPrevious
                            ? controller.previous
                            : null,
                      ),
                      const SizedBox(width: 4),
                      PlayButton(
                        playing: playback.isPlaying,
                        diameter: 44,
                        onPressed: controller.togglePlayPause,
                      ),
                      const SizedBox(width: 4),
                      RoundIconButton(
                        slot: ThemedIconSlot.next,
                        tooltip: 'Next',
                        diameter: 36,
                        onPressed: playback.hasNext ? controller.next : null,
                      ),
                    ],
                  ),
                ),
              ),
              _MiniProgressBar(
                position: playback.position,
                duration: playback.duration,
                activeColor: theme.colors.progressBar,
                trackColor: theme.colors.progressBarTrack,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A slim, non-interactive progress line along the bottom edge of the mini
/// player — previously there was no sense of playback progress at all here,
/// only in the full Now Playing screen, which is part of why the mini
/// player felt inert/static ("hanging") rather than alive. Animates its own
/// fill between position updates instead of jumping in visible steps, so it
/// reads as continuously running even though the underlying position only
/// ticks a few times a second.
class _MiniProgressBar extends StatelessWidget {
  final Duration position;
  final Duration duration;
  final Color activeColor;
  final Color trackColor;

  const _MiniProgressBar({
    required this.position,
    required this.duration,
    required this.activeColor,
    required this.trackColor,
  });

  @override
  Widget build(BuildContext context) {
    final totalMs = duration.inMilliseconds <= 0 ? 1 : duration.inMilliseconds;
    final fraction = (position.inMilliseconds / totalMs).clamp(0.0, 1.0);

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: fraction),
      duration: const Duration(milliseconds: 400),
      curve: Curves.linear,
      builder: (context, value, _) {
        return SizedBox(
          height: 3,
          child: LinearProgressIndicator(
            value: value,
            minHeight: 3,
            backgroundColor: trackColor,
            valueColor: AlwaysStoppedAnimation<Color>(activeColor),
          ),
        );
      },
    );
  }
}
