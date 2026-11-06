import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../models/board_corner.dart';
import '../models/board_geometry.dart';
import '../models/mold_board_spec.dart';
import 'background_model.dart';
import 'board_marker_detector.dart';
import 'camera_pose.dart';
import 'contour_extractor.dart';
import 'homography.dart';
import 'image_rectifier.dart';
import 'marker_scale.dart';
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

  /// Where the camera was, for the thickness correction; null if it could
  /// not be worked out.
  final CameraPose? cameraPose;

  /// The marker spacing actually used for the scale.
  final BoardGeometry board;

  /// True when that spacing was measured from the QR codes in the photo.
  final bool scaleFromMarkers;

  const MoldScanResult({
    required this.contourMm,
    required this.board,
    this.warnings = const [],
    this.previewPng,
    this.cameraPose,
    this.scaleFromMarkers = false,
  });
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
  // Outside the marker papers is not board: wall, floor, a table. The cut
  // papers reach 100mm out from each marker center and the virtual board edge
  // is 150mm out, so ignoring the outer 50mm stops exactly at the paper edge.
  // With the bottom papers flush with the floor, a mold standing on the floor
  // ends there too and is measured whole, with no strip of floor attached.
  static const ignoreBorderMm = 50.0;
  // Above this disagreement, a typed marker spacing is overruled by the one
  // measured from the QR codes.
  /// A spacing measured with a tape over ~2 m is more precise than one
  /// extrapolated from 18 cm QR squares (which varies ~2% between photos,
  /// with paper curl and blur), so a typed spacing wins unless it is off by
  /// more than this, which means it was measured wrong.
  static const maxManualDisagreement = 0.05;

  /// Width change between the upper and lower part of the outline above
  /// which a lean is suspected (see [_taperWarning]).
  static const maxTaper = 0.02;
  static const previewWidth = 1000;
  static const _cornerOrder = [
    BoardCorner.topLeft,
    BoardCorner.topRight,
    BoardCorner.bottomRight,
    BoardCorner.bottomLeft,
  ];

  /// [board] is the marker spacing typed by the user, or null to measure it
  /// from the QR codes. [printedMarkerMm] is the side of the black square as
  /// printed (180 when the PDF was printed at 100%).
  ///
  /// [manualCenters] skips the QR detection: the 4 marker centers marked by
  /// hand on the photo, in the order top-left, top-right, bottom-right,
  /// bottom-left, as fractions (0..1) of the photo's width and height, so
  /// they survive any resizing. The scale then comes only from [board],
  /// which becomes required.
  static Future<MoldScanResult> run(
    Uint8List bytes, {
    BoardGeometry? board,
    double printedMarkerMm = MoldBoardSpec.markerSizeMm,
    List<Point2D>? manualCenters,
    Future<void> Function(String stage)? onStage,
  }) async {
    if (board != null && !board.isUsable) {
      throw const MoldScanException(BoardGeometry.spanHint);
    }
    if (manualCenters != null && (manualCenters.length != 4 || board == null)) {
      throw const MoldScanException(
        'Na calibração manual, informe a distância entre os marcadores (horizontal e vertical) em "Escala".',
      );
    }
    if (printedMarkerMm < 120 || printedMarkerMm > 240) {
      throw const MoldScanException(
        'Informe o lado do quadrado preto impresso, em cm (o normal é 18,0).',
      );
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
      throw const MoldScanException(
        'Não foi possível ler a imagem enviada. Use uma foto JPG ou PNG.',
      );
    }
    if (photo.exif.imageIfd.hasOrientation &&
        photo.exif.imageIfd.orientation != 1) {
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

    final List<Point2D> srcPixels;
    var geometry = board ?? BoardGeometry.standard;
    var scaleFromMarkers = false;
    if (manualCenters != null) {
      srcPixels = [
        for (final c in manualCenters)
          Point2D(c.x * photo.width, c.y * photo.height),
      ];
      _checkOrder(srcPixels);
      warnings.add(
        'Calibração manual: a precisão depende de onde os 4 pontos foram colocados e da distância digitada '
        'entre os marcadores. Confira com a trena.',
      );
    } else {
      await stage('Procurando os 4 marcadores do quadro...');
      final markers = BoardMarkerDetector().detectFromImage(photo);
      final missing = _cornerOrder
          .where((c) => !markers.containsKey(c))
          .toList();
      if (missing.isNotEmpty) {
        throw MoldScanException(
          'Encontrei só ${markers.length} dos 4 marcadores do quadro. Confira se os 4 estão '
          'inteiros e nítidos na foto, sem reflexo, e se a foto não foi comprimida '
          '(use o arquivo original, não o enviado por WhatsApp).',
        );
      }
      srcPixels = [for (final c in _cornerOrder) markers[c]!.center];
      _checkOrder(srcPixels);

      await stage('Medindo a escala pelos marcadores...');
      final measured = _measureSpacing(
        photo,
        markers,
        srcPixels,
        geometry,
        printedMarkerMm,
      );
      if (measured == null) {
        if (board == null) {
          throw const MoldScanException(
            'Não consegui medir a escala pelos marcadores. Confira se os 4 estão nítidos, retos e da mesma '
            'impressão, ou informe a distância entre eles na configuração da escala.',
          );
        }
        warnings.add(
          'Não consegui conferir a escala pelos QR; usei a distância digitada.',
        );
      } else if (board == null) {
        geometry = measured;
        scaleFromMarkers = true;
      } else {
        final dx = board.spanXMm / measured.spanXMm - 1,
            dy = board.spanYMm / measured.spanYMm - 1;
        if (dx.abs() > maxManualDisagreement ||
            dy.abs() > maxManualDisagreement) {
          warnings.add(
            'A distância digitada entre os marcadores (${_cm(board.spanXMm)} × ${_cm(board.spanYMm)} cm) não '
            'bate com o tamanho dos QR na foto, que indica ${_cm(measured.spanXMm)} × ${_cm(measured.spanYMm)} cm. '
            'Usei a medida dos QR. Confira a trena e se a impressão saiu a 100% (quadrado preto de 18,0 cm).',
          );
          geometry = measured;
          scaleFromMarkers = true;
        } else if (dx.abs() > 0.008 || dy.abs() > 0.008) {
          warnings.add(
            'Usei a distância digitada (${_cm(board.spanXMm)} × ${_cm(board.spanYMm)} cm). Pelos QR daria '
            '${_cm(measured.spanXMm)} × ${_cm(measured.spanYMm)} cm; a trena é mais precisa.',
          );
        }
      }
    }
    final pixelToMm = _homography(srcPixels, geometry);
    _checkResolution(srcPixels, geometry, warnings);

    await stage('Corrigindo a perspectiva...');
    final pose = CameraPoseEstimator.estimate(
      pixelToMm: pixelToMm,
      width: photo.width,
      height: photo.height,
    );
    final rectified = ImageRectifier.rectify(
      source: photo,
      pixelToMm: pixelToMm,
      widthMm: geometry.widthMm,
      heightMm: geometry.heightMm,
      pixelsPerMm: pixelsPerMm,
    );

    await stage('Extraindo o contorno do molde...');
    final ContourResult extracted;
    try {
      final background = BackgroundModel.estimate(
        image: rectified,
        pixelsPerMm: pixelsPerMm,
        boardWidthMm: geometry.widthMm,
        boardHeightMm: geometry.heightMm,
      );
      extracted = ContourExtractor.extract(
        image: rectified,
        background: background,
        pixelsPerMm: pixelsPerMm,
        excludedRegionsMm: [
          for (final c in BoardCorner.values) c.markerExclusionRectMm(geometry),
        ],
        ignoreBorderMm: ignoreBorderMm,
      );
    } on ContourExtractionException catch (e) {
      throw MoldScanException(
        '${e.message} Confira se o molde está sobre o quadro e se a foto pegou o quadro inteiro.',
      );
    }

    final contour = PolylineSimplifier.simplify(
      extracted.contourMm,
      simplifyToleranceMm,
    );
    final xs = contour.map((p) => p.x), ys = contour.map((p) => p.y);
    final widthMm = xs.reduce(max) - xs.reduce(min);
    final heightMm = ys.reduce(max) - ys.reduce(min);
    if (widthMm < 15 || heightMm < 15) {
      throw const MoldScanException(
        'O objeto encontrado é muito pequeno (menos de 15 mm). Confira se o molde está sobre o '
        'quadro e bem iluminado, sem sombras fortes.',
      );
    }
    if (extracted.touchedSides.isNotEmpty) {
      warnings.add(
        'O molde encosta no limite da área dos marcadores (${extracted.touchedSides.join(', ')}). '
        'Tudo que passa além dos papéis dos QR fica de fora da medida. Se o molde está só apoiado no chão, '
        'rente aos QR de baixo, a medida está certa.',
      );
    }

    final taper = _taperWarning(contour);
    if (taper != null) warnings.add(taper);

    await stage('Montando a prévia...');
    final preview = _buildPreview(rectified, contour);

    return MoldScanResult(
      contourMm: contour,
      board: geometry,
      warnings: warnings,
      previewPng: preview,
      cameraPose: pose,
      scaleFromMarkers: scaleFromMarkers,
    );
  }

  /// A mold leaning on the wall with its foot away from it (or lying on a
  /// shim) is not in the markers' plane: the part closer to the camera comes
  /// out bigger. On a straight-sided mold that shows as a width that grows
  /// toward one end. Compares the widths at 20% and 80% of the height.
  static String? _taperWarning(List<Point2D> contour) {
    final ys = contour.map((p) => p.y);
    final y0 = ys.reduce(min), y1 = ys.reduce(max);
    double? widthAt(double f) {
      final y = y0 + (y1 - y0) * f + 0.37; // off the 1 mm grid of the vertices
      final xs = <double>[];
      for (var i = 0; i < contour.length; i++) {
        final a = contour[i], b = contour[(i + 1) % contour.length];
        if ((a.y > y) != (b.y > y)) {
          xs.add(a.x + (y - a.y) * (b.x - a.x) / (b.y - a.y));
        }
      }
      if (xs.length < 2) return null;
      return xs.reduce(max) - xs.reduce(min);
    }

    final top = widthAt(0.2), bottom = widthAt(0.8);
    if (top == null || bottom == null || top < 50 || bottom < 50) return null;
    final ratio = bottom / top;
    // Beyond ~15% it is the mold's own shape, not a lean.
    if ((ratio - 1).abs() <= maxTaper || (ratio - 1).abs() > 0.15) return null;
    final pct = ((ratio - 1).abs() * 100)
        .toStringAsFixed(1)
        .replaceAll('.', ',');
    final where = ratio > 1 ? 'de baixo' : 'de cima';
    return 'A parte $where do contorno saiu $pct% mais larga. Se o molde tem os lados paralelos, ele não está '
        'encostado inteiro no plano dos QR (pé afastado da parede, calço, molde inclinado): a parte mais perto da '
        'câmera aparece maior. Deite o molde no chão com os 4 QR no chão em volta, ou apoie molde e QR no mesmo quadro.';
  }

  /// The marker spacing measured from the QR codes themselves: a coarse step
  /// from the finder centers, then a fine one from the black squares' edges.
  /// [guess] only needs to be roughly right. Null if it can't be measured.
  static BoardGeometry? _measureSpacing(
    img.Image photo,
    Map<BoardCorner, DetectedMarker> markers,
    List<Point2D> srcPixels,
    BoardGeometry guess,
    double printedMarkerMm,
  ) {
    final coarse = MarkerScale.measure(
      markers,
      _homography(srcPixels, guess),
      printedMarkerMm,
    );
    if (coarse == null) return null;
    var g = BoardGeometry.fromSpansMm(
      guess.spanXMm / coarse.$1,
      guess.spanYMm / coarse.$2,
    );
    if (!g.isUsable) return null;
    final fine = MarkerScale.refineWithEdges(
      photo,
      _homography(srcPixels, g),
      g,
      markers,
      printedMarkerMm,
    );
    if (fine != null) {
      final refined = BoardGeometry.fromSpansMm(
        g.spanXMm / fine.$1,
        g.spanYMm / fine.$2,
      );
      if (refined.isUsable) g = refined;
    }
    return g;
  }

  static String _cm(double mm) =>
      (mm / 10).toStringAsFixed(1).replaceAll('.', ',');

  static Homography _homography(List<Point2D> srcPixels, BoardGeometry board) =>
      Homography.fromCorrespondences(srcPixels, [
        for (final c in _cornerOrder) c.knownPositionMm(board),
      ]);

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
  static void _checkOrder(List<Point2D> p) {
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
  }

  static void _checkResolution(
    List<Point2D> p,
    BoardGeometry board,
    List<String> warnings,
  ) {
    double dist(Point2D a, Point2D b) =>
        sqrt(pow(a.x - b.x, 2) + pow(a.y - b.y, 2));
    final pxPerMmX = (dist(p[0], p[1]) + dist(p[3], p[2])) / 2 / board.spanXMm;
    final pxPerMmY = (dist(p[0], p[3]) + dist(p[1], p[2])) / 2 / board.spanYMm;
    final pxPerMm = min(pxPerMmX, pxPerMmY);
    if (pxPerMm < 0.4) {
      warnings.add(
        'Foto com pouca resolução (cerca de ${(1 / pxPerMm).toStringAsFixed(1)} mm por pixel). '
        'Chegue mais perto ou use a câmera em qualidade máxima para mais precisão.',
      );
    }
  }
}
