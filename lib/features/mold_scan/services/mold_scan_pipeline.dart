import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../../measurement/services/homography.dart';
import '../models/board_corner.dart';
import '../models/mold_board_spec.dart';
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

  const MoldScanResult({required this.contourMm, this.warnings = const []});
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
  // from the board edge, so anything out there is wall/floor, and a couple of
  // millimeters of marker position error would otherwise show it as a huge
  // "object" hugging the whole border.
  static const ignoreBorderMm = 45.0;
  static const _cornerOrder = [
    BoardCorner.topLeft,
    BoardCorner.topRight,
    BoardCorner.bottomRight,
    BoardCorner.bottomLeft,
  ];

  static Future<MoldScanResult> run(
    Uint8List bytes, {
    Future<void> Function(String stage)? onStage,
  }) async {
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
    _validateGeometry(srcPixels, photo, warnings);

    await stage('Corrigindo a perspectiva...');
    final dstMm = [for (final c in _cornerOrder) c.knownBoardPositionMm];
    final pixelToMm = Homography.fromCorrespondences(srcPixels, dstMm);
    final rectified = ImageRectifier.rectify(
      source: photo,
      pixelToMm: pixelToMm,
      widthMm: MoldBoardSpec.boardWidthMm,
      heightMm: MoldBoardSpec.boardHeightMm,
      pixelsPerMm: pixelsPerMm,
    );

    await stage('Extraindo o contorno do molde...');
    final background = ContourExtractor.estimateBackgroundColor(
      image: rectified,
      pixelsPerMm: pixelsPerMm,
      boardWidthMm: MoldBoardSpec.boardWidthMm,
      boardHeightMm: MoldBoardSpec.boardHeightMm,
    );

    final ContourResult extracted;
    try {
      extracted = ContourExtractor.extract(
        image: rectified,
        backgroundR: background.$1,
        backgroundG: background.$2,
        backgroundB: background.$3,
        pixelsPerMm: pixelsPerMm,
        colorThreshold: MoldBoardSpec.colorMatchThreshold,
        excludedRegionsMm: [for (final c in BoardCorner.values) c.markerExclusionRectMm],
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

    return MoldScanResult(contourMm: contour, warnings: warnings);
  }

  /// The 4 detected points must form a convex, clockwise (as seen on screen)
  /// quadrilateral in TL, TR, BR, BL order. Anything else means a marker is
  /// stuck on the wrong corner (or the photo is mirrored), which would
  /// silently produce a distorted, wrong-size contour.
  static void _validateGeometry(List<Point2D> p, img.Image photo, List<String> warnings) {
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
    final spanMm = MoldBoardSpec.boardWidthMm - 2 * (MoldBoardSpec.markerMarginMm + MoldBoardSpec.markerSizeMm / 2);
    final pxPerMm = (dist(p[0], p[1]) + dist(p[3], p[2])) / 2 / spanMm;
    if (pxPerMm < 0.4) {
      warnings.add(
        'Foto com pouca resolução (cerca de ${(1 / pxPerMm).toStringAsFixed(1)} mm por pixel). '
        'Chegue mais perto ou use a câmera em qualidade máxima para mais precisão.',
      );
    }
  }
}
