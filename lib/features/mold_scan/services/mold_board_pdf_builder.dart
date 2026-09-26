import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/board_corner.dart';
import '../models/mold_board_spec.dart';

class MoldBoardPdfBuilder {
  static Future<List<int>> buildBytes() async {
    final doc = pw.Document();

    final boardColor = PdfColor.fromInt(
      0xFF000000 |
          (MoldBoardSpec.backgroundR << 16) |
          (MoldBoardSpec.backgroundG << 8) |
          MoldBoardSpec.backgroundB,
    );

    final boardWidthPt = MoldBoardSpec.boardWidthMm * PdfPageFormat.mm;
    final boardHeightPt = MoldBoardSpec.boardHeightMm * PdfPageFormat.mm;
    final markerSizePt = MoldBoardSpec.markerSizeMm * PdfPageFormat.mm;
    final marginPt = MoldBoardSpec.markerMarginMm * PdfPageFormat.mm;

    pw.Widget marker(BoardCorner corner) => pw.Container(
          width: markerSizePt,
          height: markerSizePt,
          color: PdfColors.white,
          padding: const pw.EdgeInsets.all(2),
          child: pw.BarcodeWidget(data: corner.payload, barcode: pw.Barcode.qrCode(), drawText: false),
        );

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: pw.EdgeInsets.all(8 * PdfPageFormat.mm),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'MT Vidros - Quadro de referencia para digitalizacao de molde',
              style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 3),
            pw.Text(
              'IMPORTANTE: imprima em tamanho real (100%), nunca "ajustar a pagina". '
              'Coloque o molde sobre a area azul, dentro dos 4 marcadores, e tire uma foto '
              'de cima com boa iluminacao, sem sombras fortes.',
              style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 8),
            pw.Center(
              child: pw.Container(
                width: boardWidthPt,
                height: boardHeightPt,
                color: boardColor,
                child: pw.Stack(
                  children: [
                    pw.Positioned(left: marginPt, top: marginPt, child: marker(BoardCorner.topLeft)),
                    pw.Positioned(right: marginPt, top: marginPt, child: marker(BoardCorner.topRight)),
                    pw.Positioned(right: marginPt, bottom: marginPt, child: marker(BoardCorner.bottomRight)),
                    pw.Positioned(left: marginPt, bottom: marginPt, child: marker(BoardCorner.bottomLeft)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );

    return doc.save();
  }
}
