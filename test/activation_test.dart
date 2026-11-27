import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mt_vidros_app/features/auth/activation.dart';

String _token(Map<String, Object?> payload, {int sigLen = 64}) =>
    'MTA1.${Activation.b64e(utf8.encode(jsonEncode(payload)))}.${Activation.b64e(List.filled(sigLen, 7))}';

Map<String, Object?> _payload({String device = 'K7QD-9XMA-PW3R', int? expires}) => {
  'v': 1,
  'u': 'joao',
  'n': 'João Silva',
  'd': device,
  's': Activation.b64e(List.filled(16, 1)),
  'h': Activation.b64e(List.filled(32, 2)),
  'i': 210000,
  'x': expires ?? DateTime(2027, 2, 1).millisecondsSinceEpoch,
  't': DateTime(2026, 11, 25).millisecondsSinceEpoch,
};

void main() {
  test('lê a ativação colada, mesmo com espaços e quebras de linha', () {
    final t = _token(_payload());
    final a = Activation.parse('  ${t.substring(0, 40)}\n${t.substring(40)} ')!;
    expect(a.user, 'joao');
    expect(a.name, 'João Silva');
    expect(a.device, 'K7QD-9XMA-PW3R');
    expect(a.iterations, 210000);
    expect(a.signature.length, 64);
    expect(a.isExpired(DateTime(2027, 1, 31)), isFalse);
    expect(a.isExpired(DateTime(2027, 2, 1)), isTrue);
  });

  test('recusa texto que não é ativação', () {
    for (final t in [
      '',
      'qualquer coisa',
      'MTA1.abc',
      'XXXX.${_token(_payload()).split('.')[1]}.${_token(_payload()).split('.')[2]}',
      _token(_payload(), sigLen: 10),
      _token({..._payload(), 'v': 2}),
      _token({..._payload(), 'u': '  '}),
      _token({..._payload(), 'i': 5}),
    ]) {
      expect(Activation.parse(t), isNull, reason: t);
    }
  });

  test('código do aparelho: 12 letras e números sem ambíguos, agrupados de 4', () {
    final r = Random(1);
    for (var i = 0; i < 200; i++) {
      final c = newDeviceCode(r);
      expect(isValidDeviceCode(c), isTrue, reason: c);
      expect(c, matches(RegExp(r'^[A-Z2-9]{4}-[A-Z2-9]{4}-[A-Z2-9]{4}$')));
      expect(c, isNot(matches(RegExp('[01OIL]'))));
    }
    expect(normalizeDeviceCode('k7qd 9xma pw3r'), 'K7QD-9XMA-PW3R');
    expect(isValidDeviceCode('K7QD-9XMA-PW3'), isFalse);
    expect(isValidDeviceCode('K0QD-9XMA-PW3R'), isFalse);
  });

  test('usuário ignora maiúsculas e espaços; hashes comparados por inteiro', () {
    expect(sameUser(' Joao ', 'joao'), isTrue);
    expect(sameUser('joao', 'joana'), isFalse);
    expect(constantTimeEquals([1, 2, 3], [1, 2, 3]), isTrue);
    expect(constantTimeEquals([1, 2, 3], [1, 2, 4]), isFalse);
    expect(constantTimeEquals([1, 2], [1, 2, 3]), isFalse);
  });
}
