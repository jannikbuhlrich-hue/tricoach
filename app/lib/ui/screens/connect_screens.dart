import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/feeds_remote.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import '../widgets.dart';

Future<void> openUntisConnect(BuildContext context) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const UntisConnectScreen()));
Future<void> openTpConnect(BuildContext context) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TpConnectScreen()));

Future<String?> _clipboard() async => (await Clipboard.getData(Clipboard.kTextPlain))?.text?.trim();

/// WebUntis verbinden wie in der Untis-App: Schule suchen → Benutzer + Passwort → fertig.
/// Für Schulen mit Microsoft-/IServ-Login: Link aus „Zugriff über Untis Mobile“ einfügen.
class UntisConnectScreen extends StatefulWidget {
  const UntisConnectScreen({super.key});

  @override
  State<UntisConnectScreen> createState() => _UntisConnectScreenState();
}

class _UntisConnectScreenState extends State<UntisConnectScreen> {
  final q = TextEditingController(), user = TextEditingController(), pass = TextEditingController(), link = TextEditingController();
  Timer? _debounce;
  List<SchoolHit> hits = [];
  SchoolHit? chosen;
  String? searchMsg;
  bool searching = false, busy = false, useLink = false;

  @override
  void dispose() {
    _debounce?.cancel();
    for (final c in [q, user, pass, link]) {
      c.dispose();
    }
    super.dispose();
  }

  void _search(String text) {
    _debounce?.cancel();
    if (text.trim().length < 3) {
      setState(() {
        hits = [];
        searchMsg = null;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      setState(() => searching = true);
      try {
        final r = await AppScope.read(context).feeds!.searchSchool(text);
        if (!mounted || q.text != text) return;
        setState(() {
          hits = r;
          searchMsg = r.isEmpty ? 'Keine Schule gefunden – mit Ort probieren' : null;
        });
      } catch (e) {
        if (mounted) setState(() => searchMsg = '$e');
      }
      if (mounted) setState(() => searching = false);
    });
  }

  Future<void> _connect() async {
    final app = AppScope.read(context);
    setState(() => busy = true);
    try {
      final msg = useLink
          ? await app.connectUntis(zugang: link.text)
          : await app.connectUntis(school: chosen, user: user.text.trim(), password: pass.text);
      if (!mounted) return;
      showMsg(context, msg);
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) showMsg(context, '$e');
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = TriColors.of(context);
    final canConnect = !busy && (useLink ? link.text.trim().isNotEmpty : chosen != null && user.text.trim().isNotEmpty && pass.text.isNotEmpty);
    return Scaffold(
      appBar: AppBar(title: const Text('WebUntis verbinden')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ListView(padding: const EdgeInsets.all(16), children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Mit Passwort'), icon: Icon(Icons.password_rounded)),
                ButtonSegment(value: true, label: Text('Microsoft / IServ'), icon: Icon(Icons.link_rounded)),
              ],
              selected: {useLink},
              onSelectionChanged: (s) => setState(() => useLink = s.first),
            ),
            const SizedBox(height: 16),
            if (!useLink) ...[
              if (chosen == null) ...[
                TextField(
                  controller: q,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'Schule suchen',
                    hintText: 'Name und Ort, z. B. „Gymnasium Cuxhaven“',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: searching ? const Padding(padding: EdgeInsets.all(14), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))) : null,
                  ),
                  onChanged: _search,
                ),
                if (searchMsg != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(searchMsg!, style: TextStyle(color: c.muted))),
                for (final h in hits)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.school_outlined),
                    title: Text(h.name),
                    subtitle: Text(h.address.isNotEmpty ? h.address : h.server),
                    onTap: () => setState(() => chosen = h),
                  ),
              ] else ...[
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.school_rounded, color: c.accent),
                  title: Text(chosen!.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(chosen!.address),
                  trailing: TextButton(onPressed: () => setState(() => chosen = null), child: const Text('Ändern')),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: user,
                  autofocus: true,
                  autofillHints: const [AutofillHints.username],
                  decoration: const InputDecoration(labelText: 'WebUntis-Benutzername'),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: pass,
                  obscureText: true,
                  autofillHints: const [AutofillHints.password],
                  decoration: const InputDecoration(labelText: 'Passwort'),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => canConnect ? _connect() : null,
                ),
                const SizedBox(height: 8),
                Text('Das Passwort wird nur einmal benutzt, um – wie die Untis-App – einen App-Schlüssel zu bekommen. Gespeichert wird es nicht.',
                    style: TextStyle(color: c.muted, fontSize: 12)),
              ],
            ] else ...[
              Text('Meldest du dich bei WebUntis mit Microsoft, IServ o. Ä. an? Dann so:', style: TextStyle(color: c.fg, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text('1. WebUntis im Browser öffnen und anmelden\n'
                  '2. Oben rechts auf dein Profil → Reiter „Freigaben“\n'
                  '3. Bei „Zugriff über Untis Mobile“ auf „Anzeigen“ → Link bzw. Daten kopieren\n'
                  '4. Hier einfügen → Verbinden',
                  style: TextStyle(color: c.muted, height: 1.4)),
              const SizedBox(height: 12),
              TextField(
                controller: link,
                minLines: 1,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: 'Link oder Daten aus WebUntis',
                  hintText: 'untis://setschool?url=…&school=…&user=…&key=…',
                  suffixIcon: IconButton(
                    tooltip: 'Einfügen',
                    icon: const Icon(Icons.content_paste_rounded),
                    onPressed: () async {
                      final t = await _clipboard();
                      if (t != null && t.isNotEmpty) setState(() => link.text = t);
                    },
                  ),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ],
            const SizedBox(height: 16),
            if (useLink || chosen != null)
              FilledButton(
                onPressed: canConnect ? _connect : null,
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                child: busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Verbinden'),
              ),
          ]),
        ),
      ),
    );
  }
}

/// TrainingPeaks verbinden: privaten iCal-Link einmal einfügen – der Plan kommt danach von selbst.
class TpConnectScreen extends StatefulWidget {
  const TpConnectScreen({super.key});

  @override
  State<TpConnectScreen> createState() => _TpConnectScreenState();
}

class _TpConnectScreenState extends State<TpConnectScreen> {
  final link = TextEditingController();
  bool busy = false;

  @override
  void dispose() {
    link.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    setState(() => busy = true);
    try {
      final msg = await AppScope.read(context).connectTp(link.text);
      if (!mounted) return;
      showMsg(context, msg);
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) showMsg(context, '$e');
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = TriColors.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('TrainingPeaks verbinden')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ListView(padding: const EdgeInsets.all(16), children: [
            Text('1. app.trainingpeaks.com öffnen → Einstellungen (Zahnrad) → „Calendar“\n'
                '2. Bei „iCal Calendar Feeds“ den Link kopieren\n'
                '3. Hier einfügen → Verbinden',
                style: TextStyle(color: c.muted, height: 1.4)),
            const SizedBox(height: 6),
            Text('Geplante Einheiten, Änderungen und Löschungen deines Trainers landen dann automatisch in TriCoach.', style: TextStyle(color: c.muted, fontSize: 12)),
            const SizedBox(height: 12),
            TextField(
              controller: link,
              autofocus: true,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                labelText: 'iCal-Link',
                hintText: 'webcal://…trainingpeaks.com/…',
                suffixIcon: IconButton(
                  tooltip: 'Einfügen',
                  icon: const Icon(Icons.content_paste_rounded),
                  onPressed: () async {
                    final t = await _clipboard();
                    if (t != null && t.isNotEmpty) setState(() => link.text = t);
                  },
                ),
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => link.text.trim().isNotEmpty && !busy ? _connect() : null,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: link.text.trim().isEmpty || busy ? null : _connect,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              child: busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Verbinden'),
            ),
          ]),
        ),
      ),
    );
  }
}
