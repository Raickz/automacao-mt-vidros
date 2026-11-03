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

  /// Largest board area accepted. At 1 px/mm the photo is flattened into one
  /// pixel per mm², and the buffers needed grow with the area: 8 m² (4 x 2 m)
  /// stays well inside a phone browser's memory, 64 m² does not.
  static const maxAreaMm2 = 8e6;

  /// Marker centers must be far enough apart for the perspective math to be
  /// meaningful, and the board small enough to process.
  bool get isUsable =>
      widthMm >= 4 * markerInsetMm && heightMm >= 4 * markerInsetMm && widthMm * heightMm <= maxAreaMm2;

  /// Reads the two size fields the user types, in cm (comma or dot decimals).
  /// Returns null when a value is not a number or the board is not [isUsable].
  static BoardGeometry? fromCentimeters(String width, String height) {
    double? parse(String t) => double.tryParse(t.trim().replaceAll(',', '.'));
    final w = parse(width), h = parse(height);
    if (w == null || h == null) return null;
    final board = BoardGeometry(widthMm: w * 10, heightMm: h * 10);
    return board.isUsable ? board : null;
  }

  /// Builds the board from the distance the user measured between the
  /// markers, in cm: from the left edge of one black square to the left edge
  /// of the other (the same edge on both gives the center-to-center distance
  /// without having to find the center). Measuring this directly, instead of
  /// trusting that the papers were glued exactly where the PDF says, removes
  /// the biggest source of scale error: 1% off here is 2cm on a 2.2m board.
  static BoardGeometry? fromMarkerSpans(String horizontal, String vertical) {
    double? parse(String t) => double.tryParse(t.trim().replaceAll(',', '.'));
    final w = parse(horizontal), h = parse(vertical);
    if (w == null || h == null) return null;
    final board = BoardGeometry(widthMm: w * 10 + 2 * markerInsetMm, heightMm: h * 10 + 2 * markerInsetMm);
    return board.isUsable ? board : null;
  }

  static const spanHint =
      'Informe a distância entre os marcadores, em cm, medida do canto esquerdo de um quadrado preto até o '
      'canto esquerdo do outro. Cada medida precisa ter 30 cm ou mais, e o quadro todo no máximo 8 m².';

  static const sizeHint = 'Informe a largura e a altura reais do quadro, em cm: cada lado a partir de 60 cm '
      'e a área de até 8 m² (por exemplo, 400 × 200 cm).';
}
