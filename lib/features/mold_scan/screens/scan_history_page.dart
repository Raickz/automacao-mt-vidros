import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/mold_store.dart';
import '../theme/mold_scan_colors.dart';
import '../theme/mold_scan_theme.dart';
import '../widgets/mold_editor.dart';

/// Every scan made on this device, newest first. Opening one puts it back
/// in the editor (size, edges, margin, DXF, PDF), so nothing measured is
/// lost if the page is closed or reloaded.
class ScanHistoryPage extends StatefulWidget {
  const ScanHistoryPage({super.key});

  @override
  State<ScanHistoryPage> createState() => _ScanHistoryPageState();
}

class _ScanHistoryPageState extends State<ScanHistoryPage> {
  List<ScanRecord> _records = MoldStore.history();
  ScanRecord? _open;

  void _show(ScanRecord? r) {
    setState(() => _open = r);
    final pos = Scrollable.maybeOf(context)?.position;
    if (pos != null && pos.hasPixels) pos.jumpTo(0);
  }

  static String dateText(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  static String _cm(double mm) =>
      (mm / 10).toStringAsFixed(1).replaceAll('.', ',');

  Future<bool> _confirm(String title, String body) async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Excluir'),
            ),
          ],
        ),
      ) ??
      false;

  @override
  Widget build(BuildContext context) {
    final open = _open;
    if (open != null) {
      return MoldEditor(
        key: ValueKey(open.id),
        original: () => open.outline,
        initialName: open.name,
        fromScan: true,
        backLabel: 'Histórico',
        onBack: () => _show(null),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Histórico de digitalizações', style: MoldScanType.headline(34)),
        const SizedBox(height: 8),
        const Text(
          'Cada molde medido fica guardado aqui, neste aparelho, com data e medidas. Abra um para ajustar '
          'e baixar o DXF ou o relatório de novo.',
          style: TextStyle(
            color: MoldScanColors.textSecondary,
            fontSize: 16,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 18),
        if (_records.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Text(
              'Nenhuma digitalização ainda. Elas aparecem aqui assim que a medição termina.',
              style: TextStyle(color: MoldScanColors.textSecondary),
            ),
          )
        else ...[
          for (final r in _records) _tile(r),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: () async {
              final yes = await _confirm(
                'Limpar o histórico?',
                'Todas as digitalizações saem deste aparelho.',
              );
              if (!yes) return;
              MoldStore.clearHistory();
              setState(() => _records = MoldStore.history());
            },
            icon: const Icon(
              Icons.delete_sweep_outlined,
              size: 18,
              color: MoldScanColors.danger,
            ),
            label: const Text(
              'Limpar histórico',
              style: TextStyle(color: MoldScanColors.danger),
            ),
          ),
        ],
      ],
    );
  }

  Widget _tile(ScanRecord r) {
    Uint8List? thumb;
    if (r.thumbJpegBase64.isNotEmpty) {
      try {
        thumb = base64Decode(r.thumbJpegBase64);
      } catch (_) {}
    }
    final o = r.outline;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: MoldScanColors.surface,
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: () => _show(r),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: MoldScanColors.border),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 96,
                  height: 72,
                  child: thumb == null
                      ? CustomPaint(painter: OutlinePainter(o))
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: Image.memory(
                            thumb,
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                          ),
                        ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        r.name.isEmpty ? 'Molde' : r.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${_cm(o.width)} × ${_cm(o.height)} cm',
                        style: MoldScanType.readout(20),
                      ),
                      Text(
                        dateText(r.date),
                        style: const TextStyle(
                          color: MoldScanColors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Excluir do histórico',
                  icon: const Icon(
                    Icons.delete_outline,
                    color: MoldScanColors.textSecondary,
                  ),
                  onPressed: () async {
                    if (!await _confirm(
                      'Excluir esta digitalização?',
                      'Ela sai do histórico deste aparelho.',
                    )) {
                      return;
                    }
                    MoldStore.removeFromHistory(r.id);
                    setState(() => _records = MoldStore.history());
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
