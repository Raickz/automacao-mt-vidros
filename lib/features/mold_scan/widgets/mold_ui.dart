import 'dart:math';

import 'package:flutter/material.dart';

import '../services/homography.dart';
import '../theme/mold_scan_colors.dart';
import '../theme/mold_scan_theme.dart';

/// The Marabá Temper logo on its own navy plate (the image is full-bleed
/// navy), used in the top bar.
class MtLogoPlate extends StatelessWidget {
  final double height;

  const MtLogoPlate({super.key, this.height = 44});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Marabá Temper, indústria de vidros',
      image: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Image.asset(
          'assets/images/logo.png',
          height: height,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}

/// Top bar of the scanner: logo plate and tool name. No navigation — this
/// is the only tool in the app.
class MoldTopBar extends StatelessWidget {
  const MoldTopBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const MtLogoPlate(height: 46),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            'Digitalizar molde',
            style: MoldScanType.headline(26),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// The reference board as a drafting surface: a faint cutting-table grid and
/// registration marks at the four corners, where the QR markers are glued on
/// the real board. [aspectRatio] follows the board's own proportions.
class BoardPanel extends StatelessWidget {
  final double aspectRatio;
  final Widget child;

  const BoardPanel({super.key, required this.aspectRatio, required this.child});

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: aspectRatio,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFF01202F),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: MoldScanColors.border),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: Stack(
            fit: StackFit.expand,
            children: [
              CustomPaint(painter: _BoardMarksPainter()),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _BoardMarksPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = MoldScanColors.accentAlt.withValues(alpha: 0.05)
      ..strokeWidth = 1;
    const step = 28.0;
    for (var x = step; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (var y = step; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    final mark = Paint()
      ..color = MoldScanColors.accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.square;
    const inset = 12.0, len = 22.0;
    final w = size.width, h = size.height;
    for (final c in [
      (Offset(inset, inset), 1.0, 1.0),
      (Offset(w - inset, inset), -1.0, 1.0),
      (Offset(w - inset, h - inset), -1.0, -1.0),
      (Offset(inset, h - inset), 1.0, -1.0),
    ]) {
      final o = c.$1;
      canvas.drawLine(o, Offset(o.dx + c.$2 * len, o.dy), mark);
      canvas.drawLine(o, Offset(o.dx, o.dy + c.$3 * len), mark);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// The three real stages of one scan, as a progress rail.
class StageRail extends StatelessWidget {
  final int current;

  const StageRail({super.key, required this.current});

  static const _labels = ['Foto', 'Contorno', 'DXF'];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < _labels.length; i++)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: i == _labels.length - 1 ? 0 : 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 3,
                    color: i <= current
                        ? MoldScanColors.accent
                        : MoldScanColors.border,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${i + 1}  ${_labels[i]}',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: i == current
                          ? FontWeight.w600
                          : FontWeight.w500,
                      color: i <= current
                          ? MoldScanColors.textPrimary
                          : MoldScanColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// A measurement shown like a dimension on a technical drawing: a big
/// number with a dimension line under it.
class Readout extends StatelessWidget {
  final String label;
  final String value;
  final String unit;

  const Readout({
    super.key,
    required this.label,
    required this.value,
    required this.unit,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label: $value $unit',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: MoldScanColors.textSecondary,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(value, style: MoldScanType.readout(60)),
              const SizedBox(width: 6),
              Text(
                unit,
                style: MoldScanType.headline(26)
                    .copyWith(color: MoldScanColors.accentAlt),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const SizedBox(
            width: 170,
            height: 10,
            child: CustomPaint(painter: _DimensionLinePainter()),
          ),
        ],
      ),
    );
  }
}

class _DimensionLinePainter extends CustomPainter {
  const _DimensionLinePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = MoldScanColors.accent
      ..strokeWidth = 1.6;
    final y = size.height / 2;
    canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    canvas.drawLine(Offset(0, 0), Offset(0, size.height), p);
    canvas.drawLine(Offset(size.width, 0), Offset(size.width, size.height), p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// An inline message: a colored bar on the left, tinted background. Used for
/// errors (what went wrong and what to do) and quality warnings.
class Notice extends StatelessWidget {
  final Color color;
  final IconData icon;
  final List<String> messages;

  const Notice({
    super.key,
    required this.color,
    required this.icon,
    required this.messages,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final m in messages)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, color: color, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      m,
                      style: const TextStyle(
                        color: MoldScanColors.textPrimary,
                        fontSize: 15,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The 4 steps of the whole workflow. A real sequence, so numbered.
class HowItWorks extends StatelessWidget {
  const HowItWorks({super.key});

  static const _steps = [
    (
      'Preparar o quadro',
      'Quadro azul fixo com 4 marcadores QR nos cantos. Feito uma única vez.',
    ),
    (
      'Fotografar',
      'Molde sobre o quadro, de 2 a 3 m, com os 4 marcadores na foto.',
    ),
    (
      'Medir',
      'O sistema corrige a perspectiva e traça o contorno em milímetros.',
    ),
    ('Cortar', 'Confira as medidas e baixe o DXF para a mesa de corte CNC.'),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth >= 720;
        final tiles = [
          for (var i = 0; i < _steps.length; i++)
            _StepTile(number: i + 1, title: _steps[i].$1, text: _steps[i].$2),
        ];
        if (wide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < tiles.length; i++) ...[
                Expanded(child: tiles[i]),
                if (i != tiles.length - 1) const SizedBox(width: 20),
              ],
            ],
          );
        }
        return Column(
          children: [
            for (var i = 0; i < tiles.length; i++) ...[
              tiles[i],
              if (i != tiles.length - 1) const SizedBox(height: 14),
            ],
          ],
        );
      },
    );
  }
}

class _StepTile extends StatelessWidget {
  final int number;
  final String title;
  final String text;

  const _StepTile({
    required this.number,
    required this.title,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(top: 12),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: MoldScanColors.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 34,
            child: Text(
              '$number',
              style: MoldScanType.headline(32)
                  .copyWith(color: MoldScanColors.accent),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  text,
                  style: const TextStyle(
                    color: MoldScanColors.textSecondary,
                    fontSize: 14.5,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Width and height of the contour as big readouts, how many vertices it has
/// and any quality warnings from the scan.
class MeasurementSummary extends StatelessWidget {
  final List<Point2D> contour;
  final List<String> warnings;
  final String? note;

  const MeasurementSummary({
    super.key,
    required this.contour,
    required this.warnings,
    this.note,
  });

  static double _extent(List<Point2D> pts, double Function(Point2D) f) {
    final v = pts.map(f);
    return v.reduce(max) - v.reduce(min);
  }

  static String _cm(double mm) =>
      (mm / 10).toStringAsFixed(1).replaceAll('.', ',');

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 40,
          runSpacing: 22,
          children: [
            Readout(
              label: 'Largura',
              value: _cm(_extent(contour, (p) => p.x)),
              unit: 'cm',
            ),
            Readout(
              label: 'Altura',
              value: _cm(_extent(contour, (p) => p.y)),
              unit: 'cm',
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Medidas de borda a borda do contorno, que tem ${contour.length} vértices.',
          style: const TextStyle(
            color: MoldScanColors.textSecondary,
            fontSize: 14.5,
          ),
        ),
        if (note != null) ...[
          const SizedBox(height: 8),
          Text(
            note!,
            style: const TextStyle(
              color: MoldScanColors.textSecondary,
              fontSize: 14.5,
              height: 1.4,
            ),
          ),
        ],
        if (warnings.isNotEmpty) ...[
          const SizedBox(height: 16),
          Notice(
            color: MoldScanColors.warning,
            icon: Icons.warning_amber_rounded,
            messages: warnings,
          ),
        ],
      ],
    );
  }
}
