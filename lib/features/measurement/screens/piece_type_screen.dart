import 'package:flutter/material.dart';

import '../models/piece_type.dart';
import 'ar_measurement_screen.dart';

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
            child: ListTile(
              title: Text(type.label),
              subtitle: Text(
                type.isRectangular
                    ? 'Marque os 4 cantos do vão'
                    : 'Marque quantos pontos precisar para o contorno',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => ArMeasurementScreen(pieceType: type)),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
