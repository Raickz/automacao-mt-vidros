import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../models/measurement_result.dart';
import '../models/piece_type.dart';
import '../services/marker_measurement_service.dart';
import '../services/qr_marker_detector.dart';
import 'measurement_result_screen.dart';

class MarkerCaptureScreen extends StatefulWidget {
  final PieceType pieceType;

  const MarkerCaptureScreen({super.key, required this.pieceType});

  @override
  State<MarkerCaptureScreen> createState() => _MarkerCaptureScreenState();
}

class _MarkerCaptureScreenState extends State<MarkerCaptureScreen> {
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
    final controller = CameraController(
      backCamera,
      ResolutionPreset.veryHigh,
      enableAudio: false,
    );
    await controller.initialize();
    if (!mounted) return;
    setState(() => _controller = controller);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _captureAndMeasure() async {
    final controller = _controller;
    if (controller == null || _processing) return;

    setState(() {
      _processing = true;
      _error = null;
    });

    try {
      final photo = await controller.takePicture();
      final markers = await QrMarkerDetector().detectFromFile(photo.path);

      if (markers.length != 4) {
        setState(() {
          _error = 'Foram encontrados ${markers.length} de 4 marcadores. '
              'Ajuste o enquadramento para que todos fiquem visíveis e tire a foto de novo.';
          _processing = false;
        });
        return;
      }

      final points = MarkerMeasurementService().computeRectangleCorners(markers);
      final result = MeasurementResult(
        pieceType: widget.pieceType,
        points: points,
        deviceLabel: 'Marcadores QR (alta confiança)',
      );

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => MeasurementResultScreen(result: result)),
      );
    } on MarkerMeasurementException catch (e) {
      setState(() {
        _error = e.message;
        _processing = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Não foi possível processar a foto. Tente novamente.';
        _processing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Fotografar marcadores: ${widget.pieceType.label}')),
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
                          'Enquadre os 4 marcadores nos cantos do vão e tire a foto.',
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
                          onPressed: _processing ? null : _captureAndMeasure,
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
