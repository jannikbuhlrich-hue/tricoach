import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config.dart';
import '../theme.dart';
import '../widgets.dart';

Future<void> openLogin(BuildContext context) => Navigator.of(context).push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => const LoginScreen()));

/// Anmelden / Registrieren: E-Mail + Passwort, Login-Link per Mail, Apple, Google.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final email = TextEditingController();
  final pass = TextEditingController();
  bool register = false;
  bool busy = false;

  GoTrueClient get auth => Supabase.instance.client.auth;
  String? get _redirect => kIsWeb ? null : AppConfig.authRedirect;

  @override
  void dispose() {
    email.dispose();
    pass.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() fn) async {
    setState(() => busy = true);
    try {
      await fn();
    } on AuthException catch (e) {
      if (mounted) showMsg(context, _german(e.message));
    } catch (e) {
      if (mounted) showMsg(context, 'Das hat nicht geklappt: $e');
    }
    if (mounted) setState(() => busy = false);
  }

  static String _german(String m) {
    final s = m.toLowerCase();
    if (s.contains('invalid login')) return 'E-Mail oder Passwort stimmt nicht.';
    if (s.contains('already registered')) return 'Diese E-Mail ist schon registriert – bitte anmelden.';
    if (s.contains('password should be')) return 'Das Passwort braucht mindestens 8 Zeichen.';
    if (s.contains('email not confirmed')) return 'Bitte zuerst den Link in der Bestätigungs-Mail öffnen.';
    if (s.contains('rate limit')) return 'Zu viele Versuche – bitte kurz warten.';
    return m;
  }

  Future<void> _email() => _run(() async {
        final mail = email.text.trim(), pw = pass.text;
        if (!mail.contains('@')) throw const AuthException('Bitte eine gültige E-Mail eingeben.');
        if (register) {
          if (pw.length < 8) throw const AuthException('Das Passwort braucht mindestens 8 Zeichen.');
          final r = await auth.signUp(email: mail, password: pw, emailRedirectTo: _redirect);
          if (r.session == null && mounted) {
            showMsg(context, 'Fast geschafft: Bitte bestätige deine E-Mail über den Link, den wir dir geschickt haben.');
            return;
          }
        } else {
          await auth.signInWithPassword(email: mail, password: pw);
        }
        if (mounted) Navigator.of(context).pop();
      });

  Future<void> _oauth(OAuthProvider p) => _run(() async {
        await auth.signInWithOAuth(p, redirectTo: _redirect);
      });

  @override
  Widget build(BuildContext context) {
    final c = TriColors.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(register ? 'Registrieren' : 'Anmelden')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: ListView(padding: const EdgeInsets.all(20), shrinkWrap: true, children: [
            Text('Ein Account – alle Geräte. Deine Einheiten werden verschlüsselt übertragen und liegen auf Servern in der EU.', style: TextStyle(color: c.muted)),
            const SizedBox(height: 20),
            if (AppConfig.appleLogin) ...[
            FilledButton.icon(
              onPressed: busy ? null : () => _oauth(OAuthProvider.apple),
              icon: const Icon(Icons.apple_rounded),
              label: const Text('Mit Apple anmelden'),
              style: FilledButton.styleFrom(backgroundColor: Colors.black, foregroundColor: Colors.white, minimumSize: const Size.fromHeight(48)),
            ),
            const SizedBox(height: 10),
            ],
            if (AppConfig.googleLogin) ...[
            OutlinedButton.icon(
              onPressed: busy ? null : () => _oauth(OAuthProvider.google),
              icon: const Icon(Icons.g_mobiledata_rounded, size: 28),
              label: const Text('Mit Google anmelden'),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            ),
            const SizedBox(height: 10),
            ],
            if (AppConfig.appleLogin || AppConfig.googleLogin) ...[
              const SizedBox(height: 10),
              Row(children: [Expanded(child: Divider(color: c.line)), Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: Text('oder mit E-Mail', style: TextStyle(color: c.muted))), Expanded(child: Divider(color: c.line))]),
              const SizedBox(height: 16),
            ],
            TextField(controller: email, keyboardType: TextInputType.emailAddress, autofillHints: const [AutofillHints.email], decoration: const InputDecoration(labelText: 'E-Mail')),
            const SizedBox(height: 10),
            TextField(
              controller: pass,
              obscureText: true,
              autofillHints: [register ? AutofillHints.newPassword : AutofillHints.password],
              decoration: InputDecoration(labelText: 'Passwort', helperText: register ? 'Mindestens 8 Zeichen' : null),
              onSubmitted: (_) => _email(),
            ),
            const SizedBox(height: 14),
            FilledButton(onPressed: busy ? null : _email, style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)), child: Text(register ? 'Account anlegen' : 'Anmelden')),
            const SizedBox(height: 6),
            Center(
              child: TextButton(
                onPressed: () => setState(() => register = !register),
                child: Text(register ? 'Schon registriert? Anmelden' : 'Neu hier? Kostenlosen Account anlegen'),
              ),
            ),
            if (busy) const Padding(padding: EdgeInsets.only(top: 12), child: Center(child: CircularProgressIndicator())),
          ]),
        ),
      ),
    );
  }
}
