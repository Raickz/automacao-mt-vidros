import 'dart:math';

import '../../measurement/services/homography.dart';

/// Reduces a dense, noisy list of contour points (e.g. from pixel-by-pixel
/// boundary tracing) into a clean polyline, using the Douglas-Peucker
/// algorithm. [toleranceMm] controls how much detail is preserved: larger
/// values produce fewer points but a coarser shape.
class PolylineSimplifier {
  static List<Point2D> simplify(List<Point2D> points, double toleranceMm) {
    if (points.length < 3) return points;
    return _douglasPeucker(points, toleranceMm);
  }

  static List<Point2D> _douglasPeucker(List<Point2D> points, double tolerance) {
    if (points.length < 3) return points;

    var maxDistance = 0.0;
    var splitIndex = 0;
    final first = points.first;
    final last = points.last;

    for (var i = 1; i < points.length - 1; i++) {
      final distance = _perpendicularDistance(points[i], first, last);
      if (distance > maxDistance) {
        maxDistance = distance;
        splitIndex = i;
      }
    }

    if (maxDistance > tolerance) {
      final left = _douglasPeucker(points.sublist(0, splitIndex + 1), tolerance);
      final right = _douglasPeucker(points.sublist(splitIndex), tolerance);
      return [...left.sublist(0, left.length - 1), ...right];
    }
    return [first, last];
  }

  static double _perpendicularDistance(Point2D p, Point2D a, Point2D b) {
    final dx = b.x - a.x;
    final dy = b.y - a.y;
    final lengthSquared = dx * dx + dy * dy;

    if (lengthSquared == 0) {
      return sqrt(pow(p.x - a.x, 2) + pow(p.y - a.y, 2));
    }

    final numerator = (dy * p.x - dx * p.y + b.x * a.y - b.y * a.x).abs();
    return numerator / sqrt(lengthSquared);
  }
}
