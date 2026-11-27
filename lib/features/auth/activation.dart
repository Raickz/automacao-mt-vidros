import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

/// Access is tied to one device: the administrator issues, for a given
/// device code, a signed activation carrying the user, a salted hash of the
/// password and an expiry date. The app only accepts an activation whose
/// signature checks out with the public key built into it, whose device code
/// is this device's, and that has not expired; then the password typed at
/// login must match the hash. The same user and password on another phone
/// or PC finds no activation for that device and is refused.
///
/// The app runs entirely in the browser and its code is public, so this is a
/// strong barrier for everyday use, not protection against someone who
/// rewrites the app.
class Activation {
  final String user;
  final String name;
  final String device;
  final Uint8List salt;
  final Uint8List hash;
  final int iterations;
  final DateTime expires;
  final DateTime issued;

  /// The exact text the signature covers (base64url of the payload JSON).
  final String signedPart;
  final Uint8List signature;

  /// The whole token, as pasted, normalized.
  final String token;

  const Activation({
    required this.user,
    required this.name,
    required this.device,
    required this.salt,
    required this.hash,
    required this.iterations,
    required this.expires,
    required this.issued,
    required this.signedPart,
    required this.signature,
    required this.token,
  });

  static const prefix = 'MTA1';

  bool isExpired(DateTime now) => !now.isBefore(expires);

  /// Parses a pasted activation (spaces and line breaks are ignored), or
  /// returns null when it is not one. Does NOT check the signature.
  static Activation? parse(String text) {
    final t = text.replaceAll(RegExp(r'\s'), '');
    final parts = t.split('.');
    if (parts.length != 3 || parts[0] != prefix) return null;
    try {
      final payload = jsonDecode(utf8.decode(b64d(parts[1])));
      if (payload is! Map) return null;
      final user = payload['u'], name = payload['n'], device = payload['d'];
      final salt = payload['s'], hash = payload['h'], it = payload['i'];
      final exp = payload['x'], iss = payload['t'];
      if (payload['v'] != 1 ||
          user is! String ||
          device is! String ||
          salt is! String ||
          hash is! String ||
          it is! int ||
          exp is! int ||
          iss is! int) {
        return null;
      }
      if (user.trim().isEmpty || it < 10000 || it > 5000000) return null;
      final sig = b64d(parts[2]);
      if (sig.length != 64) return null;
      return Activation(
        user: user.trim(),
        name: name is String ? name : user.trim(),
        device: normalizeDeviceCode(device),
        salt: b64d(salt),
        hash: b64d(hash),
        iterations: it,
        expires: DateTime.fromMillisecondsSinceEpoch(exp),
        issued: DateTime.fromMillisecondsSinceEpoch(iss),
        signedPart: parts[1],
        signature: sig,
        token: t,
      );
    } catch (_) {
      return null;
    }
  }

  static Uint8List b64d(String s) {
    var n = s.replaceAll('-', '+').replaceAll('_', '/');
    while (n.length % 4 != 0) {
      n += '=';
    }
    return base64.decode(n);
  }

  static String b64e(List<int> bytes) => base64
      .encode(bytes)
      .replaceAll('+', '-')
      .replaceAll('/', '_')
      .replaceAll('=', '');
}

/// Letters and digits that can't be mistaken for each other when read out
/// or typed (no 0/O, 1/I/L).
const _alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

/// A new random device code, e.g. "K7QD-9XMA-PW3R".
String newDeviceCode([Random? random]) {
  final r = random ?? Random.secure();
  final chars = [
    for (var i = 0; i < 12; i++) _alphabet[r.nextInt(_alphabet.length)],
  ];
  return '${chars.sublist(0, 4).join()}-${chars.sublist(4, 8).join()}-${chars.sublist(8).join()}';
}

/// Upper case, no spaces, grouped by 4 — how codes are compared.
String normalizeDeviceCode(String code) {
  final c = code.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  if (c.length != 12) return c;
  return '${c.substring(0, 4)}-${c.substring(4, 8)}-${c.substring(8)}';
}

bool isValidDeviceCode(String code) {
  final c = normalizeDeviceCode(code);
  return RegExp('^[$_alphabet]{4}-[$_alphabet]{4}-[$_alphabet]{4}\$')
      .hasMatch(c);
}

/// Same user name, ignoring case and surrounding spaces.
bool sameUser(String a, String b) =>
    a.trim().toLowerCase() == b.trim().toLowerCase();

/// Compares two hashes in time independent of where they differ.
bool constantTimeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}
