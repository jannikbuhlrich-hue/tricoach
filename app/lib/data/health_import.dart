import 'package:flutter/foundation.dart';
import 'package:health/health.dart';

import '../core/models.dart';
import '../core/sport.dart';

/// Einheiten von der Uhr über Apple Health (iPhone/iPad) bzw. Health Connect (Android) holen.
/// Garmin, Apple Watch, Coros, Polar, Wahoo … schreiben ihre Einheiten dort hinein –
/// TriCoach muss dafür nicht jede Uhr einzeln unterstützen.
class HealthImport {
  final _health = Health();
  bool _configured = false;

  static bool get supported => !kIsWeb && (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.android);

  static const _types = [HealthDataType.WORKOUT, HealthDataType.HEART_RATE];

  Future<void> _configure() async {
    if (_configured) return;
    await _health.configure();
    _configured = true;
  }

  /// Health Connect ist auf manchen Android-Geräten nicht vorinstalliert
  Future<bool> healthConnectAvailable() async {
    if (defaultTargetPlatform != TargetPlatform.android) return true;
    await _configure();
    return _health.isHealthConnectAvailable();
  }

  Future<void> installHealthConnect() => _health.installHealthConnect();

  Future<bool> requestAccess() async {
    if (!supported) return false;
    await _configure();
    return _health.requestAuthorization(_types, permissions: const [HealthDataAccess.READ, HealthDataAccess.READ]);
  }

  /// Einheiten seit [from]. Feste IDs aus der Quell-ID → kein Doppel-Import, auch nicht von zwei Geräten.
  Future<List<Activity>> fetch(DateTime from, {DateTime? to}) async {
    if (!supported) return [];
    await _configure();
    final end = to ?? DateTime.now();
    final workouts = await _health.getHealthDataFromTypes(types: const [HealthDataType.WORKOUT], startTime: from, endTime: end);
    List<HealthDataPoint> hr = const [];
    try {
      hr = await _health.getHealthDataFromTypes(types: const [HealthDataType.HEART_RATE], startTime: from, endTime: end);
    } catch (_) {
      // Ohne Puls-Freigabe trotzdem Einheiten übernehmen
    }
    final out = <Activity>[];
    for (final p in _health.removeDuplicates(workouts)) {
      final v = p.value;
      if (v is! WorkoutHealthValue) continue;
      // Selbst geschriebene Einheiten (für TrainingPeaks) nicht als Uhr-Einheit zurückholen – sonst doppelt
      if (isOwnSource(p.sourceId, p.sourceName)) continue;
      final start = p.dateFrom, stop = p.dateTo;
      final dur = stop.difference(start).inSeconds;
      if (dur < 60) continue;
      final type = v.workoutActivityType.name;
      final sport = sportFor(type);
      final beats = [
        for (final h in hr)
          if (!h.dateFrom.isBefore(start) && !h.dateFrom.isAfter(stop) && h.value is NumericHealthValue)
            (h.value as NumericHealthValue).numericValue.toDouble()
      ];
      final avg = beats.isEmpty ? null : (beats.reduce((a, b) => a + b) / beats.length).round();
      final max = beats.isEmpty ? null : beats.reduce((a, b) => a > b ? a : b).round();
      final dist = (v.totalDistance ?? 0).toDouble();
      out.add(Activity(
        id: 'health-${p.uuid}',
        sport: sport,
        art: sport == Sport.other ? artFor(type) : null,
        name: '',
        start: start.toUtc(),
        durationS: dur,
        distanceM: dist,
        avgHr: avg,
        maxHr: max,
        kcal: v.totalEnergyBurned,
        swimWhere: sport == Sport.swim ? (type.contains('OPEN_WATER') ? SwimWhere.openWater : null) : null,
        source: 'health',
        extId: p.uuid,
        details: {'device': p.sourceName, 'type': type},
      ));
    }
    return out;
  }

  /// Stammt ein Eintrag aus TriCoach selbst? (Bundle-ID app.tricoach.…, Name „TriCoach“)
  static bool isOwnSource(String sourceId, String sourceName) =>
      sourceId.toLowerCase().startsWith('app.tricoach') || sourceName.trim().toLowerCase() == 'tricoach';

  /// Schreibrecht für Workouts holen (nur fürs Nachtragen in TrainingPeaks über Apple Health)
  Future<bool> requestWrite() async {
    if (!supported) return false;
    await _configure();
    return _health.requestAuthorization(const [HealthDataType.WORKOUT], permissions: const [HealthDataAccess.READ_WRITE]);
  }

  /// Eigene Einheit als Workout in Apple Health / Health Connect eintragen.
  /// TrainingPeaks übernimmt Health-Workouts der letzten 7 Tage automatisch.
  Future<bool> writeWorkout(Activity a, {int? kcal}) async {
    if (!supported) return false;
    await _configure();
    final start = a.start.toLocal(), end = start.add(Duration(seconds: a.durationS < 60 ? 60 : a.durationS));
    return _health.writeWorkoutData(
      activityType: workoutType(a.sport),
      start: start,
      end: end,
      totalEnergyBurned: a.kcal ?? kcal,
      totalDistance: a.distanceM > 0 ? a.distanceM.round() : null,
      title: a.name.isNotEmpty ? a.name : a.sport.label,
    );
  }

  static HealthWorkoutActivityType workoutType(Sport s) => switch (s) {
        Sport.swim => HealthWorkoutActivityType.SWIMMING,
        Sport.bike => HealthWorkoutActivityType.BIKING,
        Sport.run => HealthWorkoutActivityType.RUNNING,
        Sport.strength => defaultTargetPlatform == TargetPlatform.iOS ? HealthWorkoutActivityType.TRADITIONAL_STRENGTH_TRAINING : HealthWorkoutActivityType.STRENGTH_TRAINING,
        Sport.other => HealthWorkoutActivityType.OTHER,
      };

  /// Workout-Typ aus Apple Health / Health Connect → Sportart
  static Sport sportFor(String type) {
    final t = type.toUpperCase();
    if (t.contains('SWIM')) return Sport.swim;
    if (t.contains('BIK') || t.contains('CYCL')) return Sport.bike;
    if (t.contains('RUN')) return Sport.run;
    if (RegExp('STRENGTH|WEIGHT|FUNCTIONAL|CROSS_TRAINING|HIGH_INTENSITY|CORE|CALISTHENICS|PILATES').hasMatch(t)) return Sport.strength;
    return Sport.other;
  }

  static String? artFor(String type) {
    const m = {
      'KITESURFING': 'Kitesurfen', 'KITE_SURFING': 'Kitesurfen', 'SURFING': 'Surfen', 'SURFING_SPORTS': 'Surfen', 'WINDSURFING': 'Windsurfen',
      'PADDLE_SPORTS': 'SUP', 'STAND_UP_PADDLEBOARDING': 'SUP', 'HIKING': 'Wandern', 'WALKING': 'Spaziergang', 'ROWING': 'Rudern',
      'CLIMBING': 'Klettern', 'ROCK_CLIMBING': 'Klettern', 'YOGA': 'Yoga', 'CROSS_COUNTRY_SKIING': 'Ski', 'DOWNHILL_SKIING': 'Ski',
      'SOCCER': 'Fußball', 'TENNIS': 'Tennis', 'SKATING': 'Inlineskaten', 'SAILING': 'Segeln',
    };
    return m[type.toUpperCase()];
  }
}
