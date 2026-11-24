// ignore_for_file: avoid_print
// Real photos from the shop's own tests (test/real/fixtures), measured with
// a tape. These guard against regressions that synthetic scenes miss:
// mottled floors and walls, stains glued to the piece, dirty wood, paper
// markers photographed at 2 m.
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mt_vidros_app/features/mold_scan/models/board_geometry.dart';
import 'package:mt_vidros_app/features/mold_scan/services/homography.dart';
import 'package:mt_vidros_app/features/mold_scan/services/mold_outline.dart';
import 'package:mt_vidros_app/features/mold_scan/services/mold_scan_pipeline.dart';

const _dir = 'test/real/fixtures';

/// Outline measured square to its own edges, as the app shows it.
MoldOutline _scan(MoldScanResult r) {
  final o = MoldOutline(r.contourMm);
  return o.rotatedBy(o.straighteningAngle()).normalized();
}

/// Width of the outline along a horizontal line at [f] of its height.
double widthAt(MoldOutline o, double f) => _span(o.points, f, horizontal: true);

/// Height of the outline along a vertical line at [f] of its width.
double heightAt(MoldOutline o, double f) =>
    _span(o.points, f, horizontal: false);

double _span(List<Point2D> pts, double f, {required bool horizontal}) {
  double along(Point2D p) => horizontal ? p.y : p.x;
  double across(Point2D p) => horizontal ? p.x : p.y;
  final lo = pts.map(along).reduce(min), hi = pts.map(along).reduce(max);
  final at = lo + (hi - lo) * f + 0.37; // off the 1 mm vertex grid
  final xs = <double>[];
  for (var i = 0; i < pts.length; i++) {
    final a = pts[i], b = pts[(i + 1) % pts.length];
    if ((along(a) > at) != (along(b) > at)) {
      xs.add(
        across(a) +
            (at - along(a)) * (across(b) - across(a)) / (along(b) - along(a)),
      );
    }
  }
  return xs.length < 2 ? 0 : xs.reduce(max) - xs.reduce(min);
}

void _dump(String name, MoldOutline raw, MoldOutline reg) {
  final dir = Platform.environment['MT_PREVIEW_DIR'];
  if (dir == null) return;
  String pts(MoldOutline o) => o.points
      .map((p) => '${p.x.toStringAsFixed(1)},${p.y.toStringAsFixed(1)}')
      .join(' ');
  File('$dir/$name.pts').writeAsStringSync('${pts(raw)}\n${pts(reg)}\n');
}

Future<MoldOutline> _run(String file, double spanX, double spanY) async {
  final r = await MoldScanPipeline.run(
    File('$_dir/$file').readAsBytesSync(),
    board: BoardGeometry.fromSpansMm(spanX, spanY),
  );
  final o = _scan(r);
  print(
    '  $file: ${o.width.toStringAsFixed(1)} x ${o.height.toStringAsFixed(1)} mm',
  );
  return o;
}

void main() {
  const timeout = Timeout(Duration(minutes: 4));

  test('piso 61 x 50 cm, foto de cima da escada (QR a 200 x 150 de fora a fora)', () async {
    final o = await _run('piso_61x50.jpg', 1820, 1320);
    // The right edge of this piece is curved, so its full height is only on
    // the left; there are no lumps of floor stain glued to it. The vertical
    // tape distance of this test was approximate (with the flat QR the
    // height comes out 50,3 cm), hence the wider height tolerance.
    expect(o.width, closeTo(610, 6), reason: 'largura total');
    expect(o.height, closeTo(500, 12), reason: 'altura total');
    expect(widthAt(o, 0.8), closeTo(610, 6));
    expect(heightAt(o, 0.05), closeTo(500, 12), reason: 'altura do lado reto');
    final r = o.regularized();
    _dump('piso', o, r);
    print(
      '  regularizado: ${r.points.length} pontos, ${r.width.toStringAsFixed(1)} x ${r.height.toStringAsFixed(1)}',
    );
    expect(
      r.width,
      closeTo(o.width, 3),
      reason: 'regularizar não muda a medida',
    );
    expect(r.height, closeTo(o.height, 3));
    expect(
      r.points.length,
      lessThan(120),
      reason: 'retas e uma curva, sem serrilhado',
    );
  }, timeout: timeout);

  test('papelão 70 x 25 cm na parede (trena: 197,4 cm de fora a fora)', () async {
    final o = await _run('papelao_70x25.jpg', 1794, 1328);
    expect(widthAt(o, 0.5), closeTo(700, 6), reason: 'largura no meio');
    expect(heightAt(o, 0.5), closeTo(250, 6), reason: 'altura no meio');
    expect(o.width, lessThan(712), reason: 'sem calombos nas pontas');
    final r = o.regularized();
    _dump('papelao', o, r);
    print(
      '  regularizado: ${r.points.length} pontos, ${r.width.toStringAsFixed(1)} x ${r.height.toStringAsFixed(1)}',
    );
    expect(r.width, closeTo(o.width, 4));
  }, timeout: timeout);

  for (final file in ['tabua_encostada.jpg', 'tabua_calco.jpg']) {
    test(
      'tábua manchada encostada na parede ($file): contorno sem mordidas',
      () async {
        final o = await _run(file, 1806, 1315);
        // Leaning, so the foot comes out wider (see README); what is checked
        // here is that dark stains on the wood never bite into the outline.
        for (final f in [0.1, 0.3, 0.5, 0.7, 0.9]) {
          expect(
            widthAt(o, f),
            inInclusiveRange(440, 495),
            reason: 'largura a ${(f * 100).round()}% da altura',
          );
        }
      },
      timeout: timeout,
    );
  }
}
