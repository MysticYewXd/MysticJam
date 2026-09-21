import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Live frame-rate readout for Settings → Look & Feel → "Show FPS counter".
/// A running Ticker fires once per vsync, so the count is the rate the
/// engine is pacing frames at (the monitor's refresh rate) even when the UI
/// is otherwise idle — an idle app produces no frames, which would read as
/// a misleading "0 fps". Only built while the option is on.
class FpsCounter extends StatefulWidget {
  const FpsCounter({super.key});

  @override
  State<FpsCounter> createState() => _FpsCounterState();
}

class _FpsCounterState extends State<FpsCounter>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _windowStart = Duration.zero;
  int _frames = 0;
  int _fps = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      _frames++;
      final span = elapsed - _windowStart;
      if (span >= const Duration(milliseconds: 500)) {
        final fps = (_frames * 1000000 / span.inMicroseconds).round();
        _windowStart = elapsed;
        _frames = 0;
        if (fps != _fps) setState(() => _fps = fps);
      }
    })..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hz = View.of(context).display.refreshRate;
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          '$_fps fps · ${hz.round()} Hz',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            decoration: TextDecoration.none,
          ),
        ),
      ),
    );
  }
}
