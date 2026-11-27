import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

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

  /// Made on this device after a valid 9-digit number (sealed with the
  /// HMAC key), not issued as a signed text by the administrator.
  final bool local;

  const Activation({
    this.local = false,
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
  static const localPrefix = 'MTL1';

  bool isExpired(DateTime now) => !now.isBefore(expires);

  /// Parses a pasted activation (spaces and line breaks are ignored), or
  /// returns null when it is not one. Does NOT check the signature.
  static Activation? parse(String text) {
    final t = text.replaceAll(RegExp(r'\s'), '');
    final parts = t.split('.');
    if (parts.length != 3 || (parts[0] != prefix && parts[0] != localPrefix)) {
      return null;
    }
    final local = parts[0] == localPrefix;
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
      if (sig.length != (local ? 32 : 64)) return null;
      return Activation(
        local: local,
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

/// Letters and digits of the old 12-character codes (no 0/O, 1/I/L). Devices
/// activated with such a code keep it, so their activations stay valid.
const _alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

/// A new random device code, e.g. "K7QD-9XMA-PW3R".
String newDeviceCode([Random? random]) {
  final r = random ?? Random.secure();
  final chars = [
    for (var i = 0; i < 12; i++) _alphabet[r.nextInt(_alphabet.length)],
  ];
  return '${chars.sublist(0, 4).join()}-${chars.sublist(4, 8).join()}-${chars.sublist(8).join()}';
}

/// How long (days) an activation by number can last; the administrator picks
/// one when issuing it.
const codeDurations = [30, 90, 180, 365];

int _monthStamp(DateTime d) => d.year * 12 + d.month - 1;

/// The 9-digit activation number for [device]: HMAC-SHA256 of the device,
/// the duration and the month it was issued in, cut to 9 digits ("482913057").
/// The administrator's page makes the same number; no server is involved.
String activationCode(List<int> key, String device, int days, DateTime issued) {
  final mac = Hmac(sha256, key)
      .convert(
        utf8.encode(
          'MTC1|${normalizeDeviceCode(device)}|$days|${_monthStamp(issued)}',
        ),
      )
      .bytes;
  var n = 0;
  for (var i = 0; i < 4; i++) {
    n = n * 256 + mac[i];
  }
  return (n % 1000000000).toString().padLeft(9, '0');
}

/// The 9 digits in [typed] (spaces and dashes ignored), or null.
String? nineDigits(String typed) {
  final d = typed.replaceAll(RegExp(r'[\s-]'), '');
  return RegExp(r'^\d{9}$').hasMatch(d) ? d : null;
}

/// How many days the number [digits] grants on [device], if it is the one
/// issued this month or last month; null when it is not a valid number.
int? daysForCode(List<int> key, String device, String digits, DateTime now) {
  if (key.isEmpty) return null;
  for (final back in [0, 1]) {
    final issued = DateTime(now.year, now.month - back, 1);
    for (final days in codeDurations) {
      if (activationCode(key, device, days, issued) == digits) return days;
    }
  }
  return null;
}

/// The activation made on the device itself after a valid number: same
/// fields as one issued by the administrator, but sealed with the HMAC key
/// instead of the signature, so it cannot be edited in the browser storage.
String sealLocalActivation(List<int> key, Map<String, Object?> payload) {
  final p = Activation.b64e(utf8.encode(jsonEncode(payload)));
  final mac = Hmac(sha256, key).convert(ascii.encode(p)).bytes;
  return '${Activation.localPrefix}.$p.${Activation.b64e(mac)}';
}

/// True when [a] is a local activation sealed with [key].
bool localSealOk(Activation a, List<int> key) =>
    a.local &&
    key.isNotEmpty &&
    constantTimeEquals(
      Hmac(sha256, key).convert(ascii.encode(a.signedPart)).bytes,
      a.signature,
    );

/// Upper case, no spaces, grouped (3-3-3 digits, or 4-4-4 for old codes) —
/// how codes are compared.
String normalizeDeviceCode(String code) {
  final c = code.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  if (c.length == 9) {
    return '${c.substring(0, 3)}-${c.substring(3, 6)}-${c.substring(6)}';
  }
  if (c.length != 12) return c;
  return '${c.substring(0, 4)}-${c.substring(4, 8)}-${c.substring(8)}';
}

bool isValidDeviceCode(String code) {
  final c = normalizeDeviceCode(code);
  return RegExp(r'^\d{3}-\d{3}-\d{3}$').hasMatch(c) ||
      RegExp('^[$_alphabet]{4}-[$_alphabet]{4}-[$_alphabet]{4}\$').hasMatch(c);
}

/// The activation carried by a link like `.../#ativar=MTA1...` sent by the
/// administrator, or null. A fragment never reaches the web server.
String? activationFromUrl(Uri url) {
  const key = 'ativar=';
  final f = url.fragment;
  final i = f.indexOf(key);
  if (i < 0) return null;
  final t = Uri.decodeComponent(f.substring(i + key.length));
  return t.startsWith('${Activation.prefix}.') ? t : null;
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
