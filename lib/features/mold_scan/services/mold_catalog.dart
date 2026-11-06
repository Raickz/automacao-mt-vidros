import 'dart:math';

import 'homography.dart';
import 'mold_outline.dart';

/// A ready-made shape of the library. Outlines are generated here (nothing is
/// copied from anybody's catalog); the size is only a starting point, the
/// worker types the real width and height.
class CatalogMold {
  final String code;
  final String name;
  final double widthMm;
  final double heightMm;
  final bool round;
  final MoldOutline Function() build;

  const CatalogMold({
    required this.code,
    required this.name,
    required this.widthMm,
    required this.heightMm,
    required this.build,
    this.round = false,
  });

  bool get tall => heightMm / widthMm >= 1.3;
  bool get wide => widthMm / heightMm >= 1.3;

  /// The outline at its starting size.
  MoldOutline outline() => build().resized(widthMm, heightMm);
}

class MoldCatalog {
  static List<Point2D> _ellipse(int n, {double a = 1, double b = 1}) => [
    for (var i = 0; i < n; i++)
      Point2D(a * cos(2 * pi * i / n), b * sin(2 * pi * i / n)),
  ];

  /// |x/a|^e + |y/b|^e = 1: e=2 ellipse, e>2 squarish.
  static List<Point2D> _superellipse(double e, {int n = 160}) => [
    for (var i = 0; i < n; i++)
      () {
        final t = 2 * pi * i / n, c = cos(t), s = sin(t);
        return Point2D(
          c.sign * pow(c.abs(), 2 / e).toDouble(),
          s.sign * pow(s.abs(), 2 / e).toDouble(),
        );
      }(),
  ];

  /// Rectangle with corner radius [r] (fraction of the shorter side, 0..0.5).
  static List<Point2D> _roundRect(
    double w,
    double h,
    double r, {
    int arc = 14,
  }) {
    final rad = r * min(w, h);
    final pts = <Point2D>[];
    void corner(double cx, double cy, double from) {
      for (var i = 0; i <= arc; i++) {
        final t = from + (pi / 2) * i / arc;
        pts.add(Point2D(cx + rad * cos(t), cy + rad * sin(t)));
      }
    }

    corner(w - rad, h - rad, 0);
    corner(rad, h - rad, pi / 2);
    corner(rad, rad, pi);
    corner(w - rad, rad, 3 * pi / 2);
    return pts;
  }

  /// Flat bottom, semicircular top (door / window arch).
  static List<Point2D> _arch() {
    final pts = <Point2D>[const Point2D(1, 1), const Point2D(-1, 1)];
    for (var i = 0; i <= 60; i++) {
      final t = pi + pi * i / 60;
      pts.add(Point2D(cos(t), sin(t)));
    }
    return pts;
  }

  static List<Point2D> _heart() => [
    for (var i = 0; i < 160; i++)
      () {
        final t = 2 * pi * i / 160;
        return Point2D(
          16 * pow(sin(t), 3).toDouble(),
          -(13 * cos(t) - 5 * cos(2 * t) - 2 * cos(3 * t) - cos(4 * t)),
        );
      }(),
  ];

  static List<Point2D> _drop() => [
    for (var i = 0; i < 120; i++)
      () {
        final t = 2 * pi * i / 120;
        return Point2D(sin(t) * sin(t / 2) * 0.9, -cos(t));
      }(),
  ];

  static List<Point2D> _poly(int sides, {double rot = -pi / 2}) => [
    for (var i = 0; i < sides; i++)
      Point2D(cos(rot + 2 * pi * i / sides), sin(rot + 2 * pi * i / sides)),
  ];

  /// Radial blob: a circle bent by a few random harmonics. Same [seed], same
  /// shape, so codes are stable.
  static List<Point2D> _blob(
    int seed, {
    double stretchX = 1,
    double stretchY = 1,
  }) {
    final rnd = Random(seed);
    final amp = [
      for (var k = 0; k < 4; k++)
        (0.16 / (k + 1)) * (0.4 + rnd.nextDouble() * 0.6),
    ];
    final phase = [for (var k = 0; k < 4; k++) rnd.nextDouble() * 2 * pi];
    return [
      for (var i = 0; i < 180; i++)
        () {
          final t = 2 * pi * i / 180;
          var r = 1.0;
          for (var k = 0; k < 4; k++) {
            r += amp[k] * cos((k + 2) * t + phase[k]);
          }
          return Point2D(stretchX * r * cos(t), stretchY * r * sin(t));
        }(),
    ];
  }

  static List<Point2D> _kidney() => [
    for (var i = 0; i < 180; i++)
      () {
        final t = 2 * pi * i / 180;
        final r =
            1 -
            0.28 * exp(-pow(t - pi / 2, 2) * 3) -
            0.28 * exp(-pow(t - pi / 2 - 2 * pi, 2) * 3);
        return Point2D(1.3 * r * cos(t), r * sin(t));
      }(),
  ];

  static List<Point2D> _shield() {
    final pts = <Point2D>[
      const Point2D(-1, -1),
      const Point2D(1, -1),
      const Point2D(1, 0.1),
    ];
    for (var i = 1; i < 30; i++) {
      final t = i / 30;
      pts.add(Point2D(1 - t * 1.0, 0.1 + 0.9 * (1 - pow(1 - t, 2)) * 1.0));
    }
    pts.add(const Point2D(0, 1));
    for (var i = 1; i < 30; i++) {
      final t = i / 30;
      pts.add(Point2D(-t * 1.0, 0.1 + 0.9 * (1 - pow(t, 2)) * 1.0));
    }
    pts.add(const Point2D(-1, 0.1));
    return pts;
  }

  static List<Point2D> _lShape() => const [
    Point2D(0, 0),
    Point2D(0.45, 0),
    Point2D(0.45, 0.55),
    Point2D(1, 0.55),
    Point2D(1, 1),
    Point2D(0, 1),
  ];

  static List<Point2D> _trapezoid() => const [
    Point2D(0.2, 0),
    Point2D(0.8, 0),
    Point2D(1, 1),
    Point2D(0, 1),
  ];

  static List<Point2D> _quarter() {
    final pts = <Point2D>[const Point2D(0, 1)];
    for (var i = 0; i <= 50; i++) {
      final t = 3 * pi / 2 + (pi / 2) * i / 50;
      pts.add(Point2D(cos(t), 1 + sin(t)));
    }
    return pts;
  }

  static List<Point2D> _semicircle() {
    final pts = <Point2D>[];
    for (var i = 0; i <= 80; i++) {
      final t = pi + pi * i / 80;
      pts.add(Point2D(cos(t), sin(t)));
    }
    return pts;
  }

  static List<Point2D> _leaf() => [
    for (var i = 0; i < 120; i++)
      () {
        final t = 2 * pi * i / 120;
        return Point2D(cos(t), 0.55 * sin(t) * (0.6 + 0.4 * cos(t)));
      }(),
  ];

  static List<Point2D> _star(int tips) => [
    for (var i = 0; i < tips * 2; i++)
      Point2D(
        (i.isEven ? 1.0 : 0.45) * cos(-pi / 2 + pi * i / tips),
        (i.isEven ? 1.0 : 0.45) * sin(-pi / 2 + pi * i / tips),
      ),
  ];

  static final List<CatalogMold> all = _build();

  static List<CatalogMold> _build() {
    final list = <CatalogMold>[];
    var n = 0;
    void add(
      String name,
      double w,
      double h,
      List<Point2D> Function() pts, {
      bool round = false,
    }) {
      n++;
      final code = 'MT-${n.toString().padLeft(3, '0')}';
      list.add(
        CatalogMold(
          code: code,
          name: name,
          widthMm: w,
          heightMm: h,
          round: round,
          build: () => MoldOutline(pts()),
        ),
      );
    }

    add('Círculo', 600, 600, () => _ellipse(180), round: true);
    add('Oval deitada', 900, 550, () => _ellipse(180), round: true);
    add('Oval em pé', 550, 900, () => _ellipse(180), round: true);
    add('Oval grande', 1200, 700, () => _ellipse(200), round: true);
    add('Elipse alta', 450, 1400, () => _ellipse(200), round: true);
    add(
      'Quadrado arredondado',
      600,
      600,
      () => _roundRect(1, 1, 0.15),
      round: true,
    );
    add('Retângulo cantos suaves', 1000, 600, () => _roundRect(1, 0.6, 0.12));
    add(
      'Retângulo cantos redondos',
      1200,
      500,
      () => _roundRect(1, 0.42, 0.3),
      round: true,
    );
    add(
      'Pílula deitada',
      1000,
      400,
      () => _roundRect(1, 0.4, 0.5),
      round: true,
    );
    add('Pílula em pé', 400, 1000, () => _roundRect(0.4, 1, 0.5), round: true);
    add('Super-elipse', 800, 600, () => _superellipse(3.2), round: true);
    add('Super-elipse larga', 1200, 600, () => _superellipse(3.6), round: true);
    add('Arco de porta', 800, 2100, _arch);
    add('Arco de janela', 700, 1100, _arch);
    add('Arco largo', 1400, 900, _arch);
    add('Meia-lua', 1000, 500, _semicircle, round: true);
    add('Quarto de círculo', 700, 700, _quarter, round: true);
    add('Trapézio', 1000, 600, _trapezoid);
    add('Trapézio alto', 500, 1100, _trapezoid);
    add('Hexágono', 700, 606, () => _poly(6, rot: 0), round: true);
    add('Octógono', 700, 700, () => _poly(8, rot: pi / 8), round: true);
    add('Pentágono', 700, 666, () => _poly(5), round: true);
    add('Coração', 700, 650, _heart);
    add('Gota', 450, 700, _drop, round: true);
    add('Escudo', 600, 750, _shield);
    add('Rim', 900, 600, _kidney, round: true);
    add('Folha', 900, 500, _leaf, round: true);
    add('Estrela', 700, 700, () => _star(5));
    add('Forma em L', 800, 800, _lShape);
    for (var i = 0; i < 12; i++) {
      final wide = i % 3 == 0, tall = i % 3 == 1;
      add(
        'Orgânico ${(i + 1).toString().padLeft(2, '0')}',
        wide ? 1100 : (tall ? 600 : 800),
        wide ? 650 : (tall ? 1100 : 800),
        () =>
            _blob(100 + i, stretchX: wide ? 1.6 : 1, stretchY: tall ? 1.6 : 1),
        round: true,
      );
    }
    return list;
  }
}
