import 'homography.dart';

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

  /// Sides of the measured area the piece reaches ('em cima', 'embaixo',
  /// 'à esquerda', 'à direita'): anything beyond them was cut off.
  final List<String> touchedSides;

  const ContourResult({required this.contourMm, required this.areaPx, this.touchedSides = const []});
}
