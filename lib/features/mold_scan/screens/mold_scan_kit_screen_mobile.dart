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
            'de corte. Coloque o molde sobre o quadro fixo grande da loja, tire '
            'uma foto de 2-3m de distância — o app digitaliza o contorno '
            'automaticamente e gera um DXF pronto para o corte.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          Card(
            color: const Color(0xFFFFF3CD),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'Os marcadores dos 4 cantos são impressos uma única vez (cada um em '
                '4 folhas A4 para recortar e colar juntas, tamanho real) e fixados no '
                'quadro — não precisa reimprimir a cada medição.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _generating ? null : _generateAndShare,
            icon: const Icon(Icons.picture_as_pdf),
            label: Text(_generating ? 'Gerando...' : 'Gerar e compartilhar marcadores (PDF)'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _continueToCapture,
            icon: const Icon(Icons.camera_alt),
            label: const Text('Marcadores já fixados — continuar'),
          ),
        ],
      ),
    );
  }
}
