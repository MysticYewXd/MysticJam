import 'package:flutter_test/flutter_test.dart';
import 'package:music_player/core/library/metadata/track_number_parser.dart';

void main() {
  group('parseLeadingTrackNumber', () {
    test('parses a bare number', () {
      expect(parseLeadingTrackNumber('5'), 5);
    });

    test('parses "track/total" format, taking only the track', () {
      expect(parseLeadingTrackNumber('5/12'), 5);
    });

    test('trims surrounding whitespace', () {
      expect(parseLeadingTrackNumber('  7  '), 7);
      expect(parseLeadingTrackNumber(' 3 / 10'), 3);
    });

    test('returns null for null input', () {
      expect(parseLeadingTrackNumber(null), isNull);
    });

    test('returns null for an empty string', () {
      expect(parseLeadingTrackNumber(''), isNull);
    });

    test('returns null for non-numeric garbage', () {
      expect(parseLeadingTrackNumber('unknown'), isNull);
    });

    test('returns null rather than 0 for a leading slash with no number', () {
      expect(parseLeadingTrackNumber('/12'), isNull);
    });

    test('parses "0" as track zero, not as unknown', () {
      // A real (if rare) case — hidden tracks are sometimes tagged 0.
      // parseLeadingTrackNumber itself has no opinion on "unknown"; that
      // distinction is null vs. non-null, handled by its callers.
      expect(parseLeadingTrackNumber('0'), 0);
    });
  });
}
