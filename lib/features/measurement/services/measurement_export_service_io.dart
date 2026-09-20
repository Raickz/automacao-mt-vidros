import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/measurement_result.dart';
import '../models/piece_type.dart';
import 'measurement_pdf_builder.dart';

class MeasurementExportService {
  Future<File> buildPdf(MeasurementResult result) async {
    final bytes = await MeasurementPdfBuilder.buildBytes(result);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/medicao_${result.id}.pdf');
    await file.writeAsBytes(bytes);
    return file;
  }

  Future<void> shareResult(MeasurementResult result) async {
    final file = await buildPdf(result);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        text: 'Medição MT Vidros — ${result.pieceType.label}',
      ),
    );
  }
}
