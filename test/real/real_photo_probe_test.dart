// ignore_for_file: avoid_print
// Manual probe on real photos:
//   MT_REAL_PHOTOS="a.jpg;b.jpg" [MT_SPANS_MM=1808x1316] flutter test test/real
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mt_vidros_app/features/mold_scan/services/contour_extractor.dart';
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
            : (m, w, h) {
                final im = img.Image(width: w, height: h);
                for (var y = 0; y < h; y++) {
                  for (var x = 0; x < w; x++) {
                    final v = m[y * w + x] != 0 ? 255 : 0;
                    im.setPixelRgb(x, y, v, v, v);
                  }
                }
                File('$dbg/${path.split('/').last}.mask.png').writeAsBytesSync(
                  img.encodePng(img.copyResize(im, width: 700)),
                );
              };
        final r = await MoldScanPipeline.run(
          File(path).readAsBytesSync(),
          board: spans == null
              ? null
              : BoardGeometry.fromSpansMm(spans[0], spans[1]),
        );
        final b = boundingBox(r.contourMm);
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
        for (final w in r.warnings) {
          print('  - $w');
        }
      }
    },
    skip: env == null ? 'set MT_REAL_PHOTOS' : null,
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
