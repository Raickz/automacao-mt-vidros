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
  return (
    width: xs.reduce(max) - xs.reduce(min),
    height: ys.reduce(max) - ys.reduce(min),
  );
}

List<Point2D> rect(double x, double y, double w, double h) => [
  Point2D(x, y),
  Point2D(x + w, y),
  Point2D(x + w, y + h),
  Point2D(x, y + h),
];

void main() {
  group('posição da câmera', () {
    // Homography the pipeline would compute from the 4 marker centers.
    Homography markerHomography(CameraRig rig, {double noisePx = 0}) {
      final rng = Random(3);
      double n() => noisePx == 0 ? 0 : (rng.nextDouble() - 0.5) * 2 * noisePx;
      const order = [
        BoardCorner.topLeft,
        BoardCorner.topRight,
        BoardCorner.bottomRight,
        BoardCorner.bottomLeft,
      ];
      final px = [
        for (final c in order)
          () {
            final p = rig.project(c.knownPositionMm(board));
            return Point2D(p.x + n(), p.y + n());
          }(),
      ];
      return Homography.fromCorrespondences(px, [
        for (final c in order) c.knownPositionMm(board),
      ]);
    }

    test('acha onde a câmera estava (distância e ponto logo abaixo dela)', () {
      for (final (cx, cy, h) in [
        (1250.0, 750.0, 2600.0),
        (900.0, 1000.0, 3200.0),
        (1700.0, 400.0, 2200.0),
      ]) {
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
        final pose = CameraPoseEstimator.estimate(
          pixelToMm: markerHomography(rig),
          width: 2400,
          height: 1800,
        )!;
        print(
          '  câmera real h=${h.round()} nadir=(${cx.round()},${cy.round()}) -> '
          'estimado h=${pose.heightMm.round()} nadir=(${pose.nadirMm.x.round()},${pose.nadirMm.y.round()})',
        );
        expect(pose.heightMm, closeTo(h, h * 0.02));
        expect(pose.nadirMm.x, closeTo(cx, 40));
        expect(pose.nadirMm.y, closeTo(cy, 40));
      }
    });

    test('aguenta ruído de meio pixel na posição dos marcadores', () {
      final rig = CameraRig(
        width: 2400,
        height: 1800,
        focalRatio: 0.72,
        x: 1100,
        y: 850,
        heightMm: 2800,
        aimX: 1250,
        aimY: 750,
      );
      final pose = CameraPoseEstimator.estimate(
        pixelToMm: markerHomography(rig, noisePx: 0.5),
        width: 2400,
        height: 1800,
      )!;
      expect(pose.heightMm, closeTo(2800, 2800 * 0.10));
    });

    test(
      'espessura: com a câmera no meio, o molde todo encolhe na direção dela',
      () {
        const pose = CameraPose(nadirMm: Point2D(1000, 500), heightMm: 2500);
        final fixed = extent(
          CameraPoseEstimator.correctForThickness(
            rect(0, 0, 2000, 1000),
            pose,
            25,
          ),
        );
        // k = 2500 / 2475: the top face is 1% bigger than the base.
        expect(fixed.width, closeTo(2000 * 2475 / 2500, 1.5));
        expect(fixed.height, closeTo(1000 * 2475 / 2500, 1.5));
      },
    );

    test('espessura: o lado virado para a câmera (onde aparece a lateral) não é encolhido', () {
      // Camera far to the right: the right edge is the base, only the left edge is the enlarged top.
      const pose = CameraPose(nadirMm: Point2D(3000, 250), heightMm: 2500);
      final fixed = CameraPoseEstimator.correctForThickness(
        rect(0, 0, 1000, 500),
        pose,
        25,
      );
      final xs = fixed.map((p) => p.x);
      expect(xs.reduce(max), closeTo(1000, 1.5));
      expect(xs.reduce(min), closeTo(3000 - 3000 * 2475 / 2500, 1.5));
    });

    test('espessura: sem pose ou sem espessura, nada muda', () {
      const pose = CameraPose(nadirMm: Point2D(1000, 500), heightMm: 2500);
      final contour = rect(0, 0, 2000, 1000);
      expect(
        identical(
          CameraPoseEstimator.correctForThickness(contour, null, 25),
          contour,
        ),
        isTrue,
      );
      expect(
        identical(
          CameraPoseEstimator.correctForThickness(contour, pose, 0),
          contour,
        ),
        isTrue,
      );
      expect(
        identical(
          CameraPoseEstimator.correctForThickness(contour, pose, null),
          contour,
        ),
        isTrue,
      );
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
      final fixed = extent(
        CameraPoseEstimator.correctForThickness(
          result.contourMm,
          result.cameraPose,
          thicknessMm,
        ),
      );
      print(
        '  $name: real ${truth.width.round()} x ${truth.height.round()} | '
        'sem correção ${raw.width.toStringAsFixed(1)} x ${raw.height.toStringAsFixed(1)} '
        '(erro ${(raw.width - truth.width).toStringAsFixed(1)} / ${(raw.height - truth.height).toStringAsFixed(1)}) | '
        'corrigido ${fixed.width.toStringAsFixed(1)} x ${fixed.height.toStringAsFixed(1)} '
        '(erro ${(fixed.width - truth.width).toStringAsFixed(1)} / ${(fixed.height - truth.height).toStringAsFixed(1)})',
      );
      expect(result.cameraPose, isNotNull);
      expect(
        fixed.width,
        closeTo(truth.width, tolCorrected),
        reason: '$name largura',
      );
      expect(
        fixed.height,
        closeTo(truth.height, tolCorrected),
        reason: '$name altura',
      );
    }

    CameraRig rig(
      double x,
      double y,
      double h, {
      int w = 2400,
      int ht = 1800,
      double focal = 0.72,
    }) => CameraRig(
      width: w,
      height: ht,
      focalRatio: focal,
      x: x,
      y: y,
      heightMm: h,
      aimX: 1250,
      aimY: 800,
    );

    test('porta de madeira de 35 mm a 2,6 m: sem correção sobra ~2 cm, com correção fica certo', () async {
      await check(
        name: 'porta 35mm',
        rig: rig(1300, 950, 2600),
        mold: rect(550, 500, 1400, 440),
        thicknessMm: 35,
      );
    }, timeout: timeout);

    test('molde grosso visto de lado e mais longe (3,4 m)', () async {
      await check(
        name: 'grosso 40mm 3,4m',
        rig: rig(700, 1100, 3400),
        mold: rect(700, 450, 1000, 600),
        thicknessMm: 40,
      );
    }, timeout: timeout);

    test('vidro de 8 mm a 2,2 m', () async {
      await check(
        name: 'vidro 8mm',
        rig: rig(1250, 800, 2200),
        mold: rect(600, 350, 1300, 700),
        thicknessMm: 8,
        tolCorrected: 3,
      );
    }, timeout: timeout);

    test('papelão fino (3 mm), peça pequena', () async {
      await check(
        name: 'papelão 3mm',
        rig: rig(1250, 800, 2500),
        mold: rect(1000, 600, 300, 200),
        thicknessMm: 3,
        tolCorrected: 3,
      );
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

  group('escala medida pelos próprios QR (como no teste com marcadores a ~168 × 126 cm)', () {
    const timeout = Timeout(Duration(minutes: 4));
    final realBoard = BoardGeometry.fromSpansMm(1680, 1260);
    final camera = CameraRig(
      width: 2400,
      height: 1800,
      focalRatio: 0.72,
      x: 1000,
      y: 800,
      heightMm: 2200,
      aimX: 990,
      aimY: 780,
    );

    Future<MoldScanResult> scan(
      List<Point2D> mold, {
      BoardGeometry? typed,
      double printed = 180,
      double rendered = 180,
      double floorMm = 0,
    }) {
      final scene = SyntheticScene(
        width: camera.width,
        height: camera.height,
        boardPixelCorners: camera.boardCorners(realBoard),
        geometry: realBoard,
        cameraNadir: camera.nadirMm,
        cameraHeightMm: camera.heightMm,
      );
      final bytes = scene.renderJpg(
        SceneConfig(
          moldPolygonMm: mold,
          boardColor: (150, 152, 148),
          moldColor: (150, 105, 65),
          noiseSigma: 3,
          lightGradient: 0.2,
          thicknessMm: 4,
          markerSizeMm: rendered,
          tableBandMm: floorMm,
        ),
      );
      return MoldScanPipeline.run(
        bytes,
        board: typed,
        printedMarkerMm: printed,
      );
    }

    void expectSize(
      MoldScanResult r,
      List<Point2D> mold,
      String name, {
      double tol = 4,
    }) {
      final got = extent(
        CameraPoseEstimator.correctForThickness(r.contourMm, r.cameraPose, 4),
      );
      final want = extent(mold);
      print(
        '  $name: real ${want.width.round()} x ${want.height.round()} | medido '
        '${got.width.toStringAsFixed(1)} x ${got.height.toStringAsFixed(1)} | marcadores '
        '${(r.board.spanXMm / 10).toStringAsFixed(1)} x ${(r.board.spanYMm / 10).toStringAsFixed(1)} cm',
      );
      expect(got.width, closeTo(want.width, tol), reason: '$name largura');
      expect(got.height, closeTo(want.height, tol), reason: '$name altura');
    }

    final piece = rect(770, 300, 450, 1000);

    test(
      'sem digitar nada: a distância entre os marcadores sai da própria foto',
      () async {
        final r = await scan(piece);
        expect(r.scaleFromMarkers, isTrue);
        expect(r.board.spanXMm, closeTo(1680, 1680 * 0.006));
        expect(r.board.spanYMm, closeTo(1260, 1260 * 0.006));
        expectSize(r, piece, 'automático');
      },
      timeout: timeout,
    );

    test(
      'distância digitada errada (200 × 150): usa a dos QR e avisa',
      () async {
        final r = await scan(
          piece,
          typed: BoardGeometry.fromSpansMm(2000, 1500),
        );
        expect(r.scaleFromMarkers, isTrue);
        expect(r.warnings.join(' '), contains('não bate'));
        expectSize(r, piece, 'digitado errado');
      },
      timeout: timeout,
    );

    test('impressão saiu a 97%: informando o quadrado de 17,46 cm a medida fica certa', () async {
      final r = await scan(piece, printed: 174.6, rendered: 174.6);
      expectSize(r, piece, 'impressão 97%');
    }, timeout: timeout);

    test('molde em pé no chão, rente aos QR de baixo: não é cortado', () async {
      // Bottom papers flush with the floor: the floor starts at the paper edge,
      // 50mm above the virtual board edge, and the piece stands on it.
      final standing = rect(770, realBoard.heightMm - 50 - 1000, 450, 1000);
      final r = await scan(standing, floorMm: 50);
      expectSize(r, standing, 'em pé no chão');
    }, timeout: timeout);
  });
}
