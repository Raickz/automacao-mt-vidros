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
  // ~2m. Markers are 180mm so each one fits on a single A4 sheet (the target
  // printer only supports A4). The limit on photo distance is not the marker
  // size: with a normal phone photo a 180mm marker stays readable well past
  // 3m (see the 1600px case in mold_scan_e2e_test). What limits it is
  // fitting the whole board in the frame, about 2-3m for a 2.5m board.
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

  // Focal length of a typical phone main camera (26mm equivalent) as a share
  // of the photo's long side; used to estimate how far the camera was, for the
  // thickness correction. A 2x lens is ~1.4, an ultra-wide ~0.36.
  static const assumedFocalRatio = 0.72;
}
