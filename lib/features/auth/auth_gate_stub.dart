import 'package:flutter/widgets.dart';

/// Outside the web build (the old Android app) there is no login gate.
class AuthGate extends StatelessWidget {
  final Widget child;

  const AuthGate({super.key, required this.child});

  @override
  Widget build(BuildContext context) => child;
}
