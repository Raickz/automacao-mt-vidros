import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../measurement/services/homography.dart';
import '../services/dxf_writer.dart';
import '../services/mold_board_pdf_builder.dart';
import '../services/mold_scan_service_web.dart';
import '../services/web_download.dart';

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

  @override
  Widget build(BuildContext context) {
    final contour = _contour;

    return Scaffold(
      appBar: AppBar(title: const Text('Digitalizar molde (teste web)')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Passo 1 — baixe o quadro de referência, imprima em tamanho real (100%) '
            'e coloque o molde em cima dele.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _generatingBoard ? null : _downloadBoard,
            icon: const Icon(Icons.picture_as_pdf),
            label: Text(_generatingBoard ? 'Gerando...' : 'Baixar quadro de referência (PDF)'),
          ),
          const Divider(height: 32),
          Text(
            'Passo 2 — tire uma foto do quadro com o molde em cima e envie aqui.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _processing ? null : _pickAndProcess,
            icon: const Icon(Icons.upload),
            label: Text(_processing ? 'Processando...' : 'Selecionar foto'),
          ),
          if (_selectedBytes != null) ...[
            const SizedBox(height: 16),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: Image.memory(_selectedBytes!, fit: BoxFit.contain),
            ),
          ],
          if (_processing) ...[
            const SizedBox(height: 16),
            const Center(child: CircularProgressIndicator()),
          ],
          if (_error != null) ...[
            const SizedBox(height: 16),
            Card(
              color: const Color(0xFFFDECEA),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(_error!),
              ),
            ),
          ],
          if (contour != null) ...[
            const Divider(height: 32),
            Text('Passo 3 — conferir e exportar', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('${contour.length} pontos no contorno detectado'),
            Text('Largura aprox.: ${(_boundingWidthMm(contour) / 10).toStringAsFixed(1)} cm'),
            Text('Altura aprox.: ${(_boundingHeightMm(contour) / 10).toStringAsFixed(1)} cm'),
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
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _downloadDxf,
              icon: const Icon(Icons.download),
              label: const Text('Baixar DXF'),
            ),
          ],
        ],
      ),
    );
  }
}
