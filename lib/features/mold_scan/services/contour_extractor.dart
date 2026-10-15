import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../../measurement/services/homography.dart';
import '../models/mold_board_spec.dart';

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

/// Expected board color at each image pixel: one plane (a*x + b*y + c) per
/// RGB channel, so a lighting gradient or color cast across the board is
/// part of the model instead of being mistaken for an object.
class BackgroundModel {
  final List<double> _a;
  final List<double> _b;
  final List<double> _c;
  final int _w;
  final int _h;

  const BackgroundModel._(this._a, this._b, this._c, this._w, this._h);

  factory BackgroundModel.constant(int r, int g, int b) =>
      BackgroundModel._([0, 0, 0], [0, 0, 0], [r.toDouble(), g.toDouble(), b.toDouble()], 1, 1);

  (double, double, double) colorAt(int x, int y) {
    final u = x / _w, v = y / _h;
    return (
      _a[0] * u + _b[0] * v + _c[0],
      _a[1] * u + _b[1] * v + _c[1],
      _a[2] * u + _b[2] * v + _c[2],
    );
  }

  /// Color at the image center, for diagnostics.
  (double, double, double) get center => colorAt(_w ~/ 2, _h ~/ 2);

  /// Robust least-squares plane fit per channel: fit, drop samples whose
  /// residual is far above the median, refit.
  factory BackgroundModel.fit(List<double> xs, List<double> ys, List<List<double>> cs, int w, int h) {
    var keep = List<bool>.filled(xs.length, true);
    final a = [0.0, 0.0, 0.0], b = [0.0, 0.0, 0.0], c = [0.0, 0.0, 0.0];

    for (var pass = 0; pass < 4; pass++) {
      for (var ch = 0; ch < 3; ch++) {
        final p = _fitPlane(xs, ys, cs[ch], keep);
        a[ch] = p[0];
        b[ch] = p[1];
        c[ch] = p[2];
      }
      final res = <double>[];
      final all = List<double>.filled(xs.length, 0);
      for (var i = 0; i < xs.length; i++) {
        var r2 = 0.0;
        for (var ch = 0; ch < 3; ch++) {
          final d = cs[ch][i] - (a[ch] * xs[i] + b[ch] * ys[i] + c[ch]);
          r2 += d * d;
        }
        all[i] = sqrt(r2);
        if (keep[i]) res.add(all[i]);
      }
      res.sort();
      final median = res[res.length ~/ 2];
      final limit = max(3 * median, 12.0);
      keep = [for (final r in all) r <= limit];
      if (keep.where((k) => k).length < 20) break;
    }
    return BackgroundModel._(a, b, c, w, h);
  }

  static List<double> _fitPlane(List<double> xs, List<double> ys, List<double> zs, List<bool> keep) {
    double sxx = 0, sxy = 0, sx = 0, syy = 0, sy = 0, sn = 0, sxz = 0, syz = 0, sz = 0;
    for (var i = 0; i < xs.length; i++) {
      if (!keep[i]) continue;
      final x = xs[i], y = ys[i], z = zs[i];
      sxx += x * x;
      sxy += x * y;
      sx += x;
      syy += y * y;
      sy += y;
      sn += 1;
      sxz += x * z;
      syz += y * z;
      sz += z;
    }
    // Solve [[sxx sxy sx],[sxy syy sy],[sx sy sn]] * [a b c] = [sxz syz sz].
    final det = sxx * (syy * sn - sy * sy) - sxy * (sxy * sn - sy * sx) + sx * (sxy * sy - syy * sx);
    if (det.abs() < 1e-9) return [0, 0, sz / max(sn, 1)];
    final a = (sxz * (syy * sn - sy * sy) - sxy * (syz * sn - sy * sz) + sx * (syz * sy - syy * sz)) / det;
    final b = (sxx * (syz * sn - sy * sz) - sxz * (sxy * sn - sy * sx) + sx * (sxy * sz - syz * sx)) / det;
    final c = (sxx * (syy * sz - syz * sy) - sxy * (sxy * sz - syz * sx) + sxz * (sxy * sy - syy * sx)) / det;
    return [a, b, c];
  }
}

class ContourExtractor {
  static const _clockwiseOffsets = [
    (1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1), (0, -1), (1, -1),
  ];

  /// Models the board's background directly from the photo, as a color that
  /// can drift linearly across the board (uneven lighting, white-balance
  /// cast), instead of assuming one fixed value: paint never matches a
  /// hardcoded RGB, and a 2.5m board is never lit evenly.
  ///
  /// Samples 4 strips along the board's edges, away from the corner markers
  /// and from where a mold normally sits, then fits one plane per color
  /// channel, discarding outliers (a stray object, dust or glare in a strip
  /// can't skew the fit).
  static BackgroundModel estimateBackground({
    required img.Image image,
    required double pixelsPerMm,
    required double boardWidthMm,
    required double boardHeightMm,
    double stripStartMm = 55,
    double stripEndMm = 120,
  }) {
    int px(double mm, int max) => (mm * pixelsPerMm).round().clamp(0, max - 1);

    final w = image.width, h = image.height;
    final clearX = min(400.0, boardWidthMm * 0.22);
    final clearY = min(400.0, boardHeightMm * 0.22);
    final xLo = px(clearX, w), xHi = px(boardWidthMm - clearX, w);
    final yLo = px(clearY, h), yHi = px(boardHeightMm - clearY, h);
    final s0x = px(stripStartMm, w), s1x = px(stripEndMm, w);
    final s0y = px(stripStartMm, h), s1y = px(stripEndMm, h);
    final e0x = px(boardWidthMm - stripEndMm, w), e1x = px(boardWidthMm - stripStartMm, w);
    final e0y = px(boardHeightMm - stripEndMm, h), e1y = px(boardHeightMm - stripStartMm, h);

    final xs = <double>[], ys = <double>[];
    final cs = [<double>[], <double>[], <double>[]];
    final strips = <List<int>>[[], [], [], []];
    final step = max(1, (3 * pixelsPerMm).round());

    void sample(int strip, int x0, int x1, int y0, int y1) {
      for (var y = y0; y <= y1; y += step) {
        for (var x = x0; x <= x1; x += step) {
          final p = image.getPixel(x, y);
          strips[strip].add(xs.length);
          xs.add(x / w);
          ys.add(y / h);
          cs[0].add(p.r.toDouble());
          cs[1].add(p.g.toDouble());
          cs[2].add(p.b.toDouble());
        }
      }
    }

    sample(0, xLo, xHi, s0y, s1y);
    sample(1, xLo, xHi, e0y, e1y);
    sample(2, s0x, s1x, yLo, yHi);
    sample(3, e0x, e1x, yLo, yHi);

    if (xs.length < 20) {
      throw const ContourExtractionException('Imagem pequena demais para estimar a cor do quadro.');
    }

    // A mold (or the table it leans on) can cover most of one strip. Let the
    // strips vote: a strip whose color direction differs from the others'
    // is dropped, so it can't drag the background model toward the mold.
    final kept = _consistentSamples(strips, cs);
    return BackgroundModel.fit(
      [for (final i in kept) xs[i]],
      [for (final i in kept) ys[i]],
      [
        for (var ch = 0; ch < 3; ch++) [for (final i in kept) cs[ch][i]],
      ],
      w,
      h,
    );
  }

  static double _median(List<double> v) {
    final sorted = [...v]..sort();
    return sorted[sorted.length ~/ 2];
  }

  /// Indexes of the samples from strips that agree with the majority on the
  /// board's color *direction* (so a lighting gradient doesn't count as
  /// disagreement, but wood against a gray wall or blue paint does).
  static List<int> _consistentSamples(List<List<int>> strips, List<List<double>> cs) {
    final all = [for (final s in strips) ...s];
    final med = <List<double>>[];
    final norms = <double>[];
    for (final idx in strips) {
      if (idx.length < 10) {
        med.add([0, 0, 0]);
        norms.add(0);
        continue;
      }
      final m = [for (var ch = 0; ch < 3; ch++) _median([for (final i in idx) cs[ch][i]])];
      med.add(m);
      norms.add(sqrt(m[0] * m[0] + m[1] * m[1] + m[2] * m[2]));
    }
    final valid = [
      for (var s = 0; s < strips.length; s++)
        if (norms[s] >= 1) s,
    ];
    if (valid.length < 3) return all;

    List<double> unit(int s) => [for (final v in med[s]) v / norms[s]];
    final refUnit = [for (var ch = 0; ch < 3; ch++) _median([for (final s in valid) unit(s)[ch]])];
    final refNorm = _median([for (final s in valid) norms[s]]);

    final inliers = <int>[];
    for (final s in valid) {
      final u = unit(s);
      final d = sqrt(
        pow(u[0] - refUnit[0], 2) + pow(u[1] - refUnit[1], 2) + pow(u[2] - refUnit[2], 2),
      );
      final ratio = norms[s] / refNorm;
      if (d <= 0.07 && ratio >= 0.55 && ratio <= 1.8) inliers.add(s);
    }
    final use = inliers.length >= 2 ? inliers : valid;
    return [for (final s in use) ...strips[s]];
  }

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
      background: BackgroundModel.constant(backgroundR, backgroundG, backgroundB),
      pixelsPerMm: pixelsPerMm,
      excludedRegionsMm: excludedRegionsMm,
      ignoreBorderMm: ignoreBorderMm,
    ).contourMm;
  }

  /// A pixel is foreground when its *color* differs from the expected
  /// background color (ignoring brightness), or when it is much brighter or
  /// much darker than the background at that spot. Ignoring moderate
  /// brightness changes keeps shadows from being read as "object"; flagging
  /// strong ones is what lets a light piece stand out against a gray wall,
  /// where colors alone barely differ.
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
    double sliverRadiusMm = 6,
    List<MmRect> excludedRegionsMm = const [],
    double ignoreBorderMm = 0,
    int minAreaPx = 16,
  }) {
    final w = image.width, h = image.height;
    final n = w * h;
    final bytes = image.getBytes(order: img.ChannelOrder.rgb);
    var mask = Uint8List(n);
    // Euclidean distance from the expected background color, kept per pixel
    // to place the final edge (see "stage 2" below).
    final dist = Uint16List(n);

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
        final t2 = max(chromaThresholdRatio * chromaThresholdRatio * bb, minChroma2);
        if (cr * cr + cg * cg + cb * cb > t2) mask[i] = 1;
      }
    }

    void clear(int x0, int x1, int y0, int y1) {
      if (x1 < 0 || y1 < 0 || x0 > w - 1 || y0 > h - 1) return;
      final xa = x0.clamp(0, w - 1), xb = x1.clamp(0, w - 1);
      final ya = y0.clamp(0, h - 1), yb = y1.clamp(0, h - 1);
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

    // Stage 2 — edge placement. The sensitive thresholds above are good at
    // *finding* a low-contrast piece, but they put the edge too far out
    // (blurred edge pixels already pass them), which would oversize every
    // piece by a millimeter or two. Re-place the edge at a fixed share of the
    // piece's own contrast with the board (its median distance from the
    // background), which is where a blurred step edge really is.
    final hist = Int32List(1024);
    var counted = 0;
    for (var i = 0; i < n; i++) {
      if (mask[i] != 0) {
        hist[min(dist[i], 1023)]++;
        counted++;
      }
    }
    if (counted > 0) {
      var acc = 0, median = 0;
      for (var v = 0; v < hist.length; v++) {
        acc += hist[v];
        if (acc * 2 >= counted) {
          median = v;
          break;
        }
      }
      final minDist = max(edgeContrastRatio * median, 22.0);
      for (var i = 0; i < n; i++) {
        if (mask[i] != 0 && dist[i] < minDist) mask[i] = 0;
      }
    }

    final closeR = (closingRadiusMm * pixelsPerMm).round();
    if (closeR > 0) {
      mask = _boxMorph(_boxMorph(mask, w, h, closeR, erode: false), w, h, closeR, erode: true);
    }

    // Drop thin slivers (a table edge, a seam, a shadow line touching the
    // mold): keep only pixels within a few millimeters of the shape that
    // survives an opening. Reconstructing like this, instead of just
    // opening, keeps sharp corners of the mold intact.
    final sliverR = (sliverRadiusMm * pixelsPerMm).round();
    if (sliverR > 0) {
      final opened = _boxMorph(_boxMorph(mask, w, h, sliverR, erode: true), w, h, sliverR, erode: false);
      final near = _boxMorph(opened, w, h, sliverR, erode: false);
      for (var i = 0; i < n; i++) {
        if (mask[i] != 0 && near[i] == 0) mask[i] = 0;
      }
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

  /// Square dilation (or erosion) of a 0/1 mask with a (2r+1) window, done as
  /// two 1-D passes using running sums. Pixels outside the image count as 0.
  static Uint8List _boxMorph(Uint8List src, int w, int h, int r, {required bool erode}) {
    final window = 2 * r + 1;
    final tmp = Uint8List(w * h);
    final out = Uint8List(w * h);
    final prefix = Int32List(max(w, h) + 1);

    for (var y = 0; y < h; y++) {
      final row = y * w;
      for (var x = 0; x < w; x++) {
        prefix[x + 1] = prefix[x] + src[row + x];
      }
      for (var x = 0; x < w; x++) {
        final sum = prefix[min(x + r, w - 1) + 1] - prefix[max(x - r, 0)];
        tmp[row + x] = erode ? (sum == window ? 1 : 0) : (sum > 0 ? 1 : 0);
      }
    }
    for (var x = 0; x < w; x++) {
      for (var y = 0; y < h; y++) {
        prefix[y + 1] = prefix[y] + tmp[y * w + x];
      }
      for (var y = 0; y < h; y++) {
        final sum = prefix[min(y + r, h - 1) + 1] - prefix[max(y - r, 0)];
        out[y * w + x] = erode ? (sum == window ? 1 : 0) : (sum > 0 ? 1 : 0);
      }
    }
    return out;
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
