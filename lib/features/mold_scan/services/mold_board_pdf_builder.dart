import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:qr/qr.dart';

import '../models/board_corner.dart';
import '../models/mold_board_spec.dart';

/// Builds a printable PDF with the 4 corner markers, one per A4 page, no
/// cutting or taping needed — [MoldBoardSpec.markerSizeMm] is sized to fit
/// entirely within a single A4 sheet's printable area. Each marker is drawn
/// by hand from the QR code's own module matrix (via package:qr) instead of
/// the usual BarcodeWidget, so the printed size matches
/// [MoldBoardSpec.markerSizeMm] exactly regardless of the QR version chosen.
class MoldBoardPdfBuilder {
  static Future<List<int>> buildBytes() async {
    final doc = pw.Document();
    final inset = MoldBoardSpec.markerMarginMm + MoldBoardSpec.markerSizeMm / 2;
    final sizeMm = MoldBoardSpec.markerSizeMm;
    final sizePt = sizeMm * PdfPageFormat.mm;

    for (final corner in BoardCorner.values) {
      final qrCode = QrCode.fromData(
        data: corner.payload,
        errorCorrectLevel: QrErrorCorrectLevel.H,
      );
      final qrImage = QrImage(qrCode);
      final moduleCount = qrImage.moduleCount;
      final moduleSizePt = sizePt / moduleCount;

      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.all(10 * PdfPageFormat.mm),
          build: (context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'MT Vidros - Marcador ${_cornerLabel(corner)}',
                style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                'IMPORTANTE: imprima em tamanho real (100%), nunca "ajustar a pagina". '
                'O marcador deve medir exatamente ${sizeMm.toStringAsFixed(0)}mm x '
                '${sizeMm.toStringAsFixed(0)}mm depois de impresso.',
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
              pw.Container(
                width: sizePt,
                height: sizePt,
                decoration: const pw.BoxDecoration(
                  color: PdfColors.white,
                  border: pw.Border.fromBorderSide(pw.BorderSide(width: 0.75)),
                ),
                child: pw.CustomPaint(
                  size: PdfPoint(sizePt, sizePt),
                  painter: (canvas, size) {
                    canvas.setFillColor(PdfColors.black);
                    for (var row = 0; row < moduleCount; row++) {
                      for (var col = 0; col < moduleCount; col++) {
                        if (!qrImage.isDark(row, col)) continue;
                        // PDF canvases are Y-up (origin at the bottom of
                        // this widget's own box), while QR row 0 is the
                        // visual top row — flip the row to compensate, or
                        // the printed code would be upside down and
                        // wouldn't scan.
                        final x = col * moduleSizePt;
                        final y = size.y - (row + 1) * moduleSizePt;
                        canvas.drawRect(x, y, moduleSizePt, moduleSizePt);
                      }
                    }
                    canvas.fillPath();
                  },
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Text(
                'Confira com uma regua: este quadrado deve medir exatamente '
                '${sizeMm.toStringAsFixed(0)}mm de lado.',
                style: const pw.TextStyle(fontSize: 8),
              ),
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
}
