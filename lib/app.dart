import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/platform/android_media_session.dart';
import 'core/platform/file_open_channel.dart';
import 'core/platform/mpris.dart';
import 'core/platform/windows_media_controls.dart';
import 'core/settings/app_settings.dart';
import 'core/theme/theme_provider.dart';
import 'features/home_shell.dart';
import 'widgets/app_shortcuts.dart';
import 'widgets/fps_counter.dart';

class MusicPlayerApp extends ConsumerWidget {
  const MusicPlayerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeData = ref.watch(materialThemeDataProvider);
    // Read (not watch) purely to trigger creation — this registers a native
    // method channel listener once and never needs to rebuild anything
    // itself. See file_open_channel.dart.
    ref.read(fileOpenChannelProvider);
    // Same idea: starts the Android media session (lock-screen controls,
    // background playback). A no-op on other platforms.
    ref.read(androidMediaSessionProvider);
    // Linux desktop media controls (MPRIS). A no-op on other platforms.
    ref.read(mprisProvider);
    // Windows media keys and media flyout. A no-op on other platforms.
    ref.read(windowsMediaControlsProvider);
    return MaterialApp(
      title: 'MysticJam',
      debugShowCheckedModeBanner: false,
      theme: themeData,
      builder: (context, child) => AppShortcuts(
        child: Stack(
          children: [
            child!,
            if (ref.watch(uiPrefsProvider).showFps)
              const Positioned(top: 8, right: 8, child: FpsCounter()),
          ],
        ),
      ),
      home: const HomeShell(),
    );
  }
}
