import '../../measurement/services/homography.dart';

/// Writes a minimal, valid DXF file containing a single closed LWPOLYLINE.
/// A DXF file only strictly requires an ENTITIES section and EOF marker —
/// the HEADER/TABLES/BLOCKS sections are optional for basic geometry
/// interchange, which keeps this writer dependency-free.
class DxfWriter {
  static String write(List<Point2D> points, {String layer = 'MOLDE'}) {
    if (points.length < 3) {
      throw ArgumentError('Contorno precisa de pelo menos 3 pontos, recebeu ${points.length}');
    }

    final buffer = StringBuffer();
    void pair(int code, Object value) {
      buffer.writeln(code);
      buffer.writeln(value);
    }

    pair(0, 'SECTION');
    pair(2, 'ENTITIES');

    pair(0, 'LWPOLYLINE');
    pair(8, layer);
    pair(90, points.length);
    pair(70, 1); // closed polyline
    for (final p in points) {
      pair(10, p.x.toStringAsFixed(3));
      pair(20, p.y.toStringAsFixed(3));
    }

    pair(0, 'ENDSEC');
    pair(0, 'EOF');

    return buffer.toString();
  }
}
