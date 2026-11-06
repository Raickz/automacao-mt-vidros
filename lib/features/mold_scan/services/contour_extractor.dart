import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../models/mold_board_spec.dart';
import 'background_model.dart';
import 'contour_types.dart';
import 'homography.dart';
import 'mask_ops.dart';

export 'contour_types.dart';

class ContourExtractor {
  /// Test hook: receives the cleaned mask right before the outline is traced.
  static void Function(String stage, Uint8List mask, int w, int h)? debugMask;

  static const _clockwiseOffsets = [
    (1, 0),
    (1, 1),
    (0, 1),
    (-1, 1),
    (-1, 0),
    (-1, -1),
    (0, -1),
    (1, -1),
  ];

  /// Extracts the outer boundary of the largest foreground object in
  /// [image] (the photographed mold) against a constant background color,
  /// returning the contour in millimeters.
  static List<Point2D> extractFromImage({
    required img.Image image,
    required int backgroundR,
    required int backgroundG,
    required int backgroundB,
    required double pixelsPerMm,
    List<MmRect> excludedRegionsMm = const [],
    double ignoreBorderMm = 0,
  }) {
    return extract(
      image: image,
      background: BackgroundModel.constant(
        backgroundR,
        backgroundG,
        backgroundB,
      ),
      pixelsPerMm: pixelsPerMm,
      excludedRegionsMm: excludedRegionsMm,
      ignoreBorderMm: ignoreBorderMm,
    ).contourMm;
  }

  /// Finds the mold's outline in a top-down photo of the board, in steps:
  /// classify each pixel as mold or board, ignore the border strip and the
  /// marker zones, re-place the edge, close grooves, drop slivers, keep the
  /// largest blob and trace it.
  ///
  /// Gaps up to ~2x [closingRadiusMm] are closed, so a relief or groove does
  /// not split one piece into several blobs, and only the largest connected
  /// blob is kept, so dust, glare, leftover paper or seams can't be mistaken
  /// for the mold just because they come first in a raster scan.
  static ContourResult extract({
    required img.Image image,
    required BackgroundModel background,
    required double pixelsPerMm,
    double chromaThresholdRatio = MoldBoardSpec.chromaThresholdRatio,
    double minBrightnessRatio = MoldBoardSpec.brightnessMinRatio,
    double maxBrightnessRatio = MoldBoardSpec.brightnessMaxRatio,
    double edgeContrastRatio = MoldBoardSpec.edgeContrastRatio,
    double closingRadiusMm = 8,
    double edgeBandMm = 4,
    double fillGapMm = 150,
    double sliverRadiusMm = 6,
    List<MmRect> excludedRegionsMm = const [],
    double ignoreBorderMm = 0,
    int minAreaPx = 16,
  }) {
    final w = image.width, h = image.height;
    final (mask0, dist) = _classify(
      image,
      background,
      chromaThresholdRatio: chromaThresholdRatio,
      minBrightnessRatio: minBrightnessRatio,
      maxBrightnessRatio: maxBrightnessRatio,
    );
    var mask = mask0;

    final band = (ignoreBorderMm * pixelsPerMm).ceil();
    if (band > 0) {
      clearRect(mask, w, h, 0, band - 1, 0, h - 1);
      clearRect(mask, w, h, w - band, w - 1, 0, h - 1);
      clearRect(mask, w, h, 0, w - 1, 0, band - 1);
      clearRect(mask, w, h, 0, w - 1, h - band, h - 1);
    }
    for (final r in excludedRegionsMm) {
      clearRect(
        mask,
        w,
        h,
        (r.left * pixelsPerMm).floor(),
        (r.right * pixelsPerMm).ceil(),
        (r.top * pixelsPerMm).floor(),
        (r.bottom * pixelsPerMm).ceil(),
      );
    }

    debugMask?.call('classify', mask, w, h);
    _placeEdgeByContrast(
      mask,
      dist,
      edgeContrastRatio,
      w,
      h,
      (edgeBandMm * pixelsPerMm).ceil(),
    );

    debugMask?.call('edge', mask, w, h);
    final closeR = (closingRadiusMm * pixelsPerMm).round();
    if (closeR > 0) mask = closeGaps(mask, w, h, closeR);
    mask = fillHoles(mask, w, h);
    final sliverR = (sliverRadiusMm * pixelsPerMm).round();
    if (sliverR > 0) {
      dropSlivers(
        mask,
        w,
        h,
        sliverR,
        edgeZone: band > 0 ? band + sliverR + 2 : 0,
      );
    }

    final fillGap = (fillGapMm * pixelsPerMm).round();
    if (fillGap > 0) mask = fillEnclosed(mask, w, h, fillGap);

    debugMask?.call('final', mask, w, h);
    final largest = labelLargest(mask, w, h);
    if (largest.bestCount < minAreaPx) {
      throw const ContourExtractionException(
        'Nenhum objeto foi encontrado sobre o fundo do quadro de referência.',
      );
    }

    final labels = largest.labels, bestLabel = largest.bestLabel;
    final boundary = traceBoundary(
      (x, y) =>
          x >= 0 && y >= 0 && x < w && y < h && labels[y * w + x] == bestLabel,
      w,
      h,
    );

    final touched = <String>{};
    if (band > 0) {
      for (final p in boundary) {
        if (p.$2 <= band + 1) touched.add('em cima');
        if (p.$2 >= h - band - 2) touched.add('embaixo');
        if (p.$1 <= band + 1) touched.add('à esquerda');
        if (p.$1 >= w - band - 2) touched.add('à direita');
      }
    }

    return ContourResult(
      contourMm: boundaryToMillimeters(boundary, pixelsPerMm),
      areaPx: largest.bestCount,
      touchedSides: [...touched],
    );
  }

  /// A pixel is foreground when its *color* differs from the expected
  /// background color (ignoring brightness), or when it is much brighter or
  /// much darker than the background at that spot. Ignoring moderate
  /// brightness changes keeps shadows from being read as "object"; flagging
  /// strong ones is what lets a light piece stand out against a gray wall,
  /// where colors alone barely differ.
  ///
  /// Returns the 0/1 mask and, per pixel, the Euclidean distance from the
  /// expected background color (used to place the edge).
  static (Uint8List, Uint16List) _classify(
    img.Image image,
    BackgroundModel background, {
    required double chromaThresholdRatio,
    required double minBrightnessRatio,
    required double maxBrightnessRatio,
  }) {
    final w = image.width, h = image.height;
    final bytes = image.getBytes(order: img.ChannelOrder.rgb);
    final mask = Uint8List(w * h);
    final dist = Uint16List(w * h);

    const minChroma2 = 22.0 * 22.0;
    var o = 0;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++, o += 3) {
        final bg = background.colorAt(x, y);
        final bgR = bg.$1, bgG = bg.$2, bgB = bg.$3;
        final bb = bgR * bgR + bgG * bgG + bgB * bgB;
        final r = bytes[o], g = bytes[o + 1], b = bytes[o + 2];
        final i = y * w + x;
        final dr = r - bgR, dg = g - bgG, db = b - bgB;
        dist[i] = sqrt(dr * dr + dg * dg + db * db).round();
        if (bb < 1) {
          if (r * r + g * g + b * b > minChroma2) mask[i] = 1;
          continue;
        }
        final k = (r * bgR + g * bgG + b * bgB) / bb;
        if (k < minBrightnessRatio || k > maxBrightnessRatio) {
          mask[i] = 1;
          continue;
        }
        final cr = r - k * bgR;
        final cg = g - k * bgG;
        final cb = b - k * bgB;
        final t2 = max(
          chromaThresholdRatio * chromaThresholdRatio * bb,
          minChroma2,
        );
        if (cr * cr + cg * cg + cb * cb > t2) mask[i] = 1;
      }
    }
    return (mask, dist);
  }

  /// The sensitive thresholds in [_classify] are good at *finding* a
  /// low-contrast piece, but they put the edge too far out (blurred edge
  /// pixels already pass them), which would oversize every piece by a
  /// millimeter or two. Re-place the edge, in place, at a fixed share of the
  /// piece's own contrast with the board (its median distance from the
  /// background), which is where a blurred step edge really is.
  ///
  /// Only pixels within [band] px of the background are touched: inside the
  /// piece, a stain close to the board's color (dirty wood on a gray wall) is
  /// still piece, and dropping it would bite holes and notches into the
  /// outline.
  static void _placeEdgeByContrast(
    Uint8List mask,
    Uint16List dist,
    double ratio,
    int w,
    int h,
    int band,
  ) {
    final interior = band > 0
        ? boxMorph(mask, w, h, band, erode: true)
        : Uint8List(mask.length);
    final hist = Int32List(1024);
    var counted = 0;
    for (var i = 0; i < mask.length; i++) {
      if (mask[i] != 0) {
        hist[min(dist[i], 1023)]++;
        counted++;
      }
    }
    if (counted == 0) return;

    var acc = 0, median = 0;
    for (var v = 0; v < hist.length; v++) {
      acc += hist[v];
      if (acc * 2 >= counted) {
        median = v;
        break;
      }
    }
    final minDist = max(ratio * median, 22.0);
    for (var i = 0; i < mask.length; i++) {
      if (mask[i] != 0 && interior[i] == 0 && dist[i] < minDist) mask[i] = 0;
    }
  }

  /// Boundary pixels are the object's outermost pixels, so their centers sit
  /// half a pixel *inside* the true edge — measuring through them would
  /// shrink every dimension by a full pixel. Push each point half a pixel
  /// outward along the local normal to compensate.
  static List<Point2D> boundaryToMillimeters(
    List<(int, int)> boundary,
    double pixelsPerMm,
  ) {
    final n = boundary.length;
    if (n < 8) {
      return [
        for (final p in boundary)
          Point2D((p.$1 + 0.5) / pixelsPerMm, (p.$2 + 0.5) / pixelsPerMm),
      ];
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
      out.add(
        Point2D(
          (p.$1 + 0.5 + 0.5 * nx) / pixelsPerMm,
          (p.$2 + 0.5 + 0.5 * ny) / pixelsPerMm,
        ),
      );
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
      if (_clockwiseOffsets[i].$1 == dx && _clockwiseOffsets[i].$2 == dy) {
        return i;
      }
    }
    throw StateError('Offset inválido: ($dx, $dy)');
  }
}
