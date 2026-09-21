import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:music_player/core/library/database.dart';
import 'package:music_player/core/library/library_providers.dart';
import 'package:music_player/core/playback/playback_controller.dart';
import 'package:music_player/core/settings/app_settings.dart';
import 'package:music_player/features/now_playing/lyrics_screen.dart';

class _FakePlayback extends PlaybackController {
  final Duration position;
  _FakePlayback(this.position);
  @override
  PlaybackState build() => PlaybackState(position: position);
}

Track _track({String? synced, String? plain}) => Track(
  id: 1,
  filePath: '/m/1.flac',
  title: 'Song',
  artist: 'Artist',
  format: 'flac',
  dateAdded: DateTime(2025),
).copyWith(syncedLyrics: Value(synced), lyrics: Value(plain));

Widget _host(
  Track track, {
  required Future<String?> Function() online,
  Duration position = Duration.zero,
  UiPrefs prefs = const UiPrefs(),
}) => ProviderScope(
  overrides: [
    uiPrefsProvider.overrideWithValue(prefs),
    playbackControllerProvider.overrideWith(() => _FakePlayback(position)),
    onlineLyricsProvider.overrideWith((ref, t) => online()),
  ],
  child: MaterialApp(home: LyricsScreen(track: track)),
);

const _lrc = '[00:01.00]First line\n[00:05.00]Second line';

void main() {
  testWidgets('local .lrc lyrics are shown without any online lookup', (
    tester,
  ) async {
    var lookups = 0;
    await tester.pumpWidget(
      _host(
        _track(synced: _lrc),
        online: () async {
          lookups++;
          return null;
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('First line'), findsOneWidget);
    expect(find.text('Second line'), findsOneWidget);
    expect(lookups, 0);
  });

  testWidgets(
    'a track with no local lyrics shows what the online lookup returns',
    (tester) async {
      await tester.pumpWidget(_host(_track(), online: () async => _lrc));
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.text('First line'), findsOneWidget);
    },
  );

  testWidgets('shows a lookup indicator while the online request is running', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        _track(),
        online: () => Future.delayed(const Duration(seconds: 5), () => null),
      ),
    );
    await tester.pump();
    expect(find.text('Looking up lyrics online…'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets(
    'no online match falls back to embedded plain lyrics, then to none',
    (tester) async {
      await tester.pumpWidget(
        _host(_track(plain: 'la la la'), online: () async => null),
      );
      await tester.pumpAndSettle();
      expect(find.text('la la la'), findsOneWidget);

      await tester.pumpWidget(_host(_track(), online: () async => null));
      await tester.pumpAndSettle();
      expect(find.text('No lyrics found for this track'), findsOneWidget);
    },
  );

  testWidgets('the line at the current position is the highlighted one', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        _track(synced: _lrc),
        online: () async => null,
        position: const Duration(seconds: 6),
      ),
    );
    await tester.pumpAndSettle();
    double opacityOf(String text) => tester
        .widget<AnimatedOpacity>(
          find.ancestor(
            of: find.text(text),
            matching: find.byType(AnimatedOpacity),
          ),
        )
        .opacity;
    expect(opacityOf('Second line'), 1);
    expect(opacityOf('First line'), lessThan(1));
  });

  testWidgets('online lookup off never contacts the network layer', (
    tester,
  ) async {
    var lookups = 0;
    await tester.pumpWidget(
      _host(
        _track(plain: 'offline lyrics'),
        online: () async {
          lookups++;
          return _lrc;
        },
        prefs: const UiPrefs(lyricsOnlineLookup: false),
      ),
    );
    await tester.pumpAndSettle();
    expect(lookups, 0);
    expect(find.text('offline lyrics'), findsOneWidget);
  });

  testWidgets('size, position and dimming preferences are applied', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        _track(synced: _lrc),
        online: () async => null,
        position: const Duration(seconds: 6),
        prefs: const UiPrefs(
          lyricsFontSize: 30,
          lyricsAlign: LyricsAlign.center,
          lyricsInactiveOpacity: 0.6,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final text = tester.widget<Text>(find.text('First line'));
    expect(text.textAlign, TextAlign.center);
    expect(text.style!.fontSize, 30);
    final opacity = tester.widget<AnimatedOpacity>(
      find.ancestor(
        of: find.text('First line'),
        matching: find.byType(AnimatedOpacity),
      ),
    );
    expect(opacity.opacity, 0.6);
  });

  testWidgets('tap-to-seek off ignores taps on a line', (tester) async {
    await tester.pumpWidget(
      _host(
        _track(synced: _lrc),
        online: () async => null,
        prefs: const UiPrefs(lyricsTapToSeek: false),
      ),
    );
    await tester.pumpAndSettle();
    final inkWell = tester.widget<InkWell>(
      find
          .ancestor(of: find.text('First line'), matching: find.byType(InkWell))
          .first,
    );
    expect(inkWell.onTap, isNull);
  });
}
