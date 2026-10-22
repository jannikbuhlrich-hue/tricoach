import 'package:supabase_flutter/supabase_flutter.dart';

import 'sync_engine.dart';

/// Abgleich über Supabase. Lokale Tabellen heißen wie auf dem Server, nur „planned“ → planned_sessions.
class SupabaseRemote implements SyncRemote {
  SupabaseRemote(this.client, this.userId);

  final SupabaseClient client;
  final String userId;

  static const _serverTable = {'activities': 'activities', 'planned': 'planned_sessions'};
  static const _owner = {'activities': 'user_id', 'planned': 'athlete_id'};

  @override
  Future<void> upsert(String table, List<Map<String, dynamic>> rows) async {
    final t = _serverTable[table]!, owner = _owner[table]!;
    final payload = [
      for (final r in rows)
        {
          ...r,
          owner: userId,
          if (table == 'planned') 'created_by': r['created_by'] ?? userId,
        }
    ];
    await client.from(t).upsert(payload, onConflict: '$owner,id');
  }

  @override
  Future<List<Map<String, dynamic>>> pullSince(String table, String? since, {int limit = 1000}) async {
    final t = _serverTable[table]!, owner = _owner[table]!;
    var q = client.from(t).select().eq(owner, userId);
    if (since != null) q = q.gte('synced_at', since);
    final rows = await q.order('synced_at', ascending: true).limit(limit);
    return [for (final r in rows) Map<String, dynamic>.from(r)];
  }

  /// Echtzeit: Bei jeder Änderung auf dem Server (z. B. vom anderen Gerät oder vom Coach) Abgleich anstoßen
  RealtimeChannel listen(void Function() onChange) {
    final ch = client.channel('tricoach-$userId');
    ch
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'activities',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'user_id', value: userId),
          callback: (_) => onChange(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'planned_sessions',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'athlete_id', value: userId),
          callback: (_) => onChange(),
        )
        .subscribe();
    return ch;
  }

  /// Profil (Leistungswerte, Kalender-Token) laden
  Future<Map<String, dynamic>?> loadProfile() async =>
      await client.from('profiles').select().eq('id', userId).maybeSingle();

  Future<void> saveProfileSettings(Map<String, dynamic> settings, {String? displayName}) async {
    await client.from('profiles').update({
      'settings': settings,
      if (displayName != null) 'display_name': displayName,
    }).eq('id', userId);
  }

  Future<void> saveHealthConsent() async {
    await client.from('profiles').update({'health_consent_at': DateTime.now().toUtc().toIso8601String()}).eq('id', userId);
  }

  /// Neuer Kalender-Link (der alte funktioniert danach nicht mehr)
  Future<String?> rotateCalendarToken() async {
    final row = await client.rpc('rotate_calendar_token');
    return row?.toString();
  }

  // ---- Coach ----
  Future<String> createCoachInvite() async {
    final row = await client.from('coach_invites').insert({'coach_id': userId}).select('code').single();
    return '${row['code']}';
  }

  Future<void> acceptCoachInvite(String code) async {
    await client.rpc('accept_coach_invite', params: {'invite_code': code});
  }

  /// Athleten eines Coaches (Profil-Zeilen)
  Future<List<Map<String, dynamic>>> myAthletes() async {
    final links = await client.from('coach_links').select('athlete_id').eq('coach_id', userId).eq('status', 'active');
    final ids = [for (final l in links) '${l['athlete_id']}'];
    if (ids.isEmpty) return [];
    final rows = await client.from('profiles').select('id, display_name, settings').inFilter('id', ids);
    return [for (final r in rows) Map<String, dynamic>.from(r)];
  }

  Future<List<Map<String, dynamic>>> athleteActivities(String athleteId, DateTime from) async {
    final rows = await client
        .from('activities')
        .select()
        .eq('user_id', athleteId)
        .isFilter('deleted_at', null)
        .gte('start_at', from.toUtc().toIso8601String())
        .order('start_at', ascending: false)
        .limit(500);
    return [for (final r in rows) Map<String, dynamic>.from(r)];
  }

  Future<List<Map<String, dynamic>>> athletePlan(String athleteId, DateTime from) async {
    final rows = await client
        .from('planned_sessions')
        .select()
        .eq('athlete_id', athleteId)
        .isFilter('deleted_at', null)
        .gte('starts_at', from.toUtc().toIso8601String())
        .order('starts_at')
        .limit(500);
    return [for (final r in rows) Map<String, dynamic>.from(r)];
  }

  /// Coach plant eine Einheit für einen Athleten
  Future<void> planForAthlete(String athleteId, Map<String, dynamic> row) async {
    await client.from('planned_sessions').upsert({...row, 'athlete_id': athleteId, 'created_by': userId}, onConflict: 'athlete_id,id');
  }
}
