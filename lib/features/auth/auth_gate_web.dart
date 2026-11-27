import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:web/web.dart' as web;

import '../mold_scan/theme/mold_scan_colors.dart';
import '../mold_scan/theme/mold_scan_theme.dart';
import '../mold_scan/widgets/mold_ui.dart';
import 'activation.dart';
import 'auth_crypto_web.dart';
import 'auth_scope.dart';
import 'auth_store_web.dart';

/// Nothing of the app is shown until a user activated for THIS device logs
/// in (see [Activation]).
class AuthGate extends StatefulWidget {
  final Widget child;

  const AuthGate({super.key, required this.child});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

enum _View { activate, login }

class _AuthGateState extends State<AuthGate> {
  final String? _device = AuthStore.deviceCode();
  String? _user; // logged in
  late _View _view = AuthStore.activations().isEmpty
      ? _View.activate
      : _View.login;

  final _token = TextEditingController();
  final _userField = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  final _newPassword = TextEditingController();
  bool _busy = false;
  bool _showPassword = false;
  String? _error;
  String? _info;

  @override
  void initState() {
    super.initState();
    final s = AuthStore.session();
    if (s != null && _activationFor(s.$1) != null) _user = s.$1;
    // Activation link from the administrator: activate with one tap.
    final link = activationFromUrl(Uri.base);
    if (link != null) {
      // Out of the address bar and history, so it isn't shared by accident.
      try {
        web.window.history.replaceState(null, '', Uri.base.removeFragment().toString());
      } catch (_) {}
      if (_user == null && _device != null) {
        _token.text = link;
        _view = _View.activate;
        WidgetsBinding.instance.addPostFrameCallback((_) => _activate());
      }
    }
  }

  @override
  void dispose() {
    _token.dispose();
    _userField.dispose();
    _password.dispose();
    _name.dispose();
    _newPassword.dispose();
    super.dispose();
  }

  /// A stored, unexpired activation of [user] for this device.
  Activation? _activationFor(String user) {
    final now = DateTime.now();
    for (final a in AuthStore.activations()) {
      if (sameUser(a.user, user) && a.device == _device && !a.isExpired(now)) {
        return a;
      }
    }
    return null;
  }

  static String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  Future<void> _activate() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final digits = nineDigits(_token.text);
      if (digits != null) {
        await _activateWithNumber(digits);
        return;
      }
      // The whole link pasted also works.
      final pasted = _token.text.trim();
      final a = Activation.parse(
        activationFromUrl(Uri.tryParse(pasted) ?? Uri()) ?? pasted,
      );
      if (a == null) {
        _error = 'Isto não é uma ativação válida. Copie o texto inteiro que o administrador enviou (começa com MTA1).';
      } else if (!await AuthCrypto.isGenuine(a)) {
        _error = 'Ativação inválida: a assinatura não confere. Peça uma nova ao administrador.';
      } else if (a.device != _device) {
        _error =
            'Esta ativação é de outro aparelho (${a.device}). O código deste aparelho é $_device.';
      } else if (a.isExpired(DateTime.now())) {
        _error =
            'Esta ativação venceu em ${_date(a.expires)}. Peça uma nova ao administrador.';
      } else if (!AuthStore.addActivation(a)) {
        _error = 'O navegador não deixou guardar a ativação (janela privada?).';
      } else {
        _token.clear();
        _userField.text = a.user;
        _info =
            'Aparelho ativado para ${a.name}, até ${_date(a.expires)}. Entre com usuário e senha.';
        _view = _View.login;
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Activation by the 9 digits the administrator gave for THIS device: the
  /// employee also picks the name to log in with and a password.
  Future<void> _activateWithNumber(String digits) async {
    final locked = AuthStore.lockedUntil();
    if (locked != null) {
      final s = locked.difference(DateTime.now()).inSeconds + 1;
      _error = 'Muitas tentativas erradas. Tente de novo em $s s.';
      return;
    }
    if (!AuthCrypto.hasCodeKey) {
      _error = 'Esta versão do app não aceita ativação por número. Use o link ou o texto de ativação.';
      return;
    }
    final name = _name.text.trim();
    final pass = _newPassword.text;
    if (name.isEmpty || pass.length < 6) {
      _error = 'Escreva seu nome e crie uma senha de pelo menos 6 caracteres.';
      return;
    }
    final now = DateTime.now();
    final days = daysForCode(AuthCrypto.codeKey, _device!, digits, now);
    if (days == null) {
      AuthStore.recordFailure();
      _error = 'Número incorreto para este aparelho. Confira os 9 números e o código do aparelho enviado ao administrador.';
      return;
    }
    final rnd = Random.secure();
    final salt = Uint8List.fromList([for (var i = 0; i < 16; i++) rnd.nextInt(256)]);
    const iterations = 210000;
    final hash = await AuthCrypto.hashPassword(pass, salt, iterations);
    final token = sealLocalActivation(AuthCrypto.codeKey, {
      'v': 1,
      'u': name,
      'n': name,
      'd': _device,
      's': Activation.b64e(salt),
      'h': Activation.b64e(hash),
      'i': iterations,
      'x': now.add(Duration(days: days)).millisecondsSinceEpoch,
      't': now.millisecondsSinceEpoch,
    });
    final a = Activation.parse(token);
    if (a == null || !AuthStore.addActivation(a)) {
      _error = 'O navegador não deixou guardar a ativação (janela privada?).';
      return;
    }
    AuthStore.startSession(a.user);
    _token.clear();
    _newPassword.clear();
    _user = a.user;
    _info = null;
  }

  Future<void> _login() async {
    final locked = AuthStore.lockedUntil();
    if (locked != null) {
      final s = locked.difference(DateTime.now()).inSeconds + 1;
      setState(
        () => _error = 'Muitas tentativas erradas. Tente de novo em $s s.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      final user = _userField.text.trim();
      Activation? a;
      for (final o in AuthStore.activations()) {
        if (sameUser(o.user, user)) a = o;
      }
      if (a == null || a.device != _device) {
        // Same answer whether the user exists or not.
        AuthStore.recordFailure();
        _error = 'Usuário ou senha incorretos, ou usuário não ativado neste aparelho.';
      } else if (a.isExpired(DateTime.now())) {
        _error =
            'O acesso de ${a.name} neste aparelho venceu em ${_date(a.expires)}. Peça uma nova ativação.';
      } else if (!await AuthCrypto.isGenuine(a) ||
          !await AuthCrypto.passwordMatches(a, _password.text)) {
        AuthStore.recordFailure();
        _error = 'Usuário ou senha incorretos, ou usuário não ativado neste aparelho.';
      } else {
        AuthStore.startSession(a.user);
        _password.clear();
        _user = a.user;
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _logout() {
    AuthStore.endSession();
    setState(() {
      _user = null;
      _view = _View.login;
      _info = null;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = _user;
    if (user != null) {
      final a = _activationFor(user);
      return AuthScope(
        userName: a?.name ?? user,
        logout: _logout,
        child: widget.child,
      );
    }
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 28, 22, 40),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const MtLogoPlate(height: 54),
                    const SizedBox(height: 26),
                    Text(
                      'Digitalizador de molde',
                      style: MoldScanType.headline(34),
                    ),
                    const SizedBox(height: 22),
                    if (_device == null)
                      const _Message(
                        color: MoldScanColors.danger,
                        text:
                            'Este navegador não permite guardar dados (janela privada?). Abra o app '
                            'numa janela normal ou instalado na tela inicial.',
                      )
                    else if (_view == _View.activate)
                      ..._activateView()
                    else
                      ..._loginView(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _deviceCodeBox() => Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
    decoration: BoxDecoration(
      color: MoldScanColors.surface,
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: MoldScanColors.border),
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Código deste aparelho',
                style: TextStyle(
                  color: MoldScanColors.textSecondary,
                  fontSize: 13.5,
                ),
              ),
              const SizedBox(height: 2),
              SelectableText(_device!, style: MoldScanType.readout(28)),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Copiar código',
          icon: const Icon(Icons.copy, color: MoldScanColors.accentAlt),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: _device));
            if (mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('Código copiado.')));
            }
          },
        ),
      ],
    ),
  );

  List<Widget> _activateView() => [
    Text('Ativar este aparelho', style: MoldScanType.headline(24)),
    const SizedBox(height: 8),
    const Text(
      'O acesso fica preso a um único aparelho. Envie o código abaixo ao administrador; ele vai '
      'responder com 9 números ou com um link de ativação. Digite os números aqui (ou toque no link).',
      style: TextStyle(
        color: MoldScanColors.textSecondary,
        fontSize: 15,
        height: 1.4,
      ),
    ),
    const SizedBox(height: 16),
    _deviceCodeBox(),
    const SizedBox(height: 16),
    TextField(
      controller: _token,
      minLines: 1,
      maxLines: 5,
      autocorrect: false,
      enableSuggestions: false,
      onChanged: (_) => setState(() {}),
      decoration: const InputDecoration(
        labelText: 'Ativação (9 números ou texto)',
        hintText: '000 000 000',
      ),
    ),
    if (nineDigits(_token.text) != null) ...[
      const SizedBox(height: 12),
      TextField(
        controller: _name,
        autocorrect: false,
        autofillHints: const [AutofillHints.username],
        textInputAction: TextInputAction.next,
        decoration: const InputDecoration(
          labelText: 'Seu nome (para entrar)',
          prefixIcon: Icon(Icons.person_outline),
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _newPassword,
        obscureText: true,
        autocorrect: false,
        enableSuggestions: false,
        autofillHints: const [AutofillHints.newPassword],
        onSubmitted: (_) => _busy ? null : _activate(),
        decoration: const InputDecoration(
          labelText: 'Crie uma senha (mín. 6)',
          prefixIcon: Icon(Icons.lock_outline),
        ),
      ),
    ],
    const SizedBox(height: 14),
    if (_error != null) ...[
      _Message(color: MoldScanColors.danger, text: _error!),
      const SizedBox(height: 12),
    ],
    SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: _busy ? null : _activate,
        icon: const Icon(Icons.verified_user_outlined, size: 20),
        label: Text(_busy ? 'Conferindo…' : 'Ativar aparelho'),
      ),
    ),
    if (AuthStore.activations().isNotEmpty) ...[
      const SizedBox(height: 8),
      TextButton(
        onPressed: () => setState(() {
          _view = _View.login;
          _error = null;
        }),
        child: const Text('Voltar para o login'),
      ),
    ],
  ];

  List<Widget> _loginView() => [
    Text('Entrar', style: MoldScanType.headline(24)),
    const SizedBox(height: 14),
    if (_info != null) ...[
      _Message(color: MoldScanColors.accentAlt, text: _info!),
      const SizedBox(height: 14),
    ],
    TextField(
      controller: _userField,
      autocorrect: false,
      enableSuggestions: false,
      autofillHints: const [AutofillHints.username],
      textInputAction: TextInputAction.next,
      decoration: const InputDecoration(
        labelText: 'Usuário',
        prefixIcon: Icon(Icons.person_outline),
      ),
    ),
    const SizedBox(height: 12),
    TextField(
      controller: _password,
      obscureText: !_showPassword,
      autocorrect: false,
      enableSuggestions: false,
      autofillHints: const [AutofillHints.password],
      onSubmitted: (_) => _busy ? null : _login(),
      decoration: InputDecoration(
        labelText: 'Senha',
        prefixIcon: const Icon(Icons.lock_outline),
        suffixIcon: IconButton(
          tooltip: _showPassword ? 'Esconder senha' : 'Mostrar senha',
          icon: Icon(
            _showPassword
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
          ),
          onPressed: () => setState(() => _showPassword = !_showPassword),
        ),
      ),
    ),
    const SizedBox(height: 14),
    if (_error != null) ...[
      _Message(color: MoldScanColors.danger, text: _error!),
      const SizedBox(height: 12),
    ],
    SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: _busy ? null : _login,
        icon: const Icon(Icons.login, size: 20),
        label: Text(_busy ? 'Entrando…' : 'Entrar'),
      ),
    ),
    const SizedBox(height: 26),
    Row(
      children: [
        Expanded(
          child: Text(
            'Aparelho $_device',
            style: const TextStyle(
              color: MoldScanColors.textSecondary,
              fontSize: 13.5,
            ),
          ),
        ),
        TextButton(
          onPressed: () => setState(() {
            _view = _View.activate;
            _error = null;
            _info = null;
          }),
          child: const Text('Adicionar ativação'),
        ),
      ],
    ),
  ];
}

class _Message extends StatelessWidget {
  final Color color;
  final String text;

  const _Message({required this.color, required this.text});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: color.withValues(alpha: 0.55)),
    ),
    child: Text(
      text,
      style: TextStyle(color: color, fontSize: 14.5, height: 1.4),
    ),
  );
}
