// ignore_for_file: avoid_print
import 'package:flutter_test/flutter_test.dart';
import 'package:mt_vidros_app/features/mold_scan/models/board_corner.dart';
import 'package:mt_vidros_app/features/mold_scan/models/board_geometry.dart';
import 'package:mt_vidros_app/features/mold_scan/services/homography.dart';
import 'package:mt_vidros_app/features/mold_scan/services/mold_scan_pipeline.dart';

import 'support/synthetic_scene.dart';

void main() {
  final scene = SyntheticScene(
    width: 2400,
    height: 1800,
    boardPixelCorners: const [
      Point2D(190, 360),
      Point2D(2230, 330),
      Point2D(2270, 1500),
      Point2D(150, 1470),
    ],
  );
  const mold = [
    Point2D(1000, 500),
    Point2D(1700, 520),
    Point2D(1800, 900),
    Point2D(1400, 1000),
    Point2D(1000, 900),
  ];

  test('calibração manual (4 pontos clicados com ~2 px de erro) mede o molde', () async {
    final bytes = scene.renderJpg(
      const SceneConfig(moldPolygonMm: mold, noiseSigma: 3),
    );
    final mmToPx = scene.pixelToMm.invert();
    const order = [
      BoardCorner.topLeft,
      BoardCorner.topRight,
      BoardCorner.bottomRight,
      BoardCorner.bottomLeft,
    ];
    const jitter = [
      Point2D(2, -1),
      Point2D(-2, 2),
      Point2D(1, 2),
      Point2D(-1, -2),
    ];
    final centers = [
      for (var i = 0; i < 4; i++)
        () {
          final p = mmToPx.apply(
            order[i].knownPositionMm(BoardGeometry.standard),
          );
          return Point2D(
            (p.x + jitter[i].x) / scene.width,
            (p.y + jitter[i].y) / scene.height,
          );
        }(),
    ];
    final r = await MoldScanPipeline.run(
      bytes,
      board: BoardGeometry.standard,
      manualCenters: centers,
    );
    final got = boundingBox(r.contourMm), want = boundingBox(mold);
    print(
      '  manual ${got.width.toStringAsFixed(1)} x ${got.height.toStringAsFixed(1)} '
      '(real ${want.width} x ${want.height})',
    );
    expect(got.width, closeTo(want.width, 5));
    expect(got.height, closeTo(want.height, 5));
    expect(r.warnings.any((w) => w.contains('Calibração manual')), isTrue);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('calibração manual sem distância digitada é recusada', () async {
    expect(
      () => MoldScanPipeline.run(
        scene.renderJpg(const SceneConfig(moldPolygonMm: mold)),
        manualCenters: const [
          Point2D(0.1, 0.2),
          Point2D(0.9, 0.2),
          Point2D(0.9, 0.8),
          Point2D(0.1, 0.8),
        ],
      ),
      throwsA(isA<MoldScanException>()),
    );
  });
}
