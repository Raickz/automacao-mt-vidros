import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'homography.dart';
import '../models/board_corner.dart';
import '../models/board_geometry.dart';
import 'background_model.dart';
import 'board_marker_detector.dart';
import 'contour_extractor.dart';
import 'image_rectifier.dart';
import 'polyline_simplifier.dart';

class MoldScanException implements Exception {
  final String message;
  const MoldScanException(this.message);

  @override
  String toString() => message;
}

class MoldScanResult {
  final List<Point2D> contourMm;
  final List<String> warnings;

  /// The flattened (top-down) board photo with the detected contour drawn on
  /// it, so the user can check with their own eyes what was measured.
  final Uint8List? previewPng;

  const MoldScanResult({required this.contourMm, this.warnings = const [], this.previewPng});
}

/// The whole photo -> contour pipeline in plain Dart (no platform channels,
/// no dart:io), so web, Android and iOS all run identical code.
class MoldScanPipeline {
  // 1px/mm keeps the rectified 2.5m x 1.5m board at ~2500x1500 pixels —
  // about 1mm contour resolution, plenty for glass cutting, and still fast.
  static const pixelsPerMm = 1.0;
  static const simplifyToleranceMm = 0.8;
  // Photos larger than this are downscaled first: a 2.5m board at 3200px is
  // still >1px/mm, and 12-50MP decodes/rectifies far too slowly in Dart.
  static const maxPhotoSide = 3200;
  // The outer strip of the rectified board is ignored: markers sit 50mm in
  // from the board edge, so anything out there is wall/floor/table, and a
  // couple of millimeters of marker position error would otherwise show it as
  // a huge "object" hugging the whole border.
  static const ignoreBorderMm = 45.0;
  static const previewWidth = 1000;
  static const _cornerOrder = [
    BoardCorner.topLeft,
    BoardCorner.topRight,
    BoardCorner.bottomRight,
    BoardCorner.bottomLeft,
  ];

  static Future<MoldScanResult> run(
    Uint8List bytes, {
    BoardGeometry board = BoardGeometry.standard,
    Future<void> Function(String stage)? onStage,
  }) async {
    if (!board.isUsable) {
      throw const MoldScanException(BoardGeometry.sizeHint);
    }

    Future<void> stage(String s) async {
      if (onStage == null) return;
      await onStage(s);
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }

    final warnings = <String>[];

    await stage('Lendo a foto...');
    var photo = img.decodeImage(bytes);
    if (photo == null) {
      throw const MoldScanException('Não foi possível ler a imagem enviada. Use uma foto JPG ou PNG.');
    }
    if (photo.exif.imageIfd.hasOrientation && photo.exif.imageIfd.orientation != 1) {
      photo = img.bakeOrientation(photo);
    }
    final longSide = max(photo.width, photo.height);
    if (longSide > maxPhotoSide) {
      final k = maxPhotoSide / longSide;
      photo = img.copyResize(
        photo,
        width: (photo.width * k).round(),
        height: (photo.height * k).round(),
        interpolation: img.Interpolation.average,
      );
    }

    await stage('Procurando os 4 marcadores do quadro...');
    final corners = BoardMarkerDetector().detectFromImage(photo);
    final missing = _cornerOrder.where((c) => !corners.containsKey(c)).toList();
    if (missing.isNotEmpty) {
      throw MoldScanException(
        'Encontrei só ${corners.length} dos 4 marcadores do quadro. Confira se os 4 estão '
        'inteiros e nítidos na foto, sem reflexo, e se a foto não foi comprimida '
        '(use o arquivo original, não o enviado por WhatsApp).',
      );
    }

    final srcPixels = [for (final c in _cornerOrder) corners[c]!];
    _validateGeometry(srcPixels, board, warnings);

    await stage('Corrigindo a perspectiva...');
    final dstMm = [for (final c in _cornerOrder) c.knownPositionMm(board)];
    final pixelToMm = Homography.fromCorrespondences(srcPixels, dstMm);
    final rectified = ImageRectifier.rectify(
      source: photo,
      pixelToMm: pixelToMm,
      widthMm: board.widthMm,
      heightMm: board.heightMm,
      pixelsPerMm: pixelsPerMm,
    );

    await stage('Extraindo o contorno do molde...');
    final ContourResult extracted;
    try {
      final background = BackgroundModel.estimate(
        image: rectified,
        pixelsPerMm: pixelsPerMm,
        boardWidthMm: board.widthMm,
        boardHeightMm: board.heightMm,
      );
      extracted = ContourExtractor.extract(
        image: rectified,
        background: background,
        pixelsPerMm: pixelsPerMm,
        excludedRegionsMm: [for (final c in BoardCorner.values) c.markerExclusionRectMm(board)],
        ignoreBorderMm: ignoreBorderMm,
      );
    } on ContourExtractionException catch (e) {
      throw MoldScanException(
        '${e.message} Confira se o molde está sobre o quadro e se a foto pegou o quadro inteiro.',
      );
    }

    final contour = PolylineSimplifier.simplify(extracted.contourMm, simplifyToleranceMm);
    final xs = contour.map((p) => p.x), ys = contour.map((p) => p.y);
    final widthMm = xs.reduce(max) - xs.reduce(min);
    final heightMm = ys.reduce(max) - ys.reduce(min);
    if (widthMm < 15 || heightMm < 15) {
      throw const MoldScanException(
        'O objeto encontrado é muito pequeno (menos de 15 mm). Confira se o molde está sobre o '
        'quadro e bem iluminado, sem sombras fortes.',
      );
    }
    if (extracted.touchesIgnoredBorder) {
      warnings.add(
        'O molde chega perto da borda do quadro (últimos ${ignoreBorderMm.toStringAsFixed(0)} mm). '
        'O contorno pode estar cortado — afaste o molde da borda e refaça a foto.',
      );
    }

    await stage('Montando a prévia...');
    final preview = _buildPreview(rectified, contour);

    return MoldScanResult(contourMm: contour, warnings: warnings, previewPng: preview);
  }

  static Uint8List _buildPreview(img.Image rectified, List<Point2D> contour) {
    final scale = previewWidth / rectified.width;
    final small = img.copyResize(
      rectified,
      width: previewWidth,
      interpolation: img.Interpolation.average,
    );
    final color = img.ColorRgb8(255, 40, 120);
    for (var i = 0; i < contour.length; i++) {
      final a = contour[i], b = contour[(i + 1) % contour.length];
      img.drawLine(
        small,
        x1: (a.x * pixelsPerMm * scale).round(),
        y1: (a.y * pixelsPerMm * scale).round(),
        x2: (b.x * pixelsPerMm * scale).round(),
        y2: (b.y * pixelsPerMm * scale).round(),
        color: color,
        thickness: 3,
      );
    }
    return Uint8List.fromList(img.encodePng(small));
  }

  /// The 4 detected points must form a convex, clockwise (as seen on screen)
  /// quadrilateral in TL, TR, BR, BL order. Anything else means a marker is
  /// stuck on the wrong corner (or the photo is mirrored), which would
  /// silently produce a distorted, wrong-size contour.
  static void _validateGeometry(List<Point2D> p, BoardGeometry board, List<String> warnings) {
    for (var i = 0; i < 4; i++) {
      final a = p[i], b = p[(i + 1) % 4], c = p[(i + 2) % 4];
      final cross = (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x);
      if (cross <= 0) {
        throw const MoldScanException(
          'Os marcadores aparecem fora de ordem na foto. Confira se cada marcador está colado no '
          'canto indicado na folha (superior esquerdo, superior direito, inferior direito, '
          'inferior esquerdo) e se a foto não está espelhada.',
        );
      }
    }

    double dist(Point2D a, Point2D b) => sqrt(pow(a.x - b.x, 2) + pow(a.y - b.y, 2));
    final spanX = board.widthMm - 2 * BoardGeometry.markerInsetMm;
    final spanY = board.heightMm - 2 * BoardGeometry.markerInsetMm;
    final pxPerMmX = (dist(p[0], p[1]) + dist(p[3], p[2])) / 2 / spanX;
    final pxPerMmY = (dist(p[0], p[3]) + dist(p[1], p[2])) / 2 / spanY;

    // A photographed board is never stretched by more than perspective can
    // explain: if horizontal and vertical scales differ a lot, the board
    // size typed in doesn't match the real one.
    final ratio = pxPerMmX / pxPerMmY;
    final mismatch = 'As proporções do quadro na foto não batem com as medidas informadas '
        '(${(board.widthMm / 10).toStringAsFixed(0)} x ${(board.heightMm / 10).toStringAsFixed(0)} cm). '
        'Confira a largura e a altura reais do quadro (largura = lado horizontal na foto).';
    if (ratio > 1.8 || ratio < 1 / 1.8) {
      throw MoldScanException('$mismatch Com medidas erradas todas as medidas sairiam erradas.');
    }
    if (ratio > 1.35 || ratio < 1 / 1.35) {
      warnings.add('$mismatch Se estiverem certas, tire a foto mais de frente para o quadro.');
    }

    final pxPerMm = min(pxPerMmX, pxPerMmY);
    if (pxPerMm < 0.4) {
      warnings.add(
        'Foto com pouca resolução (cerca de ${(1 / pxPerMm).toStringAsFixed(1)} mm por pixel). '
        'Chegue mais perto ou use a câmera em qualidade máxima para mais precisão.',
      );
    }
  }
}
