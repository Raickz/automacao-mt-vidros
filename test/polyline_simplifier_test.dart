import 'package:flutter_test/flutter_test.dart';
import 'package:mt_vidros_app/features/measurement/services/homography.dart';
import 'package:mt_vidros_app/features/mold_scan/services/polyline_simplifier.dart';

void main() {
  test('remove pontos quase colineares mantendo o formato geral', () {
    // Uma linha reta de (0,0) a (10,0) com pontos intermediários que
    // desviam menos que a tolerância — devem ser removidos.
    final noisyLine = [
      const Point2D(0, 0),
      const Point2D(2, 0.1),
      const Point2D(4, -0.1),
      const Point2D(6, 0.05),
      const Point2D(8, -0.05),
      const Point2D(10, 0),
    ];

    final simplified = PolylineSimplifier.simplify(noisyLine, 0.5);

    expect(simplified.length, 2);
    expect(simplified.first.x, 0);
    expect(simplified.last.x, 10);
  });

  test('preserva um desvio real maior que a tolerância', () {
    final withCorner = [
      const Point2D(0, 0),
      const Point2D(5, 5),
      const Point2D(10, 0),
    ];

    final simplified = PolylineSimplifier.simplify(withCorner, 0.5);

    expect(simplified.length, 3);
  });

  test('não altera listas com menos de 3 pontos', () {
    final twoPoints = [const Point2D(0, 0), const Point2D(1, 1)];
    expect(PolylineSimplifier.simplify(twoPoints, 0.5), twoPoints);
  });
}
