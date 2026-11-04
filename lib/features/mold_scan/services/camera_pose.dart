import 'dart:math';
import 'dart:typed_data';

import '../models/mold_board_spec.dart';
import 'contour_extractor.dart';
import 'homography.dart';
import 'mask_ops.dart';
import 'polyline_simplifier.dart';

/// Where the camera was when the photo was taken, in board millimeters: the
/// point of the board plane directly below the camera, and its height above
/// the board.
class CameraPose {
  final Point2D nadirMm;
  final double heightMm;

  const CameraPose({required this.nadirMm, required this.heightMm});
}

/// The 4 markers sit on the board's plane, so the photo gives a flat map of
/// that plane. A mold has thickness: its top face is closer to the camera
/// than the board, so it looks bigger than it is (a 35mm door seen from 2.5m
/// looks 1.4% larger, about 2cm on a 1.4m piece). Knowing where the camera
/// was, the top outline can be shrunk back toward the point under the camera.
class CameraPoseEstimator {
  /// Recovers the camera position from the board homography. The focal length
  /// is not in the photo, so a typical phone main camera is assumed
  /// ([MoldBoardSpec.assumedFocalRatio]); the result is a distance good to
  /// about +-20%, which is plenty to correct a few millimeters of parallax.
  /// Returns null when the numbers make no physical sense.
  static CameraPose? estimate({
    required Homography pixelToMm,
    required int width,
    required int height,
    double focalRatio = MoldBoardSpec.assumedFocalRatio,
  }) {
    final f = focalRatio * max(width, height);
    final cx = width / 2, cy = height / 2;
    final hm = pixelToMm.invert().rowMajor; // board mm -> photo px

    // M = K^-1 * H. For a plane at z=0, M's columns are r1, r2 and t up to scale.
    List<double> column(int j) {
      final a = hm[j], b = hm[3 + j], c = hm[6 + j];
      return [(a - cx * c) / f, (b - cy * c) / f, c];
    }

    double norm(List<double> v) =>
        sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
    double dot(List<double> a, List<double> b) =>
        a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
    List<double> scale(List<double> v, double k) => [
      v[0] * k,
      v[1] * k,
      v[2] * k,
    ];

    final m1 = column(0), m2 = column(1), m3 = column(2);
    final lambda = 2 / (norm(m1) + norm(m2));
    var r1 = scale(m1, lambda);
    var r2 = scale(m2, lambda);
    var t = scale(m3, lambda);
    if (t[2] < 0) {
      r1 = scale(r1, -1);
      r2 = scale(r2, -1);
      t = scale(t, -1);
    }

    // Make r1, r2 an orthonormal pair (the 4-point homography is noisy).
    r1 = scale(r1, 1 / norm(r1));
    final proj = dot(r2, r1);
    r2 = [r2[0] - proj * r1[0], r2[1] - proj * r1[1], r2[2] - proj * r1[2]];
    r2 = scale(r2, 1 / norm(r2));
    final r3 = [
      r1[1] * r2[2] - r1[2] * r2[1],
      r1[2] * r2[0] - r1[0] * r2[2],
      r1[0] * r2[1] - r1[1] * r2[0],
    ];

    // Camera center in board coordinates: C = -R^T t.
    final cxw = -dot(r1, t), cyw = -dot(r2, t), czw = -dot(r3, t);
    final h = czw.abs();
    if (!cxw.isFinite || !cyw.isFinite || !h.isFinite || h < 300 || h > 30000) {
      return null;
    }
    return CameraPose(nadirMm: Point2D(cxw, cyw), heightMm: h);
  }

  /// Recovers the mold's real outline (its base, on the board) from the
  /// silhouette seen in the photo.
  ///
  /// Seen from the camera, a mold of thickness t shows its top face scaled
  /// away from the point under the camera by k = h / (h - t), plus the side
  /// faces between top and base. So on the side facing away from the camera
  /// the silhouette ends at the (enlarged) top face, and on the side facing
  /// the camera it ends at the base. Both cases are undone by keeping only the
  /// silhouette points that, scaled out by k, are still inside the silhouette:
  /// base = silhouette ∩ S⁻¹(silhouette). Simply shrinking everything would
  /// over-correct the camera side.
  ///
  /// Done on a 1px/mm raster of the outline. Without pose or thickness the
  /// outline is returned untouched.
  static List<Point2D> correctForThickness(List<Point2D> contour, CameraPose? pose, double? thicknessMm) {
    if (pose == null || thicknessMm == null || thicknessMm <= 0 || thicknessMm >= pose.heightMm / 2) {
      return contour;
    }
    if (contour.length < 3) return contour;
    final k = pose.heightMm / (pose.heightMm - thicknessMm);
    final nx = pose.nadirMm.x, ny = pose.nadirMm.y;

    final x0 = contour.map((p) => p.x).reduce(min).floor() - 3;
    final y0 = contour.map((p) => p.y).reduce(min).floor() - 3;
    final w = contour.map((p) => p.x).reduce(max).ceil() + 3 - x0;
    final h = contour.map((p) => p.y).reduce(max).ceil() + 3 - y0;
    final silhouette = _rasterize(contour, x0, y0, w, h);

    final base = Uint8List(w * h);
    for (var y = 0; y < h; y++) {
      final cy = y0 + y + 0.5;
      for (var x = 0; x < w; x++) {
        final i = y * w + x;
        if (silhouette[i] == 0) continue;
        final cx = x0 + x + 0.5;
        final sx = (nx + (cx - nx) * k - x0).floor();
        final sy = (ny + (cy - ny) * k - y0).floor();
        if (sx >= 0 && sy >= 0 && sx < w && sy < h && silhouette[sy * w + sx] != 0) base[i] = 1;
      }
    }

    final largest = labelLargest(base, w, h);
    if (largest.bestCount < 16) return contour;
    final labels = largest.labels, best = largest.bestLabel;
    final boundary = ContourExtractor.traceBoundary(
      (x, y) => x >= 0 && y >= 0 && x < w && y < h && labels[y * w + x] == best,
      w,
      h,
    );
    final mm = [
      for (final p in ContourExtractor.boundaryToMillimeters(boundary, 1)) Point2D(p.x + x0, p.y + y0),
    ];
    return PolylineSimplifier.simplify(mm, 0.8);
  }

  /// Even-odd fill of [polygon] on a grid whose pixel (0,0) covers
  /// [x0, x0+1) x [y0, y0+1); a pixel is inside when its center is.
  static Uint8List _rasterize(List<Point2D> polygon, int x0, int y0, int w, int h) {
    final out = Uint8List(w * h);
    final crossings = <double>[];
    for (var y = 0; y < h; y++) {
      final cy = y0 + y + 0.5;
      crossings.clear();
      for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
        final a = polygon[i], b = polygon[j];
        if ((a.y > cy) != (b.y > cy)) {
          crossings.add(a.x + (cy - a.y) * (b.x - a.x) / (b.y - a.y));
        }
      }
      crossings.sort();
      for (var c = 0; c + 1 < crossings.length; c += 2) {
        final from = max(0, (crossings[c] - x0 - 0.5).ceil());
        final to = min(w - 1, (crossings[c + 1] - x0 - 0.5).floor());
        for (var x = from; x <= to; x++) {
          out[y * w + x] = 1;
        }
      }
    }
    return out;
  }
}
