// ignore_for_file: avoid_print
// Molds up to 3 m, as used at the shop: 4 markers on the floor ~3.4 x 2.0 m
// apart (outer edges of the black squares), photo of 12 MP from a ladder.
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mt_vidros_app/features/mold_scan/models/board_geometry.dart';
import 'package:mt_vidros_app/features/mold_scan/services/camera_pose.dart';
import 'package:mt_vidros_app/features/mold_scan/services/homography.dart';
import 'package:mt_vidros_app/features/mold_scan/services/mold_scan_pipeline.dart';

import 'support/camera_rig.dart';
import 'support/synthetic_scene.dart';

void main() {
  test('molde de 3 m numa área de 3,4 × 2,0 m, foto de 12 MP da escada', () async {
    // 340 x 200 cm from the outer edges of the black squares = centers 18 cm in.
    final board = BoardGeometry.fromSpansMm(3220, 1820);
    expect(board.isUsable, isTrue);
    final camera = CameraRig(
      width: 4032,
      height: 3024,
      focalRatio: 0.72,
      x: board.widthMm / 2 + 120,
      y: board.heightMm / 2 + 250,
      heightMm: 3000,
      aimX: board.widthMm / 2,
      aimY: board.heightMm / 2,
    );
    final scene = SyntheticScene(
      width: camera.width,
      height: camera.height,
      boardPixelCorners: camera.boardCorners(board),
      geometry: board,
      cameraNadir: camera.nadirMm,
      cameraHeightMm: camera.heightMm,
    );
    // A 3000 x 900 mm piece with a rounded end.
    final mold = <Point2D>[
      const Point2D(260, 600),
      const Point2D(2960, 600),
      for (var i = 1; i < 30; i++)
        Point2D(2960 + 300 * sin(pi * i / 30), 1050 - 450 * cos(pi * i / 30)),
      const Point2D(2960, 1500),
      const Point2D(260, 1500),
    ];
    final bytes = scene.renderJpg(
      SceneConfig(
        moldPolygonMm: mold,
        boardColor: (120, 118, 112),
        moldColor: (205, 190, 160),
        noiseSigma: 3,
        lightGradient: 0.15,
        thicknessMm: 6,
      ),
    );
    final r = await MoldScanPipeline.run(bytes, board: board);
    final got = CameraPoseEstimator.correctForThickness(
      r.contourMm,
      r.cameraPose,
      6,
    );
    double span(List<Point2D> p, double Function(Point2D) f) =>
        p.map(f).reduce(max) - p.map(f).reduce(min);
    final w = span(got, (p) => p.x), h = span(got, (p) => p.y);
    print(
      '  3 m: medido ${w.toStringAsFixed(1)} x ${h.toStringAsFixed(1)} mm (real 3000 x 900)',
    );
    expect(w, closeTo(3000, 5));
    expect(h, closeTo(900, 4));
  }, timeout: const Timeout(Duration(minutes: 6)));
}
