import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:vector_math/vector_math_64.dart' show Matrix4;

import 'mold_outline.dart';
import 'quote.dart';

/// What goes on the report and on the label besides the outline.
class CutJob {
  final String name;
  final String material;
  final double? glassThicknessMm;
  final String instructions;
  final double marginMm;
  final bool spline;
  final Quote quote;
  final DateTime date;

  CutJob({
    required this.name,
    this.material = '',
    this.glassThicknessMm,
    this.instructions = '',
    this.marginMm = 0,
    this.spline = false,
    this.quote = const Quote(),
    DateTime? date,
  }) : date = date ?? DateTime.now();

  String get dateText =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} '
      '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

  /// Short id printed on the label and inside its QR code.
  String get jobCode =>
      'MT${date.year % 100}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}-'
      '${date.hour.toString().padLeft(2, '0')}${date.minute.toString().padLeft(2, '0')}${date.second.toString().padLeft(2, '0')}';
}

/// Cutting report (A4: drawing with dimensions + technical data + quote) and
/// a 100 x 60 mm piece label with a QR code. Text is ASCII-safe for the
/// built-in PDF font: accents are folded (the default Helvetica has no
/// Latin-1 glyph table in package:pdf).
class CutReportPdfBuilder {
  static Future<Uint8List> report(
    MoldOutline outline,
    CutJob job, {
    Uint8List? logoPng,
    pw.Font? font,
    pw.Font? bold,
  }) async {
    String t(String s) => font == null ? _a(s) : s;
    final theme = font == null
        ? null
        : pw.ThemeData.withFont(base: font, bold: bold ?? font);
    final o = outline.normalized();
    final doc = pw.Document(title: t(job.name), author: 'Marabá Temper');
    final logo = logoPng == null ? null : pw.MemoryImage(logoPng);
    String mm(double v) => '${v.toStringAsFixed(1).replaceAll('.', ',')} mm';

    final rows = <List<String>>[
      ['Largura', mm(o.width)],
      ['Altura', mm(o.height)],
      [
        'Área da peça',
        '${(o.areaMm2 / 1e6).toStringAsFixed(3).replaceAll('.', ',')} m²',
      ],
      [
        'Área cobrada (L × A)',
        '${(o.width * o.height / 1e6).toStringAsFixed(3).replaceAll('.', ',')} m²',
      ],
      [
        'Perímetro (linha de corte)',
        '${(o.perimeterMm / 1000).toStringAsFixed(3).replaceAll('.', ',')} m',
      ],
      ['Pontos do contorno', '${o.points.length}'],
      ['Curva', job.spline ? 'Spline (suave)' : 'Polilinha'],
      ['Margem de corte', job.marginMm == 0 ? 'nenhuma' : mm(job.marginMm)],
      if (job.material.trim().isNotEmpty) ['Material', job.material.trim()],
      if (job.glassThicknessMm != null && job.glassThicknessMm! > 0)
        ['Espessura', mm(job.glassThicknessMm!)],
      ['Arquivo', 'DXF em milímetros, escala 1:1, origem 0,0'],
    ];

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        theme: theme,
        margin: const pw.EdgeInsets.all(28),
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              children: [
                if (logo != null)
                  pw.Container(height: 40, child: pw.Image(logo)),
                if (logo != null) pw.SizedBox(width: 12),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        t('Relatório de corte'),
                        style: pw.TextStyle(
                          fontSize: 20,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.Text(
                        t(job.name),
                        style: const pw.TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      job.jobCode,
                      style: pw.TextStyle(
                        fontSize: 11,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Text(
                      job.dateText,
                      style: const pw.TextStyle(
                        fontSize: 9,
                        color: PdfColors.grey700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 10),
            pw.Divider(color: PdfColors.grey400),
            pw.SizedBox(height: 6),
            pw.Container(
              height: job.quote.isEmpty && job.instructions.trim().isEmpty
                  ? 400
                  : 290,
              width: double.infinity,
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey400, width: 0.6),
              ),
              child: pw.CustomPaint(
                painter: (canvas, size) => _drawing(canvas, size, o),
              ),
            ),
            pw.SizedBox(height: 14),
            pw.Text(
              t('Dados técnicos'),
              style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 6),
            _table(rows, t),
            if (job.instructions.trim().isNotEmpty) ...[
              pw.SizedBox(height: 10),
              pw.Text(
                t('Instruções de corte'),
                style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(
                t(job.instructions.trim()),
                style: const pw.TextStyle(fontSize: 10),
              ),
            ],
            if (!job.quote.isEmpty) ...[
              pw.SizedBox(height: 12),
              pw.Text(
                t('Orçamento'),
                style: pw.TextStyle(
                  fontSize: 13,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 6),
              _table([
                ['Quantidade', '${job.quote.quantity}'],
                if (job.quote.pricePerM2 > 0)
                  [
                    'Vidro (${Quote.brl(job.quote.pricePerM2)}/m²)',
                    Quote.brl(job.quote.glass(o)),
                  ],
                if (job.quote.pricePerMeter > 0)
                  [
                    'Acabamento de borda (${Quote.brl(job.quote.pricePerMeter)}/m)',
                    Quote.brl(job.quote.edge(o)),
                  ],
                ['Total', Quote.brl(job.quote.total(o))],
              ], t),
            ],
            pw.Spacer(),
            pw.Text(
              t(
                'Medidas a conferir na trena antes do corte. Gerado pelo app Digitalizar molde – Marabá Temper.',
              ),
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
            ),
          ],
        ),
      ),
    );
    return doc.save();
  }

  /// 100 x 60 mm label to tape on the cut piece or on the mold.
  static Future<Uint8List> label(
    MoldOutline outline,
    CutJob job, {
    pw.Font? font,
    pw.Font? bold,
  }) async {
    String t(String s) => font == null ? _a(s) : s;
    final theme = font == null
        ? null
        : pw.ThemeData.withFont(base: font, bold: bold ?? font);
    final o = outline.normalized();
    final doc = pw.Document(title: 'Etiqueta ${job.jobCode}');
    final qr =
        'MT|${job.jobCode}|${t(job.name)}|${o.width.round()}x${o.height.round()}mm'
        '${job.material.trim().isEmpty ? '' : '|${t(job.material.trim())}'}';
    doc.addPage(
      pw.Page(
        pageFormat: const PdfPageFormat(
          100 * PdfPageFormat.mm,
          60 * PdfPageFormat.mm,
        ),
        theme: theme,
        margin: const pw.EdgeInsets.all(4 * PdfPageFormat.mm),
        build: (ctx) => pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.BarcodeWidget(
              barcode: pw.Barcode.qrCode(),
              data: qr,
              width: 30 * PdfPageFormat.mm,
              height: 30 * PdfPageFormat.mm,
            ),
            pw.SizedBox(width: 4 * PdfPageFormat.mm),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    t('MARABÁ TEMPER'),
                    style: pw.TextStyle(
                      fontSize: 7,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.grey700,
                    ),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    t(job.name),
                    maxLines: 2,
                    style: pw.TextStyle(
                      fontSize: 11,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 3),
                  pw.Text(
                    '${o.width.round()} x ${o.height.round()} mm',
                    style: pw.TextStyle(
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  if (job.material.trim().isNotEmpty ||
                      (job.glassThicknessMm ?? 0) > 0)
                    pw.Text(
                      [
                        if (job.material.trim().isNotEmpty)
                          t(job.material.trim()),
                        if ((job.glassThicknessMm ?? 0) > 0)
                          '${job.glassThicknessMm!.toStringAsFixed(0)} mm',
                      ].join(' - '),
                      style: const pw.TextStyle(fontSize: 9),
                    ),
                  pw.Spacer(),
                  pw.Text(job.jobCode, style: const pw.TextStyle(fontSize: 8)),
                  pw.Text(
                    job.dateText,
                    style: const pw.TextStyle(
                      fontSize: 7,
                      color: PdfColors.grey700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    return doc.save();
  }

  static pw.Widget _table(List<List<String>> rows, String Function(String) t) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
      columnWidths: const {0: pw.FlexColumnWidth(3), 1: pw.FlexColumnWidth(4)},
      children: [
        for (var i = 0; i < rows.length; i++)
          pw.TableRow(
            decoration: pw.BoxDecoration(
              color: i.isEven ? PdfColors.grey100 : PdfColors.white,
            ),
            children: [
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 3,
                ),
                child: pw.Text(
                  t(rows[i][0]),
                  style: const pw.TextStyle(fontSize: 9.5),
                ),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 3,
                ),
                child: pw.Text(
                  t(rows[i][1]),
                  style: pw.TextStyle(
                    fontSize: 9.5,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }

  /// Outline fitted in the box, with width and height dimension lines.
  static void _drawing(PdfGraphics canvas, PdfPoint size, MoldOutline o) {
    if (o.width <= 0 || o.height <= 0) return;
    const pad = 36.0;
    final k = [
      (size.x - 2 * pad) / o.width,
      (size.y - 2 * pad) / o.height,
    ].reduce((a, b) => a < b ? a : b);
    final dx = (size.x - o.width * k) / 2, dy = (size.y - o.height * k) / 2;
    // PDF is y-up; outline is y-down.
    double px(double x) => dx + x * k;
    double py(double y) => size.y - (dy + y * k);

    canvas
      ..setStrokeColor(PdfColors.grey300)
      ..setLineWidth(0.3);
    for (var gx = 0.0; gx <= o.width; gx += 100) {
      canvas.drawLine(px(gx), py(0), px(gx), py(o.height));
    }
    for (var gy = 0.0; gy <= o.height; gy += 100) {
      canvas.drawLine(px(0), py(gy), px(o.width), py(gy));
    }
    canvas.strokePath();

    canvas.moveTo(px(o.points.first.x), py(o.points.first.y));
    for (final p in o.points.skip(1)) {
      canvas.lineTo(px(p.x), py(p.y));
    }
    canvas
      ..closePath()
      ..setStrokeColor(PdfColor.fromHex('#E0115F'))
      ..setLineWidth(1.4)
      ..strokePath();

    canvas
      ..setStrokeColor(PdfColors.grey800)
      ..setLineWidth(0.6);
    final yDim = py(o.height) - 16;
    canvas.drawLine(px(0), yDim, px(o.width), yDim);
    canvas.drawLine(px(0), yDim - 4, px(0), yDim + 4);
    canvas.drawLine(px(o.width), yDim - 4, px(o.width), yDim + 4);
    final xDim = px(0) - 16;
    canvas.drawLine(xDim, py(0), xDim, py(o.height));
    canvas.drawLine(xDim - 4, py(0), xDim + 4, py(0));
    canvas.drawLine(xDim - 4, py(o.height), xDim + 4, py(o.height));
    canvas.strokePath();

    final font = canvas.defaultFont;
    if (font == null) return;
    canvas.setFillColor(PdfColors.black);
    final wText = '${o.width.toStringAsFixed(1).replaceAll('.', ',')} mm';
    final hText = '${o.height.toStringAsFixed(1).replaceAll('.', ',')} mm';
    const fs = 9.0;
    final wW = font.stringMetrics(wText).width * fs;
    canvas.drawString(
      font,
      fs,
      wText,
      (px(0) + px(o.width)) / 2 - wW / 2,
      yDim - 12,
    );
    final hW = font.stringMetrics(hText).width * fs;
    canvas
      ..saveContext()
      ..setTransform(
        Matrix4.translationValues(
          xDim - 6,
          (py(0) + py(o.height)) / 2 - hW / 2,
          0,
        )..rotateZ(1.5708),
      );
    canvas.drawString(font, fs, hText, 0, 0);
    canvas.restoreContext();
    canvas.drawString(font, 7, 'grade de 100 mm', px(0), py(0) + 6);
  }

  /// Folds Portuguese accents so the built-in font can print the text.
  static String _a(String s) {
    const from = 'áàâãäéèêëíìîïóòôõöúùûüçÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ×²';
    const to = 'aaaaaeeeeiiiiooooouuuucAAAAAEEEEIIIIOOOOOUUUUCx2';
    final b = StringBuffer();
    for (final ch in s.runes) {
      final c = String.fromCharCode(ch);
      final i = from.indexOf(c);
      b.write(i >= 0 ? to[i] : (ch < 128 ? c : '?'));
    }
    return b.toString();
  }
}
