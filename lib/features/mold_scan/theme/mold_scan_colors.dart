import 'package:flutter/material.dart';

/// Palette built from the Marabá Temper logo: its navy plate (#013D59) and
/// glass-edge teal (#1BBFBB). The page sits one step darker than the logo's
/// plate so the logo reads as an object placed on the surface, not a patch.
class MoldScanColors {
  /// Vidro profundo — page background.
  static const background = Color(0xFF012B40);

  /// Azul Temper — the logo's own navy; raised panels.
  static const surface = Color(0xFF013D59);
  static const surfaceLight = Color(0xFF0B4D6E);
  static const border = Color(0xFF17607F);

  /// Aresta — the teal of a cut glass edge. Used for the one primary action
  /// and for active state, nowhere else.
  static const accent = Color(0xFF1BBFBB);
  static const accentAlt = Color(0xFF29D6C7);

  static const textPrimary = Color(0xFFE6F2F4);
  static const textSecondary = Color(0xFF8FB2BF);

  /// Papelão — the warm color of a cardboard template; warnings only.
  static const warning = Color(0xFFE0A458);
  static const danger = Color(0xFFFF7B7B);

  /// Corte — the line color used for the detected contour in the preview
  /// image, so the legend in the UI matches what is drawn on the photo.
  static const cut = Color(0xFFFF2878);
}
