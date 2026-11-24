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
    double colorCoreMm = 25,
    double colorReachMm = 30,
    double speckAreaMm2 = 150,
    double sliverRadiusMm = 6,
    List<MmRect> excludedRegionsMm = const [],
    double ignoreBorderMm = 0,
    int minAreaPx = 16,
  }) {
    final w = image.width, h = image.height;
    final (mask0, dist, darkOnly) = _classify(
      image,
      background,
      chromaThresholdRatio: chromaThresholdRatio,
      minBrightnessRatio: minBrightnessRatio,
      maxBrightnessRatio: maxBrightnessRatio,
    );
    var mask = mask0;

    final band = (ignoreBorderMm * pixelsPerMm).ceil();
    // Where the piece may be at all: not the border band, not the markers.
    final allowed = Uint8List(w * h)..fillRange(0, w * h, 1);
    void clearOutside(Uint8List m) {
      if (band > 0) {
        clearRect(m, w, h, 0, band - 1, 0, h - 1);
        clearRect(m, w, h, w - band, w - 1, 0, h - 1);
        clearRect(m, w, h, 0, w - 1, 0, band - 1);
        clearRect(m, w, h, 0, w - 1, h - band, h - 1);
      }
      for (final r in excludedRegionsMm) {
        clearRect(
          m,
          w,
          h,
          (r.left * pixelsPerMm).floor(),
          (r.right * pixelsPerMm).ceil(),
          (r.top * pixelsPerMm).floor(),
          (r.bottom * pixelsPerMm).ceil(),
        );
      }
    }

    clearOutside(mask);
    clearOutside(allowed);

    debugMask?.call('classify', mask, w, h);
    debugMask?.call('dark', darkOnly, w, h);
    _placeEdgeByContrast(
      mask,
      dist,
      edgeContrastRatio,
      w,
      h,
      (edgeBandMm * pixelsPerMm).ceil(),
    );

    debugMask?.call('edge', mask, w, h);
    final speck = (speckAreaMm2 * pixelsPerMm * pixelsPerMm).round();
    final closeR = (closingRadiusMm * pixelsPerMm).round();
    final sliverR = (sliverRadiusMm * pixelsPerMm).round();
    final fillGap = (fillGapMm * pixelsPerMm).round();
    Uint8List clean(Uint8List m, int w, int h) {
      if (speck > 0) removeSmallComponents(m, w, h, speck);
      if (closeR > 0) m = closeGaps(m, w, h, closeR);
      m = fillHoles(m, w, h);
      if (sliverR > 0) {
        dropSlivers(
          m,
          w,
          h,
          sliverR,
          edgeZone: band > 0 ? band + sliverR + 2 : 0,
        );
      }
      if (fillGap > 0) m = fillEnclosed(m, w, h, fillGap);
      return m;
    }

    mask = clean(mask, w, h);

    // The color passes only need the piece and a ring of board around it:
    // run them on that window (a 60 x 50 cm piece on a 2 x 1.5 m board is a
    // sixth of the pixels), then paste the result back.
    final coreR = (colorCoreMm * pixelsPerMm).round();
    final reachR = (colorReachMm * pixelsPerMm).round();
    final piece = _largestOnly(mask, w, h);
    final box = _bounds(piece, w, h);
    if (box != null && coreR > 0 && reachR > 0) {
      final margin = 2 * reachR + (200 * pixelsPerMm).round();
      final x0 = max(0, box.$1 - margin), y0 = max(0, box.$2 - margin);
      final x1 = min(w - 1, box.$3 + margin), y1 = min(h - 1, box.$4 + margin);
      final rw = x1 - x0 + 1, rh = y1 - y0 + 1;
      Uint8List crop8(Uint8List a) {
        final out = Uint8List(rw * rh);
        for (var y = 0; y < rh; y++) {
          out.setRange(y * rw, (y + 1) * rw, a, (y + y0) * w + x0);
        }
        return out;
      }

      final dist16 = Uint16List(rw * rh);
      for (var y = 0; y < rh; y++) {
        dist16.setRange(y * rw, (y + 1) * rw, dist, (y + y0) * w + x0);
      }
      final window = img.copyCrop(image, x: x0, y: y0, width: rw, height: rh);
      final allowedW = crop8(allowed);
      var m = crop8(piece);
      var refinedAny = false;
      // Twice: the second pass learns from a core no longer polluted by lumps.
      for (var pass = 0; pass < 2; pass++) {
        final refined = _refineByColor(
          window,
          _largestOnly(m, rw, rh),
          allowedW,
          rw,
          rh,
          coreR: coreR,
          reachR: reachR,
        );
        if (refined == null) break;
        for (var i = 0; i < refined.length; i++) {
          if (allowedW[i] == 0) refined[i] = 0;
        }
        _placeEdgeByContrast(
          refined,
          dist16,
          edgeContrastRatio,
          rw,
          rh,
          (edgeBandMm * pixelsPerMm).ceil(),
        );
        m = clean(refined, rw, rh);
        refinedAny = true;
      }
      if (refinedAny) {
        mask = Uint8List(w * h);
        for (var y = 0; y < rh; y++) {
          mask.setRange((y + y0) * w + x0, (y + y0) * w + x0 + rw, m, y * rw);
        }
        debugMask?.call('color', mask, w, h);
      }
    }

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
  static (Uint8List, Uint16List, Uint8List) _classify(
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
    // 1 where the pixel is "piece" only for being darker, with the board's own hue.
    final darkOnly = Uint8List(w * h);

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
        final cr = r - k * bgR;
        final cg = g - k * bgG;
        final cb = b - k * bgB;
        final t2 = max(
          chromaThresholdRatio * chromaThresholdRatio * bb,
          minChroma2,
        );
        final colored = cr * cr + cg * cg + cb * cb > t2;
        if (colored || k > maxBrightnessRatio) {
          mask[i] = 1;
        } else if (k < minBrightnessRatio) {
          mask[i] = 1;
          darkOnly[i] = 1;
        }
      }
    }
    return (mask, dist, darkOnly);
  }

  /// Bounding box (x0, y0, x1, y1) of the set pixels, or null if none.
  static (int, int, int, int)? _bounds(Uint8List m, int w, int h) {
    var x0 = w, y0 = h, x1 = -1, y1 = -1;
    for (var y = 0; y < h; y++) {
      final row = y * w;
      for (var x = 0; x < w; x++) {
        if (m[row + x] == 0) continue;
        if (x < x0) x0 = x;
        if (x > x1) x1 = x;
        if (y < y0) y0 = y;
        if (y > y1) y1 = y;
      }
    }
    return x1 < 0 ? null : (x0, y0, x1, y1);
  }

  static Uint8List _largestOnly(Uint8List mask, int w, int h) {
    final l = labelLargest(mask, w, h);
    final out = Uint8List(w * h);
    if (l.bestCount == 0) return out;
    for (var i = 0; i < out.length; i++) {
      if (l.labels[i] == l.bestLabel) out[i] = 1;
    }
    return out;
  }

  /// Second pass that tells piece from board by the piece's *own* colors.
  /// The first pass only asks "does this differ from the board?", which
  /// fails both ways on real photos: a dark stain on dirty wood can match a
  /// gray wall (bites), and a dark stain on the floor next to a light stone
  /// slab differs from the floor's average (lumps glued to the piece).
  ///
  /// The colors of the piece are learned from its safe core (the piece
  /// eroded by [coreR]) and the board's from everything farther than
  /// [reachR] from it. Near the edge (within [reachR] on both sides) each
  /// pixel goes to whichever color histogram makes it more likely; colors
  /// seen too rarely keep the first pass's answer. Returns null when the
  /// piece is too small to have a core.
  static Uint8List? _refineByColor(
    img.Image image,
    Uint8List piece,
    Uint8List allowed,
    int w,
    int h, {
    required int coreR,
    required int reachR,
  }) {
    if (coreR <= 0 || reachR <= 0) return null;
    final core = boxMorph(piece, w, h, coreR, erode: true);
    var coreCount = 0;
    for (final v in core) {
      coreCount += v;
    }
    if (coreCount < 400) return null;
    final near = boxMorph(piece, w, h, reachR, erode: false);
    final far = boxMorph(near, w, h, reachR, erode: false);

    final rgb = image.getBytes(order: img.ChannelOrder.rgb);
    int bin(int i) =>
        ((rgb[i * 3] >> 3) << 10) |
        ((rgb[i * 3 + 1] >> 3) << 5) |
        (rgb[i * 3 + 2] >> 3);
    final moldHist = Int32List(32768), boardHist = Int32List(32768);
    var nMold = 0, nBoard = 0;
    for (var i = 0; i < piece.length; i++) {
      if (allowed[i] == 0) continue;
      if (core[i] != 0) {
        moldHist[bin(i)]++;
        nMold++;
      } else if (far[i] == 0) {
        boardHist[bin(i)]++;
        nBoard++;
      }
    }
    if (nBoard < 400) return null;

    final out = Uint8List(w * h);
    for (var i = 0; i < out.length; i++) {
      if (allowed[i] == 0) continue;
      if (core[i] != 0) {
        out[i] = 1;
        continue;
      }
      if (near[i] == 0) continue;
      final b = bin(i);
      final m = moldHist[b], g = boardHist[b];
      if (m + g < 3) {
        out[i] = piece[i];
      } else {
        // Same-size samples would compare counts; scale by sample sizes.
        out[i] = m * nBoard >= g * nMold ? 1 : 0;
      }
    }
    return out;
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
