import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mt_vidros_app/features/measurement/services/homography.dart';
import 'package:mt_vidros_app/features/mold_scan/models/mold_board_spec.dart';
import 'package:mt_vidros_app/features/mold_scan/services/contour_extractor.dart';
import 'package:mt_vidros_app/features/mold_scan/services/dxf_writer.dart';
import 'package:mt_vidros_app/features/mold_scan/services/image_rectifier.dart';
import 'package:mt_vidros_app/features/mold_scan/services/polyline_simplifier.dart';

void main() {
  test(
    'pipeline completo recupera um retângulo conhecido fotografado em perspectiva',
    () {
      // 1. Build a synthetic "photo": the board (known background color)
      // photographed through a mild perspective transform, with a
      // rectangular "mold" of known real size (40x60mm) drawn on it.
      const boardWidthMm = MoldBoardSpec.boardWidthMm;
      const boardHeightMm = MoldBoardSpec.boardHeightMm;
      const photoWidth = 800;
      const photoHeight = 600;

      // Real board corners (mm) -> where they land in the synthetic photo
      // (pixels), simulating a camera held at a slight angle.
      final boardMmCorners = [
        const Point2D(0, 0),
        Point2D(boardWidthMm, 0),
        Point2D(boardWidthMm, boardHeightMm),
        const Point2D(0, boardHeightMm),
      ];
      final boardPixelCorners = [
        const Point2D(60, 80),
        const Point2D(760, 40),
        const Point2D(780, 560),
        const Point2D(40, 540),
      ];
      final mmToPixel = Homography.fromCorrespondences(boardMmCorners, boardPixelCorners);

      final photo = img.Image(width: photoWidth, height: photoHeight, numChannels: 3);
      img.fill(
        photo,
        color: img.ColorRgb8(
          MoldBoardSpec.backgroundR,
          MoldBoardSpec.backgroundG,
          MoldBoardSpec.backgroundB,
        ),
      );

      // Draw a filled 40x60mm "mold" centered on the board, in photo pixels,
      // by testing every pixel in a bounding box against the mm-space rect.
      const moldWidthMm = 40.0;
      const moldHeightMm = 60.0;
      final moldLeftMm = boardWidthMm / 2 - moldWidthMm / 2;
      final moldTopMm = boardHeightMm / 2 - moldHeightMm / 2;
      final pixelToMm = mmToPixel.invert();

      for (var y = 0; y < photoHeight; y++) {
        for (var x = 0; x < photoWidth; x++) {
          final mm = pixelToMm.apply(Point2D(x.toDouble(), y.toDouble()));
          final insideMold = mm.x >= moldLeftMm &&
              mm.x <= moldLeftMm + moldWidthMm &&
              mm.y >= moldTopMm &&
              mm.y <= moldTopMm + moldHeightMm;
          if (insideMold) {
            photo.setPixelRgb(x, y, 200, 30, 30);
          }
        }
      }

      // 2. Run the real pipeline: rectify -> extract contour -> simplify.
      const pixelsPerMm = 3.0;
      final rectified = ImageRectifier.rectify(
        source: photo,
        pixelToMm: pixelToMm,
        widthMm: boardWidthMm,
        heightMm: boardHeightMm,
        pixelsPerMm: pixelsPerMm,
      );

      final rawContour = ContourExtractor.extractFromImage(
        image: rectified,
        backgroundR: MoldBoardSpec.backgroundR,
        backgroundG: MoldBoardSpec.backgroundG,
        backgroundB: MoldBoardSpec.backgroundB,
        pixelsPerMm: pixelsPerMm,
        colorThreshold: MoldBoardSpec.colorMatchThreshold,
      );

      final simplified = PolylineSimplifier.simplify(rawContour, 1.0);

      // 3. The recovered bounding box should match the known 40x60mm mold
      // within a couple of millimeters (pixel/rounding tolerance).
      final xs = simplified.map((p) => p.x);
      final ys = simplified.map((p) => p.y);
      final recoveredWidth = xs.reduce((a, b) => a > b ? a : b) - xs.reduce((a, b) => a < b ? a : b);
      final recoveredHeight = ys.reduce((a, b) => a > b ? a : b) - ys.reduce((a, b) => a < b ? a : b);

      expect(recoveredWidth, closeTo(moldWidthMm, 2.0));
      expect(recoveredHeight, closeTo(moldHeightMm, 2.0));

      // 4. The simplified contour should still produce a valid DXF file.
      final dxf = DxfWriter.write(simplified);
      expect(dxf, contains('LWPOLYLINE'));
    },
  );
}
