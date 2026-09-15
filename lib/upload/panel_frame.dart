import 'dart:typed_data';

import 'package:archive/archive.dart' show getCrc32;

/// The six inks of the card's e-ink panel, with the RGB used for dithering.
enum PanelColor {
  black(code: 0x0, r: 0, g: 0, b: 0),
  white(code: 0x1, r: 255, g: 255, b: 255),
  yellow(code: 0x2, r: 255, g: 255, b: 0),
  red(code: 0x3, r: 255, g: 0, b: 0),
  blue(code: 0x5, r: 0, g: 0, b: 255),
  green(code: 0x6, r: 0, g: 255, b: 0);

  const PanelColor({
    required this.code,
    required this.r,
    required this.g,
    required this.b,
  });

  final int code;
  final int r;
  final int g;
  final int b;

  int channel(int index) => switch (index) {
    0 => r,
    1 => g,
    _ => b,
  };

  /// The palette index closest to an RGB value.
  ///
  /// Distances are measured from the value with its two low bits cleared and
  /// ties go to the earlier color, as in Pillow's palette cache.
  static int nearestIndex(int r, int g, int b) {
    final rq = r & 0xFC, gq = g & 0xFC, bq = b & 0xFC;
    var best = 0;
    var bestDistance = 1 << 30;
    for (var i = 0; i < values.length; i++) {
      final color = values[i];
      final dr = rq - color.r, dg = gq - color.g, db = bq - color.b;
      final distance = dr * dr + dg * dg + db * db;
      if (distance < bestDistance) {
        bestDistance = distance;
        best = i;
      }
    }
    return best;
  }
}

abstract final class PanelFrame {
  static const width = 400;
  static const height = 600;
  static const sizeInBytes = width * height ~/ 2;

  /// Packs palette indices of a 400x600 or 600x400 image into a panel frame.
  ///
  /// Landscape images are rotated 90 degrees clockwise into the panel's
  /// portrait orientation.
  static Uint8List pack(
    Uint8List paletteIndices,
    int imageWidth,
    int imageHeight,
  ) {
    final landscape = imageWidth == height && imageHeight == width;
    if (!landscape && (imageWidth != width || imageHeight != height)) {
      throw ArgumentError(
        'Expected a ${width}x$height or ${height}x$width image, '
        'got ${imageWidth}x$imageHeight',
      );
    }
    final frame = Uint8List(sizeInBytes);
    var pixel = 0;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++, pixel++) {
        final source = landscape
            ? (imageHeight - 1 - x) * imageWidth + y
            : y * imageWidth + x;
        final code = PanelColor.values[paletteIndices[source]].code;
        frame[pixel >> 1] |= pixel.isEven ? code << 4 : code;
      }
    }
    return frame;
  }

  /// Standard CRC-32 (zlib), as the upload START message expects.
  static int crc32(List<int> frame) => getCrc32(frame);
}

/// Floyd-Steinberg dithers packed RGB bytes to [PanelColor] indices.
///
/// Mirrors Pillow's integer implementation, which `png_to_epd.py` uses, so
/// frames match the reference byte for byte.
Uint8List ditherToPanelColors(Uint8List rgb, int width, int height) {
  final indices = Uint8List(width * height);
  // errorsBelow[x + 1] holds the error diffused into column x of the next row.
  final errorsBelow = Int32List((width + 1) * 3);
  final errorRight = Int32List(3);
  final pendingBelow = Int32List(3);
  final pendingBelowRight = Int32List(3);
  final value = Int32List(3);

  for (var y = 0; y < height; y++) {
    errorRight.fillRange(0, 3, 0);
    pendingBelow.fillRange(0, 3, 0);
    pendingBelowRight.fillRange(0, 3, 0);
    for (var x = 0; x < width; x++) {
      final pixel = y * width + x;
      for (var c = 0; c < 3; c++) {
        final diffused = (errorRight[c] + errorsBelow[(x + 1) * 3 + c]) ~/ 16;
        value[c] = (rgb[pixel * 3 + c] + diffused).clamp(0, 255);
      }
      final index = PanelColor.nearestIndex(value[0], value[1], value[2]);
      indices[pixel] = index;
      final color = PanelColor.values[index];
      for (var c = 0; c < 3; c++) {
        final error = value[c] - color.channel(c);
        errorsBelow[x * 3 + c] = 3 * error + pendingBelow[c];
        pendingBelow[c] = 5 * error + pendingBelowRight[c];
        pendingBelowRight[c] = error;
        errorRight[c] = 7 * error;
      }
    }
    // Pillow stores the blue channel's leftovers in all three slots here.
    errorsBelow[width * 3] = pendingBelow[2];
    errorsBelow[width * 3 + 1] = pendingBelowRight[2];
    errorsBelow[width * 3 + 2] = pendingBelowRight[2];
  }
  return indices;
}
