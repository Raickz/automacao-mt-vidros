import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';

import '../models/detected_marker.dart';
import 'homography.dart';

/// Marker payload format: "MTV1:" followed by the size in mm, e.g. "MTV1:100".
class QrMarkerDetector {
  static const _payloadPrefix = 'MTV1:';

  Future<List<DetectedMarker>> detectFromFile(String path) async {
    final scanner = BarcodeScanner(formats: [BarcodeFormat.qrCode]);
    try {
      final inputImage = InputImage.fromFilePath(path);
      final barcodes = await scanner.processImage(inputImage);

      final markers = <DetectedMarker>[];
      for (final barcode in barcodes) {
        final raw = barcode.rawValue;
        if (raw == null || !raw.startsWith(_payloadPrefix)) continue;
        final sizeMm = double.tryParse(raw.substring(_payloadPrefix.length));
        if (sizeMm == null || barcode.cornerPoints.length != 4) continue;

        markers.add(DetectedMarker(
          payload: raw,
          sizeMm: sizeMm,
          cornerPoints: barcode.cornerPoints
              .map((p) => Point2D(p.x.toDouble(), p.y.toDouble()))
              .toList(),
          boundingArea: barcode.boundingBox.width * barcode.boundingBox.height,
        ));
      }
      return markers;
    } finally {
      await scanner.close();
    }
  }
}
