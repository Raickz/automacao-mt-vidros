import 'package:flutter/material.dart';

import '../services/dxf_writer.dart';
import '../services/mold_catalog.dart';
import '../services/mold_outline.dart';
import '../services/mold_store.dart';
import '../services/svg_writer.dart';
import '../services/web_download.dart';
import '../theme/mold_scan_colors.dart';
import '../theme/mold_scan_theme.dart';

enum _Filter { todos, altos, largos, redondos, favoritos, meus }

const _filterLabels = {
  _Filter.todos: 'Todos',
  _Filter.altos: 'Altos',
  _Filter.largos: 'Largos',
  _Filter.redondos: 'Redondos',
  _Filter.favoritos: 'Favoritos',
  _Filter.meus: 'Meus',
};

/// One entry of the grid: a catalog shape or a saved one.
class _Item {
  final String key; // catalog code or saved id
  final String code;
  final String name;
  final bool saved;
  final MoldOutline Function() outline;
  final bool tall, wide, round;

  _Item({
    required this.key,
    required this.code,
    required this.name,
    required this.saved,
    required this.outline,
    required this.tall,
    required this.wide,
    required this.round,
  });
}

/// Library of ready-made and saved molds. Opening one lets the worker type
/// the real width and height, flip/rotate it, pick spline or straight
/// segments, add a cut margin, and download DXF or SVG at that exact size.
class MoldLibraryPage extends StatefulWidget {
  /// Outline of the last scan, offered as "Salvar o molde digitalizado".
  final MoldOutline? scanned;

  const MoldLibraryPage({super.key, this.scanned});

  @override
  State<MoldLibraryPage> createState() => _MoldLibraryPageState();
}

class _MoldLibraryPageState extends State<MoldLibraryPage> {
  final _search = TextEditingController();
  _Filter _filter = _Filter.todos;
  final Set<String> _favs = MoldStore.favorites();
  List<SavedMold> _saved = MoldStore.load();
  _Item? _open;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<_Item> get _items {
    final items = <_Item>[
      for (final s in _saved)
        _Item(
          key: s.id,
          code: 'MEU',
          name: s.name,
          saved: true,
          outline: () => s.outline,
          tall: s.outline.height / s.outline.width >= 1.3,
          wide: s.outline.width / s.outline.height >= 1.3,
          round: false,
        ),
      for (final c in MoldCatalog.all)
        _Item(
          key: c.code,
          code: c.code,
          name: c.name,
          saved: false,
          outline: c.outline,
          tall: c.tall,
          wide: c.wide,
          round: c.round,
        ),
    ];
    final q = _search.text.trim().toLowerCase();
    return items.where((i) {
      if (q.isNotEmpty && !('${i.code} ${i.name}'.toLowerCase().contains(q))) {
        return false;
      }
      return switch (_filter) {
        _Filter.todos => true,
        _Filter.altos => i.tall,
        _Filter.largos => i.wide,
        _Filter.redondos => i.round,
        _Filter.favoritos => _favs.contains(i.key),
        _Filter.meus => i.saved,
      };
    }).toList();
  }

  void _toggleFav(String key) {
    setState(() => _favs.contains(key) ? _favs.remove(key) : _favs.add(key));
    MoldStore.setFavorites(_favs);
  }

  void _refreshSaved() => setState(() => _saved = MoldStore.load());

  @override
  Widget build(BuildContext context) {
    final open = _open;
    if (open != null) {
      return _MoldEditor(
        key: ValueKey(open.key),
        item: open,
        onBack: () => setState(() => _open = null),
        onSaved: _refreshSaved,
        onDeleted: () {
          _refreshSaved();
          setState(() => _open = null);
        },
      );
    }
    final items = _items;
    final scanned = widget.scanned;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Biblioteca de moldes', style: MoldScanType.headline(34)),
        const SizedBox(height: 8),
        const Text(
          'Escolha uma forma pronta, digite a largura e a altura que o cliente pediu e baixe o DXF no tamanho exato.',
          style: TextStyle(
            color: MoldScanColors.textSecondary,
            fontSize: 16,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 16),
        if (scanned != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: OutlinedButton.icon(
              onPressed: () {
                final ok = MoldStore.add('Molde digitalizado', scanned);
                _refreshSaved();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      ok
                          ? 'Salvo em "Meus".'
                          : 'O navegador não deixou salvar (janela privada?).',
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.bookmark_add_outlined, size: 18),
              label: const Text('Salvar o molde digitalizado em "Meus"'),
            ),
          ),
        TextField(
          controller: _search,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'Buscar por código ou nome',
            prefixIcon: Icon(Icons.search),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final f in _Filter.values)
              ChoiceChip(
                label: Text(_filterLabels[f]!),
                selected: _filter == f,
                onSelected: (_) => setState(() => _filter = f),
              ),
          ],
        ),
        const SizedBox(height: 18),
        if (items.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Text(
              'Nenhum molde encontrado.',
              style: TextStyle(color: MoldScanColors.textSecondary),
            ),
          )
        else
          LayoutBuilder(
            builder: (context, c) {
              final cols = (c.maxWidth / 190).floor().clamp(2, 6);
              return GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: cols,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.82,
                children: [
                  for (final i in items)
                    _Card(
                      item: i,
                      fav: _favs.contains(i.key),
                      onFav: () => _toggleFav(i.key),
                      onTap: () => setState(() => _open = i),
                    ),
                ],
              );
            },
          ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  final _Item item;
  final bool fav;
  final VoidCallback onFav, onTap;

  const _Card({
    required this.item,
    required this.fav,
    required this.onFav,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        decoration: BoxDecoration(
          color: MoldScanColors.surface,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: MoldScanColors.border),
        ),
        padding: const EdgeInsets.fromLTRB(10, 6, 6, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  item.code,
                  style: const TextStyle(
                    color: MoldScanColors.accentAlt,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: fav ? 'Tirar dos favoritos' : 'Favoritar',
                  onPressed: onFav,
                  icon: Icon(
                    fav ? Icons.star : Icons.star_border,
                    size: 20,
                    color: fav
                        ? MoldScanColors.warning
                        : MoldScanColors.textSecondary,
                  ),
                ),
              ],
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 4),
                child: _Thumb(outline: item.outline()),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              item.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  final MoldOutline outline;
  const _Thumb({required this.outline});

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _OutlinePainter(outline, false), size: Size.infinite);
}

class _OutlinePainter extends CustomPainter {
  final MoldOutline outline;
  final bool dimensions;

  _OutlinePainter(this.outline, this.dimensions);

  @override
  void paint(Canvas canvas, Size size) {
    final o = outline.normalized();
    if (o.width <= 0 || o.height <= 0) return;
    final pad = dimensions ? 34.0 : 4.0;
    final k = ((size.width - 2 * pad) / o.width)
        .clamp(0, double.infinity)
        .toDouble();
    final k2 = ((size.height - 2 * pad) / o.height)
        .clamp(0, double.infinity)
        .toDouble();
    final s = k < k2 ? k : k2;
    final dx = (size.width - o.width * s) / 2,
        dy = (size.height - o.height * s) / 2;
    final path = Path();
    for (var i = 0; i < o.points.length; i++) {
      final p = Offset(dx + o.points[i].x * s, dy + o.points[i].y * s);
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
    final line = Paint()
      ..color = MoldScanColors.textSecondary
      ..strokeWidth = 1;
    void label(String t, Offset at) {
      final tp = TextPainter(
        text: TextSpan(
          text: t,
          style: const TextStyle(
            color: MoldScanColors.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, at - Offset(tp.width / 2, tp.height / 2));
    }

    final y = dy + o.height * s + 16;
    canvas.drawLine(Offset(dx, y), Offset(dx + o.width * s, y), line);
    label(
      '${o.width.toStringAsFixed(0)} mm',
      Offset(dx + o.width * s / 2, y + 12),
    );
    final x = dx - 16;
    canvas.drawLine(Offset(x, dy), Offset(x, dy + o.height * s), line);
    canvas.save();
    canvas.translate(x - 12, dy + o.height * s / 2);
    canvas.rotate(-1.5708);
    label('${o.height.toStringAsFixed(0)} mm', Offset.zero);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_OutlinePainter old) =>
      old.outline != outline || old.dimensions != dimensions;
}

class _MoldEditor extends StatefulWidget {
  final _Item item;
  final VoidCallback onBack, onSaved, onDeleted;

  const _MoldEditor({
    super.key,
    required this.item,
    required this.onBack,
    required this.onSaved,
    required this.onDeleted,
  });

  @override
  State<_MoldEditor> createState() => _MoldEditorState();
}

class _MoldEditorState extends State<_MoldEditor> {
  late MoldOutline _base; // current orientation, at the starting size
  final _w = TextEditingController();
  final _h = TextEditingController();
  final _margin = TextEditingController(text: '0');
  late final TextEditingController _name;
  bool _lock = true;
  bool _spline = false;
  double _ratio = 1; // height / width when the lock was set

  @override
  void initState() {
    super.initState();
    _base = widget.item.outline();
    _name = TextEditingController(
      text:
          '${widget.item.code == 'MEU' ? '' : '${widget.item.code} '}${widget.item.name}',
    );
    _resetSize();
  }

  @override
  void dispose() {
    _w.dispose();
    _h.dispose();
    _margin.dispose();
    _name.dispose();
    super.dispose();
  }

  void _resetSize() {
    _w.text = _fmt(_base.width);
    _h.text = _fmt(_base.height);
    _ratio = _base.height / _base.width;
  }

  static String _fmt(double v) =>
      v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 1);

  double? _num(TextEditingController c) =>
      double.tryParse(c.text.trim().replaceAll(',', '.'));

  double get _marginMm => _num(_margin) ?? 0;

  /// The outline exactly as it will be written: size, curve type, margin.
  MoldOutline? get _result {
    final w = _num(_w), h = _num(_h);
    if (w == null || h == null || w < 10 || h < 10 || w > 5000 || h > 5000)
      return null;
    var o = _base.resized(w, h);
    if (_spline) o = o.splined();
    final m = _marginMm;
    if (m != 0) o = o.offset(m).normalized();
    return o;
  }

  void _onW(String _) {
    final w = _num(_w);
    if (_lock && w != null) _h.text = _fmt(w * _ratio);
    setState(() {});
  }

  void _onH(String _) {
    final h = _num(_h);
    if (_lock && h != null && _ratio > 0) _w.text = _fmt(h / _ratio);
    setState(() {});
  }

  void _transform(MoldOutline Function(MoldOutline) f) {
    // Keep the typed size when turning: a 90° turn swaps width and height.
    final w = _num(_w), h = _num(_h);
    final before = _base;
    setState(() {
      _base = f(_base);
      final swapped =
          (_base.width - before.height).abs() < 1e-6 &&
          (_base.height - before.width).abs() < 1e-6 &&
          (before.width - before.height).abs() > 1e-6;
      if (swapped && w != null && h != null) {
        _w.text = _fmt(h);
        _h.text = _fmt(w);
      }
      final nw = _num(_w), nh = _num(_h);
      if (nw != null && nh != null && nw > 0) _ratio = nh / nw;
    });
  }

  List<String> _comments() => [
    'Molde: ${_name.text.trim()}',
    if (_marginMm != 0) 'Margem de corte: ${_fmt(_marginMm)} mm',
  ];

  String get _fileBase {
    final n = _name.text
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final r = _result;
    return '${n.isEmpty ? 'molde' : n}_${r == null ? '' : '${r.width.round()}x${r.height.round()}'}';
  }

  void _dxf() {
    final r = _result;
    if (r == null) return;
    downloadBytes(
      DxfWriter.write(r.points, comments: _comments()).codeUnits,
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

  void _saveToMine() {
    final r = _result;
    if (r == null) return;
    final ok = MoldStore.add(
      _name.text.trim().isEmpty ? 'Molde' : _name.text.trim(),
      r,
    );
    widget.onSaved();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Salvo em "Meus" com este tamanho.'
              : 'O navegador não deixou salvar (janela privada?).',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = _result;
    final preview = Container(
      height: 340,
      decoration: BoxDecoration(
        color: MoldScanColors.surface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: MoldScanColors.border),
      ),
      child: r == null
          ? const Center(
              child: Text(
                'Digite largura e altura entre 10 e 5000 mm.',
                style: TextStyle(color: MoldScanColors.textSecondary),
              ),
            )
          : CustomPaint(painter: _OutlinePainter(r, true), size: Size.infinite),
    );
    final controls = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _name,
          decoration: const InputDecoration(labelText: 'Nome do molde'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
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
              tooltip: _lock ? 'Proporção travada' : 'Proporção livre',
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
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: () => _transform((o) => o.rotated90()),
              icon: const Icon(Icons.rotate_90_degrees_cw, size: 18),
              label: const Text('Girar 90°'),
            ),
            OutlinedButton.icon(
              onPressed: () => _transform((o) => o.flippedHorizontally()),
              icon: const Icon(Icons.flip, size: 18),
              label: const Text('Espelhar ↔'),
            ),
            OutlinedButton.icon(
              onPressed: () => _transform((o) => o.flippedVertically()),
              icon: const RotatedBox(
                quarterTurns: 1,
                child: Icon(Icons.flip, size: 18),
              ),
              label: const Text('Espelhar ↕'),
            ),
            TextButton(
              onPressed: () => setState(() {
                _base = widget.item.outline();
                _spline = false;
                _margin.text = '0';
                _resetSize();
              }),
              child: const Text('Restaurar'),
            ),
          ],
        ),
        const SizedBox(height: 14),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('Polilinha')),
            ButtonSegment(value: true, label: Text('Spline (suave)')),
          ],
          selected: {_spline},
          onSelectionChanged: (s) => setState(() => _spline = s.first),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: 260,
          child: TextField(
            controller: _margin,
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
              signed: true,
            ),
            decoration: const InputDecoration(
              labelText: 'Margem de corte (mm)',
              helperText: 'Positivo aumenta, negativo diminui',
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        const SizedBox(height: 14),
        if (r != null)
          Text(
            'Tamanho final: ${r.width.toStringAsFixed(1)} × ${r.height.toStringAsFixed(1)} mm · área ${(r.areaMm2 / 1e6).toStringAsFixed(3)} m² · corte ${(r.perimeterMm / 1000).toStringAsFixed(2)} m',
            style: const TextStyle(
              color: MoldScanColors.textSecondary,
              fontSize: 14.5,
              height: 1.4,
            ),
          ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            FilledButton.icon(
              onPressed: r == null ? null : _dxf,
              icon: const Icon(Icons.download, size: 20),
              label: const Text('Baixar DXF'),
            ),
            OutlinedButton.icon(
              onPressed: r == null ? null : _svg,
              icon: const Icon(Icons.image_outlined, size: 18),
              label: const Text('Baixar SVG'),
            ),
            OutlinedButton.icon(
              onPressed: r == null ? null : _saveToMine,
              icon: const Icon(Icons.bookmark_add_outlined, size: 18),
              label: const Text('Salvar em "Meus"'),
            ),
            if (widget.item.saved)
              TextButton.icon(
                onPressed: () {
                  MoldStore.remove(widget.item.key);
                  widget.onDeleted();
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
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextButton.icon(
          onPressed: widget.onBack,
          icon: const Icon(Icons.arrow_back, size: 18),
          label: const Text('Biblioteca'),
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, c) {
            if (c.maxWidth >= 800) {
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
              children: [preview, const SizedBox(height: 20), controls],
            );
          },
        ),
      ],
    );
  }
}
