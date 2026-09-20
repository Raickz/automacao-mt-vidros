import 'dart:io';

import 'package:ar_flutter_plugin_plus/ar_flutter_plugin_plus.dart';
import 'package:ar_flutter_plugin_plus/datatypes/config_planedetection.dart';
import 'package:ar_flutter_plugin_plus/datatypes/hittest_result_types.dart';
import 'package:ar_flutter_plugin_plus/managers/ar_anchor_manager.dart';
import 'package:ar_flutter_plugin_plus/managers/ar_location_manager.dart';
import 'package:ar_flutter_plugin_plus/managers/ar_object_manager.dart';
import 'package:ar_flutter_plugin_plus/managers/ar_session_manager.dart';
import 'package:ar_flutter_plugin_plus/models/ar_hittest_result.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/measurement_point.dart';
import '../models/measurement_result.dart';
import '../models/piece_type.dart';
import 'measurement_result_screen.dart';

class ArMeasurementScreen extends StatefulWidget {
  final PieceType pieceType;

  const ArMeasurementScreen({super.key, required this.pieceType});

  @override
  State<ArMeasurementScreen> createState() => _ArMeasurementScreenState();
}

class _ArMeasurementScreenState extends State<ArMeasurementScreen> {
  ARSessionManager? _sessionManager;

  final List<MeasurementPoint> _points = [];

  @override
  void dispose() {
    _sessionManager?.dispose();
    super.dispose();
  }

  void _onARViewCreated(
    ARSessionManager sessionManager,
    ARObjectManager objectManager,
    ARAnchorManager anchorManager,
    ARLocationManager locationManager,
  ) {
    _sessionManager = sessionManager;

    sessionManager.onInitialize(
      showFeaturePoints: false,
      showPlanes: true,
      showWorldOrigin: false,
      handleTaps: true,
    );
    objectManager.onInitialize();

    sessionManager.onPlaneOrPointTap = _onPlaneOrPointTap;
  }

  void _onPlaneOrPointTap(List<ARHitTestResult> hits) {
    if (hits.isEmpty) return;
    if (widget.pieceType.isRectangular && _points.length >= 4) {
      _showSnack('Já foram marcados os 4 cantos. Toque em "Desfazer" para corrigir.');
      return;
    }

    final hit = hits.firstWhere(
      (h) => h.type == ARHitTestResultType.plane,
      orElse: () => hits.first,
    );
    final translation = hit.worldTransform.getTranslation();

    setState(() {
      _points.add(MeasurementPoint.fromVector3(_points.length, translation));
    });
    HapticFeedback.lightImpact();
  }

  void _undoLast() {
    if (_points.isEmpty) return;
    setState(() => _points.removeLast());
  }

  bool get _canFinish {
    if (widget.pieceType.isRectangular) return _points.length == 4;
    return _points.length >= 2;
  }

  void _finish() {
    final deviceLabel = Platform.isIOS ? 'iOS (ARKit)' : 'Android (ARCore)';
    final result = MeasurementResult(
      pieceType: widget.pieceType,
      points: List.of(_points),
      deviceLabel: deviceLabel,
    );
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => MeasurementResultScreen(result: result)),
    );
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Medindo: ${widget.pieceType.label}')),
      body: Stack(
        children: [
          ARView(
            onARViewCreated: _onARViewCreated,
            planeDetectionConfig: PlaneDetectionConfig.horizontalAndVertical,
            permissionPromptDescription:
                'Precisamos da permissão de câmera para medir com AR.',
            permissionPromptButtonText: 'Permitir câmera',
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _ControlPanel(
              pieceType: widget.pieceType,
              pointCount: _points.length,
              canFinish: _canFinish,
              onUndo: _undoLast,
              onFinish: _finish,
            ),
          ),
        ],
      ),
    );
  }
}

class _ControlPanel extends StatelessWidget {
  final PieceType pieceType;
  final int pointCount;
  final bool canFinish;
  final VoidCallback onUndo;
  final VoidCallback onFinish;

  const _ControlPanel({
    required this.pieceType,
    required this.pointCount,
    required this.canFinish,
    required this.onUndo,
    required this.onFinish,
  });

  @override
  Widget build(BuildContext context) {
    final target = pieceType.isRectangular ? '${pieceType.requiredPoints}' : '2+';
    return Container(
      color: Colors.black.withValues(alpha: 0.65),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Pontos marcados: $pointCount / $target',
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
            const SizedBox(height: 4),
            const Text(
              'Toque na tela sobre os cantos do vão para marcar cada ponto.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                TextButton.icon(
                  onPressed: pointCount > 0 ? onUndo : null,
                  icon: const Icon(Icons.undo, color: Colors.white),
                  label: const Text('Desfazer', style: TextStyle(color: Colors.white)),
                ),
                FilledButton.icon(
                  onPressed: canFinish ? onFinish : null,
                  icon: const Icon(Icons.check),
                  label: const Text('Finalizar'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
