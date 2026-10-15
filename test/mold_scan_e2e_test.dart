// ignore_for_file: avoid_print
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mt_vidros_app/features/measurement/services/homography.dart';
import 'package:mt_vidros_app/features/mold_scan/models/board_corner.dart';
import 'package:mt_vidros_app/features/mold_scan/models/board_geometry.dart';
import 'package:mt_vidros_app/features/mold_scan/services/mold_scan_pipeline.dart';

import 'support/synthetic_scene.dart';

Future<List<Point2D>> runPipeline(Uint8List bytes, {BoardGeometry board = BoardGeometry.standard}) async =>
    (await MoldScanPipeline.run(bytes, board: board)).contourMm;

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

const trapezoid = [
  Point2D(1000, 500),
  Point2D(1700, 520),
  Point2D(1800, 900),
  Point2D(1400, 1000),
  Point2D(1000, 900),
];

void expectMold(List<Point2D> contour, List<Point2D> truth, {double tol = 2.5}) {
  final got = boundingBox(contour);
  final want = boundingBox(truth);
  print('  medido ${got.width.toStringAsFixed(1)} x ${got.height.toStringAsFixed(1)} mm '
      '(real ${want.width.toStringAsFixed(1)} x ${want.height.toStringAsFixed(1)}), '
      'pos ${got.minX.toStringAsFixed(1)},${got.minY.toStringAsFixed(1)} '
      '(real ${want.minX.toStringAsFixed(1)},${want.minY.toStringAsFixed(1)})');
  expect(got.width, closeTo(want.width, tol), reason: 'largura');
  expect(got.height, closeTo(want.height, tol), reason: 'altura');
  expect(got.minX, closeTo(want.minX, tol), reason: 'posição x');
  expect(got.minY, closeTo(want.minY, tol), reason: 'posição y');
}

void main() {
  const timeout = Timeout(Duration(minutes: 4));

  test('cenário base: marcadores recortados, luz uniforme', () async {
    final bytes = scene.renderJpg(const SceneConfig(moldPolygonMm: trapezoid, noiseSigma: 3));
    expectMold(await runPipeline(bytes), trapezoid);
  }, timeout: timeout);

  test('folhas A4 inteiras coladas (sem recorte) não podem virar "molde"', () async {
    final bytes = scene.renderJpg(
      const SceneConfig(moldPolygonMm: trapezoid, noiseSigma: 3, paper: MarkerPaper.uncutA4),
    );
    expectMold(await runPipeline(bytes), trapezoid);
  }, timeout: timeout);

  test('iluminação irregular, sombra do molde e poeira', () async {
    final bytes = scene.renderJpg(
      const SceneConfig(
        moldPolygonMm: trapezoid,
        noiseSigma: 4,
        lightGradient: 0.45,
        shadow: true,
        specks: [(Point2D(300, 700), 4), (Point2D(700, 1300), 3), (Point2D(2100, 400), 5)],
      ),
    );
    expectMold(await runPipeline(bytes), trapezoid);
  }, timeout: timeout);

  test('tinta do quadro diferente do azul de referência', () async {
    final bytes = scene.renderJpg(
      const SceneConfig(moldPolygonMm: trapezoid, noiseSigma: 3, boardColor: (38, 70, 150)),
    );
    expectMold(await runPipeline(bytes), trapezoid);
  }, timeout: timeout);

  test('marcadores trocados de canto geram erro claro, não resultado errado', () async {
    final bytes = scene.renderJpg(
      SceneConfig(
        moldPolygonMm: trapezoid,
        payloadOverride: {
          BoardCorner.topLeft: BoardCorner.topRight.payload,
          BoardCorner.topRight: BoardCorner.topLeft.payload,
        },
      ),
    );
    await expectLater(runPipeline(bytes), throwsA(isA<MoldScanException>()));
  }, timeout: timeout);

  test('espelho grande (2000 x 900 mm) quase encostando nos marcadores', () async {
    const mirror = [Point2D(280, 300), Point2D(2280, 300), Point2D(2280, 1200), Point2D(280, 1200)];
    final bytes = scene.renderJpg(const SceneConfig(moldPolygonMm: mirror, noiseSigma: 3));
    expectMold(await runPipeline(bytes), mirror);
  }, timeout: timeout);

  test('molde preto', () async {
    final bytes = scene.renderJpg(
      const SceneConfig(moldPolygonMm: trapezoid, noiseSigma: 3, moldColor: (22, 22, 24)),
    );
    expectMold(await runPipeline(bytes), trapezoid);
  }, timeout: timeout);

  test('molde pequeno (60 x 40 mm)', () async {
    const small = [Point2D(1200, 700), Point2D(1260, 700), Point2D(1260, 740), Point2D(1200, 740)];
    final bytes = scene.renderJpg(const SceneConfig(moldPolygonMm: small, noiseSigma: 3));
    expectMold(await runPipeline(bytes), small);
  }, timeout: timeout);

  test('foto tirada de lado, com perspectiva forte', () async {
    final angled = SyntheticScene(
      width: 2400,
      height: 1800,
      boardPixelCorners: const [
        Point2D(420, 330),
        Point2D(2050, 440),
        Point2D(2330, 1640),
        Point2D(110, 1480),
      ],
    );
    final bytes = angled.renderJpg(const SceneConfig(moldPolygonMm: trapezoid, noiseSigma: 3));
    expectMold(await runPipeline(bytes), trapezoid, tol: 3.5);
  }, timeout: timeout);

  test('foto de baixa resolução (1600 px, tipo WhatsApp)', () async {
    final low = SyntheticScene(
      width: 1600,
      height: 1200,
      boardPixelCorners: const [
        Point2D(127, 240),
        Point2D(1487, 220),
        Point2D(1513, 1000),
        Point2D(100, 980),
      ],
    );
    final bytes = low.renderJpg(const SceneConfig(moldPolygonMm: trapezoid, noiseSigma: 3), quality: 75);
    expectMold(await runPipeline(bytes), trapezoid, tol: 5);
  }, timeout: timeout);

  test('sem molde sobre o quadro: erro claro', () async {
    const nothing = [Point2D(1000, 500), Point2D(1100, 500), Point2D(1050, 500)];
    final bytes = scene.renderJpg(const SceneConfig(moldPolygonMm: nothing, noiseSigma: 3));
    await expectLater(runPipeline(bytes), throwsA(isA<MoldScanException>()));
  }, timeout: timeout);

  test('quadro cortado fora da foto: erro claro pedindo os 4 marcadores', () async {
    final cut = SyntheticScene(
      width: 2400,
      height: 1800,
      boardPixelCorners: const [
        Point2D(190, 360),
        Point2D(2230, 330),
        Point2D(2600, 1500),
        Point2D(150, 1470),
      ],
    );
    final bytes = cut.renderJpg(const SceneConfig(moldPolygonMm: trapezoid));
    await expectLater(runPipeline(bytes), throwsA(isA<MoldScanException>()));
  }, timeout: timeout);

  // Reproduces the first real-world test: an improvised portrait board
  // (1.5 x 1.96 m) on a gray wall, a light wooden door with a groove between
  // frame and panel, and a table touching the bottom edge of the board.
  const portrait = BoardGeometry(widthMm: 1500, heightMm: 1960);
  final portraitScene = SyntheticScene(
    width: 1800,
    height: 2400,
    geometry: portrait,
    boardPixelCorners: const [
      Point2D(150, 130),
      Point2D(1650, 120),
      Point2D(1670, 2290),
      Point2D(130, 2300),
    ],
  );
  const door = [Point2D(530, 330), Point2D(970, 330), Point2D(970, 1760), Point2D(530, 1760)];
  const doorGrooves = [
    (Point2D(585, 385), Point2D(915, 385), 6.0),
    (Point2D(915, 385), Point2D(915, 1705), 6.0),
    (Point2D(915, 1705), Point2D(585, 1705), 6.0),
    (Point2D(585, 1705), Point2D(585, 385), 6.0),
  ];
  const doorOnGrayWall = SceneConfig(
    moldPolygonMm: door,
    boardColor: (109, 103, 94),
    moldColor: (190, 150, 110),
    noiseSigma: 3,
    lightGradient: 0.2,
    grooves: doorGrooves,
    tableBandMm: 40,
  );

  test('quadro vertical 150 x 196 cm, parede cinza, porta de madeira com sulco e mesa na borda', () async {
    final bytes = portraitScene.renderJpg(doorOnGrayWall);
    expectMold(await runPipeline(bytes, board: portrait), door, tol: 3);
  }, timeout: timeout);

  test('medidas do quadro erradas (informou 250 x 150 num quadro vertical): erro claro', () async {
    final bytes = portraitScene.renderJpg(doorOnGrayWall);
    await expectLater(runPipeline(bytes), throwsA(isA<MoldScanException>()));
  }, timeout: timeout);
}
