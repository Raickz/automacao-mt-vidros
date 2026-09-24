import 'package:uuid/uuid.dart';

import '../../measurement/services/homography.dart';

const _uuid = Uuid();

class MoldShape {
  final String id;
  final String name;
  final String material;
  final double thicknessMm;
  final String cuttingInstructions;
  final List<Point2D> contourMm;
  final DateTime createdAt;

  MoldShape({
    String? id,
    required this.name,
    required this.material,
    required this.thicknessMm,
    required this.cuttingInstructions,
    required this.contourMm,
    DateTime? createdAt,
  })  : id = id ?? _uuid.v4(),
        createdAt = createdAt ?? DateTime.now();

  double get boundingWidthMm {
    final xs = contourMm.map((p) => p.x);
    return xs.reduce((a, b) => a > b ? a : b) - xs.reduce((a, b) => a < b ? a : b);
  }

  double get boundingHeightMm {
    final ys = contourMm.map((p) => p.y);
    return ys.reduce((a, b) => a > b ? a : b) - ys.reduce((a, b) => a < b ? a : b);
  }
}
