import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../services/homography.dart';
import '../theme/mold_scan_colors.dart';
import '../theme/mold_scan_theme.dart';

/// Manual calibration: the worker drags 4 points onto the centers of the 4
/// QR markers (top-left, top-right, bottom-right, bottom-left). A magnifier
/// follows the point being dragged. Returns the points as fractions (0..1)
/// of the photo's width and height.
class CornerPicker extends StatefulWidget {
  final Uint8List photo;
  final void Function(List<Point2D> normalized) onDone;
  final VoidCallback onCancel;

  const CornerPicker({
    super.key,
    required this.photo,
    required this.onDone,
    required this.onCancel,
  });

  @override
  State<CornerPicker> createState() => _CornerPickerState();
}

class _CornerPickerState extends State<CornerPicker> {
  static const _labels = [
    'Superior esquerdo',
    'Superior direito',
    'Inferior direito',
    'Inferior esquerdo',
  ];
  static const _short = ['1', '2', '3', '4'];
  final _pts = [
    const Offset(0.12, 0.15),
    const Offset(0.88, 0.15),
    const Offset(0.88, 0.85),
    const Offset(0.12, 0.85),
  ];
  double? _aspect;
  int? _dragging;

  @override
  void initState() {
    super.initState();
    ui
        .instantiateImageCodec(widget.photo)
        .then((c) => c.getNextFrame())
        .then((f) {
          if (mounted) setState(() => _aspect = f.image.width / f.image.height);
          f.image.dispose();
        })
        .catchError((_) {
          if (mounted) setState(() => _aspect = 4 / 3);
        });
  }

  @override
  Widget build(BuildContext context) {
    final aspect = _aspect;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Calibração manual', style: MoldScanType.headline(28)),
        const SizedBox(height: 8),
        const Text(
          'Arraste cada ponto numerado para o centro do quadrado preto do QR do mesmo canto: '
          '1 superior esquerdo, 2 superior direito, 3 inferior direito, 4 inferior esquerdo. '
          'A lupa ajuda a acertar. A distância entre os marcadores precisa estar digitada em "Escala".',
          style: TextStyle(
            color: MoldScanColors.textSecondary,
            fontSize: 15,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 14),
        if (aspect == null)
          const SizedBox(
            height: 200,
            child: Center(child: CircularProgressIndicator()),
          )
        else
          LayoutBuilder(
            builder: (context, c) {
              final w = c.maxWidth, h = w / aspect;
              Offset px(int i) => Offset(_pts[i].dx * w, _pts[i].dy * h);
              final d = _dragging;
              return SizedBox(
                width: w,
                height: h,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: Image.memory(
                        widget.photo,
                        fit: BoxFit.fill,
                        gaplessPlayback: true,
                      ),
                    ),
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _QuadPainter([
                          for (var i = 0; i < 4; i++) px(i),
                        ]),
                      ),
                    ),
                    for (var i = 0; i < 4; i++)
                      Positioned(
                        left: px(i).dx - 22,
                        top: px(i).dy - 22,
                        child: Semantics(
                          label: 'Ponto ${_labels[i]}',
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onPanStart: (_) => setState(() => _dragging = i),
                            onPanEnd: (_) => setState(() => _dragging = null),
                            onPanUpdate: (u) => setState(() {
                              final p = px(i) + u.delta;
                              _pts[i] = Offset(
                                (p.dx / w).clamp(0.0, 1.0),
                                (p.dy / h).clamp(0.0, 1.0),
                              );
                            }),
                            child: SizedBox(
                              width: 44,
                              height: 44,
                              child: Center(
                                child: Container(
                                  width: 26,
                                  height: 26,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: MoldScanColors.cut.withValues(
                                      alpha: 0.85,
                                    ),
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 2,
                                    ),
                                  ),
                                  child: Text(
                                    _short[i],
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (d != null)
                      Positioned(
                        left: px(d).dx - 60,
                        top: px(d).dy - 60 - 100,
                        child: const RawMagnifier(
                          size: Size(120, 120),
                          magnificationScale: 3,
                          focalPointOffset: Offset(0, 100),
                          decoration: MagnifierDecoration(
                            shape: CircleBorder(
                              side: BorderSide(
                                color: MoldScanColors.accentAlt,
                                width: 3,
                              ),
                            ),
                          ),
                          child: Center(
                            child: Icon(
                              Icons.add,
                              color: MoldScanColors.cut,
                              size: 28,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            FilledButton.icon(
              onPressed: aspect == null
                  ? null
                  : () => widget.onDone([
                      for (final p in _pts) Point2D(p.dx, p.dy),
                    ]),
              icon: const Icon(Icons.check, size: 20),
              label: const Text('Medir com estes pontos'),
            ),
            TextButton(
              onPressed: widget.onCancel,
              child: const Text('Cancelar'),
            ),
          ],
        ),
      ],
    );
  }
}

class _QuadPainter extends CustomPainter {
  final List<Offset> pts;

  _QuadPainter(this.pts);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = MoldScanColors.accentAlt
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawPath(Path()..addPolygon(pts, true), p);
  }

  @override
  bool shouldRepaint(_QuadPainter old) => true;
}
