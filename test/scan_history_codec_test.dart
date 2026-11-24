import 'package:flutter_test/flutter_test.dart';
import 'package:mt_vidros_app/features/mold_scan/services/homography.dart';
import 'package:mt_vidros_app/features/mold_scan/services/mold_outline.dart';
import 'package:mt_vidros_app/features/mold_scan/services/scan_history_codec.dart';

ScanRecord _rec(String id, {double w = 610}) => ScanRecord(
  id: id,
  date: DateTime(2026, 11, 24, 2, 11),
  name: 'Molde $id',
  outline: MoldOutline([const Point2D(0, 0), Point2D(w, 0), Point2D(w, 500), const Point2D(0, 500)]),
  thumbJpegBase64: 'AAAA',
  note: 'trena',
);

void main() {
  test('ida e volta preserva data, nome, medida e miniatura', () {
    final back = ScanHistoryCodec.decode(ScanHistoryCodec.encode([_rec('1'), _rec('2', w: 700)]))!;
    expect(back.length, 2);
    expect(back[0].name, 'Molde 1');
    expect(back[0].date, DateTime(2026, 11, 24, 2, 11));
    expect(back[1].outline.width, closeTo(700, 1e-9));
    expect(back[0].thumbJpegBase64, 'AAAA');
  });

  test('registro corrompido é pulado sem perder os outros', () {
    final good = ScanHistoryCodec.encode([_rec('ok')]);
    final raw = good.replaceFirst('[{', '[{"id":"x","date":1,"pts":[[1,"NaN"],[2,2],[3,3]]},{"id":5},{');
    final back = ScanHistoryCodec.decode(raw)!;
    expect(back.map((r) => r.id), ['ok']);
  });

  test('texto que não é lista devolve null (para não sobrescrever às cegas)', () {
    expect(ScanHistoryCodec.decode('{"a":1}'), isNull);
    expect(ScanHistoryCodec.decode('não é json'), isNull);
  });

  test('guarda no máximo 40 digitalizações', () {
    final many = [for (var i = 0; i < 60; i++) _rec('$i')];
    expect(ScanHistoryCodec.decode(ScanHistoryCodec.encode(many))!.length, ScanHistoryCodec.maxRecords);
  });
}
