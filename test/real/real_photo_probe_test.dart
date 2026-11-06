// ignore_for_file: avoid_print
// Manual probe on real photos:
//   MT_REAL_PHOTOS="a.jpg;b.jpg" [MT_SPANS_MM=1808x1316] flutter test test/real
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mt_vidros_app/features/mold_scan/services/camera_pose.dart';
import 'package:mt_vidros_app/features/mold_scan/services/contour_extractor.dart';
import 'package:mt_vidros_app/features/mold_scan/services/mold_outline.dart';
import 'package:mt_vidros_app/features/mold_scan/models/board_geometry.dart';
import 'package:mt_vidros_app/features/mold_scan/services/mold_scan_pipeline.dart';

import '../support/synthetic_scene.dart';

void main() {
  final env = Platform.environment['MT_REAL_PHOTOS'];
  final spans = Platform.environment['MT_SPANS_MM']
      ?.split('x')
      .map(double.parse)
      .toList();
  test(
    'probe',
    () async {
      for (final path in env!.split(';')) {
        final dbg = Platform.environment['MT_PREVIEW_DIR'];
        ContourExtractor.debugMask = dbg == null
            ? null
            : (stage, m, w, h) {
                final im = img.Image(width: w, height: h);
                for (var y = 0; y < h; y++) {
                  for (var x = 0; x < w; x++) {
                    final v = m[y * w + x] != 0 ? 255 : 0;
                    im.setPixelRgb(x, y, v, v, v);
                  }
                }
                File('$dbg/${path.split('/').last}.$stage.png')
                    .writeAsBytesSync(
                      img.encodePng(img.copyResize(im, width: 700)),
                    );
              };
        final r = await MoldScanPipeline.run(
          File(path).readAsBytesSync(),
          board: spans == null
              ? null
              : BoardGeometry.fromSpansMm(spans[0], spans[1]),
        );
        final t = double.tryParse(Platform.environment['MT_THICKNESS'] ?? '');
        final contour = t == null
            ? r.contourMm
            : CameraPoseEstimator.correctForThickness(
                r.contourMm,
                r.cameraPose,
                t,
              );
        final o = MoldOutline(contour);
        final ang = o.straighteningAngle();
        final st = boundingBox(o.rotatedBy(ang).points);
        print(
          '  endireitado ${ang.toStringAsFixed(1)} graus: ${st.width.toStringAsFixed(1)} x ${st.height.toStringAsFixed(1)} mm',
        );
        final b = boundingBox(contour);
        final out = Platform.environment['MT_PREVIEW_DIR'];
        if (out != null) {
          File('$out/${path.split('/').last}.png')
              .writeAsBytesSync(r.previewPng!);
        }
        print('== $path');
        print(
          '  spans ${r.board.spanXMm.toStringAsFixed(1)} x ${r.board.spanYMm.toStringAsFixed(1)}'
          '  medido ${b.width.toStringAsFixed(1)} x ${b.height.toStringAsFixed(1)} mm',
        );
        final pts = contour;
        final y0 = b.minY, y1 = b.minY + b.height;
        for (var f = 0.05; f < 1; f += 0.1) {
          final y = y0 + (y1 - y0) * f + 0.37;
          final xs = <double>[];
          for (var i = 0; i < pts.length; i++) {
            final a = pts[i], c = pts[(i + 1) % pts.length];
            if ((a.y > y) != (c.y > y)) {
              xs.add(a.x + (y - a.y) * (c.x - a.x) / (c.y - a.y));
            }
          }
          if (xs.length >= 2) {
            xs.sort();
            print(
              '  largura a ${(f * 100).round()}%: ${(xs.last - xs.first).toStringAsFixed(1)}',
            );
          }
        }
        final x0 = b.minX, x1 = b.minX + b.width;
        for (var f = 0.1; f < 1; f += 0.2) {
          final x = x0 + (x1 - x0) * f + 0.37;
          final ys = <double>[];
          for (var i = 0; i < pts.length; i++) {
            final a = pts[i], c = pts[(i + 1) % pts.length];
            if ((a.x > x) != (c.x > x)) {
              ys.add(a.y + (x - a.x) * (c.y - a.y) / (c.x - a.x));
            }
          }
          if (ys.length >= 2) {
            ys.sort();
            print(
              '  altura a ${(f * 100).round()}%: ${(ys.last - ys.first).toStringAsFixed(1)}',
            );
          }
        }
        for (final w in r.warnings) {
          print('  - $w');
        }
      }
    },
    skip: env == null ? 'set MT_REAL_PHOTOS' : null,
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
