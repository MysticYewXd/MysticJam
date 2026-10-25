import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:music_player/core/library/database.dart';
import 'package:music_player/core/playback/playback_controller.dart';
import 'package:music_player/core/settings/app_settings.dart';
import 'package:music_player/core/theme/album_palette.dart';
import 'package:music_player/core/theme/default_theme.dart';
import 'package:music_player/features/now_playing/mini_player.dart';
import 'package:music_player/features/now_playing/now_playing_screen.dart';
import 'package:music_player/features/now_playing/queue_screen.dart';
import 'package:music_player/widgets/themed/themed_volume_slider.dart';

/// Position ticks arrive several times a second; these tests check that
/// they only rebuild the widgets that show the position. A widget that
/// wasn't rebuilt keeps the very same instance, so `same(before)` proves
/// its parent's build didn't run again.

class _FakePlayback extends PlaybackController {
  final PlaybackState initial;
  _FakePlayback(this.initial);

  @override
  PlaybackState build() => initial;

  void push(PlaybackState s) => state = s;

  // The real one asks the OS (wpctl on Linux).
  @override
  Future<void> refreshVolume() async {}
}

Track _track(int id) => Track(
  id: id,
  filePath: '/m/$id.flac',
  title: 'Song $id',
  artist: 'Artist',
  format: 'flac',
  dateAdded: DateTime(2025),
);

final _queue = [_track(1), _track(2)];

PlaybackState _state({Duration position = Duration.zero, double volume = 1}) =>
    PlaybackState(
      currentTrack: _queue.first,
      queue: _queue,
      order: const [0, 1],
      orderIndex: 0,
      isPlaying: true,
      duration: const Duration(minutes: 3),
      position: position,
      volume: volume,
    );

Future<_FakePlayback> _pump(WidgetTester tester, Widget home) async {
  tester.view.physicalSize = const Size(600, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final fake = _FakePlayback(_state());
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        playbackControllerProvider.overrideWith(() => fake),
        albumAdaptedThemeProvider.overrideWithValue(defaultTheme),
        uiPrefsProvider.overrideWithValue(
          const UiPrefs(nowPlayingStyle: NowPlayingStyle.classic),
        ),
      ],
      child: MaterialApp(home: home),
    ),
  );
  await tester.pump();
  return fake;
}

Widget _title(WidgetTester tester) => tester.widget(find.text('Song 1'));

void main() {
  testWidgets('Now Playing: a position tick only rebuilds the progress row', (
    tester,
  ) async {
    final fake = await _pump(tester, const NowPlayingScreen());
    final title = _title(tester);
    final slider = tester.widget(find.byType(ThemedVolumeSlider));

    fake.push(_state(position: const Duration(seconds: 42)));
    await tester.pump();

    expect(find.text('0:42'), findsOneWidget);
    expect(_title(tester), same(title));
    expect(tester.widget(find.byType(ThemedVolumeSlider)), same(slider));
  });

  testWidgets('Now Playing: a volume change only rebuilds the slider', (
    tester,
  ) async {
    final fake = await _pump(tester, const NowPlayingScreen());
    final title = _title(tester);

    fake.push(_state(volume: 0.3));
    await tester.pump();

    expect(
      tester.widget<ThemedVolumeSlider>(find.byType(ThemedVolumeSlider)).value,
      0.3,
    );
    expect(_title(tester), same(title));
  });

  testWidgets('mini player: a position tick only rebuilds the progress line', (
    tester,
  ) async {
    final fake = await _pump(tester, const Scaffold(body: MiniPlayer()));
    final title = _title(tester);
    double progress() => tester
        .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
        .value!;
    expect(progress(), 0);

    fake.push(_state(position: const Duration(seconds: 90)));
    await tester.pumpAndSettle();

    expect(progress(), closeTo(0.5, 0.001));
    expect(_title(tester), same(title));
  });

  testWidgets('queue: a position tick does not rebuild the list', (
    tester,
  ) async {
    final fake = await _pump(tester, const QueueScreen());
    final title = _title(tester);

    fake.push(_state(position: const Duration(seconds: 42)));
    await tester.pump();

    expect(_title(tester), same(title));
  });
}
