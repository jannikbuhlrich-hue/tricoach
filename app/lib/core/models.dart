import 'sport.dart';

DateTime? _date(Object? v) => v == null ? null : DateTime.parse(v.toString()).toUtc();
double _dbl(Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;
int? _int(Object? v) => v is num ? v.round() : int.tryParse('${v ?? ''}');
String _iso(DateTime d) => d.toUtc().toIso8601String();

/// Eine Übung bei Athletik: Name, Sätze, Wiederholungen/Zeit, Gewicht
class Exercise {
  const Exercise({required this.name, this.sets, this.reps = '', this.kg});
  final String name;
  final int? sets;
  final String reps;
  final double? kg;

  Map<String, dynamic> toJson() => {'n': name, if (sets != null) 's': sets, if (reps.isNotEmpty) 'r': reps, if (kg != null) 'w': kg};
  factory Exercise.fromJson(Map<String, dynamic> j) =>
      Exercise(name: '${j['n'] ?? ''}', sets: _int(j['s']), reps: '${j['r'] ?? ''}', kg: j['w'] == null ? null : _dbl(j['w']));

  @override
  String toString() => '$name${sets != null ? ' $sets×' : ''}$reps${kg != null ? ' @${kg!.toStringAsFixed(kg! % 1 == 0 ? 0 : 1)} kg' : ''}';
}

/// Eine absolvierte Einheit. Feldnamen in toRow() entsprechen der Supabase-Tabelle `activities`.
class Activity {
  Activity({
    required this.id,
    required this.sport,
    required this.start,
    required this.durationS,
    this.art,
    this.name = '',
    this.distanceM = 0,
    this.rpe,
    this.avgHr,
    this.maxHr,
    this.kcal,
    this.tss,
    this.notes = '',
    this.swimWhere,
    this.exercises = const [],
    this.source = 'manual',
    this.extId,
    this.details,
    DateTime? updatedAt,
    this.deletedAt,
  }) : updatedAt = updatedAt ?? DateTime.now().toUtc();

  final String id;
  final Sport sport;
  final String? art;
  final String name;
  final DateTime start;
  final int durationS;
  final double distanceM;
  final int? rpe;
  final int? avgHr;
  final int? maxHr;
  final int? kcal;
  double? tss;
  final String notes;
  final SwimWhere? swimWhere;
  final List<Exercise> exercises;

  /// manual | health | icu | fit | import
  final String source;
  final String? extId;
  final Map<String, dynamic>? details;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  bool get isManual => source == 'manual';
  bool get isDeleted => deletedAt != null;
  DateTime get end => start.add(Duration(seconds: durationS));

  /// Titel für die Anzeige: eigener Name, sonst Art (bei „Sonstiges“), sonst Standard
  String get title => name.trim().isNotEmpty ? name : (sport == Sport.other && (art ?? '').isNotEmpty ? art! : sport.defaultTitle);

  /// Normalisierte Leistung (Rad), falls von der Uhr bekannt
  double? get normalizedPower => details?['np'] is num ? (details!['np'] as num).toDouble() : null;

  Activity copyWith({
    Sport? sport,
    String? art,
    String? name,
    DateTime? start,
    int? durationS,
    double? distanceM,
    int? rpe,
    int? avgHr,
    int? kcal,
    String? notes,
    SwimWhere? swimWhere,
    List<Exercise>? exercises,
    DateTime? deletedAt,
    bool clearDeleted = false,
  }) =>
      Activity(
        id: id,
        sport: sport ?? this.sport,
        art: art ?? this.art,
        name: name ?? this.name,
        start: start ?? this.start,
        durationS: durationS ?? this.durationS,
        distanceM: distanceM ?? this.distanceM,
        rpe: rpe ?? this.rpe,
        avgHr: avgHr ?? this.avgHr,
        maxHr: maxHr,
        kcal: kcal ?? this.kcal,
        tss: tss,
        notes: notes ?? this.notes,
        swimWhere: swimWhere ?? this.swimWhere,
        exercises: exercises ?? this.exercises,
        source: source,
        extId: extId,
        details: details,
        updatedAt: DateTime.now().toUtc(),
        deletedAt: clearDeleted ? null : (deletedAt ?? this.deletedAt),
      );

  Map<String, dynamic> toRow() => {
        'id': id,
        'sport': sport.name,
        'art': art,
        'name': name,
        'start_at': _iso(start),
        'duration_s': durationS,
        'distance_m': distanceM,
        'rpe': rpe,
        'avg_hr': avgHr,
        'max_hr': maxHr,
        'kcal': kcal,
        'tss': tss,
        'notes': notes,
        'swim_where': swimWhere?.code,
        'exercises': exercises.isEmpty ? null : exercises.map((e) => e.toJson()).toList(),
        'source': source,
        'ext_id': extId,
        'details': details,
        'updated_at': _iso(updatedAt),
        'deleted_at': deletedAt == null ? null : _iso(deletedAt!),
      };

  factory Activity.fromRow(Map<String, dynamic> r) => Activity(
        id: '${r['id']}',
        sport: Sport.parse(r['sport'] as String?),
        art: r['art'] as String?,
        name: '${r['name'] ?? ''}',
        start: _date(r['start_at'])!,
        durationS: _int(r['duration_s']) ?? 0,
        distanceM: _dbl(r['distance_m']),
        rpe: _int(r['rpe']),
        avgHr: _int(r['avg_hr']),
        maxHr: _int(r['max_hr']),
        kcal: _int(r['kcal']),
        tss: r['tss'] == null ? null : _dbl(r['tss']),
        notes: '${r['notes'] ?? ''}',
        swimWhere: SwimWhere.parse(r['swim_where']),
        exercises: (r['exercises'] as List?)?.map((e) => Exercise.fromJson(Map<String, dynamic>.from(e as Map))).toList() ?? const [],
        source: '${r['source'] ?? 'manual'}',
        extId: r['ext_id'] as String?,
        details: r['details'] == null ? null : Map<String, dynamic>.from(r['details'] as Map),
        updatedAt: _date(r['updated_at']),
        deletedAt: _date(r['deleted_at']),
      );
}

/// Art eines Kalendereintrags
enum PlanKind { workout, event, race }

/// Geplante Einheit, Termin oder Wettkampf. Feldnamen in toRow() = Tabelle `planned_sessions`.
class PlannedSession {
  PlannedSession({
    required this.id,
    required this.startsAt,
    this.kind = PlanKind.workout,
    this.sport,
    this.title = '',
    this.minutes,
    this.distanceM,
    this.allDay = false,
    this.notes = '',
    this.racePrio,
    this.createdBy,
    DateTime? updatedAt,
    this.deletedAt,
  }) : updatedAt = updatedAt ?? DateTime.now().toUtc();

  final String id;
  final PlanKind kind;
  final Sport? sport;
  final String title;
  final DateTime startsAt;
  final int? minutes;
  final double? distanceM;
  final bool allDay;
  final String notes;
  final String? racePrio;

  /// Wer hat es angelegt (null = auf diesem Gerät, wird beim Abgleich auf den eigenen Account gesetzt)
  final String? createdBy;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  bool get isDeleted => deletedAt != null;
  String get displayTitle => title.trim().isNotEmpty ? title : (sport?.defaultTitle ?? 'Termin');

  PlannedSession copyWith({
    PlanKind? kind,
    Sport? sport,
    String? title,
    DateTime? startsAt,
    int? minutes,
    double? distanceM,
    bool? allDay,
    String? notes,
    DateTime? deletedAt,
  }) =>
      PlannedSession(
        id: id,
        kind: kind ?? this.kind,
        sport: sport ?? this.sport,
        title: title ?? this.title,
        startsAt: startsAt ?? this.startsAt,
        minutes: minutes ?? this.minutes,
        distanceM: distanceM ?? this.distanceM,
        allDay: allDay ?? this.allDay,
        notes: notes ?? this.notes,
        racePrio: racePrio,
        createdBy: createdBy,
        updatedAt: DateTime.now().toUtc(),
        deletedAt: deletedAt ?? this.deletedAt,
      );

  Map<String, dynamic> toRow() => {
        'id': id,
        'kind': kind.name,
        'sport': sport?.name,
        'title': title,
        'starts_at': _iso(startsAt),
        'minutes': minutes,
        'distance_m': distanceM,
        'all_day': allDay,
        'notes': notes,
        'race_prio': racePrio,
        'created_by': createdBy,
        'updated_at': _iso(updatedAt),
        'deleted_at': deletedAt == null ? null : _iso(deletedAt!),
      };

  factory PlannedSession.fromRow(Map<String, dynamic> r) => PlannedSession(
        id: '${r['id']}',
        kind: PlanKind.values.firstWhere((k) => k.name == r['kind'], orElse: () => PlanKind.workout),
        sport: r['sport'] == null ? null : Sport.parse(r['sport'] as String?),
        title: '${r['title'] ?? ''}',
        startsAt: _date(r['starts_at'])!,
        minutes: _int(r['minutes']),
        distanceM: r['distance_m'] == null ? null : _dbl(r['distance_m']),
        allDay: r['all_day'] == true,
        notes: '${r['notes'] ?? ''}',
        racePrio: r['race_prio'] as String?,
        createdBy: r['created_by'] as String?,
        updatedAt: _date(r['updated_at']),
        deletedAt: _date(r['deleted_at']),
      );
}

/// Leistungswerte für die Analysen (Standard wie in der Web-App)
class AthleteProfile {
  const AthleteProfile({
    this.weightKg = 68,
    this.ftp = 260,
    this.lthr = 172,
    this.rhr = 48,
    this.maxHr = 195,
    this.thresholdPaceS = 250,
    this.cssS = 95,
    this.weeklyHoursGoal = 8,
    this.yearKmGoal = 0,
  });

  final double weightKg;
  final double ftp;
  final double lthr;
  final double rhr;
  final double maxHr;

  /// Schwellen-Laufpace in Sekunden pro km
  final double thresholdPaceS;

  /// Critical Swim Speed in Sekunden pro 100 m
  final double cssS;
  final double weeklyHoursGoal;
  final double yearKmGoal;

  Map<String, dynamic> toJson() => {
        'weight': weightKg,
        'ftp': ftp,
        'lthr': lthr,
        'rhr': rhr,
        'maxHr': maxHr,
        'thrPace': thresholdPaceS,
        'css': cssS,
        'weeklyHours': weeklyHoursGoal,
        'yearKm': yearKmGoal,
      };

  factory AthleteProfile.fromJson(Map<String, dynamic>? j) {
    const d = AthleteProfile();
    if (j == null) return d;
    double v(String k, double def) => j[k] is num ? (j[k] as num).toDouble() : def;
    return AthleteProfile(
      weightKg: v('weight', d.weightKg),
      ftp: v('ftp', d.ftp),
      lthr: v('lthr', d.lthr),
      rhr: v('rhr', d.rhr),
      maxHr: v('maxHr', d.maxHr),
      thresholdPaceS: v('thrPace', d.thresholdPaceS),
      cssS: v('css', d.cssS),
      weeklyHoursGoal: v('weeklyHours', d.weeklyHoursGoal),
      yearKmGoal: v('yearKm', d.yearKmGoal),
    );
  }

  AthleteProfile copyWith({double? weightKg, double? ftp, double? lthr, double? rhr, double? thresholdPaceS, double? cssS, double? weeklyHoursGoal, double? yearKmGoal}) =>
      AthleteProfile(
        weightKg: weightKg ?? this.weightKg,
        ftp: ftp ?? this.ftp,
        lthr: lthr ?? this.lthr,
        rhr: rhr ?? this.rhr,
        maxHr: maxHr,
        thresholdPaceS: thresholdPaceS ?? this.thresholdPaceS,
        cssS: cssS ?? this.cssS,
        weeklyHoursGoal: weeklyHoursGoal ?? this.weeklyHoursGoal,
        yearKmGoal: yearKmGoal ?? this.yearKmGoal,
      );
}
