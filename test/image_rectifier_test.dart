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
}
