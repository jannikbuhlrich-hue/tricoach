import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/school.dart';
import '../state/app_state.dart';
import 'theme.dart';
import 'widgets.dart';

const _wdShort = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];

String _dueTxt(DateTime due, DateTime today) {
  final d = due.difference(today).inDays;
  if (d < 0) return 'überfällig';
  if (d == 0) return 'heute';
  if (d == 1) return 'bis morgen';
  return 'bis ${_wdShort[due.weekday - 1]}, ${shortDate(due)}';
}

/// Schule in „Mein Tag“: Stunden des Tages (mit Entfall/Vertretung), offene Hausaufgaben, Prüfungen.
/// Wie vToday() in js/school.js. Erscheint nur, wenn der TriCoach-Schlüssel eingetragen ist.
class SchoolCard extends StatelessWidget {
  const SchoolCard({super.key, required this.day, required this.title});
  final DateTime day;
  final String title;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context), c = TriColors.of(context), s = app.school;
    if (s == null) {
      if (app.schoolError == null) return const SizedBox.shrink();
      return TriCard(title: 'Schule', icon: Icons.school_rounded, child: Text(app.schoolError!, style: TextStyle(color: c.warn)));
    }
    final today = startOfDay(DateTime.now());
    final lessons = s.lessonsOn(day);
    final ends = s.schoolEnds(day);
    final hw = s.openHomework(app.hwDone).where((h) => h.dueDay.isBefore(addDays(today, 8))).toList();
    final exams = s.examsAhead(today, 14);
    final news = sameDay(day, today) ? s.news : const <SchoolNews>[];

    return TriCard(
      title: title,
      icon: Icons.school_rounded,
      trailing: Text(ends == null ? 'frei' : 'bis ${timeTxt(ends)}', style: TextStyle(color: c.muted, fontSize: 13)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (lessons.isEmpty)
          const EmptyHint('Kein Unterricht', 'Laut WebUntis ist an diesem Tag frei.', icon: Icons.beach_access_rounded)
        else
          for (final l in lessons) _LessonRow(l, s),
        for (final n in news)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.campaign_rounded, size: 16, color: c.muted),
              const SizedBox(width: 6),
              Expanded(child: Text([n.subject, n.text].where((x) => x.isNotEmpty).join(': '), style: TextStyle(color: c.muted, fontSize: 13))),
            ]),
          ),
        if (exams.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('Prüfungen', style: TextStyle(fontWeight: FontWeight.w700, color: c.fg)),
          for (final x in exams)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.edit_note_rounded, size: 16, color: x.startsAt.difference(today).inDays <= 3 ? c.warn : c.fg),
                const SizedBox(width: 6),
                Expanded(child: Text(
                '${x.name.isNotEmpty ? x.name : 'Prüfung'}${x.su.isNotEmpty ? ' · ${s.subjectName(x.su)}' : ''} · '
                '${_wdShort[x.startsAt.weekday - 1]}, ${shortDate(x.startsAt)}${x.start.isNotEmpty ? ' ${x.start}' : ''}${x.ro.isNotEmpty ? ' · ${x.ro}' : ''}',
                style: TextStyle(color: x.startsAt.difference(today).inDays <= 3 ? c.warn : c.fg, fontSize: 13),
              )),
              ]),
            ),
        ],
        if (hw.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('Hausaufgaben', style: TextStyle(fontWeight: FontWeight.w700, color: c.fg)),
          for (final h in hw)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              value: s.isDone(h, app.hwDone),
              onChanged: (_) => app.toggleHomework(h),
              title: Text('${s.subjectName(h.su)}: ${h.text}', maxLines: 3, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                [_dueTxt(h.dueDay, today), if (h.remark.isNotEmpty) h.remark].join(' · '),
                style: TextStyle(color: h.dueDay.isBefore(today) ? c.bad : h.dueDay.difference(today).inDays <= 1 ? c.warn : c.muted, fontSize: 12),
              ),
            ),
        ],
        const SizedBox(height: 8),
        Text(
          'WebUntis · Stand ${shortDate(s.at.toLocal())} ${timeTxt(s.at.toLocal())}${app.schoolError != null ? ' · ${app.schoolError}' : ''}',
          style: TextStyle(color: app.schoolError != null ? c.warn : c.faint, fontSize: 11),
        ),
      ]),
    );
  }
}

class _LessonRow extends StatelessWidget {
  const _LessonRow(this.l, this.s);
  final Lesson l;
  final SchoolData s;

  @override
  Widget build(BuildContext context) {
    final c = TriColors.of(context);
    final col = l.cancelled ? c.bad : (l.irregular || l.subst.isNotEmpty) ? c.warn : c.fg;
    final note = l.note;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 52,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l.start, style: TextStyle(fontWeight: FontWeight.w600, color: col, fontSize: 13)),
            Text(l.end, style: TextStyle(color: c.faint, fontSize: 11)),
          ]),
        ),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              s.subjectName(l.su, l.sul),
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: col,
                decoration: l.cancelled ? TextDecoration.lineThrough : null,
              ),
            ),
            if (l.ro.isNotEmpty || l.te.isNotEmpty) Text([l.ro, l.te].where((x) => x.isNotEmpty).join(' · '), style: TextStyle(color: c.muted, fontSize: 12)),
            if (note.isNotEmpty) Text(note, style: TextStyle(color: col, fontSize: 12, fontStyle: FontStyle.italic)),
          ]),
        ),
      ]),
    );
  }
}
