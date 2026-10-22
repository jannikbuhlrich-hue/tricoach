import 'package:flutter_test/flutter_test.dart';
import 'package:tricoach/core/analytics.dart';
import 'package:tricoach/core/format.dart';
import 'package:tricoach/core/models.dart';
import 'package:tricoach/core/sport.dart';

Activity act(Sport s, {int dur = 3600, double dist = 0, int? rpe, int? hr, DateTime? start, String source = 'manual', Map<String, dynamic>? details, String? id}) => Activity(
      id: id ?? '${s.name}-${start ?? 0}-$dur-$dist',
      sport: s,
      start: start ?? DateTime.utc(2026, 10, 20, 15),
      durationS: dur,
      distanceM: dist,
      rpe: rpe,
      avgHr: hr,
      source: source,
      details: details,
    );

void main() {
  const p = AthleteProfile(); // FTP 260, LTHR 172, RHR 48, Schwelle 4:10/km, CSS 1:35/100m

  group('TSS (wie Web-App)', () {
    test('Lauf genau im Schwellentempo: 1 h = 100', () {
      // 4:10/km eine Stunde lang = 14,4 km
      expect(trainingStress(act(Sport.run, dist: 14400), p), closeTo(100, .01));
    });
    test('Rad mit NP = FTP: 1 h = 100', () {
      expect(trainingStress(act(Sport.bike, details: {'np': 260}), p), closeTo(100, .01));
    });
    test('Schwimmen im CSS-Tempo: 1 h = 100, Deckel bei 1,6', () {
      final cssDist = 3600 / 95 * 100;
      expect(trainingStress(act(Sport.swim, dist: cssDist), p), closeTo(100, .5));
      expect(trainingStress(act(Sport.swim, dist: 50000), p), closeTo(100 * 1.6 * 1.6 * 1.6, .5));
    });
    test('RPE ohne Messdaten', () {
      expect(trainingStress(act(Sport.strength, rpe: 5), p), closeTo(70 * .7 * .7 * 100 / 70, .01));
      expect(trainingStress(act(Sport.other, rpe: 10), p), closeTo(1.05 * 1.05 * 100, .01));
    });
    test('Puls, wenn kein RPE', () {
      expect(trainingStress(act(Sport.other, hr: 172), p), closeTo(100, .01));
      expect(trainingStress(act(Sport.other, hr: 40), p), closeTo(9, .01)); // untere Grenze 0,3
    });
    test('Fallback ohne alles', () {
      expect(trainingStress(act(Sport.strength), p), 45);
      expect(trainingStress(act(Sport.other, dur: 1800), p), 20);
    });
  });

  group('Form-Kurve', () {
    test('konstante 100 TSS/Tag nähern Fitness 100 an, Form vom Vortag', () {
      final start = DateTime(2026, 1, 1);
      final acts = [
        for (var i = 0; i < 200; i++) act(Sport.run, dist: 14400, start: DateTime(2026, 1, 1 + i, 12).toUtc(), id: 'r$i')..tss = 100,
      ];
      final pts = performanceChart(acts, start, DateTime(2026, 7, 19), p);
      expect(pts.length, 200);
      expect(pts.first.tsb, 0);
      expect(pts.last.ctl, greaterThan(98));
      expect(pts.last.atl, closeTo(100, .01));
      expect(pts.last.tsb, lessThan(0));
    });
    test('Ruhetage senken Ermüdung schneller als Fitness', () {
      final acts = [for (var i = 0; i < 60; i++) act(Sport.bike, start: DateTime(2026, 3, 1 + i, 9).toUtc(), id: 'b$i')..tss = 80];
      final pts = performanceChart(acts, DateTime(2026, 3, 1), DateTime(2026, 5, 10), p);
      final peakDay = pts[59], after = pts.last;
      expect(after.atl, lessThan(peakDay.atl * .2));
      expect(after.ctl, greaterThan(peakDay.ctl * .6));
      expect(after.tsb, greaterThan(0));
    });
  });

  test('VDOT: 5 km in 20:00 ≈ 49,8 und Prognose zurück', () {
    final v = vdot(5000, 1200);
    expect(v, closeTo(49.8, .3));
    expect(predictSeconds(v, 5000), closeTo(1200, 1));
    expect(predictSeconds(v, 10000), inInclusiveRange(2450, 2550));
  });

  test('VO2-Schätzung nimmt den besten Lauf und ignoriert kurze', () {
    final today = DateTime(2026, 10, 22);
    final acts = [
      act(Sport.run, dist: 5000, dur: 1200, start: DateTime.utc(2026, 10, 10), id: 'a'),
      act(Sport.run, dist: 10000, dur: 3300, start: DateTime.utc(2026, 10, 12), id: 'b'),
      act(Sport.run, dist: 1000, dur: 180, start: DateTime.utc(2026, 10, 13), id: 'c'),
    ];
    expect(estimateVo2(acts, today), closeTo(vdot(5000, 1200), .01));
    expect(estimateVo2([], today), isNull);
  });

  test('Doppelte Uhr-Einheiten werden zusammengeführt, eigene Einträge bleiben', () {
    final t = DateTime.utc(2026, 10, 20, 7);
    final list = [
      act(Sport.run, dist: 10000, start: t, source: 'icu', id: 'icu-1'),
      act(Sport.run, dist: 10000, hr: 150, start: t.add(const Duration(seconds: 60)), source: 'health', id: 'health-1'),
      act(Sport.run, dist: 10000, start: t.add(const Duration(seconds: 30)), source: 'manual', id: 'm-1'),
      act(Sport.bike, start: t, source: 'icu', id: 'icu-2'),
    ];
    final d = dedupe(list);
    expect(d.map((a) => a.id).toSet(), {'health-1', 'm-1', 'icu-2'});
  });

  test('Gelöschte Einheiten zählen nirgends', () {
    final a = act(Sport.run, dist: 10000);
    final gone = a.copyWith(deletedAt: DateTime.now());
    expect(dedupe([gone]), isEmpty);
    expect(totals([gone], DateTime(2000), DateTime(2100)).count, 0);
  });

  test('Wochen-Serie', () {
    final today = DateTime(2026, 10, 22); // Donnerstag
    final acts = [
      act(Sport.run, start: DateTime(2026, 10, 20, 12).toUtc(), id: '1'),
      act(Sport.run, start: DateTime(2026, 10, 14, 12).toUtc(), id: '2'),
      act(Sport.run, start: DateTime(2026, 10, 6, 12).toUtc(), id: '3'),
      act(Sport.run, start: DateTime(2026, 9, 20, 12).toUtc(), id: '4'),
    ];
    expect(weekStreak(acts, today), 3);
  });

  test('Bestleistungen', () {
    final b = bests([
      act(Sport.run, dist: 5000, dur: 1260, id: 'x'),
      act(Sport.run, dist: 5200, dur: 1248, id: 'y'), // hochgerechnet 20:00
      act(Sport.swim, dist: 3800, dur: 4000, id: 'z'),
    ]);
    expect(b.fastest5kS, closeTo(1200, .01));
    expect(b.longest[Sport.swim]!.id, 'z');
  });

  group('Format', () {
    test('deutsche Zahlen', () {
      expect(de(2.346, 2), '2,35');
      expect(de(12345), '12.345');
      expect(de(-3.5, 1), '−3,5');
      expect(de(null), '–');
    });
    test('Dauer und Pace', () {
      expect(hm(3900), '1h 05m');
      expect(hm(2700), '45 min');
      expect(clock(3725), '1:02:05');
      expect(paceTxt(250), '4:10');
      expect(paceHint(Sport.run, 10000, 2500), 'Ø 4:10 /km');
      expect(paceHint(Sport.swim, 1000, 950), 'Ø 1:35 /100m');
      expect(paceHint(Sport.bike, 30000, 3600), 'Ø 30,0 km/h');
      expect(distTxt(Sport.swim, 2350), '2,35 km');
      expect(distTxt(Sport.swim, 2000), '2,0 km');
      expect(distTxt(Sport.bike, 42500), '43 km');
    });
    test('Dauer-Eingabe', () {
      expect(parseDurationMinutes('1:30'), 90);
      expect(parseDurationMinutes('90'), 90);
      expect(parseDurationMinutes('1h30'), 90);
      expect(parseDurationMinutes('2h'), 120);
      expect(parseDurationMinutes('45 min'), 45);
      expect(parseDurationMinutes('abc'), isNull);
    });
    test('Kalenderwoche', () {
      expect(isoWeek(DateTime(2026, 10, 22)), 43);
      expect(isoWeek(DateTime(2027, 1, 1)), 53);
      expect(isoWeek(DateTime(2026, 1, 1)), 1);
    });
  });

  test('Einheit überlebt den Weg zur Datenbank und zurück', () {
    final a = Activity(
      id: 'x1',
      sport: Sport.strength,
      start: DateTime.utc(2026, 10, 20, 17, 30),
      durationS: 2700,
      rpe: 7,
      notes: 'Beine',
      exercises: const [Exercise(name: 'Kniebeuge', sets: 3, reps: '10', kg: 40)],
    )..tss = 50;
    final b = Activity.fromRow(a.toRow());
    expect(b.toRow(), a.toRow());
    expect(b.exercises.first.toString(), 'Kniebeuge 3×10 @40 kg');
    final s = SwimWhere.parse('ow');
    expect(s, SwimWhere.openWater);
  });
}
