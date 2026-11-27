import 'dart:convert';

import 'package:web/web.dart' as web;

import 'activation.dart';

/// What the login keeps in this browser: this device's code, the
/// activations issued for it, the open session and failed attempts. Every
/// access is guarded (storage may be blocked); a device whose storage is
/// cleared gets a new code and needs a new activation, which is also how the
/// administrator withdraws access before an activation expires.
class AuthStore {
  static const _deviceKey = 'mt_device_code_v1';
  static const _activationsKey = 'mt_activations_v1';
  static const _sessionKey = 'mt_session_v1';
  static const _failKey = 'mt_login_fail_v1';

  /// How long a login lasts on this device.
  static const sessionLength = Duration(hours: 12);

  static web.Storage get _s => web.window.localStorage;

  /// This device's code, created on first use. Null when the browser
  /// refuses storage (private window): then nothing can be activated.
  static String? deviceCode() {
    try {
      final saved = _s.getItem(_deviceKey);
      if (saved != null && isValidDeviceCode(saved)) {
        return normalizeDeviceCode(saved);
      }
      final code = newDeviceCode();
      _s.setItem(_deviceKey, code);
      return _s.getItem(_deviceKey) == code ? code : null;
    } catch (_) {
      return null;
    }
  }

  static List<Activation> activations() {
    try {
      final raw = _s.getItem(_activationsKey);
      if (raw == null) return [];
      final list = jsonDecode(raw);
      if (list is! List) return [];
      return [
        for (final t in list)
          if (t is String)
            if (Activation.parse(t) case final Activation a) a,
      ];
    } catch (_) {
      return [];
    }
  }

  /// Keeps [a], replacing an older activation of the same user.
  static bool addActivation(Activation a) {
    try {
      final list = [
        for (final o in activations())
          if (!sameUser(o.user, a.user)) o.token,
        a.token,
      ];
      _s.setItem(_activationsKey, jsonEncode(list));
      return true;
    } catch (_) {
      return false;
    }
  }

  static void removeActivation(String user) {
    try {
      final list = [
        for (final o in activations())
          if (!sameUser(o.user, user)) o.token,
      ];
      _s.setItem(_activationsKey, jsonEncode(list));
    } catch (_) {}
  }

  /// The logged-in user and until when, or null.
  static (String, DateTime)? session() {
    try {
      final raw = _s.getItem(_sessionKey);
      if (raw == null) return null;
      final m = jsonDecode(raw);
      if (m is! Map || m['u'] is! String || m['until'] is! int) return null;
      final until = DateTime.fromMillisecondsSinceEpoch(m['until'] as int);
      if (!DateTime.now().isBefore(until)) return null;
      return (m['u'] as String, until);
    } catch (_) {
      return null;
    }
  }

  static void startSession(String user) {
    try {
      _s.setItem(
        _sessionKey,
        jsonEncode({
          'u': user,
          'until': DateTime.now().add(sessionLength).millisecondsSinceEpoch,
        }),
      );
      _s.removeItem(_failKey);
    } catch (_) {}
  }

  static void endSession() {
    try {
      _s.removeItem(_sessionKey);
    } catch (_) {}
  }

  /// When login is allowed again after repeated wrong passwords, or null.
  static DateTime? lockedUntil() {
    try {
      final raw = _s.getItem(_failKey);
      if (raw == null) return null;
      final m = jsonDecode(raw) as Map;
      final until = m['until'];
      if (until is! int) return null;
      final t = DateTime.fromMillisecondsSinceEpoch(until);
      return DateTime.now().isBefore(t) ? t : null;
    } catch (_) {
      return null;
    }
  }

  /// Counts a wrong password; from the 5th in a row each one locks login
  /// for longer (30 s, 1 min, 2 min... up to 15 min).
  static void recordFailure() {
    try {
      final raw = _s.getItem(_failKey);
      var count = 0;
      if (raw != null) {
        final m = jsonDecode(raw);
        if (m is Map && m['n'] is int) count = m['n'] as int;
      }
      count++;
      final wait = count < 5 ? 0 : (30 * (1 << (count - 5))).clamp(30, 900);
      _s.setItem(
        _failKey,
        jsonEncode({
          'n': count,
          'until': DateTime.now()
              .add(Duration(seconds: wait))
              .millisecondsSinceEpoch,
        }),
      );
    } catch (_) {}
  }
}
