import 'dart:typed_data';

import '../models/board_geometry.dart';
import 'homography.dart';
import 'mold_scan_pipeline.dart';

export 'mold_scan_pipeline.dart' show MoldScanException, MoldScanResult;

class MoldScanService {
  /// Web has no isolates, so the pipeline runs on the UI thread; [onStage]
  /// lets the screen show progress between the heavy steps.
  Future<MoldScanResult> scanContourFromBytes(
    Uint8List bytes, {
    BoardGeometry? board,
    double printedMarkerMm = 180,
    List<Point2D>? manualCenters,
    Future<void> Function(String stage)? onStage,
  }) {
    return MoldScanPipeline.run(
      bytes,
      board: board,
      printedMarkerMm: printedMarkerMm,
      manualCenters: manualCenters,
      onStage: onStage,
    );
  }
}
