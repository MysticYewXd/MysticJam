import 'package:flutter_test/flutter_test.dart';
import 'package:music_player/core/library/metadata/lrc_parser.dart';

void main() {
  group('parseLrc', () {
    test('parses standard mm:ss.xx lines in order', () {
      final lines = parseLrc('''
[00:01.00]First
[00:05.50]Second
[00:12.25]Third
''');
      expect(lines.map((l) => l.text), ['First', 'Second', 'Third']);
      expect(lines[0].time, const Duration(seconds: 1));
      expect(lines[1].time, const Duration(seconds: 5, milliseconds: 500));
      expect(lines[2].time, const Duration(seconds: 12, milliseconds: 250));
    });

    test('sorts lines that appear out of order in the file', () {
      final lines = parseLrc('[00:10.00]Later\n[00:01.00]Earlier');
      expect(lines.map((l) => l.text), ['Earlier', 'Later']);
    });

    test('a line with two timestamps repeats at both times', () {
      final lines = parseLrc('[00:01.00][00:30.00]Chorus');
      expect(lines, hasLength(2));
      expect(lines[0].text, 'Chorus');
      expect(lines[1].text, 'Chorus');
      expect(lines[0].time, const Duration(seconds: 1));
      expect(lines[1].time, const Duration(seconds: 30));
    });

    test('metadata tags are ignored, not shown as lyric lines', () {
      final lines = parseLrc('''
[ar:Some Artist]
[ti:Some Title]
[00:01.00]Real lyric
''');
      expect(lines, hasLength(1));
      expect(lines.single.text, 'Real lyric');
    });

    test('blank lines and lines with no timestamp are skipped', () {
      final lines = parseLrc('''
not a timestamp line
[00:01.00]

[00:02.00]Kept
''');
      expect(lines, hasLength(1));
      expect(lines.single.text, 'Kept');
    });

    test('a millisecond field with 3 digits is read precisely', () {
      final lines = parseLrc('[00:01.123]Precise');
      expect(lines.single.time, const Duration(seconds: 1, milliseconds: 123));
    });

    test(
      'handles hours-scale minute fields (e.g. 100:00) without crashing',
      () {
        final lines = parseLrc('[100:00.00]Long file');
        expect(lines.single.time, const Duration(minutes: 100));
      },
    );

    test('empty or garbage input yields no lines', () {
      expect(parseLrc(''), isEmpty);
      expect(parseLrc('just plain text, no brackets'), isEmpty);
    });
  });

  group('Enhanced LRC (word timing)', () {
    test('word timestamps and the singer marker are removed', () {
      final lines = parseLrc(
        '[00:14.28]v1: <00:14.287>I <00:14.509>know <00:14.794>I '
        '<00:15.092>got <00:15.383>to <00:15.520>be <00:15.806>right '
        '<00:16.091>now<00:16.323>',
      );
      expect(lines.single.text, 'I know I got to be right now');
      expect(lines.single.time, const Duration(seconds: 14, milliseconds: 280));
    });

    test('words joined without spaces stay joined', () {
      final lines = parseLrc(
        '[00:05.01]v1: <00:05.016>Nah-<00:05.273>nah-<00:05.535>nah, '
        '<00:05.821>that<00:07.283>',
      );
      expect(lines.single.text, 'Nah-nah-nah, that');
    });

    test('both two- and three-digit fractions, and a second singer', () {
      final lines = parseLrc('[00:01.00]v2: <00:01.00>Hey <00:01.5>there');
      expect(lines.single.text, 'Hey there');
    });

    test('a line of only word timestamps is skipped', () {
      expect(parseLrc('[00:01.00]v1: <00:01.000><00:02.000>'), isEmpty);
    });

    test('plain lyrics with colons or a mid-line v1: are left alone', () {
      final lines = parseLrc(
        '[00:01.00]Yo: listen  up\n[00:02.00]They said v1: is next',
      );
      expect(lines.map((l) => l.text), [
        'Yo: listen  up',
        'They said v1: is next',
      ]);
    });
  });

  group('activeLyricIndex', () {
    final lines = [
      const LyricLine(Duration(seconds: 1), 'A'),
      const LyricLine(Duration(seconds: 5), 'B'),
      const LyricLine(Duration(seconds: 10), 'C'),
    ];

    test('before the first line, nothing is active', () {
      expect(activeLyricIndex(lines, Duration.zero), -1);
      expect(activeLyricIndex(lines, const Duration(milliseconds: 999)), -1);
    });

    test('exactly on a line\'s timestamp, that line is active', () {
      expect(activeLyricIndex(lines, const Duration(seconds: 5)), 1);
    });

    test('between two lines, the earlier one stays active', () {
      expect(activeLyricIndex(lines, const Duration(seconds: 7)), 1);
    });

    test('past the last line, it stays active', () {
      expect(activeLyricIndex(lines, const Duration(minutes: 5)), 2);
    });

    test('an empty line list is always inactive', () {
      expect(activeLyricIndex(const [], const Duration(seconds: 5)), -1);
    });
  });
}
