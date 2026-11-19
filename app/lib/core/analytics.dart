import 'dart:math' as math;

import 'format.dart';
import 'models.dart';
import 'sport.dart';

/// Gefühlte Anstrengung (RPE 1–10) → Intensitätsfaktor, wie in der Web-App
const rpeIf = [0.0, .5, .55, .6, .65, .7, .77, .84, .91, .98, 1.05];

double _clamp(double v, double a, double b) => math.min(b, math.max(a, v));

/// Training Stress Score – gleiche Reihenfolge der Regeln wie in der Web-App (analytics.js)
double trainingStress(Activity a, AthleteProfile p) {
  final h = a.durationS / 3600;
  if (h <= 0) return 0;
  final np = a.normalizedPower;
  if (a.sport == Sport.bike && np != null && np > 0) return h * math.pow(np / p.ftp, 2) * 100;
  if (a.sport == Sport.run && a.distanceM > 0) {
    final thrSpeed = 1000 / p.thresholdPaceS;
    return h * math.pow(a.distanceM / a.durationS / thrSpeed, 2) * 100;
  }
  if (a.sport == Sport.swim && a.distanceM > 0) {
    final cssSpeed = 100 / p.cssS;
    return h * math.pow(math.min(1.6, a.distanceM / a.durationS / cssSpeed), 3) * 100;
  }
  if (a.rpe != null) {
    final i = rpeIf[a.rpe!.clamp(1, 10)];
    return h * i * i * 100;
  }
  if (a.avgHr != null) {
    final i = _clamp((a.avgHr! - p.rhr) / (p.lthr - p.rhr), .3, 1.2);
    return h * i * i * 100;
  }
  return h * (a.sport == Sport.strength ? 45 : 40);
}

/// Ein Tag der Form-Kurve (Performance Management Chart)
class LoadPoint {
  const LoadPoint(this.date, this.tss, this.ctl, this.atl, this.tsb);
  final DateTime date;
  final double tss;

  /// Fitness (42-Tage-Schnitt)
  final double ctl;

  /// Ermüdung (7-Tage-Schnitt)
  final double atl;

  /// Form = Fitness − Ermüdung (vom Vortag)
  final double tsb;
}

/// Form-Kurve berechnen. Startet beim ersten Training, liefert Punkte ab [from] bis [to].
List<LoadPoint> performanceChart(List<Activity> acts, DateTime from, DateTime to, AthleteProfile p) {
  final daily = <DateTime, double>{};
  DateTime? first;
  for (final a in acts) {
    if (a.isDeleted) continue;
    final d = startOfDay(a.start.toLocal());
    daily[d] = (daily[d] ?? 0) + (a.tss ?? trainingStress(a, p));
    if (first == null || d.isBefore(first)) first = d;
  }
  final start = first != null && first.isBefore(startOfDay(from)) ? first : startOfDay(from);
  var ctl = 0.0, atl = 0.0;
  final out = <LoadPoint>[];
  for (var d = start; !d.isAfter(startOfDay(to)); d = DateTime(d.year, d.month, d.day + 1)) {
    final t = daily[d] ?? 0;
    final tsb = ctl - atl;
    ctl += (t - ctl) / 42;
    atl += (t - atl) / 7;
    if (!d.isBefore(startOfDay(from))) out.add(LoadPoint(d, t, ctl, atl, tsb));
  }
  return out;
}

/// Summen für einen Zeitraum
class Totals {
  int count = 0;
  double distanceM = 0;
  double durationS = 0;
  double tss = 0;

  void add(Activity a) {
    count++;
    distanceM += a.distanceM;
    durationS += a.durationS;
    tss += a.tss ?? 0;
  }
}

Totals totals(Iterable<Activity> acts, DateTime from, DateTime to, {Sport? sport}) {
  final t = Totals();
  for (final a in acts) {
    if (a.isDeleted) continue;
    if (sport != null && a.sport != sport) continue;
    final s = a.start.toLocal();
    if (!s.isBefore(from) && s.isBefore(to)) t.add(a);
  }
  return t;
}

/// Wochen-Summen der letzten [weeks] Wochen (älteste zuerst)
List<({DateTime week, Map<Sport, Totals> bySport, Totals all})> weeklyTotals(List<Activity> acts, DateTime today, int weeks) {
  final ws = weekStart(today);
  return [
    for (var b = weeks - 1; b >= 0; b--)
      () {
        final s = ws.subtract(Duration(days: 7 * b)), e = s.add(const Duration(days: 7));
        return (
          week: s,
          bySport: {for (final sp in Sport.values) sp: totals(acts, s, e, sport: sp)},
          all: totals(acts, s, e),
        );
      }()
  ];
}

/// Wie viele Wochen am Stück (bis einschließlich dieser Woche, wenn schon trainiert) mit mindestens einer Einheit
int weekStreak(List<Activity> acts, DateTime today) {
  final weeks = acts.where((a) => !a.isDeleted).map((a) => weekStart(a.start.toLocal())).toSet();
  var w = weekStart(today);
  if (!weeks.contains(w)) w = w.subtract(const Duration(days: 7));
  var n = 0;
  while (weeks.contains(w)) {
    n++;
    w = w.subtract(const Duration(days: 7));
  }
  return n;
}

/// VDOT nach Daniels/Gilbert: Distanz in m, Zeit in s
double vdot(double meters, double seconds) {
  final t = seconds / 60, v = meters / t;
  return (-4.6 + .182258 * v + .000104 * v * v) / (.8 + .1894393 * math.exp(-.012778 * t) + .2989558 * math.exp(-.1932605 * t));
}

/// Zielzeit für [meters] bei gegebenem VDOT (Binärsuche wie in der Web-App)
double predictSeconds(double targetVdot, double meters) {
  var lo = meters / 8, hi = meters;
  for (var i = 0; i < 70; i++) {
    final m = (lo + hi) / 2;
    if (vdot(meters, m) > targetVdot) {
      lo = m;
    } else {
      hi = m;
    }
  }
  return (lo + hi) / 2;
}

/// VO2-Max-Schätzung aus den Läufen der letzten [days] Tage (beste Einheit ab 3 km und 12 min).
/// Ohne Sekunden-Messdaten ist das eine Untergrenze – lockere Läufe ziehen den Wert nicht hoch.
double? estimateVo2(List<Activity> acts, DateTime today, {int days = 60}) {
  final since = today.subtract(Duration(days: days));
  double best = 0;
  for (final a in acts) {
    if (a.isDeleted || a.sport != Sport.run || a.start.toLocal().isBefore(since)) continue;
    if (a.distanceM < 3000 || a.durationS < 720) continue;
    final v = vdot(a.distanceM, a.durationS.toDouble());
    if (v > 20 && v < 90) best = math.max(best, v);
  }
  return best > 0 ? best : null;
}

/// Bestleistungen (aus Zusammenfassungen): längste Einheit je Sportart, schnellster 5er/10er
class Bests {
  final Map<Sport, Activity> longest = {};
  Activity? fastest5k;
  double? fastest5kS;
  Activity? fastest10k;
  double? fastest10kS;
}

Bests bests(List<Activity> acts) {
  final b = Bests();
  for (final a in acts) {
    if (a.isDeleted) continue;
    if (a.sport.hasDistance && a.distanceM > 0) {
      final cur = b.longest[a.sport];
      if (cur == null || a.distanceM > cur.distanceM) b.longest[a.sport] = a;
    }
    if (a.sport == Sport.run && a.durationS > 0) {
      // Auf die Zieldistanz hochgerechnet – nur für Läufe, die mindestens so lang waren
      if (a.distanceM >= 5000 && a.distanceM < 8000) {
        final t = a.durationS * 5000 / a.distanceM;
        if (b.fastest5kS == null || t < b.fastest5kS!) {
          b.fastest5kS = t;
          b.fastest5k = a;
        }
      }
      if (a.distanceM >= 10000 && a.distanceM < 15000) {
        final t = a.durationS * 10000 / a.distanceM;
        if (b.fastest10kS == null || t < b.fastest10kS!) {
          b.fastest10kS = t;
          b.fastest10k = a;
        }
      }
    }
  }
  return b;
}

/// Doppelte Uhr-Einheiten (gleiche Sportart, Start < 3 min auseinander) zusammenführen.
/// Eigene Einträge bleiben immer. Von Doppelten gewinnt die mit mehr Daten (Puls, Leistung).
List<Activity> dedupe(Iterable<Activity> list) {
  int richness(Activity a) => (a.details?.length ?? 0) * 2 + (a.avgHr != null ? 3 : 0) + (a.distanceM > 0 ? 1 : 0) + (a.source == 'health' ? 1 : 0);
  final sorted = list.where((a) => !a.isDeleted).toList()..sort((x, y) => richness(y).compareTo(richness(x)));
  final out = <Activity>[];
  for (final a in sorted) {
    final dup = !a.isManual &&
        out.any((b) => !b.isManual && b.sport == a.sport && b.start.difference(a.start).inSeconds.abs() < 180);
    if (!dup) out.add(a);
  }
  out.sort((a, b) => b.start.compareTo(a.start));
  return out;
}

/// Kalorien schätzen, wenn keine eingetragen sind (Formel aus der Web-App)
int estimateKcal(Sport s, int durationS, int? rpe, double weightKg) {
  const met = {Sport.swim: 8.0, Sport.bike: 7.5, Sport.run: 10.0, Sport.strength: 5.0, Sport.other: 6.0};
  return (met[s]! * (.55 + (rpe ?? 5) * .09) * weightKg * durationS / 3600).round();
}

/// Ampel für die Form: frisch, ausgeglichen, belastet, überlastet
({String label, String hint, int level}) formState(double tsb) {
  if (tsb > 10) return (label: 'Frisch', hint: 'Guter Tag für einen Test oder Wettkampf.', level: 0);
  if (tsb > -10) return (label: 'Ausgeglichen', hint: 'Normales Training passt.', level: 1);
  if (tsb > -30) return (label: 'Belastet', hint: 'Fitness wird aufgebaut. Auf Schlaf achten.', level: 2);
  return (label: 'Überlastet', hint: 'Hohe Ermüdung – Entlastung einplanen.', level: 3);
}
