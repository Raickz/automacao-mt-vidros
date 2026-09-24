import '../../measurement/services/homography.dart';
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
}
