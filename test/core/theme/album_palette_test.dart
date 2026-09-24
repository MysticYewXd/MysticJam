import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_player/core/theme/album_palette.dart';
import 'package:music_player/core/theme/vesper_palette.dart';

Uint8List _image(List<Color> pixels, {int alpha = 255}) {
  final out = Uint8List(pixels.length * 4);
  for (var i = 0; i < pixels.length; i++) {
    out[i * 4] = (pixels[i].r * 255).round();
    out[i * 4 + 1] = (pixels[i].g * 255).round();
    out[i * 4 + 2] = (pixels[i].b * 255).round();
    out[i * 4 + 3] = alpha;
  }
  return out;
}

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return ((la > lb ? la : lb) + 0.05) / ((la > lb ? lb : la) + 0.05);
}

void main() {
  group('dominantColorFromRgba', () {
    test('a vivid colour beats a larger area of dull/dark pixels', () {
      final pixels = [
        for (var i = 0; i < 60; i++) const Color(0xFF101010),
        for (var i = 0; i < 40; i++) const Color(0xFFD03030),
      ];
      final seed = dominantColorFromRgba(_image(pixels))!;
      final hsl = HSLColor.fromColor(seed);
      expect(hsl.hue, anyOf(lessThan(10), greaterThan(350)));
      expect(hsl.saturation, greaterThan(0.5));
    });

    test('the largest vivid hue wins', () {
      final pixels = [
        for (var i = 0; i < 70; i++) const Color(0xFF2050D0),
        for (var i = 0; i < 30; i++) const Color(0xFFD03030),
      ];
      final hue = HSLColor.fromColor(
        dominantColorFromRgba(_image(pixels))!,
      ).hue;
      expect(hue, closeTo(225, 15));
    });

    test('greyscale art stays neutral', () {
      final pixels = [
        for (var i = 0; i < 50; i++) const Color(0xFF808080),
        for (var i = 0; i < 50; i++) const Color(0xFF404040),
      ];
      final seed = dominantColorFromRgba(_image(pixels))!;
      expect(HSLColor.fromColor(seed).saturation, lessThan(0.05));
    });

    test('transparent or empty images give null', () {
      expect(dominantColorFromRgba(_image([Colors.red], alpha: 0)), isNull);
      expect(dominantColorFromRgba(Uint8List(0)), isNull);
    });
  });

  group('adaptColorsToSeed', () {
    for (final entry in {
      'dusk': vesperDuskColors,
      'dawn': vesperDawnColors,
    }.entries) {
      test(
        '${entry.key}: text stays legible on tinted grounds for any hue',
        () {
          for (var hue = 0; hue < 360; hue += 15) {
            for (final sat in [0.0, 0.5, 1.0]) {
              for (final light in [0.2, 0.5, 0.8]) {
                final seed = HSLColor.fromAHSL(
                  1,
                  hue.toDouble(),
                  sat,
                  light,
                ).toColor();
                final c = adaptColorsToSeed(entry.value, seed);
                for (final ground in [c.background, c.chrome, c.surface]) {
                  expect(
                    _contrast(c.textPrimary, ground),
                    greaterThanOrEqualTo(4.5),
                    reason: 'primary text, seed $seed on $ground',
                  );
                  expect(
                    _contrast(c.textSecondary, ground),
                    greaterThanOrEqualTo(4.5),
                    reason: 'secondary text, seed $seed on $ground',
                  );
                }
                expect(
                  _contrast(c.onPrimary, c.primary),
                  greaterThanOrEqualTo(4.5),
                  reason: 'on-primary, seed $seed',
                );
              }
            }
          }
        },
      );

      test('${entry.key}: the result actually takes on the album hue', () {
        final c = adaptColorsToSeed(entry.value, const Color(0xFF2A9D4F));
        final hue = HSLColor.fromColor(c.background).hue;
        expect(
          hue,
          closeTo(HSLColor.fromColor(const Color(0xFF2A9D4F)).hue, 2),
        );
        expect(c.background, isNot(entry.value.background));
      });
    }
  });

  group('albumSeedProvider', () {
    testWidgets('reads a real PNG file and finds its dominant colour', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        canvas.drawRect(
          const Rect.fromLTWH(0, 0, 64, 64),
          Paint()..color = const Color(0xFF101010),
        );
        canvas.drawRect(
          const Rect.fromLTWH(0, 0, 40, 64),
          Paint()..color = const Color(0xFF2A9D4F),
        );
        final image = await recorder.endRecording().toImage(64, 64);
        final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
        final dir = Directory.systemTemp.createTempSync('mysticjam_palette_');
        addTearDown(() => dir.deleteSync(recursive: true));
        final file = File('${dir.path}/art.png')
          ..writeAsBytesSync(png.buffer.asUint8List());

        final container = ProviderContainer();
        addTearDown(container.dispose);

        final seed = await container.read(albumSeedProvider(file.path).future);
        expect(seed, isNotNull);
        expect(
          HSLColor.fromColor(seed!).hue,
          closeTo(HSLColor.fromColor(const Color(0xFF2A9D4F)).hue, 8),
        );

        expect(
          await container.read(
            albumSeedProvider('${dir.path}/missing.png').future,
          ),
          isNull,
        );
        expect(await container.read(albumSeedProvider(null).future), isNull);
      });
    });
  });
}
