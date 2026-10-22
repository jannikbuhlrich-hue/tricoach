import 'dart:async';
import 'dart:math' as math;

import 'local_store.dart';

/// Verbindung zum Server. Echte Variante: SupabaseRemote. In Tests: FakeRemote.
abstract class SyncRemote {
  /// Zeilen hochladen (anlegen oder ändern). Der Server behält bei Konflikten die neuere Version.
  Future<void> upsert(String table, List<Map<String, dynamic>> rows);

  /// Alle eigenen Zeilen, die der Server seit [since] (synced_at) gespeichert hat – älteste zuerst.
  Future<List<Map<String, dynamic>>> pullSince(String table, String? since, {int limit = 1000});
}

/// Status für die Anzeige („Synchronisiert vor 2 min“, „Offline – 3 Änderungen warten“)
class SyncStatus {
  const SyncStatus({this.busy = false, this.pending = 0, this.lastOk, this.error});
  final bool busy;
  final int pending;
  final DateTime? lastOk;
  final String? error;
}

/// Abgleich zwischen Gerät und Server.
///
/// Regeln:
/// * Jede Änderung landet sofort in der lokalen Datenbank und in einer Warteschlange (offline-fest).
/// * Hochladen: alles aus der Warteschlange. Erst nach Erfolg wird es aus der Warteschlange entfernt –
///   es sei denn, es wurde in der Zwischenzeit erneut geändert.
/// * Herunterladen: alles, was der Server seit dem letzten Abgleich hat. Die neuere Version (updated_at)
///   gewinnt. Lokale, noch nicht hochgeladene Änderungen werden nie von einer älteren Server-Version überschrieben.
/// * Fehler (kein Netz, Server weg): erneuter Versuch mit wachsender Pause (2 s … 5 min).
class SyncEngine {
  SyncEngine(this.store, {this.tables = const ['activities', 'planned'], this.onChanged, this.onStatus});

  final LocalStore store;
  final List<String> tables;

  /// Wird aufgerufen, wenn sich lokale Daten durch den Abgleich geändert haben (Tabellenname)
  final Future<void> Function(String table)? onChanged;
  final void Function(SyncStatus status)? onStatus;

  SyncRemote? _remote;
  Future<void>? _running;
  bool _again = false;
  Timer? _retry;
  int _failures = 0;
  DateTime? _lastOk;
  String? _error;

  set remote(SyncRemote? r) {
    _remote = r;
    if (r != null) schedule();
  }

  SyncRemote? get remote => _remote;

  /// Änderungen an der Warteschlange nacheinander ausführen (Speichern und Abgleich laufen parallel)
  Future<void> _queue = Future.value();
  Future<T> _locked<T>(Future<T> Function() fn) {
    final c = Completer<T>();
    _queue = _queue.then((_) async {
      try {
        c.complete(await fn());
      } catch (e, st) {
        c.completeError(e, st);
      }
    });
    return c.future;
  }

  Future<void> _addPending(String table, Iterable<String> ids) => _locked(() async {
        final cur = await pendingIds(table)..addAll(ids);
        await store.setMeta(_pendingKey(table), cur.toList());
      });

  String _pendingKey(String t) => 'pending:$t';
  String _cursorKey(String t) => 'cursor:$t';

  Future<Set<String>> pendingIds(String table) async {
    final v = await store.meta(_pendingKey(table));
    return v is List ? v.map((e) => '$e').toSet() : <String>{};
  }

  Future<int> pendingCount() async {
    var n = 0;
    for (final t in tables) {
      n += (await pendingIds(t)).length;
    }
    return n;
  }

  /// Lokal speichern und zum Hochladen vormerken
  Future<void> saveLocal(String table, List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return;
    await _locked(() => store.putAll(table, rows));
    await _addPending(table, rows.map((r) => '${r['id']}'));
    await _emitStatus();
    schedule();
  }

  /// Abgleich anstoßen (mehrfache Aufrufe werden zusammengefasst)
  void schedule() {
    if (_remote == null) return;
    if (_running != null) {
      _again = true;
      return;
    }
    _running = _loop().whenComplete(() => _running = null);
  }

  /// Abgleich jetzt und auf Ergebnis warten (z. B. „Jetzt synchronisieren“ oder Tests)
  Future<void> syncNow() async {
    if (_remote == null) return;
    schedule();
    while (_running != null) {
      await _running;
    }
  }

  Future<void> _loop() async {
    do {
      _again = false;
      await _syncOnce();
    } while (_again && _remote != null);
  }

  Future<void> _syncOnce() async {
    final remote = _remote;
    if (remote == null) return;
    _retry?.cancel();
    onStatus?.call(SyncStatus(busy: true, pending: await pendingCount(), lastOk: _lastOk, error: _error));
    try {
      for (final t in tables) {
        await _push(remote, t);
      }
      for (final t in tables) {
        await _pull(remote, t);
      }
      _failures = 0;
      _error = null;
      _lastOk = DateTime.now();
    } catch (e) {
      _failures++;
      _error = _friendly(e);
      final wait = Duration(seconds: math.min(300, 2 * math.pow(2, _failures - 1).toInt()));
      _retry = Timer(wait, schedule);
    }
    await _emitStatus();
  }

  Future<void> _push(SyncRemote remote, String table) async {
    final ids = await pendingIds(table);
    if (ids.isEmpty) return;
    final rows = <Map<String, dynamic>>[];
    for (final id in ids) {
      final r = await store.get(table, id);
      if (r != null) rows.add(r);
    }
    for (var i = 0; i < rows.length; i += 200) {
      final batch = rows.sublist(i, math.min(rows.length, i + 200));
      await remote.upsert(table, batch);
      // Nur entfernen, was seitdem nicht erneut geändert wurde
      await _locked(() async {
        final still = await pendingIds(table);
        for (final r in batch) {
          final now = await store.get(table, '${r['id']}');
          if (now == null || now['updated_at'] == r['updated_at']) still.remove('${r['id']}');
        }
        await store.setMeta(_pendingKey(table), still.toList());
      });
    }
  }

  Future<void> _pull(SyncRemote remote, String table) async {
    var cursor = await store.meta(_cursorKey(table)) as String?;
    var changed = false;
    while (true) {
      final rows = await remote.pullSince(table, cursor);
      if (rows.isEmpty) break;
      final toPut = <Map<String, dynamic>>[];
      final won = <String>[];
      String? maxSynced = cursor;
      for (final server in rows) {
        final synced = server['synced_at']?.toString();
        if (synced != null && (maxSynced == null || synced.compareTo(maxSynced) > 0)) maxSynced = synced;
        final row = Map<String, dynamic>.from(server)
          ..remove('synced_at')
          ..remove('user_id')
          ..remove('athlete_id')
          ..remove('created_at');
        toPut.add(row);
      }
      // Zusammenführen unter Sperre, damit keine gleichzeitige lokale Änderung verloren geht
      final applied = await _locked(() async {
        final pending = await pendingIds(table);
        final out = <Map<String, dynamic>>[];
        for (final row in toPut) {
          final id = '${row['id']}';
          final local = await store.get(table, id);
          if (local == null) {
            out.add(row);
          } else if (pending.contains(id)) {
            // Lokal geändert und noch nicht hochgeladen: nur eine neuere Server-Version gewinnt
            if (newer(row, local)) {
              out.add(row);
              won.add(id);
            }
          } else if (!_same(row, local)) {
            out.add(row);
          }
        }
        await store.putAll(table, out);
        if (won.isNotEmpty) {
          await store.setMeta(_pendingKey(table), (pending..removeAll(won)).toList());
        }
        return out.length;
      });
      if (applied > 0) changed = true;
      final progressed = maxSynced != cursor;
      cursor = maxSynced;
      await store.setMeta(_cursorKey(table), cursor);
      if (rows.length < 1000 || !progressed) break;
    }
    if (changed) await onChanged?.call(table);
  }

  /// Ist [a] neuer als [b]? (updated_at vergleichen, ISO-Zeitstempel in UTC)
  static bool newer(Map<String, dynamic> a, Map<String, dynamic> b) {
    final ta = DateTime.tryParse('${a['updated_at']}'), tb = DateTime.tryParse('${b['updated_at']}');
    if (ta == null) return false;
    if (tb == null) return true;
    return ta.isAfter(tb);
  }

  static bool _same(Map<String, dynamic> a, Map<String, dynamic> b) => DateTime.tryParse('${a['updated_at']}') == DateTime.tryParse('${b['updated_at']}');

  Future<void> _emitStatus() async =>
      onStatus?.call(SyncStatus(busy: _running != null && _remote != null, pending: await pendingCount(), lastOk: _lastOk, error: _error));

  static String _friendly(Object e) {
    final s = e.toString();
    if (RegExp(r'SocketException|Failed host lookup|XMLHttpRequest|ClientException|Connection', caseSensitive: false).hasMatch(s)) {
      return 'Offline – Änderungen werden später übertragen.';
    }
    if (s.contains('JWT') || s.contains('401')) return 'Anmeldung abgelaufen – bitte neu anmelden.';
    return 'Abgleich gerade nicht möglich – neuer Versuch läuft automatisch.';
  }

  /// Nach dem Abmelden: Warteschlange und Abgleich-Stand vergessen
  Future<void> reset() async {
    _retry?.cancel();
    _remote = null;
    await _locked(() async {
      for (final t in tables) {
        await store.setMeta(_pendingKey(t), null);
        await store.setMeta(_cursorKey(t), null);
      }
    });
  }

  /// Nach dem Anmelden: Alles Lokale einmal hochladen (z. B. Einträge aus der Zeit ohne Account)
  Future<void> markAllPending() async {
    for (final t in tables) {
      final rows = await store.all(t);
      await _addPending(t, rows.map((r) => '${r['id']}'));
    }
  }

  void dispose() => _retry?.cancel();
}
