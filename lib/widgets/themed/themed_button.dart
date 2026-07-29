import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/theme_provider.dart';

class ThemedButton extends ConsumerWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  const ThemedButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: theme.colors.primary,
        foregroundColor: theme.colors.textPrimary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(theme.shapes.cornerRadius),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: theme.colors.textPrimary),
            const SizedBox(width: 8),
          ],
          Text(
            label,
            style: TextStyle(
              fontFamily: theme.typography.fontFamily,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
