import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:music_player/core/audio/audio_engine_provider.dart';
import 'package:music_player/core/playback/playback_controller.dart';
import 'package:music_player/features/settings/settings_screen.dart';

class _FakePlayback extends PlaybackController {
  final exclusive = <bool>[];

  @override
  PlaybackState build() => const PlaybackState();

  @override
  Future<void> setExclusiveAudio(bool enabled) async => exclusive.add(enabled);
}

Future<_FakePlayback> _pump(
  WidgetTester tester, {
  required bool windows,
}) async {
  final fake = _FakePlayback();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        playbackControllerProvider.overrideWith(() => fake),
        exclusiveAudioSupportedProvider.overrideWithValue(windows),
      ],
      child: const MaterialApp(home: SettingsScreen()),
    ),
  );
  await tester.pump();
  return fake;
}

final _setting = find.text('Exclusive audio (bit-perfect)');

void main() {
  testWidgets('Windows: the switch turns exclusive audio on', (tester) async {
    final fake = await _pump(tester, windows: true);

    expect(_setting, findsOneWidget);
    await tester.tap(_setting);
    await tester.pump();

    expect(fake.exclusive, [true]);
  });

  testWidgets('other systems: the setting is not offered', (tester) async {
    await _pump(tester, windows: false);

    expect(_setting, findsNothing);
    expect(find.text('Playback'), findsNothing);
  });
}
