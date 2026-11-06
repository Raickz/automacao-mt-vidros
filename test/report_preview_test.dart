// Writes sample PDFs when MT_PREVIEW_DIR is set (manual visual check only).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:mt_vidros_app/features/mold_scan/services/cut_report_pdf_builder.dart';
import 'package:mt_vidros_app/features/mold_scan/services/mold_catalog.dart';
import 'package:mt_vidros_app/features/mold_scan/services/quote.dart';

void main() {
  final dir = Platform.environment['MT_PREVIEW_DIR'];
  test('preview PDFs', () async {
    final o = MoldCatalog.all
        .firstWhere((m) => m.name == 'Arco de porta')
        .outline()
        .resized(820, 2150);
    final job = CutJob(
      name: 'Porta arco - Cliente João',
      material: 'Vidro temperado incolor',
      glassThicknessMm: 8,
      instructions: 'Lapidação reta polida. Conferir prumo.',
      marginMm: -2,
      quote: const Quote(pricePerM2: 380, pricePerMeter: 14, quantity: 2),
    );
    final logo = File('assets/images/logo.png').readAsBytesSync();
    pw.Font f(String n) => pw.Font.ttf(
      File('assets/fonts/$n.ttf').readAsBytesSync().buffer.asByteData(),
    );
    final font = f('Barlow-Regular'), bold = f('Barlow-SemiBold');
    File('$dir/relatorio.pdf').writeAsBytesSync(
      await CutReportPdfBuilder.report(
        o,
        job,
        logoPng: logo,
        font: font,
        bold: bold,
      ),
    );
    File('$dir/etiqueta.pdf').writeAsBytesSync(
      await CutReportPdfBuilder.label(o, job, font: font, bold: bold),
    );
  }, skip: dir == null ? 'set MT_PREVIEW_DIR to write sample PDFs' : null);
}
