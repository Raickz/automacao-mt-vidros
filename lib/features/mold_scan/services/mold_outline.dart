import 'dart:math';

import 'homography.dart';
import 'polyline_simplifier.dart';

/// A closed outline in millimeters (the last point is NOT repeated). Every
/// operation returns a new outline; sizes and positions are exact, so a mold
/// resized to 1200 x 650 mm has a bounding box of exactly 1200 x 650 mm.
class MoldOutline {
  final List<Point2D> points;

  const MoldOutline(this.points);

  double get minX => points.map((p) => p.x).reduce(min);
  double get maxX => points.map((p) => p.x).reduce(max);
  double get minY => points.map((p) => p.y).reduce(min);
  double get maxY => points.map((p) => p.y).reduce(max);
  double get width => maxX - minX;
  double get height => maxY - minY;

  /// Enclosed area in mm² (shoelace).
  double get areaMm2 {
    var a = 0.0;
    for (var i = 0; i < points.length; i++) {
      final p = points[i], q = points[(i + 1) % points.length];
      a += p.x * q.y - q.x * p.y;
    }
    return a.abs() / 2;
  }

  /// Length of the cut line in mm.
  double get perimeterMm {
    var s = 0.0;
    for (var i = 0; i < points.length; i++) {
      final p = points[i], q = points[(i + 1) % points.length];
      s += sqrt(pow(p.x - q.x, 2) + pow(p.y - q.y, 2));
    }
    return s;
  }

  /// Moved so the bounding box starts at (0, 0).
  MoldOutline normalized() {
    final x0 = minX, y0 = minY;
    return MoldOutline([for (final p in points) Point2D(p.x - x0, p.y - y0)]);
  }

  /// Stretched so the bounding box is exactly [w] x [h], starting at (0, 0).
  MoldOutline resized(double w, double h) {
    final x0 = minX, y0 = minY;
    final sx = width == 0 ? 1.0 : w / width,
        sy = height == 0 ? 1.0 : h / height;
    return MoldOutline([
      for (final p in points) Point2D((p.x - x0) * sx, (p.y - y0) * sy),
    ]);
  }

  /// Multiplied by [fx] along x and [fy] along y, around the bounding box's
  /// top-left corner.
  MoldOutline scaled(double fx, double fy) => resized(width * fx, height * fy);

  /// Quarter turn clockwise (as seen on screen, where y points down).
  MoldOutline rotated90() =>
      MoldOutline([for (final p in points) Point2D(-p.y, p.x)]).normalized();

  MoldOutline flippedHorizontally() =>
      MoldOutline([for (final p in points) Point2D(-p.x, p.y)]).normalized();

  MoldOutline flippedVertically() =>
      MoldOutline([for (final p in points) Point2D(p.x, -p.y)]).normalized();

  /// Smooth closed curve through the points (Catmull-Rom), with a point at
  /// least every [maxStepMm]. Sampling is dense enough that straight
  /// segments between the points are indistinguishable from the curve.
  MoldOutline splined({double maxStepMm = 3}) {
    final n = points.length;
    if (n < 3) return this;
    final out = <Point2D>[];
    for (var i = 0; i < n; i++) {
      final p0 = points[(i - 1 + n) % n],
          p1 = points[i],
          p2 = points[(i + 1) % n],
          p3 = points[(i + 2) % n];
      final len = sqrt(pow(p2.x - p1.x, 2) + pow(p2.y - p1.y, 2));
      final steps = max(1, (len / maxStepMm).ceil());
      for (var s = 0; s < steps; s++) {
        final t = s / steps, t2 = t * t, t3 = t2 * t;
        double c(double a, double b, double c0, double d) =>
            0.5 *
            (2 * b +
                (-a + c0) * t +
                (2 * a - 5 * b + 4 * c0 - d) * t2 +
                (-a + 3 * b - 3 * c0 + d) * t3);
        out.add(Point2D(c(p0.x, p1.x, p2.x, p3.x), c(p0.y, p1.y, p2.y, p3.y)));
      }
    }
    return MoldOutline(out);
  }

  /// Fewer, straight segments within [toleranceMm] of the outline: the
  /// "maximum compatibility" mode for cutting software that dislikes
  /// thousands of tiny segments.
  MoldOutline simplified({double toleranceMm = 0.3}) {
    if (points.length < 4) return this;
    final open = PolylineSimplifier.simplify([
      ...points,
      points.first,
    ], toleranceMm);
    final closed = open.length > 1 ? open.sublist(0, open.length - 1) : open;
    return closed.length < 3 ? this : MoldOutline(closed);
  }

  /// Grows the outline by [mm] (negative shrinks it): every point moves along
  /// its local normal. Meant for the small margins used when cutting (a few
  /// millimeters); on tight concave corners a large margin can fold over.
  MoldOutline offset(double mm) {
    if (mm == 0 || points.length < 3) return this;
    final n = points.length;
    var area2 = 0.0;
    for (var i = 0; i < n; i++) {
      final p = points[i], q = points[(i + 1) % n];
      area2 += p.x * q.y - q.x * p.y;
    }
    // With y pointing down, a positive shoelace sum is clockwise on screen,
    // whose outward normal is (ty, -tx).
    final sign = area2 >= 0 ? 1.0 : -1.0;
    final out = <Point2D>[];
    for (var i = 0; i < n; i++) {
      final prev = points[(i - 1 + n) % n], next = points[(i + 1) % n];
      final tx = next.x - prev.x, ty = next.y - prev.y;
      final len = sqrt(tx * tx + ty * ty);
      if (len == 0) {
        out.add(points[i]);
        continue;
      }
      out.add(
        Point2D(
          points[i].x + sign * ty / len * mm,
          points[i].y - sign * tx / len * mm,
        ),
      );
    }
    return MoldOutline(out);
  }

  /// Chaikin corner cutting, [iterations] times: rounds off the stair steps
  /// of a traced photo contour without moving the overall size.
  MoldOutline smoothed({int iterations = 2}) {
    var pts = points;
    for (var it = 0; it < iterations; it++) {
      final n = pts.length;
      if (n < 3) break;
      final next = <Point2D>[];
      for (var i = 0; i < n; i++) {
        final p = pts[i], q = pts[(i + 1) % n];
        next.add(Point2D(0.75 * p.x + 0.25 * q.x, 0.75 * p.y + 0.25 * q.y));
        next.add(Point2D(0.25 * p.x + 0.75 * q.x, 0.25 * p.y + 0.75 * q.y));
      }
      pts = next;
    }
    return MoldOutline(pts);
  }

  /// Turned by [degrees] (clockwise on screen, y down) around its center.
  MoldOutline rotatedBy(double degrees) {
    final a = degrees * pi / 180, c = cos(a), sn = sin(a);
    final cx = (minX + maxX) / 2, cy = (minY + maxY) / 2;
    return MoldOutline([
      for (final p in points)
        Point2D(
          cx + (p.x - cx) * c - (p.y - cy) * sn,
          cy + (p.x - cx) * sn + (p.y - cy) * c,
        ),
    ]);
  }

  /// The small turn (within ±[maxDegrees]) that makes the bounding box
  /// smallest: a piece taped or photographed slightly crooked is measured
  /// square to its own edges instead of to the photo. Returns 0 when no
  /// turn shrinks the box by more than 0.3% (round and organic shapes).
  double straighteningAngle({double maxDegrees = 8}) {
    if (points.length < 3) return 0;
    double area(double deg) {
      final a = deg * pi / 180, c = cos(a), sn = sin(a);
      var x0 = double.infinity,
          x1 = -double.infinity,
          y0 = double.infinity,
          y1 = -double.infinity;
      for (final p in points) {
        final x = p.x * c - p.y * sn, y = p.x * sn + p.y * c;
        if (x < x0) x0 = x;
        if (x > x1) x1 = x;
        if (y < y0) y0 = y;
        if (y > y1) y1 = y;
      }
      return (x1 - x0) * (y1 - y0);
    }

    final base = area(0);
    var best = 0.0, bestArea = base;
    for (var d = -maxDegrees; d <= maxDegrees + 1e-9; d += 0.1) {
      final a = area(d);
      if (a < bestArea) {
        bestArea = a;
        best = d;
      }
    }
    return bestArea < base * 0.997 ? best : 0;
  }

  /// Same outline with points every [stepMm] along its length.
  MoldOutline resampled({double stepMm = 1}) {
    final out = <Point2D>[];
    final n = points.length;
    var carry = 0.0;
    for (var i = 0; i < n; i++) {
      final a = points[i], b = points[(i + 1) % n];
      final len = sqrt(pow(b.x - a.x, 2) + pow(b.y - a.y, 2));
      if (len == 0) continue;
      var t = carry;
      while (t < len) {
        out.add(
          Point2D(a.x + (b.x - a.x) * t / len, a.y + (b.y - a.y) * t / len),
        );
        t += stepMm;
      }
      carry = t - len;
    }
    return out.length < 3 ? this : MoldOutline(out);
  }

  /// Rebuilds the outline as glass is cut: straight edges and smooth
  /// curves, meeting at clean corners. A traced photo has small jogs and
  /// waves (a pixel step, a frayed cardboard edge) that the cutting table
  /// would faithfully copy.
  ///
  /// Corners are where the direction turns more than [cornerDegrees],
  /// measured over [spanMm] on each side (so a 1-2 mm jog is not a corner).
  /// Each stretch between corners becomes a straight line (a least-squares
  /// fit) when it stays within [straightToleranceMm] (scaled up
  /// on long edges: 0.3% of the length per mm of tolerance) of its chord, otherwise
  /// a curve smoothed over ~[smoothMm]. Corners between two straight edges
  /// are the exact intersection of the two fitted lines.
  MoldOutline regularized({
    double cornerDegrees = 35,
    double spanMm = 15,
    double straightToleranceMm = 4,
    double smoothMm = 12,
  }) {
    final dense = resampled().points;
    final n = dense.length;
    final l = spanMm.round();
    if (n < 4 * l) return this;
    Point2D at(int i) => dense[((i % n) + n) % n];

    // Turning angle at every point, over +-l points.
    final turn = List<double>.filled(n, 0);
    for (var i = 0; i < n; i++) {
      final a = at(i - l), b = at(i), c = at(i + l);
      final v1x = b.x - a.x, v1y = b.y - a.y, v2x = c.x - b.x, v2y = c.y - b.y;
      final d = sqrt(v1x * v1x + v1y * v1y) * sqrt(v2x * v2x + v2y * v2y);
      if (d == 0) continue;
      turn[i] = acos(((v1x * v2x + v1y * v2y) / d).clamp(-1.0, 1.0)) * 180 / pi;
    }
    final corners = <int>[];
    for (var i = 0; i < n; i++) {
      if (turn[i] < cornerDegrees) continue;
      var isMax = true;
      for (var k = -l; k <= l && isMax; k++) {
        final j = ((i + k) % n + n) % n;
        if (turn[j] > turn[i] || (turn[j] == turn[i] && j < i && k != 0)) {
          isMax = false;
        }
      }
      if (isMax) corners.add(i);
    }

    List<Point2D> smoothRun(List<Point2D> run, {required bool closed}) {
      final w = max(1, (smoothMm / 2).round());
      final m = run.length;
      final out = <Point2D>[];
      for (var i = 0; i < m; i++) {
        if (!closed && (i == 0 || i == m - 1)) {
          out.add(run[i]);
          continue;
        }
        // Shrink the window near the ends of an open run so its end
        // points stay put.
        final k = closed ? w : min(w, min(i, m - 1 - i));
        var sx = 0.0, sy = 0.0;
        for (var j = -k; j <= k; j++) {
          final p = run[((i + j) % m + m) % m];
          sx += p.x;
          sy += p.y;
        }
        out.add(Point2D(sx / (2 * k + 1), sy / (2 * k + 1)));
      }
      return out;
    }

    if (corners.isEmpty) {
      return MoldOutline(smoothRun(dense, closed: true))
          .simplified(toleranceMm: 0.2);
    }

    // Runs between consecutive corners, and a straight-line fit for each.
    final runs = <List<Point2D>>[];
    for (var c = 0; c < corners.length; c++) {
      final from = corners[c];
      var to = corners[(c + 1) % corners.length];
      if (to <= from) to += n;
      runs.add([for (var i = from; i <= to; i++) at(i)]);
    }
    final lines = <(Point2D, Point2D)?>[]; // point on line, unit direction
    for (final run in runs) {
      final a = run.first, b = run.last;
      final len = sqrt(pow(b.x - a.x, 2) + pow(b.y - a.y, 2));
      var maxDev = 0.0;
      for (final p in run) {
        final dev = len == 0
            ? 0.0
            : ((b.x - a.x) * (a.y - p.y) - (a.x - p.x) * (b.y - a.y)).abs() /
                  len;
        maxDev = max(maxDev, dev);
      }
      // A long edge may wave a little more and still be meant straight
      // (frayed cardboard, a sagging edge): a real curve bows far more.
      if (len == 0 ||
          maxDev >
              max(straightToleranceMm, len * straightToleranceMm * 0.003)) {
        lines.add(null);
        continue;
      }
      // Total least squares on the middle of the run (its ends bend into
      // the neighboring corners).
      final cut = min(l ~/ 2, run.length ~/ 4);
      final mid = run.sublist(cut, run.length - cut);
      final mx = mid.map((p) => p.x).reduce((x, y) => x + y) / mid.length;
      final my = mid.map((p) => p.y).reduce((x, y) => x + y) / mid.length;
      var sxx = 0.0, sxy = 0.0, syy = 0.0;
      for (final p in mid) {
        sxx += (p.x - mx) * (p.x - mx);
        sxy += (p.x - mx) * (p.y - my);
        syy += (p.y - my) * (p.y - my);
      }
      final angle = 0.5 * atan2(2 * sxy, sxx - syy);
      lines.add((Point2D(mx, my), Point2D(cos(angle), sin(angle))));
    }

    // Two straight edges in a row that are nearly aligned are one edge
    // (a wave in it was taken for a corner): merge and refit.
    (Point2D, Point2D) fit(List<Point2D> pts) {
      final mx = pts.map((p) => p.x).reduce((x, y) => x + y) / pts.length;
      final my = pts.map((p) => p.y).reduce((x, y) => x + y) / pts.length;
      var sxx = 0.0, sxy = 0.0, syy = 0.0;
      for (final p in pts) {
        sxx += (p.x - mx) * (p.x - mx);
        sxy += (p.x - mx) * (p.y - my);
        syy += (p.y - my) * (p.y - my);
      }
      final angle = 0.5 * atan2(2 * sxy, sxx - syy);
      return (Point2D(mx, my), Point2D(cos(angle), sin(angle)));
    }

    var merged = true;
    while (merged && runs.length > 2) {
      merged = false;
      for (var c = 0; c < runs.length; c++) {
        final d = (c + 1) % runs.length;
        final a = lines[c], b = lines[d];
        if (a == null || b == null) continue;
        final cosAngle = (a.$2.x * b.$2.x + a.$2.y * b.$2.y).abs();
        if (cosAngle < cos(8 * pi / 180)) continue;
        final joined = [...runs[c], ...runs[d].skip(1)];
        runs[c] = joined;
        lines[c] = fit(joined);
        corners.removeAt(d);
        runs.removeAt(d);
        lines.removeAt(d);
        merged = true;
        break;
      }
    }

    Point2D project(Point2D p, (Point2D, Point2D) line) {
      final (o, d) = line;
      final t = (p.x - o.x) * d.x + (p.y - o.y) * d.y;
      return Point2D(o.x + d.x * t, o.y + d.y * t);
    }

    // Corner c sits between run c-1 (ending there) and run c (starting there).
    final cornerPts = <Point2D>[];
    for (var c = 0; c < corners.length; c++) {
      final before = lines[(c - 1 + corners.length) % corners.length],
          after = lines[c];
      final raw = at(corners[c]);
      if (before != null && after != null) {
        final (o1, d1) = before;
        final (o2, d2) = after;
        final den = d1.x * d2.y - d1.y * d2.x;
        if (den.abs() > sin(10 * pi / 180)) {
          final t = ((o2.x - o1.x) * d2.y - (o2.y - o1.y) * d2.x) / den;
          cornerPts.add(Point2D(o1.x + d1.x * t, o1.y + d1.y * t));
          continue;
        }
      }
      cornerPts.add(
        before != null
            ? project(raw, before)
            : (after != null ? project(raw, after) : raw),
      );
    }

    final out = <Point2D>[];
    for (var c = 0; c < runs.length; c++) {
      out.add(cornerPts[c]);
      if (lines[c] != null) continue; // straight: next corner closes it
      final run = [...runs[c]];
      run[0] = cornerPts[c];
      run[run.length - 1] = cornerPts[(c + 1) % runs.length];
      final curve = MoldOutline(smoothRun(run, closed: false)).points;
      final simple = PolylineSimplifier.simplify(curve, 0.2);
      out.addAll(simple.sublist(1, simple.length - 1));
    }
    return out.length < 3 ? this : MoldOutline(out);
  }
}
