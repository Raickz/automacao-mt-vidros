import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:zxing2/qrcode.dart';

import '../../measurement/services/homography.dart';
import '../models/board_corner.dart';

/// Finds the 4 board-corner QR markers in a photo using zxing2 (pure Dart,
/// so web, Android and iOS all run the exact same code on the exact same
/// decoded pixels — no mismatch between where a native scanner thinks a
/// marker is and which pixels get rectified).
///
/// zxing2 only decodes one QR per call, so markers are found one at a time:
/// decode, record, paint the found marker over, decode again. Each marker's
/// payload says which board corner it is (see [BoardCorner]).
class BoardMarkerDetector {
  static const _maxWorkSide = 2400;

  Map<BoardCorner, Point2D> detectFromImage(img.Image image) {
    final found = <BoardCorner, Point2D>{};

    final side = max(image.width, image.height);
    final scale = side > _maxWorkSide ? _maxWorkSide / side : 1.0;
    final work = scale < 1
        ? img.copyResize(image, width: (image.width * scale).round(), interpolation: img.Interpolation.average)
        : image;
    _scan(work, 1 / scale, 0, 0, found);

    if (found.length < 4) {
      // Second chance on native-resolution tiles, for photos where the
      // downscale blurred a small/far marker beyond what zxing can read.
      final tiles = [
        (x: 0.0, y: 0.0),
        (x: 0.4, y: 0.0),
        (x: 0.4, y: 0.4),
        (x: 0.0, y: 0.4),
      ];
      for (final t in tiles) {
        if (found.length == 4) break;
        final x = (image.width * t.x).round();
        final y = (image.height * t.y).round();
        final crop = img.copyCrop(
          image,
          x: x,
          y: y,
          width: (image.width * 0.6).round(),
          height: (image.height * 0.6).round(),
        );
        _scan(crop, 1, x.toDouble(), y.toDouble(), found);
      }
    }

    return found;
  }

  /// Decodes repeatedly on [image], erasing each marker once found. Points
  /// are converted back with [pointScale] and ([offsetX], [offsetY]).
  void _scan(
    img.Image image,
    double pointScale,
    double offsetX,
    double offsetY,
    Map<BoardCorner, Point2D> found,
  ) {
    final w = image.width, h = image.height;
    final rgb = image.getBytes(order: img.ChannelOrder.rgb);
    final pixels = Int32List(w * h);
    var o = 0;
    for (var i = 0; i < pixels.length; i++, o += 3) {
      pixels[i] = 0xFF000000 | (rgb[o] << 16) | (rgb[o + 1] << 8) | rgb[o + 2];
    }

    for (var attempt = 0; attempt < 8 && found.length < 4; attempt++) {
      final result = _tryDecode(w, h, pixels);
      if (result == null) return;

      final points = result.resultPoints;
      if (points.length < 3) return;

      // zxing returns [bottomLeft, topLeft, topRight(, alignment)]. The
      // midpoint of bottomLeft and topRight is the exact geometric center of
      // the code regardless of whether an alignment pattern was found —
      // unlike an average of all points, whose bias changes with that.
      final bl = points[0], tr = points[2];
      final cx = (bl.x + tr.x) / 2;
      final cy = (bl.y + tr.y) / 2;

      final corner = BoardCornerX.fromPayload(result.text);
      if (corner != null && !found.containsKey(corner)) {
        found[corner] = Point2D(offsetX + cx * pointScale, offsetY + cy * pointScale);
      }

      final radius = sqrt(pow(tr.x - bl.x, 2) + pow(tr.y - bl.y, 2)) / 2 * 1.9;
      final x0 = max(0, (cx - radius).floor()), x1 = min(w - 1, (cx + radius).ceil());
      final y0 = max(0, (cy - radius).floor()), y1 = min(h - 1, (cy + radius).ceil());
      for (var y = y0; y <= y1; y++) {
        pixels.fillRange(y * w + x0, y * w + x1 + 1, 0xFFFFFFFF);
      }
    }
  }

  Result? _tryDecode(int w, int h, Int32List pixels) {
    final attempts = <(bool, bool)>[
      (true, false), // local-threshold binarizer: best against uneven lighting
      (false, false), // global histogram binarizer
      (true, true), // local threshold, slower but more thorough finder search
    ];
    for (final (hybrid, harder) in attempts) {
      try {
        final source = RGBLuminanceSource(w, h, pixels);
        final binarizer = hybrid ? HybridBinarizer(source) : GlobalHistogramBinarizer(source);
        final hints = DecodeHints();
        if (harder) hints.put(DecodeHintType.tryHarder);
        return QRCodeReader().decode(BinaryBitmap(binarizer), hints: hints);
      } catch (_) {
        continue;
      }
    }
    return null;
  }
}
