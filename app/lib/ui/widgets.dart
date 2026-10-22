import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/models.dart';
import '../core/sport.dart';
import '../state/app_state.dart';
import 'theme.dart';

IconData sportIcon(Sport? s) => switch (s) {
      Sport.swim => Icons.pool_rounded,
      Sport.bike => Icons.directions_bike_rounded,
      Sport.run => Icons.directions_run_rounded,
      Sport.strength => Icons.fitness_center_rounded,
      Sport.other => Icons.bolt_rounded,
      null => Icons.event_rounded,
    };

/// Runder Sport-Punkt mit Icon
class SportBadge extends StatelessWidget {
  const SportBadge(this.sport, {super.key, this.size = 36});
  final Sport? sport;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = TriColors.of(context), col = c.sport(sport);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: col.withValues(alpha: .16), borderRadius: BorderRadius.circular(size * .3)),
      child: Icon(sportIcon(sport), color: col, size: size * .55),
    );
  }
}

/// Karte mit Überschrift (wie .card in der Web-App)
class TriCard extends StatelessWidget {
  const TriCard({super.key, this.title, this.icon, this.trailing, required this.child, this.padding = const EdgeInsets.all(16)});
  final String? title;
  final IconData? icon;
  final Widget? trailing;
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final c = TriColors.of(context);
    return Card(
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null) ...[
              Row(children: [
                if (icon != null) ...[Icon(icon, size: 18, color: c.accent), const SizedBox(width: 8)],
                Expanded(
                  child: Text(c.upperLabels ? title!.toUpperCase() : title!,
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, letterSpacing: c.upperLabels ? 1.1 : 0, color: c.fg)),
                ),
                if (trailing != null) trailing!,
              ]),
              const SizedBox(height: 12),
            ],
            child,
          ],
        ),
      ),
    );
  }
}

/// Kennzahl-Kachel (wie .tile in der Web-App)
class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.label, required this.value, this.unit, this.sub, this.color, this.icon, this.onTap});
  final String label;
  final String value;
  final String? unit;
  final String? sub;
  final Color? color;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = TriColors.of(context), col = color ?? c.accent;
    return Material(
      color: Color.alphaBlend(col.withValues(alpha: .11), c.surface),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(c.tileRadius), side: BorderSide(color: col.withValues(alpha: .26))),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              if (icon != null) ...[Icon(icon, size: 18, color: col), const SizedBox(width: 6)],
              Flexible(child: Text(c.upperLabels ? label.toUpperCase() : label, style: TextStyle(color: c.muted, fontSize: 13), overflow: TextOverflow.ellipsis)),
            ]),
            const SizedBox(height: 4),
            Text.rich(
              TextSpan(children: [
                TextSpan(text: value, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: c.upperLabels ? col : c.fg, fontFeatures: const [FontFeature.tabularFigures()])),
                if (unit != null) TextSpan(text: ' $unit', style: TextStyle(fontSize: 14, color: c.muted, fontWeight: FontWeight.w600)),
              ]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (sub != null) Text(sub!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: c.muted, fontSize: 12)),
          ]),
        ),
      ),
    );
  }
}

/// Zeile für eine absolvierte Einheit
class ActivityTile extends StatelessWidget {
  const ActivityTile(this.a, {super.key, this.onTap});
  final Activity a;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = TriColors.of(context);
    final parts = [
      hm(a.durationS),
      if (a.distanceM > 0) distTxt(a.sport, a.distanceM),
      if (a.avgHr != null) 'Ø ${a.avgHr} bpm',
      if (a.tss != null) 'TSS ${a.tss!.round()}',
    ];
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: onTap,
      leading: SportBadge(a.sport),
      title: Text(a.title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text('${timeTxt(a.start.toLocal())} · ${parts.join(' · ')}', style: TextStyle(color: c.muted)),
      trailing: a.isManual ? null : Tooltip(message: _sourceTxt(a.source), child: Icon(Icons.watch_rounded, size: 16, color: c.faint)),
    );
  }

  static String _sourceTxt(String s) => switch (s) {
        'health' => 'Von deiner Uhr (Apple Health / Health Connect)',
        'icu' => 'Von deiner Uhr (intervals.icu)',
        'fit' => 'FIT-Datei',
        _ => 'Importiert',
      };
}

/// Zeile für eine geplante Einheit / einen Termin
class PlannedTile extends StatelessWidget {
  const PlannedTile(this.p, {super.key, this.done, this.onTap});
  final PlannedSession p;
  final Activity? done;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = TriColors.of(context);
    final past = p.startsAt.isBefore(DateTime.now()) && !sameDay(p.startsAt.toLocal(), DateTime.now());
    final status = p.kind != PlanKind.workout
        ? null
        : done != null
            ? Icon(Icons.check_circle_rounded, color: c.good)
            : past
                ? Icon(Icons.cancel_rounded, color: c.bad.withValues(alpha: .8))
                : Icon(Icons.radio_button_unchecked_rounded, color: c.faint);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: onTap,
      leading: p.kind == PlanKind.race
          ? Container(width: 36, height: 36, decoration: BoxDecoration(color: c.accent.withValues(alpha: .16), borderRadius: BorderRadius.circular(11)), child: Icon(Icons.flag_rounded, color: c.accent, size: 20))
          : SportBadge(p.sport),
      title: Text(p.displayTitle, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
        [
          p.allDay ? 'ganztägig' : timeTxt(p.startsAt.toLocal()),
          if (p.minutes != null) hm(p.minutes! * 60),
          if (p.kind == PlanKind.race) 'Wettkampf${p.racePrio != null ? ' ${p.racePrio}' : ''}',
          if (p.notes.isNotEmpty) p.notes.split('\n').first,
        ].join(' · '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: c.muted),
      ),
      trailing: status,
    );
  }
}

/// Hinweis bei leeren Listen
class EmptyHint extends StatelessWidget {
  const EmptyHint(this.title, this.text, {super.key, this.icon = Icons.inbox_rounded});
  final String title;
  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final c = TriColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(children: [
        Icon(icon, color: c.faint),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
            Text(text, style: TextStyle(color: c.muted, fontSize: 13)),
          ]),
        ),
      ]),
    );
  }
}

/// Kleiner Status oben rechts: synchronisiert / wartet / offline
class SyncChip extends StatelessWidget {
  const SyncChip({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context), c = TriColors.of(context), s = app.syncStatus;
    if (app.localOnly) return _chip(c, Icons.phone_iphone_rounded, 'Nur dieses Gerät', c.muted);
    if (!app.signedIn) return _chip(c, Icons.cloud_off_rounded, 'Nicht angemeldet', c.warn);
    if (s.busy) return _chip(c, Icons.sync_rounded, 'Synchronisiere …', c.muted);
    if (s.error != null) return Tooltip(message: s.error!, child: _chip(c, Icons.cloud_off_rounded, s.pending > 0 ? '${s.pending} warten' : 'Offline', c.warn));
    if (s.pending > 0) return _chip(c, Icons.cloud_upload_rounded, '${s.pending} warten', c.muted);
    return _chip(c, Icons.cloud_done_rounded, 'Synchron', c.good);
  }

  Widget _chip(TriColors c, IconData i, String t, Color col) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.line), borderRadius: BorderRadius.circular(99)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(i, size: 14, color: col), const SizedBox(width: 6), Text(t, style: TextStyle(fontSize: 12, color: c.muted))]),
      );
}

void showMsg(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}
