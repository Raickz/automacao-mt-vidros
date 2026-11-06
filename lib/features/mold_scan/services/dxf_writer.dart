import 'dart:math';

import 'homography.dart';

/// Writes a DXF file with the closed contour as one LINE per segment, in
/// millimeters.
///
/// LINE is the oldest DXF entity (R12), so every CAD/CAM reader accepts it. A
/// hand-written LWPOLYLINE is not safe: readers like `ezdxf` reject it unless
/// it carries R2000 subclass markers and a version header, and nothing here
/// has been tried in the shop's own CAM software.
///
/// Input points use image orientation (Y grows downward, origin wherever the
/// photo put it). DXF/CAM software is Y-up, so the shape is flipped
/// vertically and moved to the origin — otherwise the CNC would cut a mirror
/// image of the mold, which only shows up on asymmetric pieces.
class DxfWriter {
  /// [comments] are written as DXF comment lines (code 999) at the top, so
  /// the project data typed by the worker (material, thickness, cutting
  /// instructions) travels inside the file. Comments are plain ASCII.
  static String write(
    List<Point2D> points, {
    String layer = 'MOLDE',
    List<String> comments = const [],
  }) {
    if (points.length < 3) {
      throw ArgumentError(
        'Contorno precisa de pelo menos 3 pontos, recebeu ${points.length}',
      );
    }

    final minX = points.map((p) => p.x).reduce(min);
    final maxY = points.map((p) => p.y).reduce(max);

    final buffer = StringBuffer();
    void pair(int code, Object value) {
      buffer.writeln(code);
      buffer.writeln(value);
    }

    for (final comment in comments) {
      for (final line in comment.split(RegExp(r'[\r\n]+'))) {
        if (line.trim().isNotEmpty) pair(999, _ascii(line.trim()));
      }
    }

    pair(0, 'SECTION');
    pair(2, 'HEADER');
    pair(9, r'$INSUNITS');
    pair(70, 4); // millimeters
    pair(0, 'ENDSEC');

    pair(0, 'SECTION');
    pair(2, 'ENTITIES');

    String x(Point2D p) => (p.x - minX).toStringAsFixed(3);
    String y(Point2D p) => (maxY - p.y).toStringAsFixed(3);
    for (var i = 0; i < points.length; i++) {
      final a = points[i], b = points[(i + 1) % points.length];
      pair(0, 'LINE');
      pair(8, layer);
      pair(10, x(a));
      pair(20, y(a));
      pair(11, x(b));
      pair(21, y(b));
    }

    pair(0, 'ENDSEC');
    pair(0, 'EOF');

    return buffer.toString();
  }

  /// File name carrying what the operator needs at a glance, e.g.
  /// `Porta_01_vidro_4mm.dxf`.
  static String fileName({
    required String name,
    String material = '',
    double? thicknessMm,
  }) {
    String clean(String s) =>
        _ascii(s.trim())
            .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_')
            .replaceAll(RegExp(r'^_+|_+$'), '');
    final base = clean(name);
    final mat = clean(material).toLowerCase();
    final thickness = (thicknessMm != null && thicknessMm > 0)
        ? '${thicknessMm == thicknessMm.roundToDouble() ? thicknessMm.round() : thicknessMm}mm'
        : '';
    return '${[base.isEmpty ? 'molde' : base, mat, thickness].where((p) => p.isNotEmpty).join('_')}.dxf';
  }

  static const _accented = 'áàâãäéèêëíìîïóòôõöúùûüçñÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇÑ';
  static const _plain = 'aaaaaeeeeiiiiooooouuuucnAAAAAEEEEIIIIOOOOOUUUUCN';

  static String _ascii(String s) {
    final out = StringBuffer();
    for (final rune in s.runes) {
      final ch = String.fromCharCode(rune);
      final i = _accented.indexOf(ch);
      if (i >= 0) {
        out.write(_plain[i]);
      } else {
        out.write(rune >= 32 && rune < 127 ? ch : '?');
      }
    }
    return out.toString();
  }
}
