import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'audio_engine.dart';

/// Overridden in main() once the engine has been constructed and awaited
/// through init() — see main.dart. Never constructed lazily inside the
/// provider tree because init() is async and must complete before first use.
final audioEngineProvider = Provider<AudioEngine>((ref) {
  throw UnimplementedError(
    'audioEngineProvider must be overridden in ProviderScope after AudioEngine.init()',
  );
});
