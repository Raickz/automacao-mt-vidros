import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/piece_type.dart';
import '../services/marker_kit_pdf_builder.dart';
import 'marker_capture_screen.dart';

class _SizePreset {
  final String label;
  final double sizeMm;
  const _SizePreset(this.label, this.sizeMm);
}

const _presets = [
  _SizePreset('Pequeno (60mm) — box, guarda-corpo', 60),
  _SizePreset('Médio (100mm) — porta, janela', 100),
  _SizePreset('Grande (150mm) — fachada', 150),
];

class MarkerKitScreen extends StatefulWidget {
  final PieceType pieceType;

  const MarkerKitScreen({super.key, required this.pieceType});

  @override
  State<MarkerKitScreen> createState() => _MarkerKitScreenState();
}

class _MarkerKitScreenState extends State<MarkerKitScreen> {
  late double _selectedSize = _defaultSizeFor(widget.pieceType);
  bool _generating = false;

  static double _defaultSizeFor(PieceType type) {
    switch (type) {
      case PieceType.box2Folhas:
      case PieceType.box3Folhas:
      case PieceType.guardaCorpo:
        return 60;
      case PieceType.fachada:
        return 150;
      default:
        return 100;
    }
  }

  Future<void> _generateAndShare() async {
    setState(() => _generating = true);
    try {
      final bytes = await MarkerKitPdfBuilder.buildBytes(sizeMm: _selectedSize);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/kit_marcadores_${_selectedSize.toStringAsFixed(0)}mm.pdf');
      await file.writeAsBytes(bytes);
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], text: 'Kit de marcadores MT Vidros'),
      );
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  void _continueToCapture() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MarkerCaptureScreen(pieceType: widget.pieceType),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Kit de marcadores QR')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Imprima 4 marcadores idênticos, cole um em cada canto do vão '
            '(centro do QR sobre o canto físico) e depois tire uma única foto '
            'com os 4 visíveis. Esse método funciona bem mesmo em vidro e espelho, '
            'porque não depende de rastrear a cena, só de detectar os marcadores.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          Text('Tamanho do marcador', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final preset in _presets)
                ChoiceChip(
                  label: Text(preset.label),
                  selected: _selectedSize == preset.sizeMm,
                  onSelected: (_) => setState(() => _selectedSize = preset.sizeMm),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Card(
            color: const Color(0xFFFFF3CD),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'Ao imprimir, use "tamanho real / 100%" — nunca "ajustar à página". '
                'O PDF inclui uma régua de calibração de 100mm: confira com uma régua '
                'comum antes de usar os marcadores pela primeira vez.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _generating ? null : _generateAndShare,
            icon: const Icon(Icons.picture_as_pdf),
            label: Text(_generating ? 'Gerando...' : 'Gerar e compartilhar PDF do kit'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _continueToCapture,
            icon: const Icon(Icons.camera_alt),
            label: const Text('Já imprimi e colei os marcadores — continuar'),
          ),
        ],
      ),
    );
  }
}
