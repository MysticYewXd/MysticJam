import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:music_player/core/library/metadata/id3_metadata_reader.dart';

/// Hand-built ID3 tags, so these tests pin down that reading only the tag
/// regions of an MP3 (not the whole file) still finds everything.
List<int> _synchsafe(int n) => [
  (n >> 21) & 0x7f,
  (n >> 14) & 0x7f,
  (n >> 7) & 0x7f,
  n & 0x7f,
];

List<int> _be32(int n) => [
  (n >> 24) & 0xff,
  (n >> 16) & 0xff,
  (n >> 8) & 0xff,
  n & 0xff,
];

List<int> _frame(int version, String id, List<int> data) => [
  ...ascii.encode(id),
  ...(version >= 4 ? _synchsafe(data.length) : _be32(data.length)),
  0,
  0,
  ...data,
];

List<int> _text(String s) => [0, ...latin1.encode(s)];

List<int> _id3v2(int version, {required List<int> art, int padding = 0}) {
  final frames = [
    ..._frame(version, 'TIT2', _text('Night Drive')),
    ..._frame(version, 'TPE1', _text('Vesper')),
    ..._frame(version, 'TALB', _text('Lanterns')),
    ..._frame(version, 'APIC', [
      0,
      ...latin1.encode('image/jpeg'),
      0,
      3,
      0,
      ...art,
    ]),
    ...List.filled(padding, 0),
  ];
  return [
    ...ascii.encode('ID3'),
    version,
    0,
    0,
    ..._synchsafe(frames.length),
    ...frames,
  ];
}

List<int> _id3v1() {
  List<int> field(String s, int len) => [
    ...latin1.encode(s),
    ...List.filled(len - s.length, 0),
  ];
  return [
    ...ascii.encode('TAG'),
    ...field('V1 Title', 30),
    ...field('V1 Artist', 30),
    ...field('V1 Album', 30),
    ...field('1999', 4),
    ...field('', 28),
    0,
    7, // track number
    17, // genre: Rock
  ];
}

void main() {
  late Directory tempDir;
  final rng = Random(42);
  // Big enough that a whole-file read would be noticeably wasteful, and
  // random so it can't accidentally look like a tag.
  final audio = List<int>.generate(512 * 1024, (_) => rng.nextInt(256));
  // A minimal JPEG shape (SOI ... EOI) — dart_tags locates the picture by
  // its JPEG markers. The filler never contains 0xFF, so no stray marker.
  final art = [
    0xFF,
    0xD8,
    ...List<int>.generate(20 * 1024, (i) => (i * 7) % 255),
    0xFF,
    0xD9,
  ];

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('mysticjam_id3_test_');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  String write(String name, List<int> bytes) {
    final path = '${tempDir.path}/$name';
    File(path).writeAsBytesSync(bytes);
    return path;
  }

  for (final version in [3, 4]) {
    for (final padding in [0, 1024]) {
      test('ID3v2.$version tag (padding $padding) is read in full', () async {
        final path = write('a.mp3', [
          ..._id3v2(version, art: art, padding: padding),
          ...audio,
          ..._id3v1(),
        ]);

        final m = await readId3Metadata(path);

        expect(m.title, 'Night Drive');
        expect(m.artist, 'Vesper');
        expect(m.album, 'Lanterns');
        expect(m.artwork, Uint8List.fromList(art));
        // ID3v1 still fills in what ID3v2 didn't provide.
        expect(m.year, 1999);
        expect(m.trackNumber, 7);
      });
    }
  }

  test('a file with only an ID3v1 tag still gets its tags', () async {
    final path = write('b.mp3', [...audio, ..._id3v1()]);

    final m = await readId3Metadata(path);

    expect(m.title, 'V1 Title');
    expect(m.artist, 'V1 Artist');
    expect(m.album, 'V1 Album');
  });

  test('a file smaller than its tag regions is read whole', () async {
    final path = write('c.mp3', _id3v1());

    final m = await readId3Metadata(path);

    expect(m.title, 'V1 Title');
  });

  test('a file with no tags at all comes back empty', () async {
    final path = write('d.mp3', audio);

    final m = await readId3Metadata(path);

    expect(m.title, isNull);
    expect(m.artwork, isNull);
  });
}
