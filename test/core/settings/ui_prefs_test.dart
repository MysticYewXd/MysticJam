import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:music_player/core/settings/app_settings.dart';

class _FakePathProvider extends PathProviderPlatform {
  final String path;
  _FakePathProvider(this.path);
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

void main() {
  test('every field survives a JSON round trip', () {
    const prefs = UiPrefs(
      lyricsFontSize: 28,
      lyricsAlign: LyricsAlign.center,
      lyricsLineSpacing: 1.9,
      lyricsInactiveOpacity: 0.5,
      lyricsAutoScroll: false,
      lyricsTapToSeek: false,
      lyricsOnlineLookup: false,
      showLyricsIcon: false,
      showFormatTag: false,
      albumColors: false,
      showFps: true,
    );
    final back = UiPrefs.fromJson(
      jsonDecode(jsonEncode(prefs.toJson())) as Map<String, dynamic>,
    );
    expect(back.toJson(), prefs.toJson());
  });

  test('missing, unknown or out-of-range values fall back safely', () {
    final p = UiPrefs.fromJson({
      'lyricsAlign': 'sideways',
      'lyricsFontSize': 9999,
      'lyricsLineSpacing': -5,
      'lyricsInactiveOpacity': 'oops',
    });
    const d = UiPrefs();
    expect(p.lyricsAlign, d.lyricsAlign);
    expect(p.lyricsFontSize, 40);
    expect(p.lyricsLineSpacing, 1.0);
    expect(p.lyricsInactiveOpacity, d.lyricsInactiveOpacity);
    expect(p.lyricsOnlineLookup, isTrue);
  });

  test('settings saved before UiPrefs existed still load with defaults', () {
    final s = AppSettingsState.fromJson({
      'shuffleEnabled': true,
      'repeatMode': 'all',
    });
    expect(s.shuffleEnabled, isTrue);
    expect(s.ui.toJson(), const UiPrefs().toJson());
  });

  test('copyWith changes only the named field', () {
    final p = const UiPrefs().copyWith(lyricsAlign: LyricsAlign.right);
    expect(p.lyricsAlign, LyricsAlign.right);
    expect(p.lyricsFontSize, const UiPrefs().lyricsFontSize);
  });

  test(
    'changes are written to disk and restored by a fresh app launch',
    () async {
      final dir = Directory.systemTemp.createTempSync('mysticjam_ui_prefs_');
      addTearDown(() => dir.deleteSync(recursive: true));
      PathProviderPlatform.instance = _FakePathProvider(dir.path);

      final first = ProviderContainer();
      addTearDown(first.dispose);
      final notifier = first.read(appSettingsProvider.notifier);
      await notifier.ready;
      await notifier.updateUi(
        (u) => u.copyWith(lyricsAlign: LyricsAlign.right, showFps: true),
      );

      final second = ProviderContainer();
      addTearDown(second.dispose);
      await second.read(appSettingsProvider.notifier).ready;
      final ui = second.read(uiPrefsProvider);
      expect(ui.lyricsAlign, LyricsAlign.right);
      expect(ui.showFps, isTrue);
    },
  );
}
