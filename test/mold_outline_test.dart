import 'package:flutter_test/flutter_test.dart';
import 'package:mt_vidros_app/features/mold_scan/models/board_geometry.dart';
import 'package:mt_vidros_app/features/mold_scan/services/mold_outline.dart';
import 'package:mt_vidros_app/features/mold_scan/services/homography.dart';
import 'package:mt_vidros_app/features/mold_scan/services/dxf_writer.dart';
import 'package:mt_vidros_app/features/mold_scan/services/mold_catalog.dart';
import 'package:mt_vidros_app/features/mold_scan/services/svg_writer.dart';
import 'package:mt_vidros_app/features/mold_scan/services/cut_report_pdf_builder.dart';
import 'package:mt_vidros_app/features/mold_scan/services/quote.dart';

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
    expect(
      o.rotated90().rotated90().rotated90().rotated90().width,
      closeTo(400, 1e-9),
    );
  });

  test('offset grows a circle by the margin on each side', () {
    final c = MoldCatalog.all[0].outline().resized(600, 600);
    expect(c.offset(10).normalized().width, closeTo(620, 0.5));
    expect(c.offset(-10).normalized().width, closeTo(580, 0.5));
    expect(c.offset(0).width, closeTo(600, 1e-9));
  });

  test('spline keeps the size within a millimeter and adds points', () {
    final o = MoldCatalog.all
        .firstWhere((m) => m.name.startsWith('Orgânico'))
        .outline();
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

  test('quote charges the sheet rectangle and the edge length', () {
    final o = MoldCatalog.all[0].outline().resized(1000, 500); // ellipse
    const q = Quote(pricePerM2: 200, pricePerMeter: 10, quantity: 2);
    expect(q.glass(o), closeTo(0.5 * 200 * 2, 1e-9));
    expect(q.edge(o), closeTo(o.perimeterMm / 1000 * 10 * 2, 1e-9));
    expect(Quote.brl(1234.5), 'R\$ 1.234,50');
    expect(Quote.brl(0.07), 'R\$ 0,07');
    expect(Quote.brl(1000000), 'R\$ 1.000.000,00');
  });

  test('cut report and label are valid PDFs, accents included', () async {
    final o = MoldCatalog.all[22].outline();
    final job = CutJob(
      name: 'Coração espelho',
      material: 'Espelho prata',
      glassThicknessMm: 4,
      instructions: 'Lapidação reta, furo ø 10',
      marginMm: 2,
      quote: const Quote(pricePerM2: 250, pricePerMeter: 12),
    );
    final report = await CutReportPdfBuilder.report(o, job);
    final label = await CutReportPdfBuilder.label(o, job);
    expect(String.fromCharCodes(report.take(5)), '%PDF-');
    expect(String.fromCharCodes(label.take(5)), '%PDF-');
    expect(report.length, greaterThan(2000));
  });

  test(
    'endireitar: retângulo 700 x 250 colado 1,2° torto volta a 700 x 250',
    () {
      const rect = MoldOutline([
        Point2D(0, 0),
        Point2D(700, 0),
        Point2D(700, 250),
        Point2D(0, 250),
      ]);
      final crooked = rect.rotatedBy(1.2);
      expect(crooked.width, greaterThan(704));
      final a = crooked.straighteningAngle();
      expect(a, closeTo(-1.2, 0.11));
      final s = crooked.rotatedBy(a);
      expect(s.width, closeTo(700, 0.5));
      expect(s.height, closeTo(250, 0.5));
      // a circle has no "straight" orientation
      expect(MoldCatalog.all[0].outline().straighteningAngle(), 0);
    },
  );

  test('distância de fora a fora dos quadrados pretos vira distância entre centros', () {
    final b = BoardGeometry.fromMarkerSpans(
      '197,4',
      '150',
      outerEdgesSquareMm: 180,
    )!;
    expect(b.spanXMm, closeTo(1794, 1e-9));
    expect(b.spanYMm, closeTo(1320, 1e-9));
  });
}
