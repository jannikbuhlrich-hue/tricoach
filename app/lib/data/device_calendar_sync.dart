import 'dart:convert';

import 'package:device_calendar/device_calendar.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Color;
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../core/ics.dart';
import '../core/models.dart';
import 'local_store.dart';

/// Trainings automatisch in den Kalender des Handys schreiben:
/// iPhone/iPad → Apple Kalender, Android → Google Kalender (bzw. der Kalender des Geräts).
/// Eigener Kalender „TriCoach“, damit nichts mit privaten Terminen vermischt wird.
/// Änderungen und Löschungen werden nachgezogen; Zuordnung TriCoach-ID → Termin-ID liegt lokal.
class DeviceCalendarSync {
  DeviceCalendarSync(this.store);

  final LocalStore store;
  final _plugin = DeviceCalendarPlugin();
  bool _tzReady = false;
  bool _running = false;
  bool _again = false;

  static bool get supported => !kIsWeb && (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.android);

  Future<bool> get enabled async => (await store.meta('devcal:on')) == true;

  Future<bool> enable() async {
    if (!supported) return false;
    var perm = await _plugin.hasPermissions();
    if (perm.isSuccess && perm.data != true) perm = await _plugin.requestPermissions();
    if (!(perm.isSuccess && perm.data == true)) return false;
    await store.setMeta('devcal:on', true);
    return true;
  }

  /// Ausschalten und den TriCoach-Kalender vom Gerät entfernen
  Future<void> disable() async {
    await store.setMeta('devcal:on', false);
    final id = await store.meta('devcal:calendar') as String?;
    if (id != null) await _plugin.deleteCalendar(id);
    await store.setMeta('devcal:calendar', null);
    await store.setMeta('devcal:map', null);
  }

  void _initTz() {
    if (_tzReady) return;
    tzdata.initializeTimeZones();
    // Zielgruppe zuerst Deutschland/Österreich/Schweiz; sonst UTC (Termine stimmen trotzdem, nur die Zone heißt anders)
    final name = DateTime.now().timeZoneName;
    try {
      tz.setLocalLocation(tz.getLocation(const {'CET': 'Europe/Berlin', 'CEST': 'Europe/Berlin', 'MEZ': 'Europe/Berlin', 'MESZ': 'Europe/Berlin'}[name] ?? 'Europe/Berlin'));
    } catch (_) {
      tz.setLocalLocation(tz.UTC);
    }
    _tzReady = true;
  }

  Future<String?> _calendarId() async {
    final saved = await store.meta('devcal:calendar') as String?;
    final cals = await _plugin.retrieveCalendars();
    final list = cals.data ?? const <Calendar>[];
    if (saved != null && list.any((c) => c.id == saved)) return saved;
    for (final c in list) {
      if (c.name == 'TriCoach' && c.isReadOnly != true) {
        await store.setMeta('devcal:calendar', c.id);
        return c.id;
      }
    }
    final created = await _plugin.createCalendar('TriCoach', calendarColor: const Color(0xFFF24566), localAccountName: 'TriCoach');
    if (!created.isSuccess || created.data == null) return null;
    await store.setMeta('devcal:calendar', created.data);
    await store.setMeta('devcal:map', null);
    return created.data;
  }

  /// Kalender auf den Stand der App bringen (geplant + erledigt, 30 Tage zurück bis 120 Tage voraus)
  Future<void> sync(List<Activity> activities, List<PlannedSession> planned) async {
    if (!supported || !await enabled) return;
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    try {
      do {
        _again = false;
        await _syncOnce(activities, planned);
      } while (_again);
    } finally {
      _running = false;
    }
  }

  Future<void> _syncOnce(List<Activity> activities, List<PlannedSession> planned) async {
    _initTz();
    final calId = await _calendarId();
    if (calId == null) return;
    final now = DateTime.now();
    final from = now.subtract(const Duration(days: 30)), to = now.add(const Duration(days: 120));

    // Gewünschter Stand: Schlüssel → (Fingerabdruck, Termin)
    final want = <String, (String, Event)>{};
    for (final p in planned) {
      if (p.isDeleted || p.startsAt.isBefore(from) || p.startsAt.isAfter(to)) continue;
      final start = tz.TZDateTime.from(p.startsAt, tz.local);
      final end = p.allDay ? start.add(const Duration(days: 1)) : start.add(Duration(minutes: (p.minutes ?? 60).clamp(15, 100000)));
      final e = Event(calId, title: plannedTitle(p), description: plannedSummary(p), start: start, end: end, allDay: p.allDay);
      if (p.kind == PlanKind.workout && !p.allDay) e.reminders = [Reminder(minutes: 60)];
      want['p:${p.id}'] = (p.updatedAt.toIso8601String(), e);
    }
    for (final a in activities) {
      if (a.isDeleted || a.start.isBefore(from) || a.start.isAfter(to)) continue;
      final start = tz.TZDateTime.from(a.start, tz.local);
      final e = Event(calId, title: activityTitle(a), description: activitySummary(a), start: start, end: start.add(Duration(seconds: a.durationS < 60 ? 60 : a.durationS)));
      want['a:${a.id}'] = (a.updatedAt.toIso8601String(), e);
    }

    final raw = await store.meta('devcal:map') as String?;
    final map = raw == null ? <String, dynamic>{} : Map<String, dynamic>.from(jsonDecode(raw) as Map);

    // Entfernen, was es nicht mehr gibt
    for (final key in map.keys.toList()) {
      if (want.containsKey(key)) continue;
      final evId = (map[key] as Map)['e'] as String?;
      if (evId != null) await _plugin.deleteEvent(calId, evId);
      map.remove(key);
    }
    // Neu anlegen oder ändern (nur wenn sich etwas geändert hat)
    for (final entry in want.entries) {
      final known = map[entry.key] as Map?;
      final (fp, ev) = entry.value;
      if (known != null && known['f'] == fp) continue;
      if (known != null) ev.eventId = known['e'] as String?;
      final res = await _plugin.createOrUpdateEvent(ev);
      final id = res?.data;
      if (res != null && res.isSuccess && id != null) map[entry.key] = {'e': id, 'f': fp};
    }
    await store.setMeta('devcal:map', jsonEncode(map));
  }
}
