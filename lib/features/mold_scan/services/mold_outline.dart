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
}
