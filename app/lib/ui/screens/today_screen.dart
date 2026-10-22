import 'package:flutter/material.dart';

import '../../core/analytics.dart';
import '../../core/format.dart';
import '../../core/sport.dart';
import '../../state/app_state.dart';
import '../charts.dart';
import '../school_card.dart';
import '../theme.dart';
import '../widgets.dart';
import 'log_screen.dart';
import 'connect_screens.dart';
import 'plan_editor.dart';
import 'tp_export_screen.dart';

/// „Mein Tag“: was heute ansteht, was erledigt ist, Form und Wochenziel auf einen Blick.
/// Ab 17 Uhr rückt (wie in der Web-App) zusätzlich der nächste Tag nach oben.
class TodayScreen extends StatelessWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context), c = TriColors.of(context);
    final now = DateTime.now(), today = startOfDay(now);
    final tomorrow = addDays(today, 1);
    final evening = now.hour >= 17;
    final repo = app.repo;

    final pts = performanceChart(app.activities, addDays(today, -1), today, app.profile);
    final load = pts.isNotEmpty ? pts.last : LoadPoint(today, 0, 0, 0, 0);
    final form = formState(load.tsb);
    final week = totals(app.activities, weekStart(today), addDays(weekStart(today), 7));
    final goal = app.profile.weeklyHoursGoal;

    Widget dayCard(DateTime day, String title) {
      final plan = repo.plannedOn(day), done = repo.activitiesOn(day);
      final unplannedDone = done.where((a) => !plan.any((p) => repo.doneFor(p)?.id == a.id)).toList();
      return TriCard(
        title: title,
        icon: Icons.today_rounded,
        trailing: IconButton(
          tooltip: 'Planen',
          icon: const Icon(Icons.add_rounded),
          onPressed: () => openPlanEditor(context, day: day),
        ),
        child: plan.isEmpty && done.isEmpty
            ? EmptyHint(sameDay(day, today) ? 'Noch nichts für heute' : 'Nichts geplant', 'Plane eine Einheit oder trag ein, was du gemacht hast.', icon: Icons.wb_sunny_outlined)
            : Column(children: [
                for (final p in plan)
                  PlannedTile(p, done: repo.doneFor(p), onTap: () => openPlanEditor(context, existing: p)),
                for (final a in unplannedDone)
                  ActivityTile(a, onTap: () => openLog(context, existing: a)),
              ]),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(dayTitle(now), style: const TextStyle(fontWeight: FontWeight.w700)),
        actions: const [Padding(padding: EdgeInsets.only(right: 12), child: Center(child: SyncChip()))],
      ),
      body: RefreshIndicator(
        onRefresh: app.refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
          children: [
            if (evening) ...[dayCard(tomorrow, 'Morgen'), const SizedBox(height: 12)],
            dayCard(today, 'Heute'),
            const SizedBox(height: 12),
            if (app.signedIn && !app.untisOn && !app.untisHintOff) ...[
              Card(
                child: ListTile(
                  leading: Icon(Icons.school_rounded, color: c.accent),
                  title: const Text('Stundenplan verbinden'),
                  subtitle: const Text('WebUntis: Ausfall, Vertretung und Hausaufgaben direkt in Mein Tag'),
                  onTap: () => openUntisConnect(context),
                  trailing: IconButton(tooltip: 'Ausblenden', icon: const Icon(Icons.close_rounded), onPressed: app.hideUntisHint),
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (app.tpMissing(7).isNotEmpty) ...[
              Card(
                child: ListTile(
                  leading: Icon(Icons.upload_rounded, color: c.warn),
                  title: Text(app.tpMissing(7).length == 1 ? '1 Einheit fehlt in TrainingPeaks' : '${app.tpMissing(7).length} Einheiten fehlen in TrainingPeaks'),
                  subtitle: const Text('Deine Trainerin sieht sie erst nach dem Nachtragen'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => openTpExport(context),
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (app.school != null || app.schoolError != null) ...[
              SchoolCard(day: evening ? tomorrow : today, title: evening ? 'Schule morgen' : 'Schule heute'),
              const SizedBox(height: 12),
            ],
            GridView.count(
              crossAxisCount: MediaQuery.sizeOf(context).width > 700 ? 4 : 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.4,
              children: [
                StatTile(label: 'Form', value: de(load.tsb), sub: form.label, color: [c.good, c.form, c.warn, c.bad][form.level], icon: Icons.speed_rounded),
                StatTile(label: 'Fitness', value: de(load.ctl), sub: 'Ermüdung ${de(load.atl)}', color: c.fit, icon: Icons.trending_up_rounded),
                StatTile(label: 'Diese Woche', value: hm(week.durationS), sub: '${week.count} Einheiten · Ziel ${de(goal)} h', color: c.accent, icon: Icons.timer_rounded),
                StatTile(label: 'Serie', value: '${weekStreak(app.activities, today)}', unit: 'Wochen', sub: 'mit Training am Stück', color: c.run, icon: Icons.local_fire_department_rounded),
              ],
            ),
            const SizedBox(height: 12),
            TriCard(
              title: 'Wochenziel',
              icon: Icons.donut_large_rounded,
              child: Row(children: [
                Ring(
                  value: goal > 0 ? week.durationS / 3600 / goal : 0,
                  color: c.accent,
                  size: 72,
                  child: Text('${goal > 0 ? (week.durationS / 36 / goal).round() : 0} %', style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    for (final s in Sport.values)
                      if (totals(app.activities, weekStart(today), addDays(weekStart(today), 7), sport: s).count > 0)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(children: [
                            Icon(sportIcon(s), size: 16, color: c.sport(s)),
                            const SizedBox(width: 6),
                            Expanded(child: Text(s.label, maxLines: 1, overflow: TextOverflow.ellipsis)),
                            const SizedBox(width: 6),
                            Flexible(
                              flex: 2,
                              child: Text(() {
                                final t = totals(app.activities, weekStart(today), addDays(weekStart(today), 7), sport: s);
                                return '${hm(t.durationS)}${t.distanceM > 0 ? ' · ${distTxt(s, t.distanceM)}' : ''}';
                              }(), maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.right, style: TextStyle(color: c.muted)),
                            ),
                          ]),
                        ),
                    Text(form.hint, style: TextStyle(color: c.muted, fontSize: 12)),
                  ]),
                ),
              ]),
            ),
            const SizedBox(height: 12),
            TriCard(
              title: 'Letzte Einheiten',
              icon: Icons.history_rounded,
              child: app.activities.isEmpty
                  ? const EmptyHint('Noch keine Einheiten', 'Verbinde deine Uhr in den Einstellungen oder trag deine erste Einheit ein.', icon: Icons.watch_rounded)
                  : Column(children: [
                      for (final a in app.activities.take(5))
                        ActivityTile(a, onTap: () => openLog(context, existing: a)),
                    ]),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab-today',
        onPressed: () => openLog(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Eintragen'),
      ),
    );
  }
}
