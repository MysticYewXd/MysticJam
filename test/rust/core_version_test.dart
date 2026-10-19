import 'package:flutter_test/flutter_test.dart';
import 'package:music_player/src/rust/api/info.dart';

import '../helpers/rust_lib.dart';

void main() {
  setUpAll(loadRustLib);

  test('Dart can call into the Rust library', () {
    expect(coreVersion(), '0.1.0');
  });
}
