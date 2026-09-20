import 'package:uuid/uuid.dart';

import '../services/measurement_calculator.dart';
import 'measurement_point.dart';
import 'piece_type.dart';

const _uuid = Uuid();

class MeasurementResult {
  final String id;
  final PieceType pieceType;
  final List<MeasurementPoint> points;
  final String deviceLabel;
  final DateTime createdAt;
  final String? notes;

  MeasurementResult({
    String? id,
    required this.pieceType,
    required this.points,
    required this.deviceLabel,
    DateTime? createdAt,
    this.notes,
  })  : id = id ?? _uuid.v4(),
        createdAt = createdAt ?? DateTime.now();

  RectangleMetrics get rectangleMetrics {
    assert(pieceType.isRectangular);
    return MeasurementCalculator.computeRectangle(points);
  }

  FreeformMetrics get freeformMetrics {
    assert(!pieceType.isRectangular);
    return MeasurementCalculator.computeFreeform(points);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'pieceType': pieceType.name,
        'points': points.map((p) => p.toJson()).toList(),
        'deviceLabel': deviceLabel,
        'createdAt': createdAt.toIso8601String(),
        'notes': notes,
      };

  factory MeasurementResult.fromJson(Map<String, dynamic> json) {
    return MeasurementResult(
      id: json['id'] as String,
      pieceType: PieceType.values.byName(json['pieceType'] as String),
      points: (json['points'] as List)
          .map((p) => MeasurementPoint.fromJson(p as Map<String, dynamic>))
          .toList(),
      deviceLabel: json['deviceLabel'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      notes: json['notes'] as String?,
    );
  }
}
