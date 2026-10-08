import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../../measurement/services/homography.dart';

/// Warps a photo into a flat, top-down view at a known, fixed scale, using a
/// homography computed from reference points visible in that photo (e.g. the
/// 4 corner markers of a reference board). Once rectified, every pixel in
/// the output image corresponds to a fixed real-world distance, which is
/// what makes contour extraction produce real millimeter measurements
/// without any further per-point calculation.
///
/// Coordinates use the "pixel edge" convention (pixel i spans [i, i+1)),
/// which is what QR detectors report, and sampling is bilinear so edges stay
/// smooth when the photo is denser than the output grid.
class ImageRectifier {
  static img.Image rectify({
    required img.Image source,
    required Homography pixelToMm,
    required double widthMm,
    required double heightMm,
    double pixelsPerMm = 3,
  }) {
    final h = pixelToMm.invert().rowMajor;
    final outWidth = (widthMm * pixelsPerMm).round().clamp(1, 20000);
    final outHeight = (heightMm * pixelsPerMm).round().clamp(1, 20000);

    final srcW = source.width;
    final srcH = source.height;
    final src = source.getBytes(order: img.ChannelOrder.rgb);
    final dst = Uint8List(outWidth * outHeight * 3);
    final maxX = srcW - 1.0;
    final maxY = srcH - 1.0;

    var o = 0;
    for (var oy = 0; oy < outHeight; oy++) {
      final mmY = (oy + 0.5) / pixelsPerMm;
      for (var ox = 0; ox < outWidth; ox++, o += 3) {
        final mmX = (ox + 0.5) / pixelsPerMm;
        final w = h[6] * mmX + h[7] * mmY + h[8];
        // Clamp (rather than skip) out-of-bounds samples so the rectified
        // image has no artificial black border — an unset/black edge would
        // otherwise read as "foreground" against the board's background
        // color and make contour extraction trace the whole board instead
        // of the mold on it.
        var sx = (h[0] * mmX + h[1] * mmY + h[2]) / w - 0.5;
        var sy = (h[3] * mmX + h[4] * mmY + h[5]) / w - 0.5;
        sx = sx.clamp(0.0, maxX);
        sy = sy.clamp(0.0, maxY);

        final x0 = sx.floor();
        final y0 = sy.floor();
        final x1 = x0 + 1 < srcW ? x0 + 1 : x0;
        final y1 = y0 + 1 < srcH ? y0 + 1 : y0;
        final fx = sx - x0;
        final fy = sy - y0;
        final w00 = (1 - fx) * (1 - fy);
        final w10 = fx * (1 - fy);
        final w01 = (1 - fx) * fy;
        final w11 = fx * fy;
        final i00 = (y0 * srcW + x0) * 3;
        final i10 = (y0 * srcW + x1) * 3;
        final i01 = (y1 * srcW + x0) * 3;
        final i11 = (y1 * srcW + x1) * 3;
        for (var c = 0; c < 3; c++) {
          dst[o + c] =
              (src[i00 + c] * w00 + src[i10 + c] * w10 + src[i01 + c] * w01 + src[i11 + c] * w11 + 0.5).toInt();
        }
      }
    }

    return img.Image.fromBytes(
      width: outWidth,
      height: outHeight,
      bytes: dst.buffer,
      numChannels: 3,
    );
  }
}
