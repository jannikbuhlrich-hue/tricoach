import 'dart:typed_data';

import 'models.dart';
import 'sport.dart';

/// FIT-Dateien (Garmin-Format) lesen und schreiben – Port von js/fit.js und dem Schreiber aus js/tp.js.
///
/// Lesen: Zusammenfassung je Session (Sportart, Start, Dauer, Distanz, Puls, Leistung, Bahnlänge).
/// Multisport-Dateien (Triathlon) werden in eine Einheit pro Disziplin aufgeteilt.
/// Schreiben: eine FIT-Datei pro Einheit, die TrainingPeaks, Garmin Connect, Strava und intervals.icu lesen.

const _epoch = 631065600; // 1989-12-31 UTC
const _size = {0: 1, 1: 1, 2: 1, 3: 2, 4: 2, 5: 4, 6: 4, 7: 1, 8: 4, 9: 8, 10: 1, 11: 2, 12: 4, 13: 1, 14: 8, 15: 8, 16: 8};

class FitException implements Exception {
  FitException(this.message);
  final String message;
  @override
  String toString() => message;
}

bool isFit(Uint8List b) => b.length > 12 && String.fromCharCodes(b.sublist(8, 12)) == '.FIT';

class _Field {
  const _Field(this.num, this.size, this.type);
  final int num, size, type;
}

class _Def {
  const _Def(this.global, this.big, this.fields, this.dev);
  final int global;
  final bool big;
  final List<_Field> fields;
  final int dev;
}

class FitMessage {
  FitMessage(this.global, this.v);
  final int global;
  final Map<int, int> v;
}

/// Alle Nachrichten einer FIT-Datei (nur Ganzzahl-Felder, ungültige Werte entfernt).
/// Kaputte oder abgeschnittene Dateien ergeben immer eine FitException, nie einen Absturz.
List<FitMessage> decodeFit(Uint8List b) {
  if (!isFit(b)) throw FitException('Keine FIT-Datei');
  try {
    return _decode(b);
  } on FitException {
    rethrow;
  } on RangeError {
    throw FitException('Datei abgeschnitten');
  }
}

List<FitMessage> _decode(Uint8List b) {
  final dv = ByteData.sublistView(b);
  final hs = b[0];
  final end = (hs + dv.getUint32(4, Endian.little)).clamp(0, b.length);
  final defs = <int, _Def>{};
  final msgs = <FitMessage>[];
  var i = hs, lastTs = 0;

  FitMessage read(_Def def) {
    final v = <int, int>{};
    final e = def.big ? Endian.big : Endian.little;
    for (final f in def.fields) {
      if (i + f.size > end) throw FitException('Datei abgeschnitten');
      final bt = f.type & 0x1f, sz = _size[bt];
      if (sz == f.size && bt != 7 && bt != 8 && bt != 9 && bt < 14) {
        int? x;
        switch (bt) {
          case 0:
          case 2:
          case 10:
          case 13:
            x = dv.getUint8(i);
            if (x == 0xff || (bt == 10 && x == 0)) x = null;
          case 1:
            x = dv.getInt8(i);
            if (x == 0x7f) x = null;
          case 3:
            x = dv.getInt16(i, e);
            if (x == 0x7fff) x = null;
          case 4:
          case 11:
            x = dv.getUint16(i, e);
            if (x == 0xffff || (bt == 11 && x == 0)) x = null;
          case 5:
            x = dv.getInt32(i, e);
            if (x == 0x7fffffff) x = null;
          case 6:
          case 12:
            x = dv.getUint32(i, e);
            if (x == 0xffffffff || (bt == 12 && x == 0)) x = null;
        }
        if (x != null) v[f.num] = x;
      }
      i += f.size;
    }
    i += def.dev;
    return FitMessage(def.global, v);
  }

  while (i < end) {
    final h = b[i++];
    if (h & 0x80 != 0) {
      // komprimierter Zeitstempel
      final def = defs[(h >> 5) & 3];
      if (def == null) throw FitException('Definition fehlt');
      final m = read(def), off = h & 0x1f;
      var ts = (lastTs & 0xffffffe0) + off;
      if (off < (lastTs & 0x1f)) ts += 0x20;
      lastTs = ts;
      m.v[253] = ts;
      msgs.add(m);
    } else if (h & 0x40 != 0) {
      // Definition
      final big = b[i + 1] == 1;
      final g = dv.getUint16(i + 2, big ? Endian.big : Endian.little);
      final n = b[i + 4];
      i += 5;
      final fields = <_Field>[];
      for (var k = 0; k < n; k++) {
        fields.add(_Field(b[i], b[i + 1], b[i + 2]));
        i += 3;
      }
      var dev = 0;
      if (h & 0x20 != 0) {
        final dn = b[i++];
        for (var k = 0; k < dn; k++) {
          dev += b[i + 1];
          i += 3;
        }
      }
      defs[h & 0x0f] = _Def(g, big, fields, dev);
    } else {
      final def = defs[h & 0x0f];
      if (def == null) throw FitException('Definition fehlt');
      final m = read(def);
      if (m.v[253] != null) lastTs = m.v[253]!;
      msgs.add(m);
    }
  }
  return msgs;
}

const _sportOf = {1: Sport.run, 2: Sport.bike, 5: Sport.swim, 10: Sport.strength};
const _otherArt = {44: 'Kitesurfen', 43: 'Windsurfen', 37: 'SUP', 38: 'Surfen', 41: 'Kajak', 17: 'Wandern', 15: 'Rudern', 13: 'Ski', 12: 'Ski', 19: 'Paddeln', 11: 'Spaziergang', 31: 'Klettern'};

DateTime _date(int ts) => DateTime.fromMillisecondsSinceEpoch((ts + _epoch) * 1000, isUtc: true);

/// FIT-Datei → Einheiten (eine pro Session). [fileId] macht die ID stabil: gleiche Datei = gleiche ID.
List<Activity> activitiesFromFit(Uint8List bytes, String fileId) {
  final msgs = decodeFit(bytes);
  final sessions = msgs.where((m) => m.global == 18 && m.v[2] != null).toList();
  final records = msgs.where((m) => m.global == 20 && m.v[253] != null).toList();
  final out = <Activity>[];
  for (var idx = 0; idx < sessions.length; idx++) {
    final sv = sessions[idx].v;
    final t0 = sv[2]!;
    final durS = ((sv[7] ?? sv[8] ?? 0) / 1000).round();
    if (durS <= 60) continue;
    final t1 = t0 + durS + 1;
    final sport = _sportOf[sv[5]] ?? Sport.other;
    // Puls aus den Messpunkten, falls die Zusammenfassung keinen hat
    var avgHr = sv[16], maxHr = sv[17];
    if (avgHr == null) {
      final hrs = [for (final r in records) if (r.v[253]! >= t0 && r.v[253]! <= t1 && r.v[3] != null) r.v[3]!];
      if (hrs.isNotEmpty) {
        avgHr = (hrs.reduce((a, b) => a + b) / hrs.length).round();
        maxHr ??= hrs.reduce((a, b) => a > b ? a : b);
      }
    }
    SwimWhere? where;
    if (sport == Sport.swim) {
      final pool = sv[44] != null ? sv[44]! / 100 : null;
      where = pool == null || sv[6] == 18 ? SwimWhere.openWater : (pool >= 45 ? SwimWhere.pool50 : SwimWhere.pool25);
    }
    final id = '$fileId${sessions.length > 1 ? '-$idx' : ''}';
    out.add(Activity(
      id: 'fit-$id',
      sport: sport,
      art: sport == Sport.other ? _otherArt[sv[5]] : null,
      start: _date(t0),
      durationS: durS,
      distanceM: (sv[9] ?? 0) / 100,
      avgHr: avgHr,
      maxHr: maxHr,
      kcal: sv[11],
      swimWhere: where,
      source: 'fit',
      extId: id,
      details: {
        if (sport == Sport.bike && sv[34] != null) 'np': sv[34],
        if (sv[20] != null) 'ap': sv[20],
        if (sv[22] != null) 'elev': sv[22],
        if (sv[24] != null) 'te': sv[24]! / 10,
      },
    ));
  }
  return out;
}

// ---------------------------------------------------------------- Schreiben

const _fitSport = {Sport.bike: (2, 0), Sport.run: (1, 0), Sport.strength: (10, 20)};
const _fitOther = {'Kitesurfen': (44, 0), 'Windsurfen': (43, 0), 'Surfen': (38, 0), 'SUP': (37, 0), 'Wandern': (17, 0), 'Rudern': (15, 0), 'Yoga': (10, 43), 'Ski': (13, 0), 'Spaziergang': (11, 0), 'Klettern': (31, 0)};
const _crcT = [0x0000, 0xCC01, 0xD801, 0x1400, 0xF001, 0x3C00, 0x2800, 0xE401, 0xA001, 0x6C00, 0x7800, 0xB401, 0x5000, 0x9C01, 0x8801, 0x4400];

int fitCrc(List<int> bytes, [int crc = 0]) {
  for (final b in bytes) {
    var t = _crcT[crc & 0xF];
    crc = (crc >> 4) & 0x0FFF;
    crc = crc ^ t ^ _crcT[b & 0xF];
    t = _crcT[crc & 0xF];
    crc = (crc >> 4) & 0x0FFF;
    crc = crc ^ t ^ _crcT[(b >> 4) & 0xF];
  }
  return crc;
}

/// Basistypen: (Größe, FIT-Typ-Code, ungültiger Wert)
const _ft = {
  'enum': (1, 0x00, 0xFF),
  'u8': (1, 0x02, 0xFF),
  'u16': (2, 0x84, 0xFFFF),
  'u32': (4, 0x86, 0xFFFFFFFF),
  'u32z': (4, 0x8C, 0),
};

/// Eine Einheit als FIT-Datei (gleicher Aufbau wie buildFit() in js/tp.js, geprüft mit dem Garmin FIT SDK)
Uint8List buildFit(Activity a, {int Function(Sport, int, int?)? kcalEstimate}) {
  final out = <int>[];
  List<int> w16(int v) => [v & 0xFF, (v >> 8) & 0xFF];
  List<int> w32(int v) => [v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF];
  List<int> enc(String t, num? v) {
    final (size, _, na) = _ft[t]!;
    final x = v == null || !v.isFinite ? na : v.round();
    return size == 1 ? [x & 0xFF] : size == 2 ? w16(x) : w32(x & 0xFFFFFFFF);
  }

  var local = 0;
  void msg(int global, List<(int, String)> fields, List<List<num?>> rows) {
    final l = local++ & 0xF;
    out
      ..addAll([0x40 | l, 0, 0, ...w16(global), fields.length])
      ..addAll([for (final (n, t) in fields) ...[n, _ft[t]!.$1, _ft[t]!.$2]]);
    for (final vals in rows) {
      out.add(l);
      for (var i = 0; i < fields.length; i++) {
        out.addAll(enc(fields[i].$2, vals[i]));
      }
    }
  }

  final t0 = a.start.toUtc().millisecondsSinceEpoch ~/ 1000 - _epoch;
  final dur = a.durationS < 60 ? 60 : a.durationS, t1 = t0 + dur;
  final dist = (a.distanceM * 100).round();
  final (sport, sub) = a.sport == Sport.swim
      ? (5, a.swimWhere == SwimWhere.openWater ? 18 : a.swimWhere != null ? 17 : 0)
      : _fitSport[a.sport] ?? _fitOther[a.art] ?? (0, 0);
  final hr = a.avgHr, mx = a.maxHr ?? hr;
  final kcal = a.kcal ?? kcalEstimate?.call(a.sport, dur, a.rpe);
  final tzOff = a.start.toLocal().timeZoneOffset.inSeconds;

  msg(0, [(0, 'enum'), (1, 'u16'), (2, 'u16'), (3, 'u32z'), (4, 'u32')], [[4, 255, 1, (t0 % 4000000000) + 1, t0]]); // file_id
  msg(49, [(0, 'u16'), (1, 'u16')], [[1, 220]]); // file_creator
  msg(21, [(253, 'u32'), (0, 'enum'), (1, 'enum')], [[t0, 0, 0]]); // Timer Start
  final recs = <List<num?>>[[t0, 0, hr]];
  if (dist > 0 || hr != null) {
    final n = (dur ~/ 60).clamp(1, 60);
    for (var i = 1; i <= n; i++) {
      recs.add([t0 + (dur * i / n).round(), (dist * i / n).round(), hr]);
    }
  } else {
    recs.add([t1, 0, hr]);
  }
  msg(20, [(253, 'u32'), (5, 'u32'), (3, 'u8')], recs); // record
  msg(21, [(253, 'u32'), (0, 'enum'), (1, 'enum')], [[t1, 0, 4]]); // Timer Stop
  const sum = [(253, 'u32'), (2, 'u32'), (7, 'u32'), (8, 'u32'), (9, 'u32'), (11, 'u16'), (0, 'enum'), (1, 'enum')];
  msg(19, [...sum, (15, 'u8'), (16, 'u8'), (25, 'enum'), (39, 'enum')], [[t1, t0, dur * 1000, dur * 1000, dist, kcal, 9, 1, hr, mx, sport, sub]]); // lap
  final lane = sport == 5 ? a.swimWhere?.poolLength : null;
  msg(18, [...sum, (16, 'u8'), (17, 'u8'), (5, 'enum'), (6, 'enum'), (25, 'u16'), (26, 'u16'), if (lane != null) ...[(44, 'u16'), (46, 'enum')]], [
    [t1, t0, dur * 1000, dur * 1000, dist, kcal, 8, 1, hr, mx, sport, sub, 0, 1, if (lane != null) ...[lane * 100, 0]]
  ]); // session
  msg(34, [(253, 'u32'), (0, 'u32'), (1, 'u16'), (2, 'enum'), (3, 'enum'), (4, 'enum'), (5, 'u32')], [[t1, dur * 1000, 1, 1, 26, 1, t1 + tzOff]]); // activity

  final hdr = [14, 0x20, ...w16(2132), ...w32(out.length), 0x2E, 0x46, 0x49, 0x54];
  final all = [...hdr, ...w16(fitCrc(hdr)), ...out];
  return Uint8List.fromList([...all, ...w16(fitCrc(all))]);
}

/// Dateiname wie in der Web-App: TriCoach_2026-10-20_1700_Schwimmen.fit
String fitFileName(Activity a) {
  final s = a.start.toLocal();
  String p(int v) => v.toString().padLeft(2, '0');
  final title = a.title.replaceAll(RegExp(r'[^\wäöüÄÖÜß-]+'), '-');
  return 'TriCoach_${s.year}-${p(s.month)}-${p(s.day)}_${p(s.hour)}${p(s.minute)}_${title.length > 30 ? title.substring(0, 30) : title}.fit';
}
