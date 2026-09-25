import '../../measurement/services/homography.dart';
import '../services/contour_extractor.dart';
import 'mold_board_spec.dart';

enum BoardCorner { topLeft, topRight, bottomRight, bottomLeft }

extension BoardCornerX on BoardCorner {
  /// Payload written to the QR code printed at this corner of the board.
  /// Distinct per corner (unlike the loose Módulo 1B markers) because the
  /// board is a fixed, manufactured layout: knowing which corner is which
  /// avoids ambiguity that pure geometry can't resolve on a non-square board.
  String get payload {
    switch (this) {
      case BoardCorner.topLeft:
        return 'MTV1B:TL';
      case BoardCorner.topRight:
        return 'MTV1B:TR';
      case BoardCorner.bottomRight:
        return 'MTV1B:BR';
      case BoardCorner.bottomLeft:
        return 'MTV1B:BL';
    }
  }

  static BoardCorner? fromPayload(String payload) {
    for (final corner in BoardCorner.values) {
      if (corner.payload == payload) return corner;
    }
    return null;
  }

  /// This corner's known real-world position (mm) on the board, matching
  /// the layout drawn in MoldBoardPdfBuilder.
  Point2D get knownBoardPositionMm {
    final inset = MoldBoardSpec.markerMarginMm + MoldBoardSpec.markerSizeMm / 2;
    switch (this) {
      case BoardCorner.topLeft:
        return Point2D(inset, inset);
      case BoardCorner.topRight:
        return Point2D(MoldBoardSpec.boardWidthMm - inset, inset);
      case BoardCorner.bottomRight:
        return Point2D(MoldBoardSpec.boardWidthMm - inset, MoldBoardSpec.boardHeightMm - inset);
      case BoardCorner.bottomLeft:
        return Point2D(inset, MoldBoardSpec.boardHeightMm - inset);
    }
  }

  /// The area (mm) covered by this marker on the board, with a safety
  /// margin, used to exclude the marker from mold contour detection — it
  /// contrasts with the background just as much as the mold does.
  ///
  /// The padding is generous (not just a couple mm) because the detected
  /// marker "center" is biased: QR position detectors (zxing2 included)
  /// report the centroid of the finder patterns, not the true geometric
  /// center of the printed square, and that bias measured ~3mm in testing.
  MmRect get markerExclusionRectMm {
    final center = knownBoardPositionMm;
    final halfSize = MoldBoardSpec.markerSizeMm / 2 + 8;
    return MmRect(
      left: center.x - halfSize,
      top: center.y - halfSize,
      right: center.x + halfSize,
      bottom: center.y + halfSize,
    );
  }
}
