import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart';

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
  final _widthController = TextEditingController(text: '100');
  final _heightController = TextEditingController(text: '120');
  final List<TextEditingController> _segmentControllers = [
    TextEditingController(text: '50'),
    TextEditingController(text: '50'),
  ];

  @override
  void dispose() {
    _widthController.dispose();
    _heightController.dispose();
    for (final c in _segmentControllers) {
      c.dispose();
    }
    super.dispose();
  }

  double _parseCm(TextEditingController controller) {
    return double.tryParse(controller.text.replaceAll(',', '.')) ?? 0;
  }

  void _addSegment() {
    setState(() => _segmentControllers.add(TextEditingController(text: '50')));
  }

  void _removeSegment(int index) {
    setState(() => _segmentControllers.removeAt(index).dispose());
  }

  void _simulate() {
    final now = DateTime.now();
    List<MeasurementPoint> points;

    if (widget.pieceType.isRectangular) {
      final widthM = _parseCm(_widthController) / 100;
      final heightM = _parseCm(_heightController) / 100;
      final corners = [
        Vector3(0, 0, 0),
        Vector3(widthM, 0, 0),
        Vector3(widthM, heightM, 0),
        Vector3(0, heightM, 0),
      ];
      points = [
        for (var i = 0; i < corners.length; i++) MeasurementPoint.fromVector3(i, corners[i]),
      ];
    } else {
      var cursor = 0.0;
      final coords = <Vector3>[Vector3(0, 0, 0)];
      for (final controller in _segmentControllers) {
        cursor += _parseCm(controller) / 100;
        coords.add(Vector3(cursor, 0, 0));
      }
      points = [
        for (var i = 0; i < coords.length; i++) MeasurementPoint.fromVector3(i, coords[i]),
      ];
    }

    final result = MeasurementResult(
      pieceType: widget.pieceType,
      points: points,
      deviceLabel: 'Navegador (simulado — sem câmera/AR real)',
      createdAt: now,
    );

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => MeasurementResultScreen(result: result)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Medindo (simulado): ${widget.pieceType.label}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: const Color(0xFFFFF3CD),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'Este é o modo de teste no navegador. Não há câmera/AR real aqui — '
                'digite valores para simular uma medição e validar o restante do app '
                '(cálculos, histórico, PDF). No celular, essa tela usa a câmera de verdade.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ),
          const SizedBox(height: 24),
          if (widget.pieceType.isRectangular) ..._buildRectangleInputs() else ..._buildFreeformInputs(),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _simulate,
            icon: const Icon(Icons.check),
            label: const Text('Simular medição'),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildRectangleInputs() {
    return [
      TextField(
        controller: _widthController,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(labelText: 'Largura (cm)'),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _heightController,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(labelText: 'Altura (cm)'),
      ),
    ];
  }

  List<Widget> _buildFreeformInputs() {
    return [
      for (var i = 0; i < _segmentControllers.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _segmentControllers[i],
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: 'Segmento ${i + 1} (cm)'),
                ),
              ),
              IconButton(
                onPressed: _segmentControllers.length > 1 ? () => _removeSegment(i) : null,
                icon: const Icon(Icons.remove_circle_outline),
              ),
            ],
          ),
        ),
      TextButton.icon(
        onPressed: _addSegment,
        icon: const Icon(Icons.add),
        label: const Text('Adicionar segmento'),
      ),
    ];
  }
}
