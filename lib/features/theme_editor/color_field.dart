import 'package:flutter/material.dart';

import '../../core/theme/theme_model.dart';

/// A labelled color swatch that opens a small picker dialog on tap — a
/// hand-rolled RGB-sliders + hex-input picker rather than a new dependency,
/// since this project deliberately avoids native-toolchain-requiring
/// packages (see project notes on why dart_tags/pure-Dart parsing was
/// chosen over Rust-based alternatives — the same reasoning applies here:
/// keep the dependency surface minimal).
class ColorField extends StatelessWidget {
  final String label;
  final Color value;
  final ValueChanged<Color> onChanged;
  final AppTheme theme;

  const ColorField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    required this.theme,
  });

  Future<void> _openPicker(BuildContext context) async {
    final picked = await showDialog<Color>(
      context: context,
      builder: (_) => _ColorPickerDialog(initial: value, theme: theme),
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _openPicker(context),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: value,
                shape: BoxShape.circle,
                border: Border.all(color: theme.colors.textSecondary.withValues(alpha: 0.4)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label, style: TextStyle(color: theme.colors.textPrimary)),
            ),
            Text(
              '#${value.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}',
              style: TextStyle(color: theme.colors.textSecondary, fontSize: 12, fontFamily: 'monospace'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ColorPickerDialog extends StatefulWidget {
  final Color initial;
  final AppTheme theme;

  const _ColorPickerDialog({required this.initial, required this.theme});

  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  late double _r;
  late double _g;
  late double _b;
  late TextEditingController _hexController;

  @override
  void initState() {
    super.initState();
    _r = widget.initial.r * 255;
    _g = widget.initial.g * 255;
    _b = widget.initial.b * 255;
    _hexController = TextEditingController(text: _currentHex());
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  Color get _current => Color.fromARGB(255, _r.round(), _g.round(), _b.round());

  String _currentHex() =>
      _current.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase();

  void _applyHex(String input) {
    final cleaned = input.replaceFirst('#', '').trim();
    if (cleaned.length != 6) return;
    final parsed = int.tryParse(cleaned, radix: 16);
    if (parsed == null) return;
    setState(() {
      _r = ((parsed >> 16) & 0xFF).toDouble();
      _g = ((parsed >> 8) & 0xFF).toDouble();
      _b = (parsed & 0xFF).toDouble();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    return AlertDialog(
      backgroundColor: theme.colors.surface,
      title: Text('Pick a color', style: TextStyle(color: theme.colors.textPrimary)),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 56,
              decoration: BoxDecoration(
                color: _current,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: theme.colors.textSecondary.withValues(alpha: 0.3)),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _hexController,
              style: TextStyle(color: theme.colors.textPrimary, fontFamily: 'monospace'),
              decoration: InputDecoration(
                prefixText: '#',
                labelText: 'Hex',
                labelStyle: TextStyle(color: theme.colors.textSecondary),
              ),
              onChanged: (value) {
                _applyHex(value);
              },
            ),
            const SizedBox(height: 8),
            _slider('R', _r, (v) => setState(() {
                  _r = v;
                  _hexController.text = _currentHex();
                })),
            _slider('G', _g, (v) => setState(() {
                  _g = v;
                  _hexController.text = _currentHex();
                })),
            _slider('B', _b, (v) => setState(() {
                  _b = v;
                  _hexController.text = _currentHex();
                })),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.pop(context, _current),
          child: const Text('Use color'),
        ),
      ],
    );
  }

  Widget _slider(String label, double value, ValueChanged<double> onChanged) {
    return Row(
      children: [
        SizedBox(width: 16, child: Text(label, style: TextStyle(color: widget.theme.colors.textSecondary))),
        Expanded(
          child: Slider(
            value: value,
            min: 0,
            max: 255,
            activeColor: widget.theme.colors.primary,
            onChanged: onChanged,
          ),
        ),
        SizedBox(width: 32, child: Text(value.round().toString(), style: TextStyle(color: widget.theme.colors.textSecondary))),
      ],
    );
  }
}
