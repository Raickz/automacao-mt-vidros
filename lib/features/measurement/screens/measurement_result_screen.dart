import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/measurement_result.dart';
import '../models/piece_type.dart';
import '../services/measurement_export_service.dart';
import '../services/measurement_storage_service.dart';
import '../widgets/measurement_metric_tile.dart';
import 'home_screen.dart';

class MeasurementResultScreen extends StatefulWidget {
  final MeasurementResult result;
  final bool readOnly;

  const MeasurementResultScreen({
    super.key,
    required this.result,
    this.readOnly = false,
  });

  @override
  State<MeasurementResultScreen> createState() => _MeasurementResultScreenState();
}

class _MeasurementResultScreenState extends State<MeasurementResultScreen> {
  final _storage = MeasurementStorageService();
  final _export = MeasurementExportService();
  bool _saving = false;
  bool _saved = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    await _storage.save(widget.result);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _saved = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Medição salva no histórico.')),
    );
  }

  Future<void> _share() async {
    await _export.shareResult(widget.result);
  }

  @override
  Widget build(BuildContext context) {
    final result = widget.result;
    final dateLabel = DateFormat('dd/MM/yyyy HH:mm').format(result.createdAt);

    return Scaffold(
      appBar: AppBar(title: const Text('Resultado da medição')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(result.pieceType.label, style: Theme.of(context).textTheme.headlineSmall),
          Text(dateLabel, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _buildMetrics(context),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Origem da medição: ${result.deviceLabel}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          const Card(
            color: Color(0xFFFFF3CD),
            child: Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'Esta medição é uma referência digital feita por câmera/AR. '
                'Confirme com trena ou medidor a laser antes de cortar o vidro.',
              ),
            ),
          ),
          const SizedBox(height: 24),
          if (!widget.readOnly)
            FilledButton.icon(
              onPressed: _saving || _saved ? null : _save,
              icon: const Icon(Icons.save),
              label: Text(_saved ? 'Salvo' : 'Salvar no histórico'),
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _share,
            icon: const Icon(Icons.picture_as_pdf),
            label: const Text('Gerar e compartilhar PDF'),
          ),
          if (!widget.readOnly) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const HomeScreen()),
                (route) => false,
              ),
              child: const Text('Voltar ao início'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMetrics(BuildContext context) {
    final result = widget.result;
    if (result.pieceType.isRectangular) {
      final m = result.rectangleMetrics;
      return Column(
        children: [
          MeasurementMetricTile(label: 'Largura', value: '${(m.widthMm / 10).toStringAsFixed(1)} cm'),
          MeasurementMetricTile(label: 'Altura', value: '${(m.heightMm / 10).toStringAsFixed(1)} cm'),
          MeasurementMetricTile(label: 'Diagonal 1', value: '${(m.diagonal1Mm / 10).toStringAsFixed(1)} cm'),
          MeasurementMetricTile(label: 'Diagonal 2', value: '${(m.diagonal2Mm / 10).toStringAsFixed(1)} cm'),
          MeasurementMetricTile(
            label: 'Esquadro',
            value: m.isSquareWithinTolerance
                ? 'OK (±${m.squareDeviationMm.toStringAsFixed(0)} mm)'
                : 'Verificar (±${m.squareDeviationMm.toStringAsFixed(0)} mm)',
            valueColor: m.isSquareWithinTolerance ? Colors.green : Colors.orange,
          ),
        ],
      );
    }
    final m = result.freeformMetrics;
    return Column(
      children: [
        ...m.segmentLengthsMm.asMap().entries.map(
              (e) => MeasurementMetricTile(
                label: 'Segmento ${e.key + 1}',
                value: '${(e.value / 10).toStringAsFixed(1)} cm',
              ),
            ),
        const Divider(),
        MeasurementMetricTile(
          label: 'Comprimento total',
          value: '${(m.totalLengthMm / 10).toStringAsFixed(1)} cm',
        ),
      ],
    );
  }
}
