import 'mold_outline.dart';

/// SVG of the closed outline at real size (width/height in mm, so it prints
/// and imports 1:1). Y already points down, as SVG expects.
class SvgWriter {
  static String write(MoldOutline outline, {String title = 'Molde'}) {
    final o = outline.normalized();
    String f(double v) => v.toStringAsFixed(2);
    final d = StringBuffer('M ${f(o.points.first.x)} ${f(o.points.first.y)}');
    for (final p in o.points.skip(1)) {
      d.write(' L ${f(p.x)} ${f(p.y)}');
    }
    d.write(' Z');
    final safe = title.replaceAll(RegExp(r'[<>&"]'), '');
    return '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<svg xmlns="http://www.w3.org/2000/svg" width="${f(o.width)}mm" height="${f(o.height)}mm" '
        'viewBox="0 0 ${f(o.width)} ${f(o.height)}">\n'
        '<title>$safe</title>\n'
        '<path d="$d" fill="none" stroke="#000" stroke-width="0.5"/>\n'
        '</svg>\n';
  }
}
