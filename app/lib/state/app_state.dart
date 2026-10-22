import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../core/analytics.dart' show estimateKcal;
import '../core/fit.dart';
import '../core/format.dart';
import '../core/models.dart';
import '../core/school.dart';
import '../core/tp_plan.dart';
import '../core/zip.dart';
import '../data/device_calendar_sync.dart';
import '../data/feeds_remote.dart';
import '../data/health_import.dart';
import '../data/icu_source.dart';
import '../data/local_store.dart';
import '../data/repository.dart';
import '../data/supabase_remote.dart';
import '../data/sync_engine.dart';
import '../ui/theme.dart';

/// Zentraler Zustand der App: Daten, Design, Anmeldung, Abgleich, Uhr- und Kalender-Anbindung.
class AppState extends ChangeNotifier with WidgetsBindingObserver {
  AppState(this.store) {
    repo = Repository(store, onChanged: _changed, onStatus: (s) {
      syncStatus = s;
      notifyListeners();
    });
    devCal = DeviceCalendarSync(store);
  }

  final LocalStore store;
  late final Repository repo;
  late final DeviceCalendarSync devCal;
  final health = HealthImport();

  TriDesign design = TriDesign.nacht;
  SyncStatus syncStatus = const SyncStatus();
  bool ready = false;
  bool onboarded = false;
  bool healthOn = false;
  bool calendarOn = false;
  String icuKey = '';
  DateTime? lastWatchImport;
  String? calendarToken;
  String? message;

  // Schule (WebUntis) und TrainingPeaks-Plan – über die Server-Funktion „feeds“, für jeden Nutzer
  /// Verbundene Dienste: 'webuntis' / 'trainingpeaks' → Anzeige-Name (z. B. „Gymnasium X · max.muster“)
  Map<String, String> links = {};
  SchoolData? school;
  String? schoolError;
  Map<String, bool> hwDone = {};
  DateTime? tpAt;
  String? tpError;
  bool feedsBusy = false;
  DateTime? _lastFeeds;

  /// Garmin Connect ist mit TrainingPeaks verbunden → Uhr-Einheiten kommen dort von selbst an
  bool garminTp = true;

  /// Hinweis „Stundenplan verbinden“ in Mein Tag weggeklickt
  bool untisHintOff = false;

  SupabaseRemote? _remote;
  RealtimeChannel? _channel;
  StreamSubscription<AuthState>? _authSub;
  Timer? _periodic;
  Timer? _calDebounce;

  User? get user => AppConfig.hasBackend ? Supabase.instance.client.auth.currentUser : null;
  bool get signedIn => user != null;
  bool get localOnly => !AppConfig.hasBackend;
  SupabaseRemote? get remote => _remote;

  List<Activity> get activities => repo.activities;
  List<PlannedSession> get planned => repo.planned;
  AthleteProfile get profile => repo.profile;

  Future<void> init() async {
    design = TriDesign.parse(await store.meta('design'));
    onboarded = (await store.meta('onboarded')) == true;
    healthOn = (await store.meta('health:on')) == true;
    icuKey = (await store.meta('icu:key') as String?) ?? '';
    final li = await store.meta('watch:last') as String?;
    lastWatchImport = li == null ? null : DateTime.tryParse(li);
    calendarOn = await devCal.enabled;
    await _loadFeeds();
    await repo.load();
    if (AppConfig.hasBackend) {
      _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((s) {
        if (s.event == AuthChangeEvent.signedIn || s.event == AuthChangeEvent.initialSession || s.event == AuthChangeEvent.tokenRefreshed) {
          _attach();
        } else if (s.event == AuthChangeEvent.signedOut) {
          _detach();
        }
        notifyListeners();
      });
      _attach();
    }
    WidgetsBinding.instance.addObserver(this);
    _periodic = Timer.periodic(const Duration(minutes: 5), (_) => refresh());
    ready = true;
    notifyListeners();
    unawaited(refresh());
  }

  void _changed() {
    notifyListeners();
    _calDebounce?.cancel();
    _calDebounce = Timer(const Duration(seconds: 2), () => devCal.sync(repo.activities, repo.planned).catchError((_) {}));
  }

  Future<void> _attach() async {
    final u = user;
    if (u == null || _remote?.userId == u.id) return;
    final r = SupabaseRemote(Supabase.instance.client, u.id);
    _remote = r;
    // Einträge aus der Zeit ohne Account (oder von vor dem Anmelden) einmal hochladen
    final owner = await store.meta('owner');
    if (owner != u.id) {
      await repo.sync.markAllPending();
      await store.setMeta('owner', u.id);
    }
    repo.sync.remote = r;
    await _channel?.unsubscribe();
    _channel = r.listen(() => repo.sync.schedule());
    unawaited(_loadLinks());
    try {
      final p = await r.loadProfile();
      if (p != null) {
        calendarToken = p['calendar_token']?.toString();
        final s = p['settings'];
        if (s is Map && s.isNotEmpty) {
          await repo.saveProfile(AthleteProfile.fromJson(Map<String, dynamic>.from(s)));
        } else {
          await r.saveProfileSettings(repo.profile.toJson());
        }
      }
    } catch (_) {
      // Profil kommt beim nächsten Abgleich
    }
    notifyListeners();
  }

  Future<void> _detach() async {
    await _channel?.unsubscribe();
    _channel = null;
    _remote = null;
    calendarToken = null;
    repo.sync.remote = null;
  }

  /// Abmelden. Daten auf diesem Gerät werden gelöscht (sie liegen ja im Account).
  Future<void> signOut() async {
    await _detach();
    await Supabase.instance.client.auth.signOut();
    await repo.wipe();
    _resetFeeds();
    await devCal.disable();
    calendarOn = false;
    notifyListeners();
  }

  /// Account und alle Daten endgültig löschen (Server und dieses Gerät)
  Future<void> deleteAccount() async {
    final r = _remote;
    if (r == null) return;
    await r.deleteAccount();
    await _detach();
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {}
    await repo.wipe();
    _resetFeeds();
    await devCal.disable();
    calendarOn = false;
    healthOn = false;
    onboarded = false;
    await store.setMeta('onboarded', null);
    notifyListeners();
  }

  /// Alles abgleichen: Server, Uhr, Kalender
  Future<void> refresh() async {
    repo.sync.schedule();
    await importWatch(quiet: true);
    await syncFeeds();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(refresh());
  }

  void say(String text) {
    message = text;
    notifyListeners();
  }

  // ---------------- Design & Profil ----------------
  Future<void> setDesign(TriDesign d) async {
    design = d;
    await store.setMeta('design', d.name);
    notifyListeners();
  }

  Future<void> finishOnboarding() async {
    onboarded = true;
    await store.setMeta('onboarded', true);
    notifyListeners();
  }

  Future<void> saveProfile(AthleteProfile p) async {
    await repo.saveProfile(p);
    try {
      await _remote?.saveProfileSettings(p.toJson());
    } catch (_) {}
  }

  // ---------------- Uhr ----------------
  Future<bool> enableHealth() async {
    if (!HealthImport.supported) return false;
    if (!await health.healthConnectAvailable()) {
      say('Health Connect fehlt auf diesem Handy – bitte aus dem Play Store installieren.');
      await health.installHealthConnect();
      return false;
    }
    final ok = await health.requestAccess();
    healthOn = ok;
    await store.setMeta('health:on', ok);
    try {
      if (ok) await _remote?.saveHealthConsent();
    } catch (_) {}
    notifyListeners();
    if (ok) await importWatch();
    return ok;
  }

  Future<void> disableHealth() async {
    healthOn = false;
    await store.setMeta('health:on', false);
    notifyListeners();
  }

  Future<String> setIcuKey(String key) async {
    final k = key.trim();
    if (k.isEmpty) {
      icuKey = '';
      await store.setMeta('icu:key', null);
      notifyListeners();
      return 'intervals.icu getrennt';
    }
    final name = await IcuSource(k).test();
    icuKey = k;
    await store.setMeta('icu:key', k);
    notifyListeners();
    await importWatch();
    return 'Verbunden mit $name';
  }

  bool _importing = false;

  /// Neue Uhr-Einheiten holen (Apple Health / Health Connect und/oder intervals.icu)
  Future<int> importWatch({bool quiet = false}) async {
    if (_importing || (!healthOn && icuKey.isEmpty)) return 0;
    _importing = true;
    var added = 0;
    try {
      final since = (lastWatchImport ?? DateTime.now().subtract(const Duration(days: 120))).subtract(const Duration(days: 3));
      final found = <Activity>[];
      if (healthOn && HealthImport.supported) found.addAll(await health.fetch(since));
      if (icuKey.isNotEmpty) found.addAll(await IcuSource(icuKey).fetch(since));
      final known = {for (final r in await store.all('activities')) '${r['id']}'};
      final fresh = found.where((a) => !known.contains(a.id)).toList();
      await repo.saveActivities(fresh);
      added = fresh.length;
      lastWatchImport = DateTime.now();
      await store.setMeta('watch:last', lastWatchImport!.toIso8601String());
      if (added > 0) say(added == 1 ? 'Neu von deiner Uhr: ${fresh.first.title}' : '$added neue Einheiten von deiner Uhr');
    } catch (e) {
      if (!quiet) say('Uhr-Daten: $e');
    } finally {
      _importing = false;
    }
    return added;
  }

  /// FIT-Dateien (z. B. per USB aus GARMIN/Activity oder aus Garmin Connect exportiert) übernehmen
  Future<({int added, int known, int broken})> importFitFiles(List<(String, Uint8List)> files) async {
    final found = <Activity>[];
    var broken = 0;
    for (final (name, bytes) in files) {
      try {
        found.addAll(activitiesFromFit(bytes, name.replaceAll(RegExp(r'\.fit$', caseSensitive: false), '')));
      } catch (_) {
        broken++;
      }
    }
    final known = {for (final r in await store.all('activities')) '${r['id']}'};
    final fresh = found.where((a) => !known.contains(a.id)).toList();
    await repo.saveActivities(fresh);
    return (added: fresh.length, known: found.length - fresh.length, broken: broken);
  }

  // ---------------- Schule & TrainingPeaks ----------------
  FeedsRemote? get feeds => AppConfig.hasBackend ? FeedsRemote(Supabase.instance.client) : null;
  bool get untisOn => links.containsKey('webuntis');
  bool get tpOn => links.containsKey('trainingpeaks');

  Future<void> _loadFeeds() async {
    final l = await store.meta('links');
    if (l is Map) links = {for (final e in l.entries) '${e.key}': '${e.value}'};
    final sd = await store.meta('school:data');
    if (sd is Map) {
      try {
        school = SchoolData.fromJson(Map<String, dynamic>.from(sd));
      } catch (_) {}
    }
    final hw = await store.meta('hw:done');
    if (hw is Map) hwDone = {for (final e in hw.entries) '${e.key}': e.value == true};
    final at = await store.meta('tp:at') as String?;
    tpAt = at == null ? null : DateTime.tryParse(at);
    garminTp = (await store.meta('tp:garmin')) != false;
    untisHintOff = (await store.meta('hint:untis')) == true;
  }

  Future<void> hideUntisHint() async {
    untisHintOff = true;
    await store.setMeta('hint:untis', true);
    notifyListeners();
  }

  void _resetFeeds() {
    links = {};
    school = null;
    schoolError = null;
    hwDone = {};
    tpAt = null;
    tpError = null;
    _lastFeeds = null;
  }

  Future<void> _saveLinks() => store.setMeta('links', Map<String, Object?>.from(links));

  /// Welche Dienste sind verbunden? (nach dem Anmelden, z. B. auf einem neuen Gerät)
  Future<void> _loadLinks() async {
    final f = feeds;
    if (f == null || !signedIn) return;
    try {
      links = await f.status();
      await _saveLinks();
      notifyListeners();
      await syncFeeds(manual: true);
    } catch (_) {}
  }

  Future<void> _applySchool(Map<String, dynamic> raw, {bool announce = false}) async {
    final d = SchoolData.fromJson(raw);
    final before = school;
    school = d;
    schoolError = null;
    await store.setMeta('school:data', d.raw);
    if (announce && before != null) {
      final today = startOfDay(DateTime.now()), to = addDays(today, 2);
      final n = d.changes(today, to).length;
      if (n > before.changes(today, to).length) say('Stundenplan: $n Änderung${n == 1 ? '' : 'en'} heute/morgen');
    }
  }

  Future<String> _applyTp(String ics, {bool announce = false}) async {
    if (!ics.contains('BEGIN:VCALENDAR')) throw const FormatException('Plan ist keine Kalenderdatei');
    final known = {for (final x in (await store.meta('tp:ids') as List? ?? const [])) '$x'};
    final r = await repo.importTpPlan(tpPlanFromIcs(ics), known);
    await store.setMeta('tp:ids', r.ids.toList());
    tpAt = DateTime.now();
    await store.setMeta('tp:at', tpAt!.toIso8601String());
    tpError = null;
    final ch = [if (r.added > 0) '${r.added} neu', if (r.changed > 0) '${r.changed} geändert', if (r.removed > 0) '${r.removed} entfernt'];
    if (announce && ch.isNotEmpty && known.isNotEmpty) say('Trainerin hat den Plan geändert: ${ch.join(', ')}');
    return ch.isEmpty ? 'unverändert' : ch.join(', ');
  }

  String _feedErr(Object e) {
    if (e is FeedsError) return e.message;
    if (e is TimeoutException) return 'Keine Verbindung – später nochmal';
    if (e is FormatException) return e.message;
    return '$e';
  }

  /// WebUntis verbinden – mit Schule + Benutzer + Passwort (Passwort wird nicht gespeichert) oder mit dem Link aus „Zugriff über Untis Mobile“
  Future<String> connectUntis({String? zugang, SchoolHit? school, String? user, String? password}) async {
    final f = feeds;
    if (f == null || !signedIn) return 'Bitte zuerst anmelden';
    final r = await f.connectUntis(zugang: zugang?.trim(), school: school, user: user, password: password);
    links['webuntis'] = r.label;
    await _saveLinks();
    await _applySchool(r.data);
    notifyListeners();
    return 'Verbunden: ${r.label}';
  }

  /// TrainingPeaks (oder einen anderen Kalender) über den privaten iCal-Link verbinden
  Future<String> connectTp(String ical) async {
    final f = feeds;
    if (f == null || !signedIn) return 'Bitte zuerst anmelden';
    final r = await f.connectTp(ical.trim());
    links['trainingpeaks'] = r.label;
    await _saveLinks();
    final res = await _applyTp(r.ics);
    notifyListeners();
    return 'Verbunden mit ${r.label} · Plan $res';
  }

  Future<void> disconnectFeed(String kind) async {
    try {
      await feeds?.disconnect(kind);
    } catch (_) {}
    links.remove(kind);
    await _saveLinks();
    if (kind == 'webuntis') {
      school = null;
      schoolError = null;
      await store.setMeta('school:data', null);
    } else {
      tpError = null;
    }
    notifyListeners();
  }

  /// Stundenplan und TrainingPeaks-Plan holen. Ohne [manual] höchstens alle 10 Minuten.
  Future<String> syncFeeds({bool manual = false}) async {
    final f = feeds;
    if (f == null || !signedIn || links.isEmpty) return '';
    if (feedsBusy) return 'Läuft schon …';
    if (!manual && _lastFeeds != null && DateTime.now().difference(_lastFeeds!) < const Duration(minutes: 10)) return '';
    feedsBusy = true;
    notifyListeners();
    final done = <String>[];
    try {
      if (untisOn) {
        try {
          await _applySchool(await f.fetchUntis().timeout(const Duration(seconds: 40)), announce: !manual);
          done.add('Schule');
        } catch (e) {
          if (e is FeedsError && e.notConnected) links.remove('webuntis');
          schoolError = _feedErr(e);
        }
      }
      if (tpOn) {
        try {
          done.add('TrainingPeaks ${await _applyTp(await f.fetchTp().timeout(const Duration(seconds: 40)), announce: !manual)}');
        } catch (e) {
          if (e is FeedsError && e.notConnected) links.remove('trainingpeaks');
          tpError = _feedErr(e);
        }
      }
      await _saveLinks();
      _lastFeeds = DateTime.now();
    } finally {
      feedsBusy = false;
      notifyListeners();
    }
    if (done.isNotEmpty) return 'Aktualisiert: ${done.join(' · ')}';
    return [schoolError, tpError].whereType<String>().join(' · ');
  }

  /// Hausaufgabe abhaken / wieder öffnen (eigener Haken, unabhängig von WebUntis)
  Future<void> toggleHomework(Homework h) async {
    final s = school;
    if (s == null) return;
    hwDone['u${h.id}'] = !s.isDone(h, hwDone);
    await store.setMeta('hw:done', Map<String, Object?>.from(hwDone));
    notifyListeners();
  }

  // ---------------- In TrainingPeaks nachtragen ----------------
  /// Was in TrainingPeaks fehlt: eigene Einträge ohne Haken – und, wenn Garmin Connect NICHT mit
  /// TrainingPeaks verbunden ist, auch die Uhr-Einheiten (wie tpMissing() in js/tp.js)
  List<Activity> tpMissing(int days, {DateTime? now}) {
    final n = now ?? DateTime.now(), from = startOfDay(n).subtract(Duration(days: days));
    return activities
        .where((a) => a.details?['tp'] == null && !a.start.isBefore(from) && !a.start.isAfter(n) && (a.isManual || (!garminTp && a.source != 'demo')))
        .toList();
  }

  Future<void> setGarminTp(bool connected) async {
    garminTp = connected;
    await store.setMeta('tp:garmin', connected);
    notifyListeners();
  }

  /// Merken, dass die Einheiten in TrainingPeaks sind (wird mit dem Account auf alle Geräte übertragen)
  Future<void> markTp(List<Activity> list, String how) async {
    final at = DateTime.now().toUtc().toIso8601String();
    await repo.saveActivities([for (final a in list) a.copyWith(details: {...?a.details, 'tp': how, 'tpAt': at})]);
  }

  /// ZIP mit einer FIT-Datei je Einheit – in TrainingPeaks alle zusammen auf den Kalender ziehen
  Uint8List tpZip(List<Activity> list) {
    final used = <String>{}, files = <(String, List<int>)>[];
    for (final a in list) {
      var n = fitFileName(a);
      while (used.contains(n)) {
        n = n.replaceFirst(RegExp(r'\.fit$'), '-2.fit');
      }
      used.add(n);
      files.add((n, buildFit(a, kcalEstimate: (s, d, r) => estimateKcal(s, d, r, profile.weightKg))));
    }
    return makeZip(files);
  }

  /// Einheiten der letzten 7 Tage an Apple Health – TrainingPeaks holt sie von dort
  Future<int> tpToHealth(List<Activity> list) async {
    if (!await health.requestWrite()) throw Exception('Kein Schreibzugriff auf Apple Health – in Einstellungen → Health → TriCoach erlauben.');
    final week = DateTime.now().subtract(const Duration(days: 7));
    final sent = <Activity>[];
    for (final a in list.where((a) => a.start.isAfter(week))) {
      if (await health.writeWorkout(a, kcal: estimateKcal(a.sport, a.durationS, a.rpe, profile.weightKg))) sent.add(a);
    }
    await markTp(sent, 'health');
    return sent.length;
  }

  // ---------------- Kalender ----------------
  Future<bool> enableCalendar() async {
    final ok = await devCal.enable();
    calendarOn = ok;
    notifyListeners();
    if (ok) await devCal.sync(repo.activities, repo.planned);
    return ok;
  }

  Future<void> disableCalendar() async {
    await devCal.disable();
    calendarOn = false;
    notifyListeners();
  }

  Future<void> rotateCalendarLink() async {
    final t = await _remote?.rotateCalendarToken();
    if (t != null) calendarToken = t;
    notifyListeners();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSub?.cancel();
    _periodic?.cancel();
    _calDebounce?.cancel();
    repo.dispose();
    super.dispose();
  }
}

/// Zugriff auf den App-Zustand aus jedem Widget: AppScope.of(context)
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child}) : super(notifier: state);

  static AppState of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
  static AppState read(BuildContext context) => context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
