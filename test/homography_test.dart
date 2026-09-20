import 'package:flutter_test/flutter_test.dart';
import 'package:mt_vidros_app/features/measurement/services/homography.dart';

void main() {
  test('identidade: pontos iguais na origem e no destino não mudam nada', () {
    final square = [
      const Point2D(0, 0),
      const Point2D(1, 0),
      const Point2D(1, 1),
      const Point2D(0, 1),
    ];
    final h = Homography.fromCorrespondences(square, square);
    final p = h.apply(const Point2D(0.5, 0.5));
    expect(p.x, closeTo(0.5, 1e-9));
    expect(p.y, closeTo(0.5, 1e-9));
  });

  test('escala pura: quadrado unitário mapeado para 100x100', () {
    final src = [
      const Point2D(0, 0),
      const Point2D(1, 0),
      const Point2D(1, 1),
      const Point2D(0, 1),
    ];
    final dst = [
      const Point2D(0, 0),
      const Point2D(100, 0),
      const Point2D(100, 100),
      const Point2D(0, 100),
    ];
    final h = Homography.fromCorrespondences(src, dst);
    final center = h.apply(const Point2D(0.5, 0.5));
    expect(center.x, closeTo(50, 1e-6));
    expect(center.y, closeTo(50, 1e-6));
  });

  test('perspectiva: mapeia um trapézio (câmera em ângulo) de volta a um quadrado real', () {
    // Um marcador de 100x100mm fotografado em ângulo aparece como um
    // quadrilátero não-retangular na imagem (pixels). A homografia deve
    // desfazer essa distorção e recuperar as coordenadas reais.
    final markerRealCorners = [
      const Point2D(0, 0),
      const Point2D(100, 0),
      const Point2D(100, 100),
      const Point2D(0, 100),
    ];
    final markerPixelCorners = [
      const Point2D(200, 150),
      const Point2D(340, 160),
      const Point2D(330, 300),
      const Point2D(210, 290),
    ];

    final h = Homography.fromCorrespondences(markerPixelCorners, markerRealCorners);

    for (var i = 0; i < 4; i++) {
      final recovered = h.apply(markerPixelCorners[i]);
      expect(recovered.x, closeTo(markerRealCorners[i].x, 1e-6));
      expect(recovered.y, closeTo(markerRealCorners[i].y, 1e-6));
    }
  });

  test('invert() desfaz a transformação original', () {
    final src = [
      const Point2D(0, 0),
      const Point2D(1, 0),
      const Point2D(1, 1),
      const Point2D(0, 1),
    ];
    final dst = [
      const Point2D(10, 20),
      const Point2D(60, 25),
      const Point2D(55, 80),
      const Point2D(15, 75),
    ];
    final h = Homography.fromCorrespondences(src, dst);
    final inv = h.invert();

    final roundTrip = inv.apply(h.apply(const Point2D(0.3, 0.7)));
    expect(roundTrip.x, closeTo(0.3, 1e-6));
    expect(roundTrip.y, closeTo(0.7, 1e-6));
  });
}
