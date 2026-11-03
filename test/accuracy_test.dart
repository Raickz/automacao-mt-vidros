// ignore_for_file: avoid_print
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mt_vidros_app/features/mold_scan/models/board_corner.dart';
import 'package:mt_vidros_app/features/mold_scan/models/board_geometry.dart';
import 'package:mt_vidros_app/features/mold_scan/services/camera_pose.dart';
import 'package:mt_vidros_app/features/mold_scan/services/homography.dart';
import 'package:mt_vidros_app/features/mold_scan/services/mold_scan_pipeline.dart';

import 'support/camera_rig.dart';
import 'support/synthetic_scene.dart';

const board = BoardGeometry.standard;

({double width, double height}) extent(List<Point2D> pts) {
  final xs = pts.map((p) => p.x), ys = pts.map((p) => p.y);
  return (width: xs.reduce(max) - xs.reduce(min), height: ys.reduce(max) - ys.reduce(min));
}

List<Point2D> rect(double x, double y, double w, double h) =>
    [Point2D(x, y), Point2D(x + w, y), Point2D(x + w, y + h), Point2D(x, y + h)];

void main() {
  group('posição da câmera', () {
    // Homography the pipeline would compute from the 4 marker centers.
    Homography markerHomography(CameraRig rig, {double noisePx = 0}) {
      final rng = Random(3);
      double n() => noisePx == 0 ? 0 : (rng.nextDouble() - 0.5) * 2 * noisePx;
      const order = [BoardCorner.topLeft, BoardCorner.topRight, BoardCorner.bottomRight, BoardCorner.bottomLeft];
      final px = [
        for (final c in order)
          () {
            final p = rig.project(c.knownPositionMm(board));
            return Point2D(p.x + n(), p.y + n());
          }(),
      ];
      return Homography.fromCorrespondences(px, [for (final c in order) c.knownPositionMm(board)]);
    }

    test('acha onde a câmera estava (distância e ponto logo abaixo dela)', () {
      for (final (cx, cy, h) in [(1250.0, 750.0, 2600.0), (900.0, 1000.0, 3200.0), (1700.0, 400.0, 2200.0)]) {
        final rig = CameraRig(
          width: 2400,
          height: 1800,
          focalRatio: 0.72,
          x: cx,
          y: cy,
          heightMm: h,
          aimX: 1250,
          aimY: 750,
        );
        final pose = CameraPoseEstimator.estimate(pixelToMm: markerHomography(rig), width: 2400, height: 1800)!;
        print('  câmera real h=${h.round()} nadir=(${cx.round()},${cy.round()}) -> '
            'estimado h=${pose.heightMm.round()} nadir=(${pose.nadirMm.x.round()},${pose.nadirMm.y.round()})');
        expect(pose.heightMm, closeTo(h, h * 0.02));
        expect(pose.nadirMm.x, closeTo(cx, 40));
        expect(pose.nadirMm.y, closeTo(cy, 40));
      }
    });

    test('aguenta ruído de meio pixel na posição dos marcadores', () {
      final rig = CameraRig(
        width: 2400, height: 1800, focalRatio: 0.72, x: 1100, y: 850, heightMm: 2800, aimX: 1250, aimY: 750,
      );
      final pose = CameraPoseEstimator.estimate(pixelToMm: markerHomography(rig, noisePx: 0.5), width: 2400, height: 1800)!;
      expect(pose.heightMm, closeTo(2800, 2800 * 0.10));
    });

    test('desconta a espessura só quando há pose e espessura', () {
      const pose = CameraPose(nadirMm: Point2D(1000, 500), heightMm: 2500);
      final contour = rect(0, 0, 2000, 1000);
      final fixed = CameraPoseEstimator.correctForThickness(contour, pose, 25);
      // 25mm at 2.5m = 1%: the far corner (2000,1000) is 1000/500mm from the nadir.
      expect(fixed[1].x, closeTo(1000 + 1000 * 0.99, 1e-6));
      expect(fixed[2].y, closeTo(500 + 500 * 0.99, 1e-6));
      expect(identical(CameraPoseEstimator.correctForThickness(contour, null, 25), contour), isTrue);
      expect(identical(CameraPoseEstimator.correctForThickness(contour, pose, 0), contour), isTrue);
      expect(identical(CameraPoseEstimator.correctForThickness(contour, pose, null), contour), isTrue);
    });
  });

  group('medição de ponta a ponta com câmera de verdade', () {
    const timeout = Timeout(Duration(minutes: 4));

    Future<void> check({
      required String name,
      required CameraRig rig,
      required List<Point2D> mold,
      required double thicknessMm,
      double tolCorrected = 4,
      int photoWidth = 2400,
      int quality = 90,
    }) async {
      final scene = SyntheticScene(
        width: rig.width,
        height: rig.height,
        boardPixelCorners: rig.boardCorners(board),
        geometry: board,
        cameraNadir: rig.nadirMm,
        cameraHeightMm: rig.heightMm,
      );
      final bytes = scene.renderJpg(
        SceneConfig(
          moldPolygonMm: mold,
          boardColor: (115, 115, 108),
          moldColor: (190, 150, 110),
          noiseSigma: 3,
          lightGradient: 0.2,
          thicknessMm: thicknessMm,
        ),
        quality: quality,
      );
      final result = await MoldScanPipeline.run(bytes, board: board);
      final truth = extent(mold);
      final raw = extent(result.contourMm);
      final fixed = extent(CameraPoseEstimator.correctForThickness(result.contourMm, result.cameraPose, thicknessMm));
      print('  $name: real ${truth.width.round()} x ${truth.height.round()} | '
          'sem correção ${raw.width.toStringAsFixed(1)} x ${raw.height.toStringAsFixed(1)} '
          '(erro ${(raw.width - truth.width).toStringAsFixed(1)} / ${(raw.height - truth.height).toStringAsFixed(1)}) | '
          'corrigido ${fixed.width.toStringAsFixed(1)} x ${fixed.height.toStringAsFixed(1)} '
          '(erro ${(fixed.width - truth.width).toStringAsFixed(1)} / ${(fixed.height - truth.height).toStringAsFixed(1)})');
      expect(result.cameraPose, isNotNull);
      expect(fixed.width, closeTo(truth.width, tolCorrected), reason: '$name largura');
      expect(fixed.height, closeTo(truth.height, tolCorrected), reason: '$name altura');
    }

    CameraRig rig(double x, double y, double h, {int w = 2400, int ht = 1800, double focal = 0.72}) => CameraRig(
          width: w, height: ht, focalRatio: focal, x: x, y: y, heightMm: h, aimX: 1250, aimY: 800,
        );

    test('porta de madeira de 35 mm a 2,6 m: sem correção sobra ~2 cm, com correção fica certo', () async {
      await check(name: 'porta 35mm', rig: rig(1300, 950, 2600), mold: rect(550, 500, 1400, 440), thicknessMm: 35);
    }, timeout: timeout);

    test('molde grosso visto de lado e mais longe (3,4 m)', () async {
      await check(name: 'grosso 40mm 3,4m', rig: rig(700, 1100, 3400), mold: rect(700, 450, 1000, 600), thicknessMm: 40);
    }, timeout: timeout);

    test('vidro de 8 mm a 2,2 m', () async {
      await check(name: 'vidro 8mm', rig: rig(1250, 800, 2200), mold: rect(600, 350, 1300, 700), thicknessMm: 8, tolCorrected: 3);
    }, timeout: timeout);

    test('papelão fino (3 mm), peça pequena', () async {
      await check(name: 'papelão 3mm', rig: rig(1250, 800, 2500), mold: rect(1000, 600, 300, 200), thicknessMm: 3, tolCorrected: 3);
    }, timeout: timeout);

    test('foto de 1600 px, espessura 18 mm, câmera deslocada', () async {
      await check(
        name: '1600px 18mm',
        rig: rig(1700, 600, 2700, w: 1600, ht: 1200),
        mold: rect(500, 450, 1200, 500),
        thicknessMm: 18,
        tolCorrected: 5,
        quality: 80,
      );
    }, timeout: timeout);

    // The focal length is not in the photo, so the app assumes a typical phone
    // main camera. A wide or tele lens makes the distance estimate off, and the
    // correction with it — still much better than none (21mm without).
    test('lente mais aberta que o esperado (0,55): a correção ainda tira a maior parte do erro', () async {
      await check(
        name: 'lente 0,55',
        rig: rig(1300, 950, 2600, focal: 0.55),
        mold: rect(550, 500, 1400, 440),
        thicknessMm: 35,
        tolCorrected: 9,
      );
    }, timeout: timeout);

    test('lente mais fechada que o esperado (1,0): a correção ainda tira a maior parte do erro', () async {
      await check(
        name: 'lente 1,0',
        rig: rig(1300, 950, 2600, focal: 1.0),
        mold: rect(550, 500, 1400, 440),
        thicknessMm: 35,
        tolCorrected: 10,
      );
    }, timeout: timeout);
  });
}
