import 'package:flutter/material.dart';

import '../models/piece_type.dart';

class MarkerKitScreen extends StatelessWidget {
  final PieceType pieceType;

  const MarkerKitScreen({super.key, required this.pieceType});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Medição por marcadores QR')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.qr_code_2, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              const Text(
                'A medição por marcadores QR usa a câmera real do aparelho e '
                'só funciona no app instalado (Android/iOS), não nesta versão web.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Voltar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
