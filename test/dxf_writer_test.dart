import 'package:flutter_test/flutter_test.dart';
import 'package:mt_vidros_app/features/measurement/services/homography.dart';
import 'package:mt_vidros_app/features/mold_scan/services/dxf_writer.dart';

void main() {
  test('gera uma LWPOLYLINE fechada com os vértices corretos', () {
    final square = [
      const Point2D(0, 0),
      const Point2D(100, 0),
      const Point2D(100, 100),
      const Point2D(0, 100),
    ];

    final dxf = DxfWriter.write(square);

    expect(dxf, contains('SECTION'));
    expect(dxf, contains('ENTITIES'));
    expect(dxf, contains('LWPOLYLINE'));
    expect(dxf, contains('ENDSEC'));
    expect(dxf, contains('EOF'));

    final lines = dxf.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    final xValues = <double>[];
    final yValues = <double>[];
    for (var i = 0; i < lines.length - 1; i++) {
      if (lines[i] == '10') xValues.add(double.parse(lines[i + 1]));
      if (lines[i] == '20') yValues.add(double.parse(lines[i + 1]));
    }

    expect(xValues, [0.0, 100.0, 100.0, 0.0]);
    // Image Y grows downward; DXF is Y-up, so the shape is flipped.
    expect(yValues, [100.0, 100.0, 0.0, 0.0]);
  });

  test('inverte o eixo Y e leva o contorno para a origem (sem espelhar a peça)', () {
    // Notch on the TOP of the photo (small y) must end up at the TOP in DXF
    // (large y), far from the board's origin offset.
    final shape = [
      const Point2D(1000, 500),
      const Point2D(1100, 500),
      const Point2D(1100, 540), // top notch lowers the right-top corner
      const Point2D(1200, 540),
      const Point2D(1200, 700),
      const Point2D(1000, 700),
    ];
    final dxf = DxfWriter.write(shape);
    final lines = dxf.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    final xs = <double>[], ys = <double>[];
    for (var i = 0; i < lines.length - 1; i++) {
      if (lines[i] == '10') xs.add(double.parse(lines[i + 1]));
      if (lines[i] == '20') ys.add(double.parse(lines[i + 1]));
    }
    expect(xs.reduce((a, b) => a < b ? a : b), 0.0);
    expect(ys.reduce((a, b) => a < b ? a : b), 0.0);
    expect(ys.first, 200.0); // photo top (y=500) -> DXF top
    expect(ys[2], 160.0); // notch is below the top edge in DXF as well
    expect(dxf, contains(r'$INSUNITS'));
  });

  test('rejeita contornos com menos de 3 pontos', () {
    final tooFew = [const Point2D(0, 0), const Point2D(10, 10)];
    expect(() => DxfWriter.write(tooFew), throwsArgumentError);
  });
}
