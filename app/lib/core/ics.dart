import 'dart:convert';

import 'format.dart';
import 'models.dart';
import 'sport.dart';

/// Kalender-Datei (.ics) bauen – gleiche Regeln wie supabase/functions/calendar/ics.js.
/// Wird für den Export „Als Datei teilen“ genutzt; das Abo läuft über den Server.

String escapeIcs(String s) => s.replaceAll(r'\', r'\\').replaceAll(';', r'\;').replaceAll(',', r'\,').replaceAll(RegExp(r'\r?\n'), r'\n');

String foldIcs(String line) {
  if (utf8.encode(line).length <= 75) return line;
  final out = <String>[];
  final cur = StringBuffer();
  var bytes = 0, limit = 75;
  for (final rune in line.runes) {
    final ch = String.fromCharCode(rune);
    final b = utf8.encode(ch).length;
    if (bytes + b > limit) {
      out.add(cur.toString());
      cur.clear();
      bytes = 0;
      limit = 74;
    }
    cur.write(ch);
    bytes += b;
  }
  out.add(cur.toString());
  return out.join('\r\n ');
}

String icsUtc(DateTime d) {
  final u = d.toUtc();
  String p(int v, [int w = 2]) => v.toString().padLeft(w, '0');
  return '${p(u.year, 4)}${p(u.month)}${p(u.day)}T${p(u.hour)}${p(u.minute)}${p(u.second)}Z';
}

String _icsDate(DateTime d) => '${d.year.toString().padLeft(4, '0')}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';

const _icon = {Sport.swim: '🏊', Sport.bike: '🚴', Sport.run: '🏃', Sport.strength: '🏋️', Sport.other: '⚡'};

/// Kurzbeschreibung einer Einheit (Kalender, Teilen)
String activitySummary(Activity a) => [
      '${a.sport == Sport.other && (a.art ?? '').isNotEmpty ? a.art : a.sport.label} · ${hm(a.durationS)}${a.distanceM > 0 ? ' · ${distTxt(a.sport, a.distanceM)}' : ''}',
      if (a.avgHr != null) 'Ø Puls ${a.avgHr}',
      if (a.rpe != null) 'RPE ${a.rpe}/10',
      if (a.tss != null) 'TSS ${a.tss!.round()}',
      if (a.exercises.isNotEmpty) 'Übungen: ${a.exercises.join(', ')}',
      if (a.notes.trim().isNotEmpty) a.notes.trim(),
    ].join('\n');

String plannedSummary(PlannedSession p) => [
      if (p.minutes != null) 'Geplant: ${hm(p.minutes! * 60)}${(p.distanceM ?? 0) > 0 && p.sport != null ? ' · ${distTxt(p.sport!, p.distanceM!)}' : ''}',
      if (p.notes.trim().isNotEmpty) p.notes.trim(),
    ].join('\n');

String plannedTitle(PlannedSession p) {
  final prefix = switch (p.kind) {
    PlanKind.race => '🏁 ${p.racePrio != null ? '${p.racePrio}-Wettkampf: ' : ''}',
    PlanKind.workout => '${_icon[p.sport] ?? '📅'} ',
    PlanKind.event => '',
  };
  return '$prefix${p.displayTitle}';
}

String activityTitle(Activity a) => '✓ ${_icon[a.sport]} ${a.title}';

String buildIcs({String name = 'TriCoach', List<Activity> activities = const [], List<PlannedSession> planned = const [], DateTime? now}) {
  final stamp = icsUtc(now ?? DateTime.now());
  final l = <String>[
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//TriCoach//Training//DE',
    'CALSCALE:GREGORIAN',
    'METHOD:PUBLISH',
    'X-WR-CALNAME:${escapeIcs(name)}',
  ];
  for (final p in planned) {
    if (p.isDeleted) continue;
    final title = plannedTitle(p);
    l.addAll(['BEGIN:VEVENT', 'UID:plan-${p.id}@tricoach.app', 'DTSTAMP:$stamp']);
    if (p.allDay) {
      final d = p.startsAt.toLocal();
      l.add('DTSTART;VALUE=DATE:${_icsDate(d)}');
      l.add('DTEND;VALUE=DATE:${_icsDate(DateTime(d.year, d.month, d.day + 1))}');
    } else {
      l.add('DTSTART:${icsUtc(p.startsAt)}');
      l.add('DTEND:${icsUtc(p.startsAt.add(Duration(minutes: (p.minutes ?? 60).clamp(15, 100000))))}');
    }
    l.add('SUMMARY:${escapeIcs(title)}');
    final desc = plannedSummary(p);
    if (desc.isNotEmpty) l.add('DESCRIPTION:${escapeIcs(desc)}');
    if (p.kind == PlanKind.workout && !p.allDay) {
      l.addAll(['BEGIN:VALARM', 'ACTION:DISPLAY', 'DESCRIPTION:${escapeIcs(title)}', 'TRIGGER:-PT1H', 'END:VALARM']);
    }
    l.add('END:VEVENT');
  }
  for (final a in activities) {
    if (a.isDeleted) continue;
    l.addAll([
      'BEGIN:VEVENT',
      'UID:act-${a.id}@tricoach.app',
      'DTSTAMP:$stamp',
      'DTSTART:${icsUtc(a.start)}',
      'DTEND:${icsUtc(a.start.add(Duration(seconds: a.durationS < 60 ? 60 : a.durationS)))}',
      'SUMMARY:${escapeIcs(activityTitle(a))}',
      'DESCRIPTION:${escapeIcs(activitySummary(a))}',
      'END:VEVENT',
    ]);
  }
  l.add('END:VCALENDAR');
  return '${l.map(foldIcs).join('\r\n')}\r\n';
}
