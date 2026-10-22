import 'backup_import.dart' show importId;
import 'models.dart';
import 'sport.dart';

/// Trainingsplan der Trainerin aus TrainingPeaks (privater iCal-Link).
/// Gleiche Regeln wie importIcs(…, 'tp') in js/calendar.js – inklusive derselben IDs,
/// damit Einträge aus einer Web-App-Sicherung und aus dem Plan nicht doppelt auftauchen.

class IcsEvent {
  String? uid, summary, desc, location;
  DateTime? start, end;
  bool allDay = false;
  int? durMin;
}

/// Kalenderdatei in Termine zerlegen (Zeilen entfaltet, Erinnerungen übersprungen)
List<IcsEvent> parseIcsEvents(String text) {
  final lines = text.replaceAll(RegExp(r'\r?\n[ \t]'), '').split(RegExp(r'\r?\n'));
  String unesc(String s) => s.replaceAll(RegExp(r'\\n', caseSensitive: false), '\n').replaceAllMapped(RegExp(r'\\([,;\\])'), (m) => m[1]!);
  final out = <IcsEvent>[];
  IcsEvent? ev;
  var inAlarm = false;
  for (final line in lines) {
    if (line == 'BEGIN:VEVENT') {
      ev = IcsEvent();
      continue;
    }
    if (ev == null) continue;
    if (line == 'BEGIN:VALARM') {
      inAlarm = true;
      continue;
    }
    if (line == 'END:VALARM') {
      inAlarm = false;
      continue;
    }
    if (line == 'END:VEVENT') {
      if (ev.start != null) out.add(ev);
      ev = null;
      continue;
    }
    if (inAlarm) continue;
    final c = line.indexOf(':');
    if (c < 0) continue;
    final head = line.substring(0, c), val = line.substring(c + 1);
    final parts = head.split(';'), name = parts.first.toUpperCase(), params = parts.skip(1).join(';');
    switch (name) {
      case 'UID':
        ev.uid = val;
      case 'SUMMARY':
        ev.summary = unesc(val);
      case 'DESCRIPTION':
        ev.desc = unesc(val);
      case 'LOCATION':
        ev.location = unesc(val);
      case 'DTSTART':
        final d = parseIcsDate(val, params);
        if (d != null) {
          ev.start = d.$1;
          ev.allDay = d.$2;
        }
      case 'DTEND':
        ev.end = parseIcsDate(val, params)?.$1;
      case 'DURATION':
        final m = RegExp(r'P(?:(\d+)D)?T?(?:(\d+)H)?(?:(\d+)M)?').firstMatch(val);
        if (m != null) ev.durMin = (int.tryParse(m[1] ?? '') ?? 0) * 1440 + (int.tryParse(m[2] ?? '') ?? 0) * 60 + (int.tryParse(m[3] ?? '') ?? 0);
    }
  }
  return out;
}

/// „20261024T150000Z“ (UTC), „20261024T170000“ (Ortszeit) oder „20261024“ (ganztägig)
(DateTime, bool)? parseIcsDate(String v, String params) {
  if (RegExp(r'VALUE=DATE(?!-)').hasMatch(params) || RegExp(r'^\d{8}$').hasMatch(v)) {
    return (DateTime(int.parse(v.substring(0, 4)), int.parse(v.substring(4, 6)), int.parse(v.substring(6, 8))), true);
  }
  final m = RegExp(r'^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})?(Z)?').firstMatch(v);
  if (m == null) return null;
  final p = [for (var i = 1; i <= 5; i++) int.parse(m[i]!)];
  return (m[7] != null ? DateTime.utc(p[0], p[1], p[2], p[3], p[4]) : DateTime(p[0], p[1], p[2], p[3], p[4]), false);
}

Sport? guessSport(String t) {
  bool has(String re) => RegExp(re, caseSensitive: false).hasMatch(t);
  if (has(r'schwimm|swim|🏊|freiwasser|\bcss\b|kraul')) return Sport.swim;
  if (has(r'\brad\b|radfahr|bike|ride|cycl|🚴|zwift|\bftp\b|sweet ?spot')) return Sport.bike;
  if (has(r'lauf|run|🏃|jog|\btrab')) return Sport.run;
  if (has(r'athletik|kraft|stabi|core|strength|gym|mobility|🏋|yoga|zirkel')) return Sport.strength;
  return null;
}

/// Geplante Dauer aus dem TrainingPeaks-Text: „Planned Time: 1:30:00“, „1:15 h“, „90 min“, „2h“.
/// [strict]: nur „Planned Time“ (in der Beschreibung ist „15 min einlaufen“ nicht die Gesamtdauer)
int? tpMinutes(String t, {bool strict = false}) {
  var m = RegExp(r'(?:planned (?:time|duration)|geplante (?:zeit|dauer)|dauer|duration)\s*:?\s*(\d{1,2}):(\d{2})(?::\d{2})?', caseSensitive: false).firstMatch(t) ??
      RegExp(r'\b(\d{1,2}):(\d{2})(?::\d{2})?\s*h\b', caseSensitive: false).firstMatch(t);
  if (m != null) return int.parse(m[1]!) * 60 + int.parse(m[2]!);
  if (strict) return null;
  m = RegExp(r"\b(\d{2,3})\s*(?:min|minuten|')(?![a-z])", caseSensitive: false).firstMatch(t);
  if (m != null) return int.parse(m[1]!);
  m = RegExp(r'\b(\d(?:[.,]\d+)?)\s*(?:h|std|stunden?)\b', caseSensitive: false).firstMatch(t);
  if (m != null) return (double.parse(m[1]!.replaceAll(',', '.')) * 60).round();
  return null;
}

/// ID wie in der Web-App („tp-…“), dann wie beim Sicherungs-Import in eine feste UUID umgerechnet
String tpPlanId(IcsEvent ev) {
  final raw = (ev.uid ?? '${ev.summary ?? ''}${ev.start!.millisecondsSinceEpoch}').replaceAll(RegExp(r'[^\w-]'), '');
  return importId('plan', 'tp-${raw.length > 60 ? raw.substring(0, 60) : raw}');
}

/// Termine aus dem TrainingPeaks-Kalender → geplante Einheiten / Wettkämpfe
List<PlannedSession> tpPlanFromIcs(String ics) {
  final out = <PlannedSession>[];
  for (final ev in parseIcsEvents(ics)) {
    final summary = ev.summary ?? '', desc = ev.desc ?? '';
    final sport = guessSport('$summary $desc');
    final race = RegExp(r'wettkampf|race|rennen|triathlon|marathon|🏁|ironman|70\.3', caseSensitive: false).hasMatch(summary) &&
        !RegExp(r'training|einheit', caseSensitive: false).hasMatch(summary);
    final kind = race ? PlanKind.race : PlanKind.workout;
    int? minutes;
    if (!ev.allDay) {
      if (ev.end != null) {
        minutes = ev.end!.difference(ev.start!).inMinutes;
        if (minutes < 5) minutes = 5;
      } else {
        minutes = ev.durMin ?? 60;
      }
      if (kind == PlanKind.workout) minutes = tpMinutes(summary) ?? tpMinutes(desc, strict: true) ?? minutes;
    }
    final title = summary.replaceFirst(RegExp(r'^[^\p{L}\p{N}]+', unicode: true), '').trim();
    out.add(PlannedSession(
      id: tpPlanId(ev),
      kind: kind,
      sport: race ? null : (sport ?? Sport.other),
      title: title.isEmpty ? 'Training' : title,
      startsAt: ev.start!.toUtc(),
      minutes: minutes,
      allDay: ev.allDay,
      notes: desc.trim(),
      racePrio: race ? 'A' : null,
    ));
  }
  return out;
}

/// Hat sich ein Eintrag aus TrainingPeaks inhaltlich geändert? (dann übernehmen, sonst nicht anfassen)
bool tpChanged(PlannedSession old, PlannedSession neu) =>
    old.title != neu.title ||
    !old.startsAt.isAtSameMomentAs(neu.startsAt) ||
    old.minutes != neu.minutes ||
    old.notes != neu.notes ||
    old.allDay != neu.allDay ||
    old.sport != neu.sport;
