import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class MarkerKitPdfBuilder {
  static Future<List<int>> buildBytes({required double sizeMm}) async {
    final doc = pw.Document();
    final qrData = 'MTV1:${sizeMm.toStringAsFixed(0)}';
    final markerSize = sizeMm * PdfPageFormat.mm;

    pw.Widget marker() => pw.Column(
          mainAxisSize: pw.MainAxisSize.min,
          children: [
            pw.Container(
              width: markerSize,
              height: markerSize,
              padding: const pw.EdgeInsets.all(4),
              decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.5)),
              child: pw.BarcodeWidget(
                data: qrData,
                barcode: pw.Barcode.qrCode(),
                drawText: false,
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              '${sizeMm.toStringAsFixed(0)}mm — alinhe o CENTRO deste marcador com o canto do vão',
              style: const pw.TextStyle(fontSize: 8),
              textAlign: pw.TextAlign.center,
            ),
          ],
        );

    doc.addPage(
      pw.Page(
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'MT Vidros — Kit de marcadores para medição',
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 8),
            pw.Text(
              'IMPORTANTE: imprima esta página em tamanho real (100%), nunca em '
              '"ajustar à página". Qualquer escala aplicada pela impressora distorce '
              'a medida inteira. Confira com uma régua a linha de calibração no final '
              'da página antes de usar os marcadores pela primeira vez.',
              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 8),
            pw.Text(
              'Recorte os 4 marcadores abaixo e cole um em cada canto do vão a medir, '
              'de forma que o centro de cada QR code fique exatamente sobre o canto '
              'físico. Depois tire uma única foto com os 4 marcadores visíveis no app.',
              style: const pw.TextStyle(fontSize: 10),
            ),
            pw.SizedBox(height: 24),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
              children: [marker(), marker()],
            ),
            pw.SizedBox(height: 24),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
              children: [marker(), marker()],
            ),
            pw.SizedBox(height: 32),
            _calibrationRuler(),
          ],
        ),
      ),
    );

    return doc.save();
  }

  static pw.Widget _calibrationRuler() {
    const rulerLengthMm = 100.0;
    final rulerLengthPt = rulerLengthMm * PdfPageFormat.mm;
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Régua de calibração — deve medir exatamente 100mm com uma régua comum:',
          style: const pw.TextStyle(fontSize: 9),
        ),
        pw.SizedBox(height: 4),
        pw.Container(
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
