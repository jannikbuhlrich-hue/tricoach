import 'package:flutter/material.dart';

import '../../core/analytics.dart';
import '../../core/format.dart';
import '../../core/sport.dart';
import '../../state/app_state.dart';
import '../charts.dart';
import '../theme.dart';
import '../widgets.dart';
import 'log_screen.dart';

/// Fortschritt: Form-Kurve, Wochenumfang, VO2 Max, Bestleistungen, Jahressummen.
class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key});

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  int days = 90;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context), c = TriColors.of(context);
    final today = startOfDay(DateTime.now());
    final acts = app.activities;
    final pts = performanceChart(acts, addDays(today, -days), today, app.profile);
    final last = pts.isNotEmpty ? pts.last : null;
    final weeks = weeklyTotals(acts, today, days > 120 ? 26 : 12);
    final vo2 = estimateVo2(acts, today);
    final vo2Before = estimateVo2(acts.where((a) => a.start.isBefore(addDays(today, -30))).toList(), addDays(today, -30));
    final b = bests(acts);
    final yearStart = DateTime(today.year, 1, 1);
    final year = {for (final s in Sport.values) s: totals(acts, yearStart, addDays(today, 1), sport: s)};
    final yearAll = totals(acts, yearStart, addDays(today, 1));
    final lastYear = totals(acts, DateTime(today.year - 1, 1, 1), DateTime(today.year - 1, today.month, today.day + 1));

    return Scaffold(
      appBar: AppBar(title: const Text('Fortschritt', style: TextStyle(fontWeight: FontWeight.w700))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
        children: [
          TriCard(
            title: 'Form-Kurve',
            icon: Icons.show_chart_rounded,
            trailing: SegmentedButton<int>(
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: const [ButtonSegment(value: 42, label: Text('6 W')), ButtonSegment(value: 90, label: Text('3 M')), ButtonSegment(value: 365, label: Text('1 J'))],
              selected: {days},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => days = s.first),
            ),
            child: acts.isEmpty
                ? const EmptyHint('Noch keine Daten', 'Die Kurve entsteht aus deinen Einheiten (TSS).')
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    LoadChart(pts),
                    if (last != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        'Fitness ${de(last.ctl)} · Ermüdung ${de(last.atl)} · Form ${de(last.tsb)} – ${formState(last.tsb).label}. ${formState(last.tsb).hint}',
                        style: TextStyle(color: c.muted, fontSize: 13),
                      ),
                    ],
                  ]),
          ),
          const SizedBox(height: 12),
          TriCard(
            title: 'Wochenumfang',
            icon: Icons.bar_chart_rounded,
            trailing: Text('Ziel ${de(app.profile.weeklyHoursGoal)} h', style: TextStyle(color: c.muted, fontSize: 12)),
            child: Column(children: [
              WeeklyBars(weeks, goalHours: app.profile.weeklyHoursGoal),
              const SizedBox(height: 8),
              Wrap(spacing: 12, runSpacing: 4, children: [
                for (final s in Sport.values)
                  Row(mainAxisSize: MainAxisSize.min, children: [Icon(sportIcon(s), size: 14, color: c.sport(s)), const SizedBox(width: 4), Text(s.label, style: const TextStyle(fontSize: 12))]),
              ]),
            ]),
          ),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: MediaQuery.sizeOf(context).width > 700 ? 4 : 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.4,
            children: [
              StatTile(
                label: 'VO2 Max',
                value: vo2 == null ? '–' : de(vo2, 1),
                sub: vo2 == null
                    ? 'aus Läufen ab 3 km'
                    : vo2Before != null
                        ? '${vo2 - vo2Before >= 0 ? '+' : ''}${de(vo2 - vo2Before, 1)} in 30 Tagen · geschätzt'
                        : 'geschätzt aus Läufen',
                color: c.run,
                icon: Icons.favorite_rounded,
              ),
              StatTile(
                label: '5 km',
                value: b.fastest5kS == null ? '–' : clock(b.fastest5kS!),
                sub: b.fastest5k == null ? 'bester Lauf ab 5 km' : shortDate(b.fastest5k!.start.toLocal()),
                color: c.run,
                icon: Icons.emoji_events_rounded,
                onTap: b.fastest5k == null ? null : () => openLog(context, existing: b.fastest5k),
              ),
              StatTile(
                label: '10 km',
                value: b.fastest10kS == null ? '–' : clock(b.fastest10kS!),
                sub: b.fastest10k == null ? 'bester Lauf ab 10 km' : shortDate(b.fastest10k!.start.toLocal()),
                color: c.run,
                icon: Icons.emoji_events_rounded,
                onTap: b.fastest10k == null ? null : () => openLog(context, existing: b.fastest10k),
              ),
              StatTile(
                label: 'Prognose 10 km',
                value: vo2 == null ? '–' : clock(predictSeconds(vo2, 10000)),
                sub: vo2 == null ? '' : 'Halbmarathon ${clock(predictSeconds(vo2, 21097.5))}',
                color: c.fit,
                icon: Icons.insights_rounded,
              ),
            ],
          ),
          const SizedBox(height: 12),
          TriCard(
            title: 'Längste Einheiten',
            icon: Icons.straighten_rounded,
            child: b.longest.isEmpty
                ? const EmptyHint('Noch nichts', 'Sobald du Einheiten mit Distanz hast, erscheinen sie hier.')
                : Column(children: [for (final a in b.longest.values) ActivityTile(a, onTap: () => openLog(context, existing: a))]),
          ),
          const SizedBox(height: 12),
          TriCard(
            title: 'Jahr ${today.year}',
            icon: Icons.calendar_month_rounded,
            trailing: Text('${yearAll.count} Einheiten · ${hm(yearAll.durationS)}', style: TextStyle(color: c.muted, fontSize: 12)),
            child: Column(children: [
              for (final s in Sport.values)
                if (year[s]!.count > 0)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(children: [
                      SportBadge(s, size: 28),
                      const SizedBox(width: 10),
                      Expanded(child: Text(s.label)),
                      Text('${year[s]!.distanceM > 0 ? '${distTxt(s, year[s]!.distanceM)} · ' : ''}${hm(year[s]!.durationS)}', style: TextStyle(color: c.muted)),
                    ]),
                  ),
              if (lastYear.count > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Zum selben Zeitpunkt ${today.year - 1}: ${hm(lastYear.durationS)} (${yearAll.durationS >= lastYear.durationS ? '+' : ''}${de((yearAll.durationS - lastYear.durationS) / 3600)} h)',
                    style: TextStyle(color: c.muted, fontSize: 13),
                  ),
                ),
              if (app.profile.yearKmGoal > 0) ...[
                const SizedBox(height: 10),
                () {
                  final km = yearAll.distanceM / 1000;
                  final dayOfYear = today.difference(yearStart).inDays + 1;
                  final projected = km / dayOfYear * 365;
                  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    LinearProgressIndicator(value: (km / app.profile.yearKmGoal).clamp(0, 1), minHeight: 8, borderRadius: BorderRadius.circular(8), color: c.accent),
                    const SizedBox(height: 4),
                    Text('${de(km)} von ${de(app.profile.yearKmGoal)} km · Hochrechnung ${de(projected)} km', style: TextStyle(color: c.muted, fontSize: 12)),
                  ]);
                }(),
              ],
            ]),
          ),
        ],
      ),
    );
  }
}
