import 'package:sembast/sembast_memory.dart';

import 'db_open_io.dart' if (dart.library.js_interop) 'db_open_web.dart';

/// Lokale Datenbank auf dem Gerät. Die App liest und schreibt immer hier zuerst –
/// so läuft sie offline, und der Abgleich mit dem Server passiert im Hintergrund.
abstract class LocalStore {
  Future<List<Map<String, dynamic>>> all(String table);
  Future<Map<String, dynamic>?> get(String table, String id);
  Future<void> putAll(String table, List<Map<String, dynamic>> rows);
  Future<Object?> meta(String key);
  Future<void> setMeta(String key, Object? value);
  Future<void> clear();
}

/// Sembast: eine reine Dart-Datenbank, läuft auf iOS, Android, Windows, macOS und im Browser.
class SembastStore implements LocalStore {
  SembastStore._(this._db);
  final Database _db;
  final _meta = StoreRef<String, Object?>('meta');
  StoreRef<String, Map<String, Object?>> _table(String t) => stringMapStoreFactory.store(t);

  static Future<SembastStore> open() async => SembastStore._(await openPlatformDb());

  /// Nur für Tests
  static Future<SembastStore> inMemory() async => SembastStore._(await databaseFactoryMemory.openDatabase('test-${DateTime.now().microsecondsSinceEpoch}'));

  @override
  Future<List<Map<String, dynamic>>> all(String table) async {
    final recs = await _table(table).find(_db);
    return [for (final r in recs) Map<String, dynamic>.from(r.value)];
  }

  @override
  Future<Map<String, dynamic>?> get(String table, String id) async {
    final v = await _table(table).record(id).get(_db);
    return v == null ? null : Map<String, dynamic>.from(v);
  }

  @override
  Future<void> putAll(String table, List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return;
    await _db.transaction((txn) async {
      for (final r in rows) {
        await _table(table).record('${r['id']}').put(txn, r.cast<String, Object?>());
      }
    });
  }

  @override
  Future<Object?> meta(String key) => _meta.record(key).get(_db);

  @override
  Future<void> setMeta(String key, Object? value) async {
    if (value == null) {
      await _meta.record(key).delete(_db);
    } else {
      await _meta.record(key).put(_db, value);
    }
  }

  @override
  Future<void> clear() async {
    await _db.transaction((txn) async {
      for (final t in const ['activities', 'planned']) {
        await _table(t).delete(txn);
      }
      await _meta.delete(txn);
    });
  }
}

/// Speicher im Arbeitsspeicher – für Tests
class MemoryStore implements LocalStore {
  final Map<String, Map<String, Map<String, dynamic>>> _t = {};
  final Map<String, Object?> _m = {};

  @override
  Future<List<Map<String, dynamic>>> all(String table) async => [for (final r in (_t[table] ?? {}).values) Map<String, dynamic>.from(r)];

  @override
  Future<Map<String, dynamic>?> get(String table, String id) async {
    final r = _t[table]?[id];
    return r == null ? null : Map<String, dynamic>.from(r);
  }

  @override
  Future<void> putAll(String table, List<Map<String, dynamic>> rows) async {
    final t = _t.putIfAbsent(table, () => {});
    for (final r in rows) {
      t['${r['id']}'] = Map<String, dynamic>.from(r);
    }
  }

  @override
  Future<Object?> meta(String key) async => _m[key];

  @override
  Future<void> setMeta(String key, Object? value) async => value == null ? _m.remove(key) : _m[key] = value;

  @override
  Future<void> clear() async {
    _t.clear();
    _m.clear();
  }
}
