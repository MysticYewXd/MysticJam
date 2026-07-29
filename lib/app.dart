import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/theme_provider.dart';
import 'features/home_shell.dart';

class MusicPlayerApp extends ConsumerWidget {
  const MusicPlayerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeData = ref.watch(materialThemeDataProvider);
    return MaterialApp(
      title: 'Music Player',
      debugShowCheckedModeBanner: false,
      theme: themeData,
      home: const HomeShell(),
    );
  }
}
