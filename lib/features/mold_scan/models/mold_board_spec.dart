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
  // ~2m. Markers are 260mm so they stay readable in a photo taken from
  // 2-3m away (rule of thumb: max reliable reading distance ≈ 10x marker
  // size) — a 260mm marker no longer fits a single A4 sheet, so each one
  // is printed alone on its own A3 sheet instead of combined with the
  // board background like the earlier small-board design.
  static const boardWidthMm = 2500.0;
  static const boardHeightMm = 1500.0;
  static const markerSizeMm = 260.0;
  static const markerMarginMm = 60.0;

  static const colorMatchThreshold = 60.0;
}
