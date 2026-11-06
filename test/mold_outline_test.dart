import 'package:flutter_test/flutter_test.dart';
import 'package:mt_vidros_app/features/mold_scan/services/dxf_writer.dart';
import 'package:mt_vidros_app/features/mold_scan/services/mold_catalog.dart';
import 'package:mt_vidros_app/features/mold_scan/services/svg_writer.dart';

void main() {
  test('every catalog shape is a valid closed outline at its default size', () {
    expect(MoldCatalog.all.length, greaterThanOrEqualTo(40));
    final codes = <String>{};
    for (final m in MoldCatalog.all) {
      expect(codes.add(m.code), isTrue, reason: 'duplicate code ${m.code}');
      final o = m.outline();
      expect(o.points.length, greaterThanOrEqualTo(3), reason: m.name);
      expect(o.width, closeTo(m.widthMm, 1e-6), reason: m.name);
      expect(o.height, closeTo(m.heightMm, 1e-6), reason: m.name);
      expect(o.areaMm2, greaterThan(0), reason: m.name);
    }
  });

  test('resize gives exactly the typed width and height', () {
    final o = MoldCatalog.all[1].outline().resized(1234.5, 678.9);
    expect(o.width, closeTo(1234.5, 1e-9));
    expect(o.height, closeTo(678.9, 1e-9));
    expect(o.minX, closeTo(0, 1e-9));
    expect(o.minY, closeTo(0, 1e-9));
  });

  test('rotate swaps width and height; flips keep the size', () {
    final o = MoldCatalog.all[2].outline().resized(400, 900);
    final r = o.rotated90();
    expect(r.width, closeTo(900, 1e-9));
    expect(r.height, closeTo(400, 1e-9));
    expect(o.flippedHorizontally().width, closeTo(400, 1e-9));
    expect(o.flippedVertically().height, closeTo(900, 1e-9));
    expect(o.rotated90().rotated90().rotated90().rotated90().width, closeTo(400, 1e-9));
  });

  test('offset grows a circle by the margin on each side', () {
    final c = MoldCatalog.all[0].outline().resized(600, 600);
    expect(c.offset(10).normalized().width, closeTo(620, 0.5));
    expect(c.offset(-10).normalized().width, closeTo(580, 0.5));
    expect(c.offset(0).width, closeTo(600, 1e-9));
  });

  test('spline keeps the size within a millimeter and adds points', () {
    final o = MoldCatalog.all.firstWhere((m) => m.name.startsWith('Orgânico')).outline();
    final s = o.splined();
    expect(s.points.length, greaterThanOrEqualTo(o.points.length));
    expect(s.width, closeTo(o.width, 1.0));
    expect(s.height, closeTo(o.height, 1.0));
  });

  test('DXF and SVG of a resized mold carry the typed size', () {
    final o = MoldCatalog.all[6].outline().resized(1000, 500);
    final dxf = DxfWriter.write(o.points);
    expect(dxf, contains('SECTION'));
    final svg = SvgWriter.write(o, title: 'a<b');
    expect(svg, contains('width="1000.00mm"'));
    expect(svg, contains('height="500.00mm"'));
    expect(svg, isNot(contains('a<b')));
  });
}
