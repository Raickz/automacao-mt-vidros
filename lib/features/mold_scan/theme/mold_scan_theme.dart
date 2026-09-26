import 'package:flutter/material.dart';

import 'mold_scan_colors.dart';

/// Scoped dark theme for the mold-scanning screens only — the rest of the
/// app keeps its light Material theme. Applied locally via a [Theme]
/// wrapper rather than changed globally.
class MoldScanTheme {
  static ThemeData dark() {
    final base = ThemeData(brightness: Brightness.dark, useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: MoldScanColors.background,
      colorScheme: base.colorScheme.copyWith(
        brightness: Brightness.dark,
        primary: MoldScanColors.accent,
        secondary: MoldScanColors.accentAlt,
        surface: MoldScanColors.surface,
        onSurface: MoldScanColors.textPrimary,
        error: MoldScanColors.danger,
      ),
      textTheme: base.textTheme.apply(
        bodyColor: MoldScanColors.textPrimary,
        displayColor: MoldScanColors.textPrimary,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: MoldScanColors.surface,
        foregroundColor: MoldScanColors.textPrimary,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      dividerColor: MoldScanColors.border,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: MoldScanColors.surfaceLight,
        hintStyle: const TextStyle(color: MoldScanColors.textSecondary),
        labelStyle: const TextStyle(color: MoldScanColors.textSecondary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: MoldScanColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: MoldScanColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: MoldScanColors.accent, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: MoldScanColors.accent,
          foregroundColor: const Color(0xFF04211D),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: MoldScanColors.accentAlt,
          side: const BorderSide(color: MoldScanColors.border),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: MoldScanColors.accent),
    );
  }
}
