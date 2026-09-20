import 'package:flutter/material.dart';

import '../models/piece_type.dart';
import 'ar_measurement_screen.dart';
import 'marker_kit_screen.dart';

class PieceTypeScreen extends StatelessWidget {
  const PieceTypeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tipo de peça')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: PieceType.values.map((type) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(type.label, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    type.isRectangular
                        ? 'Marque os 4 cantos do vão'
                        : 'Marque quantos pontos precisar para o contorno',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.view_in_ar),
                          label: const Text('AR (rápido)'),
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => ArMeasurementScreen(pieceType: type)),
                          ),
                        ),
                      ),
                      if (type.isRectangular) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton.icon(
                            icon: const Icon(Icons.qr_code_2),
                            label: const Text('Marcadores QR'),
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => MarkerKitScreen(pieceType: type)),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
