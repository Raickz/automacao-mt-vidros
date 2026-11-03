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
  final bool touchesIgnoredBorder;

  const ContourResult({required this.contourMm, required this.areaPx, required this.touchesIgnoredBorder});
}
