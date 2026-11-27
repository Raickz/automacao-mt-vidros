import 'package:flutter/widgets.dart';

/// Who is logged in, for the screens below the login gate.
class AuthScope extends InheritedWidget {
  final String userName;
  final VoidCallback logout;

  const AuthScope({
    super.key,
    required this.userName,
    required this.logout,
    required super.child,
  });

  /// Null when the app runs without the login gate (not the web build).
  static AuthScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AuthScope>();

  @override
  bool updateShouldNotify(AuthScope old) => old.userName != userName;
}
