import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_player/core/library/metadata/metadata_reader.dart';
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
      expect(f.metadata.title, 'Fixture Title', reason: name);
      expect(f.metadata.album, 'Fixture Album', reason: name);
      expect(f.metadata.lyrics, _plain, reason: name);
      expect(f.syncedLyrics, isNull, reason: name);
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

  test('Rust and the Dart readers agree on tags', () async {
    for (final name in [
      'tagged.mp3',
      'tagged.flac',
      'tagged.m4a',
      'tagged.ogg',
      'tagged.opus',
    ]) {
      final dart = await readTrackMetadata(_fixture(name));
      final rust = (await readTrackFile(_fixture(name))).metadata;
      // The old Dart MP3 reader (package:dart_tags) leaves the ID3 string
      // terminator on: 'Title\x00'. Rust doesn't; compare without it.
      String? clean(String? s) => s?.replaceAll(RegExp(r'\x00+$'), '');
      expect(rust.title, clean(dart.title), reason: '$name title');
      expect(rust.artist, clean(dart.artist), reason: '$name artist');
      expect(rust.album, clean(dart.album), reason: '$name album');
      expect(
        rust.albumArtist,
        clean(dart.albumArtist),
        reason: '$name album artist',
      );
      expect(rust.genre, clean(dart.genre), reason: '$name genre');
      expect(rust.year, dart.year, reason: '$name year');
      expect(rust.trackNumber, dart.trackNumber, reason: '$name track');
    }
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
