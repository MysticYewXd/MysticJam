import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:music_player/core/library/database.dart';
import 'package:music_player/core/playback/playback_controller.dart';
import 'package:music_player/core/theme/album_palette.dart';
import 'package:music_player/core/theme/default_theme.dart';
import 'package:music_player/core/theme/theme_model.dart';
import 'package:music_player/features/now_playing/mini_player.dart';
import 'package:music_player/widgets/themed/round_buttons.dart';

class _FakePlayback extends PlaybackController {
  final PlaybackState initial;
  _FakePlayback(this.initial);

  @override
  PlaybackState build() => initial;
}

Track _track() => Track(
  id: 1,
  filePath: '/music/1.flac',
  title: 'Song',
  artist: 'Artist',
  format: 'flac',
  dateAdded: DateTime(2025),
);

Container _playButtonContainer(WidgetTester tester) => tester.widget<Container>(
  find.descendant(
    of: find.byType(PlayButton),
    matching: find.byType(Container),
  ),
);

void main() {
  testWidgets(
    'the play button inside the mini player follows the album-adapted '
    'theme, not the plain active theme',
    (tester) async {
      const adaptedPrimary = Color(0xFF11FF33);
      final adaptedTheme = AppTheme(
        name: defaultTheme.name,
        author: defaultTheme.author,
        colors: defaultTheme.colors.copyWith(primary: adaptedPrimary),
        typography: defaultTheme.typography,
        shapes: defaultTheme.shapes,
        layout: defaultTheme.layout,
        icons: defaultTheme.icons,
        animations: defaultTheme.animations,
        assets: defaultTheme.assets,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playbackControllerProvider.overrideWith(
              () => _FakePlayback(PlaybackState(currentTrack: _track())),
            ),
            albumAdaptedThemeProvider.overrideWithValue(adaptedTheme),
          ],
          child: const MaterialApp(home: Scaffold(body: MiniPlayer())),
        ),
      );
      await tester.pump();

      final decoration =
          _playButtonContainer(tester).decoration! as BoxDecoration;
      expect(decoration.color, adaptedPrimary);
      // Confirms this isn't a coincidence — the plain (non-adapted) default
      // theme's primary is a different colour, so a passing assertion above
      // means the override, not the base theme, is what's actually applied.
      expect(defaultTheme.colors.primary, isNot(adaptedPrimary));
    },
  );
}
