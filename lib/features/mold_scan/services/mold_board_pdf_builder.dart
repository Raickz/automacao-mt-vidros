import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:qr/qr.dart';

import '../models/board_corner.dart';
import '../models/mold_board_spec.dart';

/// Builds a printable PDF with the 4 corner markers, each split into a 2x2
/// grid of A4 pages (the printer available only supports A4, and a single
/// 260mm marker doesn't fit on one A4 sheet). Each quadrant is drawn by
/// hand from the QR code's own module matrix (via package:qr) instead of
/// the usual BarcodeWidget, since that widget has no way to render only a
/// cropped portion of a barcode split across pages.
class MoldBoardPdfBuilder {
  static Future<List<int>> buildBytes() async {
    final doc = pw.Document();
    final inset = MoldBoardSpec.markerMarginMm + MoldBoardSpec.markerSizeMm / 2;

    for (final corner in BoardCorner.values) {
      final qrCode = QrCode.fromData(
        data: corner.payload,
        errorCorrectLevel: QrErrorCorrectLevel.H,
      );
      final qrImage = QrImage(qrCode);
      final moduleCount = qrImage.moduleCount;
      final moduleSizeMm = MoldBoardSpec.markerSizeMm / moduleCount;

      final rowSplit = (moduleCount / 2).ceil();
      final colSplit = (moduleCount / 2).ceil();
      final quadrants = [
        (rowStart: 0, rowEnd: rowSplit, colStart: 0, colEnd: colSplit, label: 'superior-esquerda'),
        (rowStart: 0, rowEnd: rowSplit, colStart: colSplit, colEnd: moduleCount, label: 'superior-direita'),
        (rowStart: rowSplit, rowEnd: moduleCount, colStart: 0, colEnd: colSplit, label: 'inferior-esquerda'),
        (
          rowStart: rowSplit,
          rowEnd: moduleCount,
          colStart: colSplit,
          colEnd: moduleCount,
          label: 'inferior-direita',
        ),
      ];

      for (var i = 0; i < quadrants.length; i++) {
        final q = quadrants[i];
        final widthMm = (q.colEnd - q.colStart) * moduleSizeMm;
        final heightMm = (q.rowEnd - q.rowStart) * moduleSizeMm;
        final widthPt = widthMm * PdfPageFormat.mm;
        final heightPt = heightMm * PdfPageFormat.mm;
        final moduleSizePt = moduleSizeMm * PdfPageFormat.mm;

        doc.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: pw.EdgeInsets.all(10 * PdfPageFormat.mm),
            build: (context) => pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'MT Vidros - Marcador ${_cornerLabel(corner)} - Parte ${i + 1}/4 (${q.label})',
                  style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  'IMPORTANTE: imprima em tamanho real (100%), nunca "ajustar a pagina". Recorte '
                  'exatamente na borda do quadrado abaixo e cole as 4 partes desta secao juntas, '
                  'sem sobrepor nem deixar vao, formando um marcador de '
                  '${MoldBoardSpec.markerSizeMm.toStringAsFixed(0)}mm x '
                  '${MoldBoardSpec.markerSizeMm.toStringAsFixed(0)}mm.',
                  style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
                ),
                if (i == 0) ...[
                  pw.SizedBox(height: 4),
                  pw.Text(
                    'Posicao no quadro (${MoldBoardSpec.boardWidthMm.toStringAsFixed(0)}x'
                    '${MoldBoardSpec.boardHeightMm.toStringAsFixed(0)}mm): depois de montado, cole o '
                    'CENTRO deste marcador a ${inset.toStringAsFixed(0)}mm ${_horizontalEdge(corner)} e '
                    '${inset.toStringAsFixed(0)}mm ${_verticalEdge(corner)}.',
                    style: const pw.TextStyle(fontSize: 9),
                  ),
                ],
                pw.SizedBox(height: 12),
                pw.Container(
                  width: widthPt,
                  height: heightPt,
                  decoration: const pw.BoxDecoration(
                    color: PdfColors.white,
                    border: pw.Border.fromBorderSide(pw.BorderSide(width: 0.75)),
                  ),
                  child: pw.CustomPaint(
                    size: PdfPoint(widthPt, heightPt),
                    painter: (canvas, size) {
                      canvas.setFillColor(PdfColors.black);
                      for (var row = q.rowStart; row < q.rowEnd; row++) {
                        for (var col = q.colStart; col < q.colEnd; col++) {
                          if (!qrImage.isDark(row, col)) continue;
                          final localCol = col - q.colStart;
                          final localRow = row - q.rowStart;
                          // PDF canvases are Y-up (origin at the bottom of
                          // this widget's own box), while QR row 0 is the
                          // visual top row — flip the row to compensate, or
                          // the printed code would be upside down and
                          // wouldn't scan.
                          final x = localCol * moduleSizePt;
                          final y = size.y - (localRow + 1) * moduleSizePt;
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
                  '${widthMm.toStringAsFixed(0)}mm de lado.',
                  style: const pw.TextStyle(fontSize: 8),
                ),
              ],
            ),
          ),
        );
      }
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
