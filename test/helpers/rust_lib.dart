import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:music_player/src/rust/frb_generated.dart';
import 'package:path/path.dart' as p;

bool _loaded = false;

/// Builds the Rust crate (a no-op when it's up to date) and loads it, for
/// tests that call into Rust. `flutter test` doesn't run the app build that
/// normally bundles the library, so tests load cargo's output directly.
Future<void> loadRustLib() async {
  if (_loaded) return;
  final manifest = p.join(Directory.current.path, 'rust', 'Cargo.toml');
  final build = await Process.run('cargo', [
    'build',
    '--manifest-path',
    manifest,
  ]);
  if (build.exitCode != 0) {
    throw StateError('cargo build failed:\n${build.stderr}');
  }
  final name = Platform.isWindows
      ? 'mysticjam_core.dll'
      : Platform.isMacOS
      ? 'libmysticjam_core.dylib'
      : 'libmysticjam_core.so';
  final lib = p.join(Directory.current.path, 'rust', 'target', 'debug', name);
  await RustLib.init(externalLibrary: ExternalLibrary.open(lib));
  _loaded = true;
}
