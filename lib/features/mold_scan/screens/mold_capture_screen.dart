import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../services/mold_scan_service_io.dart';
import 'mold_result_screen.dart';

class MoldCaptureScreen extends StatefulWidget {
  const MoldCaptureScreen({super.key});

  @override
  State<MoldCaptureScreen> createState() => _MoldCaptureScreenState();
}

class _MoldCaptureScreenState extends State<MoldCaptureScreen> {
  CameraController? _controller;
  Future<void>? _initialization;
  bool _processing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initialization = _setupCamera();
  }

  Future<void> _setupCamera() async {
    final cameras = await availableCameras();
    final backCamera = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );
    final controller = CameraController(backCamera, ResolutionPreset.ultraHigh, enableAudio: false);
    await controller.initialize();
    if (!mounted) return;
    setState(() => _controller = controller);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _captureAndScan() async {
    final controller = _controller;
    if (controller == null || _processing) return;

    setState(() {
      _processing = true;
      _error = null;
    });

    try {
      final photo = await controller.takePicture();
      final result = await MoldScanService().scanContourFromPhoto(photo.path);

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => MoldResultScreen(contourMm: result.contourMm, warnings: result.warnings),
        ),
      );
    } on MoldScanException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _processing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Não foi possível processar a foto. Tente novamente.';
        _processing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Fotografar molde')),
      body: FutureBuilder<void>(
        future: _initialization,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done || _controller == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return Stack(
            children: [
              Positioned.fill(child: CameraPreview(_controller!)),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  color: Colors.black.withValues(alpha: 0.65),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  child: SafeArea(
                    top: false,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Fique a 2-3m, de frente para o quadro, com os 4 marcadores inteiros na foto (e o molde em cima), e tire a foto.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.orangeAccent),
                          ),
                        ],
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: _processing ? null : _captureAndScan,
                          icon: _processing
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.camera_alt),
                          label: Text(_processing ? 'Processando...' : 'Capturar'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
