import '../services/homography.dart';

class DetectedMarker {
  final String payload;
  final double sizeMm;
  final List<Point2D> cornerPoints;
  final double boundingArea;

  const DetectedMarker({
    required this.payload,
    required this.sizeMm,
    required this.cornerPoints,
    required this.boundingArea,
  });

  Point2D get centroid {
    final sumX = cornerPoints.fold<double>(0, (s, p) => s + p.x);
    final sumY = cornerPoints.fold<double>(0, (s, p) => s + p.y);
    return Point2D(sumX / cornerPoints.length, sumY / cornerPoints.length);
  }
}
