import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format_duration.dart';
import '../../core/library/database.dart';
import '../../core/library/library_providers.dart';
import '../../core/library/library_repository.dart';
import '../../core/playback/playback_controller.dart';
import '../../core/theme/theme_model.dart';
import '../../core/theme/theme_provider.dart';
import '../../widgets/themed/themed_icon.dart';
import 'lyrics_screen.dart';

// ---------------------------------------------------------------------------
// Album mood: decides which transition an album gets when it starts playing.
// ---------------------------------------------------------------------------

/// How an album "enters" the disc player, picked from its cover art:
/// - [stark]: mostly colourless covers (think a clear CD case) → glitch cut.
/// - [vivid]: loud, saturated covers → colour burst with expanding rings.
/// - [soft]: everything in between → slow blur bloom with a heartbeat pulse.
enum DiscMood { stark, vivid, soft }

extension on DiscMood {
  Duration get duration => switch (this) {
    DiscMood.stark => const Duration(milliseconds: 700),
    DiscMood.vivid => const Duration(milliseconds: 1000),
    DiscMood.soft => const Duration(milliseconds: 1500),
  };
}

/// Decodes [path] small and measures how colourful the whole cover is (mean
/// saturation over every pixel, so a grey cover with one red strip still
/// reads as stark — unlike the album *seed* colour, which deliberately
/// hunts for the most vivid hue).
Future<DiscMood> _moodFromFile(String path) async {
  try {
    final bytes = await File(path).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: 32);
    final frame = await codec.getNextFrame();
    final data = await frame.image.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    frame.image.dispose();
    codec.dispose();
    if (data == null) return DiscMood.soft;
    final px = data.buffer.asUint8List();
    double satSum = 0;
    var n = 0;
    for (var i = 0; i + 3 < px.length; i += 4) {
      if (px[i + 3] < 128) continue;
      final r = px[i], g = px[i + 1], b = px[i + 2];
      final mx = math.max(r, math.max(g, b));
      final mn = math.min(r, math.min(g, b));
      // HSV saturation, damped for near-black pixels whose hue is noise.
      final sat = mx == 0 ? 0.0 : (mx - mn) / mx;
      satSum += sat * (mx / 255).clamp(0.25, 1.0);
      n++;
    }
    if (n == 0) return DiscMood.soft;
    final meanSat = satSum / n;
    if (meanSat < 0.12) return DiscMood.stark;
    if (meanSat > 0.38) return DiscMood.vivid;
    return DiscMood.soft;
  } catch (_) {
    return DiscMood.soft;
  }
}

final _discMoodProvider = FutureProvider.family<DiscMood, String?>((
  ref,
  path,
) async {
  if (path == null) return DiscMood.stark;
  return _moodFromFile(path);
});

/// The cover decoded at disc resolution. Auto-disposed so only the albums
/// actually on screen stay in memory.
final _discArtProvider = FutureProvider.autoDispose.family<ui.Image?, String?>((
  ref,
  path,
) async {
  if (path == null) return null;
  try {
    final bytes = await File(path).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: 720);
    final frame = await codec.getNextFrame();
    codec.dispose();
    // Not disposed explicitly: the view keeps showing the previous cover
    // while the next one decodes, so it may outlive this provider. The
    // engine frees it once nothing references it.
    return frame.image;
  } catch (_) {
    return null;
  }
});

// ---------------------------------------------------------------------------
// The view
// ---------------------------------------------------------------------------

/// Disc-style Now Playing: a spinning disc you can drag to scrub, a row of
/// hardware-style keys, and an OLED panel listing the album's songs. Lives
/// inside NowPlayingScreen, which supplies the album-tinted theme.
class DiscPlayerView extends ConsumerStatefulWidget {
  const DiscPlayerView({super.key});

  @override
  ConsumerState<DiscPlayerView> createState() => _DiscPlayerViewState();
}

const _keysHeight = 56.0;
const _panelHeight = 262.0;
// Device padding, gaps between sections, and the brand row.
const _chromeHeight = 14.0 + 18 + 16 * 3 + _brandHeight + 6;
const _brandHeight = 14.0;
const _minDisc = 150.0;

class _DiscPlayerViewState extends ConsumerState<DiscPlayerView>
    with TickerProviderStateMixin {
  /// 33⅓ rpm in radians per second.
  static const _spinSpeed = 2 * math.pi * (100 / 3) / 60;

  /// One full turn of the disc scrubs this far through the song.
  static const _secondsPerTurn = 30.0;

  final _angle = ValueNotifier<double>(0);
  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;
  double _speed = 0;

  late final AnimationController _fx;
  DiscMood _mood = DiscMood.stark;

  // Scrubbing state (drag on the disc).
  bool _scrubbing = false;
  double _lastPointerAngle = 0;

  // True while the OLED seek bar is being dragged, or its seek is still
  // landing — position ticks are ignored meanwhile so the bar doesn't jump
  // back. Unlike a disc scrub, the disc keeps spinning.
  bool _barSeeking = false;

  // What the progress arc and OLED clock show: the playback position, or the
  // scrub position while dragging. A notifier rather than widget state, so a
  // position tick (many per second) repaints just those two instead of
  // rebuilding the whole view.
  late final ValueNotifier<Duration> _shownPos;

  // Last decoded cover, shown while the next album's art is still decoding
  // so the disc never flashes empty between albums.
  ui.Image? _lastArt;

  final _face = DiscFaceCache();

  @override
  void initState() {
    super.initState();
    _shownPos = ValueNotifier(ref.read(playbackControllerProvider).position);
    _ticker = createTicker(_onTick)..start();
    _fx = AnimationController(vsync: this, duration: _mood.duration);
    // Play the entrance once for whatever is already playing.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final track = ref.read(playbackControllerProvider).currentTrack;
      if (track != null) _startAlbumTransition(track.albumArtPath);
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    _fx.dispose();
    _angle.dispose();
    _shownPos.dispose();
    _face.dispose();
    super.dispose();
  }

  bool get _reduceMotion =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  void _onTick(Duration elapsed) {
    final dt = ((elapsed - _lastTick).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _lastTick = elapsed;
    if (_scrubbing) return;
    final playing = ref.read(playbackControllerProvider).isPlaying;
    final target = playing ? _spinSpeed * (_reduceMotion ? 0.35 : 1) : 0.0;
    _speed += (target - _speed) * math.min(1.0, dt * 2.5);
    // Idle and settled: stop ticking, so a paused disc costs no frames at
    // all. [_wake] restarts it.
    if (_speed.abs() < 0.002 && target == 0) {
      _speed = 0;
      _ticker.stop();
      return;
    }
    _angle.value = (_angle.value + _speed * dt) % (2 * math.pi);
  }

  /// Restarts the spin ticker after it stopped itself at rest.
  void _wake() {
    if (_ticker.isActive) return;
    _lastTick = Duration.zero;
    _ticker.start();
  }

  Future<void> _startAlbumTransition(String? artPath) async {
    final mood = await ref.read(_discMoodProvider(artPath).future);
    if (!mounted) return;
    setState(() => _mood = mood);
    if (_reduceMotion) {
      _fx.value = 1;
      return;
    }
    _fx.duration = mood.duration;
    // A little kick of extra spin as the new record lands.
    _speed += mood == DiscMood.stark ? -6 : 5;
    _wake();
    unawaited(_fx.forward(from: 0));
  }

  // --- scrubbing ------------------------------------------------------------

  double _pointerAngle(Offset local, Size size) =>
      math.atan2(local.dy - size.height / 2, local.dx - size.width / 2);

  void _scrubStart(DragStartDetails d, Size size) {
    final playback = ref.read(playbackControllerProvider);
    if (playback.currentTrack == null) return;
    setState(() => _scrubbing = true);
    _shownPos.value = playback.position;
    _speed = 0;
    _lastPointerAngle = _pointerAngle(d.localPosition, size);
  }

  void _scrubUpdate(DragUpdateDetails d, Size size) {
    if (!_scrubbing) return;
    final a = _pointerAngle(d.localPosition, size);
    var delta = a - _lastPointerAngle;
    if (delta > math.pi) delta -= 2 * math.pi;
    if (delta < -math.pi) delta += 2 * math.pi;
    _lastPointerAngle = a;
    _angle.value += delta;
    final int maxMs = math.max(
      0,
      ref.read(playbackControllerProvider).duration.inMilliseconds,
    );
    final int ms =
        _shownPos.value.inMilliseconds +
        (delta / (2 * math.pi) * _secondsPerTurn * 1000).round();
    _shownPos.value = Duration(milliseconds: ms.clamp(0, maxMs).toInt());
  }

  void _scrubEnd() {
    if (!_scrubbing) return;
    ref.read(playbackControllerProvider.notifier).seek(_shownPos.value);
    setState(() => _scrubbing = false);
    _wake();
  }

  // --- seek bar (OLED panel) ------------------------------------------------

  /// Shows [fraction] of the song on the clock and the arc without seeking.
  void _barPreview(double fraction) {
    final duration = ref.read(playbackControllerProvider).duration;
    if (duration <= Duration.zero) return;
    _barSeeking = true;
    _shownPos.value = duration * fraction.clamp(0.0, 1.0);
  }

  /// Seeks to [fraction] (a tap), or to the previewed spot (end of a drag).
  Future<void> _barCommit([double? fraction]) async {
    if (fraction != null) _barPreview(fraction);
    if (!_barSeeking) return;
    await ref.read(playbackControllerProvider.notifier).seek(_shownPos.value);
    _barSeeking = false;
  }

  void _barCancel() {
    _barSeeking = false;
    _shownPos.value = ref.read(playbackControllerProvider).position;
  }

  void _wheelScrub(PointerSignalEvent e) {
    if (e is! PointerScrollEvent) return;
    final playback = ref.read(playbackControllerProvider);
    if (playback.currentTrack == null) return;
    final step = e.scrollDelta.dy > 0 ? -5 : 5;
    final int maxMs = math.max(0, playback.duration.inMilliseconds);
    final int ms = (playback.position.inMilliseconds + step * 1000)
        .clamp(0, maxMs)
        .toInt();
    _angle.value += step / _secondsPerTurn * 2 * math.pi;
    ref
        .read(playbackControllerProvider.notifier)
        .seek(Duration(milliseconds: ms));
  }

  void _openLyrics(Track track) {
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 420),
        reverseTransitionDuration: const Duration(milliseconds: 320),
        pageBuilder: (_, _, _) => LyricsScreen(track: track),
        transitionsBuilder: (_, animation, _, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          );
          return SlideTransition(
            position: Tween(
              begin: const Offset(1, 0),
              end: Offset.zero,
            ).animate(curved),
            child: FadeTransition(opacity: curved, child: child),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    // Rebuild for everything except position, which ticks many times a
    // second and only reaches the arc and the clock (through _shownPos).
    // Lists compare by identity, which is right: the controller replaces
    // them rather than mutating.
    ref.watch(
      playbackControllerProvider.select(
        (s) => (
          s.currentTrack,
          s.queue,
          s.order,
          s.orderIndex,
          s.shuffleEnabled,
          s.repeatMode,
          s.isPlaying,
          s.duration,
        ),
      ),
    );
    final playback = ref.read(playbackControllerProvider);
    final controller = ref.read(playbackControllerProvider.notifier);
    final track = playback.currentTrack;

    // New album → new entrance. Keyed on the album (falling back to the art
    // path) so skipping songs within one album doesn't replay it.
    ref.listen<String?>(
      playbackControllerProvider.select((s) {
        final t = s.currentTrack;
        if (t == null) return null;
        return '${t.albumId ?? t.album}|${t.albumArtPath}';
      }),
      (prev, next) {
        if (next == null || prev == next) return;
        _startAlbumTransition(
          ref.read(playbackControllerProvider).currentTrack?.albumArtPath,
        );
      },
    );
    // Every track change nudges the disc, album or not.
    ref.listen<int?>(
      playbackControllerProvider.select((s) => s.currentTrack?.id),
      (prev, next) {
        if (prev != null && next != null && prev != next && !_reduceMotion) {
          _speed += 3;
          _wake();
        }
      },
    );
    ref.listen<bool>(
      playbackControllerProvider.select((s) => s.isPlaying),
      (_, _) => _wake(),
    );
    ref.listen<Duration>(playbackControllerProvider.select((s) => s.position), (
      _,
      pos,
    ) {
      if (!_scrubbing && !_barSeeking) _shownPos.value = pos;
    });

    final art = ref.watch(_discArtProvider(track?.albumArtPath));
    final image = art.valueOrNull ?? (art.isLoading ? _lastArt : null);
    if (art.hasValue) _lastArt = art.valueOrNull;

    // What the OLED lists. Normally the play queue, in play order. When the
    // queue is just this one song (e.g. MysticJam resumed it on launch), list
    // its whole album instead, so the panel and prev/next still make sense;
    // picking from it switches the queue over to that album.
    final queueSongs = [for (final i in playback.order) playback.queue[i]];
    List<Track>? albumSongs;
    if (track?.albumId != null && queueSongs.length <= 1) {
      final albums = ref.watch(albumsProvider).valueOrNull;
      for (final a in albums ?? const <AlbumWithTracks>[]) {
        if (a.id == track!.albumId && a.tracks.length > 1) {
          albumSongs = _albumOrder(a.tracks);
          break;
        }
      }
    }
    final browse = albumSongs;
    final songs = browse ?? queueSongs;
    final current = browse != null
        ? browse.indexWhere((t) => t.id == track?.id)
        : playback.orderIndex;
    Future<void> pick(int i) => browse != null
        ? controller.playFromQueue(browse, i)
        : controller.jumpToOrderIndex(i);
    final VoidCallback? onPrevious = browse != null
        ? (current > 0 ? () => pick(current - 1) : null)
        : (playback.hasPrevious ? controller.previous : null);
    final VoidCallback? onNext = browse != null
        ? (current >= 0 && current < browse.length - 1
              ? () => pick(current + 1)
              : null)
        : (playback.hasNext ? controller.next : null);

    final colors = theme.colors;
    final body = Color.lerp(colors.surface, colors.background, 0.35)!;

    final device = LayoutBuilder(
      builder: (context, constraints) {
        // Disc takes what's left after the keys and the OLED panel.
        const keysHeight = _keysHeight;
        const panelHeight = _panelHeight;
        const chrome = _chromeHeight;
        final discSize = math
            .min(
              constraints.maxWidth - 36,
              constraints.maxHeight - keysHeight - panelHeight - chrome,
            )
            .clamp(_minDisc, 420.0);
        final face = _face.resolve(
          image,
          radius: _restRadius(discSize),
          pixelRatio: MediaQuery.devicePixelRatioOf(context),
          tint: colors.primary,
        );

        return Container(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.lerp(body, colors.textPrimary, 0.05)!,
                Color.lerp(body, Colors.black, 0.25)!,
              ],
            ),
            border: Border.all(color: colors.line),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 30,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _BrandRow(theme: theme, format: track?.format),
              const SizedBox(height: 16),
              SizedBox.square(
                dimension: discSize,
                child: _Disc(
                  face: face,
                  hasArt: image != null,
                  angle: _angle,
                  fx: _fx,
                  mood: _mood,
                  position: _shownPos,
                  duration: playback.duration,
                  colors: colors,
                  scrubbing: _scrubbing,
                  enabled: track != null,
                  onTap: controller.togglePlayPause,
                  onPanStart: (d) => _scrubStart(d, Size.square(discSize)),
                  onPanUpdate: (d) => _scrubUpdate(d, Size.square(discSize)),
                  onPanEnd: (_) => _scrubEnd(),
                  onPointerSignal: _wheelScrub,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: keysHeight,
                child: _KeysRow(
                  theme: theme,
                  playback: playback,
                  onPrevious: onPrevious,
                  onNext: onNext,
                  onPlay: track == null ? null : controller.togglePlayPause,
                  onLoop: controller.cycleRepeatMode,
                  onLyrics: track == null ? null : () => _openLyrics(track),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: panelHeight,
                child: _OledPanel(
                  theme: theme,
                  playback: playback,
                  songs: songs,
                  current: current,
                  forceAlbum: browse != null,
                  position: _shownPos,
                  onPick: pick,
                  onSeekPreview: _barPreview,
                  onSeekCommit: _barCommit,
                  onSeekCancel: _barCancel,
                ),
              ),
            ],
          ),
        );
      },
    );

    const needed = _minDisc + _keysHeight + _panelHeight + _chromeHeight + 16;
    return LayoutBuilder(
      builder: (context, outer) {
        final fits = outer.maxHeight >= needed;
        final content = Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: _AlbumTransition(
              animation: _fx,
              mood: _mood,
              accent: colors.primary,
              child: fits
                  ? device
                  : SizedBox(height: needed - 16, child: device),
            ),
          ),
        );
        // Phones always fit, so the disc's drag never fights a scroll view;
        // only a very short desktop window falls back to scrolling.
        return fits
            ? Center(child: content)
            : SingleChildScrollView(child: Center(child: content));
      },
    );
  }
}

/// Album order: by track number, unknown numbers last (same rule as the
/// album screen).
List<Track> _albumOrder(List<Track> tracks) {
  final sorted = [...tracks];
  sorted.sort((a, b) {
    final an = a.trackNumber;
    final bn = b.trackNumber;
    if (an == null && bn == null) return 0;
    if (an == null) return 1;
    if (bn == null) return -1;
    return an.compareTo(bn);
  });
  return sorted;
}

// ---------------------------------------------------------------------------
// Album transition wrapper (whole device)
// ---------------------------------------------------------------------------

class _AlbumTransition extends StatelessWidget {
  final AnimationController animation;
  final DiscMood mood;
  final Color accent;
  final Widget child;

  const _AlbumTransition({
    required this.animation,
    required this.mood,
    required this.accent,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        // The widget tree keeps the same shape whether or not an effect is
        // running, so the device below is never rebuilt from scratch (the
        // track list would lose its scroll position otherwise).
        final running = animation.isAnimating && animation.value < 1;
        final t = running ? animation.value : 1.0;

        var jitter = 0.0;
        var scale = 1.0;
        var opacity = 1.0;
        var sigma = 0.0;
        final step = (t * 14).floor();
        if (running) {
          switch (mood) {
            case DiscMood.stark:
              final rnd = math.Random(step * 7919);
              jitter = (rnd.nextDouble() - 0.5) * 22 * (1 - t);
            case DiscMood.vivid:
              scale = 0.9 + 0.1 * Curves.elasticOut.transform(t);
            case DiscMood.soft:
              final e = Curves.easeOutCubic.transform(t);
              sigma = 14 * (1 - e);
              opacity = (0.25 + 0.75 * e).clamp(0.0, 1.0);
          }
        }

        return Stack(
          children: [
            ImageFiltered(
              enabled: sigma > 0.3,
              imageFilter: ui.ImageFilter.blur(
                sigmaX: math.max(sigma, 0.01),
                sigmaY: math.max(sigma, 0.01),
              ),
              child: Opacity(
                opacity: opacity,
                child: Transform.translate(
                  offset: Offset(jitter, 0),
                  child: Transform.scale(scale: scale, child: child),
                ),
              ),
            ),
            if (running && mood == DiscMood.stark)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _GlitchPainter(t: t, step: step, accent: accent),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _GlitchPainter extends CustomPainter {
  final double t;
  final int step;
  final Color accent;

  _GlitchPainter({required this.t, required this.step, required this.accent});

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(step * 104729 + 1);
    final fade = 1 - t;
    final palette = [accent, Colors.white, Colors.black];
    for (var i = 0; i < 9; i++) {
      final y = rnd.nextDouble() * size.height;
      final h = 2 + rnd.nextDouble() * 26;
      final x = (rnd.nextDouble() - 0.5) * size.width * 0.4;
      final w = size.width * (0.3 + rnd.nextDouble() * 0.9);
      final c = palette[rnd.nextInt(palette.length)];
      canvas.drawRect(
        Rect.fromLTWH(x, y, w, h),
        Paint()..color = c.withValues(alpha: 0.55 * fade),
      );
    }
    // Two hard white flashes.
    if ((t > 0.18 && t < 0.24) || (t > 0.52 && t < 0.56)) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = Colors.white.withValues(alpha: 0.35),
      );
    }
  }

  @override
  bool shouldRepaint(_GlitchPainter old) => old.step != step || old.t != t;
}

// ---------------------------------------------------------------------------
// Brand row
// ---------------------------------------------------------------------------

class _BrandRow extends StatelessWidget {
  final AppTheme theme;
  final String? format;

  const _BrandRow({required this.theme, required this.format});

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      color: theme.colors.textSecondary,
      fontSize: 10,
      fontWeight: FontWeight.w700,
      letterSpacing: 2.4,
    );
    return SizedBox(
      height: _brandHeight,
      child: Row(
        children: [
          Text('MYSTICJAM', style: style),
          const Spacer(),
          if (format != null) Text(format!.toUpperCase(), style: style),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Disc
// ---------------------------------------------------------------------------

/// Disc radius at rest (before the heartbeat pulse) in a [side]-wide box.
double _restRadius(double side) => side / 2 - 6;

/// Progress through the album entrance, or 1 when none is running.
double _fxT(AnimationController fx) => fx.isAnimating ? fx.value : 1.0;

/// Heartbeat pulse for soft albums: two beats, then rest.
double _heartbeat(DiscMood mood, double t) {
  if (mood != DiscMood.soft || t >= 1) return 1;
  double beat(double at) => math.exp(-math.pow((t - at) / 0.05, 2));
  return 1 + 0.04 * beat(0.4) + 0.03 * beat(0.58);
}

class _Disc extends StatelessWidget {
  final ui.Image? face;
  final bool hasArt;
  final ValueNotifier<double> angle;
  final AnimationController fx;
  final DiscMood mood;
  final ValueListenable<Duration> position;
  final Duration duration;
  final AppColorScheme colors;
  final bool scrubbing;
  final bool enabled;
  final VoidCallback onTap;
  final GestureDragStartCallback onPanStart;
  final GestureDragUpdateCallback onPanUpdate;
  final GestureDragEndCallback onPanEnd;
  final void Function(PointerSignalEvent) onPointerSignal;

  const _Disc({
    required this.face,
    required this.hasArt,
    required this.angle,
    required this.fx,
    required this.mood,
    required this.position,
    required this.duration,
    required this.colors,
    required this.scrubbing,
    required this.enabled,
    required this.onTap,
    required this.onPanStart,
    required this.onPanUpdate,
    required this.onPanEnd,
    required this.onPointerSignal,
  });

  @override
  Widget build(BuildContext context) {
    // Three layers, each behind its own repaint boundary, so each repaints
    // only for what it shows: the spinning face every frame (one textured
    // draw), the progress overlay on position ticks, the shadow only during
    // an album entrance.
    Widget layer(CustomPainter painter) => Positioned.fill(
      child: RepaintBoundary(child: CustomPaint(painter: painter)),
    );
    return Semantics(
      label: 'Disc. Tap to play or pause, drag around to scrub.',
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.grab : SystemMouseCursors.basic,
        child: Listener(
          onPointerSignal: enabled ? onPointerSignal : null,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: enabled ? onTap : null,
            onPanStart: enabled ? onPanStart : null,
            onPanUpdate: enabled ? onPanUpdate : null,
            onPanEnd: enabled ? onPanEnd : null,
            onPanCancel: enabled ? () => onPanEnd(DragEndDetails()) : null,
            child: Stack(
              alignment: Alignment.center,
              children: [
                layer(_DiscBackPainter(fx: fx, mood: mood, colors: colors)),
                layer(
                  _DiscSpinPainter(
                    face: face,
                    glitch: hasArt,
                    angle: angle,
                    fx: fx,
                    mood: mood,
                  ),
                ),
                layer(
                  _DiscFrontPainter(
                    position: position,
                    duration: duration,
                    fx: fx,
                    mood: mood,
                    colors: colors,
                  ),
                ),
                AnimatedOpacity(
                  opacity: scrubbing ? 1 : 0,
                  duration: const Duration(milliseconds: 150),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: ValueListenableBuilder<Duration>(
                      valueListenable: position,
                      builder: (_, pos, _) => Text(
                        formatDuration(pos),
                        style: _oledText(24, colors.primary, glow: true),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The part of the disc that turns — cover (or silver CD), grooves and the
/// spin marker, clipped to a ring — drawn once into a texture. Spinning is
/// then a single rotated image draw per frame instead of re-recording ~60
/// paths, clips and gradients, which is what keeps it smooth at 120 Hz.
@visibleForTesting
class DiscFaceCache {
  ui.Image? _image;
  Object? _key;

  /// The face for [art] at [radius] logical pixels. Rebuilt only when the
  /// cover, tint or pixel size bucket changes; sizes are rounded up to a
  /// 64 px step so dragging a window edge doesn't re-bake every frame (the
  /// painter scales the slightly larger texture down).
  ui.Image? resolve(
    ui.Image? art, {
    required double radius,
    required double pixelRatio,
    required Color tint,
  }) {
    if (radius <= 0) return null;
    final px = ((radius * 2 * pixelRatio / 64).ceil() * 64).clamp(64, 4096);
    final key = (art, px, art == null ? tint : null);
    if (key == _key && _image != null) return _image;

    final r = px / 2;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.clipPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addOval(Rect.fromCircle(center: Offset(r, r), radius: r))
        ..addOval(Rect.fromCircle(center: Offset(r, r), radius: r * 0.07)),
    );
    canvas.translate(r, r);
    final dst = Rect.fromCircle(center: Offset.zero, radius: r);
    if (art != null) {
      final side = math.min(art.width, art.height).toDouble();
      final src = Rect.fromCenter(
        center: Offset(art.width / 2, art.height / 2),
        width: side,
        height: side,
      );
      canvas.drawImageRect(
        art,
        src,
        dst,
        Paint()..filterQuality = FilterQuality.medium,
      );
    } else {
      // No cover: a plain silver CD tinted with the theme.
      canvas.drawRect(
        dst,
        Paint()
          ..shader = SweepGradient(
            colors: [
              const Color(0xFFE6E9EE),
              Color.lerp(const Color(0xFF8A9099), tint, 0.25)!,
              const Color(0xFFF4F6F8),
              const Color(0xFF6C727A),
              const Color(0xFFE6E9EE),
            ],
          ).createShader(dst),
      );
    }

    // Grooves, spaced 3 logical px apart whatever the texture resolution.
    final step = 3 * px / (radius * 2);
    final groove = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = step / 3;
    for (var rr = r * 0.3; rr < r; rr += step) {
      groove.color = Colors.black.withValues(
        alpha: 0.05 + 0.035 * math.sin(rr / step * 3),
      );
      canvas.drawCircle(Offset.zero, rr, groove);
    }
    // A marker so the spin is visible on symmetric covers.
    canvas.drawRect(
      Rect.fromLTWH(-r * 0.008, -r * 0.97, r * 0.016, r * 0.12),
      Paint()..color = Colors.white.withValues(alpha: 0.85),
    );

    final picture = recorder.endRecording();
    // Safe to dispose while a frame still shows it: the engine keeps its own
    // reference until that frame is gone.
    _image?.dispose();
    _image = picture.toImageSync(px, px);
    picture.dispose();
    _key = key;
    return _image;
  }

  void dispose() {
    _image?.dispose();
    _image = null;
  }
}

/// Behind the disc: drop shadow, and the burst rings of a vivid entrance.
class _DiscBackPainter extends CustomPainter {
  final AnimationController fx;
  final DiscMood mood;
  final AppColorScheme colors;

  _DiscBackPainter({required this.fx, required this.mood, required this.colors})
    : super(repaint: fx);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final t = _fxT(fx);
    final r = _restRadius(size.shortestSide) * _heartbeat(mood, t);

    if (mood == DiscMood.vivid && t < 1) {
      final ringColors = [colors.primary, colors.accent, colors.textPrimary];
      for (var i = 0; i < 3; i++) {
        final p = ((t - i * 0.12) / 0.7).clamp(0.0, 1.0);
        if (p <= 0) continue;
        canvas.drawCircle(
          c,
          r * (0.9 + p * 1.6),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 8 * (1 - p) + 1
            ..color = ringColors[i].withValues(alpha: 0.7 * (1 - p)),
        );
      }
    }

    canvas.drawShadow(
      Path()..addOval(Rect.fromCircle(center: c.translate(0, 4), radius: r)),
      Colors.black,
      14,
      false,
    );
  }

  @override
  bool shouldRepaint(_DiscBackPainter old) =>
      old.mood != mood || old.colors != colors;
}

/// The turning face: the cached texture, rotated. Repaints every frame while
/// spinning, so it does as little as possible.
class _DiscSpinPainter extends CustomPainter {
  final ui.Image? face;
  final bool glitch;
  final ValueNotifier<double> angle;
  final AnimationController fx;
  final DiscMood mood;

  _DiscSpinPainter({
    required this.face,
    required this.glitch,
    required this.angle,
    required this.fx,
    required this.mood,
  }) : super(repaint: Listenable.merge([angle, fx]));

  @override
  void paint(Canvas canvas, Size size) {
    final img = face;
    if (img == null) return;
    final t = _fxT(fx);
    final r = _restRadius(size.shortestSide) * _heartbeat(mood, t);
    final src = Rect.fromLTWH(
      0,
      0,
      img.width.toDouble(),
      img.height.toDouble(),
    );
    final dst = Rect.fromCircle(center: Offset.zero, radius: r);

    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(angle.value);
    canvas.drawImageRect(
      img,
      src,
      dst,
      Paint()..filterQuality = FilterQuality.low,
    );

    // Glitch: RGB split while a stark album lands.
    if (glitch && mood == DiscMood.stark && t < 0.7) {
      final split = r * 0.05 * (1 - t / 0.7);
      for (final (color, dx) in [
        (const Color(0xFFFF0040), split),
        (const Color(0xFF00E5FF), -split),
      ]) {
        canvas.drawImageRect(
          img,
          src,
          dst.shift(Offset(dx, 0)),
          Paint()
            ..filterQuality = FilterQuality.low
            ..colorFilter = ColorFilter.mode(color, BlendMode.modulate)
            ..blendMode = BlendMode.screen,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_DiscSpinPainter old) =>
      old.face != face || old.glitch != glitch || old.mood != mood;
}

/// Fixed on top of the turning face: light sheen, clear hub, rim, and the
/// progress arc with its hand (12 o'clock is the start of the song).
class _DiscFrontPainter extends CustomPainter {
  final ValueListenable<Duration> position;
  final Duration duration;
  final AnimationController fx;
  final DiscMood mood;
  final AppColorScheme colors;

  _DiscFrontPainter({
    required this.position,
    required this.duration,
    required this.fx,
    required this.mood,
    required this.colors,
  }) : super(repaint: Listenable.merge([position, fx]));

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = _restRadius(size.shortestSide) * _heartbeat(mood, _fxT(fx));
    final hole = r * 0.07;

    // Fixed light sheen across the surface (doesn't rotate, so the disc
    // looks like it's turning under a light).
    canvas.save();
    canvas.clipPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addOval(Rect.fromCircle(center: c, radius: r))
        ..addOval(Rect.fromCircle(center: c, radius: hole)),
    );
    canvas.drawRect(
      Rect.fromCircle(center: c, radius: r),
      Paint()
        ..shader = SweepGradient(
          center: Alignment.center,
          startAngle: 0,
          endAngle: 2 * math.pi,
          transform: const GradientRotation(-0.7),
          colors: [
            Colors.transparent,
            const Color(0x40FF78BE),
            const Color(0x38FFE678),
            const Color(0x335AFFD2),
            Colors.transparent,
            Colors.transparent,
            const Color(0x2E78C8FF),
            Colors.transparent,
          ],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
    canvas.restore();

    // Clear hub.
    canvas.drawCircle(
      c,
      r * 0.2,
      Paint()..color = Colors.white.withValues(alpha: 0.22),
    );
    canvas.drawCircle(
      c,
      r * 0.14,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.black.withValues(alpha: 0.2),
    );
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.black.withValues(alpha: 0.25),
    );

    final ms = duration.inMilliseconds;
    final progress = ms <= 0
        ? 0.0
        : (position.value.inMilliseconds / ms).clamp(0.0, 1.0);
    final pr = r * 0.8;
    final arcRect = Rect.fromCircle(center: c, radius: pr);
    final start = -math.pi / 2;
    final sweep = progress * 2 * math.pi;
    final end = start + sweep;
    final tip = c + Offset(math.cos(end) * pr, math.sin(end) * pr);
    final accent = colors.primary;

    canvas.drawCircle(
      c,
      pr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.035
        ..color = Colors.black.withValues(alpha: 0.28),
    );
    if (sweep > 0) {
      canvas.drawArc(
        arcRect,
        start,
        sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = r * 0.06
          ..color = accent.withValues(alpha: 0.5)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
      canvas.drawArc(
        arcRect,
        start,
        sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = r * 0.035
          ..color = accent,
      );
    }
    canvas.drawLine(
      c,
      tip,
      Paint()
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..color = accent,
    );
    canvas.drawCircle(tip, r * 0.03, Paint()..color = accent);
    canvas.drawCircle(c, r * 0.05, Paint()..color = const Color(0xFF111111));
    canvas.drawCircle(c, r * 0.025, Paint()..color = accent);
  }

  @override
  bool shouldRepaint(_DiscFrontPainter old) =>
      old.position != position ||
      old.duration != duration ||
      old.mood != mood ||
      old.colors != colors;
}

// ---------------------------------------------------------------------------
// Keys
// ---------------------------------------------------------------------------

class _KeysRow extends StatelessWidget {
  final AppTheme theme;
  final PlaybackState playback;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback? onPlay;
  final VoidCallback onLoop;
  final VoidCallback? onLyrics;

  const _KeysRow({
    required this.theme,
    required this.playback,
    required this.onPrevious,
    required this.onNext,
    required this.onPlay,
    required this.onLoop,
    required this.onLyrics,
  });

  @override
  Widget build(BuildContext context) {
    final repeat = playback.repeatMode;
    final loopLabel = switch (repeat) {
      PlayerRepeatMode.off => 'Loop: off',
      PlayerRepeatMode.all => 'Loop: whole album',
      PlayerRepeatMode.one => 'Loop: this song',
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: _DeviceKey(
            theme: theme,
            tooltip: 'Previous',
            onPressed: onPrevious,
            icon: ThemedIconSlot.previous,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _DeviceKey(
            theme: theme,
            tooltip: 'Next',
            onPressed: onNext,
            icon: ThemedIconSlot.next,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 3,
          child: _DeviceKey(
            theme: theme,
            tooltip: playback.isPlaying ? 'Pause' : 'Play',
            onPressed: onPlay,
            icon: playback.isPlaying
                ? ThemedIconSlot.pause
                : ThemedIconSlot.play,
            primary: true,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _DeviceKey(
            theme: theme,
            tooltip: loopLabel,
            onPressed: onLoop,
            icon: repeat == PlayerRepeatMode.one
                ? ThemedIconSlot.repeatOne
                : ThemedIconSlot.repeat,
            lit: repeat != PlayerRepeatMode.off,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _DeviceKey(
            theme: theme,
            tooltip: 'Lyrics',
            onPressed: onLyrics,
            icon: ThemedIconSlot.lyrics,
          ),
        ),
      ],
    );
  }
}

/// A chunky hardware-style key: sinks a few pixels while pressed, and has a
/// small LED that lights for toggles (loop).
class _DeviceKey extends StatefulWidget {
  final AppTheme theme;
  final String tooltip;
  final VoidCallback? onPressed;
  final ThemedIconSlot icon;
  final bool primary;
  final bool lit;

  const _DeviceKey({
    required this.theme,
    required this.tooltip,
    required this.onPressed,
    required this.icon,
    this.primary = false,
    this.lit = false,
  });

  @override
  State<_DeviceKey> createState() => _DeviceKeyState();
}

class _DeviceKeyState extends State<_DeviceKey> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.theme.colors;
    final enabled = widget.onPressed != null;
    final fill = widget.primary
        ? c.primary
        : Color.lerp(c.surface, c.textPrimary, 0.07)!;
    final fg = widget.primary ? c.onPrimary : c.controlActive;
    const depth = 4.0;

    return Tooltip(
      message: widget.tooltip,
      child: Semantics(
        button: true,
        enabled: enabled,
        toggled:
            widget.icon == ThemedIconSlot.repeat ||
                widget.icon == ThemedIconSlot.repeatOne
            ? widget.lit
            : null,
        label: widget.tooltip,
        excludeSemantics: true,
        child: Opacity(
          opacity: enabled ? 1 : 0.4,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 70),
            margin: EdgeInsets.only(
              top: _down ? depth : 0,
              bottom: _down ? 0 : depth,
            ),
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: c.line),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.45),
                  offset: Offset(0, _down ? 0 : depth),
                ),
              ],
            ),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: widget.onPressed,
                onHighlightChanged: (v) => setState(() => _down = v),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    ThemedIcon(
                      widget.icon,
                      size: widget.primary ? 26 : 20,
                      color: fg,
                    ),
                    if (!widget.primary)
                      Positioned(
                        top: 6,
                        right: 7,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: widget.lit
                                ? c.primary
                                : Colors.white.withValues(alpha: 0.1),
                            boxShadow: widget.lit
                                ? [BoxShadow(color: c.primary, blurRadius: 8)]
                                : null,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// OLED panel
// ---------------------------------------------------------------------------

const _monoFallback = [
  'JetBrains Mono',
  'DejaVu Sans Mono',
  'Noto Sans Mono',
  'Roboto Mono',
  'Consolas',
  'Courier New',
];

TextStyle _oledText(
  double size,
  Color color, {
  bool glow = false,
  FontWeight weight = FontWeight.w500,
  double spacing = 0,
}) => TextStyle(
  fontFamily: 'monospace',
  fontFamilyFallback: _monoFallback,
  fontSize: size,
  fontWeight: weight,
  letterSpacing: spacing,
  height: 1.1,
  color: color,
  fontFeatures: const [FontFeature.tabularFigures()],
  shadows: glow
      ? [Shadow(color: color.withValues(alpha: 0.6), blurRadius: 6)]
      : null,
);

class _OledPanel extends StatefulWidget {
  final AppTheme theme;
  final PlaybackState playback;
  final ValueListenable<Duration> position;
  final List<Track> songs;

  /// Index of the playing song within [songs]; -1 if it isn't in the list.
  final int current;
  final bool forceAlbum;
  final Future<void> Function(int index) onPick;

  /// Seek bar: preview a fraction of the song while dragging, commit it (a
  /// tap passes its fraction; the end of a drag passes null), or cancel.
  final ValueChanged<double> onSeekPreview;
  final Future<void> Function([double? fraction]) onSeekCommit;
  final VoidCallback onSeekCancel;

  const _OledPanel({
    required this.theme,
    required this.playback,
    required this.position,
    required this.songs,
    required this.current,
    required this.forceAlbum,
    required this.onPick,
    required this.onSeekPreview,
    required this.onSeekCommit,
    required this.onSeekCancel,
  });

  @override
  State<_OledPanel> createState() => _OledPanelState();
}

class _OledPanelState extends State<_OledPanel> {
  static const _rowHeight = 24.0;
  final _scroll = ScrollController();

  @override
  void didUpdateWidget(_OledPanel old) {
    super.didUpdateWidget(old);
    if (old.current != widget.current) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _scrollTo(widget.current, animate: true),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _scrollTo(widget.current, animate: false),
    );
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _scrollTo(int index, {required bool animate}) {
    if (!_scroll.hasClients || index < 0) return;
    final target = ((index - 1) * _rowHeight).clamp(
      0.0,
      _scroll.position.maxScrollExtent,
    );
    if (animate) {
      _scroll.animateTo(
        target,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    } else {
      _scroll.jumpTo(target);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.theme.colors;
    final pb = widget.playback;
    final track = pb.currentTrack;
    final pix = Color.lerp(c.primary, Colors.white, 0.55)!;
    final dim = pix.withValues(alpha: 0.45);
    const oled = Color(0xFF000000);

    // Songs in the order they'll actually play.
    final songs = widget.songs;
    final current = widget.current;
    final isAlbum =
        widget.forceAlbum ||
        (songs.isNotEmpty &&
            songs.every(
              (s) =>
                  (s.albumId ?? s.album) ==
                  (songs.first.albumId ?? songs.first.album),
            ));
    final title = track == null
        ? 'NOTHING PLAYING'
        : isAlbum
        ? (track.album ?? 'Unknown album').toUpperCase()
        : 'QUEUE';
    final subtitle = track == null
        ? 'Pick an album to start'
        : [
            track.albumArtist ?? track.artist,
            if (isAlbum) track.year?.toString(),
          ].whereType<String>().join(' · ');

    final dur = pb.duration;

    Widget flag(String label, bool on) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: on ? pix : Colors.transparent,
        border: Border.all(color: on ? pix : dim),
      ),
      child: Text(label, style: _oledText(10, on ? oled : dim, spacing: 1)),
    );

    return Container(
      decoration: BoxDecoration(
        color: oled,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text(
                      isAlbum ? 'ALBUM' : 'PLAYING FROM',
                      style: _oledText(11, dim, spacing: 2),
                    ),
                    const Spacer(),
                    if (songs.isNotEmpty)
                      Text(
                        '${(math.max(current, 0) + 1).toString().padLeft(2, '0')}/'
                        '${songs.length.toString().padLeft(2, '0')}',
                        style: _oledText(11, dim, spacing: 1),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _oledText(
                    20,
                    pix,
                    glow: true,
                    weight: FontWeight.w700,
                    spacing: 0.5,
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _oledText(13, dim),
                  ),
                ],
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Container(height: 1, color: dim),
                ),
                Expanded(
                  child: ListView.builder(
                    controller: _scroll,
                    itemExtent: _rowHeight,
                    itemCount: songs.length,
                    itemBuilder: (context, i) {
                      final song = songs[i];
                      final playing = i == current;
                      final fg = playing ? oled : pix;
                      final fgDim = playing ? oled : dim;
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => widget.onPick(i),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            color: playing ? pix : Colors.transparent,
                            borderRadius: BorderRadius.circular(2),
                          ),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 14,
                                child: Text(
                                  playing ? (pb.isPlaying ? '▶' : '■') : '',
                                  style: _oledText(11, fg),
                                ),
                              ),
                              SizedBox(
                                width: 26,
                                child: Text(
                                  (song.trackNumber ?? i + 1)
                                      .toString()
                                      .padLeft(2, '0'),
                                  style: _oledText(14, fgDim),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  song.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: _oledText(14, fg),
                                ),
                              ),
                              if (song.durationMs != null)
                                Padding(
                                  padding: const EdgeInsets.only(left: 8),
                                  child: Text(
                                    formatDuration(
                                      Duration(milliseconds: song.durationMs!),
                                    ),
                                    style: _oledText(13, fgDim),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                if (track != null) _OledVolumeSlider(pix: pix, dim: dim),
                // The only part of the panel that follows the position, so
                // it alone rebuilds on each tick.
                ValueListenableBuilder<Duration>(
                  valueListenable: widget.position,
                  builder: (context, pos, _) {
                    final frac = dur.inMilliseconds <= 0
                        ? 0.0
                        : (pos.inMilliseconds / dur.inMilliseconds).clamp(
                            0.0,
                            1.0,
                          );
                    return Row(
                      children: [
                        Text(
                          formatDuration(pos),
                          style: _oledText(13, pix, glow: true),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _OledSeekBar(
                            fraction: frac,
                            pix: pix,
                            enabled: track != null && dur > Duration.zero,
                            onPreview: widget.onSeekPreview,
                            onCommit: widget.onSeekCommit,
                            onCancel: widget.onSeekCancel,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          formatDuration(dur),
                          style: _oledText(13, pix, glow: true),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    flag(pb.isPlaying ? 'PLAY' : 'PAUSE', pb.isPlaying),
                    const SizedBox(width: 6),
                    flag(switch (pb.repeatMode) {
                      PlayerRepeatMode.off => 'LOOP',
                      PlayerRepeatMode.all => 'LOOP ALL',
                      PlayerRepeatMode.one => 'LOOP 1',
                    }, pb.repeatMode != PlayerRepeatMode.off),
                    const SizedBox(width: 6),
                    flag('SHUF', pb.shuffleEnabled),
                  ],
                ),
              ],
            ),
          ),
          // Scanlines.
          const Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: _ScanlinePainter()),
            ),
          ),
        ],
      ),
    );
  }
}

/// The OLED clock row's progress bar, made seekable: tap to jump, or drag
/// to preview (clock and disc arc follow) and seek on release. The bar stays
/// 5 px tall; the touch area around it is taller so it's easy to hit.
class _OledSeekBar extends StatelessWidget {
  final double fraction;
  final Color pix;
  final bool enabled;
  final ValueChanged<double> onPreview;
  final Future<void> Function([double? fraction]) onCommit;
  final VoidCallback onCancel;

  const _OledSeekBar({
    required this.fraction,
    required this.pix,
    required this.enabled,
    required this.onPreview,
    required this.onCommit,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final bar = Container(
      height: 5,
      color: Colors.white.withValues(alpha: 0.08),
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: fraction,
        heightFactor: 1,
        child: ColoredBox(color: pix),
      ),
    );
    if (!enabled) return bar;
    return LayoutBuilder(
      builder: (context, constraints) {
        double at(Offset local) => local.dx / constraints.maxWidth;
        return MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            key: const ValueKey('disc-seek-bar'),
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) => onCommit(at(d.localPosition)),
            onHorizontalDragStart: (d) => onPreview(at(d.localPosition)),
            onHorizontalDragUpdate: (d) => onPreview(at(d.localPosition)),
            onHorizontalDragEnd: (_) => onCommit(),
            onHorizontalDragCancel: onCancel,
            child: SizedBox(height: 20, child: Center(child: bar)),
          ),
        );
      },
    );
  }
}

/// System volume, in the OLED panel's pixel colours. Changes the volume
/// live on every drag tick: the Linux volume controller collapses a fast
/// drag into one-at-a-time updates that end on the release value. Watches
/// only the volume, so a drag doesn't rebuild the rest of the view.
class _OledVolumeSlider extends ConsumerWidget {
  final Color pix;
  final Color dim;

  const _OledVolumeSlider({required this.pix, required this.dim});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final volume = ref.watch(
      playbackControllerProvider.select((s) => s.volume),
    );
    final controller = ref.read(playbackControllerProvider.notifier);
    return SizedBox(
      height: 26,
      child: Row(
        children: [
          ThemedIcon(ThemedIconSlot.volumeDown, size: 14, color: dim),
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 2,
                activeTrackColor: pix,
                inactiveTrackColor: dim,
                thumbColor: pix,
                overlayColor: pix.withValues(alpha: 0.15),
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              ),
              child: Slider(
                value: volume.clamp(0.0, 1.0),
                semanticFormatterCallback: (v) =>
                    'Volume ${(v * 100).round()}%',
                onChanged: (v) => unawaited(controller.setVolume(v)),
              ),
            ),
          ),
          ThemedIcon(ThemedIconSlot.volumeUp, size: 14, color: dim),
        ],
      ),
    );
  }
}

class _ScanlinePainter extends CustomPainter {
  const _ScanlinePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = Colors.black.withValues(alpha: 0.22);
    for (double y = 0; y < size.height; y += 3) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 1), p);
    }
  }

  @override
  bool shouldRepaint(_ScanlinePainter old) => false;
}
