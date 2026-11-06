import 'package:flutter/material.dart';

import '../services/dxf_writer.dart';
import '../services/homography.dart';
import '../theme/mold_scan_theme.dart';

/// What the worker types about the piece. It travels with the DXF — as
/// comment lines inside the file and in the file name — so the operator at
/// the cutting table sees it; typing it must never be a no-op.
class ProjectData {
  final name = TextEditingController(text: 'Molde 01');
  final material = TextEditingController();
  final thickness = TextEditingController(text: '4');
  final instructions = TextEditingController();

  double? get thicknessMm =>
      double.tryParse(thickness.text.trim().replaceAll(',', '.'));

  String dxf(List<Point2D> contour) {
    final t = thicknessMm;
    return DxfWriter.write(
      contour,
      comments: [
        'Projeto: ${name.text.trim()}',
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
    material: material.text,
    thicknessMm: thicknessMm,
  );

  void dispose() {
    name.dispose();
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
