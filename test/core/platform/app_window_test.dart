import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_player/core/platform/app_window.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(appWindowChannel, null));

  test('asks the native window to raise itself', () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(appWindowChannel, (call) async {
      calls.add(call.method);
      return null;
    });
    await raiseAppWindow();
    expect(calls, ['raise']);
    expect(appWindowChannel.name, 'com.musicplayer.music_player/window');
  });

  test('does nothing, without throwing, when there is no native side', () {
    expect(raiseAppWindow(), completes);
  });

  test('a native error is swallowed too', () async {
    messenger.setMockMethodCallHandler(appWindowChannel, (call) async {
      throw PlatformException(code: 'boom');
    });
    await expectLater(raiseAppWindow(), completes);
  });
}
