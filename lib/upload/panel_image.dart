import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import 'panel_frame.dart';

/// A card image converted for the panel: the frame to upload and a PNG of
/// exactly what the panel will show.
class PanelImage {
  const PanelImage({required this.frame, required this.previewPng});

  final Uint8List frame;
  final Uint8List previewPng;

  int get crc32 => PanelFrame.crc32(frame);
}

typedef PanelImageConverter = Future<PanelImage> Function(Uint8List encoded);

const defaultSaturation = 1.8;
const defaultContrast = 1.2;

Future<PanelImage> convertToPanelImageInBackground(Uint8List encoded) =>
    compute(convertToPanelImage, encoded);

/// Runs the image pipeline from `tools/png_to_epd.py` on an encoded image.
PanelImage convertToPanelImage(Uint8List encoded) {
  final fitted = fitToPanel(compositeOnWhite(_decode(encoded)));
  final rgb = fitted.getBytes(order: img.ChannelOrder.rgb);
  enhance(rgb, saturation: defaultSaturation, contrast: defaultContrast);
  final indices = ditherToPanelColors(rgb, fitted.width, fitted.height);
  return PanelImage(
    frame: PanelFrame.pack(indices, fitted.width, fitted.height),
    previewPng: img.encodePng(
      paletteIndicesToImage(indices, fitted.width, fitted.height),
    ),
  );
}

img.Image _decode(Uint8List encoded) {
  const failure = FormatException("The card image couldn't be decoded");
  try {
    return img.decodeImage(encoded) ?? (throw failure);
  } on RangeError {
    // package:image reads past the end of truncated files.
    throw failure;
  }
}

img.Image compositeOnWhite(img.Image source) {
  final canvas = img.Image(
    width: source.width,
    height: source.height,
    numChannels: 3,
  );
  img.fill(canvas, color: img.ColorRgb8(255, 255, 255));
  return img.compositeImage(
    canvas,
    source.convert(format: img.Format.uint8, numChannels: 4),
  );
}

/// Scales to the panel height and centers on a white canvas, cropping the
/// sides of anything wider.
img.Image fitToPanel(img.Image source) {
  final portrait = source.height >= source.width;
  final targetWidth = portrait ? PanelFrame.width : PanelFrame.height;
  final targetHeight = portrait ? PanelFrame.height : PanelFrame.width;
  final scaledWidth = _roundHalfToEven(
    source.width * targetHeight / source.height,
  );
  final scaled = scaledWidth == source.width && targetHeight == source.height
      ? source
      : img.copyResize(
          source,
          width: scaledWidth,
          height: targetHeight,
          interpolation: img.Interpolation.linear,
        );
  final left = ((targetWidth - scaledWidth) / 2).floor();
  if (left < 0) {
    return img.copyCrop(
      scaled,
      x: -left,
      y: 0,
      width: targetWidth,
      height: targetHeight,
    );
  }
  final canvas = img.Image(
    width: targetWidth,
    height: targetHeight,
    numChannels: 3,
  );
  img.fill(canvas, color: img.ColorRgb8(255, 255, 255));
  return img.compositeImage(canvas, scaled, dstX: left);
}

/// Boosts saturation and contrast of packed RGB bytes in place.
///
/// Reproduces Pillow's `ImageEnhance.Color` and `ImageEnhance.Contrast`,
/// which blend toward the pixel's luma and the image's mean luma. The
/// adjustColor filter in package:image uses different formulas.
void enhance(
  Uint8List rgb, {
  required double saturation,
  required double contrast,
}) {
  for (var i = 0; i < rgb.length; i += 3) {
    final gray = _luma(rgb[i], rgb[i + 1], rgb[i + 2]);
    for (var c = i; c < i + 3; c++) {
      rgb[c] = _extrapolate(gray, rgb[c], saturation);
    }
  }
  final mean = _meanLuma(rgb);
  for (var i = 0; i < rgb.length; i++) {
    rgb[i] = _extrapolate(mean, rgb[i], contrast);
  }
}

img.Image paletteIndicesToImage(Uint8List indices, int width, int height) {
  final rgb = Uint8List(indices.length * 3);
  for (var i = 0; i < indices.length; i++) {
    final color = PanelColor.values[indices[i]];
    rgb[i * 3] = color.r;
    rgb[i * 3 + 1] = color.g;
    rgb[i * 3 + 2] = color.b;
  }
  return img.Image.fromBytes(
    width: width,
    height: height,
    bytes: rgb.buffer,
    numChannels: 3,
  );
}

int _luma(int r, int g, int b) =>
    (r * 19595 + g * 38470 + b * 7471 + 0x8000) >> 16;

int _meanLuma(Uint8List rgb) {
  var sum = 0;
  for (var i = 0; i < rgb.length; i += 3) {
    sum += _luma(rgb[i], rgb[i + 1], rgb[i + 2]);
  }
  return (sum / (rgb.length ~/ 3) + 0.5).toInt();
}

final _float32 = Float32List(1);

double _toFloat32(double value) {
  _float32[0] = value;
  return _float32[0];
}

// Pillow blends in single precision and truncates, so 1.8 * 5 gives 8, not 9.
int _extrapolate(int from, int to, double factor) {
  final scaled = _toFloat32(_toFloat32(factor) * (to - from));
  return _toFloat32(from + scaled).clamp(0, 255).toInt();
}

// Python's round(), which png_to_epd.py uses for the scaled width.
int _roundHalfToEven(double value) {
  final floor = value.floor();
  final fraction = value - floor;
  if (fraction != 0.5) return value.round();
  return floor.isEven ? floor : floor + 1;
}
