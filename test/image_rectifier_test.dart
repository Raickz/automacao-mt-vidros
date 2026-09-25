import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mt_vidros_app/features/measurement/services/homography.dart';
import 'package:mt_vidros_app/features/mold_scan/services/image_rectifier.dart';

void main() {
  test('homografia identidade reproduz a imagem original pixel a pixel', () {
    final source = img.Image(width: 20, height: 20, numChannels: 3);
    img.fill(source, color: img.ColorRgb8(10, 10, 10));
    source.setPixelRgb(5, 5, 255, 0, 0);
    source.setPixelRgb(15, 15, 0, 0, 255);

    final identityCorners = [
      const Point2D(0, 0),
      const Point2D(19, 0),
      const Point2D(19, 19),
      const Point2D(0, 19),
    ];
    final identity = Homography.fromCorrespondences(identityCorners, identityCorners);

    final result = ImageRectifier.rectify(
      source: source,
      pixelToMm: identity,
      widthMm: 20,
      heightMm: 20,
      pixelsPerMm: 1,
    );

    final redPixel = result.getPixel(5, 5);
    expect(redPixel.r, 255);
    expect(redPixel.g, 0);
    expect(redPixel.b, 0);

    final bluePixel = result.getPixel(15, 15);
    expect(bluePixel.r, 0);
    expect(bluePixel.b, 255);
  });

  test('escala 2x reduz a imagem retificada corretamente', () {
    final source = img.Image(width: 40, height: 40, numChannels: 3);
    img.fill(source, color: img.ColorRgb8(0, 0, 0));
    source.setPixelRgb(20, 20, 255, 255, 0);

    // pixel space is 2x the mm space: mm (10,10) -> pixel (20,20)
    final srcCorners = [
      const Point2D(0, 0),
      const Point2D(40, 0),
      const Point2D(40, 40),
      const Point2D(0, 40),
    ];
    final mmCorners = [
      const Point2D(0, 0),
      const Point2D(20, 0),
      const Point2D(20, 20),
      const Point2D(0, 20),
    ];
    final homography = Homography.fromCorrespondences(srcCorners, mmCorners);

    final result = ImageRectifier.rectify(
      source: source,
      pixelToMm: homography,
      widthMm: 20,
      heightMm: 20,
      pixelsPerMm: 1,
    );

    expect(result.width, 20);
    expect(result.height, 20);
    final yellow = result.getPixel(10, 10);
    expect(yellow.r, 255);
    expect(yellow.g, 255);
    expect(yellow.b, 0);
  });

  test('não cria borda preta artificial quando a foto não tem margem ao redor do quadro', () {
    // Regression test: a source photo cropped tightly to the board (no
    // surrounding margin) used to leave a black ring around the rectified
    // output wherever sampling rounded slightly out of bounds, which made
    // contour extraction trace the whole board instead of the object on it.
    const background = 20;
    final source = img.Image(width: 30, height: 30, numChannels: 3);
    img.fill(source, color: img.ColorRgb8(background, 90, 200));

    final corners = [
      const Point2D(0, 0),
      const Point2D(29, 0),
      const Point2D(29, 29),
      const Point2D(0, 29),
    ];
    final identity = Homography.fromCorrespondences(corners, corners);

    final result = ImageRectifier.rectify(
      source: source,
      pixelToMm: identity,
      widthMm: 30,
      heightMm: 30,
      pixelsPerMm: 1,
    );

    for (final xy in [
      (0, 0), (result.width - 1, 0), (0, result.height - 1), (result.width - 1, result.height - 1),
    ]) {
      final pixel = result.getPixel(xy.$1, xy.$2);
      expect(pixel.r, background, reason: 'canto (${xy.$1},${xy.$2}) não deveria estar preto');
    }
  });
}
