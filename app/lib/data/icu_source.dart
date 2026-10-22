import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/models.dart';
import '../core/sport.dart';

/// intervals.icu: bekommt die Einheiten automatisch aus Garmin Connect (wie in der Web-App).
/// Läuft auf allen Geräten inkl. PC und Web – praktisch für alle, die Apple Health/Health Connect nicht nutzen.
class IcuSource {
  IcuSource(this.apiKey, {http.Client? client}) : _client = client ?? http.Client();

  final String apiKey;
  final http.Client _client;
  static const _base = 'https://intervals.icu/api/v1';

  Map<String, String> get _auth => {'Authorization': 'Basic ${base64Encode(utf8.encode('API_KEY:${apiKey.trim()}'))}'};

  Future<dynamic> _get(String path) async {
    final r = await _client.get(Uri.parse('$_base$path'), headers: _auth);
    if (r.statusCode == 401 || r.statusCode == 403) throw IcuException('API-Key wird nicht akzeptiert. Bitte in den Einstellungen prüfen.');
    if (r.statusCode != 200) throw IcuException('intervals.icu antwortet mit ${r.statusCode}');
    return jsonDecode(utf8.decode(r.bodyBytes));
  }

  /// Verbindung testen → Name des Athleten
  Future<String> test() async {
    final a = await _get('/athlete/0') as Map;
    return '${a['name'] ?? a['firstname'] ?? 'verbunden'}';
  }

  String _day(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Einheiten (Zusammenfassung) seit [from]
  Future<List<Activity>> fetch(DateTime from, {DateTime? to}) async {
    final end = to ?? DateTime.now().add(const Duration(days: 1));
    final list = await _get('/athlete/0/activities?oldest=${_day(from)}&newest=${_day(end)}') as List;
    return [for (final item in list) if (item is Map) fromIcu(Map<String, dynamic>.from(item))].whereType<Activity>().toList();
  }

  static Sport sportOf(String t) {
    if (RegExp('swim', caseSensitive: false).hasMatch(t)) return Sport.swim;
    if (RegExp('ride|cycl|bike', caseSensitive: false).hasMatch(t)) return Sport.bike;
    if (RegExp('run', caseSensitive: false).hasMatch(t)) return Sport.run;
    if (RegExp('weight|strength|workout|crossfit|hiit|pilates', caseSensitive: false).hasMatch(t)) return Sport.strength;
    return Sport.other;
  }

  static const _art = {
    'Kitesurf': 'Kitesurfen', 'Windsurf': 'Windsurfen', 'Surfing': 'Surfen', 'StandUpPaddling': 'SUP', 'Hike': 'Wandern', 'Walk': 'Spaziergang',
    'Rowing': 'Rudern', 'RockClimbing': 'Klettern', 'NordicSki': 'Ski', 'AlpineSki': 'Ski', 'Soccer': 'Fußball', 'Tennis': 'Tennis',
    'InlineSkate': 'Inlineskaten', 'Canoeing': 'Kanu', 'Kayaking': 'Kajak', 'Sail': 'Segeln', 'Yoga': 'Yoga',
  };

  /// Eine Einheit aus der intervals.icu-Liste übernehmen (öffentlich für Tests)
  static Activity? fromIcu(Map<String, dynamic> item) {
    final id = item['id']?.toString();
    final startRaw = item['start_date_local'] ?? item['start_date'];
    if (id == null || startRaw == null) return null;
    // start_date_local hat keine Zeitzone → als Ortszeit lesen
    final start = DateTime.tryParse('$startRaw');
    if (start == null) return null;
    final type = '${item['type'] ?? ''}';
    final sport = sportOf(type);
    final desc = '${item['description'] ?? ''}'.replaceAll(RegExp(r'\n?\(per Siri über TriCoach\)'), '').trim();
    final rpe = item['icu_rpe'] ?? item['perceived_exertion'];
    final pool = item['pool_length'];
    num? n(Object? v) => v is num ? v : null;
    return Activity(
      id: 'icu-$id',
      sport: sport,
      art: sport == Sport.other ? (_art[type] ?? (type.isEmpty ? null : type)) : null,
      name: '${item['name'] ?? ''}',
      start: start.isUtc ? start : start.toUtc(),
      durationS: (n(item['moving_time']) ?? n(item['elapsed_time']) ?? 0).round(),
      distanceM: (n(item['distance']) ?? 0).toDouble(),
      avgHr: n(item['average_heartrate'])?.round(),
      maxHr: n(item['max_heartrate'])?.round(),
      kcal: n(item['calories'])?.round(),
      rpe: rpe is num ? rpe.round().clamp(1, 10) : null,
      notes: desc,
      swimWhere: sport == Sport.swim ? (RegExp('open', caseSensitive: false).hasMatch(type) ? SwimWhere.openWater : SwimWhere.parse(pool is num ? pool.round() : null)) : null,
      source: 'icu',
      extId: id,
      details: {
        if ('${item['device_name'] ?? ''}'.trim().isNotEmpty) 'device': '${item['device_name']}'.trim(),
        if (n(item['icu_weighted_avg_watts']) != null) 'np': n(item['icu_weighted_avg_watts'])!.round(),
        if (n(item['icu_average_watts']) != null) 'ap': n(item['icu_average_watts'])!.round(),
        if (n(item['total_elevation_gain']) != null) 'elev': n(item['total_elevation_gain'])!.round(),
        if (n(item['icu_training_load']) != null) 'icuLoad': n(item['icu_training_load'])!.round(),
      },
    );
  }
}

class IcuException implements Exception {
  IcuException(this.message);
  final String message;
  @override
  String toString() => message;
}
