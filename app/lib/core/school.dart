import 'format.dart';

/// Schule aus WebUntis – Format von tools/untis-sync.mjs (GitHub-Job „Schule (WebUntis)“).
/// Stunden mit Entfall/Vertretung/Raumänderung, Hausaufgaben, Prüfungen und Nachrichten des Tages.

String _s(Object? v) => v == null ? '' : '$v';

/// „2026-10-22“ + „07:45“ → lokale Uhrzeit
DateTime lessonTime(String day, String hhmm) {
  final d = day.split('-').map(int.parse).toList();
  final t = (hhmm.isEmpty ? '08:00' : hhmm).split(':').map(int.parse).toList();
  return DateTime(d[0], d[1], d[2], t[0], t.length > 1 ? t[1] : 0);
}

String isoDay(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class Lesson {
  Lesson({
    required this.id,
    required this.day,
    required this.start,
    required this.end,
    this.su = '',
    this.sul = '',
    this.ro = '',
    this.roOrg = '',
    this.te = '',
    this.teOrg = '',
    this.code = '',
    this.info = '',
    this.subst = '',
    this.ls = '',
  });

  factory Lesson.fromJson(Map<String, dynamic> j) => Lesson(
        id: _s(j['id']),
        day: _s(j['d']),
        start: _s(j['s']),
        end: _s(j['e']),
        su: _s(j['su']),
        sul: _s(j['sul']),
        ro: _s(j['ro']),
        roOrg: _s(j['roOrg']),
        te: _s(j['te']),
        teOrg: _s(j['teOrg']),
        code: _s(j['code']),
        info: _s(j['info']),
        subst: _s(j['subst']),
        ls: _s(j['ls']),
      );

  final String id, day, start, su, sul, ro, roOrg, te, teOrg, code, info, subst, ls;
  String end;

  bool get cancelled => code == 'cancelled';
  bool get irregular => code == 'irregular';

  /// Etwas weicht vom normalen Plan ab (Entfall, Vertretung, Raum, Hinweis der Lehrkraft)
  bool get changed => code.isNotEmpty || info.isNotEmpty || subst.isNotEmpty;
  DateTime get startsAt => lessonTime(day, start);
  DateTime get endsAt => lessonTime(day, end);

  /// Kurztext der Änderung, z. B. „Entfall · Aufgaben im Moodle-Kurs“ oder „Vertretung · Raum R 110 → R 204“
  String get note => [
        if (cancelled) 'Entfall' else if (irregular) (subst.isNotEmpty ? subst : 'Änderung') else if (subst.isNotEmpty) subst,
        if (roOrg.isNotEmpty) 'Raum $roOrg → $ro',
        if (teOrg.isNotEmpty) '$teOrg → $te',
        if (info.isNotEmpty) info,
      ].join(' · ');

  Lesson copy() => Lesson(id: id, day: day, start: start, end: end, su: su, sul: sul, ro: ro, roOrg: roOrg, te: te, teOrg: teOrg, code: code, info: info, subst: subst, ls: ls);
}

class Homework {
  Homework({required this.id, this.su = '', this.text = '', this.remark = '', required this.date, required this.due, this.done = false});

  factory Homework.fromJson(Map<String, dynamic> j) => Homework(
        id: _s(j['id']),
        su: _s(j['su']),
        text: _s(j['text']),
        remark: _s(j['remark']),
        date: _s(j['date']),
        due: _s(j['due']),
        done: j['done'] == true,
      );

  final String id, su, text, remark, date, due;

  /// Haken aus WebUntis (eigene Haken in der App kommen über [SchoolData.isDone])
  final bool done;
  DateTime get dueDay => lessonTime(due, '00:00');
}

class Exam {
  Exam({required this.id, required this.day, this.start = '', this.end = '', this.su = '', this.name = '', this.type = '', this.text = '', this.ro = ''});

  factory Exam.fromJson(Map<String, dynamic> j) => Exam(
        id: _s(j['id']),
        day: _s(j['d']),
        start: _s(j['s']),
        end: _s(j['e']),
        su: _s(j['su']),
        name: _s(j['name']),
        type: _s(j['type']),
        text: _s(j['text']),
        ro: _s(j['ro']),
      );

  final String id, day, start, end, su, name, type, text, ro;
  DateTime get startsAt => lessonTime(day, start);
}

class SchoolNews {
  SchoolNews(this.subject, this.text);
  final String subject, text;
}

const _subj = {
  'M': 'Mathe', 'MA': 'Mathe', 'MAT': 'Mathe', 'DE': 'Deutsch', 'EN': 'Englisch', 'D': 'Deutsch', 'E': 'Englisch', 'F': 'Französisch', 'L': 'Latein',
  'S': 'Spanisch', 'BIO': 'Biologie', 'BI': 'Biologie', 'CH': 'Chemie', 'PH': 'Physik', 'GE': 'Geschichte', 'EK': 'Erdkunde', 'POL': 'Politik',
  'PW': 'Politik', 'SW': 'Sozialwiss.', 'WI': 'Wirtschaft', 'INF': 'Informatik', 'IF': 'Informatik', 'KU': 'Kunst', 'MU': 'Musik', 'SP': 'Sport',
  'RE': 'Religion', 'ER': 'ev. Religion', 'KR': 'kath. Religion', 'PL': 'Philosophie', 'WN': 'Werte & Normen', 'DS': 'Darst. Spiel',
};

class SchoolData {
  SchoolData({required this.at, required this.lessons, required this.homework, required this.exams, required this.news, this.err = const [], required this.raw});

  /// [raw] ist das entschlüsselte JSON – wird so gespeichert, damit nichts verloren geht
  factory SchoolData.fromJson(Map<String, dynamic> j) {
    List<Map<String, dynamic>> list(String k) => [for (final x in (j[k] as List? ?? const [])) if (x is Map) Map<String, dynamic>.from(x)];
    return SchoolData(
      at: DateTime.tryParse(_s(j['at'])) ?? DateTime.now(),
      lessons: list('lessons').map(Lesson.fromJson).where((l) => l.day.length == 10 && l.start.isNotEmpty).toList(),
      homework: list('homework').map(Homework.fromJson).where((h) => h.due.length == 10).toList(),
      exams: list('exams').map(Exam.fromJson).where((x) => x.day.length == 10).toList(),
      news: list('news').map((m) => SchoolNews(_s(m['subject']), _s(m['text']))).where((m) => m.subject.isNotEmpty || m.text.isNotEmpty).toList(),
      err: [for (final e in (j['err'] as List? ?? const [])) '$e'],
      raw: j,
    );
  }

  final DateTime at;
  final List<Lesson> lessons;
  final List<Homework> homework;
  final List<Exam> exams;
  final List<SchoolNews> news;
  final List<String> err;
  final Map<String, dynamic> raw;

  /// Fachname: Langname aus WebUntis, sonst aus den Stunden desselben Kurses (z. B. „MatL1“ → Mathematik), sonst Kürzel-Liste
  String subjectName(String su, [String long = '']) {
    if (long.isNotEmpty && long != su) return long;
    if (su.isEmpty) return '';
    for (final l in lessons) {
      if (l.su == su && l.sul.isNotEmpty && l.sul != su) return l.sul;
    }
    final up = su.toUpperCase();
    if (_subj.containsKey(up)) return _subj[up]!;
    final pre = (_subj.keys.where((k) => k.length >= 2 && up.startsWith(k)).toList()..sort((a, b) => b.length - a.length)).firstOrNull;
    if (pre != null) return _subj[pre]!;
    if (_subj.containsKey(up[0]) && RegExp(r'^[A-Z][^A-Z]').hasMatch(su)) return _subj[up[0]]!;
    return su;
  }

  /// Stunden eines Tages; Doppelstunden (gleiches Fach, Raum, Lehrkraft, ≤ 10 min Pause) werden zusammengefasst
  List<Lesson> lessonsOn(DateTime day) {
    final k = isoDay(day);
    final ls = lessons.where((l) => l.day == k).toList()
      ..sort((a, b) {
        final c = a.start.compareTo(b.start);
        return c != 0 ? c : (a.cancelled ? 1 : 0) - (b.cancelled ? 1 : 0);
      });
    final out = <Lesson>[];
    for (final l in ls) {
      final p = out.isEmpty ? null : out.last;
      final gap = p == null ? 99 : l.startsAt.difference(p.endsAt).inMinutes;
      if (p != null && p.su == l.su && p.code == l.code && p.ro == l.ro && p.te == l.te && p.info == l.info && gap >= 0 && gap <= 10) {
        p.end = l.end;
      } else {
        out.add(l.copy());
      }
    }
    return out;
  }

  /// Änderungen (Entfall, Vertretung, Hinweise) zwischen [from] und [to]
  List<Lesson> changes(DateTime from, DateTime to) => [
        for (var d = startOfDay(from); d.isBefore(to); d = addDays(d, 1)) ...lessonsOn(d).where((l) => l.changed),
      ];

  /// Erledigt? Eigener Haken in der App geht vor dem Haken aus WebUntis
  bool isDone(Homework h, Map<String, bool> mine) => mine['u${h.id}'] ?? h.done;

  /// Offene Hausaufgaben, nach Fälligkeit sortiert
  List<Homework> openHomework(Map<String, bool> mine) => homework.where((h) => !isDone(h, mine)).toList()..sort((a, b) => a.due.compareTo(b.due));

  /// Prüfungen in den nächsten [days] Tagen ab [today]
  List<Exam> examsAhead(DateTime today, int days) {
    final from = startOfDay(today), to = addDays(from, days);
    return exams.where((x) => !x.startsAt.isBefore(from) && x.startsAt.isBefore(to)).toList()..sort((a, b) => a.startsAt.compareTo(b.startsAt));
  }

  /// Unterrichtsende des Tages (letzte Stunde, die nicht ausfällt) – praktisch fürs Trainingsfenster
  DateTime? schoolEnds(DateTime day) {
    final ls = lessonsOn(day).where((l) => !l.cancelled).toList();
    return ls.isEmpty ? null : ls.map((l) => l.endsAt).reduce((a, b) => a.isAfter(b) ? a : b);
  }
}
