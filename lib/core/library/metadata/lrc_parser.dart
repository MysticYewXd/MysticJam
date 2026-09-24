/// One line of synced lyrics: the instant it starts, and its text.
class LyricLine {
  final Duration time;
  final String text;

  const LyricLine(this.time, this.text);
}

/// Standard LRC line: `[mm:ss.xx]text` or `[mm:ss.xxx]text`, optionally with
/// more than one timestamp before the text (`[00:12.00][00:45.00]text`, used
/// by files that repeat a chorus at the same lyric line). Metadata tags
/// (`[ar:...]`, `[ti:...]`, `[al:...]`, `[offset:...]`, etc.) and blank or
/// unparsable lines are silently skipped rather than shown as garbage lyric
/// text.
final _timestamp = RegExp(r'^\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]');

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
    final text = remaining.trim();
    if (text.isEmpty) continue;
    for (final time in timestamps) {
      lines.add(LyricLine(time, text));
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
