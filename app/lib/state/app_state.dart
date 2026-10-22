import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../core/fit.dart';
import '../core/models.dart';
import '../data/device_calendar_sync.dart';
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
