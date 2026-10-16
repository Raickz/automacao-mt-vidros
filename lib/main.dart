import 'package:flutter/material.dart';

import 'features/mold_scan/screens/mold_scan_kit_screen.dart';
import 'features/mold_scan/theme/mold_scan_theme.dart';

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
      theme: MoldScanTheme.dark(),
      home: const MoldScanKitScreen(),
    );
  }
}
