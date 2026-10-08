import 'dart:math';
import 'dart:typed_data';

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

class ContourResult {
  final List<Point2D> contourMm;
  final int areaPx;
  final bool touchesIgnoredBorder;

  const ContourResult({required this.contourMm, required this.areaPx, required this.touchesIgnoredBorder});
}

class ContourExtractor {
  static const _clockwiseOffsets = [
    (1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1), (0, -1), (1, -1),
  ];

  /// Measures the board's actual background color directly from the photo,
  /// instead of assuming a fixed value (paint mixing, lighting and camera
  /// white balance always shift it).
  ///
  /// Samples 4 strips along the board's edges, away from the corner markers
  /// and from where a mold normally sits, and takes the per-channel median
  /// so a stray object, dust or glare in a strip can't skew the result.
  static (int, int, int) estimateBackgroundColor({
    required img.Image image,
    required double pixelsPerMm,
    required double boardWidthMm,
    required double boardHeightMm,
    double stripStartMm = 55,
    double stripEndMm = 120,
    double cornerClearMm = 400,
  }) {
    int px(double mm, int max) => (mm * pixelsPerMm).round().clamp(0, max - 1);

    final w = image.width, h = image.height;
    final xLo = px(cornerClearMm, w), xHi = px(boardWidthMm - cornerClearMm, w);
    final yLo = px(cornerClearMm, h), yHi = px(boardHeightMm - cornerClearMm, h);
    final s0x = px(stripStartMm, w), s1x = px(stripEndMm, w);
    final s0y = px(stripStartMm, h), s1y = px(stripEndMm, h);
    final e0x = px(boardWidthMm - stripEndMm, w), e1x = px(boardWidthMm - stripStartMm, w);
    final e0y = px(boardHeightMm - stripEndMm, h), e1y = px(boardHeightMm - stripStartMm, h);

    final rs = <int>[], gs = <int>[], bs = <int>[];
    final step = max(1, (3 * pixelsPerMm).round());

    void sample(int x0, int x1, int y0, int y1) {
      for (var y = y0; y <= y1; y += step) {
        for (var x = x0; x <= x1; x += step) {
          final p = image.getPixel(x, y);
          rs.add(p.r.toInt());
          gs.add(p.g.toInt());
          bs.add(p.b.toInt());
        }
      }
    }

    sample(xLo, xHi, s0y, s1y);
    sample(xLo, xHi, e0y, e1y);
    sample(s0x, s1x, yLo, yHi);
    sample(e0x, e1x, yLo, yHi);

    if (rs.isEmpty) {
      throw const ContourExtractionException('Imagem pequena demais para estimar a cor do quadro.');
    }

    int median(List<int> v) {
      v.sort();
      return v[v.length ~/ 2];
    }

    return (median(rs), median(gs), median(bs));
  }

  /// Extracts the outer boundary of the largest foreground object in
  /// [image] (the photographed mold) and returns it in millimeters.
  static List<Point2D> extractFromImage({
    required img.Image image,
    required int backgroundR,
    required int backgroundG,
    required int backgroundB,
    required double pixelsPerMm,
    double colorThreshold = 50,
    double minBrightnessRatio = 0.35,
    List<MmRect> excludedRegionsMm = const [],
    double ignoreBorderMm = 0,
  }) {
    return extract(
      image: image,
      backgroundR: backgroundR,
      backgroundG: backgroundG,
      backgroundB: backgroundB,
      pixelsPerMm: pixelsPerMm,
      colorThreshold: colorThreshold,
      minBrightnessRatio: minBrightnessRatio,
      excludedRegionsMm: excludedRegionsMm,
      ignoreBorderMm: ignoreBorderMm,
    ).contourMm;
  }

  /// A pixel is foreground when its *color* (not its brightness) differs
  /// from the background's, or when it is much darker than the background.
  /// Comparing the component of the pixel's color that is orthogonal to the
  /// background color's direction makes the test immune to uneven lighting
  /// across a 2.5m board and to soft shadows (both just scale brightness),
  /// which a plain RGB distance would read as "object".
  ///
  /// Only the largest connected foreground blob is kept, so dust, glare,
  /// leftover paper or seams can't be mistaken for the mold just because
  /// they come first in a raster scan.
  static ContourResult extract({
    required img.Image image,
    required int backgroundR,
    required int backgroundG,
    required int backgroundB,
    required double pixelsPerMm,
    double colorThreshold = 50,
    double minBrightnessRatio = 0.35,
    List<MmRect> excludedRegionsMm = const [],
    double ignoreBorderMm = 0,
    int minAreaPx = 16,
  }) {
    final w = image.width, h = image.height;
    final n = w * h;
    final bytes = image.getBytes(order: img.ChannelOrder.rgb);
    final mask = Uint8List(n);

    final bb = (backgroundR * backgroundR + backgroundG * backgroundG + backgroundB * backgroundB).toDouble();
    final t2 = colorThreshold * colorThreshold;
    var o = 0;
    for (var i = 0; i < n; i++, o += 3) {
      final r = bytes[o], g = bytes[o + 1], b = bytes[o + 2];
      if (bb < 1) {
        if (r * r + g * g + b * b > t2) mask[i] = 1;
        continue;
      }
      final k = (r * backgroundR + g * backgroundG + b * backgroundB) / bb;
      if (k < minBrightnessRatio) {
        mask[i] = 1;
        continue;
      }
      final cr = r - k * backgroundR;
      final cg = g - k * backgroundG;
      final cb = b - k * backgroundB;
      if (cr * cr + cg * cg + cb * cb > t2) mask[i] = 1;
    }

    void clear(int x0, int x1, int y0, int y1) {
      final xa = x0.clamp(0, w - 1), xb = x1.clamp(0, w - 1);
      final ya = y0.clamp(0, h - 1), yb = y1.clamp(0, h - 1);
      if (x1 < 0 || y1 < 0 || x0 > w - 1 || y0 > h - 1) return;
      for (var y = ya; y <= yb; y++) {
        mask.fillRange(y * w + xa, y * w + xb + 1, 0);
      }
    }

    final band = (ignoreBorderMm * pixelsPerMm).ceil();
    if (band > 0) {
      clear(0, band - 1, 0, h - 1);
      clear(w - band, w - 1, 0, h - 1);
      clear(0, w - 1, 0, band - 1);
      clear(0, w - 1, h - band, h - 1);
    }
    for (final r in excludedRegionsMm) {
      clear(
        (r.left * pixelsPerMm).floor(),
        (r.right * pixelsPerMm).ceil(),
        (r.top * pixelsPerMm).floor(),
        (r.bottom * pixelsPerMm).ceil(),
      );
    }

    final labels = Int32List(n);
    final stack = Int32List(n);
    var nextLabel = 0, bestLabel = 0, bestCount = 0;
    for (var start = 0; start < n; start++) {
      if (mask[start] == 0 || labels[start] != 0) continue;
      nextLabel++;
      var sp = 0, count = 0;
      stack[sp++] = start;
      labels[start] = nextLabel;
      while (sp > 0) {
        final p = stack[--sp];
        count++;
        final x = p % w, y = p ~/ w;
        for (var dy = -1; dy <= 1; dy++) {
          final ny = y + dy;
          if (ny < 0 || ny >= h) continue;
          for (var dx = -1; dx <= 1; dx++) {
            final nx = x + dx;
            if (nx < 0 || nx >= w) continue;
            final q = ny * w + nx;
            if (mask[q] != 0 && labels[q] == 0) {
              labels[q] = nextLabel;
              stack[sp++] = q;
            }
          }
        }
      }
      if (count > bestCount) {
        bestCount = count;
        bestLabel = nextLabel;
      }
    }

    if (bestCount < minAreaPx) {
      throw const ContourExtractionException(
        'Nenhum objeto foi encontrado sobre o fundo do quadro de referência.',
      );
    }

    final boundary = traceBoundary(
      (x, y) => x >= 0 && y >= 0 && x < w && y < h && labels[y * w + x] == bestLabel,
      w,
      h,
    );

    var touches = false;
    if (band > 0) {
      for (final p in boundary) {
        if (p.$1 <= band + 1 || p.$2 <= band + 1 || p.$1 >= w - band - 2 || p.$2 >= h - band - 2) {
          touches = true;
          break;
        }
      }
    }

    return ContourResult(
      contourMm: _toMillimetersOutward(boundary, pixelsPerMm),
      areaPx: bestCount,
      touchesIgnoredBorder: touches,
    );
  }

  /// Boundary pixels are the object's outermost pixels, so their centers sit
  /// half a pixel *inside* the true edge — measuring through them would
  /// shrink every dimension by a full pixel. Push each point half a pixel
  /// outward along the local normal to compensate.
  static List<Point2D> _toMillimetersOutward(List<(int, int)> boundary, double pixelsPerMm) {
    final n = boundary.length;
    if (n < 8) {
      return [for (final p in boundary) Point2D((p.$1 + 0.5) / pixelsPerMm, (p.$2 + 0.5) / pixelsPerMm)];
    }

    var area2 = 0.0;
    for (var i = 0; i < n; i++) {
      final a = boundary[i], b = boundary[(i + 1) % n];
      area2 += a.$1 * b.$2 - b.$1 * a.$2;
    }
    final sign = area2 >= 0 ? 1.0 : -1.0;

    const k = 4;
    final out = <Point2D>[];
    for (var i = 0; i < n; i++) {
      final prev = boundary[(i - k + n) % n];
      final next = boundary[(i + k) % n];
      final tx = (next.$1 - prev.$1).toDouble();
      final ty = (next.$2 - prev.$2).toDouble();
      final len = sqrt(tx * tx + ty * ty);
      var nx = 0.0, ny = 0.0;
      if (len > 0) {
        nx = sign * ty / len;
        ny = -sign * tx / len;
      }
      final p = boundary[i];
      out.add(Point2D((p.$1 + 0.5 + 0.5 * nx) / pixelsPerMm, (p.$2 + 0.5 + 0.5 * ny) / pixelsPerMm));
    }
    return out;
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
