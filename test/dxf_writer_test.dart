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
    expect(yValues, [0.0, 0.0, 100.0, 100.0]);
  });

  test('rejeita contornos com menos de 3 pontos', () {
    final tooFew = [const Point2D(0, 0), const Point2D(10, 10)];
    expect(() => DxfWriter.write(tooFew), throwsArgumentError);
  });
}
