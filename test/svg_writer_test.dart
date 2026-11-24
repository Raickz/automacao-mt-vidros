import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mt_vidros_app/features/mold_scan/services/homography.dart';
import 'package:mt_vidros_app/features/mold_scan/services/mold_outline.dart';
import 'package:mt_vidros_app/features/mold_scan/services/svg_writer.dart';

const square = MoldOutline([
  Point2D(0, 0),
  Point2D(100, 0),
  Point2D(100, 50),
  Point2D(0, 50),
]);

void main() {
  test(
    'o arquivo SVG sai em UTF-8 válido, com acentos e travessão intactos',
    () {
      final bytes = SvgWriter.bytes(square, title: 'Sacada – Área de serviço');
      // Antes saíam as unidades UTF-16 truncadas para byte: "Á" virava um byte
      // solto (UTF-8 inválido) e "–" virava o caractere de controle 0x13.
      final text = utf8.decode(bytes); // lança se não for UTF-8
      expect(text, contains('<title>Sacada – Área de serviço</title>'));
      expect(bytes.every((b) => b != 0x13), isTrue);
    },
  );

  test('nome hostil não injeta marcação no SVG', () {
    final svg = SvgWriter.write(
      square,
      title: '</title><script>alert(1)</script>&"\'\u0001\u0008',
    );
    expect(svg, isNot(contains('<script>')));
    expect(svg, contains('&lt;/title&gt;&lt;script&gt;'));
    expect(svg, contains('&amp;&quot;&apos;</title>'));
    expect(svg.codeUnits.any((c) => c < 0x20 && c != 0x0A), isFalse);
    expect('<title>'.allMatches(svg).length, 1);
  });

  test('contorno com NaN não vira SVG quebrado', () {
    expect(
      () => SvgWriter.write(
        const MoldOutline([
          Point2D(0, 0),
          Point2D(double.nan, 1),
          Point2D(1, 1),
        ]),
      ),
      throwsArgumentError,
    );
  });
}
