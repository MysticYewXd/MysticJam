import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/platform/file_open_channel.dart';
import 'core/settings/app_settings.dart';
import 'core/theme/theme_provider.dart';
import 'core/undo/last_undo_provider.dart';
import 'features/home_shell.dart';
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
    return MaterialApp(
      title: 'MysticJam',
      debugShowCheckedModeBanner: false,
      theme: themeData,
      builder: (context, child) => Stack(
        children: [
          child!,
          if (ref.watch(uiPrefsProvider).showFps)
            const Positioned(top: 8, right: 8, child: FpsCounter()),
        ],
      ),
      home: CallbackShortcuts(
        // App-wide Ctrl+Z for "undo my last delete" — the same action the
        // snackbar's Undo button triggers (see last_undo_provider.dart), so
        // it still works after the snackbar itself has disappeared. Placed
        // above HomeShell so it fires no matter which screen has focus.
        bindings: {
          LogicalKeySet(
            LogicalKeyboardKey.control,
            LogicalKeyboardKey.keyZ,
          ): () =>
              performLastUndo(ref),
        },
        child: const HomeShell(),
      ),
    );
  }
}
