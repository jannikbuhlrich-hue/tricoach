import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../config.dart';
import '../../core/format.dart';
import '../../core/ics.dart';
import '../../core/models.dart';
import '../../data/device_calendar_sync.dart';
import '../../data/health_import.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import '../widgets.dart';
import 'coach_screen.dart';
import 'login_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context), c = TriColors.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Einstellungen', style: TextStyle(fontWeight: FontWeight.w700))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
        children: [
          _account(context, app, c),
          const SizedBox(height: 12),
          _watch(context, app, c),
          const SizedBox(height: 12),
          _calendar(context, app, c),
          const SizedBox(height: 12),
          TriCard(
            title: 'Design',
            icon: Icons.palette_rounded,
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              for (final d in TriDesign.values)
                ChoiceChip(
                  avatar: CircleAvatar(backgroundColor: TriColors.forDesign(d).accent, radius: 7),
                  label: Text(d.label),
                  selected: app.design == d,
                  onSelected: (_) => app.setDesign(d),
                ),
            ]),
          ),
          const SizedBox(height: 12),
          _ProfileCard(app.profile),
          const SizedBox(height: 12),
          TriCard(
            title: 'Coach',
            icon: Icons.groups_rounded,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Dein Coach sieht deine Einheiten und plant dir Trainings direkt in den Kalender – ohne TrainingPeaks-Abo.', style: TextStyle(color: c.muted)),
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                onPressed: app.signedIn ? () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CoachScreen())) : () => openLogin(context),
                icon: const Icon(Icons.link_rounded),
                label: Text(app.signedIn ? 'Coach verbinden / Athleten verwalten' : 'Dafür anmelden'),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          _data(context, app, c),
          const SizedBox(height: 12),
          Center(child: Text('TriCoach ${AppConfig.appVersion}', style: TextStyle(color: c.faint, fontSize: 12))),
        ],
      ),
    );
  }

  Widget _account(BuildContext context, AppState app, TriColors c) {
    if (app.localOnly) {
      return TriCard(
        title: 'Account',
        icon: Icons.person_rounded,
        child: Text('Diese Version läuft ohne Server: Alles bleibt auf diesem Gerät. Sobald der Server eingerichtet ist, meldest du dich hier an und alles erscheint auf allen Geräten.',
            style: TextStyle(color: c.muted)),
      );
    }
    final u = app.user;
    return TriCard(
      title: 'Account',
      icon: Icons.person_rounded,
      trailing: const SyncChip(),
      child: u == null
          ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Melde dich an, damit deine Einheiten auf iPhone, iPad, Android und PC gleich sind.', style: TextStyle(color: c.muted)),
              const SizedBox(height: 8),
              FilledButton(onPressed: () => openLogin(context), child: const Text('Anmelden oder registrieren')),
            ])
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(u.email ?? 'Angemeldet', style: const TextStyle(fontWeight: FontWeight.w600)),
              if (app.syncStatus.lastOk != null) Text('Zuletzt abgeglichen ${timeTxt(app.syncStatus.lastOk!)}', style: TextStyle(color: c.muted, fontSize: 12)),
              if (app.syncStatus.error != null) Text(app.syncStatus.error!, style: TextStyle(color: c.warn, fontSize: 12)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, children: [
                OutlinedButton.icon(onPressed: () => app.repo.sync.syncNow(), icon: const Icon(Icons.sync_rounded), label: const Text('Jetzt abgleichen')),
                TextButton(
                  onPressed: () async {
                    final ok = await _confirm(context, 'Abmelden?', 'Deine Daten bleiben im Account. Auf diesem Gerät werden sie gelöscht, bis du dich wieder anmeldest.');
                    if (ok) await app.signOut();
                  },
                  child: const Text('Abmelden'),
                ),
              ]),
            ]),
    );
  }

  Widget _watch(BuildContext context, AppState app, TriColors c) {
    return TriCard(
      title: 'Uhr',
      icon: Icons.watch_rounded,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (HealthImport.supported)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(Theme.of(context).platform == TargetPlatform.iOS ? 'Apple Health' : 'Health Connect'),
            subtitle: const Text('Einheiten mit Puls, Distanz und Dauer automatisch übernehmen – Garmin, Apple Watch, Coros, Polar …'),
            value: app.healthOn,
            onChanged: (v) async {
              if (v) {
                final ok = await app.enableHealth();
                if (!ok && context.mounted) showMsg(context, 'Kein Zugriff erteilt – in den Systemeinstellungen änderbar.');
              } else {
                await app.disableHealth();
              }
            },
          )
        else
          Text('Apple Health / Health Connect gibt es nur in der App auf iPhone, iPad und Android. Hier am PC/Browser: intervals.icu.', style: TextStyle(color: c.muted)),
        const SizedBox(height: 8),
        _IcuField(initial: app.icuKey),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: Text(app.lastWatchImport == null ? 'Noch nicht abgerufen' : 'Zuletzt geholt: ${shortDate(app.lastWatchImport!)} ${timeTxt(app.lastWatchImport!)}',
                style: TextStyle(color: c.muted, fontSize: 12)),
          ),
          TextButton.icon(
            onPressed: (app.healthOn || app.icuKey.isNotEmpty)
                ? () async {
                    final n = await app.importWatch();
                    if (context.mounted && n == 0) showMsg(context, 'Alles aktuell');
                  }
                : null,
            icon: const Icon(Icons.download_rounded),
            label: const Text('Jetzt holen'),
          ),
        ]),
      ]),
    );
  }

  Widget _calendar(BuildContext context, AppState app, TriColors c) {
    final token = app.calendarToken;
    return TriCard(
      title: 'Kalender',
      icon: Icons.event_available_rounded,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (DeviceCalendarSync.supported)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(Theme.of(context).platform == TargetPlatform.iOS ? 'In Apple Kalender eintragen' : 'In den Kalender des Handys eintragen'),
            subtitle: const Text('Eigener Kalender „TriCoach“: geplante und erledigte Einheiten, Änderungen werden automatisch nachgezogen.'),
            value: app.calendarOn,
            onChanged: (v) async {
              if (v) {
                final ok = await app.enableCalendar();
                if (!ok && context.mounted) showMsg(context, 'Kein Kalender-Zugriff – in den Systemeinstellungen änderbar.');
              } else {
                await app.disableCalendar();
              }
            },
          ),
        if (token != null) ...[
          const SizedBox(height: 4),
          Text('Abo-Link für PC, Outlook und Google Kalender', style: TextStyle(color: c.muted, fontSize: 13)),
          const SizedBox(height: 4),
          Wrap(spacing: 8, runSpacing: 4, children: [
            OutlinedButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: AppConfig.calendarFeedUrl(token)));
                if (context.mounted) showMsg(context, 'Link kopiert – in Google Kalender: „Andere Kalender → Per URL“ einfügen.');
              },
              icon: const Icon(Icons.copy_rounded),
              label: const Text('Link kopieren'),
            ),
            TextButton(
              onPressed: () async {
                if (await _confirm(context, 'Neuen Link erzeugen?', 'Der alte Link funktioniert danach nicht mehr – z. B. wenn du ihn versehentlich geteilt hast.')) {
                  await app.rotateCalendarLink();
                }
              },
              child: const Text('Neuen Link erzeugen'),
            ),
          ]),
        ] else if (!app.localOnly)
          Text('Nach dem Anmelden bekommst du hier einen Abo-Link für PC und Google Kalender.', style: TextStyle(color: c.muted, fontSize: 13)),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () async {
              final ics = buildIcs(activities: app.activities, planned: app.planned);
              await FilePicker.platform.saveFile(dialogTitle: 'Kalender speichern', fileName: 'TriCoach.ics', bytes: Uint8List.fromList(utf8.encode(ics)));
            },
            icon: const Icon(Icons.file_download_rounded),
            label: const Text('Als .ics-Datei speichern'),
          ),
        ),
      ]),
    );
  }

  Widget _data(BuildContext context, AppState app, TriColors c) {
    return TriCard(
      title: 'Daten',
      icon: Icons.storage_rounded,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Sicherung aus der bisherigen TriCoach-Web-App übernehmen (Einstellungen → „Daten sichern“). Doppelte Einträge entstehen nicht.', style: TextStyle(color: c.muted)),
        const SizedBox(height: 8),
        FilledButton.tonalIcon(
          icon: const Icon(Icons.upload_file_rounded),
          label: const Text('Sicherung laden'),
          onPressed: () async {
            final res = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: const ['json'], withData: true);
            final bytes = res?.files.single.bytes;
            if (bytes == null) return;
            try {
              final r = await app.repo.importWebBackup(utf8.decode(bytes));
              await app.saveProfile(app.profile);
              if (context.mounted) showMsg(context, 'Übernommen: ${r.activities} Einheiten, ${r.planned} Kalendereinträge${r.skipped > 0 ? ' (${r.skipped} übersprungen)' : ''}');
            } catch (e) {
              if (context.mounted) showMsg(context, '$e');
            }
          },
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () async {
            if (await _confirm(context, 'Alles auf diesem Gerät löschen?', app.signedIn ? 'Im Account bleibt alles erhalten.' : 'Ohne Account sind die Daten danach weg.')) {
              await app.repo.wipe();
            }
          },
          child: Text('Alle Daten auf diesem Gerät löschen', style: TextStyle(color: c.bad)),
        ),
      ]),
    );
  }
}

Future<bool> _confirm(BuildContext context, String title, String text) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(text),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('OK')),
        ],
      ),
    ) ==
    true;

class _IcuField extends StatefulWidget {
  const _IcuField({required this.initial});
  final String initial;

  @override
  State<_IcuField> createState() => _IcuFieldState();
}

class _IcuFieldState extends State<_IcuField> {
  late final ctl = TextEditingController(text: widget.initial);
  bool busy = false;

  @override
  void dispose() {
    ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(
        child: TextField(
          controller: ctl,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'intervals.icu API-Key', hintText: 'intervals.icu → Settings → Developer'),
        ),
      ),
      const SizedBox(width: 8),
      FilledButton(
        onPressed: busy
            ? null
            : () async {
                setState(() => busy = true);
                try {
                  final msg = await AppScope.read(context).setIcuKey(ctl.text);
                  if (context.mounted) showMsg(context, msg);
                } catch (e) {
                  if (context.mounted) showMsg(context, '$e');
                }
                if (mounted) setState(() => busy = false);
              },
        child: const Text('Verbinden'),
      ),
    ]);
  }
}

class _ProfileCard extends StatefulWidget {
  const _ProfileCard(this.p);
  final AthleteProfile p;

  @override
  State<_ProfileCard> createState() => _ProfileCardState();
}

class _ProfileCardState extends State<_ProfileCard> {
  late final weight = TextEditingController(text: de(widget.p.weightKg, 1));
  late final ftp = TextEditingController(text: de(widget.p.ftp));
  late final lthr = TextEditingController(text: de(widget.p.lthr));
  late final rhr = TextEditingController(text: de(widget.p.rhr));
  late final pace = TextEditingController(text: paceTxt(widget.p.thresholdPaceS));
  late final css = TextEditingController(text: paceTxt(widget.p.cssS));
  late final week = TextEditingController(text: de(widget.p.weeklyHoursGoal, 1));
  late final yearKm = TextEditingController(text: widget.p.yearKmGoal > 0 ? widget.p.yearKmGoal.round().toString() : '');

  @override
  void dispose() {
    for (final c in [weight, ftp, lthr, rhr, pace, css, week, yearKm]) {
      c.dispose();
    }
    super.dispose();
  }

  /// „68,5“ oder „68.5“ – beides geht
  double? _n(TextEditingController c) {
    final t = c.text.trim();
    return double.tryParse(t.contains(',') ? t.replaceAll('.', '').replaceAll(',', '.') : t);
  }
  double? _mmss(TextEditingController c) {
    final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(c.text.trim());
    return m == null ? null : int.parse(m[1]!) * 60.0 + int.parse(m[2]!);
  }

  Widget _f(TextEditingController c, String label, {String? hint}) => SizedBox(
        width: 150,
        child: TextField(controller: c, keyboardType: TextInputType.text, decoration: InputDecoration(labelText: label, hintText: hint)),
      );

  @override
  Widget build(BuildContext context) {
    final c = TriColors.of(context);
    return TriCard(
      title: 'Leistungswerte & Ziele',
      icon: Icons.tune_rounded,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Daraus berechnet TriCoach Belastung (TSS), Form und Zonen.', style: TextStyle(color: c.muted)),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 10, children: [
          _f(weight, 'Gewicht (kg)'),
          _f(ftp, 'FTP Rad (W)'),
          _f(lthr, 'Schwellenpuls'),
          _f(rhr, 'Ruhepuls'),
          _f(pace, 'Schwelle Lauf (/km)', hint: '4:10'),
          _f(css, 'CSS Schwimmen (/100m)', hint: '1:35'),
          _f(week, 'Wochenziel (h)'),
          _f(yearKm, 'Jahresziel (km)', hint: 'optional'),
        ]),
        const SizedBox(height: 10),
        FilledButton(
          onPressed: () async {
            final app = AppScope.read(context), p = app.profile;
            await app.saveProfile(p.copyWith(
              weightKg: _n(weight),
              ftp: _n(ftp),
              lthr: _n(lthr),
              rhr: _n(rhr),
              thresholdPaceS: _mmss(pace),
              cssS: _mmss(css),
              weeklyHoursGoal: _n(week),
              yearKmGoal: _n(yearKm) ?? 0,
            ));
            if (context.mounted) showMsg(context, 'Gespeichert – TSS und Form neu berechnet');
          },
          child: const Text('Speichern'),
        ),
      ]),
    );
  }
}
