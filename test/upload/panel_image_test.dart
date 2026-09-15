import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tcg_proxy_card_app/upload/panel_frame.dart';
import 'package:tcg_proxy_card_app/upload/panel_image.dart';

/// A synthetic image with cut-out transparent squares, generated the same
/// way in Python to produce the reference CRCs below.
img.Image pattern(int width, int height) {
  final image = img.Image(width: width, height: height, numChannels: 4);
  for (final pixel in image) {
    final x = pixel.x, y = pixel.y;
    final transparent = (x ~/ 40 + y ~/ 40) % 5 == 0;
    pixel.setRgba(
      (x * 7 + y * 3) % 256,
      (x * y) % 256,
      (x + 2 * y) % 256,
      transparent ? 0 : 255,
    );
  }
  return image;
}

void main() {
  // CRCs of tools/png_to_epd.py's output for the same images.
  test('matches png_to_epd.py for a portrait image', () {
    final panel = convertToPanelImage(img.encodePng(pattern(400, 600)));
    expect(panel.frame, hasLength(PanelFrame.sizeInBytes));
    expect(panel.crc32, 0x70dfcffb);
  });

  test('matches png_to_epd.py for a landscape image', () {
    final panel = convertToPanelImage(img.encodePng(pattern(600, 400)));
    expect(panel.crc32, 0x6c4cfd2e);
  });

  test('scales a Scryfall-sized card to the panel height and crops', () {
    final card = img.Image(width: 672, height: 936)
      ..clear(img.ColorRgb8(255, 0, 0));
    final panel = convertToPanelImage(img.encodeJpg(card));

    expect(panel.frame, hasLength(PanelFrame.sizeInBytes));
    expect(panel.frame.every((byte) => byte == 0x33), isTrue);
    final preview = img.decodePng(panel.previewPng)!;
    expect((preview.width, preview.height), (400, 600));
  });

  test('pads a narrow image with white', () {
    final strip = img.Image(width: 100, height: 600)
      ..clear(img.ColorRgb8(0, 0, 0));
    final frame = convertToPanelImage(img.encodePng(strip)).frame;

    expect(frame[0], 0x11);
    expect(frame[100], 0x00);
  });

  test('rejects data that is not a complete image', () {
    final png = img.encodePng(img.Image(width: 1, height: 1));
    expect(() => convertToPanelImage(png.sublist(0, 8)), throwsFormatException);
    expect(() => convertToPanelImage(Uint8List(16)), throwsFormatException);
  });
}
