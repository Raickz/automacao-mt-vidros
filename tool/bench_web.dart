// Browser benchmark of the scan pipeline on the real fixture photos.
// Build:  flutter build web -t tool/bench_web.dart [--wasm] -o build/bench
// Serve build/bench with test/real/fixtures copied to ./fixtures, open it and
// read the console (or document.title).
import 'dart:js_interop';

import 'package:mt_vidros_app/features/mold_scan/models/board_geometry.dart';
import 'package:mt_vidros_app/features/mold_scan/services/mold_scan_service_web.dart';
import 'package:web/web.dart' as web;

Future<void> main() async {
  final out = StringBuffer();
  void log(String s) {
    out.writeln(s);
    web.console.log(s.toJS);
  }

  for (final (file, sx, sy) in [
    ('piso_61x50.jpg', 1820.0, 1320.0),
    ('papelao_70x25.jpg', 1794.0, 1328.0),
  ]) {
    final resp = await web.window.fetch('fixtures/$file'.toJS).toDart;
    final bytes = (await resp.arrayBuffer().toDart).toDart.asUint8List();
    final sw = Stopwatch()..start();
    var last = 0;
    final parts = <String>[];
    final r = await MoldScanService().scanContourFromBytes(
      bytes,
      board: BoardGeometry.fromSpansMm(sx, sy),
      onStage: (s) async {
        parts.add('${sw.elapsedMilliseconds - last}');
        last = sw.elapsedMilliseconds;
        parts.add(s);
      },
    );
    sw.stop();
    parts.add('${sw.elapsedMilliseconds - last}');
    log(
      'BENCH $file total=${sw.elapsedMilliseconds}ms points=${r.contourMm.length} | ${parts.join(' | ')}',
    );
  }
  web.document.title = 'DONE ${out.toString().replaceAll('\n', ' ;; ')}';
}
