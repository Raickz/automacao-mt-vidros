import 'dart:math';

import '../models/mold_board_spec.dart';
import 'homography.dart';

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

  /// Moves the outline of the mold's top face down to the board plane: every
  /// point goes back toward the nadir by (h - thickness) / h. With no pose or
  /// no thickness the outline is returned untouched.
  static List<Point2D> correctForThickness(
    List<Point2D> contour,
    CameraPose? pose,
    double? thicknessMm,
  ) {
    if (pose == null ||
        thicknessMm == null ||
        thicknessMm <= 0 ||
        thicknessMm >= pose.heightMm / 2) {
      return contour;
    }
    final k = (pose.heightMm - thicknessMm) / pose.heightMm;
    final n = pose.nadirMm;
    return [
      for (final p in contour)
        Point2D(n.x + (p.x - n.x) * k, n.y + (p.y - n.y) * k),
    ];
  }
}
