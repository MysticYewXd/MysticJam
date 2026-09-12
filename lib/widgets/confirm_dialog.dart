import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/theme_provider.dart';

/// Confirmation dialog for destructive actions (delete track, delete
/// playlist, etc.) — returns true only if the user explicitly confirmed.
Future<bool> confirmDestructiveAction(
  BuildContext context,
  WidgetRef ref, {
  required String title,
  required String message,
  String confirmLabel = 'Delete',
}) async {
  final theme = ref.read(themeProvider);
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel, style: TextStyle(color: theme.colors.error)),
        ),
      ],
    ),
  );
  return result ?? false;
}
