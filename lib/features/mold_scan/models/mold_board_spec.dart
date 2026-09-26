/// Fixed specification of the printed reference board: a solid, high-contrast
/// background color (uncommon in cardboard, MDF or glass) with 4 identical
/// QR markers at its corners, reusing the same marker format as Módulo 1B.
class MoldBoardSpec {
  static const backgroundR = 20;
  static const backgroundG = 90;
  static const backgroundB = 200;

  // Sized to fit a single A4 sheet in landscape (297x210mm) with margins,
  // so no large-format printer is needed. Bigger boards (multi-sheet
  // tiling) are a future enhancement for larger molds. Height is kept well
  // under the 210mm page height (minus margins and heading text) — an
  // earlier 180mm value overflowed the printable area and got silently
  // clipped by the PDF renderer.
  static const boardWidthMm = 270.0;
  static const boardHeightMm = 150.0;
  static const markerSizeMm = 30.0;
  static const markerMarginMm = 8.0;

  static const colorMatchThreshold = 60.0;
}
