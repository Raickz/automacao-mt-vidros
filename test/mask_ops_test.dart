import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mt_vidros_app/features/mold_scan/services/mask_ops.dart';

Uint8List maskOf(int w, int h, bool Function(int x, int y) on) =>
    Uint8List.fromList([
      for (var y = 0; y < h; y++)
        for (var x = 0; x < w; x++) on(x, y) ? 1 : 0,
    ]);

int count(Uint8List m) => m.fold(0, (a, b) => a + b);

void main() {
  const w = 20, h = 20;

  test(
    'boxMorph: dilatar um pixel dá um quadrado 3x3 e erodar volta ao pixel',
    () {
      final one = maskOf(w, h, (x, y) => x == 10 && y == 10);
      final grown = boxMorph(one, w, h, 1, erode: false);
      expect(count(grown), 9);
      expect(boxMorph(grown, w, h, 1, erode: true), one);
    },
  );

  test(
    'closeGaps: fecha um sulco fino entre dois blocos e mantém as bordas retas',
    () {
      // Two 8x8 blocks with a 2px groove between them.
      final blocks = maskOf(
        w,
        h,
        (x, y) =>
            y >= 6 && y < 14 && ((x >= 2 && x < 10) || (x >= 12 && x < 18)),
      );
      final closed = closeGaps(blocks, w, h, 2);
      expect(closed[10 * w + 10], 1, reason: 'sulco preenchido');
      expect(closed[10 * w + 11], 1);
      expect(closed[10 * w + 1], 0, reason: 'borda externa não cresceu');
      expect(closed[5 * w + 5], 0);
      expect(count(closed), 16 * 8);
    },
  );

  test(
    'dropSlivers: tira uma faixa fina colada na peça e preserva os cantos',
    () {
      // 10x10 piece with a 1px-thick tail running away from it.
      final piece = maskOf(
        w,
        h,
        (x, y) =>
            (x >= 4 && x < 14 && y >= 4 && y < 14) ||
            (y == 8 && x >= 14 && x < 19),
      );
      dropSlivers(piece, w, h, 2);
      expect(piece[8 * w + 18], 0, reason: 'ponta da faixa removida');
      expect(piece[4 * w + 4], 1, reason: 'canto da peça mantido');
      expect(piece[13 * w + 13], 1);
    },
  );

  test('labelLargest: escolhe o maior bloco, não o primeiro', () {
    final mask = maskOf(
      w,
      h,
      (x, y) => (x < 3 && y < 3) || (x >= 8 && x < 16 && y >= 8 && y < 16),
    );
    final r = labelLargest(mask, w, h);
    expect(r.bestCount, 64);
    expect(r.labels[10 * w + 10], r.bestLabel);
    expect(r.labels[1 * w + 1], isNot(r.bestLabel));
  });

  test('labelLargest: sem nada na máscara, bestCount é 0', () {
    expect(labelLargest(Uint8List(w * h), w, h).bestCount, 0);
  });
}
