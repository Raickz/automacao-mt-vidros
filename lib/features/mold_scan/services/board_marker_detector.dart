import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';

import '../../measurement/services/homography.dart';
import '../models/board_corner.dart';

class BoardMarkerDetector {
  Future<Map<BoardCorner, Point2D>> detectFromFile(String path) async {
    final scanner = BarcodeScanner(formats: [BarcodeFormat.qrCode]);
    try {
      final inputImage = InputImage.fromFilePath(path);
      final barcodes = await scanner.processImage(inputImage);

      final found = <BoardCorner, Point2D>{};
      for (final barcode in barcodes) {
        final raw = barcode.rawValue;
        if (raw == null) continue;
        final corner = BoardCornerX.fromPayload(raw);
        if (corner == null || barcode.cornerPoints.length != 4) continue;

        final sumX = barcode.cornerPoints.fold<double>(0, (s, p) => s + p.x);
        final sumY = barcode.cornerPoints.fold<double>(0, (s, p) => s + p.y);
        found[corner] = Point2D(sumX / 4, sumY / 4);
      }
      return found;
    } finally {
      await scanner.close();
    }
  }
}
