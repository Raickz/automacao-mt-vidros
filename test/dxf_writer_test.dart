import 'package:flutter_test/flutter_test.dart';
import 'package:mt_vidros_app/features/mold_scan/services/dxf_writer.dart';
import 'package:mt_vidros_app/features/mold_scan/services/homography.dart';

List<String> codes(String dxf) => dxf.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

List<double> valuesOf(String dxf, String code) {
  final lines = codes(dxf);
  return [
    for (var i = 0; i < lines.length - 1; i++)
      if (lines[i] == code) double.parse(lines[i + 1]),
  ];
}

void main() {
  test('gera um LINE por segmento, fechando o contorno, com os vértices corretos', () {
    final square = [
      const Point2D(0, 0),
      const Point2D(100, 0),
      const Point2D(100, 100),
      const Point2D(0, 100),
    ];

    final dxf = DxfWriter.write(square);

    expect(dxf, contains('SECTION'));
    expect(dxf, contains('ENTITIES'));
    expect(dxf, isNot(contains('LWPOLYLINE')));
    expect(codes(dxf).where((l) => l == 'LINE').length, 4);
    expect(dxf, contains('ENDSEC'));
    expect(dxf, contains('EOF'));

    // 10/20 = start of each segment.
    expect(valuesOf(dxf, '10'), [0.0, 100.0, 100.0, 0.0]);
    // Image Y grows downward; DXF is Y-up, so the shape is flipped.
    expect(valuesOf(dxf, '20'), [100.0, 100.0, 0.0, 0.0]);

    // 11/21 = end of each segment. The last one ends where the first starts.
    expect(valuesOf(dxf, '11').last, valuesOf(dxf, '10').first);
    expect(valuesOf(dxf, '21').last, valuesOf(dxf, '20').first);
  });

  test('inverte o eixo Y e leva o contorno para a origem (sem espelhar a peça)', () {
    // Notch on the TOP of the photo (small y) must end up at the TOP in DXF
    // (large y), far from the board's origin offset.
    final shape = [
      const Point2D(1000, 500),
      const Point2D(1100, 500),
      const Point2D(1100, 540), // top notch lowers the right-top corner
      const Point2D(1200, 540),
      const Point2D(1200, 700),
      const Point2D(1000, 700),
    ];
    final dxf = DxfWriter.write(shape);
    final xs = valuesOf(dxf, '10'), ys = valuesOf(dxf, '20');
    expect(xs.reduce((a, b) => a < b ? a : b), 0.0);
    expect(ys.reduce((a, b) => a < b ? a : b), 0.0);
    expect(ys.first, 200.0); // photo top (y=500) -> DXF top
    expect(ys[2], 160.0); // notch is below the top edge in DXF as well
    expect(dxf, contains(r'$INSUNITS'));
  });

  test('escreve material, espessura e instruções como comentários ASCII (999)', () {
    final dxf = DxfWriter.write(
      const [Point2D(0, 0), Point2D(10, 0), Point2D(0, 10)],
      comments: ['Projeto: Porta cozinha', 'Instruções de corte: fresa 6 mm\ncuidado nas quinas — ok'],
    );
    final lines = codes(dxf);
    final comments = [
      for (var i = 0; i < lines.length - 1; i++)
        if (lines[i] == '999') lines[i + 1],
    ];
    expect(comments, [
      'Projeto: Porta cozinha',
      'Instrucoes de corte: fresa 6 mm',
      'cuidado nas quinas ? ok',
    ]);
    expect(dxf.codeUnits.every((c) => c < 128), isTrue);
    // Comments come before the first section, so readers skip them.
    expect(dxf.indexOf('999'), lessThan(dxf.indexOf('SECTION')));
  });

  test('o nome do arquivo leva nome, material e espessura', () {
    expect(DxfWriter.fileName(name: 'Molde 01', material: 'Vidro', thicknessMm: 4), 'Molde_01_vidro_4mm.dxf');
    expect(
      DxfWriter.fileName(name: 'Porta é/ção', material: ' espelho ', thicknessMm: 3.5),
      'Porta_e_cao_espelho_3.5mm.dxf',
    );
    expect(DxfWriter.fileName(name: '  ', material: '', thicknessMm: null), 'molde.dxf');
  });

  test('rejeita contornos com menos de 3 pontos', () {
    final tooFew = [const Point2D(0, 0), const Point2D(10, 10)];
    expect(() => DxfWriter.write(tooFew), throwsArgumentError);
  });
}
