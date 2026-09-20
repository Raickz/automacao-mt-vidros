import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'features/measurement/screens/home_screen.dart';

void main() {
  runApp(const MtVidrosApp());
}

class MtVidrosApp extends StatelessWidget {
  const MtVidrosApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MT Vidros',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: const HomeScreen(),
    );
  }
}
