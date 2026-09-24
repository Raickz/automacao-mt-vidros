import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../measurement/services/homography.dart';
import '../models/mold_shape.dart';
import '../services/dxf_writer.dart';

class MoldResultScreen extends StatefulWidget {
  final List<Point2D> contourMm;

  const MoldResultScreen({super.key, required this.contourMm});

  @override
  State<MoldResultScreen> createState() => _MoldResultScreenState();
}

class _MoldResultScreenState extends State<MoldResultScreen> {
  final _nameController = TextEditingController(text: 'Molde 01');
  final _materialController = TextEditingController();
  final _thicknessController = TextEditingController(text: '4');
  final _instructionsController = TextEditingController();
  bool _exporting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _materialController.dispose();
    _thicknessController.dispose();
    _instructionsController.dispose();
    super.dispose();
  }

  double get _boundingWidthMm {
    final xs = widget.contourMm.map((p) => p.x);
    return xs.reduce((a, b) => a > b ? a : b) - xs.reduce((a, b) => a < b ? a : b);
  }

  double get _boundingHeightMm {
    final ys = widget.contourMm.map((p) => p.y);
    return ys.reduce((a, b) => a > b ? a : b) - ys.reduce((a, b) => a < b ? a : b);
  }

  Future<void> _exportDxf() async {
    setState(() => _exporting = true);
    try {
      final shape = MoldShape(
        name: _nameController.text.trim().isEmpty ? 'Molde' : _nameController.text.trim(),
        material: _materialController.text.trim(),
        thicknessMm: double.tryParse(_thicknessController.text.replaceAll(',', '.')) ?? 0,
        cuttingInstructions: _instructionsController.text.trim(),
        contourMm: widget.contourMm,
      );

      final dxfText = DxfWriter.write(shape.contourMm);
      final dir = await getTemporaryDirectory();
      final safeName = shape.name.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
      final file = File('${dir.path}/$safeName.dxf');
      await file.writeAsString(dxfText);

      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], text: 'Molde MT Vidros — ${shape.name}'),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Molde digitalizado')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Contorno detectado', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text('${widget.contourMm.length} pontos no contorno'),
                  Text('Largura aprox.: ${(_boundingWidthMm / 10).toStringAsFixed(1)} cm'),
                  Text('Altura aprox.: ${(_boundingHeightMm / 10).toStringAsFixed(1)} cm'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Nome do projeto'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _materialController,
            decoration: const InputDecoration(labelText: 'Material (ex: vidro, espelho, MDF)'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _thicknessController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Espessura (mm)'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _instructionsController,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Instruções de corte',
              hintText: 'ex: cortar com fresa 6mm, atenção às quinas internas',
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _exporting ? null : _exportDxf,
            icon: const Icon(Icons.download),
            label: Text(_exporting ? 'Gerando...' : 'Exportar e compartilhar DXF'),
          ),
        ],
      ),
    );
  }
}
