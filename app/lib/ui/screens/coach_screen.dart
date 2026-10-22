import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/sport.dart';
import '../../data/repository.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import '../widgets.dart';

/// Coach ↔ Athlet: Einladung per Code, Trainer-Ansicht mit Ampel, Einheiten für Athleten planen.
class CoachScreen extends StatefulWidget {
  const CoachScreen({super.key});

  @override
  State<CoachScreen> createState() => _CoachScreenState();
}

class _CoachScreenState extends State<CoachScreen> {
  final code = TextEditingController();
  String? myCode;
  List<Map<String, dynamic>>? athletes;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    code.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final r = AppScope.read(context).remote;
    if (r == null) return;
    try {
      final a = await r.myAthletes();
      if (mounted) setState(() => athletes = a);
    } catch (e) {
      if (mounted) setState(() => athletes = []);
    }
  }

  Future<void> _run(Future<void> Function() fn) async {
    setState(() => busy = true);
    try {
      await fn();
    } catch (e) {
      if (mounted) showMsg(context, e.toString().replaceFirst(RegExp(r'^.*?message: '), '').split(',').first);
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context), c = TriColors.of(context), r = app.remote;
    return Scaffold(
      appBar: AppBar(title: const Text('Coach')),
      body: r == null
          ? const Center(child: Text('Bitte zuerst anmelden.'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TriCard(
                  title: 'Ich bin Athlet',
                  icon: Icons.directions_run_rounded,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text('Code von deinem Coach eingeben. Danach sieht er deine Einheiten und kann dir Trainings planen.', style: TextStyle(color: c.muted)),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(child: TextField(controller: code, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Einladungscode', hintText: 'z. B. 7F3K9Q2A'))),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: busy
                            ? null
                            : () => _run(() async {
                                  await r.acceptCoachInvite(code.text);
                                  if (mounted) showMsg(context, 'Verbunden – dein Coach sieht jetzt deine Einheiten.');
                                  code.clear();
                                }),
                        child: const Text('Verbinden'),
                      ),
                    ]),
                  ]),
                ),
                const SizedBox(height: 12),
                TriCard(
                  title: 'Ich bin Coach',
                  icon: Icons.sports_rounded,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text('Erzeuge einen Code und schick ihn deinem Athleten. Jeder Code gilt 14 Tage und einmal.', style: TextStyle(color: c.muted)),
                    const SizedBox(height: 8),
                    if (myCode != null)
                      Row(children: [
                        SelectableText(myCode!, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: 3)),
                        IconButton(
                          tooltip: 'Kopieren',
                          icon: const Icon(Icons.copy_rounded),
                          onPressed: () => Clipboard.setData(ClipboardData(text: 'Verbinde dich mit mir in TriCoach: Einstellungen › Coach › Code $myCode')),
                        ),
                      ]),
                    FilledButton.tonal(
                      onPressed: busy
                          ? null
                          : () => _run(() async {
                                final code = await r.createCoachInvite();
                                if (mounted) setState(() => myCode = code);
                              }),
                      child: const Text('Neuen Einladungscode erzeugen'),
                    ),
                  ]),
                ),
                const SizedBox(height: 12),
                TriCard(
                  title: 'Meine Athleten',
                  icon: Icons.groups_rounded,
                  trailing: IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded), tooltip: 'Aktualisieren'),
                  child: athletes == null
                      ? const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator()))
                      : athletes!.isEmpty
                          ? const EmptyHint('Noch keine Athleten', 'Sobald jemand deinen Code einlöst, erscheint er hier.', icon: Icons.person_add_alt_rounded)
                          : Column(children: [
                              for (final a in athletes!)
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: CircleAvatar(child: Text(_initial('${a['display_name'] ?? ''}'))),
                                  title: Text('${a['display_name'] ?? 'Athlet'}'),
                                  trailing: const Icon(Icons.chevron_right_rounded),
                                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AthleteView(id: '${a['id']}', name: '${a['display_name'] ?? 'Athlet'}'))),
                                ),
                            ]),
                ),
              ],
            ),
    );
  }
}

/// Trainer-Ansicht eines Athleten: letzte 14 Tage, nächste 14 Tage, Ampel erledigt/verpasst
class AthleteView extends StatefulWidget {
  const AthleteView({super.key, required this.id, required this.name});
  final String id;
  final String name;

  @override
  State<AthleteView> createState() => _AthleteViewState();
}

class _AthleteViewState extends State<AthleteView> {
  List<Activity> acts = [];
  List<PlannedSession> plan = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = AppScope.read(context).remote!;
    final from = DateTime.now().subtract(const Duration(days: 14));
    final a = await r.athleteActivities(widget.id, from);
    final p = await r.athletePlan(widget.id, from);
    if (!mounted) return;
    setState(() {
      acts = a.map(Activity.fromRow).toList();
      plan = p.map(PlannedSession.fromRow).toList();
      loading = false;
    });
  }

  Activity? _done(PlannedSession p) {
    for (final a in acts) {
      if (sameDay(a.start.toLocal(), p.startsAt.toLocal()) && (p.sport == null || p.sport == a.sport)) return a;
    }
    return null;
  }

  Future<void> _planFor() async {
    final title = TextEditingController(), minutes = TextEditingController(text: '1:00'), notes = TextEditingController();
    var sport = Sport.run;
    var day = DateTime.now().add(const Duration(days: 1));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text('Einheit für ${widget.name}'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Wrap(spacing: 6, children: [
                for (final s in Sport.values) ChoiceChip(label: Text(s.label), selected: sport == s, onSelected: (_) => set(() => sport = s)),
              ]),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.event_rounded),
                label: Text(dayTitle(day)),
                onPressed: () async {
                  final d = await showDatePicker(context: ctx, initialDate: day, firstDate: DateTime.now().subtract(const Duration(days: 1)), lastDate: DateTime(2100));
                  if (d != null) set(() => day = DateTime(d.year, d.month, d.day, 17));
                },
              ),
              const SizedBox(height: 8),
              TextField(controller: title, decoration: const InputDecoration(labelText: 'Titel', hintText: 'z. B. Schwelle 5×1 km')),
              const SizedBox(height: 8),
              TextField(controller: minutes, decoration: const InputDecoration(labelText: 'Dauer (h:mm)')),
              const SizedBox(height: 8),
              TextField(controller: notes, minLines: 2, maxLines: 6, decoration: const InputDecoration(labelText: 'Beschreibung')),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Planen')),
          ],
        ),
      ),
    );
    if (ok == true && mounted) {
      final p = PlannedSession(
        id: Repository.newId(),
        sport: sport,
        title: title.text.trim(),
        startsAt: DateTime(day.year, day.month, day.day, 17).toUtc(),
        minutes: parseDurationMinutes(minutes.text),
        notes: notes.text.trim(),
      );
      await AppScope.read(context).remote!.planForAthlete(widget.id, p.toRow()..remove('created_by'));
      await _load();
    }
    title.dispose();
    minutes.dispose();
    notes.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = TriColors.of(context);
    final now = DateTime.now();
    final past = plan.where((p) => p.kind == PlanKind.workout && p.startsAt.isBefore(startOfDay(now))).toList();
    final doneN = past.where((p) => _done(p) != null).length;
    return Scaffold(
      appBar: AppBar(title: Text(widget.name)),
      floatingActionButton: FloatingActionButton.extended(heroTag: 'fab-coach', onPressed: _planFor, icon: const Icon(Icons.add_rounded), label: const Text('Einheit planen')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 100), children: [
                if (past.isNotEmpty)
                  TriCard(
                    child: Row(children: [
                      Icon(Icons.traffic_rounded, color: doneN == past.length ? c.good : (doneN >= past.length / 2 ? c.warn : c.bad)),
                      const SizedBox(width: 10),
                      Expanded(child: Text('$doneN von ${past.length} geplanten Einheiten der letzten 14 Tage erledigt')),
                    ]),
                  ),
                const SizedBox(height: 12),
                TriCard(
                  title: 'Plan',
                  icon: Icons.event_note_rounded,
                  child: plan.isEmpty
                      ? const EmptyHint('Nichts geplant', 'Plane die erste Einheit mit dem Knopf unten.')
                      : Column(children: [for (final p in plan) PlannedTile(p, done: _done(p))]),
                ),
                const SizedBox(height: 12),
                TriCard(
                  title: 'Einheiten (14 Tage)',
                  icon: Icons.history_rounded,
                  child: acts.isEmpty
                      ? const EmptyHint('Keine Einheiten', 'In den letzten 14 Tagen nichts eingetragen.')
                      : Column(children: [
                          for (final a in acts)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: SportBadge(a.sport),
                              title: Text(a.title),
                              subtitle: Text('${shortDate(a.start.toLocal())} · ${hm(a.durationS)}${a.distanceM > 0 ? ' · ${distTxt(a.sport, a.distanceM)}' : ''}${a.rpe != null ? ' · RPE ${a.rpe}' : ''}${a.notes.isNotEmpty ? '\n${a.notes}' : ''}'),
                            ),
                        ]),
                ),
              ]),
            ),
    );
  }
}

String _initial(String name) => name.trim().isEmpty ? '?' : name.trim().characters.first.toUpperCase();
