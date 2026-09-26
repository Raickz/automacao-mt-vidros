import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../measurement/services/homography.dart';
import '../services/dxf_writer.dart';
import '../services/mold_board_pdf_builder.dart';
import '../services/mold_scan_service_web.dart';
import '../services/web_download.dart';
import '../theme/mold_scan_colors.dart';
import '../theme/mold_scan_theme.dart';
import '../widgets/section_card.dart';
import '../widgets/step_nav.dart';

class MoldScanKitScreen extends StatefulWidget {
  const MoldScanKitScreen({super.key});

  @override
  State<MoldScanKitScreen> createState() => _MoldScanKitScreenState();
}

class _MoldScanKitScreenState extends State<MoldScanKitScreen> {
  Uint8List? _selectedBytes;
  bool _processing = false;
  bool _generatingBoard = false;
  String? _error;
  List<Point2D>? _contour;

  final _nameController = TextEditingController(text: 'Molde 01');
  final _materialController = TextEditingController();
  final _thicknessController = TextEditingController(text: '4');
  final _instructionsController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _materialController.dispose();
    _thicknessController.dispose();
    _instructionsController.dispose();
    super.dispose();
  }

  Future<void> _downloadBoard() async {
    setState(() => _generatingBoard = true);
    try {
      final bytes = await MoldBoardPdfBuilder.buildBytes();
      downloadBytes(bytes, 'quadro_referencia_molde.pdf', 'application/pdf');
    } finally {
      if (mounted) setState(() => _generatingBoard = false);
    }
  }

  Future<void> _pickAndProcess() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    final bytes = await picked.readAsBytes();
    setState(() {
      _selectedBytes = bytes;
      _processing = true;
      _error = null;
      _contour = null;
    });

    try {
      final contour = await MoldScanService().scanContourFromBytes(bytes);
      if (!mounted) return;
      setState(() {
        _contour = contour;
        _processing = false;
      });
    } on MoldScanException catch (e) {
      setState(() {
        _error = e.message;
        _processing = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Não foi possível processar a imagem. Tente outra foto.';
        _processing = false;
      });
    }
  }

  void _downloadDxf() {
    final contour = _contour;
    if (contour == null) return;
    final dxf = DxfWriter.write(contour);
    final safeName = _nameController.text.trim().isEmpty
        ? 'molde'
        : _nameController.text.trim().replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    downloadBytes(dxf.codeUnits, '$safeName.dxf', 'application/dxf');
  }

  double _boundingWidthMm(List<Point2D> contour) {
    final xs = contour.map((p) => p.x);
    return xs.reduce((a, b) => a > b ? a : b) - xs.reduce((a, b) => a < b ? a : b);
  }

  double _boundingHeightMm(List<Point2D> contour) {
    final ys = contour.map((p) => p.y);
    return ys.reduce((a, b) => a > b ? a : b) - ys.reduce((a, b) => a < b ? a : b);
  }

  int get _currentStepIndex {
    if (_contour != null) return 2;
    if (_selectedBytes != null) return 1;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final contour = _contour;

    return Theme(
      data: MoldScanTheme.dark(),
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.asset('assets/images/logo.png', width: 30, height: 30, fit: BoxFit.cover),
              ),
              const SizedBox(width: 10),
              const Text('Marabá Temper — Digitalização de Moldes', style: TextStyle(fontSize: 16)),
            ],
          ),
          bottom: MoldScanStepNav(currentIndex: _currentStepIndex),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 880),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text(
                  'Do molde físico ao DXF industrial',
                  style: TextStyle(
                    color: MoldScanColors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Fotografe o molde sobre o quadro de referência, o app corrige a '
                  'perspectiva e extrai um contorno pronto para a mesa de corte CNC.',
                  style: TextStyle(color: MoldScanColors.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 24),
                SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SectionHeading(
                        icon: Icons.picture_as_pdf_outlined,
                        title: 'Quadro de referência',
                        subtitle: 'Imprima em tamanho real (100%) e coloque o molde em cima dele.',
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: _generatingBoard ? null : _downloadBoard,
                        icon: const Icon(Icons.download_outlined, size: 18),
                        label: Text(_generatingBoard ? 'Gerando...' : 'Baixar quadro de referência (PDF)'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SectionHeading(
                        icon: Icons.cloud_upload_outlined,
                        title: 'Upload de foto',
                        subtitle: 'Envie a foto do quadro com o molde em cima.',
                      ),
                      const SizedBox(height: 16),
                      _UploadDropzone(
                        selectedBytes: _selectedBytes,
                        processing: _processing,
                        onTap: _processing ? null : _pickAndProcess,
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: MoldScanColors.danger.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: MoldScanColors.danger.withValues(alpha: 0.4)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline, color: MoldScanColors.danger, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(_error!, style: const TextStyle(color: MoldScanColors.textPrimary)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (contour != null) ...[
                  const SizedBox(height: 16),
                  SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SectionHeading(
                          icon: Icons.auto_fix_high_outlined,
                          title: 'Vetorização & DXF',
                          subtitle: 'Confira o contorno detectado e exporte o arquivo de corte.',
                        ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            _StatChip(label: 'Pontos no contorno', value: '${contour.length}'),
                            _StatChip(
                              label: 'Largura aprox.',
                              value: '${(_boundingWidthMm(contour) / 10).toStringAsFixed(1)} cm',
                            ),
                            _StatChip(
                              label: 'Altura aprox.',
                              value: '${(_boundingHeightMm(contour) / 10).toStringAsFixed(1)} cm',
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'Dados do projeto',
                          style: TextStyle(color: MoldScanColors.textPrimary, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 12),
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
                        const SizedBox(height: 20),
                        FilledButton.icon(
                          onPressed: _downloadDxf,
                          icon: const Icon(Icons.download, size: 18),
                          label: const Text('Baixar DXF'),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UploadDropzone extends StatelessWidget {
  final Uint8List? selectedBytes;
  final bool processing;
  final VoidCallback? onTap;

  const _UploadDropzone({required this.selectedBytes, required this.processing, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: MoldScanColors.surfaceLight,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: MoldScanColors.border, width: 1.2),
        ),
        child: Column(
          children: [
            if (selectedBytes != null) ...[
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(selectedBytes!, fit: BoxFit.contain),
                ),
              ),
              const SizedBox(height: 16),
            ] else ...[
              const Icon(Icons.image_outlined, size: 40, color: MoldScanColors.textSecondary),
              const SizedBox(height: 12),
            ],
            if (processing) ...[
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              const SizedBox(height: 12),
              const Text('Processando...', style: TextStyle(color: MoldScanColors.textSecondary)),
            ] else
              FilledButton.icon(
                onPressed: onTap,
                icon: const Icon(Icons.upload_outlined, size: 18),
                label: Text(selectedBytes == null ? 'Selecionar foto' : 'Selecionar outra foto'),
              ),
          ],
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;

  const _StatChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: MoldScanColors.surfaceLight,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: MoldScanColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(color: MoldScanColors.textSecondary, fontSize: 11)),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              color: MoldScanColors.accent,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
