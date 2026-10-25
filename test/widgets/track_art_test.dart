import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:music_player/widgets/themed/track_art.dart';

void main() {
  test('decode width is the shown size in pixels, rounded up to 64', () {
    expect(decodeWidth(40, 1), 64);
    expect(decodeWidth(40, 2), 128, reason: '80 px rounds up');
    expect(decodeWidth(320, 1), 320, reason: 'already a 64 px step');
    expect(decodeWidth(300, 1.5), 512, reason: '450 px rounds up');
    expect(decodeWidth(0, 1), 64, reason: 'never zero');
  });

  testWidgets('a large cover is decoded at display size, not full size', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: TrackArt(albumArtPath: '/nowhere/cover.art', size: 300),
        ),
      ),
    );

    final image = tester.widget<Image>(find.byType(Image)).image;
    expect(image, isA<ResizeImage>());
    expect((image as ResizeImage).width, 640, reason: '600 px rounds up');
  });
}
