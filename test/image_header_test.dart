import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mt_vidros_app/features/mold_scan/services/mold_scan_pipeline.dart';

void main() {
  test('tamanho lido do cabeçalho JPEG de uma foto real', () {
    final bytes = File('test/real/fixtures/papelao_70x25.jpg')
        .readAsBytesSync();
    expect(MoldScanPipeline.imageSize(bytes), (3200, 2400));
    expect(() => MoldScanPipeline.checkHeader(bytes), returnsNormally);
  });

  test('tamanho do PNG e do JPEG gerados', () {
    final im = img.Image(width: 321, height: 123);
    expect(MoldScanPipeline.imageSize(img.encodePng(im)), (321, 123));
    expect(MoldScanPipeline.imageSize(img.encodeJpg(im)), (321, 123));
  });

  test('PNG que declara 50000 x 50000 é recusado sem decodificar', () {
    final png = img.encodePng(img.Image(width: 4, height: 4));
    void put32(int at, int v) {
      png[at] = (v >> 24) & 0xFF;
      png[at + 1] = (v >> 16) & 0xFF;
      png[at + 2] = (v >> 8) & 0xFF;
      png[at + 3] = v & 0xFF;
    }

    put32(16, 50000);
    put32(20, 50000);
    expect(
      () => MoldScanPipeline.checkHeader(png),
      throwsA(isA<MoldScanException>()),
    );
  });

  test('arquivo que não é imagem, vazio ou cortado é recusado', () {
    for (final b in [
      Uint8List(0),
      Uint8List.fromList('não é uma foto'.codeUnits),
      Uint8List.fromList([0xFF, 0xD8, 0xFF]),
    ]) {
      expect(MoldScanPipeline.imageSize(b), isNull);
      expect(
        () => MoldScanPipeline.checkHeader(b),
        throwsA(isA<MoldScanException>()),
      );
    }
  });
}
