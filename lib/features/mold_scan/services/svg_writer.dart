import 'dart:convert';
import 'dart:typed_data';

import 'mold_outline.dart';

/// SVG of the closed outline at real size (width/height in mm, so it prints
/// and imports 1:1). Y already points down, as SVG expects.
class SvgWriter {
  static String write(MoldOutline outline, {String title = 'Molde'}) {
    if (outline.points.length < 3 ||
        outline.points.any((p) => !p.x.isFinite || !p.y.isFinite)) {
      throw ArgumentError('Contorno inválido para o SVG.');
    }
    final o = outline.normalized();
    String f(double v) => v.toStringAsFixed(2);
    final d = StringBuffer('M ${f(o.points.first.x)} ${f(o.points.first.y)}');
    for (final p in o.points.skip(1)) {
      d.write(' L ${f(p.x)} ${f(p.y)}');
    }
    d.write(' Z');
    return '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<svg xmlns="http://www.w3.org/2000/svg" width="${f(o.width)}mm" height="${f(o.height)}mm" '
        'viewBox="0 0 ${f(o.width)} ${f(o.height)}">\n'
        '<title>${escapeXml(title)}</title>\n'
        '<path d="$d" fill="none" stroke="#000" stroke-width="0.5"/>\n'
        '</svg>\n';
  }

  /// The file as it must be saved: UTF-8, as the XML header declares. (The
  /// string's UTF-16 code units are not bytes: "Área" would come out as
  /// invalid UTF-8 and "–" as a control character, and the SVG would not
  /// open.)
  static Uint8List bytes(MoldOutline outline, {String title = 'Molde'}) =>
      utf8.encode(write(outline, title: title));

  /// Text safe inside an XML element or attribute: markup characters are
  /// escaped and characters XML 1.0 forbids (control codes, lone
  /// surrogates) are dropped.
  static String escapeXml(String s) {
    final out = StringBuffer();
    for (final r in s.runes) {
      final ok =
          r == 0x9 ||
          r == 0xA ||
          r == 0xD ||
          (r >= 0x20 && r <= 0xD7FF) ||
          (r >= 0xE000 && r <= 0xFFFD) ||
          (r >= 0x10000 && r <= 0x10FFFF);
      if (!ok) continue;
      switch (r) {
        case 0x26:
          out.write('&amp;');
        case 0x3C:
          out.write('&lt;');
        case 0x3E:
          out.write('&gt;');
        case 0x22:
          out.write('&quot;');
        case 0x27:
          out.write('&apos;');
        default:
          out.writeCharCode(r);
      }
    }
    return out.toString();
  }
}
