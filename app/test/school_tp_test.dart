import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tricoach/core/backup_import.dart';
import 'package:tricoach/data/health_import.dart';
import 'package:tricoach/core/models.dart';
import 'package:tricoach/core/school.dart';
import 'package:tricoach/core/sport.dart';
import 'package:tricoach/core/tc_crypto.dart';
import 'package:tricoach/core/tp_plan.dart';
import 'package:tricoach/core/zip.dart';
import 'package:tricoach/data/local_store.dart';
import 'package:tricoach/data/repository.dart';
import 'package:tricoach/state/app_state.dart';
import 'package:tricoach/ui/school_card.dart';
import 'package:tricoach/ui/theme.dart';

/// Mit tools/untis-sync.mjs (encrypt) und dem Test-Schlüssel erzeugt – genau das Format, das der GitHub-Job
/// „Schule (WebUntis)“ in den Branch schule-daten legt. Kein echter Schlüssel, keine echten Schuldaten.
const testKey = 'test-schluessel-123';
const nodeFixture =
    r'{"v":1,"salt":"cWV/nSCSywe2g5q7rlaXCg==","iv":"Iq3AUoTfrxBykgqb","ct":"cz5sLCGCa62rA+u5TdaOyLPgUik6YLFpXtMhpD/1LRaoaSwCN+ytOD7+HxtLFPPzLjiORATrCHpyRODkt1QB2CEzh4kvYIjVGvhaGrMgKK4pT8GX0opOSa4+nlPXo51Ph03taYto+VlVi+lPs8AZ1VLG3P77YDnc9mFlQGKjUEgk5SpNDFOcqGWE2FYu2LrpvLoxJq61x3BDDfCqSVOK/cr5ivmIcXrD1H8lKHVFsLuJkZPmlHWPg2TU2x56GxTayCewT0+AIkQeh2Rx5wFiyKWpxPbJ3X8ihmBVN+PIv6ODKIs7gZUUE3TD3YDzfonIOtrWIt1X8R0CK4MSaqDiZQQP3f7R4o5POXAcONCRlGXWZdkYor4PLXdNKVkEMuqwq8mIK837e5w6NdDPY3M5bLbfV/RjgHSHdNcaaa11/rD1r9moIrHOc2Lk9r7o3p4483aZN8E9xx76RUnCEF9L7criSWhXrwJaFtNomQ8bao43MIQovvmRdDiG4DgtMhysFO2v7aqEFqsfoFLo/OfaqrPvYqDDc704CehZvdNx+6uz64c0I9h5FWBYhL5eAgHdZ9WZ508RbsYF/B4BsEKgKTa5deTXtxfKRvZtVGjiAMiYb9qjFfzqqcWUWVq+XKACckW0zjg02uIsKa65TCHgWf6J5Eur/lX1kllaLUQhcbKHf7zCKh0IKRAn2uOmRcN4IKRc5Zv8NKwohtG1lmmRDIH7B3f9gZuvx0+mZEcqExzjz9QlbV7GLPsSZdlRVw3ghcNTAIeDHkB77b7MAI/4RKSAm9OqKpf6H2c4n8psn34tZpZDeNf7x4gQUegdjB0cpWGLuuESkOb9C2avUqpLdIM6wH7ftr7xYjvBZex02unE9qeLdvLCY6NzIgNSmlGiqaO1Lf2V8Ec39JWRGmb1bFyVwmj/BhQNqC4ztHviaufub0ht7s6ZSqKQwxcRstr+xpiwQqL8hAQWvVlomKry5aHU4cs8r4kHJLQtgGMerlH+QtM+knv987JyapoWHsBy5jq9//Hj0HWEPh1LOcWAHvOzNujPKVUvOObvbwi7cUKoGhjRamqw6m2UDHBYv07phEZgfAonYVbE91EoB6qFK6NT50cMw0fMjH2FuLb+xcpyRZiFyo/JrMpm8zxeswFQiJ6s7CbslatQ4Z02m++Zu2+HYhLPfKSZHUSSp/KqKni1SN6K3qHulgGF1mJrjurFzUvTO8efxrTPkuL3/DK/ENi06nm5FtWxilPEONtA//b5PndTrOr3NFU0PF5W1xMWjQ8buJE35rzxdrui/jzmEEARxgBokvWiZOqt7Atr/8xwUgiJkpA7m0W8yjib9i6w3TQY8r69VdS5om4ss1XUKMeI9dcsAARGCJLDy3BaDc9GA1TFrPO4H5spehECHuHsawQJgrMi+VgBv+89pg0s4IhCcZFXTS0hDMQ9l+cFFw6hr2deztJ09ZX25ubHVUjPiLAHQJBmnYa5Dhv5S9JAo6e1EyrigLZUiwGLwvxaNHEBvOOD904LJuSySsWob7Sb0AjNx58axLpMBBJ41s/sz+zWE0xDMDxuXA4RjYo5iLkKeThSvKKVhUGNe79ZeZW1mgA8EaAytKAzqQ=="}';

String tpIcs({bool moved = false, bool withBike = true}) => [
      'BEGIN:VCALENDAR',
      'VERSION:2.0',
      'BEGIN:VEVENT',
      'UID:tp-1001@trainingpeaks.com',
      moved ? 'DTSTART:20261024T160000Z' : 'DTSTART:20261024T150000Z',
      moved ? 'DTEND:20261024T170000Z' : 'DTEND:20261024T160000Z',
      'SUMMARY:Run: Schwelle 5x1 km',
      r'DESCRIPTION:Planned Time: 1:15:00\n15 min einlaufen\, 90 s Trabpause',
      'BEGIN:VALARM',
      'TRIGGER:-PT1H',
      'END:VALARM',
      'END:VEVENT',
      if (withBike) ...[
        'BEGIN:VEVENT',
        'UID:tp-1002@trainingpeaks.com',
        'DTSTART;VALUE=DATE:20261026',
        'SUMMARY:Bike: Sweet Spot 3x12',
        'DESCRIPTION:Planned Time: 1:30:00',
        'END:VEVENT',
      ],
      'BEGIN:VEVENT',
      'UID:tp-1003@trainingpeaks.com',
      'DTSTART;VALUE=DATE:20261030',
      'SUMMARY:🏁 Stadttriathlon Sprint',
      'END:VEVENT',
      'END:VCALENDAR',
    ].join('\r\n');

void main() {
  group('Verschlüsselung (gleich wie GitHub-Job und Web-App)', () {
    test('liest die Datei aus tools/untis-sync.mjs', () async {
      final d = await TcCrypto.decrypt(nodeFixture, testKey) as Map;
      expect(d['at'], '2026-10-22T14:33:54.432Z');
      expect((d['lessons'] as List).length, 4);
      expect(((d['homework'] as List).first as Map)['text'], 'S. 112 Nr. 4a–d');
    });

    test('falscher Schlüssel ergibt eine klare Meldung', () async {
      await expectLater(TcCrypto.decrypt(nodeFixture, 'falsch'), throwsA(isA<TcKeyError>()));
    });

    test('festes Salz wie im Node-Werkzeug, Hin und zurück', () async {
      expect(base64.encode(await TcCrypto.fixedSalt()), 'cWV/nSCSywe2g5q7rlaXCg==');
      final enc = await TcCrypto.encrypt({'a': 'Ä', 'n': 3}, testKey);
      expect(TcCrypto.saltOf(enc), 'cWV/nSCSywe2g5q7rlaXCg==');
      expect(await TcCrypto.decrypt(enc, testKey), {'a': 'Ä', 'n': 3});
    });
  });

  group('Schule', () {
    late SchoolData s;
    setUpAll(() async => s = SchoolData.fromJson(Map<String, dynamic>.from(await TcCrypto.decrypt(nodeFixture, testKey) as Map)));

    test('Doppelstunden werden zusammengefasst, Änderungen erkannt', () {
      final ls = s.lessonsOn(DateTime(2026, 10, 26));
      expect(ls.length, 3);
      expect((ls[0].start, ls[0].end), ('07:45', '09:15'));
      expect(s.subjectName(ls[0].su, ls[0].sul), 'Mathe'); // „MatL1“ → Mathe
      expect(ls[1].note, 'Vertretung · Raum R 110 → R 204 · BEC → MÜL');
      expect(ls[2].cancelled, isTrue);
      expect(ls[2].note, 'Entfall · Aufgaben im Moodle-Kurs');
      expect(s.changes(DateTime(2026, 10, 26), DateTime(2026, 10, 27)).length, 2);
      expect(s.schoolEnds(DateTime(2026, 10, 26)), DateTime(2026, 10, 26, 10, 20)); // Bio fällt aus
      expect(s.lessonsOn(DateTime(2026, 10, 25)), isEmpty);
    });

    test('Hausaufgaben: eigener Haken geht vor WebUntis', () {
      expect(s.openHomework({}).map((h) => h.id), ['7']);
      expect(s.openHomework({'u7': true}), isEmpty);
      expect(s.openHomework({'u8': false}).map((h) => h.id), ['7', '8']);
    });

    test('Prüfungen im Zeitraum', () {
      expect(s.examsAhead(DateTime(2026, 10, 22), 14).single.name, 'Klassenarbeit Mathe');
      expect(s.examsAhead(DateTime(2026, 10, 30), 14), isEmpty);
    });

    testWidgets('Karte zeigt Stunden, Entfall und Hausaufgaben', (tester) async {
      final state = AppState(MemoryStore())..school = s;
      await tester.pumpWidget(AppScope(
        state: state,
        child: MaterialApp(
          theme: buildTheme(TriDesign.nacht),
          home: Scaffold(body: SingleChildScrollView(child: SchoolCard(day: DateTime(2026, 10, 26), title: 'Schule heute'))),
        ),
      ));
      expect(find.text('Schule heute'), findsOneWidget);
      expect(find.text('Mathe'), findsOneWidget);
      expect(find.text('Biologie'), findsOneWidget);
      expect(find.text('Entfall · Aufgaben im Moodle-Kurs'), findsOneWidget);
      expect(find.text('Mathe: S. 112 Nr. 4a–d'), findsOneWidget);
      expect(find.text('Englisch: Vokabeln Unit 3'), findsNothing); // in WebUntis schon erledigt
    });
  });

  group('TrainingPeaks-Plan', () {
    test('Termine werden zu Einheiten und Wettkämpfen (Regeln der Web-App)', () {
      final p = tpPlanFromIcs(tpIcs());
      expect(p.length, 3);
      expect(p[0].sport, Sport.run);
      expect(p[0].minutes, 75); // „Planned Time“, nicht die 60 min aus DTEND und nicht „15 min einlaufen“
      expect(p[0].title, 'Run: Schwelle 5x1 km');
      expect(p[0].notes, 'Planned Time: 1:15:00\n15 min einlaufen, 90 s Trabpause');
      expect(p[0].startsAt, DateTime.utc(2026, 10, 24, 15));
      expect(p[1].sport, Sport.bike);
      expect(p[1].allDay, isTrue);
      expect(p[1].minutes, isNull);
      expect(p[2].kind, PlanKind.race);
      expect(p[2].title, 'Stadttriathlon Sprint');
      // gleiche ID wie ein „tp-…“-Eintrag aus einer Sicherung der Web-App → keine Doppelten
      expect(p[0].id, importId('plan', 'tp-tp-1001trainingpeakscom'));
    });

    test('Dauer aus dem Text', () {
      expect(tpMinutes('Lauf 1:30 h'), 90);
      expect(tpMinutes('Rad 90 min'), 90);
      expect(tpMinutes('Schwimmen 1,5 h'), 90);
      expect(tpMinutes('15 min einlaufen', strict: true), isNull);
    });

    test('Abgleich: neu, unverändert, geändert, von der Trainerin gelöscht, selbst gelöscht', () async {
      final now = DateTime(2026, 10, 22);
      final repo = Repository(MemoryStore());
      await repo.load();

      final r1 = await repo.importTpPlan(tpPlanFromIcs(tpIcs()), {}, now: now);
      expect((r1.added, r1.changed, r1.removed), (3, 0, 0));
      expect(repo.planned.length, 3);

      final r2 = await repo.importTpPlan(tpPlanFromIcs(tpIcs()), r1.ids, now: now);
      expect((r2.added, r2.changed, r2.removed), (0, 0, 0));

      // Trainerin verschiebt den Lauf und streicht das Rad
      final r3 = await repo.importTpPlan(tpPlanFromIcs(tpIcs(moved: true, withBike: false)), r2.ids, now: now);
      expect((r3.added, r3.changed, r3.removed), (0, 1, 1));
      expect(repo.planned.length, 2);
      expect(repo.planned.first.startsAt, DateTime.utc(2026, 10, 24, 16));

      // Selbst gelöscht bleibt gelöscht
      final race = repo.planned.firstWhere((p) => p.kind == PlanKind.race);
      await repo.deletePlanned(race.id);
      final r4 = await repo.importTpPlan(tpPlanFromIcs(tpIcs(moved: true, withBike: false)), r3.ids, now: now);
      expect((r4.added, r4.changed, r4.removed), (0, 0, 0));
      expect(repo.planned.length, 1);
    });

    test('Erledigte Einheiten bleiben, auch wenn die Trainerin sie streicht', () async {
      final now = DateTime(2026, 10, 22);
      final repo = Repository(MemoryStore());
      await repo.load();
      final r1 = await repo.importTpPlan(tpPlanFromIcs(tpIcs()), {}, now: now);
      final bikeDay = repo.planned.firstWhere((p) => p.sport == Sport.bike).startsAt.toLocal();
      await repo.saveActivity(Activity(id: 'a1', sport: Sport.bike, start: DateTime(bikeDay.year, bikeDay.month, bikeDay.day, 16).toUtc(), durationS: 5400));
      final r2 = await repo.importTpPlan(tpPlanFromIcs(tpIcs(withBike: false)), r1.ids, now: now);
      expect(r2.removed, 0);
      expect(repo.planned.where((p) => p.sport == Sport.bike).length, 1);
    });
  });

  group('In TrainingPeaks nachtragen', () {
    test('ZIP: Prüfsumme und Aufbau', () {
      expect(crc32(utf8.encode('123456789')), 0xCBF43926);
      final z = makeZip([('Lauf.fit', [1, 2, 3]), ('Schwimmen-Ä.fit', List.filled(300, 7))], at: DateTime(2026, 10, 22, 16, 30));
      expect(z.sublist(0, 4), [0x50, 0x4b, 0x03, 0x04]);
      final end = z.sublist(z.length - 22);
      expect(end.sublist(0, 4), [0x50, 0x4b, 0x05, 0x06]);
      expect(end[10], 2); // zwei Dateien
      final cdSize = end[12] | end[13] << 8, cdOff = end[16] | end[17] << 8;
      expect(cdOff + cdSize, z.length - 22);
    });

    test('fehlend = eigene Einträge ohne Haken; Uhr nur ohne Garmin-Verbindung', () async {
      final state = AppState(MemoryStore());
      await state.repo.load();
      final now = DateTime.now();
      await state.repo.saveActivities([
        Activity(id: 'm1', sport: Sport.run, start: now.subtract(const Duration(days: 1)).toUtc(), durationS: 2700),
        Activity(id: 'w1', sport: Sport.bike, start: now.subtract(const Duration(days: 2)).toUtc(), durationS: 3600, source: 'health'),
      ]);
      expect(state.tpMissing(7).map((a) => a.id), ['m1']);
      state.garminTp = false;
      expect(state.tpMissing(7).map((a) => a.id).toSet(), {'m1', 'w1'});
      await state.markTp(state.tpMissing(7), 'fit');
      expect(state.tpMissing(7), isEmpty);
      expect(state.activities.firstWhere((a) => a.id == 'w1').details?['tp'], 'fit');
      final z = state.tpZip([state.activities.first]);
      expect(z.sublist(0, 4), [0x50, 0x4b, 0x03, 0x04]);
    });

    test('selbst nach Apple Health geschriebene Einheiten kommen nicht doppelt zurück', () {
      expect(HealthImport.isOwnSource('app.tricoach.tricoach', 'TriCoach'), isTrue);
      expect(HealthImport.isOwnSource('com.garmin.connect.mobile', 'Connect'), isFalse);
    });
  });
}
