import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../services/homography.dart';
import '../theme/mold_scan_colors.dart';
import '../theme/mold_scan_theme.dart';
import '../widgets/mold_ui.dart';
import '../widgets/project_form.dart';

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
  final _project = ProjectData();
  bool _exporting = false;

  @override
  void dispose() {
    _project.dispose();
    super.dispose();
  }

  Future<void> _exportDxf() async {
    setState(() => _exporting = true);
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/${_project.fileName}');
      await file.writeAsString(_project.dxf(widget.contourMm));

      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], text: 'Molde MT Vidros — ${_project.name.text.trim()}'),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                MeasurementSummary(contour: widget.contourMm, warnings: widget.warnings),
                const SizedBox(height: 28),
                ProjectFields(data: _project),
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
    );
  }
}
