import 'package:image/image.dart' as img;

import '../../measurement/services/homography.dart';

/// Warps a photo into a flat, top-down view at a known, fixed scale, using a
/// homography computed from reference points visible in that photo (e.g. the
/// 4 corner markers of a reference board). Once rectified, every pixel in
/// the output image corresponds to a fixed real-world distance, which is
/// what makes contour extraction produce real millimeter measurements
/// without any further per-point calculation.
///
/// This runs a loop over every output pixel and should be invoked off the
/// UI isolate (e.g. via Flutter's `compute()`) for boards larger than a few
/// hundred millimeters.
class ImageRectifier {
  static img.Image rectify({
    required img.Image source,
    required Homography pixelToMm,
    required double widthMm,
    required double heightMm,
    double pixelsPerMm = 3,
  }) {
    final mmToPixel = pixelToMm.invert();
    final outWidth = (widthMm * pixelsPerMm).round().clamp(1, 20000);
    final outHeight = (heightMm * pixelsPerMm).round().clamp(1, 20000);
    final output = img.Image(width: outWidth, height: outHeight, numChannels: 3);

    for (var oy = 0; oy < outHeight; oy++) {
      final mmY = oy / pixelsPerMm;
      for (var ox = 0; ox < outWidth; ox++) {
        final mmX = ox / pixelsPerMm;
        final srcPoint = mmToPixel.apply(Point2D(mmX, mmY));
        // Clamp (rather than skip) out-of-bounds samples so the rectified
        // image has no artificial black border — an unset/black edge would
        // otherwise read as "foreground" against the board's background
        // color and make contour extraction trace the whole board instead
        // of the mold on it.
        final sx = srcPoint.x.round().clamp(0, source.width - 1);
        final sy = srcPoint.y.round().clamp(0, source.height - 1);
        final pixel = source.getPixel(sx, sy);
        output.setPixelRgb(ox, oy, pixel.r, pixel.g, pixel.b);
      }
    }

    return output;
  }
}
