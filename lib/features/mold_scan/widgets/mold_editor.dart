import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/widgets.dart' as pw;

import '../services/cut_report_pdf_builder.dart';
import '../services/dxf_writer.dart';
import '../services/homography.dart';
import '../services/mold_outline.dart';
import '../services/mold_store.dart';
import '../services/quote.dart';
import '../services/svg_writer.dart';
import '../services/web_download.dart';
import '../theme/mold_scan_colors.dart';
import '../theme/mold_scan_theme.dart';

/// Where an outline sits inside a box of [size] with [pad] around it.
({double k, double dx, double dy}) fitOutline(
  Size size,
  MoldOutline o,
  double pad,
) {
  final k = max(
    0.0,
    min((size.width - 2 * pad) / o.width, (size.height - 2 * pad) / o.height),
  );
  return (
    k: k,
    dx: (size.width - o.width * k) / 2,
    dy: (size.height - o.height * k) / 2,
  );
}

/// Draws an outline fitted in its box: a thumbnail, or (with [dimensions])
/// the editor view with width/height dimension lines, an optional 100 mm
/// grid and an optional measurement between two points.
class OutlinePainter extends CustomPainter {
  final MoldOutline outline;
  final bool dimensions;
  final bool grid;
  final List<Point2D> measure; // 0-2 points, in outline mm

  OutlinePainter(
    this.outline, {
    this.dimensions = false,
    this.grid = false,
    this.measure = const [],
  });

  static const editorPad = 40.0;

  @override
  void paint(Canvas canvas, Size size) {
    final o = outline.normalized();
    if (o.width <= 0 || o.height <= 0) return;
    final f = fitOutline(size, o, dimensions ? editorPad : 4);
    Offset at(Point2D p) => Offset(f.dx + p.x * f.k, f.dy + p.y * f.k);

    if (grid) {
      final g = Paint()
        ..color = MoldScanColors.border.withValues(alpha: 0.7)
        ..strokeWidth = 0.6;
      for (var x = 0.0; x <= o.width + 1e-6; x += 100) {
        canvas.drawLine(at(Point2D(x, 0)), at(Point2D(x, o.height)), g);
      }
      for (var y = 0.0; y <= o.height + 1e-6; y += 100) {
        canvas.drawLine(at(Point2D(0, y)), at(Point2D(o.width, y)), g);
      }
    }

    final path = Path();
    for (var i = 0; i < o.points.length; i++) {
      final p = at(o.points[i]);
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    path.close();
    canvas.drawPath(
      path,
      Paint()..color = MoldScanColors.accent.withValues(alpha: 0.14),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = MoldScanColors.cut
        ..style = PaintingStyle.stroke
        ..strokeWidth = dimensions ? 2 : 1.5
        ..strokeJoin = StrokeJoin.round,
    );
    if (!dimensions) return;

    void label(
      String t,
      Offset c, {
      Color color = MoldScanColors.textPrimary,
      Color? bg,
    }) {
      final tp = TextPainter(
        text: TextSpan(
          text: t,
          style: TextStyle(
            color: color,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final r = Rect.fromCenter(
        center: c,
        width: tp.width + 10,
        height: tp.height + 4,
      );
      if (bg != null) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(r, const Radius.circular(3)),
          Paint()..color = bg,
        );
      }
      tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
    }

    final line = Paint()
      ..color = MoldScanColors.textSecondary
      ..strokeWidth = 1;
    final bottom = at(Point2D(0, o.height)).dy + 16,
        left = at(const Point2D(0, 0)).dx - 16;
    final x0 = at(const Point2D(0, 0)).dx, x1 = at(Point2D(o.width, 0)).dx;
    final y0 = at(const Point2D(0, 0)).dy, y1 = at(Point2D(0, o.height)).dy;
    canvas.drawLine(Offset(x0, bottom), Offset(x1, bottom), line);
    canvas.drawLine(Offset(x0, bottom - 4), Offset(x0, bottom + 4), line);
    canvas.drawLine(Offset(x1, bottom - 4), Offset(x1, bottom + 4), line);
    label('${_mm(o.width)} mm', Offset((x0 + x1) / 2, bottom + 12));
    canvas.drawLine(Offset(left, y0), Offset(left, y1), line);
    canvas.drawLine(Offset(left - 4, y0), Offset(left + 4, y0), line);
    canvas.drawLine(Offset(left - 4, y1), Offset(left + 4, y1), line);
    canvas.save();
    canvas.translate(left - 12, (y0 + y1) / 2);
    canvas.rotate(-pi / 2);
    label('${_mm(o.height)} mm', Offset.zero);
    canvas.restore();

    if (measure.isNotEmpty) {
      final dot = Paint()..color = MoldScanColors.warning;
      for (final p in measure) {
        canvas.drawCircle(at(p), 5, dot);
      }
      if (measure.length == 2) {
        final a = at(measure[0]), b = at(measure[1]);
        canvas.drawLine(a, b, dot..strokeWidth = 2);
        final d = sqrt(
          pow(measure[0].x - measure[1].x, 2) +
              pow(measure[0].y - measure[1].y, 2),
        );
        label(
          '${_mm(d)} mm',
          (a + b) / 2 - const Offset(0, 14),
          color: MoldScanColors.background,
          bg: MoldScanColors.warning,
        );
      }
    }
  }

  static String _mm(double v) => v.toStringAsFixed(1).replaceAll('.', ',');

  @override
  bool shouldRepaint(OutlinePainter old) =>
      old.outline != outline ||
      old.dimensions != dimensions ||
      old.grid != grid ||
      old.measure != measure;
}

/// Edits one outline (from the library or from a scan) into the piece to
/// cut: exact width and height (proportion locked or free), rotate/flip,
/// polyline or spline, optional smoothing/simplification, cut margin; then
/// exports DXF, SVG, cut report PDF and QR label, with a quick quote.
class MoldEditor extends StatefulWidget {
  final MoldOutline Function() original;
  final String initialName;
  final String backLabel;
  final VoidCallback onBack;
  final VoidCallback? onSaved;
  final VoidCallback? onDelete;

  /// Offer "Suavizar" and "Simplificar": useful on traced photo contours,
  /// pointless on clean library shapes.
  final bool fromScan;
  final String material;
  final String instructions;

  const MoldEditor({
    super.key,
    required this.original,
    required this.initialName,
    required this.onBack,
    this.backLabel = 'Voltar',
    this.onSaved,
    this.onDelete,
    this.fromScan = false,
    this.material = '',
    this.instructions = '',
  });

  @override
  State<MoldEditor> createState() => _MoldEditorState();
}

class _MoldEditorState extends State<MoldEditor> {
  late MoldOutline _base; // current orientation, at the starting size
  final _w = TextEditingController();
  final _h = TextEditingController();
  final _margin = TextEditingController(text: '0');
  late final TextEditingController _name = TextEditingController(
    text: widget.initialName,
  );
  late final TextEditingController _material = TextEditingController(
    text: widget.material,
  );
  final _glass = TextEditingController();
  late final TextEditingController _instructions = TextEditingController(
    text: widget.instructions,
  );
  late final TextEditingController _priceM2;
  late final TextEditingController _priceM;
  final _qty = TextEditingController(text: '1');
  bool _lock = true;
  bool _spline = false;
  bool _smooth = false;
  bool _simplify = false;
  bool _grid = false;
  bool _measuring = false;
  List<Point2D> _measure = const [];
  double _ratio = 1; // height / width when the lock was set
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _base = widget.original();
    final prices = MoldStore.prices();
    _priceM2 = TextEditingController(text: prices.$1);
    _priceM = TextEditingController(text: prices.$2);
    _resetSize();
  }

  @override
  void dispose() {
    for (final c in [
      _w,
      _h,
      _margin,
      _name,
      _material,
      _glass,
      _instructions,
      _priceM2,
      _priceM,
      _qty,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _resetSize() {
    _w.text = _fmt(_base.width);
    _h.text = _fmt(_base.height);
    _ratio = _base.height / _base.width;
  }

  static String _fmt(double v) =>
      v.toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '').replaceAll('.', ',');

  static double? _num(TextEditingController c) =>
      double.tryParse(c.text.trim().replaceAll(',', '.'));

  double get _marginMm => _num(_margin) ?? 0;

  Quote get _quote => Quote(
    pricePerM2: _num(_priceM2) ?? 0,
    pricePerMeter: _num(_priceM) ?? 0,
    quantity: (int.tryParse(_qty.text.trim()) ?? 1).clamp(1, 9999),
  );

  /// The outline exactly as it will be written: size, curve type, margin.
  MoldOutline? get _result {
    final w = _num(_w), h = _num(_h);
    if (w == null || h == null || w < 10 || h < 10 || w > 6000 || h > 6000) {
      return null;
    }
    final m = _marginMm;
    if (m.abs() > min(w, h) / 4) return null;
    var o = _base;
    if (_smooth) o = o.smoothed();
    if (_simplify) o = o.simplified();
    o = o.resized(w, h);
    if (_spline) o = o.splined();
    if (m != 0) o = o.offset(m).normalized();
    return o;
  }

  void _changed() => setState(() => _measure = const []);

  void _onW(String _) {
    final w = _num(_w);
    if (_lock && w != null) _h.text = _fmt(w * _ratio);
    _changed();
  }

  void _onH(String _) {
    final h = _num(_h);
    if (_lock && h != null && _ratio > 0) _w.text = _fmt(h / _ratio);
    _changed();
  }

  void _transform(MoldOutline Function(MoldOutline) f, {bool swaps = false}) {
    final w = _num(_w), h = _num(_h);
    setState(() {
      _base = f(_base);
      _measure = const [];
      // A quarter turn swaps the typed width and height.
      if (swaps && w != null && h != null) {
        _w.text = _fmt(h);
        _h.text = _fmt(w);
      }
      final nw = _num(_w), nh = _num(_h);
      if (nw != null && nh != null && nw > 0) _ratio = nh / nw;
    });
  }

  CutJob _job() => CutJob(
    name: _name.text.trim().isEmpty ? 'Molde' : _name.text.trim(),
    material: _material.text,
    glassThicknessMm: _num(_glass),
    instructions: _instructions.text,
    marginMm: _marginMm,
    spline: _spline,
    quote: _quote,
  );

  String get _fileBase {
    final n = _name.text
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final r = _result;
    return '${n.isEmpty ? 'molde' : n}${r == null ? '' : '_${r.width.round()}x${r.height.round()}mm'}';
  }

  void _dxf() {
    final r = _result;
    if (r == null) return;
    final j = _job();
    downloadBytes(
      DxfWriter.write(
        r.points,
        comments: [
          'Projeto: ${j.name}',
          'Medida final: ${r.width.toStringAsFixed(1)} x ${r.height.toStringAsFixed(1)} mm',
          if (j.material.trim().isNotEmpty) 'Material: ${j.material.trim()}',
          if ((j.glassThicknessMm ?? 0) > 0)
            'Espessura: ${j.glassThicknessMm} mm',
          if (j.marginMm != 0) 'Margem de corte: ${_fmt(j.marginMm)} mm',
          if (j.instructions.trim().isNotEmpty)
            'Instrucoes de corte: ${j.instructions.trim()}',
        ],
      ).codeUnits,
      '$_fileBase.dxf',
      'application/dxf',
    );
  }

  void _svg() {
    final r = _result;
    if (r == null) return;
    downloadBytes(
      SvgWriter.write(r, title: _name.text.trim()).codeUnits,
      '$_fileBase.svg',
      'image/svg+xml',
    );
  }

  Future<void> _pdf({required bool label}) async {
    final r = _result;
    if (r == null || _busy) return;
    setState(() => _busy = true);
    try {
      final job = _job();
      Future<ByteData?> asset(String path) async {
        try {
          return await rootBundle.load(path);
        } catch (_) {
          return null;
        }
      }

      final regular = await asset('assets/fonts/Barlow-Regular.ttf');
      final semi = await asset('assets/fonts/Barlow-SemiBold.ttf');
      final font = regular == null ? null : pw.Font.ttf(regular);
      final bold = semi == null ? null : pw.Font.ttf(semi);
      if (label) {
        downloadBytes(
          await CutReportPdfBuilder.label(r, job, font: font, bold: bold),
          'etiqueta_$_fileBase.pdf',
          'application/pdf',
        );
      } else {
        final logo = await asset('assets/images/logo.png');
        downloadBytes(
          await CutReportPdfBuilder.report(
            r,
            job,
            logoPng: logo?.buffer.asUint8List(),
            font: font,
            bold: bold,
          ),
          'relatorio_$_fileBase.pdf',
          'application/pdf',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _saveToMine() {
    final r = _result;
    if (r == null) return;
    final ok = MoldStore.add(
      _name.text.trim().isEmpty ? 'Molde' : _name.text.trim(),
      r,
    );
    widget.onSaved?.call();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Salvo em "Meus" na Biblioteca, com este tamanho.'
              : 'O navegador não deixou salvar (janela privada?).',
        ),
      ),
    );
  }

  void _tapPreview(Offset pos, Size size, MoldOutline r) {
    if (!_measuring) return;
    final o = r.normalized();
    final f = fitOutline(size, o, OutlinePainter.editorPad);
    if (f.k <= 0) return;
    final p = Point2D(
      ((pos.dx - f.dx) / f.k).clamp(0, o.width),
      ((pos.dy - f.dy) / f.k).clamp(0, o.height),
    );
    setState(() => _measure = _measure.length >= 2 ? [p] : [..._measure, p]);
  }

  Widget _section(String title, List<Widget> children) => Padding(
    padding: const EdgeInsets.only(top: 22),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: MoldScanType.headline(22)),
        const SizedBox(height: 12),
        ...children,
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final r = _result;
    final quote = _quote;

    final preview = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 380,
          decoration: BoxDecoration(
            color: MoldScanColors.surface,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: _measuring
                  ? MoldScanColors.warning
                  : MoldScanColors.border,
            ),
          ),
          child: r == null
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Digite largura e altura entre 10 e 6000 mm (a margem de corte não pode passar de 1/4 da menor medida).',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: MoldScanColors.textSecondary),
                    ),
                  ),
                )
              : LayoutBuilder(
                  builder: (context, c) => MouseRegion(
                    cursor: _measuring
                        ? SystemMouseCursors.precise
                        : MouseCursor.defer,
                    child: GestureDetector(
                      onTapUp: (d) =>
                          _tapPreview(d.localPosition, c.biggest, r),
                      child: CustomPaint(
                        painter: OutlinePainter(
                          r,
                          dimensions: true,
                          grid: _grid,
                          measure: _measure,
                        ),
                        size: Size.infinite,
                      ),
                    ),
                  ),
                ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilterChip(
              avatar: const Icon(Icons.grid_on, size: 16),
              label: const Text('Grade 10 cm'),
              selected: _grid,
              onSelected: (v) => setState(() => _grid = v),
            ),
            FilterChip(
              avatar: const Icon(Icons.straighten, size: 16),
              label: const Text('Medir'),
              selected: _measuring,
              onSelected: (v) => setState(() {
                _measuring = v;
                _measure = const [];
              }),
            ),
          ],
        ),
        if (_measuring)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              'Toque em dois pontos do desenho para medir a distância entre eles.',
              style: TextStyle(
                color: MoldScanColors.textSecondary,
                fontSize: 13.5,
              ),
            ),
          ),
        if (r != null) ...[
          const SizedBox(height: 14),
          Wrap(
            spacing: 22,
            runSpacing: 10,
            children: [
              _stat('Largura final', '${_fmt(r.width)} mm'),
              _stat('Altura final', '${_fmt(r.height)} mm'),
              _stat(
                'Área da peça',
                '${(r.areaMm2 / 1e6).toStringAsFixed(3).replaceAll('.', ',')} m²',
              ),
              _stat(
                'Linha de corte',
                '${(r.perimeterMm / 1000).toStringAsFixed(2).replaceAll('.', ',')} m',
              ),
              _stat('Pontos', '${r.points.length}'),
            ],
          ),
        ],
      ],
    );

    final controls = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _name,
          decoration: const InputDecoration(
            labelText: 'Nome do molde / projeto',
          ),
          onChanged: (_) => setState(() {}),
        ),
        _section('Medida final', [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _w,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: 'Largura (mm)'),
                  onChanged: _onW,
                ),
              ),
              IconButton(
                tooltip: _lock
                    ? 'Proporção travada: mude uma medida e a outra acompanha'
                    : 'Proporção livre',
                onPressed: () => setState(() {
                  _lock = !_lock;
                  final w = _num(_w), h = _num(_h);
                  if (_lock && w != null && h != null && w > 0) _ratio = h / w;
                }),
                icon: Icon(
                  _lock ? Icons.link : Icons.link_off,
                  color: _lock
                      ? MoldScanColors.accentAlt
                      : MoldScanColors.textSecondary,
                ),
              ),
              Expanded(
                child: TextField(
                  controller: _h,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: 'Altura (mm)'),
                  onChanged: _onH,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _lock
                ? 'Proporção travada.'
                : 'Proporção livre: largura e altura independentes.',
            style: const TextStyle(
              color: MoldScanColors.textSecondary,
              fontSize: 13.5,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => _transform((o) => o.rotated90(), swaps: true),
                icon: const Icon(Icons.rotate_90_degrees_cw, size: 18),
                label: const Text('Girar 90°'),
              ),
              OutlinedButton.icon(
                onPressed: () => _transform((o) => o.flippedHorizontally()),
                icon: const Icon(Icons.flip, size: 18),
                label: const Text('Espelhar lados'),
              ),
              OutlinedButton.icon(
                onPressed: () => _transform((o) => o.flippedVertically()),
                icon: const RotatedBox(
                  quarterTurns: 1,
                  child: Icon(Icons.flip, size: 18),
                ),
                label: const Text('Espelhar cima/baixo'),
              ),
              TextButton.icon(
                onPressed: () => setState(() {
                  _base = widget.original();
                  _spline = _smooth = _simplify = false;
                  _margin.text = '0';
                  _measure = const [];
                  _resetSize();
                }),
                icon: const Icon(Icons.restart_alt, size: 18),
                label: const Text('Restaurar'),
              ),
            ],
          ),
        ]),
        _section('Curva e margem', [
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Polilinha')),
              ButtonSegment(value: true, label: Text('Spline (suave)')),
            ],
            selected: {_spline},
            onSelectionChanged: (s) => setState(() => _spline = s.first),
          ),
          if (widget.fromScan) ...[
            const SizedBox(height: 6),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _smooth,
              onChanged: (v) => _changedWith(() => _smooth = v),
              title: const Text('Suavizar contorno'),
              subtitle: const Text(
                'Tira os pequenos degraus da foto, sem mudar a medida.',
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _simplify,
              onChanged: (v) => _changedWith(() => _simplify = v),
              title: const Text('Simplificar (compatibilidade máxima)'),
              subtitle: const Text(
                'Menos segmentos, desvio de até 0,3 mm. Para softwares de corte mais antigos.',
              ),
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: 280,
            child: TextField(
              controller: _margin,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Margem de corte (mm)',
                helperText: 'Positivo aumenta, negativo diminui a peça',
              ),
              onChanged: (_) => _changed(),
            ),
          ),
        ]),
        _section('Dados do projeto', [
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _material,
                  decoration: const InputDecoration(
                    labelText: 'Material',
                    hintText: 'vidro incolor, espelho',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _glass,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Espessura (mm)',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _instructions,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Instruções de corte',
              hintText: 'ex: lapidação reta, furo de 10 mm',
            ),
          ),
        ]),
        _section('Orçamento rápido', [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _priceM2,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Vidro (R\$/m²)',
                  ),
                  onChanged: (_) => _savePrices(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _priceM,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: 'Borda (R\$/m)'),
                  onChanged: (_) => _savePrices(),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 70,
                child: TextField(
                  controller: _qty,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Qtd.'),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (r != null && !quote.isEmpty)
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text:
                        'Área cobrada ${(quote.chargedAreaM2(r) * quote.quantity).toStringAsFixed(3).replaceAll('.', ',')} m² · '
                        'borda ${(quote.edgeMeters(r) * quote.quantity).toStringAsFixed(2).replaceAll('.', ',')} m\n',
                    style: const TextStyle(
                      color: MoldScanColors.textSecondary,
                      fontSize: 14,
                    ),
                  ),
                  TextSpan(
                    text: 'Total ${Quote.brl(quote.total(r))}',
                    style: MoldScanType.readout(26),
                  ),
                ],
              ),
            )
          else
            const Text(
              'O vidro é cobrado pelo retângulo (largura × altura); a borda, pela linha de corte. Os preços ficam salvos neste aparelho.',
              style: TextStyle(
                color: MoldScanColors.textSecondary,
                fontSize: 13.5,
                height: 1.4,
              ),
            ),
        ]),
        _section('Exportar', [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: r == null ? null : _dxf,
                icon: const Icon(Icons.download, size: 20),
                label: const Text('DXF 1:1'),
              ),
              OutlinedButton.icon(
                onPressed: r == null ? null : _svg,
                icon: const Icon(Icons.polyline_outlined, size: 18),
                label: const Text('SVG'),
              ),
              OutlinedButton.icon(
                onPressed: r == null || _busy ? null : () => _pdf(label: false),
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                label: const Text('Relatório PDF'),
              ),
              OutlinedButton.icon(
                onPressed: r == null || _busy ? null : () => _pdf(label: true),
                icon: const Icon(Icons.qr_code_2, size: 18),
                label: const Text('Etiqueta QR'),
              ),
              OutlinedButton.icon(
                onPressed: r == null ? null : _saveToMine,
                icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                label: const Text('Salvar em "Meus"'),
              ),
              if (widget.onDelete != null)
                TextButton.icon(
                  onPressed: () async {
                    final yes = await showDialog<bool>(
                      context: context,
                      builder: (c) => AlertDialog(
                        title: const Text('Excluir este molde?'),
                        content: const Text(
                          'Ele sai de "Meus" neste aparelho.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(c, false),
                            child: const Text('Cancelar'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(c, true),
                            child: const Text('Excluir'),
                          ),
                        ],
                      ),
                    );
                    if (yes == true) widget.onDelete!();
                  },
                  icon: const Icon(
                    Icons.delete_outline,
                    size: 18,
                    color: MoldScanColors.danger,
                  ),
                  label: const Text(
                    'Excluir',
                    style: TextStyle(color: MoldScanColors.danger),
                  ),
                ),
            ],
          ),
        ]),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextButton.icon(
          onPressed: widget.onBack,
          icon: const Icon(Icons.arrow_back, size: 18),
          label: Text(widget.backLabel),
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, c) {
            if (c.maxWidth >= 860) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 6, child: preview),
                  const SizedBox(width: 32),
                  Expanded(flex: 5, child: controls),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [preview, const SizedBox(height: 8), controls],
            );
          },
        ),
      ],
    );
  }

  void _changedWith(VoidCallback f) => setState(() {
    f();
    _measure = const [];
  });

  void _savePrices() {
    MoldStore.setPrices(_priceM2.text.trim(), _priceM.text.trim());
    setState(() {});
  }

  Widget _stat(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(
          color: MoldScanColors.textSecondary,
          fontSize: 13,
        ),
      ),
      Text(value, style: MoldScanType.readout(20)),
    ],
  );
}
