import 'package:supabase_flutter/supabase_flutter.dart';

/// Server-Funktion „feeds“ (supabase/functions/feeds): verbindet WebUntis und TrainingPeaks für jeden Nutzer.
/// Zugangsdaten bleiben auf dem Server – die App bekommt nur Stundenplan bzw. Kalenderdatei zurück.
class FeedsRemote {
  FeedsRemote(this._c);
  final SupabaseClient _c;

  Future<Map<String, dynamic>> _call(String action, [Map<String, dynamic> args = const {}]) async {
    try {
      final r = await _c.functions.invoke('feeds', body: {'action': action, ...args});
      final d = r.data;
      if (d is Map) return Map<String, dynamic>.from(d);
      throw const FeedsError('Unerwartete Antwort vom Server');
    } on FunctionException catch (e) {
      final d = e.details;
      final msg = d is Map && d['error'] != null ? '${d['error']}' : 'Server gerade nicht erreichbar (${e.status})';
      throw FeedsError(msg, notConnected: d is Map && d['code'] == 'none');
    }
  }

  Future<List<SchoolHit>> searchSchool(String q) async {
    final r = await _call('searchSchool', {'q': q});
    return [
      for (final s in (r['schools'] as List? ?? const []))
        if (s is Map) SchoolHit('${s['server']}', '${s['school']}', '${s['name']}', '${s['address'] ?? ''}'),
    ];
  }

  /// Verbindungen des Nutzers: Dienst → Anzeige-Name
  Future<Map<String, String>> status() async {
    final r = await _call('status');
    final links = r['links'];
    return {if (links is Map) for (final e in links.entries) '${e.key}': '${(e.value as Map?)?['label'] ?? ''}'};
  }

  /// Mit Link/Text aus „Zugriff über Untis Mobile“ ([zugang]) oder mit Schule + Benutzer + Passwort
  Future<({String label, Map<String, dynamic> data})> connectUntis({String? zugang, SchoolHit? school, String? user, String? password}) async {
    final r = await _call('untisConnect', {
      if (zugang != null) 'zugang': zugang,
      if (school != null) ...{'server': school.server, 'school': school.school, 'name': school.name},
      if (user != null) 'user': user,
      if (password != null) 'password': password,
    });
    return (label: '${r['label']}', data: Map<String, dynamic>.from(r['data'] as Map));
  }

  Future<Map<String, dynamic>> fetchUntis() async => Map<String, dynamic>.from((await _call('untisFetch'))['data'] as Map);

  Future<({String label, String ics})> connectTp(String ical) async {
    final r = await _call('tpConnect', {'ical': ical});
    return (label: '${r['label']}', ics: '${r['ics']}');
  }

  Future<String> fetchTp() async => '${(await _call('tpFetch'))['ics']}';

  Future<void> disconnect(String kind) => _call('disconnect', {'kind': kind});
}

class SchoolHit {
  const SchoolHit(this.server, this.school, this.name, this.address);
  final String server, school, name, address;
}

class FeedsError implements Exception {
  const FeedsError(this.message, {this.notConnected = false});
  final String message;
  final bool notConnected;
  @override
  String toString() => message;
}
