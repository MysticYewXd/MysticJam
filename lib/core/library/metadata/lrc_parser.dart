/// One line of synced lyrics: the instant it starts, and its text.
class LyricLine {
  final Duration time;
  final String text;

  /// Which voice sings the line in a duet (Enhanced LRC's `v1:`, `v2:` …),
  /// or null when the lyrics don't say.
  final int? singer;

  const LyricLine(this.time, this.text, {this.singer});
}

/// Standard LRC line: `[mm:ss.xx]text` or `[mm:ss.xxx]text`, optionally with
/// more than one timestamp before the text (`[00:12.00][00:45.00]text`, used
/// by files that repeat a chorus at the same lyric line). Metadata tags
/// (`[ar:...]`, `[ti:...]`, `[al:...]`, `[offset:...]`, etc.) and blank or
/// unparsable lines are silently skipped rather than shown as garbage lyric
/// text.
final _timestamp = RegExp(r'^\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]');

/// Enhanced LRC (word-level timing, as in Apple Music exports) adds a
/// `<mm:ss.xx>` before each word and an optional singer marker (`v1:`,
/// `v2:`) at the start of the text. Both are stripped from the text (the
/// stored lyrics keep them); the singer is kept as [LyricLine.singer].
final _wordTimestamp = RegExp(r'<\d{1,3}:\d{2}(?:[.:]\d{1,3})?>');
final _singerMarker = RegExp(r'^v(\d+):\s*');
final _spaces = RegExp(r'\s+');

/// The lyric text after a line's timestamps, without Enhanced LRC codes,
/// and the singer its marker named. Plain lines are only trimmed, so
/// ordinary lyrics are shown as written.
(String, int?) _lyricText(String rest) {
  var text = rest.trim();
  final marker = _singerMarker.firstMatch(text);
  final singer = marker == null ? null : int.parse(marker.group(1)!);
  if (marker != null) text = text.substring(marker.end);
  if (!_wordTimestamp.hasMatch(text)) return (text, singer);
  final clean = text
      .replaceAll(_wordTimestamp, '')
      .replaceAll(_spaces, ' ')
      .trim();
  return (clean, singer);
}

/// Parses raw `.lrc` file content into time-ordered lyric lines. Never
/// throws — a malformed or non-LRC file just yields fewer (or zero) lines
/// rather than crashing the scan that reads it.
List<LyricLine> parseLrc(String content) {
  final lines = <LyricLine>[];

  for (final rawLine in content.split(RegExp(r'\r\n|\r|\n'))) {
    var remaining = rawLine;
    final timestamps = <Duration>[];

    while (true) {
      final match = _timestamp.firstMatch(remaining);
      if (match == null) break;
      final minutes = int.parse(match.group(1)!);
      final seconds = int.parse(match.group(2)!);
      final fraction = match.group(3);
      final millis = fraction == null
          ? 0
          : int.parse(fraction.padRight(3, '0').substring(0, 3));
      timestamps.add(
        Duration(minutes: minutes, seconds: seconds, milliseconds: millis),
      );
      remaining = remaining.substring(match.end);
    }

    if (timestamps.isEmpty) continue;
    final (text, singer) = _lyricText(remaining);
    if (text.isEmpty) continue;
    for (final time in timestamps) {
      lines.add(LyricLine(time, text, singer: singer));
    }
  }

  lines.sort((a, b) => a.time.compareTo(b.time));
  return lines;
}

/// Index of the line that should be highlighted at [position] — the last
/// line whose timestamp is at or before it, or -1 before the first line
/// starts. [lines] must already be time-sorted (as [parseLrc] returns them).
int activeLyricIndex(List<LyricLine> lines, Duration position) {
  var active = -1;
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].time > position) break;
    active = i;
  }
  return active;
}
