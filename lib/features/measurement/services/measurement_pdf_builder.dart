import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/measurement_result.dart';
import '../models/piece_type.dart';

class MeasurementPdfBuilder {
  static final _dateFormat = DateFormat('dd/MM/yyyy HH:mm');

  static Future<List<int>> buildBytes(MeasurementResult result) async {
    final doc = pw.Document();

    final rows = <List<String>>[];
    if (result.pieceType.isRectangular) {
      final m = result.rectangleMetrics;
      rows.addAll([
        ['Largura', '${m.widthMm.toStringAsFixed(1)} mm'],
        ['Altura', '${m.heightMm.toStringAsFixed(1)} mm'],
        ['Diagonal 1', '${m.diagonal1Mm.toStringAsFixed(1)} mm'],
        ['Diagonal 2', '${m.diagonal2Mm.toStringAsFixed(1)} mm'],
        [
          'Esquadro',
          m.isSquareWithinTolerance
              ? 'OK (desvio ${m.squareDeviationMm.toStringAsFixed(1)} mm)'
              : 'Fora de esquadro (desvio ${m.squareDeviationMm.toStringAsFixed(1)} mm)',
        ],
      ]);
    } else {
      final m = result.freeformMetrics;
      for (var i = 0; i < m.segmentLengthsMm.length; i++) {
        rows.add(['Segmento ${i + 1}', '${m.segmentLengthsMm[i].toStringAsFixed(1)} mm']);
      }
      rows.add(['Total', '${m.totalLengthMm.toStringAsFixed(1)} mm']);
    }

    doc.addPage(
      pw.Page(
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('MT Vidros — Medição', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 8),
            pw.Text('Peça: ${result.pieceType.label}'),
            pw.Text('Data: ${_dateFormat.format(result.createdAt)}'),
            pw.Text('Origem da medição: ${result.deviceLabel}'),
            pw.SizedBox(height: 16),
            pw.TableHelper.fromTextArray(
              headers: ['Medida', 'Valor'],
              data: rows,
            ),
            pw.SizedBox(height: 16),
            pw.Text(
              'Aviso: esta medição é uma referência digital feita por câmera/AR. '
              'Confirme com trena ou medidor a laser antes de cortar o vidro.',
              style: pw.TextStyle(fontSize: 10, fontStyle: pw.FontStyle.italic),
            ),
          ],
        ),
      ),
    );

    return doc.save();
  }
}
