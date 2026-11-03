import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/board_geometry.dart';
import '../services/camera_pose.dart';
import '../services/homography.dart';
import '../services/mold_board_pdf_builder.dart';
import '../services/mold_scan_service_web.dart';
import '../services/web_download.dart';
import '../theme/mold_scan_colors.dart';
import '../theme/mold_scan_theme.dart';
import '../widgets/mold_ui.dart';
import '../widgets/project_form.dart';

class MoldScanKitScreen extends StatefulWidget {
  const MoldScanKitScreen({super.key});

  @override
  State<MoldScanKitScreen> createState() => _MoldScanKitScreenState();
}

class _MoldScanKitScreenState extends State<MoldScanKitScreen> {
  Uint8List? _selectedBytes;
  bool _processing = false;
  bool _generatingBoard = false;
  bool _settingsOpen = false;
  String? _error;
  String _stage = 'Processando...';
  List<String> _warnings = const [];
  List<Point2D>? _contour;
  Uint8List? _preview;
  CameraPose? _pose;

  final _project = ProjectData();
  final _boardWidthController = TextEditingController(text: '220');
  final _boardHeightController = TextEditingController(text: '120');

  @override
  void dispose() {
    _project.dispose();
    _boardWidthController.dispose();
    _boardHeightController.dispose();
    super.dispose();
  }

  BoardGeometry? get _typedBoard => BoardGeometry.fromMarkerSpans(
    _boardWidthController.text,
    _boardHeightController.text,
  );

  double get _boardAspect {
    final board = _typedBoard;
    return board == null
        ? 250 / 150
        : (board.widthMm / board.heightMm).clamp(0.6, 2.4);
  }

  BoardGeometry? _readBoard() {
    final board = _typedBoard;
    if (board == null) {
      setState(() {
        _error = BoardGeometry.spanHint;
        _settingsOpen = true;
      });
    }
    return board;
  }

  Future<void> _downloadBoard() async {
    setState(() => _generatingBoard = true);
    try {
      final bytes = await MoldBoardPdfBuilder.buildBytes();
      downloadBytes(
        bytes,
        'marcadores_quadro_referencia.pdf',
        'application/pdf',
      );
    } finally {
      if (mounted) setState(() => _generatingBoard = false);
    }
  }

  Future<void> _pickAndProcess() async {
    final board = _readBoard();
    if (board == null) return;

    // Resizing in the browser (canvas) bakes in the photo's rotation and
    // spares the pure-Dart decoder from 12-50MP originals.
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 3200,
      maxHeight: 3200,
      imageQuality: 95,
    );
    if (picked == null) return;

    final bytes = await picked.readAsBytes();
    setState(() {
      _selectedBytes = bytes;
      _processing = true;
      _stage = 'Processando...';
      _error = null;
      _warnings = const [];
      _contour = null;
      _preview = null;
      _pose = null;
    });
    // Let the progress bar paint before the (UI-thread) processing starts.
    await Future<void>.delayed(const Duration(milliseconds: 80));

    try {
      final result = await MoldScanService().scanContourFromBytes(
        bytes,
        board: board,
        onStage: (stage) async {
          if (mounted) setState(() => _stage = stage);
        },
      );
      if (!mounted) return;
      setState(() {
        _contour = result.contourMm;
        _warnings = result.warnings;
        _preview = result.previewPng;
        _pose = result.cameraPose;
        _processing = false;
      });
    } on MoldScanException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _processing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Não foi possível processar a imagem. Tente outra foto.';
        _processing = false;
      });
    }
  }

  void _downloadDxf() {
    final contour = _contour;
    if (contour == null) return;
    downloadBytes(
      _project.dxf(_shown(contour)).codeUnits,
      _project.fileName,
      'application/dxf',
    );
  }

  /// The mold's top face is closer to the camera than the board, so it looks
  /// bigger; take that off using the thickness typed in the project data.
  List<Point2D> _shown(List<Point2D> contour) =>
      CameraPoseEstimator.correctForThickness(
        contour,
        _pose,
        _project.thicknessMm,
      );

  String _thicknessNote(List<Point2D> raw, List<Point2D> shown) {
    final t = _project.thicknessMm;
    if (t == null || t <= 0) {
      return 'Sem desconto de espessura. Informe a espessura do molde em "Dados do projeto": o topo do molde '
          'fica mais perto da câmera que o quadro e aparece maior.';
    }
    final pose = _pose;
    if (pose == null) {
      return 'Não foi possível estimar a distância da câmera, então a espessura não foi descontada.';
    }
    double span(List<Point2D> pts, double Function(Point2D) f) =>
        pts.map(f).reduce((a, b) => a > b ? a : b) -
        pts.map(f).reduce((a, b) => a < b ? a : b);
    String mm(double v) => v.toStringAsFixed(1).replaceAll('.', ',');
    final dw = span(raw, (p) => p.x) - span(shown, (p) => p.x);
    final dh = span(raw, (p) => p.y) - span(shown, (p) => p.y);
    return 'Descontei a espessura de ${mm(t)} mm (câmera a cerca de ${mm(pose.heightMm / 1000)} m): '
        '${mm(dw)} mm na largura e ${mm(dh)} mm na altura.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1120),
            child: LayoutBuilder(
              builder: (context, c) {
                final wide = c.maxWidth >= 900;
                final pad = wide ? 32.0 : 18.0;
                return ListView(
                  padding: EdgeInsets.fromLTRB(pad, 18, pad, 40),
                  children: [
                    const MoldTopBar(),
                    SizedBox(height: wide ? 40 : 28),
                    _header(wide),
                    const SizedBox(height: 22),
                    StageRail(
                      current: _contour != null
                          ? 2
                          : (_selectedBytes != null ? 1 : 0),
                    ),
                    const SizedBox(height: 22),
                    if (wide)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 7, child: _mesa()),
                          const SizedBox(width: 36),
                          Expanded(flex: 5, child: _sidebar()),
                        ],
                      )
                    else ...[
                      _mesa(),
                      const SizedBox(height: 22),
                      _sidebar(),
                    ],
                    if (_contour == null) ...[
                      SizedBox(height: wide ? 56 : 40),
                      Text('Como funciona', style: MoldScanType.headline(30)),
                      const SizedBox(height: 16),
                      const HowItWorks(),
                    ],
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(bool wide) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Do molde ao arquivo de corte',
          style: MoldScanType.headline(wide ? 56 : 38),
        ),
        const SizedBox(height: 12),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: const Text(
            'Fotografe o molde sobre o quadro de referência. O sistema mede o contorno '
            'e gera o DXF para a mesa de corte.',
            style: TextStyle(
              color: MoldScanColors.textSecondary,
              fontSize: 17,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }

  Widget _mesa() {
    final hasPreview = _preview != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BoardPanel(
          aspectRatio: _boardAspect,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            child: KeyedSubtree(
              key: ValueKey(
                '${_processing}_${hasPreview}_${_selectedBytes != null}',
              ),
              child: _mesaContent(),
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (hasPreview) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 9, right: 10),
                child: Container(
                  width: 26,
                  height: 3,
                  color: MoldScanColors.cut,
                ),
              ),
              const Expanded(
                child: Text(
                  'Contorno medido, sobre a foto vista de cima. Ele deve acompanhar a borda externa do '
                  'molde, de ponta a ponta. Se não acompanhar, as medidas não valem: refaça a foto.',
                  style: TextStyle(
                    color: MoldScanColors.textSecondary,
                    fontSize: 14.5,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: _processing ? null : _pickAndProcess,
            icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
            label: const Text('Enviar outra foto'),
          ),
        ] else
          const Text(
            'Mostre os 4 marcadores inteiros e nítidos, de 2 a 3 m, de frente para o quadro. '
            'Use a foto original da câmera, não a enviada por WhatsApp.',
            style: TextStyle(
              color: MoldScanColors.textSecondary,
              fontSize: 14.5,
              height: 1.4,
            ),
          ),
      ],
    );
  }

  Widget _mesaContent() {
    final bytes = _selectedBytes;
    if (_preview != null) {
      return Semantics(
        label:
            'Foto do quadro vista de cima, com o contorno do molde desenhado',
        image: true,
        child: Image.memory(_preview!, fit: BoxFit.fill, gaplessPlayback: true),
      );
    }
    if (_processing && bytes != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Opacity(opacity: 0.32, child: Image.memory(bytes, fit: BoxFit.cover)),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _stage,
                    style: MoldScanType.headline(24),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 14),
                  const SizedBox(
                    width: 240,
                    child: LinearProgressIndicator(minHeight: 3),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }
    if (bytes != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Opacity(opacity: 0.4, child: Image.memory(bytes, fit: BoxFit.cover)),
          Center(
            child: FilledButton.icon(
              onPressed: _pickAndProcess,
              icon: const Icon(Icons.add_photo_alternate_outlined, size: 20),
              label: const Text('Escolher outra foto'),
            ),
          ),
        ],
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Envie a foto do molde\nsobre o quadro',
              style: MoldScanType.headline(26),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _pickAndProcess,
              icon: const Icon(Icons.add_photo_alternate_outlined, size: 20),
              label: const Text('Escolher foto'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sidebar() {
    final contour = _contour;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _boardSettings(),
        if (_error != null) ...[
          const SizedBox(height: 16),
          Notice(
            color: MoldScanColors.danger,
            icon: Icons.error_outline,
            messages: [_error!],
          ),
        ],
        if (contour != null) ...[
          const SizedBox(height: 28),
          ListenableBuilder(
            listenable: _project.thickness,
            builder: (context, _) {
              final shown = _shown(contour);
              return MeasurementSummary(
                contour: shown,
                warnings: _warnings,
                note: _thicknessNote(contour, shown),
              );
            },
          ),
          const SizedBox(height: 28),
          ProjectFields(data: _project),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _downloadDxf,
              icon: const Icon(Icons.download, size: 20),
              label: const Text('Baixar DXF'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _boardSettings() {
    return Container(
      decoration: BoxDecoration(
        color: MoldScanColors.surface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: MoldScanColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(4),
            onTap: () => setState(() => _settingsOpen = !_settingsOpen),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Distância entre os marcadores',
                          style: TextStyle(
                            color: MoldScanColors.textSecondary,
                            fontSize: 14.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        ListenableBuilder(
                          listenable: Listenable.merge([
                            _boardWidthController,
                            _boardHeightController,
                          ]),
                          builder: (context, _) => Text(
                            '${_boardWidthController.text} × ${_boardHeightController.text} cm',
                            style: MoldScanType.headline(28),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    _settingsOpen ? 'Fechar' : 'Alterar',
                    style: const TextStyle(
                      color: MoldScanColors.accentAlt,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Icon(
                    _settingsOpen ? Icons.expand_less : Icons.expand_more,
                    color: MoldScanColors.accentAlt,
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            alignment: Alignment.topCenter,
            child: _settingsOpen
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _boardWidthController,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                decoration: const InputDecoration(
                                  labelText: 'Na horizontal (cm)',
                                ),
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: _boardHeightController,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                decoration: const InputDecoration(
                                  labelText: 'Na vertical (cm)',
                                ),
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Depois de colar os 4 marcadores, meça com a trena do canto esquerdo de um '
                          'quadrado preto até o canto esquerdo do outro: nos dois de cima para a medida '
                          'horizontal, nos dois da esquerda para a vertical. Essa medida define a escala '
                          'de tudo, então meça com cuidado. No quadro da loja dá 220 × 120 cm.',
                          style: TextStyle(
                            color: MoldScanColors.textSecondary,
                            fontSize: 14,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          onPressed: _generatingBoard ? null : _downloadBoard,
                          icon: const Icon(Icons.download_outlined, size: 18),
                          label: Text(
                            _generatingBoard
                                ? 'Gerando...'
                                : 'Baixar marcadores em PDF',
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '4 folhas A4, uma por marcador. Imprima a 100%, recorte na linha tracejada e cole '
                          'nos cantos do quadro, com a borda do papel a 50 mm das bordas.',
                          style: TextStyle(
                            color: MoldScanColors.textSecondary,
                            fontSize: 14,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}
