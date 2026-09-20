import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/measurement_result.dart';
import '../models/piece_type.dart';
import '../services/measurement_storage_service.dart';
import 'measurement_result_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _storage = MeasurementStorageService();
  late Future<List<MeasurementResult>> _future;

  @override
  void initState() {
    super.initState();
    _future = _storage.loadAll();
  }

  void _reload() {
    setState(() => _future = _storage.loadAll());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Histórico de medições')),
      body: FutureBuilder<List<MeasurementResult>>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snapshot.data!;
          if (items.isEmpty) {
            return const Center(child: Text('Nenhuma medição salva ainda.'));
          }
          return ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return Dismissible(
                key: ValueKey(item.id),
                background: Container(
                  color: Colors.red,
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  child: const Icon(Icons.delete, color: Colors.white),
                ),
                direction: DismissDirection.endToStart,
                onDismissed: (_) async {
                  await _storage.delete(item.id);
                },
                child: ListTile(
                  leading: const Icon(Icons.straighten),
                  title: Text(item.pieceType.label),
                  subtitle: Text(DateFormat('dd/MM/yyyy HH:mm').format(item.createdAt)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => MeasurementResultScreen(result: item, readOnly: true),
                      ),
                    );
                    _reload();
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
