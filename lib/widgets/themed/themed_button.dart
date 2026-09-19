import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/theme_provider.dart';

/// Vesper pill call-to-action. The filled form is for the one main action on
/// a page; [ghost] is the outlined secondary.
class ThemedButton extends ConsumerWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool ghost;

  const ThemedButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.ghost = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    final foreground = ghost
        ? theme.colors.textPrimary
        : theme.colors.onPrimary;
    const padding = EdgeInsets.symmetric(horizontal: 22, vertical: 12);
    const shape = StadiumBorder();

    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[Icon(icon, size: 18), const SizedBox(width: 8)],
        Text(
          label,
          style: TextStyle(
            fontFamily: theme.typography.fontFamily,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );

    if (ghost) {
      return OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: foreground,
          side: BorderSide(
            color: theme.colors.textSecondary.withValues(alpha: 0.55),
          ),
          shape: shape,
          padding: padding,
        ),
        child: child,
      );
    }
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: theme.colors.primary,
        foregroundColor: foreground,
        elevation: 0,
        shape: shape,
        padding: padding,
      ),
      child: child,
    );
  }
}
