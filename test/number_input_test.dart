import 'package:flutter_test/flutter_test.dart';
import 'package:mt_vidros_app/features/mold_scan/models/board_geometry.dart';
import 'package:mt_vidros_app/features/mold_scan/services/camera_pose.dart';
import 'package:mt_vidros_app/features/mold_scan/services/homography.dart';
import 'package:mt_vidros_app/features/mold_scan/services/number_input.dart';

void main() {
  test('aceita vírgula e ponto, recusa NaN e infinito', () {
    expect(parseDecimal(' 12,5 '), 12.5);
    expect(parseDecimal('4.25'), 4.25);
    expect(parseDecimal(''), isNull);
    expect(parseDecimal('abc'), isNull);
    // double.tryParse aceita estes, e eles passam por qualquer "< mínimo".
    expect(parseDecimal('NaN'), isNull);
    expect(parseDecimal('Infinity'), isNull);
    expect(parseDecimal('-Infinity'), isNull);
    expect(parseDecimal('1e400'), isNull);
  });

  test('distância "NaN" na escala é recusada', () {
    expect(BoardGeometry.fromMarkerSpans('NaN', '120'), isNull);
    expect(BoardGeometry.fromCentimeters('250', 'Infinity'), isNull);
  });

  test('espessura NaN não derruba o desconto de espessura', () {
    const contour = [
      Point2D(100, 100),
      Point2D(600, 100),
      Point2D(600, 400),
      Point2D(100, 400),
    ];
    const pose = CameraPose(nadirMm: Point2D(350, 250), heightMm: 2500);
    expect(
      CameraPoseEstimator.correctForThickness(contour, pose, double.nan),
      contour,
    );
  });
}
