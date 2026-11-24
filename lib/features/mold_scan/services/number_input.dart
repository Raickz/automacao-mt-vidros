/// Reads a number typed by the user: comma or dot decimals, spaces around
/// ignored. Null when it is not a finite number — `double.tryParse` alone
/// accepts "NaN" and "Infinity", which slip past every `< min` / `> max`
/// check (all comparisons with NaN are false) and end up as NaN
/// coordinates in the DXF or as a crash.
double? parseDecimal(String text) {
  final v = double.tryParse(text.trim().replaceAll(',', '.'));
  return v != null && v.isFinite ? v : null;
}
