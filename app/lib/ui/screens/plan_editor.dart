import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/sport.dart';
import '../../data/repository.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import '../widgets.dart';
import 'log_screen.dart';

/// Einheit planen, Termin oder Wettkampf eintragen (oder bearbeiten)
Future<void> openPlanEditor(BuildContext context, {DateTime? day, PlannedSession? existing}) => Navigator.of(context).push(
      MaterialPageRoute(fullscreenDialog: true, builder: (_) => PlanEditor(day: day, existing: existing)),
    );

class PlanEditor extends StatefulWidget {
  const PlanEditor({super.key, this.day, this.existing});
  final DateTime? day;
  final PlannedSession? existing;

  @override
  State<PlanEditor> createState() => _PlanEditorState();
}

class _PlanEditorState extends State<PlanEditor> {
  late PlanKind kind;
  Sport? sport;
  late DateTime start;
  bool allDay = false;
  String prio = 'A';
  final title = TextEditingController();
  final dur = TextEditingController();
  final dist = TextEditingController();
  final notes = TextEditingController();

  PlannedSession? get e => widget.existing;

  @override
  void initState() {
    super.initState();
    final p = e;
    kind = p?.kind ?? PlanKind.workout;
    sport = p?.sport ?? (p == null ? Sport.run : null);
    final d = widget.day ?? DateTime.now().add(const Duration(days: 1));
    start = p?.startsAt.toLocal() ?? DateTime(d.year, d.month, d.day, 17);
    allDay = p?.allDay ?? false;
    prio = p?.racePrio ?? 'A';
    title.text = p?.title ?? '';
    dur.text = minutesTxt(p?.minutes ?? 60);
    if ((p?.distanceM ?? 0) > 0) dist.text = (p!.distanceM! / 1000).toStringAsFixed(1).replaceAll('.', ',');
    notes.text = p?.notes ?? '';
  }

  @override
  void dispose() {
    for (final c in [title, dur, dist, notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final app = AppScope.read(context);
    final km = double.tryParse(dist.text.trim().replaceAll(',', '.'));
    final p = PlannedSession(
      id: e?.id ?? Repository.newId(),
      kind: kind,
      sport: kind == PlanKind.event ? null : sport,
      title: title.text.trim(),
      startsAt: (allDay ? DateTime(start.year, start.month, start.day) : start).toUtc(),
      minutes: allDay ? null : parseDurationMinutes(dur.text),
      distanceM: km == null || km <= 0 ? null : km * 1000,
      allDay: allDay,
      notes: notes.text.trim(),
      racePrio: kind == PlanKind.race ? prio : null,
      createdBy: e?.createdBy,
    );
    await app.repo.savePlanned(p);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    await AppScope.read(context).repo.deletePlanned(e!.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = TriColors.of(context);
    final done = e == null ? null : AppScope.of(context).repo.doneFor(e!);
    return Scaffold(
      appBar: AppBar(
        title: Text(e == null ? 'Planen' : 'Geplant'),
        actions: [
          if (e != null) IconButton(tooltip: 'Löschen', icon: const Icon(Icons.delete_outline_rounded), onPressed: _delete),
          Padding(padding: const EdgeInsets.only(right: 8), child: FilledButton(onPressed: _save, child: const Text('Sichern'))),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          SegmentedButton<PlanKind>(
            segments: const [
              ButtonSegment(value: PlanKind.workout, label: Text('Training'), icon: Icon(Icons.fitness_center_rounded)),
              ButtonSegment(value: PlanKind.event, label: Text('Termin'), icon: Icon(Icons.event_rounded)),
              ButtonSegment(value: PlanKind.race, label: Text('Wettkampf'), icon: Icon(Icons.flag_rounded)),
            ],
            selected: {kind},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() {
              kind = s.first;
              if (kind == PlanKind.race) allDay = true;
            }),
          ),
          const SizedBox(height: 16),
          if (kind != PlanKind.event)
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
          const SizedBox(height: 12),
          TextField(
            controller: title,
            decoration: InputDecoration(
              labelText: 'Titel',
              hintText: switch (kind) { PlanKind.workout => 'z. B. Schwelle 5×1 km', PlanKind.event => 'z. B. Physio', PlanKind.race => 'z. B. Stadttriathlon' },
            ),
          ),
          if (kind == PlanKind.race) ...[
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'A', label: Text('A – Saisonhöhepunkt')),
                ButtonSegment(value: 'B', label: Text('B')),
                ButtonSegment(value: 'C', label: Text('C')),
              ],
              selected: {prio},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => prio = s.first),
            ),
          ],
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.event_rounded),
                label: Text(shortDate(start)),
                onPressed: () async {
                  final d = await showDatePicker(context: context, initialDate: start, firstDate: DateTime(2015), lastDate: DateTime(2100));
                  if (d != null) setState(() => start = DateTime(d.year, d.month, d.day, start.hour, start.minute));
                },
              ),
            ),
            const SizedBox(width: 8),
            if (!allDay)
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.schedule_rounded),
                  label: Text(timeTxt(start)),
                  onPressed: () async {
                    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(start));
                    if (t != null) setState(() => start = DateTime(start.year, start.month, start.day, t.hour, t.minute));
                  },
                ),
              ),
          ]),
          SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Ganztägig'), value: allDay, onChanged: (v) => setState(() => allDay = v)),
          if (!allDay)
            Row(children: [
              Expanded(child: TextField(controller: dur, decoration: const InputDecoration(labelText: 'Dauer (h:mm)'))),
              if (kind == PlanKind.workout && (sport?.hasDistance ?? false)) ...[
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: dist, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Distanz (km)', hintText: 'optional'))),
              ],
            ]),
          const SizedBox(height: 12),
          TextField(controller: notes, minLines: 3, maxLines: 10, decoration: const InputDecoration(labelText: 'Beschreibung', hintText: 'z. B. 15 min ein, 5×1 km @ Schwelle, 90 s Trabpause')),
          if (e != null && e!.kind == PlanKind.workout) ...[
            const SizedBox(height: 20),
            if (done != null)
              TriCard(child: Row(children: [Icon(Icons.check_circle_rounded, color: c.good), const SizedBox(width: 10), Expanded(child: Text('Erledigt: ${done.title} · ${hm(done.durationS)}'))]))
            else
              OutlinedButton.icon(
                icon: const Icon(Icons.check_rounded),
                label: const Text('Als erledigt eintragen'),
                onPressed: () async {
                  final nav = Navigator.of(context);
                  nav.pop();
                  await openLog(nav.context, fromPlan: e);
                },
              ),
          ],
        ],
      ),
    );
  }
}
