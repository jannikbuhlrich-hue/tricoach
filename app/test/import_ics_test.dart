import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tricoach/core/backup_import.dart';
import 'package:tricoach/core/ics.dart';
import 'package:tricoach/core/models.dart';
import 'package:tricoach/core/sport.dart';
import 'package:tricoach/data/icu_source.dart';
import 'package:tricoach/data/local_store.dart';
import 'package:tricoach/data/repository.dart';

/// Ausschnitt einer echten Sicherung aus TriCoach 2.6 (Format von backup() in js/settings.js)
final webBackup = jsonEncode({
  'version': '2.6.2',
  'settings': {
    'profile': {'weight': 68, 'height': 182, 'ftp': 245, 'lthr': 170, 'rhr': 47, 'maxHr': 196, 'thrPace': 255, 'css': 98, 'bikeKg': 8.5},
    'design': 'nordsee',
  },
  'plan': [
    {'id': 'p1', 'kind': 'workout', 'date': '2026-10-24T15:00:00.000Z', 'sport': 'run', 'title': 'Schwelle 5×1 km', 'min': 60, 'notes': '90 s Trabpause', 'from': 'tp'},
    {'id': 'r1', 'kind': 'race', 'date': '2027-06-01T07:00:00.000Z', 'title': 'Stadttriathlon', 'allDay': true},
  ],
  'edits': {
    'icu-555': {'dist': 2400, 'notes': 'eigentlich 2,4 km'},
  },
  'activities': [
    {'id': 'man-abc', 'source': 'manual', 'sport': 'strength', 'name': 'Athletik', 'start': '2026-10-19T16:00:00.000Z', 'dur': 2700, 'dist': 0, 'rpe': 6, 'ex': [
      {'n': 'Kniebeuge', 's': 3, 'r': '10', 'w': 40},
      {'n': '', 's': 1},
    ]},
    {'id': 'man-kite', 'source': 'manual', 'sport': 'other', 'art': 'Kitesurfen', 'name': '', 'start': '2026-10-18T12:00:00.000Z', 'dur': 7200, 'dist': 0, 'rpe': 5},
    {'id': 'icu-555', 'extId': '555', 'source': 'icu', 'sport': 'swim', 'name': 'Schwimmen', 'start': '2026-10-17T16:00:00.000Z', 'dur': 3000, 'dist': 2000, 'avgHr': 140,
      'swim': {'pool': 25}, 'samples': [{'t': 0, 'hr': 120}], 'laps': []},
    {'id': 'icu-777', 'extId': '777', 'source': 'icu', 'sport': 'bike', 'name': 'Radfahrt', 'start': '2026-10-16T14:00:00.000Z', 'dur': 5400, 'dist': 45000,
      'bike': {'np': 220, 'ap': 200}},
    {'id': 'demo-1', 'source': 'demo', 'sport': 'run', 'start': '2026-10-15T10:00:00.000Z', 'dur': 1800, 'dist': 5000},
  ],
  'wellness': [],
});

void main() {
  group('Import der Web-App-Sicherung', () {
    test('liest Einheiten, Korrekturen, Kalender und Profil', () {
      final b = parseWebBackup(webBackup);
      expect(b.activities.length, 4);
      expect(b.skipped, 1, reason: 'Demo-Daten werden nicht übernommen');
      expect(b.planned.length, 2);
      expect(b.profile!.ftp, 245);
      expect(b.profile!.cssS, 98);

      final str = b.activities.firstWhere((a) => a.sport == Sport.strength);
      expect(str.exercises.length, 1, reason: 'leere Übung fällt weg');
      expect(str.exercises.single.kg, 40);
      expect(str.source, 'manual');

      final kite = b.activities.firstWhere((a) => a.sport == Sport.other);
      expect(kite.title, 'Kitesurfen');

      final swim = b.activities.firstWhere((a) => a.sport == Sport.swim);
      expect(swim.distanceM, 2400, reason: 'Korrektur aus edits');
      expect(swim.notes, 'eigentlich 2,4 km');
      expect(swim.swimWhere, SwimWhere.pool25);
      expect(swim.source, 'icu');

      final bike = b.activities.firstWhere((a) => a.sport == Sport.bike);
      expect(bike.normalizedPower, 220);
      // NP 220 bei FTP 245, 1,5 h → TSS ≈ 120,9
      expect(bike.tss, closeTo(1.5 * (220 / 245) * (220 / 245) * 100, .1));

      final race = b.planned.firstWhere((p) => p.kind == PlanKind.race);
      expect(race.allDay, isTrue);
      final w = b.planned.firstWhere((p) => p.kind == PlanKind.workout);
      expect(w.minutes, 60);
      expect(w.sport, Sport.run);
    });

    test('gleiche Sicherung zweimal = keine Doppelten (feste IDs)', () async {
      final repo = Repository(MemoryStore());
      await repo.load();
      final first = await repo.importWebBackup(webBackup);
      expect(first.activities, 4);
      expect(first.planned, 2);
      final second = await repo.importWebBackup(webBackup);
      expect(second.activities, 0);
      expect(second.planned, 0);
      expect(repo.activities.length, 4);
      expect(repo.profile.ftp, 245);
      expect(importId('act', 'man-abc'), importId('act', 'man-abc'));
      expect(importId('act', 'man-abc'), isNot(importId('plan', 'man-abc')));
    });

    test('kaputte Datei → verständliche Meldung', () {
      expect(() => parseWebBackup('kein json'), throwsA(isA<BackupFormatException>()));
      expect(() => parseWebBackup('{"foo":1}'), throwsA(isA<BackupFormatException>()));
    });
  });

  group('Kalender-Datei (.ics)', () {
    final now = DateTime.utc(2026, 10, 22, 10);
    final ics = buildIcs(
      now: now,
      activities: [
        Activity(id: 'a1', sport: Sport.swim, name: 'CSS 10×100', start: DateTime.utc(2026, 10, 20, 15), durationS: 3300, distanceM: 2350, avgHr: 142, rpe: 6, notes: 'Hauptserie, gut')..tss = 61.4,
        Activity(id: 'gone', sport: Sport.run, start: DateTime.utc(2026, 10, 18), durationS: 1800, deletedAt: DateTime.utc(2026, 10, 19)),
      ],
      planned: [
        PlannedSession(id: 'p1', sport: Sport.run, title: 'Schwelle 5×1 km', startsAt: DateTime.utc(2026, 10, 24, 15), minutes: 60),
        PlannedSession(id: 'r1', kind: PlanKind.race, title: 'Stadttriathlon', startsAt: DateTime(2027, 6, 1), allDay: true),
      ],
    );
    test('Aufbau und Inhalt', () {
      final lines = ics.split('\r\n');
      expect(lines.first, 'BEGIN:VCALENDAR');
      expect(ics.endsWith('END:VCALENDAR\r\n'), isTrue);
      expect(RegExp('BEGIN:VEVENT').allMatches(ics).length, 3);
      expect(ics, contains('DTSTART:20261020T150000Z'));
      expect(ics, contains('DTEND:20261020T155500Z'));
      expect(ics, contains(r'2\,35 km'));
      expect(ics, contains('DTSTART;VALUE=DATE:20270601'));
      expect(ics, contains('TRIGGER:-PT1H'));
      expect(ics, isNot(contains('UID:act-gone')));
    });
    test('keine Zeile länger als 75 Byte, Faltung umkehrbar', () {
      for (final l in ics.split('\r\n')) {
        expect(utf8.encode(l).length, lessThanOrEqualTo(75));
      }
      final long = 'SUMMARY:${'Schwimmen 🏊 Ähre ' * 10}';
      expect(foldIcs(long).split('\r\n ').join(), long);
      expect(escapeIcs('a,b;c\\d\ne'), r'a\,b\;c\\d\ne');
    });
  });

  test('intervals.icu-Einheit übernehmen', () {
    final a = IcuSource.fromIcu({
      'id': 'i123',
      'type': 'Kitesurf',
      'name': 'Kugelbake',
      'start_date_local': '2026-10-18T12:00:00',
      'moving_time': 5400,
      'distance': 30000,
      'average_heartrate': 128.4,
      'description': 'Gute Böen\n(per Siri über TriCoach)',
      'icu_rpe': 6,
    })!;
    expect(a.id, 'icu-i123');
    expect(a.sport, Sport.other);
    expect(a.art, 'Kitesurfen');
    expect(a.avgHr, 128);
    expect(a.notes, 'Gute Böen');
    expect(a.rpe, 6);
    final swim = IcuSource.fromIcu({'id': 9, 'type': 'OpenWaterSwim', 'start_date_local': '2026-07-01T08:00:00', 'moving_time': 1800, 'distance': 1500})!;
    expect(swim.sport, Sport.swim);
    expect(swim.swimWhere, SwimWhere.openWater);
    final ride = IcuSource.fromIcu({'id': 10, 'type': 'VirtualRide', 'start_date_local': '2026-07-01T08:00:00', 'moving_time': 3600, 'icu_weighted_avg_watts': 230})!;
    expect(ride.normalizedPower, 230);
    expect(IcuSource.fromIcu({'type': 'Run'}), isNull);
  });
}
