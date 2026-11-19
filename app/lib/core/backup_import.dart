import 'dart:convert';

import 'package:uuid/uuid.dart';

import 'analytics.dart';
import 'models.dart';
import 'sport.dart';

/// Ergebnis des Imports einer Sicherung aus der bisherigen Web-App (TriCoach 2.x)
class BackupImport {
  BackupImport(this.activities, this.planned, this.profile, this.skipped);
  final List<Activity> activities;
  final List<PlannedSession> planned;
  final AthleteProfile? profile;

  /// Demo-Einheiten und kaputte Einträge, die nicht übernommen wurden
  final int skipped;
}

class BackupFormatException implements Exception {
  BackupFormatException(this.message);
  final String message;
  @override
  String toString() => message;
}

const _uuid = Uuid();

/// Feste ID für importierte Einträge: gleicher Eintrag → gleiche ID. So entstehen beim
/// zweiten Import oder auf einem zweiten Gerät keine Doppelten.
String importId(String kind, String originalId) => _uuid.v5(Namespace.url.value, 'tricoach-import:$kind:$originalId');

DateTime? _date(Object? v) {
  if (v == null) return null;
  if (v is num) return DateTime.fromMillisecondsSinceEpoch(v.toInt(), isUtc: true);
  return DateTime.tryParse(v.toString())?.toUtc();
}

double _num(Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;
int? _intOrNull(Object? v) => v is num ? v.round() : int.tryParse('${v ?? ''}');

/// Liest die Datei „TriCoach-Backup-JJJJ-MM-TT.json“ (Einstellungen → Daten sichern in der Web-App).
/// Übernimmt eigene Einheiten, Uhr-Einheiten (als Zusammenfassung), Korrekturen, Kalender und Profilwerte.
BackupImport parseWebBackup(String jsonText, {AthleteProfile? profileForTss}) {
  final Object? raw;
  try {
    raw = jsonDecode(jsonText);
  } catch (_) {
    throw BackupFormatException('Das ist keine TriCoach-Sicherung (keine gültige JSON-Datei).');
  }
  if (raw is! Map || raw['activities'] is! List || raw['plan'] is! List) {
    throw BackupFormatException('Das ist keine TriCoach-Sicherung (Einheiten oder Kalender fehlen).');
  }
  final edits = raw['edits'] is Map ? Map<String, dynamic>.from(raw['edits'] as Map) : <String, dynamic>{};

  AthleteProfile? profile;
  final settings = raw['settings'];
  if (settings is Map && settings['profile'] is Map) {
    final p = Map<String, dynamic>.from(settings['profile'] as Map);
    profile = AthleteProfile.fromJson({
      'weight': p['weight'],
      'ftp': p['ftp'],
      'lthr': p['lthr'],
      'rhr': p['rhr'],
      'maxHr': p['maxHr'],
      'thrPace': p['thrPace'],
      'css': p['css'],
    });
  }
  final tssProfile = profileForTss ?? profile ?? const AthleteProfile();

  var skipped = 0;
  final acts = <Activity>[];
  for (final item in raw['activities'] as List) {
    if (item is! Map) {
      skipped++;
      continue;
    }
    final a = Map<String, dynamic>.from(item);
    final src = '${a['source'] ?? ''}';
    if (src == 'demo' || src.isEmpty) {
      skipped++;
      continue;
    }
    final start = _date(a['start']);
    final origId = '${a['id'] ?? ''}';
    if (start == null || origId.isEmpty) {
      skipped++;
      continue;
    }
    // Korrekturen an Uhr-Einheiten (z. B. geschwommene km) übernehmen
    final e = edits[origId] is Map ? Map<String, dynamic>.from(edits[origId] as Map) : const <String, dynamic>{};
    final sport = Sport.parse(a['sport'] as String?);
    final source = switch (src) { 'manual' => 'manual', 'icu' => 'icu', 'fit' => 'fit', _ => 'import' };
    final bike = a['bike'] is Map ? Map<String, dynamic>.from(a['bike'] as Map) : null;
    final details = <String, dynamic>{
      if (bike?['np'] is num) 'np': (bike!['np'] as num).round(),
      if (bike?['ap'] is num) 'ap': (bike!['ap'] as num).round(),
      if (a['elev'] is num) 'elev': (a['elev'] as num).round(),
      'importedFrom': 'web-2.x',
    };
    final ex = (a['ex'] as List?)
            ?.whereType<Map>()
            .map((x) => Exercise.fromJson(Map<String, dynamic>.from(x)))
            .where((x) => x.name.isNotEmpty)
            .toList() ??
        const <Exercise>[];
    final act = Activity(
      id: importId('act', origId),
      sport: sport,
      art: (e['art'] ?? a['art'])?.toString(),
      name: '${e['name'] ?? a['name'] ?? ''}',
      start: start,
      durationS: _num(a['dur']).round(),
      distanceM: e['dist'] != null ? _num(e['dist']) : _num(a['dist']),
      rpe: _intOrNull(e['rpe'] ?? a['rpe']),
      avgHr: _intOrNull(a['avgHr']),
      maxHr: _intOrNull(a['maxHr']),
      kcal: _intOrNull(a['kcal']),
      notes: '${e['notes'] ?? a['notes'] ?? ''}',
      swimWhere: sport == Sport.swim ? SwimWhere.parse(e['where'] ?? a['where'] ?? (a['swim'] is Map ? ((a['swim'] as Map)['ow'] == true ? 'ow' : (a['swim'] as Map)['pool']) : null)) : null,
      exercises: ex,
      source: source,
      extId: '${a['extId'] ?? origId}',
      details: details,
      updatedAt: DateTime.now().toUtc(),
    );
    act.tss = trainingStress(act, tssProfile);
    acts.add(act);
  }

  final plan = <PlannedSession>[];
  for (final item in raw['plan'] as List) {
    if (item is! Map) continue;
    final p = Map<String, dynamic>.from(item);
    final date = _date(p['date']);
    final origId = '${p['id'] ?? ''}';
    if (date == null || origId.isEmpty) continue;
    final kindRaw = '${p['kind'] ?? 'workout'}';
    final kind = kindRaw == 'race' ? PlanKind.race : (kindRaw == 'workout' ? PlanKind.workout : PlanKind.event);
    plan.add(PlannedSession(
      id: importId('plan', origId),
      kind: kind,
      sport: p['sport'] == null ? null : Sport.parse(p['sport'] as String?),
      title: '${p['title'] ?? ''}',
      startsAt: date,
      minutes: _intOrNull(p['min']),
      distanceM: p['dist'] is num ? (p['dist'] as num).toDouble() : null,
      allDay: p['allDay'] == true,
      notes: '${p['notes'] ?? ''}',
    ));
  }
  return BackupImport(acts, plan, profile, skipped);
}
