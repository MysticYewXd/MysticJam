import 'dart:ui' show Tristate;
import 'package:drift/drift.dart' show Value;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:music_player/core/library/database.dart';
import 'package:music_player/core/playback/playback_controller.dart';
import 'package:music_player/core/settings/app_settings.dart';
import 'package:music_player/widgets/themed/round_buttons.dart';
import 'package:music_player/widgets/themed/themed_button.dart';
import 'package:music_player/widgets/themed/themed_icon.dart';
import 'package:music_player/widgets/themed/track_row.dart';

class _FakePlayback extends PlaybackController {
  final PlaybackState initial;
  _FakePlayback(this.initial);

  @override
  PlaybackState build() => initial;
}

Track _track(int id, String title) => Track(
  id: id,
  filePath: '/music/$id.flac',
  title: title,
  artist: 'Artist',
  album: 'Album $id',
  durationMs: 187000,
  format: 'flac',
  dateAdded: DateTime(2025),
);

Widget _host(
  Widget child, {
  PlaybackState? playback,
  UiPrefs prefs = const UiPrefs(),
}) => ProviderScope(
  overrides: [
    uiPrefsProvider.overrideWithValue(prefs),
    if (playback != null)
      playbackControllerProvider.overrideWith(() => _FakePlayback(playback)),
  ],
  child: MaterialApp(
    home: Scaffold(body: Center(child: child)),
  ),
);

void main() {
  testWidgets('RoundIconButton fires when enabled and not when disabled', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      _host(
        RoundIconButton(
          slot: ThemedIconSlot.next,
          tooltip: 'Next',
          onPressed: () => taps++,
        ),
      ),
    );
    await tester.tap(find.byType(RoundIconButton));
    expect(taps, 1);

    await tester.pumpWidget(
      _host(
        const RoundIconButton(
          slot: ThemedIconSlot.next,
          tooltip: 'Next',
          onPressed: null,
        ),
      ),
    );
    await tester.tap(find.byType(RoundIconButton));
    expect(taps, 1);
  });

  testWidgets('RoundIconButton exposes its label and toggled state', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _host(
        RoundIconButton(
          slot: ThemedIconSlot.shuffle,
          tooltip: 'Shuffle',
          active: true,
          onPressed: () {},
        ),
      ),
    );
    final node = tester.getSemantics(find.bySemanticsLabel('Shuffle'));
    // ignore: deprecated_member_use
    final data = node.getSemanticsData();
    expect(data.label, 'Shuffle');
    expect(data.hasAction(SemanticsAction.tap), isTrue);
    expect(data.flagsCollection.isButton, isTrue);
    expect(data.flagsCollection.isToggled, Tristate.isTrue);
    handle.dispose();
  });

  testWidgets('PlayButton swaps its icon and reports taps', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _host(PlayButton(playing: false, onPressed: () => taps++)),
    );
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    await tester.tap(find.byType(PlayButton));
    expect(taps, 1);

    await tester.pumpWidget(
      _host(PlayButton(playing: true, onPressed: () => taps++)),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.pause), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow), findsNothing);
  });

  testWidgets('ThemedButton renders filled and ghost variants', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _host(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ThemedButton(label: 'Add Files', onPressed: () => taps++),
            ThemedButton(
              label: 'Add Folder',
              ghost: true,
              onPressed: () => taps++,
            ),
          ],
        ),
      ),
    );
    expect(find.byType(ElevatedButton), findsOneWidget);
    expect(find.byType(OutlinedButton), findsOneWidget);
    await tester.tap(find.text('Add Folder'));
    expect(taps, 1);
  });

  group('TrackRow', () {
    testWidgets('a non-playing row shows no equalizer', (tester) async {
      await tester.pumpWidget(
        _host(
          SizedBox(
            width: 500,
            child: TrackRow(
              track: _track(1, 'One'),
              subtitle: 'Album 1',
              onTap: () {},
            ),
          ),
          playback: PlaybackState(currentTrack: _track(2, 'Two')),
        ),
      );
      expect(find.text('One'), findsOneWidget);
      expect(find.text('Album 1'), findsOneWidget);
      expect(find.text('3:07'), findsOneWidget);
      expect(find.byType(EqualizerBars), findsNothing);
    });

    testWidgets('only the current track shows the equalizer', (tester) async {
      final playing = _track(1, 'One');
      await tester.pumpWidget(
        _host(
          SizedBox(
            width: 500,
            child: Column(
              children: [
                TrackRow(track: playing, onTap: () {}),
                TrackRow(track: _track(2, 'Two'), onTap: () {}),
              ],
            ),
          ),
          playback: PlaybackState(currentTrack: playing, isPlaying: true),
        ),
      );
      expect(find.byType(EqualizerBars), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(TrackRow).first,
          matching: find.byType(EqualizerBars),
        ),
        findsOneWidget,
      );
    });

    testWidgets('actions stay hidden until hover, then can be tapped', (
      tester,
    ) async {
      var added = 0;
      await tester.pumpWidget(
        _host(
          SizedBox(
            width: 500,
            child: TrackRow(
              track: _track(1, 'One'),
              onTap: () {},
              actions: [
                RoundIconButton(
                  slot: ThemedIconSlot.playlistAdd,
                  tooltip: 'Add to playlist',
                  diameter: 36,
                  onPressed: () => added++,
                ),
              ],
            ),
          ),
          playback: const PlaybackState(),
        ),
      );
      Opacity actionOpacity() => tester.widget<Opacity>(
        find.ancestor(
          of: find.byType(RoundIconButton),
          matching: find.byType(Opacity),
        ),
      );
      expect(actionOpacity().opacity, 0);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.byType(TrackRow)));
      await tester.pumpAndSettle();
      expect(actionOpacity().opacity, 1);

      await tester.tap(find.byType(RoundIconButton));
      expect(added, 1);
    });

    testWidgets('tapping the row calls onTap', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _host(
          SizedBox(
            width: 500,
            child: TrackRow(track: _track(1, 'One'), onTap: () => taps++),
          ),
          playback: const PlaybackState(),
        ),
      );
      await tester.tap(find.text('One'));
      expect(taps, 1);
    });
    testWidgets('shows a lyrics icon only for tracks with lyrics', (
      tester,
    ) async {
      final plain = _track(1, 'Plain');
      final synced = _track(
        2,
        'Synced',
      ).copyWith(syncedLyrics: const Value('[00:01.00]hi'));
      final embedded = _track(
        3,
        'Embedded',
      ).copyWith(lyrics: const Value('la la'));
      await tester.pumpWidget(
        _host(
          SizedBox(
            width: 500,
            child: Column(
              children: [
                for (final t in [plain, synced, embedded])
                  TrackRow(track: t, onTap: () {}),
              ],
            ),
          ),
          playback: const PlaybackState(),
        ),
      );
      expect(find.byIcon(Icons.lyrics_outlined), findsNWidgets(2));
      expect(
        find.descendant(
          of: find.byType(TrackRow).first,
          matching: find.byIcon(Icons.lyrics_outlined),
        ),
        findsNothing,
      );
    });

    testWidgets('lyrics icon and format tag can be switched off in settings', (
      tester,
    ) async {
      final t = _track(
        2,
        'Synced',
      ).copyWith(syncedLyrics: const Value('[00:01.00]hi'));
      Widget row(UiPrefs prefs) => _host(
        SizedBox(
          width: 500,
          child: TrackRow(track: t, onTap: () {}),
        ),
        playback: const PlaybackState(),
        prefs: prefs,
      );

      await tester.pumpWidget(row(const UiPrefs()));
      expect(find.byIcon(Icons.lyrics_outlined), findsOneWidget);
      expect(find.text('FLAC'), findsOneWidget);

      await tester.pumpWidget(
        row(const UiPrefs(showLyricsIcon: false, showFormatTag: false)),
      );
      expect(find.byIcon(Icons.lyrics_outlined), findsNothing);
      expect(find.text('FLAC'), findsNothing);
    });
  });
}
