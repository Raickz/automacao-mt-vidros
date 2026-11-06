import 'dart:math';

import 'package:image/image.dart' as img;

import '../models/board_corner.dart';
import '../models/board_geometry.dart';
import 'board_marker_detector.dart';
import 'homography.dart';

/// Uses the QR codes themselves as rulers. Each printed code has a known size,
/// so its size mapped to board millimeters tells whether the board size
/// assumed by the homography is right. If that size is wrong by some factor,
/// every marker comes out bigger or smaller by that same factor, horizontally
/// and vertically — exactly, not just approximately: a wrong spacing changes
/// the homography by a scale and a shift, which scales every local length by
/// the same factors.
///
/// Both measurements return (sx, sy) = measured / expected size along the
/// board's x and y axes; the true marker spacing is the assumed one divided
/// by them.
class MarkerScale {
  /// Coarse: from the finder pattern centers reported by the QR decoder
  /// (good to ~0.5%). The two finder vectors of a code (TL->TR and TL->BL)
  /// are equal and at a right angle on paper, so ux² + wx² and uy² + wy² do
  /// not depend on how the sheet was rotated when glued.
  static (double, double)? measure(
    Map<BoardCorner, DetectedMarker> markers,
    Homography pixelToMm,
    double printedSizeMm,
  ) {
    if (markers.length < 4) return null;
    final sxs = <double>[], sys = <double>[];
    markers.forEach((corner, m) {
      final expected = corner.finderSpanMm(printedSizeMm);
      final tl = pixelToMm.apply(m.topLeft);
      final tr = pixelToMm.apply(m.topRight);
      final bl = pixelToMm.apply(m.bottomLeft);
      final ux = tr.x - tl.x, uy = tr.y - tl.y;
      final wx = bl.x - tl.x, wy = bl.y - tl.y;
      sxs.add(sqrt(ux * ux + wx * wx) / expected);
      sys.add(sqrt(uy * uy + wy * wy) / expected);
    });
    return (_median(sxs), _median(sys));
  }

  /// Fine: measures the outer edges of the black square of each code in the
  /// photo, with sub-pixel precision (where the brightness crosses halfway
  /// between the white paper and the black finder ring), over many rows and
  /// columns. Blur widens both edges equally, so the size comes out unbiased.
  /// Expects [pixelToMm]/[board] already close (within ~2%), e.g. corrected
  /// by [measure]. Returns null if fewer than 3 markers could be measured.
  ///
  /// Each side of a QR is crossed where it has finder patterns (solid black
  /// 7-module squares). Three of the 4 corners hold a finder, so one row band
  /// (top or bottom) and one column band (left or right) have finders at both
  /// ends; which ones depends on how the sheet was rotated, and is read from
  /// where the decoder found the finders.
  static (double, double)? refineWithEdges(
    img.Image photo,
    Homography pixelToMm,
    BoardGeometry board,
    Map<BoardCorner, DetectedMarker> markers,
    double printedSizeMm,
  ) {
    final h = pixelToMm.invert().rowMajor; // board mm -> photo px
    final rgb = photo.getBytes(order: img.ChannelOrder.rgb);
    final pw = photo.width, ph = photo.height;

    double luminance(Point2D mm) {
      final w = h[6] * mm.x + h[7] * mm.y + h[8];
      final px = (h[0] * mm.x + h[1] * mm.y + h[2]) / w - 0.5;
      final py = (h[3] * mm.x + h[4] * mm.y + h[5]) / w - 0.5;
      if (px < 0 || py < 0 || px >= pw - 1 || py >= ph - 1) return double.nan;
      final x0 = px.floor(), y0 = py.floor();
      final fx = px - x0, fy = py - y0;
      double at(int x, int y) {
        final o = (y * pw + x) * 3;
        return 0.299 * rgb[o] + 0.587 * rgb[o + 1] + 0.114 * rgb[o + 2];
      }

      return at(x0, y0) * (1 - fx) * (1 - fy) +
          at(x0 + 1, y0) * fx * (1 - fy) +
          at(x0, y0 + 1) * (1 - fx) * fy +
          at(x0 + 1, y0 + 1) * fx * fy;
    }

    /// Offset (mm) where the profile crosses from white (outside) to black
    /// (inside). [along] maps a signed offset (negative = outside) to a point.
    double? edge(Point2D Function(double offset) along) {
      double mean(double from, double to) {
        var sum = 0.0, n = 0;
        for (var d = from; d <= to; d += 0.25) {
          final v = luminance(along(d));
          if (v.isNaN) return double.nan;
          sum += v;
          n++;
        }
        return sum / n;
      }

      final white = mean(-5.5, -2), black = mean(2, 5.5);
      if (white.isNaN || black.isNaN || white - black < 30) return null;
      final threshold = (white + black) / 2;
      double? prevD, prevV;
      for (var d = -6.0; d <= 6.0; d += 0.1) {
        final v = luminance(along(d));
        if (v.isNaN) return null;
        if (prevV != null &&
            prevD != null &&
            prevV >= threshold &&
            v < threshold) {
          return prevD + (prevV - threshold) / (prevV - v) * (d - prevD);
        }
        prevD = d;
        prevV = v;
      }
      return null;
    }

    final sxs = <double>[], sys = <double>[];
    markers.forEach((corner, m) {
      final c = corner.knownPositionMm(board);
      final half = printedSizeMm / 2;
      final finder = printedSizeMm * 7 / corner.moduleCount;
      final left = c.x - half,
          right = c.x + half,
          top = c.y - half,
          bottom = c.y + half;

      // Which corners hold finders, from the decoder's points in board mm.
      final finders = [
        for (final f in [m.topLeft, m.topRight, m.bottomLeft])
          pixelToMm.apply(f),
      ];
      bool occupied(bool upper, bool leftSide) =>
          finders.any((p) => (p.y < c.y) == upper && (p.x < c.x) == leftSide);
      final rowsAtTop = occupied(true, true) && occupied(true, false);
      final colsAtLeft = occupied(true, true) && occupied(false, true);

      final widths = <double>[];
      for (var t = 0.2; t <= 0.8; t += 0.03) {
        final y = rowsAtTop ? top + finder * t : bottom - finder * t;
        final l = edge((d) => Point2D(left + d, y));
        final r = edge((d) => Point2D(right - d, y));
        if (l != null && r != null) widths.add((right - r) - (left + l));
      }
      final heights = <double>[];
      for (var t = 0.2; t <= 0.8; t += 0.03) {
        final x = colsAtLeft ? left + finder * t : right - finder * t;
        final tp = edge((d) => Point2D(x, top + d));
        final bt = edge((d) => Point2D(x, bottom - d));
        if (tp != null && bt != null) heights.add((bottom - bt) - (top + tp));
      }
      if (widths.length >= 5 && heights.length >= 5) {
        sxs.add(_median(widths) / printedSizeMm);
        sys.add(_median(heights) / printedSizeMm);
      }
    });
    if (sxs.length < 3) return null;
    return (_median(sxs), _median(sys));
  }

  static double _median(List<double> v) {
    final s = [...v]..sort();
    final n = s.length;
    return n.isOdd ? s[n ~/ 2] : (s[n ~/ 2 - 1] + s[n ~/ 2]) / 2;
  }
}
