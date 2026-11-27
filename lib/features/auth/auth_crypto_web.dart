import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'activation.dart';

/// Signature and password checks with the browser's own cryptography
/// (WebCrypto): ECDSA P-256 / SHA-256 for activations, PBKDF2-SHA-256 for
/// passwords.
class AuthCrypto {
  /// Public half of the administrator's key. The private half never leaves
  /// the administrator's computer (admin/gerar_ativacao.html); with it alone
  /// can activations be issued.
  static const _publicKeyX = 'RuMHovmun-cT9Jgep7uMdgEUm_4jCqtsAhKQegatAG8';
  static const _publicKeyY = '9fzHFlhbqCaHms8q7iC6t_DJRS9LsXH8qrLH9t-Re3U';

  static web.SubtleCrypto get _subtle => web.window.crypto.subtle;

  /// True when [a] was signed by the administrator.
  static Future<bool> isGenuine(Activation a) async {
    try {
      final key = await _subtle
          .importKey(
            'jwk',
            web.JsonWebKey(
              kty: 'EC',
              crv: 'P-256',
              x: _publicKeyX,
              y: _publicKeyY,
              ext: true,
            ),
            _obj({'name': 'ECDSA'.toJS, 'namedCurve': 'P-256'.toJS}),
            false,
            <JSString>['verify'.toJS].toJS,
          )
          .toDart;
      final ok = await _subtle
          .verify(
            _obj({'name': 'ECDSA'.toJS, 'hash': 'SHA-256'.toJS}),
            key,
            a.signature.toJS,
            Uint8List.fromList(ascii.encode(a.signedPart)).toJS,
          )
          .toDart;
      return (ok as JSBoolean?)?.toDart == true;
    } catch (_) {
      return false;
    }
  }

  /// True when [password] is the one this activation was issued with.
  static Future<bool> passwordMatches(Activation a, String password) async {
    try {
      final base = await _subtle
          .importKey(
            'raw',
            Uint8List.fromList(utf8.encode(password)).toJS,
            'PBKDF2'.toJS,
            false,
            <JSString>['deriveBits'.toJS].toJS,
          )
          .toDart;
      final bits = await _subtle
          .deriveBits(
            _obj({
              'name': 'PBKDF2'.toJS,
              'hash': 'SHA-256'.toJS,
              'salt': a.salt.toJS,
              'iterations': a.iterations.toJS,
            }),
            base,
            256,
          )
          .toDart;
      return constantTimeEquals(bits.toDart.asUint8List(), a.hash);
    } catch (_) {
      return false;
    }
  }

  /// A plain JS object with these properties (WebCrypto algorithm
  /// parameters).
  static JSObject _obj(Map<String, JSAny> props) {
    final o = JSObject();
    props.forEach((k, v) => o.setProperty(k.toJS, v));
    return o;
  }
}
