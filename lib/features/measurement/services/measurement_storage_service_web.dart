import '../models/measurement_result.dart';

class MeasurementStorageService {
  static final List<MeasurementResult> _inMemory = [];

  Future<List<MeasurementResult>> loadAll() async {
    final list = List<MeasurementResult>.of(_inMemory);
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  Future<void> save(MeasurementResult result) async {
    _inMemory.removeWhere((m) => m.id == result.id);
    _inMemory.add(result);
  }

  Future<void> delete(String id) async {
    _inMemory.removeWhere((m) => m.id == id);
  }
}
