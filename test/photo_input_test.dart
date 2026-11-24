import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mt_vidros_app/features/mold_scan/models/board_geometry.dart';
import 'package:mt_vidros_app/features/mold_scan/services/mold_scan_pipeline.dart';

import 'mold_scan_e2e_test.dart' show scene, trapezoid, expectMold;
import 'support/synthetic_scene.dart';

/// PNG CRC-32 (the test only needs it to forge a header).
int _crc32(List<int> bytes) {
  var c = 0xFFFFFFFF;
  for (final b in bytes) {
    c ^= b;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? (c >> 1) ^ 0xEDB88320 : c >> 1;
    }
  }
  return c ^ 0xFFFFFFFF;
}

void main() {
  const timeout = Timeout(Duration(minutes: 3));

  test('PNG de 16 bits por canal é medido igual à foto normal', () async {
    // Antes os bytes de 16 bits eram lidos como se fossem RGB de 8 bits e
    // o app dizia "Encontrei só 0 dos 4 marcadores".
    final photo = scene
        .render(const SceneConfig(moldPolygonMm: trapezoid, noiseSigma: 3))
        .convert(format: img.Format.uint16);
    final r = await MoldScanPipeline.run(
      img.encodePng(photo),
      board: BoardGeometry.standard,
    );
    expectMold(r.contourMm, trapezoid);
  }, timeout: timeout);

  test('decodePhoto entrega sempre RGB de 8 bits', () {
    final gray = img.Image(width: 40, height: 30, numChannels: 1);
    final p = MoldScanPipeline.decodePhoto(img.encodePng(gray));
    expect(p.numChannels, 3);
    expect(p.format, img.Format.uint8);
    final paletted = img.quantize(
      img.Image(width: 40, height: 30)..clear(img.ColorRgb8(200, 10, 10)),
      numberOfColors: 4,
    );
    final q = MoldScanPipeline.decodePhoto(img.encodePng(paletted));
    expect(q.hasPalette, isFalse);
    expect(q.numChannels, 3);
    expect(q.getPixel(5, 5).r, closeTo(200, 2));
  });

  test('a rotação do EXIF sobrevive à conversão para 8 bits RGB', () {
    final photo = img.Image(width: 40, height: 20, format: img.Format.uint16);
    photo.exif.imageIfd.orientation = 6;
    final p = MoldScanPipeline.toRgb8(photo);
    expect(p.format, img.Format.uint8);
    expect(p.numChannels, 3);
    expect(p.exif.imageIfd.orientation, 6);
  });

  test('arquivo que declara dimensões absurdas é recusado sem decodificar', () {
    final png = Uint8List.fromList(
      img.encodePng(img.Image(width: 8, height: 8)),
    );
    // IHDR: width at byte 16, height at 20, CRC of "IHDR"+data at 29.
    final bd = ByteData.sublistView(png);
    bd.setUint32(16, 60000);
    bd.setUint32(20, 60000);
    bd.setUint32(29, _crc32(png.sublist(12, 29)));
    expect(
      () => MoldScanPipeline.decodePhoto(png),
      throwsA(
        isA<MoldScanException>().having(
          (e) => e.message,
          'mensagem',
          contains('grande demais'),
        ),
      ),
    );
  });

  test('arquivo que não é imagem dá a mensagem de foto ilegível', () {
    expect(
      () => MoldScanPipeline.decodePhoto(
        Uint8List.fromList('<svg onload=alert(1)>'.codeUnits),
      ),
      throwsA(isA<MoldScanException>()),
    );
    expect(
      () => MoldScanPipeline.decodePhoto(Uint8List(0)),
      throwsA(isA<MoldScanException>()),
    );
  });
}
