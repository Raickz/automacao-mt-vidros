import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/board_corner.dart';
import '../models/mold_board_spec.dart';

/// Builds a printable PDF with the 4 corner markers, one per A3 page — at
/// this board size (2.5m x 1.5m) the markers are too large to combine with
/// the board background on a single sheet like the earlier small-board
/// design, and the board itself is a physical structure built at the store,
/// not something printed.
class MoldBoardPdfBuilder {
  static Future<List<int>> buildBytes() async {
    final doc = pw.Document();
    final markerSizePt = MoldBoardSpec.markerSizeMm * PdfPageFormat.mm;
    final inset = MoldBoardSpec.markerMarginMm + MoldBoardSpec.markerSizeMm / 2;

    for (final corner in BoardCorner.values) {
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a3,
          margin: pw.EdgeInsets.all(10 * PdfPageFormat.mm),
          build: (context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'MT Vidros - Marcador do quadro de referencia (${_cornerLabel(corner)})',
                style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                'IMPORTANTE: imprima em tamanho real (100%), nunca "ajustar a pagina". '
                'O marcador deve medir exatamente ${MoldBoardSpec.markerSizeMm.toStringAsFixed(0)}mm '
                'de lado depois de impresso - confira com a regua de calibracao abaixo antes de fixar no quadro.',
                style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                'Posicao no quadro (${MoldBoardSpec.boardWidthMm.toStringAsFixed(0)}x'
                '${MoldBoardSpec.boardHeightMm.toStringAsFixed(0)}mm): cole o CENTRO deste '
                'marcador a ${inset.toStringAsFixed(0)}mm ${_horizontalEdge(corner)} e '
                '${inset.toStringAsFixed(0)}mm ${_verticalEdge(corner)}.',
                style: const pw.TextStyle(fontSize: 9),
              ),
              pw.SizedBox(height: 12),
              pw.Center(
                child: pw.Container(
                  width: markerSizePt,
                  height: markerSizePt,
                  color: PdfColors.white,
                  padding: const pw.EdgeInsets.all(6),
                  child: pw.BarcodeWidget(
                    data: corner.payload,
                    barcode: pw.Barcode.qrCode(),
                    drawText: false,
                  ),
                ),
              ),
              pw.SizedBox(height: 12),
              _calibrationRuler(),
            ],
          ),
        ),
      );
    }

    return doc.save();
  }

  static String _cornerLabel(BoardCorner corner) {
    switch (corner) {
      case BoardCorner.topLeft:
        return 'superior esquerdo';
      case BoardCorner.topRight:
        return 'superior direito';
      case BoardCorner.bottomRight:
        return 'inferior direito';
      case BoardCorner.bottomLeft:
        return 'inferior esquerdo';
    }
  }

  static String _horizontalEdge(BoardCorner corner) {
    final fromLeft = corner == BoardCorner.topLeft || corner == BoardCorner.bottomLeft;
    return fromLeft ? 'da borda esquerda' : 'da borda direita';
  }

  static String _verticalEdge(BoardCorner corner) {
    final fromTop = corner == BoardCorner.topLeft || corner == BoardCorner.topRight;
    return fromTop ? 'da borda superior' : 'da borda inferior';
  }

  static pw.Widget _calibrationRuler() {
    const rulerLengthMm = 100.0;
    final rulerLengthPt = rulerLengthMm * PdfPageFormat.mm;
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Regua de calibracao - deve medir exatamente 100mm com uma regua comum:',
          style: const pw.TextStyle(fontSize: 9),
        ),
        pw.SizedBox(height: 4),
        pw.SizedBox(
          width: rulerLengthPt,
          height: 12,
          child: pw.CustomPaint(
            size: PdfPoint(rulerLengthPt, 12),
            painter: (canvas, size) {
              canvas
                ..setLineWidth(1)
                ..drawLine(0, 0, size.x, 0)
                ..strokePath();
              for (var mm = 0; mm <= 100; mm += 10) {
                final x = mm * PdfPageFormat.mm;
                final tickHeight = mm % 50 == 0 ? 10.0 : 6.0;
                canvas
                  ..drawLine(x, 0, x, tickHeight)
                  ..strokePath();
              }
            },
          ),
        ),
      ],
    );
  }
}
