import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../playback/playback_controller.dart';
import '../settings/app_settings.dart';
import 'theme_model.dart';
import 'theme_provider.dart';

const _hueBins = 12;
const _sampleSize = 48;

/// Picks the colour that best represents an image: pixels are weighted by
/// how vivid they are (saturation, and mid-range lightness so near-black and
/// near-white don't win), grouped into hue bins, and the heaviest bin's
/// weighted-average colour is returned. Greyscale artwork has no vivid
/// pixels, so it falls back to the plain average, which keeps the result
/// neutral instead of inventing a hue. Returns null for an empty/transparent
/// image. [rgba] is straight (non-premultiplied) 8-bit RGBA.
Color? dominantColorFromRgba(Uint8List rgba) {
  final weightPerBin = List<double>.filled(_hueBins, 0);
  final rSum = List<double>.filled(_hueBins, 0);
  final gSum = List<double>.filled(_hueBins, 0);
  final bSum = List<double>.filled(_hueBins, 0);

  double allR = 0, allG = 0, allB = 0;
  var opaque = 0;

  for (var i = 0; i + 3 < rgba.length; i += 4) {
    if (rgba[i + 3] < 128) continue;
    final r = rgba[i].toDouble();
    final g = rgba[i + 1].toDouble();
    final b = rgba[i + 2].toDouble();
    allR += r;
    allG += g;
    allB += b;
    opaque++;

    final hsl = HSLColor.fromColor(
      Color.fromARGB(255, r.round(), g.round(), b.round()),
    );
    final lightnessFit = 1 - (2 * hsl.lightness - 1).abs();
    final weight = hsl.saturation * lightnessFit;
    if (weight <= 0.02) continue;
    final bin = (hsl.hue / (360 / _hueBins)).floor() % _hueBins;
    weightPerBin[bin] += weight;
    rSum[bin] += r * weight;
    gSum[bin] += g * weight;
    bSum[bin] += b * weight;
  }

  if (opaque == 0) return null;

  var best = 0;
  for (var i = 1; i < _hueBins; i++) {
    if (weightPerBin[i] > weightPerBin[best]) best = i;
  }

  // Under ~2% of pixels' worth of colour: treat as greyscale artwork.
  if (weightPerBin[best] < opaque * 0.02) {
    return Color.fromARGB(
      255,
      (allR / opaque).round(),
      (allG / opaque).round(),
      (allB / opaque).round(),
    );
  }
  final w = weightPerBin[best];
  return Color.fromARGB(
    255,
    (rSum[best] / w).round(),
    (gSum[best] / w).round(),
    (bSum[best] / w).round(),
  );
}

/// Rebuilds [base] around [seed]: backgrounds become a deep (dark base) or
/// pale (light base) tint of the seed hue; the primary/progress colours are a
/// lightness-adjusted version of it. Text and control colours are kept from
/// [base] so contrast is preserved — the tinted grounds stay in the same
/// lightness band as the base's own, so they remain legible.
AppColorScheme adaptColorsToSeed(AppColorScheme base, Color seed) {
  final dark =
      ThemeData.estimateBrightnessForColor(base.background) == Brightness.dark;
  final hsl = HSLColor.fromColor(seed);
  // Cap saturation for large surfaces so a neon cover doesn't glare.
  final surfaceSat = hsl.saturation.clamp(0.0, 0.55);

  Color tint(double lightness, {double? sat}) =>
      HSLColor.fromAHSL(1, hsl.hue, sat ?? surfaceSat, lightness).toColor();

  final background = dark ? tint(0.09) : tint(0.95, sat: surfaceSat * 0.7);
  final chrome = dark ? tint(0.13) : tint(0.92, sat: surfaceSat * 0.7);
  final surface = dark ? tint(0.18) : tint(0.98, sat: surfaceSat * 0.5);
  final track = dark ? tint(0.25) : tint(0.86, sat: surfaceSat * 0.7);

  // Accent colours: vivid, lifted for dark grounds and deepened for light.
  final vividSat = hsl.saturation < 0.15
      ? hsl.saturation
      : hsl.saturation.clamp(0.45, 0.9);
  final primary = HSLColor.fromAHSL(
    1,
    hsl.hue,
    vividSat,
    dark ? 0.75 : 0.30,
  ).toColor();
  final accent = HSLColor.fromAHSL(
    1,
    (hsl.hue + 28) % 360,
    vividSat,
    dark ? 0.72 : 0.34,
  ).toColor();

  return AppColorScheme(
    background: background,
    surface: surface,
    primary: primary,
    accent: accent,
    textPrimary: base.textPrimary,
    textSecondary: base.textSecondary,
    progressBar: accent,
    progressBarTrack: track,
    controlActive: base.controlActive,
    controlInactive: base.controlInactive,
    error: base.error,
    chrome: chrome,
    line: dark ? tint(0.22) : tint(0.82, sat: surfaceSat * 0.6),
    onPrimary: _readableOn(primary),
    accentSoft: primary.withValues(alpha: 0.18),
    textFaint: base.textFaint,
  );
}

/// Near-black or white, whichever reads better on [fill] (a plain
/// lightness pick isn't enough: a light-theme primary can still be a
/// mid-lightness yellow that white text fails on).
Color _readableOn(Color fill) {
  const dark = Color(0xFF111111);
  const light = Color(0xFFFFFFFF);
  double contrast(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    return ((la > lb ? la : lb) + 0.05) / ((la > lb ? lb : la) + 0.05);
  }

  return contrast(fill, dark) >= contrast(fill, light) ? dark : light;
}

Future<Color?> _seedFromFile(String path) async {
  try {
    final bytes = await File(path).readAsBytes();
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: _sampleSize,
    );
    final frame = await codec.getNextFrame();
    final data = await frame.image.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    frame.image.dispose();
    codec.dispose();
    if (data == null) return null;
    return dominantColorFromRgba(data.buffer.asUint8List());
  } catch (_) {
    // Missing/corrupt art just means no adaptation — the base theme applies.
    return null;
  }
}

/// The dominant colour of a track's cached album art, computed once per path
/// (Riverpod caches the future). Null when there is no art or it can't be read.
final albumSeedProvider = FutureProvider.family<Color?, String?>((
  ref,
  path,
) async {
  if (path == null) return null;
  return _seedFromFile(path);
});

String? _currentArtPath(Ref ref) =>
    ref.read(playbackControllerProvider).currentTrack?.albumArtPath;

/// The seed colour of the playing track's art. Keeps showing the previous
/// track's seed until the next one resolves, so skipping tracks cross-fades
/// between album colours instead of flashing back to the base theme.
class CurrentAlbumSeed extends Notifier<Color?> {
  var _disposed = false;

  @override
  Color? build() {
    ref.onDispose(() => _disposed = true);
    ref.listen(
      playbackControllerProvider.select((s) => s.currentTrack?.albumArtPath),
      (_, path) => _resolve(path),
      fireImmediately: true,
    );
    return null;
  }

  Future<void> _resolve(String? path) async {
    // Yield so the initial fireImmediately call doesn't set state mid-build.
    await null;
    if (path == null) {
      if (!_disposed) state = null;
      return;
    }
    final seed = await ref.read(albumSeedProvider(path).future);
    if (_disposed || _currentArtPath(ref) != path) return;
    state = seed;
  }
}

final currentAlbumSeedProvider = NotifierProvider<CurrentAlbumSeed, Color?>(
  CurrentAlbumSeed.new,
);

/// The active theme recoloured to match the currently playing track's album
/// art, or the plain active theme when nothing is playing / no usable art.
/// Deliberately separate from [themeProvider]: only the playback surfaces
/// (mini player, Now Playing) opt in, so the rest of the app keeps the theme
/// the user chose.
final albumAdaptedThemeProvider = Provider<AppTheme>((ref) {
  final base = ref.watch(themeProvider);
  final seed = ref.watch(currentAlbumSeedProvider);
  if (seed == null || !ref.watch(uiPrefsProvider).albumColors) return base;
  return AppTheme(
    name: base.name,
    author: base.author,
    colors: adaptColorsToSeed(base.colors, seed),
    typography: base.typography,
    shapes: base.shapes,
    layout: base.layout,
    icons: base.icons,
    animations: base.animations,
    assets: base.assets,
  );
});
