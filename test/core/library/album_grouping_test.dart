import 'package:flutter_test/flutter_test.dart';
import 'package:music_player/core/library/album_grouping.dart';
import 'package:music_player/core/library/metadata/year_parser.dart';

void main() {
  group('albumKeyFor', () {
    test('same album + same album artist share a key', () {
      final a = albumKeyFor(album: 'Abbey Road', albumArtist: 'The Beatles');
      final b = albumKeyFor(album: 'Abbey Road', albumArtist: 'The Beatles');
      expect(a.groupKey, b.groupKey);
    });

    test('same title by different artists does NOT merge', () {
      final a = albumKeyFor(album: 'Greatest Hits', albumArtist: 'Queen');
      final b = albumKeyFor(album: 'Greatest Hits', albumArtist: 'ABBA');
      expect(a.groupKey, isNot(b.groupKey));
    });

    test('case and stray whitespace do not split an album', () {
      final a = albumKeyFor(album: 'Abbey Road', albumArtist: 'The Beatles');
      final b = albumKeyFor(
        album: '  abbey   ROAD ',
        albumArtist: 'the beatles',
      );
      expect(a.groupKey, b.groupKey);
    });

    test('display title keeps the tagged casing, whitespace collapsed', () {
      final k = albumKeyFor(
        album: '  Abbey   Road ',
        albumArtist: 'The Beatles',
      );
      expect(k.title, 'Abbey Road');
      expect(k.artist, 'The Beatles');
    });

    test('falls back to the track artist when there is no album artist', () {
      final withFallback = albumKeyFor(
        album: 'Thriller',
        artist: 'Michael Jackson',
      );
      final explicit = albumKeyFor(
        album: 'Thriller',
        albumArtist: 'Michael Jackson',
      );
      expect(withFallback.groupKey, explicit.groupKey);
      expect(withFallback.artist, 'Michael Jackson');
    });

    test('album artist wins over the track artist (guest features)', () {
      final k = albumKeyFor(
        album: 'Album',
        albumArtist: 'Main Artist',
        artist: 'Main Artist feat. Guest',
      );
      expect(k.artist, 'Main Artist');
    });

    test('no artist info at all is still a valid, distinct album', () {
      final k = albumKeyFor(album: 'Mystery');
      expect(k.isUnknown, isFalse);
      expect(k.artist, isNull);
      expect(
        k.groupKey,
        isNot(albumKeyFor(album: 'Mystery', artist: 'X').groupKey),
      );
    });

    test(
      'missing, empty, whitespace-only and control-char albums are Unknown',
      () {
        for (final broken in [null, '', '   ', '\u0000\u0001', '\t\n']) {
          final k = albumKeyFor(album: broken, albumArtist: 'Someone');
          expect(k.isUnknown, isTrue, reason: 'album=${broken.toString()}');
          expect(k.title, unknownAlbumTitle);
          expect(k.groupKey, unknownAlbumGroupKey);
          expect(
            k.artist,
            isNull,
            reason: 'unknown bucket has no single artist',
          );
        }
      },
    );

    test(
      'a real album literally titled "Unknown Album" stays separate from the bucket',
      () {
        final real = albumKeyFor(album: 'Unknown Album', albumArtist: 'A Band');
        expect(real.isUnknown, isFalse);
        expect(real.groupKey, isNot(unknownAlbumGroupKey));
      },
    );

    test(
      'field boundaries cannot be forged by shifting spaces between them',
      () {
        final a = albumKeyFor(album: 'a', albumArtist: 'b c');
        final b = albumKeyFor(album: 'a b', albumArtist: 'c');
        expect(a.groupKey, isNot(b.groupKey));
      },
    );
  });

  group('parseLeadingYear', () {
    test('bare year', () => expect(parseLeadingYear('2019'), 2019));
    test('ISO date', () => expect(parseLeadingYear('2019-05-03'), 2019));
    test(
      'ISO timestamp',
      () => expect(parseLeadingYear('1999-12-31T23:59:59Z'), 1999),
    );
    test(
      'year at the end of a d/m/y date',
      () => expect(parseLeadingYear('05/03/2019'), 2019),
    );
    test('null / empty / garbage give null', () {
      expect(parseLeadingYear(null), isNull);
      expect(parseLeadingYear(''), isNull);
      expect(parseLeadingYear('unknown'), isNull);
    });
    test('does not slice a year out of a longer digit run', () {
      expect(parseLeadingYear('12345'), isNull);
      expect(parseLeadingYear('0000'), isNull);
    });
  });
}
