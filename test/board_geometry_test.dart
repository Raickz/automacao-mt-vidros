import 'package:flutter_test/flutter_test.dart';
import 'package:mt_vidros_app/features/mold_scan/models/board_geometry.dart';

void main() {
  group('BoardGeometry.fromCentimeters', () {
    test('lê o quadro da loja e aceita vírgula ou ponto', () {
      final board = BoardGeometry.fromCentimeters('250', '150')!;
      expect((board.widthMm, board.heightMm), (2500.0, 1500.0));

      final decimal = BoardGeometry.fromCentimeters(' 250,5 ', '150.5')!;
      expect((decimal.widthMm, decimal.heightMm), (2505.0, 1505.0));
    });

    test('recusa texto, vazio e lado pequeno demais', () {
      expect(BoardGeometry.fromCentimeters('abc', '150'), isNull);
      expect(BoardGeometry.fromCentimeters('', ''), isNull);
      expect(BoardGeometry.fromCentimeters('50', '150'), isNull);
    });

    test(
      'recusa quadro grande demais, que estouraria a memória do navegador',
      () {
        expect(
          BoardGeometry.fromCentimeters('400', '200'),
          isNotNull,
        ); // 8 m², o limite
        expect(BoardGeometry.fromCentimeters('800', '800'), isNull); // 64 m²
        expect(
          BoardGeometry.fromCentimeters('2500', '1500'),
          isNull,
        ); // mm digitado como cm
      },
    );
  });
}
