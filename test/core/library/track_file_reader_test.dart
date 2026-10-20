import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_player/core/library/track_file_reader.dart';
import 'package:path/path.dart' as p;

import '../../helpers/rust_lib.dart';

/// Tiny ffmpeg-tagged files (rust/tests/fixtures/make_fixtures.sh).
String _fixture(String name) =>
    p.join(Directory.current.path, 'rust', 'tests', 'fixtures', name);

const _plain = 'Plain line one\nPlain line two';

void main() {
  setUpAll(loadRustLib);

  late Directory scratch;
  setUp(() => scratch = Directory.systemTemp.createTempSync('mysticjam_tfr_'));
  tearDown(() => scratch.deleteSync(recursive: true));

  String copy(String fixture, String name) =>
      (File(_fixture(fixture)).copySync(p.join(scratch.path, name))).path;

  test('every audio format yields its tags and embedded lyrics', () async {
    for (final name in [
      'tagged.mp3',
      'tagged.flac',
      'tagged.m4a',
      'tagged.mp4',
      'tagged.ogg',
      'tagged.opus',
      'tagged.wma', // Dart reader
    ]) {
      final f = await readTrackFile(_fixture(name));
      final m = f.metadata;
      expect(m.title, 'Fixture Title', reason: name);
      expect(m.artist, 'Fixture Artist', reason: name);
      expect(m.album, 'Fixture Album', reason: name);
      expect(m.albumArtist, 'Fixture Album Artist', reason: name);
      expect(m.genre, 'Fixture Genre', reason: name);
      expect(m.lyrics, _plain, reason: name);
      expect(f.syncedLyrics, isNull, reason: name);
      // The WMA reader doesn't read ffmpeg's plain "date" descriptor or a
      // DWORD track number (see wma_metadata_reader.dart).
      if (name != 'tagged.wma') {
        expect(m.year, 2001, reason: name);
        expect(m.trackNumber, 3, reason: name);
      }
    }
  });

  test('timestamped WMA lyrics are stored as synced', () async {
    final f = await readTrackFile(_fixture('synced.wma'));
    expect(f.metadata.title, 'Synced WMA');
    expect(f.syncedLyrics, '[00:01.00]First\n[00:02.50]Second');
    expect(f.metadata.lyrics, isNull);
  });

  test('a lone [instrumental:true] marker is not lyrics', () async {
    final f = await readTrackFile(_fixture('instrumental.wma'));
    expect(f.metadata.title, 'Instrumental WMA');
    expect(f.metadata.lyrics, isNull);
    expect(f.syncedLyrics, isNull);
  });

  test('LRC header lines are stripped from plain lyrics', () async {
    final f = await readTrackFile(_fixture('headers.wma'));
    expect(f.metadata.lyrics, 'Words here');
    expect(f.syncedLyrics, isNull);
  });

  test('the Dart path also finds the .lrc file and folder cover', () async {
    final wma = copy('tagged.wma', 'song.wma');
    File(p.join(scratch.path, 'song.lrc')).writeAsStringSync('[00:03.00]Hi');
    File(p.join(scratch.path, 'cover.jpg')).writeAsBytesSync([9, 9, 9]);
    final f = await readTrackFile(wma);
    expect(f.syncedLyrics, '[00:03.00]Hi');
    expect(f.metadata.lyrics, _plain, reason: 'plain lyrics kept alongside');
    expect(f.metadata.artwork, [9, 9, 9]);
  });

  test('a big folder cover is stored shrunk, on both reading paths', () async {
    final bigCover = File(_fixture('big_cover.png')).readAsBytesSync();
    File(p.join(scratch.path, 'cover.png')).writeAsBytesSync(bigCover);
    for (final name in ['song.wma', 'song.ogg']) {
      final song = copy('tagged.${name.split('.').last}', name);
      final art = (await readTrackFile(song)).metadata.artwork!;
      // Shrunk covers without transparency are re-encoded as JPEG (FF D8),
      // and are no longer the 2400x1800 original.
      expect(art.take(2), [0xFF, 0xD8], reason: name);
      expect(art, isNot(bigCover), reason: name);
      expect(_jpegSize(art), (1024, 768), reason: name);
    }
  });

  test('broken files never throw', () async {
    final bad = File(p.join(scratch.path, 'broken.flac'))
      ..writeAsStringSync('not audio');
    final f = await readTrackFile(bad.path);
    expect(f.metadata.title, isNull);
    expect(f.syncedLyrics, isNull);
    final missing = await readTrackFile(p.join(scratch.path, 'gone.mp3'));
    expect(missing.metadata.title, isNull);
  });
}

/// Width and height from a JPEG's start-of-frame header.
(int, int) _jpegSize(List<int> b) {
  var i = 2;
  while (i + 9 < b.length) {
    if (b[i] != 0xFF) {
      i++;
      continue;
    }
    final marker = b[i + 1];
    final length = (b[i + 2] << 8) | b[i + 3];
    if (marker >= 0xC0 && marker <= 0xC3) {
      return ((b[i + 7] << 8) | b[i + 8], (b[i + 5] << 8) | b[i + 6]);
    }
    i += 2 + length;
  }
  throw StateError('no JPEG frame header');
}
