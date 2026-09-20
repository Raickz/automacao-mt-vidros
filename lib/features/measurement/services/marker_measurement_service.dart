import 'dart:math' as math;

import '../models/detected_marker.dart';
import '../models/measurement_point.dart';
import 'homography.dart';

class MarkerMeasurementException implements Exception {
  final String message;
  const MarkerMeasurementException(this.message);

  @override
  String toString() => message;
}

class MarkerMeasurementService {
  /// Converts 4 detected identical square markers (one per corner of a
  /// rectangular opening) into 4 real-world [MeasurementPoint]s, ordered
  /// sequentially around the rectangle.
  ///
  /// Uses the marker with the largest bounding area in the photo (usually
  /// the least perspective-distorted) as the reference to compute a 2D
  /// homography from pixel space to real-world millimeters, then projects
  /// every marker's centroid through it. This works even on glass or
  /// mirrored surfaces because it never relies on tracking scene texture.
  List<MeasurementPoint> computeRectangleCorners(List<DetectedMarker> markers) {
    if (markers.length != 4) {
      throw MarkerMeasurementException(
        'Foram encontrados ${markers.length} marcador(es), mas são necessários exatamente 4.',
      );
    }

    final sizes = markers.map((m) => m.sizeMm).toList();
    final avgSize = sizes.reduce((a, b) => a + b) / sizes.length;
    for (final s in sizes) {
      if ((s - avgSize).abs() / avgSize > 0.05) {
        throw const MarkerMeasurementException(
          'Os marcadores detectados têm tamanhos diferentes. Use os 4 marcadores do mesmo kit impresso.',
        );
      }
    }

    final reference = markers.reduce((a, b) => a.boundingArea >= b.boundingArea ? a : b);
    final size = reference.sizeMm;

    // Real-world square for the reference marker, matching ML Kit's corner
    // order: clockwise starting at top-left.
    final realCorners = [
      const Point2D(0, 0),
      Point2D(size, 0),
      Point2D(size, size),
      Point2D(0, size),
    ];

    final homography = Homography.fromCorrespondences(reference.cornerPoints, realCorners);

    final realPositions = markers.map((m) => homography.apply(m.centroid)).toList();

    final orderedIndices = _orderClockwise(realPositions);

    final now = DateTime.now();
    return [
      for (var i = 0; i < orderedIndices.length; i++)
        MeasurementPoint(
          index: i,
          x: realPositions[orderedIndices[i]].x / 1000,
          y: realPositions[orderedIndices[i]].y / 1000,
          z: 0,
          capturedAt: now,
        ),
    ];
  }

  List<int> _orderClockwise(List<Point2D> points) {
    final cx = points.fold<double>(0, (s, p) => s + p.x) / points.length;
    final cy = points.fold<double>(0, (s, p) => s + p.y) / points.length;
    final indices = List<int>.generate(points.length, (i) => i);
    indices.sort((a, b) {
      final angleA = math.atan2(points[a].y - cy, points[a].x - cx);
      final angleB = math.atan2(points[b].y - cy, points[b].x - cx);
      return angleA.compareTo(angleB);
    });
    return indices;
  }
}
