import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/theme_provider.dart';
import 'themed_icon.dart';

class ThemedSearchBar extends ConsumerWidget {
  final String hintText;
  final ValueChanged<String> onChanged;
  final TextEditingController? controller;

  const ThemedSearchBar({
    super.key,
    required this.onChanged,
    this.hintText = 'Search',
    this.controller,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    return Container(
      decoration: BoxDecoration(
        color: theme.colors.surface,
        borderRadius: BorderRadius.circular(theme.shapes.cornerRadius),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: TextStyle(color: theme.colors.textPrimary),
        decoration: InputDecoration(
          border: InputBorder.none,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
          hintText: hintText,
          hintStyle: TextStyle(color: theme.colors.textSecondary),
          prefixIcon: ThemedIcon(ThemedIconSlot.search, color: theme.colors.textSecondary),
        ),
      ),
    );
  }
}
