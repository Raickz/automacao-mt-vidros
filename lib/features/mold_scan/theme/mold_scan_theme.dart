import 'package:flutter/material.dart';

import 'mold_scan_colors.dart';

/// Type: Barlow (text) and Barlow Condensed (headlines and measurement
/// readouts) — a superfamily drawn after industrial signage, which is what
/// a glass shop's labels and cutting-table markings look like.
class MoldScanType {
  static const text = 'Barlow';
  static const display = 'BarlowCondensed';

  static TextStyle headline(double size) => TextStyle(
    fontFamily: display,
    fontSize: size,
    fontWeight: FontWeight.w600,
    height: 1.02,
    color: MoldScanColors.textPrimary,
  );

  /// Big numbers (measurements). Tabular figures keep digits from jittering
  /// between photos.
  static TextStyle readout(double size) => TextStyle(
    fontFamily: display,
    fontSize: size,
    fontWeight: FontWeight.w700,
    height: 1,
    color: MoldScanColors.textPrimary,
    fontFeatures: const [FontFeature.tabularFigures()],
  );
}

/// Theme for the whole app — the mold scanner is the only tool in it.
class MoldScanTheme {
  static ThemeData dark() {
    final base = ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      fontFamily: MoldScanType.text,
    );
    return base.copyWith(
      scaffoldBackgroundColor: MoldScanColors.background,
      colorScheme: base.colorScheme.copyWith(
        brightness: Brightness.dark,
        primary: MoldScanColors.accent,
        onPrimary: const Color(0xFF032A2A),
        secondary: MoldScanColors.accentAlt,
        surface: MoldScanColors.surface,
        onSurface: MoldScanColors.textPrimary,
        error: MoldScanColors.danger,
        // Selected segments and chips: teal from the logo, not M3's default lilac.
        secondaryContainer: const Color(0xFF0E6E73),
        onSecondaryContainer: MoldScanColors.textPrimary,
        outline: MoldScanColors.border,
        outlineVariant: MoldScanColors.border,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: MoldScanColors.surface,
        selectedColor: const Color(0xFF0E6E73),
        checkmarkColor: MoldScanColors.textPrimary,
        side: const BorderSide(color: MoldScanColors.border),
        labelStyle: const TextStyle(
          color: MoldScanColors.textPrimary,
          fontWeight: FontWeight.w500,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? MoldScanColors.background
              : MoldScanColors.textSecondary,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? MoldScanColors.accent
              : MoldScanColors.surfaceLight,
        ),
      ),
      textTheme: base.textTheme.apply(
        fontFamily: MoldScanType.text,
        bodyColor: MoldScanColors.textPrimary,
        displayColor: MoldScanColors.textPrimary,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: MoldScanColors.background,
        foregroundColor: MoldScanColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      dividerColor: MoldScanColors.border,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: MoldScanColors.surface,
        hintStyle: const TextStyle(color: MoldScanColors.textSecondary),
        labelStyle: const TextStyle(color: MoldScanColors.textSecondary),
        floatingLabelStyle: const TextStyle(color: MoldScanColors.accentAlt),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: MoldScanColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: MoldScanColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(
            color: MoldScanColors.accent,
            width: 1.6,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: MoldScanColors.accent,
          foregroundColor: const Color(0xFF032A2A),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: MoldScanColors.textPrimary,
          side: const BorderSide(color: MoldScanColors.border),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          textStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 15),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: MoldScanColors.accentAlt),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: MoldScanColors.accent,
        linearTrackColor: MoldScanColors.surfaceLight,
      ),
    );
  }
}
