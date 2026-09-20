import 'package:vector_math/vector_math_64.dart';

class MeasurementPoint {
  final int index;
  final double x;
  final double y;
  final double z;
  final DateTime capturedAt;

  MeasurementPoint({
    required this.index,
    required this.x,
    required this.y,
    required this.z,
    required this.capturedAt,
  });

  factory MeasurementPoint.fromVector3(int index, Vector3 v) {
    return MeasurementPoint(
      index: index,
      x: v.x,
      y: v.y,
      z: v.z,
      capturedAt: DateTime.now(),
    );
  }

  Vector3 toVector3() => Vector3(x, y, z);

  Map<String, dynamic> toJson() => {
        'index': index,
        'x': x,
        'y': y,
        'z': z,
        'capturedAt': capturedAt.toIso8601String(),
      };

  factory MeasurementPoint.fromJson(Map<String, dynamic> json) {
    return MeasurementPoint(
      index: json['index'] as int,
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      z: (json['z'] as num).toDouble(),
      capturedAt: DateTime.parse(json['capturedAt'] as String),
    );
  }
}
