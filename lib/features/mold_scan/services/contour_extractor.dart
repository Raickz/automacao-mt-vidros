import 'dart:math';

import 'package:image/image.dart' as img;

import '../../measurement/services/homography.dart';

class MmRect {
  final double left;
  final double top;
  final double right;
  final double bottom;

  const MmRect({required this.left, required this.top, required this.right, required this.bottom});
}

class ContourExtractionException implements Exception {
  final String message;
  const ContourExtractionException(this.message);

  @override
  String toString() => message;
}

class ContourExtractor {
  static const _clockwiseOffsets = [
    (1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1), (0, -1), (1, -1),
  ];

  /// Measures the board's actual background color directly from the photo,
  /// instead of assuming a fixed value. A physically painted board will
  /// never match a hardcoded RGB exactly (paint mixing, lighting, camera
  /// white balance all shift it), so detection is calibrated per-photo.
  ///
  /// Samples a small patch just inside each of the 4 board corners — close
  /// enough to the corner to sit outside both the markers' own footprint
  /// and a centered mold, but still on the board itself.
  static (int, int, int) sampleBackgroundColor({
    required img.Image image,
    required double pixelsPerMm,
    required double boardWidthMm,
    required double boardHeightMm,
    double cornerInsetMm = 10,
  }) {
    final corners = [
      (cornerInsetMm, cornerInsetMm),
      (boardWidthMm - cornerInsetMm, cornerInsetMm),
      (cornerInsetMm, boardHeightMm - cornerInsetMm),
      (boardWidthMm - cornerInsetMm, boardHeightMm - cornerInsetMm),
    ];

    var sumR = 0, sumG = 0, sumB = 0, count = 0;
    for (final corner in corners) {
      final px = (corner.$1 * pixelsPerMm).round().clamp(0, image.width - 1);
      final py = (corner.$2 * pixelsPerMm).round().clamp(0, image.height - 1);
      final pixel = image.getPixel(px, py);
      sumR += pixel.r.toInt();
      sumG += pixel.g.toInt();
      sumB += pixel.b.toInt();
      count++;
    }

    return (sumR ~/ count, sumG ~/ count, sumB ~/ count);
  }

  /// Extracts the outer boundary of the foreground object in [image] (the
  /// photographed mold) against a known solid background color, returning
  /// the contour as real-world millimeter points.
  ///
  /// [excludedRegionsMm] lets callers mask out known fixed elements of the
  /// board (the 4 corner QR markers) so they aren't mistaken for the mold —
  /// the markers contrast with the background just as much as the mold
  /// does, and being near the top-left corner, the raster scan would
  /// otherwise find one of them before ever reaching the actual mold.
  static List<Point2D> extractFromImage({
    required img.Image image,
    required int backgroundR,
    required int backgroundG,
    required int backgroundB,
    required double pixelsPerMm,
    double colorThreshold = 60,
    List<MmRect> excludedRegionsMm = const [],
  }) {
    bool isExcluded(int x, int y) {
      if (excludedRegionsMm.isEmpty) return false;
      final mmX = x / pixelsPerMm;
      final mmY = y / pixelsPerMm;
      for (final r in excludedRegionsMm) {
        if (mmX >= r.left && mmX <= r.right && mmY >= r.top && mmY <= r.bottom) {
          return true;
        }
      }
      return false;
    }

    bool isForeground(int x, int y) {
      if (x < 0 || y < 0 || x >= image.width || y >= image.height) return false;
      if (isExcluded(x, y)) return false;
      final p = image.getPixel(x, y);
      final dr = p.r - backgroundR;
      final dg = p.g - backgroundG;
      final db = p.b - backgroundB;
      return sqrt(dr * dr + dg * dg + db * db) > colorThreshold;
    }

    final pixels = traceBoundary(isForeground, image.width, image.height);
    return pixels.map((p) => Point2D(p.$1 / pixelsPerMm, p.$2 / pixelsPerMm)).toList();
  }

  /// Pure boundary-tracing logic (Moore-neighbor tracing), independent of
  /// any image library so it can be unit-tested against synthetic grids.
  static List<(int, int)> traceBoundary(
    bool Function(int x, int y) isForeground,
    int width,
    int height,
  ) {
    int? startX;
    int? startY;
    outer:
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        if (isForeground(x, y)) {
          startX = x;
          startY = y;
          break outer;
        }
      }
    }

    if (startX == null || startY == null) {
      throw const ContourExtractionException(
        'Nenhum objeto foi encontrado sobre o fundo do quadro de referência.',
      );
    }

    final boundary = <(int, int)>[(startX, startY)];
    var backtrackIndex = _offsetIndex(-1, 0);
    var curX = startX, curY = startY;
    final maxSteps = width * height;

    for (var step = 0; step < maxSteps; step++) {
      (int, int)? found;
      var foundIndex = -1;

      for (var i = 1; i <= 8; i++) {
        final idx = (backtrackIndex + i) % 8;
        final off = _clockwiseOffsets[idx];
        final nx = curX + off.$1;
        final ny = curY + off.$2;
        if (isForeground(nx, ny)) {
          found = (nx, ny);
          foundIndex = idx;
          break;
        }
      }

      if (found == null) break; // isolated pixel, nothing more to trace
      if (found.$1 == startX && found.$2 == startY) break; // back to start

      boundary.add(found);
      final off = _clockwiseOffsets[foundIndex];
      backtrackIndex = _offsetIndex(-off.$1, -off.$2);
      curX = found.$1;
      curY = found.$2;
    }

    return boundary;
  }

  static int _offsetIndex(int dx, int dy) {
    for (var i = 0; i < _clockwiseOffsets.length; i++) {
      if (_clockwiseOffsets[i].$1 == dx && _clockwiseOffsets[i].$2 == dy) return i;
    }
    throw StateError('Offset inválido: ($dx, $dy)');
  }
}
