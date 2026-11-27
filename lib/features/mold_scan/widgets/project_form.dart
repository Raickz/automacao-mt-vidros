import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/cut_job.dart';
import '../services/dxf_writer.dart';
import '../services/homography.dart';
import '../services/number_input.dart';
import '../theme/mold_scan_colors.dart';
import '../theme/mold_scan_theme.dart';

/// What the worker types about the piece. It travels with the DXF — as
/// comment lines inside the file and in the file name — so the operator at
/// the cutting table sees it; typing it must never be a no-op.
class ProjectData {
  final name = TextEditingController(text: 'Molde 01');
  final order = TextEditingController();
  final material = TextEditingController();
  final thickness = TextEditingController(text: '4');
  final instructions = TextEditingController();
  final slack = TextEditingController(text: '100');

  double? get thicknessMm => parseDecimal(thickness.text);

  /// Total extra glass of the order rectangle (width and height), in mm.
  double get slackMm {
    final s = parseDecimal(slack.text);
    return s == null || s < 0 || s > 1000 ? CutJob.defaultSlackMm : s;
  }

  String dxf(List<Point2D> contour) {
    final t = thicknessMm;
    final xs = contour.map((p) => p.x), ys = contour.map((p) => p.y);
    final w = xs.reduce(max) - xs.reduce(min);
    final h = ys.reduce(max) - ys.reduce(min);
    return DxfWriter.write(
      contour,
      padMm: slackMm / 2,
      comments: [
        if (order.text.trim().isNotEmpty) 'Pedido: ${order.text.trim()}',
        'Projeto: ${name.text.trim()}',
        ...orderRectComments(w, h, slackMm),
        if (material.text.trim().isNotEmpty)
          'Material: ${material.text.trim()}',
        if (t != null && t > 0) 'Espessura do molde: $t mm',
        if (instructions.text.trim().isNotEmpty)
          'Instrucoes de corte: ${instructions.text.trim()}',
      ],
    );
  }

  String get fileName => DxfWriter.fileName(
    name: name.text,
    order: order.text,
    material: material.text,
    thicknessMm: thicknessMm,
  );

  void dispose() {
    name.dispose();
    order.dispose();
    slack.dispose();
    material.dispose();
    thickness.dispose();
    instructions.dispose();
  }
}

class ProjectFields extends StatelessWidget {
  final ProjectData data;

  const ProjectFields({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Dados do projeto', style: MoldScanType.headline(24)),
        const SizedBox(height: 14),
        OrderField(controller: data.order),
        const SizedBox(height: 12),
        TextField(
          controller: data.name,
          decoration: const InputDecoration(labelText: 'Nome do projeto'),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              flex: 3,
              child: TextField(
                controller: data.material,
                decoration: const InputDecoration(
                  labelText: 'Material',
                  hintText: 'vidro, espelho, MDF',
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: TextField(
                controller: data.thickness,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Espessura do molde (mm)',
                  helperText: 'Do molde, não do vidro',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: data.instructions,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Instruções de corte',
            hintText: 'ex: fresa 6 mm, cuidado nas quinas internas',
          ),
        ),
      ],
    );
  }
}

/// DXF comment lines saying which glass rectangle to reserve in the order
/// and that the file's origin is that rectangle's corner.
List<String> orderRectComments(double w, double h, double slackMm) {
  final (rw, rh) = CutJob.orderRect(w, h, slackMm);
  final side = (slackMm / 2).toStringAsFixed(slackMm % 2 == 0 ? 0 : 1);
  return [
    'Retangulo do pedido: $rw x $rh mm (folga de $side mm por lado)',
    'Origem 0,0 no canto do retangulo do pedido',
  ];
}

/// The WGglass order number: it goes in the file name, the DXF, the PDF and
/// the label, so the operator matches the cut with the order.
class OrderField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String>? onChanged;

  const OrderField({super.key, required this.controller, this.onChanged});

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    keyboardType: TextInputType.number,
    onChanged: onChanged,
    decoration: const InputDecoration(
      labelText: 'Nº do pedido (WGglass)',
      hintText: 'ex.: 130918',
      prefixIcon: Icon(Icons.receipt_long_outlined),
    ),
  );
}

/// The rectangle the seller types in the order (piece + slack), with the
/// slack editable and a button to copy "L x A".
class OrderRectBox extends StatelessWidget {
  final double widthMm;
  final double heightMm;
  final TextEditingController slack;
  final double slackMm;
  final ValueChanged<String> onSlackChanged;

  const OrderRectBox({
    super.key,
    required this.widthMm,
    required this.heightMm,
    required this.slack,
    required this.slackMm,
    required this.onSlackChanged,
  });

  @override
  Widget build(BuildContext context) {
    final (rw, rh) = CutJob.orderRect(widthMm, heightMm, slackMm);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 14),
      decoration: BoxDecoration(
        color: MoldScanColors.surface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: MoldScanColors.accentAlt),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Retângulo para o pedido (L × A)',
                      style: TextStyle(
                        color: MoldScanColors.textSecondary,
                        fontSize: 13.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text('$rw × $rh mm', style: MoldScanType.readout(26)),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Copiar medidas',
                icon: const Icon(Icons.copy, color: MoldScanColors.accentAlt),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: '$rw x $rh'));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Copiado: $rw x $rh')),
                    );
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: 240,
            child: TextField(
              controller: slack,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: onSlackChanged,
              decoration: const InputDecoration(
                labelText: 'Folga total (mm)',
                helperText: '100 = 5 cm em cada lado',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
