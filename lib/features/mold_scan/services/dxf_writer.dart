import 'dart:math';

import '../../measurement/services/homography.dart';

/// Writes a minimal, valid DXF file containing a single closed LWPOLYLINE,
/// in millimeters.
///
/// Input points use image orientation (Y grows downward, origin wherever the
/// photo put it). DXF/CAM software is Y-up, so the shape is flipped
/// vertically and moved to the origin — otherwise the CNC would cut a mirror
/// image of the mold, which only shows up on asymmetric pieces.
class DxfWriter {
  static String write(List<Point2D> points, {String layer = 'MOLDE'}) {
    if (points.length < 3) {
      throw ArgumentError('Contorno precisa de pelo menos 3 pontos, recebeu ${points.length}');
    }

    final minX = points.map((p) => p.x).reduce(min);
    final maxY = points.map((p) => p.y).reduce(max);

    final buffer = StringBuffer();
    void pair(int code, Object value) {
      buffer.writeln(code);
      buffer.writeln(value);
    }

    pair(0, 'SECTION');
    pair(2, 'HEADER');
    pair(9, r'$INSUNITS');
    pair(70, 4); // millimeters
    pair(0, 'ENDSEC');

    pair(0, 'SECTION');
    pair(2, 'ENTITIES');

    pair(0, 'LWPOLYLINE');
    pair(8, layer);
    pair(90, points.length);
    pair(70, 1); // closed polyline
    for (final p in points) {
      pair(10, (p.x - minX).toStringAsFixed(3));
      pair(20, (maxY - p.y).toStringAsFixed(3));
    }

    pair(0, 'ENDSEC');
    pair(0, 'EOF');

    return buffer.toString();
  }
}
