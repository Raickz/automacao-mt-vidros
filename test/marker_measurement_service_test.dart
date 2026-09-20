import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mt_vidros_app/features/measurement/models/detected_marker.dart';
import 'package:mt_vidros_app/features/measurement/services/homography.dart';
import 'package:mt_vidros_app/features/measurement/services/marker_measurement_service.dart';
import 'package:mt_vidros_app/features/measurement/services/measurement_calculator.dart';

/// Simulates a camera photographing a flat plane: an arbitrary (but fixed)
/// affine map from real-world millimeters to pixel coordinates.
Point2D _toPixel(double x, double y) {
  return Point2D(0.5 * x - 0.1 * y + 300, 0.05 * x + 0.6 * y + 100);
}

List<Point2D> _markerCorners(double centerX, double centerY, double size) {
  final half = size / 2;
  return [
    Point2D(centerX - half, centerY - half),
    Point2D(centerX + half, centerY - half),
    Point2D(centerX + half, centerY + half),
    Point2D(centerX - half, centerY + half),
  ].map((p) => _toPixel(p.x, p.y)).toList();
}

void main() {
  test('recupera largura, altura e diagonal reais a partir de 4 marcadores fotografados', () {
    const size = 100.0;
    const width = 1000.0;
    const height = 1200.0;

    final markers = [
      DetectedMarker(payload: 'MTV1:100', sizeMm: size, cornerPoints: _markerCorners(0, 0, size), boundingArea: 1000),
      DetectedMarker(payload: 'MTV1:100', sizeMm: size, cornerPoints: _markerCorners(width, 0, size), boundingArea: 900),
      DetectedMarker(payload: 'MTV1:100', sizeMm: size, cornerPoints: _markerCorners(width, height, size), boundingArea: 950),
      DetectedMarker(payload: 'MTV1:100', sizeMm: size, cornerPoints: _markerCorners(0, height, size), boundingArea: 920),
    ];

    final points = MarkerMeasurementService().computeRectangleCorners(markers);
    final metrics = MeasurementCalculator.computeRectangle(points);

    final sides = [metrics.widthMm, metrics.heightMm]..sort();
    final expectedSides = [width, height]..sort();
    expect(sides[0], closeTo(expectedSides[0], 0.5));
    expect(sides[1], closeTo(expectedSides[1], 0.5));

    final expectedDiagonal = sqrt(width * width + height * height);
    expect(metrics.diagonal1Mm, closeTo(expectedDiagonal, 0.5));
    expect(metrics.diagonal2Mm, closeTo(expectedDiagonal, 0.5));
    expect(metrics.isSquareWithinTolerance, isTrue);
  });

  test('rejeita quando o número de marcadores não é 4', () {
    final markers = [
      DetectedMarker(payload: 'MTV1:100', sizeMm: 100, cornerPoints: _markerCorners(0, 0, 100), boundingArea: 1000),
    ];
    expect(
      () => MarkerMeasurementService().computeRectangleCorners(markers),
      throwsA(isA<MarkerMeasurementException>()),
    );
  });

  test('rejeita quando os marcadores têm tamanhos muito diferentes', () {
    final markers = [
      DetectedMarker(payload: 'MTV1:100', sizeMm: 100, cornerPoints: _markerCorners(0, 0, 100), boundingArea: 1000),
      DetectedMarker(payload: 'MTV1:100', sizeMm: 100, cornerPoints: _markerCorners(1000, 0, 100), boundingArea: 1000),
      DetectedMarker(payload: 'MTV1:200', sizeMm: 200, cornerPoints: _markerCorners(1000, 1200, 200), boundingArea: 1000),
      DetectedMarker(payload: 'MTV1:100', sizeMm: 100, cornerPoints: _markerCorners(0, 1200, 100), boundingArea: 1000),
    ];
    expect(
      () => MarkerMeasurementService().computeRectangleCorners(markers),
      throwsA(isA<MarkerMeasurementException>()),
    );
  });
}
