import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../../measurement/services/homography.dart';
import '../models/board_corner.dart';
import '../models/mold_board_spec.dart';
import 'board_marker_detector_web.dart';
import 'contour_extractor.dart';
import 'image_rectifier.dart';
import 'polyline_simplifier.dart';

class MoldScanException implements Exception {
  final String message;
  const MoldScanException(this.message);

  @override
  String toString() => message;
}

class MoldScanService {
  static const _pixelsPerMm = 3.0;
  static const _simplifyToleranceMm = 1.0;
  static const _cornerOrder = [
    BoardCorner.topLeft,
    BoardCorner.topRight,
    BoardCorner.bottomRight,
    BoardCorner.bottomLeft,
  ];

  Future<List<Point2D>> scanContourFromBytes(Uint8List bytes) async {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw const MoldScanException('Não foi possível ler a imagem enviada.');
    }

    final corners = BoardMarkerDetectorWeb().detectFromImage(decoded);

    final missing = _cornerOrder.where((c) => !corners.containsKey(c)).toList();
    if (missing.isNotEmpty) {
      throw MoldScanException(
        'Não foi possível encontrar todos os 4 cantos do quadro de referência '
        '(faltando ${missing.length}). Envie uma foto com o quadro inteiro visível.',
      );
    }

    final srcPixels = [for (final c in _cornerOrder) corners[c]!];
    final dstMm = [for (final c in _cornerOrder) c.knownBoardPositionMm];
    final pixelToMm = Homography.fromCorrespondences(srcPixels, dstMm);

    final rectified = ImageRectifier.rectify(
      source: decoded,
      pixelToMm: pixelToMm,
      widthMm: MoldBoardSpec.boardWidthMm,
      heightMm: MoldBoardSpec.boardHeightMm,
      pixelsPerMm: _pixelsPerMm,
    );

    final rawContour = ContourExtractor.extractFromImage(
      image: rectified,
      backgroundR: MoldBoardSpec.backgroundR,
      backgroundG: MoldBoardSpec.backgroundG,
      backgroundB: MoldBoardSpec.backgroundB,
      pixelsPerMm: _pixelsPerMm,
      colorThreshold: MoldBoardSpec.colorMatchThreshold,
    );

    return PolylineSimplifier.simplify(rawContour, _simplifyToleranceMm);
  }
}
