import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:mt_vidros_app/features/measurement/services/homography.dart';
import 'package:mt_vidros_app/features/mold_scan/models/board_corner.dart';
import 'package:mt_vidros_app/features/mold_scan/models/mold_board_spec.dart';
import 'package:qr/qr.dart';

enum MarkerPaper { cutWithQuietZone, uncutA4 }

class SceneConfig {
  final List<Point2D> moldPolygonMm;
  final (int, int, int) moldColor;
  final (int, int, int) boardColor;
  final (int, int, int) wallColor;
  final MarkerPaper paper;
  final double lightGradient;
  final double noiseSigma;
  final bool shadow;
  final List<(Point2D, double)> specks;
  final Map<BoardCorner, String> payloadOverride;
  final double blurRadius;

  const SceneConfig({
    required this.moldPolygonMm,
    this.moldColor = (170, 125, 80),
    this.boardColor = (20, 90, 200),
    this.wallColor = (205, 205, 195),
    this.paper = MarkerPaper.cutWithQuietZone,
    this.lightGradient = 0,
    this.noiseSigma = 0,
    this.shadow = false,
    this.specks = const [],
    this.payloadOverride = const {},
    this.blurRadius = 1,
  });
}

/// Renders a fake camera photo of the reference board (2.5m x 1.5m, 4 QR
/// markers, a mold on it) through a real perspective transform, so the whole
/// pipeline (QR detection -> homography -> rectification -> contour) can be
/// exercised end to end against a known ground truth.
class SyntheticScene {
  final int width;
  final int height;
  final List<Point2D> boardPixelCorners;

  late final Homography _mmToPx;
  late final Homography pixelToMm;
  Float64List? _mmX;
  Float64List? _mmY;

  SyntheticScene({required this.width, required this.height, required this.boardPixelCorners}) {
    final mm = [
      const Point2D(0, 0),
      const Point2D(MoldBoardSpec.boardWidthMm, 0),
      const Point2D(MoldBoardSpec.boardWidthMm, MoldBoardSpec.boardHeightMm),
      const Point2D(0, MoldBoardSpec.boardHeightMm),
    ];
    _mmToPx = Homography.fromCorrespondences(mm, boardPixelCorners);
    pixelToMm = _mmToPx.invert();
  }

  void _precompute() {
    if (_mmX != null) return;
    final xs = Float64List(width * height);
    final ys = Float64List(width * height);
    var i = 0;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final p = pixelToMm.apply(Point2D(x + 0.5, y + 0.5));
        xs[i] = p.x;
        ys[i] = p.y;
        i++;
      }
    }
    _mmX = xs;
    _mmY = ys;
  }

  static bool _inPolygon(double x, double y, List<Point2D> poly) {
    var inside = false;
    for (var i = 0, j = poly.length - 1; i < poly.length; j = i++) {
      final a = poly[i], b = poly[j];
      if ((a.y > y) != (b.y > y) && x < (b.x - a.x) * (y - a.y) / (b.y - a.y) + a.x) {
        inside = !inside;
      }
    }
    return inside;
  }

  Uint8List renderJpg(SceneConfig cfg, {int quality = 90}) {
    return img.encodeJpg(render(cfg), quality: quality);
  }

  img.Image render(SceneConfig cfg) {
    _precompute();
    final mmX = _mmX!, mmY = _mmY!;
    final out = img.Image(width: width, height: height, numChannels: 3);

    const boardW = MoldBoardSpec.boardWidthMm;
    const boardH = MoldBoardSpec.boardHeightMm;
    const size = MoldBoardSpec.markerSizeMm;
    const quiet = 10.0;

    final qrs = <BoardCorner, QrImage>{};
    for (final c in BoardCorner.values) {
      final payload = cfg.payloadOverride[c] ?? c.payload;
      qrs[c] = QrImage(QrCode.fromData(data: payload, errorCorrectLevel: QrErrorCorrectLevel.H));
    }

    final poly = cfg.moldPolygonMm;
    var minX = double.infinity, minY = double.infinity, maxX = -double.infinity, maxY = -double.infinity;
    for (final p in poly) {
      minX = min(minX, p.x);
      minY = min(minY, p.y);
      maxX = max(maxX, p.x);
      maxY = max(maxY, p.y);
    }
    final shadowPoly = [for (final p in poly) Point2D(p.x + 18, p.y + 22)];

    final rng = Random(7);
    var i = 0;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++, i++) {
        final mx = mmX[i], my = mmY[i];
        var r = cfg.wallColor.$1.toDouble(), g = cfg.wallColor.$2.toDouble(), b = cfg.wallColor.$3.toDouble();

        if (mx >= 0 && mx <= boardW && my >= 0 && my <= boardH) {
          r = cfg.boardColor.$1.toDouble();
          g = cfg.boardColor.$2.toDouble();
          b = cfg.boardColor.$3.toDouble();

          if (cfg.shadow && mx >= minX && mx <= maxX + 30 && my >= minY && my <= maxY + 30) {
            if (_inPolygon(mx, my, shadowPoly)) {
              r *= 0.55;
              g *= 0.55;
              b *= 0.55;
            }
          }

          for (final c in BoardCorner.values) {
            final center = c.knownBoardPositionMm;
            final lx = mx - (center.x - size / 2);
            final ly = my - (center.y - size / 2);

            bool inPaper;
            if (cfg.paper == MarkerPaper.cutWithQuietZone) {
              inPaper = lx >= -quiet && lx <= size + quiet && ly >= -quiet && ly <= size + quiet;
            } else {
              inPaper = lx >= -10 && lx <= size + 20 && ly >= -57 && ly <= size + 50;
            }
            if (!inPaper) continue;

            r = g = b = 245;
            if (lx >= 0 && lx < size && ly >= 0 && ly < size) {
              final qr = qrs[c]!;
              final n = qr.moduleCount;
              final col = (lx / size * n).floor().clamp(0, n - 1);
              final row = (ly / size * n).floor().clamp(0, n - 1);
              if (qr.isDark(row, col)) r = g = b = 15;
            }
          }

          if (mx >= minX && mx <= maxX && my >= minY && my <= maxY && _inPolygon(mx, my, poly)) {
            r = cfg.moldColor.$1.toDouble();
            g = cfg.moldColor.$2.toDouble();
            b = cfg.moldColor.$3.toDouble();
          }

          for (final s in cfg.specks) {
            final dx = mx - s.$1.x, dy = my - s.$1.y;
            if (dx * dx + dy * dy <= s.$2 * s.$2) {
              r = g = b = 10;
            }
          }
        }

        final light = 1 + cfg.lightGradient * (mx / boardW - 0.5);
        r *= light;
        g *= light;
        b *= light;

        out.setPixelRgb(x, y, r.clamp(0, 255).round(), g.clamp(0, 255).round(), b.clamp(0, 255).round());
      }
    }

    var result = out;
    if (cfg.blurRadius > 0) {
      result = img.gaussianBlur(result, radius: cfg.blurRadius.round());
    }

    if (cfg.noiseSigma > 0) {
      for (var y = 0; y < result.height; y++) {
        for (var x = 0; x < result.width; x++) {
          final p = result.getPixel(x, y);
          double n() => (rng.nextDouble() + rng.nextDouble() + rng.nextDouble() - 1.5) * 2 * cfg.noiseSigma;
          result.setPixelRgb(
            x,
            y,
            (p.r + n()).clamp(0, 255).round(),
            (p.g + n()).clamp(0, 255).round(),
            (p.b + n()).clamp(0, 255).round(),
          );
        }
      }
    }
    return result;
  }
}

({double width, double height, double minX, double minY}) boundingBox(List<Point2D> pts) {
  final xs = pts.map((p) => p.x), ys = pts.map((p) => p.y);
  final minX = xs.reduce(min), maxX = xs.reduce(max);
  final minY = ys.reduce(min), maxY = ys.reduce(max);
  return (width: maxX - minX, height: maxY - minY, minX: minX, minY: minY);
}
