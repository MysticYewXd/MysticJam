import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/library/library_providers.dart';
import '../../core/settings/app_settings.dart';
import '../../core/theme/theme_provider.dart';
import '../now_playing/lyrics_screen.dart';

/// "144 Hz", or "59.9 Hz" for the fractional rates some monitors report.
String formatRefreshRate(double hz) => (hz - hz.round()).abs() < 0.05
    ? '${hz.round()} Hz'
    : '${hz.toStringAsFixed(1)} Hz';

class LookAndFeelScreen extends ConsumerStatefulWidget {
  const LookAndFeelScreen({super.key});

  @override
  ConsumerState<LookAndFeelScreen> createState() => _LookAndFeelScreenState();
}

class _LookAndFeelScreenState extends ConsumerState<LookAndFeelScreen> {
  String? _rescanStatus;

  Future<void> _rescanLyrics() async {
    final scanner = ref.read(libraryScannerProvider);
    final found = await scanner.rescanLyrics(
      onProgress: (done, total) {
        if (!mounted) return;
        setState(() => _rescanStatus = 'Scanning $done of $total…');
      },
    );
    if (!mounted) return;
    setState(() => _rescanStatus = null);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Lyrics rescan done — found lyrics for $found tracks'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final ui = ref.watch(uiPrefsProvider);
    final notifier = ref.read(appSettingsProvider.notifier);
    void set(UiPrefs Function(UiPrefs) f) => notifier.updateUi(f);
    final c = theme.colors;

    Widget header(String label) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: c.textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1,
        ),
      ),
    );

    Widget toggle(
      String title,
      String subtitle,
      bool value,
      ValueChanged<bool> onChanged,
    ) => SwitchListTile(
      title: Text(title, style: TextStyle(color: c.textPrimary)),
      subtitle: Text(subtitle, style: TextStyle(color: c.textSecondary)),
      activeThumbColor: c.primary,
      value: value,
      onChanged: onChanged,
    );

    Widget slider(
      String title,
      double value,
      double min,
      double max,
      String Function(double) label,
      ValueChanged<double> onChanged,
    ) => ListTile(
      title: Text(title, style: TextStyle(color: c.textPrimary)),
      subtitle: Slider(
        value: value.clamp(min, max),
        min: min,
        max: max,
        activeColor: c.primary,
        onChanged: onChanged,
      ),
      trailing: Text(label(value), style: TextStyle(color: c.textSecondary)),
    );

    final refreshRate = View.of(context).display.refreshRate;

    return Scaffold(
      appBar: AppBar(
        title: Text('Look & Feel', style: TextStyle(color: c.textPrimary)),
      ),
      body: ListView(
        children: [
          header('Lyrics'),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(theme.shapes.cornerRadius),
            ),
            child: SizedBox(
              width: double.infinity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'This line is playing now',
                    textAlign: lyricsTextAlign(ui.lyricsAlign),
                    style: lyricsTextStyle(theme, ui),
                  ),
                  Opacity(
                    opacity: ui.lyricsInactiveOpacity,
                    child: Text(
                      'and this one comes next',
                      textAlign: lyricsTextAlign(ui.lyricsAlign),
                      style: lyricsTextStyle(theme, ui),
                    ),
                  ),
                ],
              ),
            ),
          ),
          ListTile(
            title: Text(
              'Text position',
              style: TextStyle(color: c.textPrimary),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SegmentedButton<LyricsAlign>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: LyricsAlign.left, label: Text('Left')),
                  ButtonSegment(
                    value: LyricsAlign.center,
                    label: Text('Middle'),
                  ),
                  ButtonSegment(value: LyricsAlign.right, label: Text('Right')),
                ],
                selected: {ui.lyricsAlign},
                onSelectionChanged: (s) =>
                    set((u) => u.copyWith(lyricsAlign: s.first)),
              ),
            ),
          ),
          slider(
            'Text size',
            ui.lyricsFontSize,
            14,
            34,
            (v) => '${v.round()} px',
            (v) => set((u) => u.copyWith(lyricsFontSize: v)),
          ),
          slider(
            'Line spacing',
            ui.lyricsLineSpacing,
            1.0,
            2.2,
            (v) => v.toStringAsFixed(1),
            (v) => set((u) => u.copyWith(lyricsLineSpacing: v)),
          ),
          slider(
            'Other lines opacity',
            ui.lyricsInactiveOpacity,
            0.15,
            0.8,
            (v) => '${(v * 100).round()}%',
            (v) => set((u) => u.copyWith(lyricsInactiveOpacity: v)),
          ),
          toggle(
            'Auto-scroll',
            'Follow the playing line',
            ui.lyricsAutoScroll,
            (v) => set((u) => u.copyWith(lyricsAutoScroll: v)),
          ),
          toggle(
            'Tap a line to jump there',
            'Seeks playback to that line',
            ui.lyricsTapToSeek,
            (v) => set((u) => u.copyWith(lyricsTapToSeek: v)),
          ),
          toggle(
            'Look up missing lyrics online',
            'Opening Lyrics on a song with no .lrc file asks lrclib.net once, '
                'sending only artist, title and length. Off keeps the app fully offline.',
            ui.lyricsOnlineLookup,
            (v) => set((u) => u.copyWith(lyricsOnlineLookup: v)),
          ),
          ListTile(
            leading: _rescanStatus == null
                ? Icon(Icons.refresh, color: c.textSecondary)
                : SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: c.primary,
                    ),
                  ),
            title: Text(
              'Rescan lyrics',
              style: TextStyle(color: c.textPrimary),
            ),
            subtitle: Text(
              _rescanStatus ??
                  'Re-read .lrc files and embedded lyrics for every song. Existing lyrics are kept.',
              style: TextStyle(color: c.textSecondary),
            ),
            onTap: _rescanStatus == null ? _rescanLyrics : null,
          ),
          header('Lists'),
          toggle(
            'Lyrics icon',
            'Mark songs that have lyrics',
            ui.showLyricsIcon,
            (v) => set((u) => u.copyWith(showLyricsIcon: v)),
          ),
          toggle(
            'File format',
            'Show FLAC / MP3 tags on song rows',
            ui.showFormatTag,
            (v) => set((u) => u.copyWith(showFormatTag: v)),
          ),
          header('Now Playing'),
          toggle(
            'Album colours',
            'Tint the player with the album art\'s colours',
            ui.albumColors,
            (v) => set((u) => u.copyWith(albumColors: v)),
          ),
          header('Display'),
          ListTile(
            leading: Icon(Icons.speed, color: c.textSecondary),
            title: Text(
              'Monitor refresh rate',
              style: TextStyle(color: c.textPrimary),
            ),
            subtitle: Text(
              '${formatRefreshRate(refreshRate)}. '
              'The app renders at your monitor\'s rate automatically.',
              style: TextStyle(color: c.textSecondary),
            ),
          ),
          toggle(
            'Show FPS counter',
            'Live frame rate overlay, to check smoothness',
            ui.showFps,
            (v) => set((u) => u.copyWith(showFps: v)),
          ),
        ],
      ),
    );
  }
}
