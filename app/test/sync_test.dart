import 'package:flutter_test/flutter_test.dart';
import 'package:tricoach/core/models.dart';
import 'package:tricoach/core/sport.dart';
import 'package:tricoach/data/local_store.dart';
import 'package:tricoach/data/repository.dart';
import 'package:tricoach/data/sync_engine.dart';

/// Nachbau des Servers mit denselben Regeln wie die Datenbank:
/// neuere Version gewinnt (updated_at), synced_at setzt der Server.
class FakeServer {
  final Map<String, Map<String, Map<String, dynamic>>> tables = {'activities': {}, 'planned': {}};
  int _clock = 0;
  bool offline = false;

  String _stamp() => DateTime.utc(2026, 1, 1).add(Duration(microseconds: ++_clock)).toIso8601String();

  void write(String table, Map<String, dynamic> row) {
    final t = tables[table]!, id = '${row['id']}';
    final old = t[id];
    if (old != null && DateTime.parse('${row['updated_at']}').isBefore(DateTime.parse('${old['updated_at']}'))) return;
    t[id] = {...row, 'synced_at': _stamp()};
  }
}

class FakeRemote implements SyncRemote {
  FakeRemote(this.server);
  final FakeServer server;
  int upserts = 0;

  @override
  Future<void> upsert(String table, List<Map<String, dynamic>> rows) async {
    if (server.offline) throw Exception('SocketException: Failed host lookup');
    upserts++;
    for (final r in rows) {
      server.write(table, r);
    }
  }

  @override
  Future<List<Map<String, dynamic>>> pullSince(String table, String? since, {int limit = 1000}) async {
    if (server.offline) throw Exception('SocketException: Failed host lookup');
    final rows = server.tables[table]!.values.where((r) => since == null || '${r['synced_at']}'.compareTo(since) >= 0).toList()
      ..sort((a, b) => '${a['synced_at']}'.compareTo('${b['synced_at']}'));
    return rows.take(limit).map((r) => {...r, 'user_id': 'u1'}).toList();
  }
}

Activity swim(String id, {double km = 2, DateTime? updated}) => Activity(
      id: id,
      sport: Sport.swim,
      start: DateTime.utc(2026, 10, 20, 16),
      durationS: 3000,
      distanceM: km * 1000,
      swimWhere: SwimWhere.pool25,
      updatedAt: updated,
    );

Future<Repository> device(FakeServer server) async {
  final r = Repository(MemoryStore());
  await r.load();
  r.sync.remote = FakeRemote(server);
  return r;
}

void main() {
  test('Eintrag auf Gerät A erscheint auf Gerät B', () async {
    final server = FakeServer();
    final a = await device(server), b = await device(server);
    await a.saveActivity(swim('s1', km: 2.35));
    await a.sync.syncNow();
    await b.sync.syncNow();
    expect(b.activities.single.distanceM, 2350);
    expect(b.activities.single.tss, isNotNull);
  });

  test('Bearbeiten auf B und Löschen auf A kommen überall an', () async {
    final server = FakeServer();
    final a = await device(server), b = await device(server);
    await a.saveActivity(swim('s1'));
    await a.sync.syncNow();
    await b.sync.syncNow();

    await b.saveActivity(b.activities.single.copyWith(notes: 'Hauptserie 10×100', distanceM: 2500));
    await b.sync.syncNow();
    await a.sync.syncNow();
    expect(a.activities.single.notes, 'Hauptserie 10×100');
    expect(a.activities.single.distanceM, 2500);

    await a.deleteActivity('s1');
    await a.sync.syncNow();
    await b.sync.syncNow();
    expect(a.activities, isEmpty);
    expect(b.activities, isEmpty);
  });

  test('Offline: Änderungen warten und gehen später raus', () async {
    final server = FakeServer()..offline = true;
    final a = await device(server);
    await a.saveActivity(swim('s1'));
    await a.saveActivity(swim('s2'));
    await a.sync.syncNow();
    expect(await a.sync.pendingCount(), 2);
    expect(server.tables['activities'], isEmpty);
    expect(a.activities.length, 2, reason: 'lokal sofort sichtbar');

    server.offline = false;
    await a.sync.syncNow();
    expect(await a.sync.pendingCount(), 0);
    expect(server.tables['activities']!.length, 2);
  });

  test('Konflikt: die neuere Änderung gewinnt – auf beiden Geräten', () async {
    final server = FakeServer();
    final a = await device(server), b = await device(server);
    await a.saveActivity(swim('s1'));
    await a.sync.syncNow();
    await b.sync.syncNow();

    // Beide ändern offline; B später
    server.offline = true;
    final t = DateTime.now().toUtc();
    await a.saveActivity(swim('s1', km: 1.0, updated: t));
    await b.saveActivity(swim('s1', km: 3.0, updated: t.add(const Duration(seconds: 5))));
    await a.sync.syncNow();
    await b.sync.syncNow();
    server.offline = false;

    // B lädt zuerst hoch, dann A (ältere Änderung) – trotzdem gewinnt B
    await b.sync.syncNow();
    await a.sync.syncNow();
    await b.sync.syncNow();
    expect(server.tables['activities']!['s1']!['distance_m'], 3000);
    expect(a.activities.single.distanceM, 3000);
    expect(b.activities.single.distanceM, 3000);
    expect(await a.sync.pendingCount(), 0);
  });

  test('Ungespeicherte lokale Änderung wird nicht von älterem Server-Stand überschrieben', () async {
    final server = FakeServer();
    final a = await device(server);
    final old = swim('s1', km: 1, updated: DateTime.utc(2026, 10, 1));
    server.write('activities', old.toRow());
    // Lokale neuere Version, noch nicht hochgeladen
    server.offline = true;
    await a.saveActivity(swim('s1', km: 2, updated: DateTime.utc(2026, 10, 2)));
    server.offline = false;
    await a.sync.syncNow();
    expect(a.activities.single.distanceM, 2000);
    expect(server.tables['activities']!['s1']!['distance_m'], 2000);
  });

  test('Geplante Einheiten werden genauso abgeglichen', () async {
    final server = FakeServer();
    final a = await device(server), b = await device(server);
    await a.savePlanned(PlannedSession(id: 'p1', startsAt: DateTime.utc(2026, 10, 24, 15), sport: Sport.run, title: 'Schwelle 5×1 km', minutes: 60));
    await a.sync.syncNow();
    await b.sync.syncNow();
    expect(b.planned.single.title, 'Schwelle 5×1 km');
    await b.deletePlanned('p1');
    await b.sync.syncNow();
    await a.sync.syncNow();
    expect(a.planned, isEmpty);
  });

  test('Viele Einträge: Hochladen in Paketen', () async {
    final server = FakeServer();
    final a = await device(server);
    final remote = a.sync.remote as FakeRemote;
    await a.saveActivities([for (var i = 0; i < 450; i++) swim('s$i')]);
    await a.sync.syncNow();
    expect(server.tables['activities']!.length, 450);
    expect(remote.upserts, greaterThanOrEqualTo(3));
  });

  test('Sembast-Datenbank (wie auf dem Gerät) speichert und liest', () async {
    final s = await SembastStore.inMemory();
    await s.putAll('activities', [swim('s1').toRow()]);
    await s.setMeta('pending:activities', ['s1']);
    expect((await s.get('activities', 's1'))!['distance_m'], 2000);
    expect(await s.meta('pending:activities'), ['s1']);
    await s.clear();
    expect(await s.all('activities'), isEmpty);
  });
}
