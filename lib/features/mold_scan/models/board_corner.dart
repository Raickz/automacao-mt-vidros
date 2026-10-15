import '../../measurement/services/homography.dart';
import '../services/contour_extractor.dart';
import 'board_geometry.dart';
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

  /// This corner's known real-world position (mm) on a board of the given
  /// size, matching the layout drawn in MoldBoardPdfBuilder.
  Point2D knownPositionMm([BoardGeometry board = BoardGeometry.standard]) {
    const inset = BoardGeometry.markerInsetMm;
    switch (this) {
      case BoardCorner.topLeft:
        return const Point2D(inset, inset);
      case BoardCorner.topRight:
        return Point2D(board.widthMm - inset, inset);
      case BoardCorner.bottomRight:
        return Point2D(board.widthMm - inset, board.heightMm - inset);
      case BoardCorner.bottomLeft:
        return Point2D(inset, board.heightMm - inset);
    }
  }

  /// The area (mm) covered by this marker on the board, with a safety
  /// margin, used to exclude the marker from mold contour detection — it
  /// contrasts with the background just as much as the mold does.
  ///
  /// Covers the QR plus its white paper margin (markerQuietZoneMm) plus
  /// slack for cutting/positioning error, so leftover paper can't be mistaken
  /// for the mold. Padding scales with marker size, floored at 8mm.
  MmRect markerExclusionRectMm([BoardGeometry board = BoardGeometry.standard]) {
    final center = knownPositionMm(board);
    final padding = (MoldBoardSpec.markerSizeMm * 0.15).clamp(8, double.infinity);
    final halfSize = MoldBoardSpec.markerSizeMm / 2 + padding;
    return MmRect(
      left: center.x - halfSize,
      top: center.y - halfSize,
      right: center.x + halfSize,
      bottom: center.y + halfSize,
    );
  }
}
