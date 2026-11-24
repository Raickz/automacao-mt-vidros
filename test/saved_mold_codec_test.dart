import 'package:flutter_test/flutter_test.dart';
import 'package:mt_vidros_app/features/mold_scan/services/homography.dart';
import 'package:mt_vidros_app/features/mold_scan/services/mold_outline.dart';
import 'package:mt_vidros_app/features/mold_scan/services/saved_mold_codec.dart';

void main() {
  const good =
      '{"id":"1","name":"Porta","pts":[[0,0],[800,0],[800,2100],[0,2100]]}';

  test('ida e volta preserva nome e pontos (2 casas)', () {
    final m = SavedMold(
      '42',
      'Espelho',
      const MoldOutline([Point2D(0, 0), Point2D(10.123, 0), Point2D(5, 7.456)]),
    );
    final back = SavedMoldCodec.decode(SavedMoldCodec.encode([m]))!;
    expect(back.single.name, 'Espelho');
    expect(back.single.outline.points[1].x, 10.12);
    expect(back.single.outline.points[2].y, 7.46);
  });

  test('um molde corrompido não apaga os outros', () {
    final raw =
        '[$good,'
        '{"id":"2","name":"poucos pontos","pts":[[0,0],[1,1]]},'
        '{"id":"3","name":"gigante","pts":[[0,0],[1e300,0],[0,5]]},'
        '{"id":"4","name":"texto","pts":[[0,0],["a",0],[0,5]]},'
        '{"id":5,"name":"id numérico","pts":[[0,0],[9,0],[0,5]]},'
        '{"id":"6","name":"linha","pts":[[0,0],[100,0],[200,0]]},'
        '"lixo", null, 7]';
    final molds = SavedMoldCodec.decode(raw)!;
    expect(molds.map((m) => m.id), ['1']);
    expect(molds.single.outline.width, 800);
  });

  test(
    'JSON inválido ou que não é lista devolve null (para não sobrescrever)',
    () {
      expect(SavedMoldCodec.decode('{'), isNull);
      expect(SavedMoldCodec.decode('{"a":1}'), isNull);
      expect(SavedMoldCodec.decode('[]'), isEmpty);
    },
  );

  test('nome gigante é cortado', () {
    final raw = '[{"id":"1","name":"${'x' * 5000}","pts":[[0,0],[9,0],[0,5]]}]';
    expect(
      SavedMoldCodec.decode(raw)!.single.name.length,
      SavedMoldCodec.maxNameLength,
    );
  });
}
