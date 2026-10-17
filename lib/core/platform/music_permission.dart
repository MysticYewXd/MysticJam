import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

/// Asks for permission to read the user's music before a folder is picked or
/// scanned. Only Android gates this behind a runtime grant; everywhere else
/// it returns true straight away.
///
/// Android 13+ uses READ_MEDIA_AUDIO ([Permission.audio]); older versions use
/// READ_EXTERNAL_STORAGE ([Permission.storage]). Each one is a no-op (never
/// granted) on the versions where the other applies, so both are requested
/// and either grant is enough.
///
/// When refused, shows a snackbar on [context] that links to the app's
/// system settings, since a permanently denied grant can only be changed
/// there.
Future<bool> ensureMusicReadPermission(BuildContext context) async {
  if (!Platform.isAndroid) return true;
  final statuses = await [Permission.audio, Permission.storage].request();
  if (statuses.values.any((s) => s.isGranted || s.isLimited)) return true;
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('MysticJam needs permission to read your music'),
        action: SnackBarAction(label: 'Settings', onPressed: openAppSettings),
      ),
    );
  }
  return false;
}
