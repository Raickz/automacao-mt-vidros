import 'dart:js_interop';
import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:web/web.dart' as web;

import '../models/board_geometry.dart';
import 'homography.dart';
import 'mold_scan_pipeline.dart';

export 'mold_scan_pipeline.dart' show MoldScanException, MoldScanResult;

class MoldScanService {
  /// Web has no isolates, so the pipeline runs on the UI thread; [onStage]
  /// lets the screen show progress between the heavy steps.
  ///
  /// The photo is decoded by the browser itself (native JPEG decoding, with
  /// the EXIF rotation applied), which takes a fraction of a second where
  /// the pure-Dart decoder took 3 s for a 3200 x 2400 photo. If the browser
  /// can't, the Dart decoder is used.
  Future<MoldScanResult> scanContourFromBytes(
    Uint8List bytes, {
    BoardGeometry? board,
    double printedMarkerMm = 180,
    List<Point2D>? manualCenters,
    Future<void> Function(String stage)? onStage,
  }) async {
    // Header check first (file type, declared size): the browser must never
    // be handed a decompression bomb.
    MoldScanPipeline.checkHeader(bytes);
    if (onStage != null) await onStage('Lendo a foto...');
    final photo = await _decodeNative(bytes, MoldScanPipeline.maxPhotoSide);
    if (photo == null) {
      return MoldScanPipeline.run(
        bytes,
        board: board,
        printedMarkerMm: printedMarkerMm,
        manualCenters: manualCenters,
        onStage: onStage,
      );
    }
    return MoldScanPipeline.runOnPhoto(
      photo,
      board: board,
      printedMarkerMm: printedMarkerMm,
      manualCenters: manualCenters,
      onStage: onStage,
    );
  }

  /// RGB photo decoded and, if larger, scaled down to [maxSide] by the
  /// browser; null when the browser can't decode it.
  static Future<img.Image?> _decodeNative(Uint8List bytes, int maxSide) async {
    try {
      final blob = web.Blob(<JSAny>[bytes.toJS].toJS);
      final bitmap = await web.window
          .createImageBitmap(
            blob,
            web.ImageBitmapOptions(imageOrientation: 'from-image'),
          )
          .toDart;
      final k = min(1.0, maxSide / max(bitmap.width, bitmap.height));
      final w = max(1, (bitmap.width * k).round());
      final h = max(1, (bitmap.height * k).round());
      final canvas = web.HTMLCanvasElement()
        ..width = w
        ..height = h;
      final ctx = canvas.getContext('2d') as web.CanvasRenderingContext2D;
      ctx.imageSmoothingEnabled = true;
      ctx.imageSmoothingQuality = 'high';
      ctx.drawImage(bitmap, 0, 0, w, h);
      bitmap.close();
      // A plain Uint8List view: indexing the Uint8ClampedList itself goes
      // through dart2js's generic dispatch and made this loop take 3 s.
      final clamped = ctx.getImageData(0, 0, w, h).data.toDart;
      final rgba = Uint8List.view(
        clamped.buffer,
        clamped.offsetInBytes,
        clamped.lengthInBytes,
      );
      final rgb = _rgbaToRgb(rgba, w * h);
      // Free the canvas memory now (phones run out with several photos).
      canvas
        ..width = 1
        ..height = 1;
      return img.Image.fromBytes(
        width: w,
        height: h,
        bytes: rgb.buffer,
        numChannels: 3,
      );
    } catch (_) {
      return null;
    }
  }

  /// Kept out of the async function on purpose: dart2js turns an async body
  /// into a state machine whose locals live in a closure, and this 8-million
  /// step loop took 3 s there instead of a few tens of milliseconds.
  static Uint8List _rgbaToRgb(Uint8List rgba, int pixels) {
    final rgb = Uint8List(pixels * 3);
    for (var i = 0, o = 0; o < rgb.length; i += 4, o += 3) {
      rgb[o] = rgba[i];
      rgb[o + 1] = rgba[i + 1];
      rgb[o + 2] = rgba[i + 2];
    }
    return rgb;
  }
}
