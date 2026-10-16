import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../measurement/services/homography.dart';
import '../models/mold_shape.dart';
import '../services/dxf_writer.dart';
import '../theme/mold_scan_colors.dart';
import '../theme/mold_scan_theme.dart';
import '../widgets/mold_ui.dart';

class MoldResultScreen extends StatefulWidget {
  final List<Point2D> contourMm;
  final List<String> warnings;
  final Uint8List? previewPng;

  const MoldResultScreen({
    super.key,
    required this.contourMm,
    this.warnings = const [],
    this.previewPng,
  });

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

  double _extent(double Function(Point2D) f) {
    final v = widget.contourMm.map(f);
    return v.reduce(max) - v.reduce(min);
  }

  String _cm(double mm) => (mm / 10).toStringAsFixed(1).replaceAll('.', ',');

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
    return Theme(
      data: MoldScanTheme.dark(),
      child: Scaffold(
        appBar: AppBar(title: Text('Molde digitalizado', style: MoldScanType.headline(24))),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 36),
                children: [
                  if (widget.previewPng != null) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Image.memory(widget.previewPng!, fit: BoxFit.contain),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 9, right: 10),
                          child: Container(width: 26, height: 3, color: MoldScanColors.cut),
                        ),
                        const Expanded(
                          child: Text(
                            'Contorno medido. Ele deve acompanhar a borda externa do molde, de ponta a '
                            'ponta. Se não acompanhar, refaça a foto.',
                            style: TextStyle(color: MoldScanColors.textSecondary, fontSize: 14.5, height: 1.4),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                  ],
                  Wrap(
                    spacing: 40,
                    runSpacing: 20,
                    children: [
                      Readout(label: 'Largura', value: _cm(_extent((p) => p.x)), unit: 'cm'),
                      Readout(label: 'Altura', value: _cm(_extent((p) => p.y)), unit: 'cm'),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Medidas de borda a borda do contorno, que tem ${widget.contourMm.length} vértices.',
                    style: const TextStyle(color: MoldScanColors.textSecondary, fontSize: 14.5),
                  ),
                  if (widget.warnings.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Notice(
                      color: MoldScanColors.warning,
                      icon: Icons.warning_amber_rounded,
                      messages: widget.warnings,
                    ),
                  ],
                  const SizedBox(height: 28),
                  Text('Dados do projeto', style: MoldScanType.headline(24)),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(labelText: 'Nome do projeto'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _materialController,
                    decoration: const InputDecoration(labelText: 'Material', hintText: 'vidro, espelho, MDF'),
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
                      hintText: 'ex: fresa 6 mm, cuidado nas quinas internas',
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _exporting ? null : _exportDxf,
                    icon: const Icon(Icons.ios_share, size: 20),
                    label: Text(_exporting ? 'Gerando...' : 'Compartilhar DXF'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
