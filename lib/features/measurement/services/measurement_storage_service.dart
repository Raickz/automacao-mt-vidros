import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/measurement_result.dart';

class MeasurementStorageService {
  static const _fileName = 'measurements.json';

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  Future<List<MeasurementResult>> loadAll() async {
    final file = await _file();
    if (!await file.exists()) return [];
    final content = await file.readAsString();
    if (content.trim().isEmpty) return [];
    final list = jsonDecode(content) as List;
    return list
        .map((e) => MeasurementResult.fromJson(e as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<void> save(MeasurementResult result) async {
    final all = await loadAll();
    all.removeWhere((m) => m.id == result.id);
    all.add(result);
    final file = await _file();
    await file.writeAsString(jsonEncode(all.map((m) => m.toJson()).toList()));
  }

  Future<void> delete(String id) async {
    final all = await loadAll();
    all.removeWhere((m) => m.id == id);
    final file = await _file();
    await file.writeAsString(jsonEncode(all.map((m) => m.toJson()).toList()));
  }
}
