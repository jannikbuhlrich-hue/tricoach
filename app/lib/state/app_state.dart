import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' show ClientException;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../core/fit.dart';
import '../core/format.dart';
import '../core/models.dart';
import '../core/school.dart';
import '../core/tc_crypto.dart';
import '../core/tp_plan.dart';
import '../data/device_calendar_sync.dart';
import '../data/github_feeds.dart';
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

  // Schule (WebUntis) und TrainingPeaks-Plan – kommen verschlüsselt von den GitHub-Jobs
  String tcKey = '';
  String tcRepo = GithubFeeds.defaultRepo;
  SchoolData? school;
  String? schoolError;
  Map<String, bool> hwDone = {};
  DateTime? tpAt;
  String? tpError;
  bool feedsBusy = false;
  DateTime? _lastFeeds;

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

  // ---------------- Schule & TrainingPeaks (über GitHub) ----------------
  Future<void> _loadFeeds() async {
    tcKey = (await store.meta('tc:key') as String?) ?? '';
    tcRepo = (await store.meta('tc:repo') as String?) ?? GithubFeeds.defaultRepo;
    final dk = await store.meta('tc:dk');
    if (dk is Map && tcKey.isNotEmpty && dk['salt'] is String && dk['k'] is String) {
      TcCrypto.remember(tcKey, dk['salt'] as String, base64.decode(dk['k'] as String));
    }
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
  }

  void _resetFeeds() {
    tcKey = '';
    tcRepo = GithubFeeds.defaultRepo;
    school = null;
    schoolError = null;
    hwDone = {};
    tpAt = null;
    tpError = null;
    _lastFeeds = null;
  }

  /// Schlüssel (= GitHub-Secret TRICOACH_KEY) und Repo speichern und sofort abrufen
  Future<String> setTcKey(String key, {String? repo}) async {
    final k = key.trim(), r = (repo ?? tcRepo).trim();
    if (r.isNotEmpty && !GithubFeeds.validRepo(r)) return 'Repo bitte als „besitzer/name“ angeben';
    if (k != tcKey) await store.setMeta('tc:dk', null);
    tcKey = k;
    tcRepo = r.isEmpty ? GithubFeeds.defaultRepo : r;
    await store.setMeta('tc:key', k.isEmpty ? null : k);
    await store.setMeta('tc:repo', tcRepo);
    if (k.isEmpty) {
      school = null;
      schoolError = null;
      tpError = null;
      await store.setMeta('school:data', null);
      notifyListeners();
      return 'Schule & TrainingPeaks getrennt';
    }
    notifyListeners();
    return syncFeeds(manual: true);
  }

  String _feedErr(Object e) {
    if (e is TcKeyError) return e.toString();
    if (e is TimeoutException || e is ClientException) return 'Keine Verbindung zu GitHub – später nochmal';
    if (e is FormatException) return e.message;
    return '$e';
  }

  Future<void> _rememberKey(String txt) async {
    try {
      final salt = TcCrypto.saltOf(txt);
      final dk = await store.meta('tc:dk');
      if (dk is Map && dk['salt'] == salt) return;
      final k = await TcCrypto.deriveKey(tcKey, base64.decode(salt));
      await store.setMeta('tc:dk', {'salt': salt, 'k': base64.encode(k)});
    } catch (_) {}
  }

  /// Stundenplan und TrainingPeaks-Plan holen. Ohne [manual] höchstens alle 10 Minuten.
  Future<String> syncFeeds({bool manual = false}) async {
    if (tcKey.isEmpty) return manual ? 'Erst den TriCoach-Schlüssel eintragen' : '';
    if (feedsBusy) return 'Läuft schon …';
    if (!manual && _lastFeeds != null && DateTime.now().difference(_lastFeeds!) < const Duration(minutes: 10)) return '';
    feedsBusy = true;
    notifyListeners();
    final feeds = GithubFeeds(tcRepo), done = <String>[];
    try {
      // Schule
      try {
        final txt = await feeds.school();
        if (txt == null) {
          schoolError = 'Noch keine Schuldaten – läuft der GitHub-Job „Schule (WebUntis)“?';
        } else {
          final d = SchoolData.fromJson(Map<String, dynamic>.from(await TcCrypto.decrypt(txt, tcKey) as Map));
          await _rememberKey(txt);
          final before = school;
          school = d;
          schoolError = null;
          await store.setMeta('school:data', d.raw);
          done.add('Schule (Stand ${timeTxt(d.at.toLocal())})');
          if (!manual && before != null) {
            final today = startOfDay(DateTime.now()), to = addDays(today, 2);
            final n = d.changes(today, to).length;
            if (n > before.changes(today, to).length) say('Stundenplan: $n Änderung${n == 1 ? '' : 'en'} heute/morgen');
          }
        }
      } catch (e) {
        schoolError = _feedErr(e);
      }
      // TrainingPeaks
      try {
        final txt = await feeds.trainingPeaks();
        if (txt == null) {
          tpError = 'Noch kein Plan – der iCal-Link deiner Trainerin fehlt im GitHub-Job „TrainingPeaks-Plan“.';
        } else {
          final o = Map<String, dynamic>.from(await TcCrypto.decrypt(txt, tcKey) as Map);
          await _rememberKey(txt);
          final ics = '${o['ics'] ?? ''}';
          if (!ics.contains('BEGIN:VCALENDAR')) throw const FormatException('Plan ist keine Kalenderdatei');
          final known = {for (final x in (await store.meta('tp:ids') as List? ?? const [])) '$x'};
          final r = await repo.importTpPlan(tpPlanFromIcs(ics), known);
          await store.setMeta('tp:ids', r.ids.toList());
          tpAt = DateTime.tryParse('${o['at']}');
          await store.setMeta('tp:at', tpAt?.toIso8601String());
          tpError = null;
          final ch = [if (r.added > 0) '${r.added} neu', if (r.changed > 0) '${r.changed} geändert', if (r.removed > 0) '${r.removed} entfernt'];
          done.add('TrainingPeaks ${ch.isEmpty ? 'unverändert' : ch.join(', ')}');
          if (!manual && ch.isNotEmpty && known.isNotEmpty) say('Trainerin hat den Plan geändert: ${ch.join(', ')}');
        }
      } catch (e) {
        tpError = _feedErr(e);
      }
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
