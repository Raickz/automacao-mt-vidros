import 'dart:math';

import 'package:mt_vidros_app/features/mold_scan/models/board_geometry.dart';
import 'package:mt_vidros_app/features/mold_scan/services/homography.dart';

/// A pinhole camera looking at the board plane, to produce photos with
/// realistic perspective and a known ground truth for where the camera is.
///
/// Board coordinates: x right, y down (like the photo of a board seen from
/// the front), z pointing into the board, so the camera sits at z = -height.
class CameraRig {
  final int width;
  final int height;
  final double focalPx;
  final double x;
  final double y;
  final double heightMm;

  late final List<double> _right, _down, _forward;

  /// [aimX]/[aimY] is the board point at the center of the frame.
  CameraRig({
    required this.width,
    required this.height,
    required double focalRatio,
    required this.x,
    required this.y,
    required this.heightMm,
    required double aimX,
    required double aimY,
  }) : focalPx = focalRatio * max(width, height) {
    List<double> norm(List<double> v) {
      final n = sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
      return [v[0] / n, v[1] / n, v[2] / n];
    }

    double dot(List<double> a, List<double> b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
    _forward = norm([aimX - x, aimY - y, heightMm]);
    const yAxis = [0.0, 1.0, 0.0];
    final d = dot(yAxis, _forward);
    _down = norm([yAxis[0] - d * _forward[0], yAxis[1] - d * _forward[1], yAxis[2] - d * _forward[2]]);
    // right = down x forward
    _right = [
      _down[1] * _forward[2] - _down[2] * _forward[1],
      _down[2] * _forward[0] - _down[0] * _forward[2],
      _down[0] * _forward[1] - _down[1] * _forward[0],
    ];
  }

  Point2D get nadirMm => Point2D(x, y);

  Point2D project(Point2D boardMm) {
    final v = [boardMm.x - x, boardMm.y - y, heightMm];
    double dot(List<double> a, List<double> b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
    final z = dot(v, _forward);
    return Point2D(width / 2 + focalPx * dot(v, _right) / z, height / 2 + focalPx * dot(v, _down) / z);
  }

  /// Photo pixels of the 4 board corners, in the order the scene expects.
  List<Point2D> boardCorners(BoardGeometry board) => [
        project(const Point2D(0, 0)),
        project(Point2D(board.widthMm, 0)),
        project(Point2D(board.widthMm, board.heightMm)),
        project(Point2D(0, board.heightMm)),
      ];
}
