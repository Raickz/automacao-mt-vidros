import 'mold_outline.dart';

/// Quick glass quote. Glass is charged by the rectangle of sheet the piece
/// uses (width x height), not by the area of the curved shape; edge work
/// (lapidação/polimento) is charged by the length of the cut line.
class Quote {
  final double pricePerM2;
  final double pricePerMeter;
  final int quantity;

  const Quote({this.pricePerM2 = 0, this.pricePerMeter = 0, this.quantity = 1});

  bool get isEmpty => pricePerM2 <= 0 && pricePerMeter <= 0;

  double chargedAreaM2(MoldOutline o) => o.width * o.height / 1e6;
  double edgeMeters(MoldOutline o) => o.perimeterMm / 1000;

  double glass(MoldOutline o) => chargedAreaM2(o) * pricePerM2 * quantity;
  double edge(MoldOutline o) => edgeMeters(o) * pricePerMeter * quantity;
  double total(MoldOutline o) => glass(o) + edge(o);

  /// Largest price per unit accepted from the form; above it (or negative,
  /// or not a number) the price counts as not given.
  static const maxUnitPrice = 1e6;

  /// [typed] as a usable unit price: 0 when missing, negative, absurd.
  static double unitPrice(double? typed) =>
      typed == null || !typed.isFinite || typed < 0 || typed > maxUnitPrice
      ? 0
      : typed;

  /// 1234.5 -> "R$ 1.234,50"; -2 -> "-R$ 2,00". A value that is not a
  /// number, or beyond R$ 1 trillion, shows as "R$ —" instead of throwing
  /// (the editor page would stop drawing).
  static String brl(double v) {
    if (!v.isFinite || v.abs() >= 1e12) return 'R\$ —';
    if (v < 0) return '-${brl(-v)}';
    final cents = (v * 100).round();
    final reais = (cents ~/ 100).toString();
    final buf = StringBuffer();
    for (var i = 0; i < reais.length; i++) {
      if (i > 0 && (reais.length - i) % 3 == 0) buf.write('.');
      buf.write(reais[i]);
    }
    return 'R\$ $buf,${(cents % 100).toString().padLeft(2, '0')}';
  }
}
