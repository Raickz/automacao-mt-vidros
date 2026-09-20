import 'package:flutter/material.dart';

import 'history_screen.dart';
import 'piece_type_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('MT Vidros — Automação')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.window_outlined, size: 72, color: Colors.blueGrey),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PieceTypeScreen()),
                ),
                icon: const Icon(Icons.straighten),
                label: const Text('Nova medição'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const HistoryScreen()),
                ),
                icon: const Icon(Icons.history),
                label: const Text('Histórico de medições'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
