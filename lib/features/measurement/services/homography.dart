import 'package:vector_math/vector_math_64.dart';

class Point2D {
  final double x;
  final double y;

  const Point2D(this.x, this.y);
}

/// A 2D projective transform (3x3 matrix, row-major: h0..h8) mapping points
/// from a source plane to a destination plane, computed via the Direct
/// Linear Transform (DLT) from exactly 4 point correspondences.
class Homography {
  final Matrix3 _matrix;

  const Homography._(this._matrix);

  factory Homography.fromCorrespondences(List<Point2D> src, List<Point2D> dst) {
    if (src.length != 4 || dst.length != 4) {
      throw ArgumentError('Homografia requer exatamente 4 correspondências de pontos');
    }

    final a = List.generate(8, (_) => List<double>.filled(8, 0));
    final b = List<double>.filled(8, 0);

    for (var i = 0; i < 4; i++) {
      final sx = src[i].x, sy = src[i].y;
      final dx = dst[i].x, dy = dst[i].y;

      final r0 = i * 2;
      a[r0][0] = sx;
      a[r0][1] = sy;
      a[r0][2] = 1;
      a[r0][6] = -sx * dx;
      a[r0][7] = -sy * dx;
      b[r0] = dx;

      final r1 = r0 + 1;
      a[r1][3] = sx;
      a[r1][4] = sy;
      a[r1][5] = 1;
      a[r1][6] = -sx * dy;
      a[r1][7] = -sy * dy;
      b[r1] = dy;
    }

    final h = _solveLinearSystem(a, b);
    // h holds [h0..h7]; h8 is fixed at 1 (standard DLT normalization).
    final matrix = Matrix3.fromList([
      h[0], h[3], h[6],
      h[1], h[4], h[7],
      h[2], h[5], 1.0,
    ]);
    return Homography._(matrix);
  }

  Point2D apply(Point2D p) {
    final v = _matrix.transformed(Vector3(p.x, p.y, 1.0));
    return Point2D(v.x / v.z, v.y / v.z);
  }

  Homography invert() {
    final inv = Matrix3.copy(_matrix)..invert();
    return Homography._(inv);
  }

  static List<double> _solveLinearSystem(List<List<double>> a, List<double> b) {
    final n = b.length;
    for (var col = 0; col < n; col++) {
      var pivotRow = col;
      var maxVal = a[col][col].abs();
      for (var r = col + 1; r < n; r++) {
        if (a[r][col].abs() > maxVal) {
          maxVal = a[r][col].abs();
          pivotRow = r;
        }
      }
      if (maxVal < 1e-12) {
        throw StateError('Sistema singular ao calcular homografia (pontos colineares ou repetidos)');
      }
      if (pivotRow != col) {
        final tmpRow = a[col];
        a[col] = a[pivotRow];
        a[pivotRow] = tmpRow;
        final tmpB = b[col];
        b[col] = b[pivotRow];
        b[pivotRow] = tmpB;
      }
      final pivot = a[col][col];
      for (var r = col + 1; r < n; r++) {
        final factor = a[r][col] / pivot;
        if (factor == 0) continue;
        for (var c = col; c < n; c++) {
          a[r][c] -= factor * a[col][c];
        }
        b[r] -= factor * b[col];
      }
    }

    final x = List<double>.filled(n, 0);
    for (var row = n - 1; row >= 0; row--) {
      var sum = b[row];
      for (var c = row + 1; c < n; c++) {
        sum -= a[row][c] * x[c];
      }
      x[row] = sum / a[row][row];
    }
    return x;
  }
}
