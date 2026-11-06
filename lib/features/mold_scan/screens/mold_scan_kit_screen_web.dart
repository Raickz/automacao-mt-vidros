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
import '../services/mold_outline.dart';
import 'mold_library_page.dart';
import '../services/mold_store.dart';
import '../widgets/corner_picker.dart';
import '../widgets/mold_editor.dart';

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
  BoardGeometry? _resultBoard;
  bool _scaleFromMarkers = false;
  int _tab = 0; // 0 = digitalizar, 1 = biblioteca
  bool _editing = false; // scan result open in the editor
  bool _picking = false; // manual calibration
  bool _showOriginal = false; // "antes" view of the result

  final _project = ProjectData();
  final _scroll = ScrollController();
  // Optional: left blank, the marker spacing is measured from the QR codes.
  late final _boardWidthController = TextEditingController(
    text: MoldStore.markerSpans().$1,
  );
  late final _boardHeightController = TextEditingController(
    text: MoldStore.markerSpans().$2,
  );
  final _printedController = TextEditingController(text: '18,0');

  @override
  void dispose() {
    _project.dispose();
    _scroll.dispose();
    _boardWidthController.dispose();
    _boardHeightController.dispose();
    _printedController.dispose();
    super.dispose();
  }

  bool get _manualSpans =>
      _boardWidthController.text.trim().isNotEmpty ||
      _boardHeightController.text.trim().isNotEmpty;

  BoardGeometry? get _typedBoard => BoardGeometry.fromMarkerSpans(
    _boardWidthController.text,
    _boardHeightController.text,
    outerEdgesSquareMm: _printedMm ?? 180,
  );

  double? get _printedMm {
    final cm = double.tryParse(
      _printedController.text.trim().replaceAll(',', '.'),
    );
    return cm == null ? null : cm * 10;
  }

  double get _boardAspect {
    final board = _resultBoard ?? (_manualSpans ? _typedBoard : null);
    return board == null
        ? 250 / 150
        : (board.widthMm / board.heightMm).clamp(0.6, 2.4);
  }

  /// The scale inputs, or null (with the error shown) when they are invalid.
  /// No typed spacing means "measure it from the QR codes".
  ({BoardGeometry? board, double printedMm})? _readScale() {
    void fail(String message) => setState(() {
      _error = message;
      _settingsOpen = true;
    });
    final printed = _printedMm;
    if (printed == null || printed < 120 || printed > 240) {
      fail(
        'Informe o lado do quadrado preto impresso, em cm (impresso a 100% dá 18,0).',
      );
      return null;
    }
    if (!_manualSpans) return (board: null, printedMm: printed);
    final board = _typedBoard;
    if (board == null) {
      fail(
        '${BoardGeometry.spanHint} Ou deixe os dois em branco para a escala sair dos QR (menos preciso).',
      );
      return null;
    }
    return (board: board, printedMm: printed);
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
    final scale = _readScale();
    if (scale == null) return;

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
    await _process(bytes, scale);
  }

  /// Manual calibration: the 4 marker centers placed by hand.
  Future<void> _processManual(List<Point2D> centers) async {
    final scale = _readScale();
    final bytes = _selectedBytes;
    if (scale == null || bytes == null) return;
    if (scale.board == null) {
      setState(() {
        _error =
            'Na calibração manual, a escala vem da distância entre os marcadores: meça com a trena e '
            'digite em "Escala" (horizontal e vertical).';
        _settingsOpen = true;
      });
      return;
    }
    setState(() => _picking = false);
    await _process(bytes, scale, manualCenters: centers);
  }

  Future<void> _process(
    Uint8List bytes,
    ({BoardGeometry? board, double printedMm}) scale, {
    List<Point2D>? manualCenters,
  }) async {
    setState(() {
      _selectedBytes = bytes;
      _showOriginal = false;
      _editing = false;
      _processing = true;
      _stage = 'Processando...';
      _error = null;
      _warnings = const [];
      _contour = null;
      _preview = null;
      _pose = null;
      _resultBoard = null;
    });
    // Let the progress bar paint before the (UI-thread) processing starts.
    await Future<void>.delayed(const Duration(milliseconds: 80));

    try {
      final result = await MoldScanService().scanContourFromBytes(
        bytes,
        board: scale.board,
        printedMarkerMm: scale.printedMm,
        manualCenters: manualCenters,
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
        _resultBoard = result.board;
        _scaleFromMarkers = result.scaleFromMarkers;
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

  void _spansChanged() {
    MoldStore.setMarkerSpans(
      _boardWidthController.text.trim(),
      _boardHeightController.text.trim(),
    );
    setState(() {});
  }

  /// Switches what the page shows and goes back to its top.
  void _view(VoidCallback change) {
    setState(change);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(0);
    });
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
  List<Point2D> _corrected(List<Point2D> contour) =>
      CameraPoseEstimator.correctForThickness(
        contour,
        _pose,
        _project.thicknessMm,
      );

  List<Point2D> _shown(List<Point2D> contour) {
    final corrected = MoldOutline(_corrected(contour));
    // A piece taped slightly crooked is measured square to its own edges.
    final angle = corrected.straighteningAngle();
    return angle == 0 ? corrected.points : corrected.rotatedBy(angle).points;
  }

  String _resultNote(List<Point2D> raw, List<Point2D> shown) {
    final board = _resultBoard;
    String cm(double mm) => (mm / 10).toStringAsFixed(1).replaceAll('.', ',');
    final sq = _printedMm ?? 180;
    final scale = board == null
        ? ''
        : _scaleFromMarkers
        ? 'Escala pelos QR (menos precisa): de fora a fora dos quadrados pretos daria '
              '${cm(board.spanXMm + sq)} × ${cm(board.spanYMm + sq)} cm. Para precisão de milímetro, meça com a '
              'trena e digite em "Escala". '
        : 'Escala pela trena: ${cm(board.spanXMm + sq)} × ${cm(board.spanYMm + sq)} cm de fora a fora dos '
              'quadrados pretos. ';
    final angle = MoldOutline(_corrected(raw)).straighteningAngle();
    final straight = angle == 0
        ? ''
        : 'O molde estava ${angle.abs().toStringAsFixed(1).replaceAll('.', ',')}° torto na foto; medi '
              'endireitado. ';
    return '$scale$straight${_thicknessNote(raw, _corrected(raw))}';
  }

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
                  controller: _scroll,
                  padding: EdgeInsets.fromLTRB(pad, 18, pad, 40),
                  children: [
                    const MoldTopBar(),
                    const SizedBox(height: 18),
                    SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(
                          value: 0,
                          icon: Icon(Icons.photo_camera_outlined),
                          label: Text('Digitalizar'),
                        ),
                        ButtonSegment(
                          value: 1,
                          icon: Icon(Icons.grid_view_rounded),
                          label: Text('Biblioteca'),
                        ),
                      ],
                      selected: {_tab},
                      onSelectionChanged: (s) => setState(() => _tab = s.first),
                    ),
                    SizedBox(height: wide ? 32 : 22),
                    if (_tab == 1)
                      MoldLibraryPage(
                        scanned: _contour == null
                            ? null
                            : MoldOutline(_shown(_contour!)),
                      )
                    else if (_editing && _contour != null)
                      MoldEditor(
                        key: ValueKey(_contour),
                        original: () =>
                            MoldOutline(_shown(_contour!)).normalized(),
                        initialName: _project.name.text.trim(),
                        material: _project.material.text.trim(),
                        instructions: _project.instructions.text.trim(),
                        fromScan: true,
                        backLabel: 'Voltar ao resultado',
                        onBack: () => _view(() => _editing = false),
                      )
                    else if (_picking && _selectedBytes != null) ...[
                      CornerPicker(
                        photo: _selectedBytes!,
                        onDone: _processManual,
                        onCancel: () => _view(() => _picking = false),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        Notice(
                          color: MoldScanColors.danger,
                          icon: Icons.error_outline,
                          messages: [_error!],
                        ),
                      ],
                      const SizedBox(height: 22),
                      _boardSettings(),
                    ] else ...[
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
                '${_processing}_${hasPreview}_${_selectedBytes != null}_$_showOriginal',
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
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Depois')),
                  ButtonSegment(value: true, label: Text('Antes')),
                ],
                selected: {_showOriginal},
                onSelectionChanged: (v) =>
                    setState(() => _showOriginal = v.first),
              ),
            ],
          ),
          const SizedBox(height: 6),
          TextButton.icon(
            onPressed: _processing ? null : _pickAndProcess,
            icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
            label: const Text('Enviar outra foto'),
          ),
        ] else
          const Text(
            'O molde precisa estar inteiro no mesmo plano dos QR: deitado no chão com os QR no chão, ou '
            'encostado inteiro no quadro. Molde inclinado ou com o pé afastado da parede sai maior embaixo. '
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
    if (_preview != null && _showOriginal && bytes != null) {
      return Image.memory(bytes, fit: BoxFit.contain, gaplessPlayback: true);
    }
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
          if (_selectedBytes != null && contour == null && !_processing) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => _view(() {
                _picking = true;
                _error = null;
              }),
              icon: const Icon(Icons.touch_app_outlined, size: 18),
              label: const Text('Marcar os 4 marcadores à mão'),
            ),
          ],
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
                note: _resultNote(contour, shown),
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
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _view(() => _editing = true),
              icon: const Icon(Icons.tune, size: 18),
              label: const Text('Ajustar medida, margem, PDF e orçamento'),
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
                          'Escala',
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
                            _manualSpans
                                ? 'Medida: ${_boardWidthController.text} × ${_boardHeightController.text} cm'
                                : 'Automática pelos QR',
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
                        SizedBox(
                          width: 240,
                          child: TextField(
                            controller: _printedController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Quadrado preto impresso (cm)',
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'O app mede a escala pelos próprios QR, que são réguas de tamanho conhecido. Meça '
                          'um quadrado preto impresso com a régua: impresso a 100% dá 18,0 cm.',
                          style: TextStyle(
                            color: MoldScanColors.textSecondary,
                            fontSize: 14,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 18),
                        const Text(
                          'Distância entre os quadrados pretos, de fora a fora',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 10),
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
                                  labelText: 'Horizontal (cm)',
                                  hintText: 'ex: 197,4',
                                ),
                                onChanged: (_) => _spansChanged(),
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
                                  labelText: 'Vertical (cm)',
                                  hintText: 'ex: 150,0',
                                ),
                                onChanged: (_) => _spansChanged(),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Essencial para precisão de milímetro. Com a trena, meça da borda de fora de um quadrado '
                          'preto até a borda de fora do outro (o preto, não a folha branca): os dois de cima para a '
                          'horizontal, os dois da esquerda para a vertical. Fica salvo neste aparelho; se mudar os QR '
                          'de lugar, meça de novo. Em branco, a escala sai do tamanho dos QR na foto, que erra até 4% '
                          'quando a folha está ondulada ou descolada.',
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
                          'um em cada canto do quadro, retos, com a borda do papel a cerca de 5 cm das bordas.',
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
