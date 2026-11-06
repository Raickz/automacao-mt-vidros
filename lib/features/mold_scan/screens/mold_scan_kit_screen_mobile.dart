import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/board_geometry.dart';
import '../services/mold_board_pdf_builder.dart';
import '../theme/mold_scan_colors.dart';
import '../theme/mold_scan_theme.dart';
import '../widgets/mold_ui.dart';
import 'mold_capture_screen.dart';

class MoldScanKitScreen extends StatefulWidget {
  const MoldScanKitScreen({super.key});

  @override
  State<MoldScanKitScreen> createState() => _MoldScanKitScreenState();
}

class _MoldScanKitScreenState extends State<MoldScanKitScreen> {
  bool _generating = false;
  String? _error;
  final _boardWidthController = TextEditingController(text: '250');
  final _boardHeightController = TextEditingController(text: '150');

  @override
  void dispose() {
    _boardWidthController.dispose();
    _boardHeightController.dispose();
    super.dispose();
  }

  Future<void> _generateAndShare() async {
    setState(() => _generating = true);
    try {
      final bytes = await MoldBoardPdfBuilder.buildBytes();
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/marcadores_quadro_referencia.pdf');
      await file.writeAsBytes(bytes);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: 'Marcadores do quadro de referência — MT Vidros',
        ),
      );
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  void _continueToCapture() {
    final board = BoardGeometry.fromCentimeters(
      _boardWidthController.text,
      _boardHeightController.text,
    );
    if (board == null) {
      setState(() => _error = BoardGeometry.sizeHint);
      return;
    }
    setState(() => _error = null);
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => MoldCaptureScreen(board: board)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 36),
              children: [
                const MoldTopBar(),
                const SizedBox(height: 32),
                Text(
                  'Do molde ao arquivo de corte',
                  style: MoldScanType.headline(40),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Fotografe o molde sobre o quadro de referência. O app mede o contorno '
                  'e gera o DXF para a mesa de corte.',
                  style: TextStyle(
                    color: MoldScanColors.textSecondary,
                    fontSize: 17,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 28),
                Text('Quadro de referência', style: MoldScanType.headline(24)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _boardWidthController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Largura (cm)',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _boardHeightController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Altura (cm)',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Medidas reais do quadro como ele aparece na foto: a largura é o lado horizontal. '
                  'O quadro da loja tem 250 × 150 cm.',
                  style: TextStyle(
                    color: MoldScanColors.textSecondary,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Notice(
                    color: MoldScanColors.danger,
                    icon: Icons.error_outline,
                    messages: [_error!],
                  ),
                ],
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _continueToCapture,
                    icon: const Icon(Icons.photo_camera_outlined, size: 22),
                    label: const Text('Fotografar molde'),
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Fique a 2-3 m, de frente para o quadro, com os 4 marcadores inteiros na foto.',
                  style: TextStyle(
                    color: MoldScanColors.textSecondary,
                    fontSize: 14.5,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 32),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: MoldScanColors.surface,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: MoldScanColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Marcadores do quadro',
                        style: MoldScanType.headline(24),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'São impressos uma única vez: 4 folhas A4, uma por marcador. Imprima a 100%, '
                        'recorte na linha tracejada e cole nos cantos do quadro, com a borda do papel '
                        'a 50 mm das bordas.',
                        style: TextStyle(
                          color: MoldScanColors.textSecondary,
                          fontSize: 14.5,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 14),
                      OutlinedButton.icon(
                        onPressed: _generating ? null : _generateAndShare,
                        icon: const Icon(
                          Icons.picture_as_pdf_outlined,
                          size: 20,
                        ),
                        label: Text(
                          _generating
                              ? 'Gerando...'
                              : 'Gerar e compartilhar PDF',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 36),
                Text('Como funciona', style: MoldScanType.headline(28)),
                const SizedBox(height: 16),
                const HowItWorks(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
