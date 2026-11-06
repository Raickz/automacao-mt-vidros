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

  /// 1234.5 -> "R$ 1.234,50"
  static String brl(double v) {
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
