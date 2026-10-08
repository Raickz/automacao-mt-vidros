import 'dart:typed_data';

import 'mold_scan_pipeline.dart';

export 'mold_scan_pipeline.dart' show MoldScanException, MoldScanResult;

class MoldScanService {
  /// Web has no isolates, so the pipeline runs on the UI thread; [onStage]
  /// lets the screen show progress between the heavy steps.
  Future<MoldScanResult> scanContourFromBytes(
    Uint8List bytes, {
    Future<void> Function(String stage)? onStage,
  }) {
    return MoldScanPipeline.run(bytes, onStage: onStage);
  }
}
