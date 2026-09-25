import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mt_vidros_app/features/mold_scan/services/contour_extractor.dart';

void main() {
  group('extractFromImage', () {
    test('ignora um marcador excluído e encontra o molde de verdade', () {
      // Regression test: without exclusion, the raster scan (top-left to
      // bottom-right) finds the corner marker — which contrasts with the
      // background just as much as the mold — before ever reaching the
      // actual mold placed further into the image.
      final image = img.Image(width: 100, height: 100, numChannels: 3);
      img.fill(image, color: img.ColorRgb8(20, 90, 200));

      // Simulated marker near the top-left corner.
      for (var y = 0; y < 20; y++) {
        for (var x = 0; x < 20; x++) {
          image.setPixelRgb(x, y, 255, 255, 255);
        }
      }

      // The real mold, elsewhere in the image.
      for (var y = 50; y < 70; y++) {
        for (var x = 50; x < 70; x++) {
          image.setPixelRgb(x, y, 200, 30, 30);
        }
      }

      final withoutExclusion = ContourExtractor.extractFromImage(
        image: image,
        backgroundR: 20,
        backgroundG: 90,
        backgroundB: 200,
        pixelsPerMm: 1,
      );
      final withoutExclusionXs = withoutExclusion.map((p) => p.x);
      // Confirms the bug scenario: it latches onto the marker (x in 0..19).
      expect(withoutExclusionXs.reduce((a, b) => a < b ? a : b), lessThan(20));

      final withExclusion = ContourExtractor.extractFromImage(
        image: image,
        backgroundR: 20,
        backgroundG: 90,
        backgroundB: 200,
        pixelsPerMm: 1,
        excludedRegionsMm: const [MmRect(left: 0, top: 0, right: 20, bottom: 20)],
      );
      final xs = withExclusion.map((p) => p.x);
      final ys = withExclusion.map((p) => p.y);
      expect(xs.reduce((a, b) => a < b ? a : b), greaterThanOrEqualTo(50));
      expect(ys.reduce((a, b) => a < b ? a : b), greaterThanOrEqualTo(50));
    });
  });


  group('traceBoundary', () {
    bool inSquare(int x, int y) => x >= 3 && x <= 6 && y >= 3 && y <= 6;

    test('traça apenas pontos que pertencem à forma', () {
      final boundary = ContourExtractor.traceBoundary(inSquare, 10, 10);

      expect(boundary, isNotEmpty);
      for (final p in boundary) {
        expect(inSquare(p.$1, p.$2), isTrue, reason: 'ponto (${p.$1},${p.$2}) fora da forma');
      }
    });

    test('inclui os 4 cantos do quadrado', () {
      final boundary = ContourExtractor.traceBoundary(inSquare, 10, 10).toSet();

      expect(boundary, contains((3, 3)));
      expect(boundary, contains((6, 3)));
      expect(boundary, contains((6, 6)));
      expect(boundary, contains((3, 6)));
    });

    test('todo ponto retornado tem ao menos um vizinho fora da forma (é borda de verdade)', () {
      final boundary = ContourExtractor.traceBoundary(inSquare, 10, 10);

      for (final p in boundary) {
        final hasBackgroundNeighbor = [
          (p.$1 - 1, p.$2), (p.$1 + 1, p.$2),
          (p.$1, p.$2 - 1), (p.$1, p.$2 + 1),
        ].any((n) => !inSquare(n.$1, n.$2));
        expect(hasBackgroundNeighbor, isTrue, reason: 'ponto (${p.$1},${p.$2}) não é borda');
      }
    });

    test('funciona com forma côncava (L), incluindo o canto interno', () {
      // L-shape: full 6x6 block minus the top-right 3x3 corner.
      bool inL(int x, int y) {
        if (x < 1 || x > 6 || y < 1 || y > 6) return false;
        if (x >= 4 && y <= 3) return false; // recorte no canto superior direito
        return true;
      }

      final boundary = ContourExtractor.traceBoundary(inL, 10, 10);

      for (final p in boundary) {
        expect(inL(p.$1, p.$2), isTrue, reason: 'ponto (${p.$1},${p.$2}) fora da forma em L');
      }
      final asSet = boundary.toSet();
      // Reentrant corner of the L must be traced.
      expect(asSet, contains((4, 4)));
      expect(asSet, contains((1, 1)));
      expect(asSet, contains((1, 6)));
      expect(asSet, contains((6, 6)));
    });

    test('lança exceção quando não há nenhum objeto no fundo', () {
      expect(
        () => ContourExtractor.traceBoundary((x, y) => false, 10, 10),
        throwsA(isA<ContourExtractionException>()),
      );
    });
  });
}
