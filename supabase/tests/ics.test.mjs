// node supabase/tests/ics.test.mjs
import assert from 'node:assert/strict';
import { buildCalendar, escapeText, fold, utc } from '../functions/calendar/ics.js';

assert.equal(escapeText('a,b;c\\d\ne'), 'a\\,b\\;c\\\\d\\ne');
assert.equal(utc('2026-10-24T15:00:00.000Z'), '20261024T150000Z');

// Faltung: keine Zeile über 75 Byte, Umlaute/Emoji bleiben ganz
const long = 'SUMMARY:' + 'Schwimmen 🏊 Ähre '.repeat(10);
const folded = fold(long);
for (const l of folded.split('\r\n')) assert.ok(new TextEncoder().encode(l).length <= 75, 'Zeile zu lang: ' + l);
assert.equal(folded.split('\r\n ').join(''), long);

const now = new Date('2026-10-22T10:00:00Z');
const ics = buildCalendar({
  name: 'TriCoach – Jannik',
  now,
  activities: [
    { id: 'a1', sport: 'swim', name: 'CSS 10×100', start_at: '2026-10-20T15:00:00Z', duration_s: 3300, distance_m: 2350, avg_hr: 142, rpe: 6, tss: 61.4, notes: 'Hauptserie, gut' },
    { id: 'a2', sport: 'other', art: 'Kitesurfen', name: '', start_at: '2026-10-19T12:00:00Z', duration_s: 7200, distance_m: 0 },
    { id: 'gone', sport: 'run', name: 'gelöscht', start_at: '2026-10-18T12:00:00Z', duration_s: 1800, deleted_at: '2026-10-19T00:00:00Z' }
  ],
  planned: [
    { id: 'p1', kind: 'workout', sport: 'run', title: 'Schwelle 5×1 km', starts_at: '2026-10-24T15:00:00Z', minutes: 60, notes: '90 s Trabpause' },
    { id: 'r1', kind: 'race', sport: null, title: 'Stadttriathlon', starts_at: '2027-06-01T00:00:00Z', all_day: true, race_prio: 'A' }
  ]
});

const lines = ics.split('\r\n');
assert.equal(lines[0], 'BEGIN:VCALENDAR');
assert.equal(lines.at(-2), 'END:VCALENDAR');
assert.ok(ics.endsWith('\r\n'));
assert.equal((ics.match(/BEGIN:VEVENT/g) || []).length, 4, 'gelöschte Einheit darf nicht erscheinen');
assert.ok(!ics.includes('gelöscht'));
assert.ok(ics.includes('UID:act-a1@tricoach.app'));
assert.ok(ics.includes('DTSTART:20261020T150000Z') && ics.includes('DTEND:20261020T155500Z'));
assert.ok(ics.includes('2\\,35 km'), 'Schwimm-km mit Komma');
assert.ok(ics.includes('Kitesurfen'));
assert.ok(ics.includes('DTSTART;VALUE=DATE:20270601') && ics.includes('DTEND;VALUE=DATE:20270602'));
assert.ok(ics.includes('A-Wettkampf: Stadttriathlon'));
assert.ok(ics.includes('TRIGGER:-PT1H'));
for (const l of lines) assert.ok(new TextEncoder().encode(l).length <= 75, 'Zeile zu lang');

console.log('OK  Kalender-Datei (.ics): alle Tests bestanden');
