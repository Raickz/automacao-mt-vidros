import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;

import 'mold_scan_pipeline.dart';

export 'mold_scan_pipeline.dart' show MoldScanException, MoldScanResult;

class _Outcome {
  final MoldScanResult? result;
  final String? error;

  const _Outcome({this.result, this.error});
}

Future<_Outcome> _runInIsolate(Uint8List bytes) async {
  try {
    return _Outcome(result: await MoldScanPipeline.run(bytes));
  } on MoldScanException catch (e) {
    return _Outcome(error: e.message);
  }
}

class MoldScanService {
  /// Runs the pipeline in a background isolate so the camera screen's
  /// spinner keeps animating while a multi-megapixel photo is processed.
  Future<MoldScanResult> scanContourFromPhoto(String photoPath) async {
    final bytes = await File(photoPath).readAsBytes();
    final outcome = await compute(_runInIsolate, bytes);
    final error = outcome.error;
    if (error != null) throw MoldScanException(error);
    return outcome.result!;
  }
}
