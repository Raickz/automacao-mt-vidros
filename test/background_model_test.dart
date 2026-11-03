import 'package:flutter_test/flutter_test.dart';
import 'package:mt_vidros_app/features/mold_scan/services/background_model.dart';

void main() {
  test('fit recupera um gradiente de luz em x', () {
    // Color = 100 + 60*x in every channel, sampled on a grid.
    final xs = <double>[], ys = <double>[];
    final cs = [<double>[], <double>[], <double>[]];
    for (var i = 0; i <= 10; i++) {
      for (var j = 0; j <= 10; j++) {
        final x = i / 10, y = j / 10;
        xs.add(x);
        ys.add(y);
        for (final c in cs) {
          c.add(100 + 60 * x);
        }
      }
    }
    final model = BackgroundModel.fit(xs, ys, cs, 1000, 600);
    expect(model.colorAt(0, 300).$1, closeTo(100, 1));
    expect(model.colorAt(1000, 300).$2, closeTo(160, 1));
  });

  test('consistentSamples descarta a faixa coberta pelo molde e mantém as da parede', () {
    // 4 strips x 20 samples. Strip 1 (e.g. the bottom one) is covered by wood.
    const wall = [110.0, 105.0, 100.0];
    const wood = [190.0, 150.0, 110.0];
    final cs = [<double>[], <double>[], <double>[]];
    final strips = <List<int>>[];
    for (var s = 0; s < 4; s++) {
      final ids = <int>[];
      for (var k = 0; k < 20; k++) {
        ids.add(cs[0].length);
        final color = s == 1 ? wood : wall;
        for (var ch = 0; ch < 3; ch++) {
          cs[ch].add(color[ch] + (k % 3));
        }
      }
      strips.add(ids);
    }

    final kept = BackgroundModel.consistentSamples(strips, cs);
    expect(kept.length, 60);
    expect(kept.toSet().intersection(strips[1].toSet()), isEmpty);
  });

  test('consistentSamples não confunde gradiente de luz com molde: mantém todas as faixas', () {
    // Same hue, brightness 0.7x to 1.3x across strips.
    final cs = [<double>[], <double>[], <double>[]];
    final strips = <List<int>>[];
    for (var s = 0; s < 4; s++) {
      final ids = <int>[];
      final light = 0.7 + 0.2 * s;
      for (var k = 0; k < 20; k++) {
        ids.add(cs[0].length);
        cs[0].add(20 * light);
        cs[1].add(90 * light);
        cs[2].add(200 * light);
      }
      strips.add(ids);
    }
    expect(BackgroundModel.consistentSamples(strips, cs).length, 80);
  });
}
