import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:music_player/app.dart';
import 'package:music_player/core/audio/audio_engine.dart';
import 'package:music_player/core/audio/audio_engine_provider.dart';

class _FakeAudioEngine implements AudioEngine {
  @override
  Future<void> init() async {}

  @override
  Future<void> open(String filePath, {bool play = true}) async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> dispose() async {}

  @override
  Stream<Duration> get positionStream => const Stream.empty();

  @override
  Stream<Duration> get durationStream => const Stream.empty();

  @override
  Stream<bool> get playingStream => const Stream.empty();

  @override
  Stream<bool> get completedStream => const Stream.empty();

  @override
  Stream<String> get errorStream => const Stream.empty();

  @override
  Stream<double> get volumeStream => const Stream.empty();
}

void main() {
  testWidgets('App builds and shows the library screen', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          audioEngineProvider.overrideWithValue(_FakeAudioEngine()),
        ],
        child: const MusicPlayerApp(),
      ),
    );
    await tester.pump();

    expect(find.text('Library'), findsAtLeastNWidgets(1));
  });
}
