import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:qr/qr.dart';

import '../models/board_corner.dart';
import '../models/mold_board_spec.dart';

/// Builds a printable PDF with the 4 corner markers, one per A4 page.
///
/// Each marker is a [MoldBoardSpec.markerSizeMm] QR with
/// [MoldBoardSpec.markerQuietZoneMm] of white paper around it, framed by a
/// dashed cut line. The sheet MUST be cut along that line: leftover white
/// paper beside the marker would otherwise show up in photos as a big
/// bright "object" next to the mold. The QR is drawn by hand from the code's
/// own module matrix (via package:qr) so its printed size is exact.
class MoldBoardPdfBuilder {
  static Future<List<int>> buildBytes() async {
    final doc = pw.Document();
    final sizeMm = MoldBoardSpec.markerSizeMm;
    final quietMm = MoldBoardSpec.markerQuietZoneMm;
    final sizePt = sizeMm * PdfPageFormat.mm;
    final cutPt = (sizeMm + 2 * quietMm) * PdfPageFormat.mm;
    final paperEdgeMm = MoldBoardSpec.markerMarginMm - quietMm;

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
          margin: pw.EdgeInsets.all(4 * PdfPageFormat.mm),
          build: (context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'MT Vidros - Marcador ${_cornerLabel(corner)}',
                style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 3),
              pw.Text(
                'Imprima em tamanho real (100%), nunca "ajustar a pagina". Recorte exatamente na '
                'linha tracejada, sem deixar sobra de papel (a margem branca dentro da linha faz '
                'parte do marcador - nao recorte dentro dela).',
                style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 3),
              pw.Text(
                'Posicao no quadro (${MoldBoardSpec.boardWidthMm.toStringAsFixed(0)}x'
                '${MoldBoardSpec.boardHeightMm.toStringAsFixed(0)}mm): cole o papel recortado com a '
                'borda do papel a ${paperEdgeMm.toStringAsFixed(0)}mm ${_horizontalEdge(corner)} e '
                'a ${paperEdgeMm.toStringAsFixed(0)}mm ${_verticalEdge(corner)}.',
                style: const pw.TextStyle(fontSize: 9),
              ),
              pw.SizedBox(height: 8),
              pw.Container(
                width: cutPt,
                height: cutPt,
                alignment: pw.Alignment.center,
                decoration: pw.BoxDecoration(
                  color: PdfColors.white,
                  border: pw.Border.all(color: PdfColors.grey700, width: 0.6, style: pw.BorderStyle.dashed),
                ),
                child: pw.SizedBox(
                  width: sizePt,
                  height: sizePt,
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
              ),
              pw.SizedBox(height: 5),
              pw.Text(
                'Confira com uma regua: o quadrado preto deve medir exatamente '
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
    return fromLeft ? 'da borda esquerda do quadro' : 'da borda direita do quadro';
  }

  static String _verticalEdge(BoardCorner corner) {
    final fromTop = corner == BoardCorner.topLeft || corner == BoardCorner.topRight;
    return fromTop ? 'da borda superior do quadro' : 'da borda inferior do quadro';
  }
}
