import 'package:flutter/material.dart';

class AppTheme {
  static ThemeData light() {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF0F6FB3),
        brightness: Brightness.light,
      ),
      appBarTheme: const AppBarTheme(centerTitle: true),
    );
  }
}
