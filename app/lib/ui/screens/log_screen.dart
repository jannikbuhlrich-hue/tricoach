import 'package:flutter/material.dart';

import '../../core/analytics.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/sport.dart';
import '../../data/repository.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import '../widgets.dart';

/// Einheit eintragen oder bearbeiten.
Future<void> openLog(BuildContext context, {Activity? existing, PlannedSession? fromPlan, DateTime? day}) =>
    Navigator.of(context).push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => LogScreen(existing: existing, fromPlan: fromPlan, day: day)));

class LogScreen extends StatefulWidget {
  const LogScreen({super.key, this.existing, this.fromPlan, this.day});
  final Activity? existing;
  final PlannedSession? fromPlan;
  final DateTime? day;

  @override
  State<LogScreen> createState() => _LogScreenState();
}

class _ExRow {
  _ExRow([Exercise? e])
      : name = TextEditingController(text: e?.name ?? ''),
        sets = TextEditingController(text: e?.sets?.toString() ?? ''),
        reps = TextEditingController(text: e?.reps ?? ''),
        kg = TextEditingController(text: _kgTxt(e?.kg));
  static String _kgTxt(double? kg) => kg == null ? '' : de(kg, kg % 1 == 0 ? 0 : 1).replaceAll('.', '');
  final TextEditingController name, sets, reps, kg;
  Exercise? toExercise() => name.text.trim().isEmpty
      ? null
      : Exercise(
          name: name.text.trim(),
          sets: int.tryParse(sets.text.trim()),
          reps: reps.text.trim(),
          kg: double.tryParse(kg.text.trim().replaceAll(',', '.')),
        );
  void dispose() {
    for (final c in [name, sets, reps, kg]) {
      c.dispose();
    }
  }
}

class _LogScreenState extends State<LogScreen> {
  late Sport sport;
  late DateTime start;
  SwimWhere where = SwimWhere.pool25;
  int rpe = 5;
  final name = TextEditingController();
  final art = TextEditingController();
  final dur = TextEditingController();
  final dist = TextEditingController();
  final lanes = TextEditingController();
  final hr = TextEditingController();
  final kcal = TextEditingController();
  final notes = TextEditingController();
  final ex = <_ExRow>[];
  bool saving = false;

  Activity? get e => widget.existing;
  bool get watch => e != null && !e!.isManual;

  @override
  void initState() {
    super.initState();
    final a = e, p = widget.fromPlan;
    final now = DateTime.now();
    final day = widget.day;
    sport = a?.sport ?? p?.sport ?? Sport.swim;
    start = (a?.start ?? p?.startsAt)?.toLocal() ??
        (day != null && !sameDay(day, now) ? DateTime(day.year, day.month, day.day, 17) : DateTime(now.year, now.month, now.day, now.hour, now.minute ~/ 5 * 5).subtract(const Duration(hours: 1)));
    name.text = a?.name ?? p?.title ?? '';
    art.text = a?.art ?? '';
    final minutes = a != null ? (a.durationS / 60).round() : (p?.minutes ?? 60);
    dur.text = minutesTxt(minutes);
    final m = a?.distanceM ?? p?.distanceM ?? 0;
    if (m > 0) dist.text = (m / 1000).toStringAsFixed(sport == Sport.swim ? 2 : 1).replaceAll('.', ',');
    rpe = a?.rpe ?? 5;
    if (a?.avgHr != null) hr.text = '${a!.avgHr}';
    if (a?.kcal != null && a!.isManual) kcal.text = '${a.kcal}';
    notes.text = a?.notes ?? p?.notes ?? '';
    where = a?.swimWhere ?? _lastWhere() ?? SwimWhere.pool25;
    for (final x in a?.exercises ?? const <Exercise>[]) {
      ex.add(_ExRow(x));
    }
  }

  SwimWhere? _lastWhere() {
    final app = AppScope.read(context);
    for (final a in app.activities) {
      if (a.sport == Sport.swim && a.swimWhere != null) return a.swimWhere;
    }
    return null;
  }

  @override
  void dispose() {
    for (final c in [name, art, dur, dist, lanes, hr, kcal, notes]) {
      c.dispose();
    }
    for (final r in ex) {
      r.dispose();
    }
    super.dispose();
  }

  double? get _distM {
    final v = double.tryParse(dist.text.trim().replaceAll(',', '.'));
    return v == null || v <= 0 ? null : v * 1000;
  }

  int? get _durS {
    final m = parseDurationMinutes(dur.text);
    return m == null || m <= 0 ? null : m * 60;
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(context: context, initialDate: start, firstDate: DateTime(2015), lastDate: DateTime.now().add(const Duration(days: 1)));
    if (d != null) setState(() => start = DateTime(d.year, d.month, d.day, start.hour, start.minute));
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(start));
    if (t != null) setState(() => start = DateTime(start.year, start.month, start.day, t.hour, t.minute));
  }

  Future<void> _save() async {
    final app = AppScope.read(context);
    final durS = watch ? e!.durationS : _durS;
    if (durS == null) {
      showMsg(context, 'Bitte eine Dauer eintragen, z. B. 1:15');
      return;
    }
    setState(() => saving = true);
    final exercises = sport == Sport.strength ? ex.map((r) => r.toExercise()).whereType<Exercise>().toList() : const <Exercise>[];
    final kcalVal = int.tryParse(kcal.text.trim());
    final a = Activity(
      id: e?.id ?? Repository.newId(),
      sport: watch ? e!.sport : sport,
      art: sport == Sport.other ? art.text.trim() : null,
      name: name.text.trim(),
      start: watch ? e!.start : start.toUtc(),
      durationS: durS,
      distanceM: sport.hasDistance ? (_distM ?? 0) : 0,
      rpe: rpe,
      avgHr: watch ? e!.avgHr : int.tryParse(hr.text.trim()),
      maxHr: e?.maxHr,
      kcal: watch ? e!.kcal : (kcalVal ?? estimateKcal(sport, durS, rpe, app.profile.weightKg)),
      notes: notes.text.trim(),
      swimWhere: sport == Sport.swim ? where : null,
      exercises: exercises,
      source: e?.source ?? 'manual',
      extId: e?.extId,
      details: e?.details,
    );
    await app.repo.saveActivity(a);
    if (!mounted) return;
    Navigator.of(context).pop();
    showMsg(context, e != null ? 'Einheit aktualisiert' : '${a.title} eingetragen${a.distanceM > 0 ? ' · ${distTxt(a.sport, a.distanceM)}' : ''}');
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Einheit löschen?'),
        content: Text(watch ? 'Sie verschwindet auf allen Geräten. Von der Uhr wird sie nicht erneut geholt.' : 'Sie verschwindet auf allen Geräten.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Löschen')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await AppScope.read(context).repo.deleteActivity(e!.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = TriColors.of(context);
    final hint = paceHint(sport, _distM, _durS);
    return Scaffold(
      appBar: AppBar(
        title: Text(e != null ? 'Einheit bearbeiten' : 'Einheit eintragen'),
        actions: [
          if (e != null) IconButton(tooltip: 'Löschen', icon: const Icon(Icons.delete_outline_rounded), onPressed: _delete),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(onPressed: saving ? null : _save, child: const Text('Sichern')),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          if (watch)
            TriCard(
              child: Row(children: [
                Icon(Icons.watch_rounded, color: c.accent),
                const SizedBox(width: 12),
                const Expanded(child: Text('Einheit von deiner Uhr. Messdaten bleiben unverändert – Name, Distanz, Bahn, RPE und Notizen kannst du korrigieren.')),
              ]),
            )
          else
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final s in Sport.values)
                ChoiceChip(
                  avatar: Icon(sportIcon(s), size: 18, color: sport == s ? c.onAccent : c.sport(s)),
                  label: Text(s.label),
                  selected: sport == s,
                  selectedColor: c.sport(s),
                  onSelected: (_) => setState(() => sport = s),
                ),
            ]),
          const SizedBox(height: 16),
          TextField(controller: name, decoration: InputDecoration(labelText: 'Titel', hintText: sport == Sport.other && art.text.isNotEmpty ? art.text : sport.defaultTitle)),
          if (sport == Sport.other) ...[
            const SizedBox(height: 12),
            Autocomplete<String>(
              initialValue: TextEditingValue(text: art.text),
              optionsBuilder: (v) => otherTypes.where((t) => t.toLowerCase().contains(v.text.toLowerCase())),
              onSelected: (v) => art.text = v,
              fieldViewBuilder: (ctx, ctl, focus, submit) => TextField(
                controller: ctl,
                focusNode: focus,
                onChanged: (v) => art.text = v,
                decoration: const InputDecoration(labelText: 'Art', hintText: 'z. B. Kitesurfen'),
              ),
            ),
          ],
          const SizedBox(height: 12),
          if (!watch)
            Row(children: [
              Expanded(child: OutlinedButton.icon(onPressed: _pickDate, icon: const Icon(Icons.event_rounded), label: Text(shortDate(start)))),
              const SizedBox(width: 8),
              Expanded(child: OutlinedButton.icon(onPressed: _pickTime, icon: const Icon(Icons.schedule_rounded), label: Text(timeTxt(start)))),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: dur,
                  keyboardType: TextInputType.datetime,
                  decoration: const InputDecoration(labelText: 'Dauer (h:mm)', hintText: '1:00'),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ]),
          if (sport == Sport.swim) ...[
            const SizedBox(height: 16),
            Text('Wo geschwommen?', style: TextStyle(color: c.muted)),
            const SizedBox(height: 6),
            SegmentedButton<SwimWhere>(
              segments: [for (final w in SwimWhere.values) ButtonSegment(value: w, label: Text(w.label))],
              selected: {where},
              onSelectionChanged: (s) => setState(() => where = s.first),
              showSelectedIcon: false,
            ),
          ],
          if (sport.hasDistance) ...[
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: dist,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: sport == Sport.swim ? 'Geschwommen (km)' : 'Distanz (km)', hintText: sport == Sport.swim ? 'z. B. 1,8' : 'z. B. 42,5'),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              if (sport == Sport.swim && where.poolLength != null) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: lanes,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: 'oder Bahnen à ${where.poolLength} m'),
                    onChanged: (v) {
                      final n = int.tryParse(v.trim());
                      if (n != null && n > 0) dist.text = (n * where.poolLength! / 1000).toStringAsFixed(2).replaceAll('.', ',');
                      setState(() {});
                    },
                  ),
                ),
              ],
            ]),
            if (hint.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(hint, style: TextStyle(color: c.muted))),
          ],
          if (sport == Sport.strength) ...[
            const SizedBox(height: 16),
            Row(children: [
              Text('Übungen', style: TextStyle(color: c.muted)),
              Text('  optional', style: TextStyle(color: c.faint, fontSize: 12)),
              const Spacer(),
              TextButton.icon(onPressed: () => setState(() => ex.add(_ExRow())), icon: const Icon(Icons.add_rounded), label: const Text('Übung')),
            ]),
            if (ex.isEmpty) Text('Z. B. Kniebeuge 3 × 10 mit 40 kg, Plank 3 × 45 s.', style: TextStyle(color: c.faint, fontSize: 13)),
            for (final r in ex)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(children: [
                  Expanded(flex: 4, child: TextField(controller: r.name, decoration: const InputDecoration(hintText: 'Übung'))),
                  const SizedBox(width: 6),
                  Expanded(flex: 2, child: TextField(controller: r.sets, keyboardType: TextInputType.number, decoration: const InputDecoration(hintText: 'Sätze'))),
                  const SizedBox(width: 6),
                  Expanded(flex: 2, child: TextField(controller: r.reps, decoration: const InputDecoration(hintText: 'Wdh'))),
                  const SizedBox(width: 6),
                  Expanded(flex: 2, child: TextField(controller: r.kg, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(hintText: 'kg'))),
                  IconButton(
                    tooltip: 'Übung entfernen',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => setState(() {
                      ex.remove(r);
                      r.dispose();
                    }),
                  ),
                ]),
              ),
          ],
          const SizedBox(height: 16),
          Row(children: [
            Text('Anstrengung (RPE)', style: TextStyle(color: c.muted)),
            const Spacer(),
            Text('$rpe · ${rpeText[rpe]}', style: const TextStyle(fontWeight: FontWeight.w700)),
          ]),
          Slider(value: rpe.toDouble(), min: 1, max: 10, divisions: 9, label: '$rpe', onChanged: (v) => setState(() => rpe = v.round())),
          if (!watch)
            Row(children: [
              Expanded(child: TextField(controller: hr, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Ø Puls', hintText: 'optional'))),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: kcal, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Kalorien', hintText: 'wird geschätzt'))),
            ]),
          const SizedBox(height: 12),
          TextField(
            controller: notes,
            minLines: 3,
            maxLines: 8,
            decoration: const InputDecoration(labelText: 'Notizen', hintText: 'Für dich und deinen Coach – z. B. Hauptserie, Gefühl, Material'),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(onPressed: saving ? null : _save, icon: const Icon(Icons.check_rounded), label: Text(e != null ? 'Änderungen sichern' : 'Einheit sichern')),
        ],
      ),
    );
  }
}
