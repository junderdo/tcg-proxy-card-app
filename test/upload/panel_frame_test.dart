import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tcg_proxy_card_app/upload/panel_frame.dart';

void main() {
  final black = PanelColor.black.index;
  final white = PanelColor.white.index;
  final validCodes = {for (final color in PanelColor.values) color.code};

  Uint8List filled(int width, int height, int index) =>
      Uint8List(width * height)..fillRange(0, width * height, index);

  Uint8List rgbPixels(List<List<int>> pixels) =>
      Uint8List.fromList([for (final pixel in pixels) ...pixel]);

  group('PanelFrame.pack', () {
    test('produces a 120,000-byte frame', () {
      final frame = PanelFrame.pack(filled(400, 600, white), 400, 600);
      expect(frame, hasLength(120000));
      expect(frame.every((byte) => byte == 0x11), isTrue);
    });

    test('puts the first pixel of each pair in the high nibble', () {
      final indices = filled(400, 600, white);
      indices.setAll(0, [
        PanelColor.black.index,
        PanelColor.yellow.index,
        PanelColor.red.index,
        PanelColor.blue.index,
        PanelColor.green.index,
        PanelColor.white.index,
      ]);

      final frame = PanelFrame.pack(indices, 400, 600);

      expect(frame.sublist(0, 4), [0x02, 0x35, 0x61, 0x11]);
    });

    test('only emits defined color codes', () {
      final random = Random(7);
      final indices = Uint8List.fromList(
        List.generate(240000, (_) => random.nextInt(PanelColor.values.length)),
      );

      final frame = PanelFrame.pack(indices, 400, 600);

      final codes = {
        for (final byte in frame) ...[byte >> 4, byte & 0x0F],
      };
      expect(validCodes.containsAll(codes), isTrue);
    });

    test('rotates a landscape image 90 degrees clockwise', () {
      final indices = filled(600, 400, white);
      indices[399 * 600] = black; // bottom-left
      indices[0] = PanelColor.red.index; // top-left
      indices[599] = PanelColor.blue.index; // top-right

      final frame = PanelFrame.pack(indices, 600, 400);

      expect(frame[0] >> 4, PanelColor.black.code);
      expect(frame[199] & 0x0F, PanelColor.red.code);
      expect(frame[119999] & 0x0F, PanelColor.blue.code);
    });

    test('rejects other sizes', () {
      expect(
        () => PanelFrame.pack(filled(400, 400, white), 400, 400),
        throwsArgumentError,
      );
    });
  });

  group('PanelColor.nearestIndex', () {
    test('maps colors to the closest ink', () {
      expect(PanelColor.nearestIndex(240, 230, 20), PanelColor.yellow.index);
      expect(PanelColor.nearestIndex(20, 30, 200), PanelColor.blue.index);
      expect(PanelColor.nearestIndex(100, 100, 100), black);
    });

    test('ignores the two low bits, like Pillow', () {
      // 129 would be closer to white; its quantized value 128 is closer to
      // white too, but 127 quantizes to 124 and lands on black.
      expect(PanelColor.nearestIndex(127, 127, 127), black);
      expect(PanelColor.nearestIndex(128, 128, 128), white);
    });
  });

  group('ditherToPanelColors', () {
    test('leaves palette colors unchanged', () {
      final rgb = rgbPixels([
        [0, 0, 0],
        [255, 255, 255],
        [255, 0, 0],
        [0, 255, 0],
      ]);

      expect(ditherToPanelColors(rgb, 2, 2), [
        black,
        white,
        PanelColor.red.index,
        PanelColor.green.index,
      ]);
    });

    test('alternates black and white across a mid-gray row', () {
      final rgb = rgbPixels(List.filled(4, [128, 128, 128]));

      expect(ditherToPanelColors(rgb, 4, 1), [white, black, white, black]);
    });

    // Expected indices come from Pillow's quantize(), as png_to_epd.py uses.
    test('diffuses error to the right and into the next row', () {
      final rgb = rgbPixels(List.filled(9, [150, 150, 150]));

      expect(ditherToPanelColors(rgb, 3, 3), [1, 0, 1, 1, 0, 1, 1, 0, 1]);
    });

    test('matches Pillow on mixed colors', () {
      final tall = rgbPixels([
        [200, 120, 40],
        [30, 90, 160],
        [90, 200, 90],
        [250, 250, 120],
        [120, 30, 60],
        [180, 180, 180],
      ]);
      final wide = rgbPixels([
        [60, 60, 200],
        [200, 60, 60],
        [60, 200, 60],
        [128, 128, 0],
        [0, 128, 128],
        [128, 0, 128],
      ]);

      expect(ditherToPanelColors(tall, 2, 3), [3, 4, 5, 1, 3, 1]);
      expect(ditherToPanelColors(wide, 3, 2), [4, 3, 5, 2, 4, 3]);
    });
  });

  test('CRC-32 matches the standard check value', () {
    expect(PanelFrame.crc32(ascii.encode('123456789')), 0xCBF43926);
  });
}
