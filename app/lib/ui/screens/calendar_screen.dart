import 'package:flutter/material.dart';

import '../../core/analytics.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import '../widgets.dart';
import 'log_screen.dart';
import 'plan_editor.dart';

enum CalView { month, week, list }

/// Kalender: Monat (mit KW), Woche, Liste – geplante und erledigte Einheiten zusammen.
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  CalView view = CalView.month;
  DateTime focus = startOfDay(DateTime.now());
  DateTime selected = startOfDay(DateTime.now());

  void _shift(int dir) => setState(() {
        focus = switch (view) {
          CalView.month => DateTime(focus.year, focus.month + dir, 1),
          CalView.week => addDays(focus, 7 * dir),
          CalView.list => addDays(focus, 14 * dir),
        };
      });

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final title = switch (view) {
      CalView.month => '${monthNames[focus.month - 1]} ${focus.year}',
      CalView.week => 'KW ${isoWeek(focus)} · ${shortDate(weekStart(focus))} – ${shortDate(addDays(weekStart(focus), 6))}',
      CalView.list => 'Ab ${shortDate(focus)}',
    };
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kalender', style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          TextButton(
            onPressed: () => setState(() {
              focus = startOfDay(DateTime.now());
              selected = focus;
            }),
            child: const Text('Heute'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
        children: [
          SegmentedButton<CalView>(
            segments: const [
              ButtonSegment(value: CalView.month, label: Text('Monat')),
              ButtonSegment(value: CalView.week, label: Text('Woche')),
              ButtonSegment(value: CalView.list, label: Text('Liste')),
            ],
            selected: {view},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() => view = s.first),
          ),
          const SizedBox(height: 8),
          Row(children: [
            IconButton(onPressed: () => _shift(-1), icon: const Icon(Icons.chevron_left_rounded), tooltip: 'Zurück'),
            Expanded(child: Text(title, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
            IconButton(onPressed: () => _shift(1), icon: const Icon(Icons.chevron_right_rounded), tooltip: 'Weiter'),
          ]),
          const SizedBox(height: 8),
          ...switch (view) {
            CalView.month => [_month(context, app), const SizedBox(height: 12), _day(context, app, selected)],
            CalView.week => [for (var i = 0; i < 7; i++) Padding(padding: const EdgeInsets.only(bottom: 10), child: _day(context, app, addDays(weekStart(focus), i), compact: true))],
            CalView.list => _list(context, app),
          },
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'fab-calendar',
        tooltip: 'Planen',
        onPressed: () => openPlanEditor(context, day: selected),
        child: const Icon(Icons.add_rounded),
      ),
    );
  }

  Widget _month(BuildContext context, AppState app) {
    final c = TriColors.of(context);
    final first = DateTime(focus.year, focus.month, 1);
    final gridStart = weekStart(first);
    final today = startOfDay(DateTime.now());
    return TriCard(
      padding: const EdgeInsets.all(8),
      child: Column(children: [
        Row(children: [
          SizedBox(width: 28, child: Text('KW', style: TextStyle(fontSize: 10, color: c.faint))),
          for (final d in wdShort) Expanded(child: Center(child: Text(d, style: TextStyle(fontSize: 12, color: c.muted)))),
        ]),
        for (var w = 0; w < 6; w++)
          if (w < 5 || addDays(gridStart, w * 7).month == focus.month)
            Row(children: [
              SizedBox(width: 28, child: Text('${isoWeek(addDays(gridStart, w * 7))}', style: TextStyle(fontSize: 10, color: c.faint))),
              for (var d = 0; d < 7; d++)
                Expanded(child: () {
                  final day = addDays(gridStart, w * 7 + d);
                  final plan = app.repo.plannedOn(day), done = app.repo.activitiesOn(day);
                  final inMonth = day.month == focus.month, isSel = sameDay(day, selected), isToday = sameDay(day, today);
                  return InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => setState(() => selected = day),
                    child: Container(
                      height: 52,
                      margin: const EdgeInsets.all(1.5),
                      decoration: BoxDecoration(
                        color: isSel ? c.accent.withValues(alpha: .18) : null,
                        borderRadius: BorderRadius.circular(10),
                        border: isToday ? Border.all(color: c.accent, width: 1.5) : null,
                      ),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Text('${day.day}', style: TextStyle(fontWeight: isToday ? FontWeight.w800 : FontWeight.w500, color: inMonth ? c.fg : c.faint)),
                        const SizedBox(height: 4),
                        Wrap(spacing: 2, runSpacing: 2, alignment: WrapAlignment.center, children: [
                          for (final a in done.take(4)) Container(width: 6, height: 6, decoration: BoxDecoration(color: c.sport(a.sport), shape: BoxShape.circle)),
                          for (final p in plan.where((p) => app.repo.doneFor(p) == null).take(3))
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: p.kind == PlanKind.race ? c.accent : c.sport(p.sport), width: 1.4)),
                            ),
                        ]),
                      ]),
                    ),
                  );
                }()),
            ]),
      ]),
    );
  }

  Widget _day(BuildContext context, AppState app, DateTime day, {bool compact = false}) {
    final plan = app.repo.plannedOn(day), done = app.repo.activitiesOn(day);
    final extra = done.where((a) => !plan.any((p) => app.repo.doneFor(p)?.id == a.id)).toList();
    final t = totals(done, day, addDays(day, 1));
    return TriCard(
      title: dayTitle(day),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (t.count > 0) Text(hm(t.durationS), style: TextStyle(color: TriColors.of(context).muted, fontSize: 12)),
        IconButton(visualDensity: VisualDensity.compact, tooltip: 'Eintragen', icon: const Icon(Icons.edit_note_rounded), onPressed: () => openLog(context, day: day)),
        IconButton(visualDensity: VisualDensity.compact, tooltip: 'Planen', icon: const Icon(Icons.add_rounded), onPressed: () => openPlanEditor(context, day: day)),
      ]),
      child: plan.isEmpty && done.isEmpty
          ? (compact ? const SizedBox.shrink() : const EmptyHint('Frei', 'Nichts geplant, nichts eingetragen.', icon: Icons.self_improvement_rounded))
          : Column(children: [
              for (final p in plan) PlannedTile(p, done: app.repo.doneFor(p), onTap: () => openPlanEditor(context, existing: p)),
              for (final a in extra) ActivityTile(a, onTap: () => openLog(context, existing: a)),
            ]),
    );
  }

  List<Widget> _list(BuildContext context, AppState app) {
    final out = <Widget>[];
    for (var i = 0; i < 28; i++) {
      final day = addDays(focus, i);
      if (app.repo.plannedOn(day).isEmpty && app.repo.activitiesOn(day).isEmpty) continue;
      out.add(Padding(padding: const EdgeInsets.only(bottom: 10), child: _day(context, app, day, compact: true)));
    }
    if (out.isEmpty) out.add(const EmptyHint('Keine Einträge', 'In den nächsten 4 Wochen ist nichts geplant oder eingetragen.'));
    return out;
  }
}
