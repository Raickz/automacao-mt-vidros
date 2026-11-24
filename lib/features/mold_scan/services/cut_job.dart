import 'quote.dart';

/// What goes on the report and on the label besides the outline.
class CutJob {
  final String name;
  final String material;
  final double? glassThicknessMm;
  final String instructions;
  final double marginMm;
  final bool spline;
  final Quote quote;
  final DateTime date;

  CutJob({
    required this.name,
    this.material = '',
    this.glassThicknessMm,
    this.instructions = '',
    this.marginMm = 0,
    this.spline = false,
    this.quote = const Quote(),
    DateTime? date,
  }) : date = date ?? DateTime.now();

  String get dateText =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} '
      '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

  /// Short id printed on the label and inside its QR code.
  String get jobCode =>
      'MT${date.year % 100}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}-'
      '${date.hour.toString().padLeft(2, '0')}${date.minute.toString().padLeft(2, '0')}${date.second.toString().padLeft(2, '0')}';
}
