import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import '../models/measurement_result.dart';
import 'measurement_pdf_builder.dart';

class MeasurementExportService {
  Future<void> shareResult(MeasurementResult result) async {
    final bytes = await MeasurementPdfBuilder.buildBytes(result);
    final blob = web.Blob(
      <JSAny>[Uint8List.fromList(bytes).toJS].toJS,
      web.BlobPropertyBag(type: 'application/pdf'),
    );
    final url = web.URL.createObjectURL(blob);
    final anchor = web.HTMLAnchorElement()
      ..href = url
      ..download = 'medicao_${result.id}.pdf';
    web.document.body?.append(anchor);
    anchor.click();
    anchor.remove();
    web.URL.revokeObjectURL(url);
  }
}
