import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_player/core/theme/custom_theme_data.dart';
import 'package:music_player/core/theme/default_theme.dart';
import 'package:music_player/core/theme/theme_model.dart';
import 'package:music_player/core/theme/theme_presets.dart';
import 'package:music_player/core/theme/vesper_palette.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  test('default theme is Vesper Dusk', () {
    expect(defaultTheme.colors, same(vesperDuskColors));
    expect(defaultTheme.colors.background, const Color(0xFF15162A));
  });

  test('the light preset keeps its id and is Vesper Dawn', () {
    final light = builtInPresets.firstWhere((p) => p.id == 'preset-light');
    expect(light.name, 'Vesper Dawn');
    expect(light.colors, same(vesperDawnColors));
  });

  test('extras round-trip through JSON', () {
    final data = CustomThemeData.fromAppTheme('x', 'X', defaultTheme);
    final back = CustomThemeData.fromJson(
      jsonDecode(jsonEncode(data.toJson())) as Map<String, dynamic>,
    );
    expect(back.colors.chrome, vesperDuskColors.chrome);
    expect(back.colors.line, vesperDuskColors.line);
    expect(back.colors.onPrimary, vesperDuskColors.onPrimary);
    expect(back.colors.accentSoft, vesperDuskColors.accentSoft);
    expect(back.colors.textFaint, vesperDuskColors.textFaint);
  });

  test('old saved JSON without extras still loads and derives fallbacks', () {
    final json = {
      'id': 'old',
      'name': 'Old',
      'colors': {
        'background': 0xFF121212,
        'surface': 0xFF1E1E1E,
        'primary': 0xFF6C63FF,
        'accent': 0xFF03DAC6,
        'textPrimary': 0xFFF5F5F5,
        'textSecondary': 0xFFAAAAAA,
        'progressBar': 0xFF6C63FF,
        'progressBarTrack': 0xFF3A3A3A,
        'controlActive': 0xFFF5F5F5,
        'controlInactive': 0xFF888888,
        'error': 0xFFCF6679,
      },
      'typography': {
        'fontFamily': 'Roboto',
        'headerSize': 22,
        'headerWeight': 5,
        'bodySize': 15,
        'bodyWeight': 3,
        'lyricsSize': 17,
        'lyricsWeight': 3,
      },
      'shapes': {'cornerRadius': 12, 'borderWidth': 1, 'cardElevation': 0},
    };
    final data = CustomThemeData.fromJson(json);
    expect(data.colors.explicitExtras, isEmpty);
    expect(data.colors.chrome, data.colors.surface);
    expect(data.colors.onPrimary, isNot(equals(data.colors.primary)));
    // Fallbacks must not be persisted as if the user chose them.
    expect((data.toJson()['colors'] as Map).containsKey('chrome'), isFalse);
  });

  test('copyWith keeps the extras', () {
    final c = vesperDuskColors.copyWith(background: Colors.black);
    expect(c.background, Colors.black);
    expect(c.chrome, vesperDuskColors.chrome);
    expect(c.textFaint, vesperDuskColors.textFaint);
  });

  for (final entry in {
    'dusk': vesperDuskColors,
    'dawn': vesperDawnColors,
  }.entries) {
    test('${entry.key}: text stays legible (4.5:1) on every surface', () {
      final c = entry.value;
      for (final ground in [
        c.background,
        c.chrome,
        c.surface,
        c.progressBarTrack,
      ]) {
        for (final ink in [c.textPrimary, c.textSecondary, c.textFaint]) {
          expect(
            _contrast(ink, ground),
            greaterThanOrEqualTo(4.5),
            reason: '$ink on $ground',
          );
        }
      }
      expect(_contrast(c.onPrimary, c.primary), greaterThanOrEqualTo(4.5));
    });
  }

  group('fonts', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    test(
      'the Vesper font families are registered and their files load',
      () async {
        final manifest = await rootBundle.loadString('FontManifest.json');
        expect(manifest, contains('DM Sans'));
        expect(manifest, contains('Fraunces'));
        for (final f in [
          'DMSans-400',
          'DMSans-500',
          'DMSans-600',
          'Fraunces-500',
        ]) {
          final data = await rootBundle.load('assets/fonts/$f.ttf');
          expect(data.lengthInBytes, greaterThan(10000), reason: f);
        }
      },
    );

    test('built-in themes use the Vesper families', () {
      expect(defaultTheme.typography.fontFamily, sansFontFamily);
      expect(defaultTheme.typography.displayFamily, displayFontFamily);
      for (final p in builtInPresets) {
        expect(p.typography.fontFamily, sansFontFamily, reason: p.name);
      }
    });

    test(
      'themes saved with Roboto load with the new sans; display family round-trips',
      () {
        final saved = CustomThemeData.fromAppTheme(
          'x',
          'X',
          defaultTheme,
        ).toJson();
        (saved['typography'] as Map)['fontFamily'] = 'Roboto';
        (saved['typography'] as Map).remove('displayFamily');
        final loaded = CustomThemeData.fromJson(saved);
        expect(loaded.typography.fontFamily, sansFontFamily);
        expect(loaded.typography.displayFamily, displayFontFamily);

        final again = CustomThemeData.fromJson(
          jsonDecode(jsonEncode(loaded.toJson())) as Map<String, dynamic>,
        );
        expect(again.typography.displayFamily, displayFontFamily);
      },
    );

    test('display() is Fraunces at the bundled weight', () {
      final style = defaultTheme.typography.display(28, color: Colors.white);
      expect(style.fontFamily, 'Fraunces');
      expect(style.fontWeight, FontWeight.w500);
      expect(style.fontSize, 28);
    });
  });
}
