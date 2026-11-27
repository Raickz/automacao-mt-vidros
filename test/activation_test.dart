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

  test('código do aparelho: 12 letras e números sem ambíguos; o de 9 dígitos antigo segue válido', () {
    final r = Random(1);
    for (var i = 0; i < 200; i++) {
      final c = newDeviceCode(r);
      expect(isValidDeviceCode(c), isTrue, reason: c);
      expect(c, matches(RegExp(r'^[A-Z2-9]{4}-[A-Z2-9]{4}-[A-Z2-9]{4}$')));
      expect(c, isNot(matches(RegExp('[01OIL]'))));
    }
    // 9-digit device codes made by the previous version still work.
    expect(normalizeDeviceCode('482 913057'), '482-913-057');
    expect(isValidDeviceCode('482-913-057'), isTrue);
    expect(isValidDeviceCode('482-913-05'), isFalse);
    expect(normalizeDeviceCode('k7qd 9xma pw3r'), 'K7QD-9XMA-PW3R');
    expect(isValidDeviceCode('K7QD-9XMA-PW3R'), isTrue);
    expect(isValidDeviceCode('K7QD-9XMA-PW3'), isFalse);
    expect(isValidDeviceCode('K0QD-9XMA-PW3R'), isFalse);
  });

  test('link de ativação: lê o token do fragmento #ativar=', () {
    final t = _token(_payload());
    expect(
      activationFromUrl(
        Uri.parse('https://raickz.github.io/automacao-mt-vidros/#ativar=$t'),
      ),
      t,
    );
    expect(activationFromUrl(Uri.parse('https://x.io/app/')), isNull);
    expect(activationFromUrl(Uri.parse('https://x.io/#ativar=lixo')), isNull);
    expect(Activation.parse(activationFromUrl(
      Uri.parse('https://x.io/#ativar=$t'),
    )!), isNotNull);
  });

  group('ativação por 9 números', () {
    final key = utf8.encode('chave-de-teste');
    const device = 'K7QD-9XMA-PW3R';
    final now = DateTime(2026, 11, 27);

    test('número tem 9 dígitos e depende do aparelho, da validade e do mês', () {
      final c = activationCode(key, device, 90, now);
      expect(c, matches(RegExp(r'^\d{9}$')));
      expect(activationCode(key, device, 90, DateTime(2026, 11, 3)), c);
      expect(activationCode(key, 'AAAA-BBBB-CCCC', 90, now), isNot(c));
      expect(activationCode(key, device, 30, now), isNot(c));
      expect(activationCode(key, device, 90, DateTime(2026, 12, 1)), isNot(c));
      expect(activationCode(utf8.encode('outra'), device, 90, now), isNot(c));
    });

    test('app confere o número: vale no mês e no mês seguinte, não depois', () {
      for (final d in codeDurations) {
        final c = activationCode(key, device, d, now);
        expect(daysForCode(key, device, c, now), d);
        expect(daysForCode(key, device, c, DateTime(2026, 12, 20)), d);
        expect(daysForCode(key, device, c, DateTime(2027, 1, 2)), isNull);
        expect(daysForCode(key, 'AAAA-BBBB-CCCC', c, now), isNull);
      }
      expect(daysForCode(key, device, '000000000', now), isNull);
      expect(daysForCode(const [], device, '123456789', now), isNull);
    });

    test('lê 9 números com espaços e traços', () {
      expect(nineDigits('482 913 057'), '482913057');
      expect(nineDigits('482-913-057'), '482913057');
      expect(nineDigits('48291305'), isNull);
      expect(nineDigits('4829130571'), isNull);
      expect(nineDigits('MTA1.abc'), isNull);
    });

    test('ativação local: lacrada com a chave, não aceita edição', () {
      final p = _payload(device: device);
      final t = sealLocalActivation(key, p);
      final a = Activation.parse(t)!;
      expect(a.local, isTrue);
      expect(a.user, 'joao');
      expect(localSealOk(a, key), isTrue);
      expect(localSealOk(a, utf8.encode('outra')), isFalse);
      // Changing the expiry invalidates the seal.
      final edited = Activation.parse(
        sealLocalActivation(key, {...p, 'x': 1}).replaceFirst(
          RegExp(r'\.[^.]+$'),
          '.${t.split('.')[2]}',
        ),
      )!;
      expect(localSealOk(edited, key), isFalse);
      // A signed (non-local) activation is never "sealed".
      expect(localSealOk(Activation.parse(_token(_payload()))!, key), isFalse);
    });
  });

  test('usuário ignora maiúsculas e espaços; hashes comparados por inteiro', () {
    expect(sameUser(' Joao ', 'joao'), isTrue);
    expect(sameUser('joao', 'joana'), isFalse);
    expect(constantTimeEquals([1, 2, 3], [1, 2, 3]), isTrue);
    expect(constantTimeEquals([1, 2, 3], [1, 2, 4]), isFalse);
    expect(constantTimeEquals([1, 2], [1, 2, 3]), isFalse);
  });
}
