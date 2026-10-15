import 'mold_board_spec.dart';

/// Outer size of the physical board the markers are glued on. The store's
/// permanent board is 2.5m x 1.5m, but any size works (a portrait board, a
/// test setup on a wall) as long as the 4 papers are glued
/// [MoldBoardSpec.markerMarginMm] minus [MoldBoardSpec.markerQuietZoneMm]
/// from the board's edges, as printed on each sheet.
class BoardGeometry {
  final double widthMm;
  final double heightMm;

  const BoardGeometry({required this.widthMm, required this.heightMm});

  static const standard = BoardGeometry(
    widthMm: MoldBoardSpec.boardWidthMm,
    heightMm: MoldBoardSpec.boardHeightMm,
  );

  /// Distance from the board edge to the center of a marker.
  static const markerInsetMm = MoldBoardSpec.markerMarginMm + MoldBoardSpec.markerSizeMm / 2;

  /// Marker centers must be far enough apart for the perspective math to
  /// be meaningful.
  bool get isUsable =>
      widthMm >= 4 * markerInsetMm && heightMm >= 4 * markerInsetMm && widthMm <= 8000 && heightMm <= 8000;
}
