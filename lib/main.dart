import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import 'app.dart';
import 'core/audio/audio_engine_provider.dart';
import 'core/audio/media_kit_audio_engine.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  final audioEngine = MediaKitAudioEngine();
  await audioEngine.init();

  runApp(
    ProviderScope(
      overrides: [
        audioEngineProvider.overrideWithValue(audioEngine),
      ],
      child: const MusicPlayerApp(),
    ),
  );
}
