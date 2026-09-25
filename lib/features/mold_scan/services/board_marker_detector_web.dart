import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:zxing2/qrcode.dart';

import '../../measurement/services/homography.dart';
import '../models/board_corner.dart';

/// Web-compatible board marker detection using zxing2 (pure Dart, no
/// platform channels, unlike google_mlkit_barcode_scanning used on mobile).
///
/// zxing2's QRCodeReader only finds one QR per call, but our board always
/// has exactly 4 QRs, one near each corner of the photo — so instead of a
/// general multi-barcode detector, this crops the image into 4 overlapping
/// quadrants and decodes each separately. Each marker's payload says which
/// corner it is (see BoardCorner), so it doesn't matter which quadrant
/// happens to find which marker.
class BoardMarkerDetectorWeb {
  Map<BoardCorner, Point2D> detectFromImage(img.Image image) {
    final w = image.width;
    final h = image.height;
    final regions = [
      (x: 0, y: 0, w: (w * 0.6).round(), h: (h * 0.6).round()), // top-left
      (x: (w * 0.4).round(), y: 0, w: (w * 0.6).round(), h: (h * 0.6).round()), // top-right
      (x: (w * 0.4).round(), y: (h * 0.4).round(), w: (w * 0.6).round(), h: (h * 0.6).round()), // bottom-right
      (x: 0, y: (h * 0.4).round(), w: (w * 0.6).round(), h: (h * 0.6).round()), // bottom-left
    ];

    final found = <BoardCorner, Point2D>{};

    for (final region in regions) {
      final crop = img.copyCrop(image, x: region.x, y: region.y, width: region.w, height: region.h);
      final result = _tryDecode(crop);
      if (result == null) continue;

      final corner = BoardCornerX.fromPayload(result.text);
      if (corner == null) continue;

      final points = result.resultPoints;
      if (points.isEmpty) continue;

      final sumX = points.fold<double>(0, (s, p) => s + p.x);
      final sumY = points.fold<double>(0, (s, p) => s + p.y);
      found[corner] = Point2D(
        region.x + sumX / points.length,
        region.y + sumY / points.length,
      );
    }

    return found;
  }

  Result? _tryDecode(img.Image crop) {
    try {
      final pixels = Int32List(crop.width * crop.height);
      var i = 0;
      for (final pixel in crop) {
        pixels[i++] = 0xFF000000 |
            ((pixel.r.toInt() & 0xff) << 16) |
            ((pixel.g.toInt() & 0xff) << 8) |
            (pixel.b.toInt() & 0xff);
      }
      final source = RGBLuminanceSource(crop.width, crop.height, pixels);
      final bitmap = BinaryBitmap(GlobalHistogramBinarizer(source));
      return QRCodeReader().decode(bitmap);
    } catch (_) {
      return null;
    }
  }
}
