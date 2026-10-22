import 'dart:async';

import 'package:uuid/uuid.dart';

import '../core/analytics.dart';
import '../core/backup_import.dart';
import '../core/models.dart';
import 'local_store.dart';
import 'sync_engine.dart';

/// Datenzugriff für die App: liest/schreibt lokal, der SyncEngine gleicht im Hintergrund ab.
/// Kein Flutter-Import – dadurch komplett in reinen Dart-Tests prüfbar.
class Repository {
  Repository(this.store, {void Function()? onChanged, void Function(SyncStatus)? onStatus})
      : _onChanged = onChanged {
    sync = SyncEngine(store, onChanged: (_) => reload(), onStatus: onStatus);
  }

  final LocalStore store;
  late final SyncEngine sync;
  final void Function()? _onChanged;
  static const _uuid = Uuid();

  List<Activity> _all = [];
  List<Activity> activities = [];
  List<PlannedSession> planned = [];
  AthleteProfile profile = const AthleteProfile();

  static String newId() => _uuid.v4();

  Future<void> load() async {
    final p = await store.meta('profile');
    if (p is Map) profile = AthleteProfile.fromJson(Map<String, dynamic>.from(p));
    await reload();
  }

  Future<void> reload() async {
    _all = [for (final r in await store.all('activities')) Activity.fromRow(r)];
    for (final a in _all) {
      a.tss ??= trainingStress(a, profile);
    }
    activities = dedupe(_all);
    planned = [for (final r in await store.all('planned')) PlannedSession.fromRow(r)].where((p) => !p.isDeleted).toList()
      ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    _onChanged?.call();
  }

  /// Einheit speichern (neu oder geändert). TSS wird mit dem aktuellen Profil berechnet.
  Future<void> saveActivity(Activity a) async {
    a.tss = trainingStress(a, profile);
    await sync.saveLocal('activities', [a.toRow()]);
    await reload();
  }

  Future<void> saveActivities(List<Activity> list) async {
    if (list.isEmpty) return;
    for (final a in list) {
      a.tss ??= trainingStress(a, profile);
    }
    await sync.saveLocal('activities', [for (final a in list) a.toRow()]);
    await reload();
  }

  /// Löschen = als gelöscht markieren, damit die anderen Geräte es mitbekommen
  Future<void> deleteActivity(String id) async {
    final r = await store.get('activities', id);
    if (r == null) return;
    final a = Activity.fromRow(r).copyWith(deletedAt: DateTime.now().toUtc());
    await sync.saveLocal('activities', [a.toRow()]);
    await reload();
  }

  Future<void> savePlanned(PlannedSession p) async {
    await sync.saveLocal('planned', [p.toRow()]);
    await reload();
  }

  Future<void> deletePlanned(String id) async {
    final r = await store.get('planned', id);
    if (r == null) return;
    final p = PlannedSession.fromRow(r).copyWith(deletedAt: DateTime.now().toUtc());
    await sync.saveLocal('planned', [p.toRow()]);
    await reload();
  }

  Future<void> saveProfile(AthleteProfile p) async {
    profile = p;
    await store.setMeta('profile', p.toJson());
    // TSS mit den neuen Schwellenwerten neu berechnen (nur lokal für die Anzeige)
    for (final a in _all) {
      a.tss = trainingStress(a, p);
    }
    _onChanged?.call();
  }

  /// Sicherung aus der Web-App übernehmen. Schon vorhandene Einträge werden nicht doppelt angelegt.
  Future<({int activities, int planned, int skipped})> importWebBackup(String json, {bool takeProfile = true}) async {
    final b = parseWebBackup(json, profileForTss: profile);
    if (takeProfile && b.profile != null) await saveProfile(b.profile!.copyWith(weeklyHoursGoal: profile.weeklyHoursGoal, yearKmGoal: profile.yearKmGoal));
    final haveA = {for (final r in await store.all('activities')) '${r['id']}'};
    final haveP = {for (final r in await store.all('planned')) '${r['id']}'};
    final newA = b.activities.where((a) => !haveA.contains(a.id)).toList();
    final newP = b.planned.where((p) => !haveP.contains(p.id)).toList();
    for (final a in newA) {
      a.tss = trainingStress(a, profile);
    }
    await sync.saveLocal('activities', [for (final a in newA) a.toRow()]);
    await sync.saveLocal('planned', [for (final p in newP) p.toRow()]);
    await reload();
    return (activities: newA.length, planned: newP.length, skipped: b.skipped + (b.activities.length - newA.length));
  }

  /// Einheiten eines Tages (lokale Zeit)
  List<Activity> activitiesOn(DateTime day) =>
      activities.where((a) {
        final s = a.start.toLocal();
        return s.year == day.year && s.month == day.month && s.day == day.day;
      }).toList()
        ..sort((a, b) => a.start.compareTo(b.start));

  List<PlannedSession> plannedOn(DateTime day) => planned.where((p) {
        final s = p.startsAt.toLocal();
        return s.year == day.year && s.month == day.month && s.day == day.day;
      }).toList();

  /// Ist eine geplante Einheit erledigt? (gleiche Sportart am selben Tag)
  Activity? doneFor(PlannedSession p) {
    if (p.kind != PlanKind.workout) return null;
    for (final a in activitiesOn(p.startsAt.toLocal())) {
      if (p.sport == null || a.sport == p.sport) return a;
    }
    return null;
  }

  /// Alles lokal löschen (z. B. beim Abmelden)
  Future<void> wipe() async {
    await sync.reset();
    await store.clear();
    profile = const AthleteProfile();
    await reload();
  }

  void dispose() => sync.dispose();
}
