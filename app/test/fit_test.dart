import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tricoach/core/fit.dart';
import 'package:tricoach/core/models.dart';
import 'package:tricoach/core/sport.dart';

import 'fit_fixtures.dart';

/// Die Testdateien stammen vom FIT-Schreiber der Web-App (mit dem Garmin FIT SDK geprüft).
/// Erwartete Werte = Ergebnis des Web-App-Lesers js/fit.js für dieselben Dateien.
void main() {
  test('Schwimmen 25-m-Bahn lesen', () {
    final a = activitiesFromFit(base64Decode(fitFixtures['swim25']!), 'swim25').single;
    expect(a.sport, Sport.swim);
    expect(a.start, DateTime.utc(2026, 10, 20, 15));
    expect(a.durationS, 3300);
    expect(a.distanceM, 2350);
    expect(a.avgHr, 142);
    expect(a.maxHr, 165);
    expect(a.swimWhere, SwimWhere.pool25);
    expect(a.id, 'fit-swim25');
    expect(a.source, 'fit');
  });

  test('Kitesurfen und Rad lesen', () {
    final k = activitiesFromFit(base64Decode(fitFixtures['kite']!), 'kite').single;
    expect(k.sport, Sport.other);
    expect(k.art, 'Kitesurfen');
    expect(k.title, 'Kitesurfen');
    expect(k.durationS, 7200);
    expect(k.avgHr, 128);
    final b = activitiesFromFit(base64Decode(fitFixtures['bike']!), 'bike').single;
    expect(b.sport, Sport.bike);
    expect(b.distanceM, 45000);
    expect(b.maxHr, 171);
  });

  test('Schreiben ergibt byte-genau dieselbe Datei wie die Web-App', () {
    final cases = {
      'swim25': Activity(id: 'x', sport: Sport.swim, swimWhere: SwimWhere.pool25, start: DateTime.utc(2026, 10, 20, 15), durationS: 3300, distanceM: 2350, avgHr: 142, maxHr: 165, kcal: 610),
      'kite': Activity(id: 'y', sport: Sport.other, art: 'Kitesurfen', start: DateTime.utc(2026, 10, 18, 12), durationS: 7200, avgHr: 128, kcal: 900),
      'bike': Activity(id: 'z', sport: Sport.bike, start: DateTime.utc(2026, 10, 16, 14), durationS: 5400, distanceM: 45000, avgHr: 138, maxHr: 171, kcal: 1200),
    };
    // Die Web-App schreibt den Ortszeit-Versatz in die Datei; die Testdateien entstanden in UTC
    final utc = DateTime.now().timeZoneOffset == Duration.zero;
    for (final e in cases.entries) {
      final mine = buildFit(e.value);
      expect(isFit(mine), isTrue);
      // Hin und zurück
      final back = activitiesFromFit(mine, e.key).single;
      expect(back.sport, e.value.sport);
      expect(back.durationS, e.value.durationS);
      expect(back.distanceM, e.value.distanceM);
      expect(back.avgHr, e.value.avgHr);
      if (utc) expect(base64Encode(mine), fitFixtures[e.key], reason: e.key);
    }
  });

  test('Prüfsumme und kaputte Dateien', () {
    final bytes = buildFit(Activity(id: 'r', sport: Sport.run, start: DateTime.utc(2026, 1, 1, 8), durationS: 1800, distanceM: 5000));
    expect(fitCrc(bytes), 0, reason: 'Datei-Prüfsumme über alles ergibt 0');
    expect(() => activitiesFromFit(bytes.sublist(0, 60), 'x'), throwsA(isA<FitException>()));
    expect(isFit(utf8.encode('keine fit datei')), isFalse);
    expect(fitFileName(Activity(id: 'n', sport: Sport.swim, name: 'CSS 10×100', start: DateTime(2026, 10, 20, 17), durationS: 60)), 'TriCoach_2026-10-20_1700_CSS-10-100.fit');
  });
}
