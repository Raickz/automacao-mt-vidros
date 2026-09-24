import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../services/mold_board_pdf_builder.dart';
import 'mold_capture_screen.dart';

class MoldScanKitScreen extends StatefulWidget {
  const MoldScanKitScreen({super.key});

  @override
  State<MoldScanKitScreen> createState() => _MoldScanKitScreenState();
}

class _MoldScanKitScreenState extends State<MoldScanKitScreen> {
  bool _generating = false;

  Future<void> _generateAndShare() async {
    setState(() => _generating = true);
    try {
      final bytes = await MoldBoardPdfBuilder.buildBytes();
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/quadro_referencia_molde.pdf');
      await file.writeAsBytes(bytes);
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], text: 'Quadro de referência MT Vidros'),
      );
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  void _continueToCapture() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const MoldCaptureScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Digitalizar molde')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Use esta ferramenta quando um cliente trouxer um molde físico '
            '(papelão, MDF, formato irregular) para enviar direto para a mesa '
            'de corte. Imprima o quadro de referência, coloque o molde em cima '
            'dele e tire uma foto — o app digitaliza o contorno automaticamente '
            'e gera um DXF pronto para o corte.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          Card(
            color: const Color(0xFFFFF3CD),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'Imprima em tamanho real (100%), nunca "ajustar à página". '
                'Use boa iluminação e evite sombras fortes sobre o quadro.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _generating ? null : _generateAndShare,
            icon: const Icon(Icons.picture_as_pdf),
            label: Text(_generating ? 'Gerando...' : 'Gerar e compartilhar quadro de referência'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _continueToCapture,
            icon: const Icon(Icons.camera_alt),
            label: const Text('Já imprimi o quadro — continuar'),
          ),
        ],
      ),
    );
  }
}
