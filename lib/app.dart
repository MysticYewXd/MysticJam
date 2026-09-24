import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/platform/file_open_channel.dart';
import 'core/platform/mpris.dart';
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
    // Publishes playback on the Linux session bus (MPRIS); see mpris.dart.
    ref.read(mprisProvider);
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
