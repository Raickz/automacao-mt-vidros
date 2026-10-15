/// Specification of the physical reference setup: a large, fixed, solid-color
/// board built at the store (not something we print), with 4 QR markers
/// mounted at its corners — printed separately, individually, since at this
/// size they no longer fit on a single sheet with the board background.
///
/// [backgroundR]/[backgroundG]/[backgroundB] are only a fallback/reference —
/// actual detection samples the real board color from each photo (see
/// `ContourExtractor`/`MoldScanService`), since matching a paint color to an
/// exact RGB value in real life is unreliable and this board is physically
/// painted once, not reprintable.
class MoldBoardSpec {
  static const backgroundR = 20;
  static const backgroundG = 90;
  static const backgroundB = 200;

  // A fixed board built at the store, sized for glass/mirror pieces up to
  // ~2m. Markers are 180mm so each one fits on a single A4 sheet with no
  // cutting or taping (the target printer only supports A4). Rule of thumb:
  // max reliable reading distance ≈ 10x marker size, so photos should be
  // taken from no more than ~1.8m away.
  static const boardWidthMm = 2500.0;
  static const boardHeightMm = 1500.0;
  static const markerSizeMm = 180.0;
  static const markerMarginMm = 60.0;
  // White paper left around each QR so it keeps a clean quiet zone. The
  // printed sheet is cut along this line, so the paper's own edge sits
  // (markerMarginMm - markerQuietZoneMm) from the board edge.
  static const markerQuietZoneMm = 10.0;

  // Foreground detection (see ContourExtractor.extract). A pixel is "the
  // mold" when its color differs from the board's by more than this share of
  // the board color's own magnitude, ignoring brightness...
  static const chromaThresholdRatio = 0.12;
  // ...or when it is much brighter / much darker than the board *at that
  // spot* (shadows only darken moderately, so they stay background).
  static const brightnessMaxRatio = 1.22;
  static const brightnessMinRatio = 0.35;
  // Where the piece's edge is placed, as a share of its own contrast.
  static const edgeContrastRatio = 0.35;
}
