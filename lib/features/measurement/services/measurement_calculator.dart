import '../models/measurement_point.dart';

class RectangleMetrics {
  final double widthMm;
  final double heightMm;
  final double diagonal1Mm;
  final double diagonal2Mm;
  final double squareDeviationMm;

  const RectangleMetrics({
    required this.widthMm,
    required this.heightMm,
    required this.diagonal1Mm,
    required this.diagonal2Mm,
    required this.squareDeviationMm,
  });

  bool get isSquareWithinTolerance => squareDeviationMm <= 5.0;
}

class FreeformMetrics {
  final List<double> segmentLengthsMm;
  final double totalLengthMm;

  const FreeformMetrics({
    required this.segmentLengthsMm,
    required this.totalLengthMm,
  });
}

class MeasurementCalculator {
  static double distanceMm(MeasurementPoint a, MeasurementPoint b) {
    return a.toVector3().distanceTo(b.toVector3()) * 1000;
  }

  static RectangleMetrics computeRectangle(List<MeasurementPoint> points) {
    if (points.length != 4) {
      throw ArgumentError('Retângulo requer exatamente 4 pontos, recebeu ${points.length}');
    }
    final p0 = points[0], p1 = points[1], p2 = points[2], p3 = points[3];
    final width = distanceMm(p0, p1);
    final height = distanceMm(p1, p2);
    final diagonal1 = distanceMm(p0, p2);
    final diagonal2 = distanceMm(p1, p3);
    return RectangleMetrics(
      widthMm: width,
      heightMm: height,
      diagonal1Mm: diagonal1,
      diagonal2Mm: diagonal2,
      squareDeviationMm: (diagonal1 - diagonal2).abs(),
    );
  }

  static FreeformMetrics computeFreeform(List<MeasurementPoint> points) {
    final segments = <double>[];
    for (var i = 0; i < points.length - 1; i++) {
      segments.add(distanceMm(points[i], points[i + 1]));
    }
    final total = segments.fold<double>(0, (sum, s) => sum + s);
    return FreeformMetrics(segmentLengthsMm: segments, totalLengthMm: total);
  }
}
