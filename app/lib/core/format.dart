import 'sport.dart';

/// Zahlen deutsch formatieren: 2,35
String de(num? v, [int digits = 0]) {
  if (v == null || !v.isFinite) return '–';
  final s = v.toStringAsFixed(digits);
  final parts = s.split('.');
  final neg = parts[0].startsWith('-');
  var whole = neg ? parts[0].substring(1) : parts[0];
  final buf = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) buf.write('.');
    buf.write(whole[i]);
  }
  whole = buf.toString();
  return '${neg ? '−' : ''}$whole${parts.length > 1 ? ',${parts[1]}' : ''}';
}

/// Sekunden → „1h 05m“ oder „45 min“
String hm(num seconds) {
  final m = (seconds / 60).round();
  return m >= 60 ? '${m ~/ 60}h ${(m % 60).toString().padLeft(2, '0')}m' : '$m min';
}

/// Sekunden → „1:05:00“ oder „45:00“
String clock(num seconds) {
  final s = seconds.round().clamp(0, 1 << 31);
  final h = s ~/ 3600, m = s % 3600 ~/ 60, x = s % 60;
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:${x.toString().padLeft(2, '0')}' : '$m:${x.toString().padLeft(2, '0')}';
}

/// Sekunden → „4:10“ (Pace)
String paceTxt(num? s) {
  if (s == null || !s.isFinite || s <= 0) return '–';
  final r = s.round();
  return '${r ~/ 60}:${(r % 60).toString().padLeft(2, '0')}';
}

/// Distanz je Sportart: Schwimmen mit zwei Nachkommastellen
String distTxt(Sport sport, num meters) {
  if (meters <= 0) return '';
  final km = meters / 1000;
  if (sport == Sport.swim) return '${de(km, meters % 1000 == 0 ? 1 : 2)} km';
  return '${de(km, sport == Sport.bike ? 0 : 1)} km';
}

/// Tempo-Hinweis für das Formular: /100m beim Schwimmen, km/h beim Rad, /km beim Laufen
String paceHint(Sport sport, num? meters, num? seconds) {
  if (meters == null || seconds == null || meters <= 0 || seconds <= 0) return '';
  final v = meters / seconds;
  switch (sport) {
    case Sport.swim:
      return 'Ø ${paceTxt(100 / v)} /100m';
    case Sport.bike:
      return 'Ø ${de(v * 3.6, 1)} km/h';
    case Sport.run:
      return 'Ø ${paceTxt(1000 / v)} /km';
    default:
      return '';
  }
}

/// „1:30“, „90“ oder „1h30“ → Minuten
int? parseDurationMinutes(String input) {
  final s = input.trim().toLowerCase().replaceAll(' ', '');
  if (s.isEmpty) return null;
  final hm = RegExp(r'^(\d{1,2})[:h.,](\d{1,2})m?(in)?$').firstMatch(s);
  if (hm != null) return int.parse(hm[1]!) * 60 + int.parse(hm[2]!);
  final h = RegExp(r'^(\d{1,2})h$').firstMatch(s);
  if (h != null) return int.parse(h[1]!) * 60;
  final m = RegExp(r'^(\d{1,4})(m|min)?$').firstMatch(s);
  if (m != null) return int.parse(m[1]!);
  return null;
}

/// Minuten → „1:30“
String minutesTxt(int minutes) => '${minutes ~/ 60}:${(minutes % 60).toString().padLeft(2, '0')}';

const _wd = ['Montag', 'Dienstag', 'Mittwoch', 'Donnerstag', 'Freitag', 'Samstag', 'Sonntag'];
const wdShort = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
const monthNames = ['Januar', 'Februar', 'März', 'April', 'Mai', 'Juni', 'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember'];

/// „Donnerstag, 22. Oktober“
String dayTitle(DateTime d) => '${_wd[d.weekday - 1]}, ${d.day}. ${monthNames[d.month - 1]}';

/// „22. Okt“
String shortDate(DateTime d) => '${d.day}. ${monthNames[d.month - 1].substring(0, 3)}';

/// „17:30“
String timeTxt(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

DateTime startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);
DateTime addDays(DateTime d, int n) => DateTime(d.year, d.month, d.day + n, d.hour, d.minute, d.second);
DateTime weekStart(DateTime d) => startOfDay(d).subtract(Duration(days: d.weekday - 1));
bool sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

/// ISO-Kalenderwoche
int isoWeek(DateTime d) {
  final thursday = startOfDay(d).add(Duration(days: 4 - d.weekday));
  final firstThursday = DateTime(thursday.year, 1, 4);
  final firstWeekStart = firstThursday.subtract(Duration(days: firstThursday.weekday - 1));
  return thursday.difference(firstWeekStart).inDays ~/ 7 + 1;
}
