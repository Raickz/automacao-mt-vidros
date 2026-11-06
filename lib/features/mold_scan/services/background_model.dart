import 'dart:math';

import 'package:image/image.dart' as img;

import 'contour_types.dart';

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

  factory BackgroundModel.constant(int r, int g, int b) => BackgroundModel._(
    [0, 0, 0],
    [0, 0, 0],
    [r.toDouble(), g.toDouble(), b.toDouble()],
    1,
    1,
  );

  (double, double, double) colorAt(int x, int y) {
    final u = x / _w, v = y / _h;
    return (
      _a[0] * u + _b[0] * v + _c[0],
      _a[1] * u + _b[1] * v + _c[1],
      _a[2] * u + _b[2] * v + _c[2],
    );
  }

  /// Models the board's background directly from the photo, instead of
  /// assuming one fixed value: paint never matches a hardcoded RGB, and a
  /// 2.5m board is never lit evenly.
  ///
  /// Samples 4 strips along the board's edges, away from the corner markers
  /// and from where a mold normally sits. A mold (or the table it leans on)
  /// can still cover most of one strip, so the strips vote
  /// ([consistentSamples]) before one plane per color channel is fitted,
  /// discarding outliers (dust or glare can't skew the fit).
  static BackgroundModel estimate({
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
    final e0x = px(boardWidthMm - stripEndMm, w),
        e1x = px(boardWidthMm - stripStartMm, w);
    final e0y = px(boardHeightMm - stripEndMm, h),
        e1y = px(boardHeightMm - stripStartMm, h);

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
      throw const ContourExtractionException(
        'Imagem pequena demais para estimar a cor do quadro.',
      );
    }

    final kept = consistentSamples(strips, cs);
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
  /// disagreement, but wood against a gray wall or blue paint does). [strips]
  /// holds each strip's sample indexes, [cs] the R, G, B value of every sample.
  static List<int> consistentSamples(
    List<List<int>> strips,
    List<List<double>> cs,
  ) {
    final all = [for (final s in strips) ...s];
    final med = <List<double>>[];
    final norms = <double>[];
    for (final idx in strips) {
      if (idx.length < 10) {
        med.add([0, 0, 0]);
        norms.add(0);
        continue;
      }
      final m = [
        for (var ch = 0; ch < 3; ch++)
          _median([for (final i in idx) cs[ch][i]]),
      ];
      med.add(m);
      norms.add(sqrt(m[0] * m[0] + m[1] * m[1] + m[2] * m[2]));
    }
    final valid = [
      for (var s = 0; s < strips.length; s++)
        if (norms[s] >= 1) s,
    ];
    if (valid.length < 3) return all;

    List<double> unit(int s) => [for (final v in med[s]) v / norms[s]];
    final refUnit = [
      for (var ch = 0; ch < 3; ch++)
        _median([for (final s in valid) unit(s)[ch]]),
    ];
    final refNorm = _median([for (final s in valid) norms[s]]);

    final inliers = <int>[];
    for (final s in valid) {
      final u = unit(s);
      final d = sqrt(
        pow(u[0] - refUnit[0], 2) +
            pow(u[1] - refUnit[1], 2) +
            pow(u[2] - refUnit[2], 2),
      );
      final ratio = norms[s] / refNorm;
      if (d <= 0.07 && ratio >= 0.55 && ratio <= 1.8) inliers.add(s);
    }
    final use = inliers.length >= 2 ? inliers : valid;
    return [for (final s in use) ...strips[s]];
  }

  /// Robust least-squares plane fit per channel: fit, drop samples whose
  /// residual is far above the median, refit.
  factory BackgroundModel.fit(
    List<double> xs,
    List<double> ys,
    List<List<double>> cs,
    int w,
    int h,
  ) {
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

  static List<double> _fitPlane(
    List<double> xs,
    List<double> ys,
    List<double> zs,
    List<bool> keep,
  ) {
    double sxx = 0,
        sxy = 0,
        sx = 0,
        syy = 0,
        sy = 0,
        sn = 0,
        sxz = 0,
        syz = 0,
        sz = 0;
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
    final det =
        sxx * (syy * sn - sy * sy) -
        sxy * (sxy * sn - sy * sx) +
        sx * (sxy * sy - syy * sx);
    if (det.abs() < 1e-9) return [0, 0, sz / max(sn, 1)];
    final a =
        (sxz * (syy * sn - sy * sy) -
            sxy * (syz * sn - sy * sz) +
            sx * (syz * sy - syy * sz)) /
        det;
    final b =
        (sxx * (syz * sn - sy * sz) -
            sxz * (sxy * sn - sy * sx) +
            sx * (sxy * sz - syz * sx)) /
        det;
    final c =
        (sxx * (syy * sz - syz * sy) -
            sxy * (sxy * sz - syz * sx) +
            sxz * (sxy * sy - syy * sx)) /
        det;
    return [a, b, c];
  }
}
