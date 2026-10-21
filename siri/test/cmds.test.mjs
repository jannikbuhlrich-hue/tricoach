import { load } from './harness.mjs';
import { encrypt, decrypt } from '../../tools/untis-sync.mjs';
import { readFileSync } from 'node:fs';
import assert from 'node:assert';
const K = 'test-key-123';
// Schuldaten: echte Struktur, eigene Testwerte
const sd = { at: '2026-10-26T05:00:00Z', err: [], news: [],
  lessons: [
    { id: 1, d: '2026-10-27', s: '08:00', e: '08:45', su: 'BioG2', sul: 'Biologie', ro: 'OG101', roOrg: '', te: 'KUR', teOrg: '', code: '', info: '', subst: '', ls: '' },
    { id: 2, d: '2026-10-27', s: '08:45', e: '09:30', su: 'BioG2', sul: 'Biologie', ro: 'OG101', roOrg: '', te: 'KUR', teOrg: '', code: '', info: '', subst: '', ls: '' },
    { id: 3, d: '2026-10-27', s: '09:50', e: '10:35', su: 'MatL1', sul: '', ro: 'R12', roOrg: '', te: 'X', teOrg: '', code: 'cancelled', info: '', subst: '', ls: '' },
    { id: 4, d: '2026-10-27', s: '10:35', e: '11:20', su: 'MatL1', sul: '', ro: 'R12', roOrg: '', te: 'X', teOrg: '', code: 'cancelled', info: '', subst: '', ls: '' },
    { id: 5, d: '2026-10-27', s: '11:40', e: '12:25', su: 'EnG1', sul: 'Englisch', ro: 'R5', roOrg: 'R3', te: 'Y', teOrg: '', code: 'irregular', info: 'Vokabeltest', subst: 'Raumänderung', ls: '' },
    { id: 6, d: '2026-10-28', s: '08:00', e: '13:15', su: 'DeG1', sul: 'Deutsch', ro: 'R1', roOrg: '', te: 'Z', teOrg: '', code: '', info: '', subst: '', ls: '' }],
  homework: [{ id: 9, su: 'MatL1', text: 'S. 135/6, AB 2a-d', remark: '', date: '2026-10-20', due: '2026-10-28', done: false }, { id: 10, su: 'DeG1', text: 'Gedicht', due: '2026-10-20', done: false }],
  exams: [{ id: 3725, d: '2026-10-27', s: '08:00', e: '09:30', su: 'BioG2', name: 'BioG2', type: 'Klausur', text: 'Biologieklausur', ro: 'OG101' }, { id: 3726, d: '2026-11-10', s: '10:00', su: 'MatL1', type: 'Klausur', text: '' }] };
const ics = ['BEGIN:VCALENDAR', 'BEGIN:VEVENT', 'UID:tp1', 'DTSTART;VALUE=DATE:20261027', 'SUMMARY:🏃 Run: Easy 45min', 'DESCRIPTION:Planned Time: 0:45:00\\nlocker Z2', 'END:VEVENT',
  'BEGIN:VEVENT', 'UID:tp2', 'DTSTART;VALUE=DATE:20261027', 'SUMMARY:🏊 Swim: CSS Intervalle', 'DESCRIPTION:Planned Time: 1:00:00', 'END:VEVENT',
  'BEGIN:VEVENT', 'UID:tp3', 'DTSTART;VALUE=DATE:20270530', 'SUMMARY:Triathlon Cuxhaven', 'END:VEVENT', 'END:VCALENDAR'].join('\r\n');
const encS = await encrypt(sd, K), encT = await encrypt({ at: 'x', n: 3, ics }, K);
const posted = [];
const routes = {
  'schule-daten/schule.enc': () => ({ body: encS }), 'tp-daten/tp.enc': () => ({ body: encT }),
  'intervals.icu/api/v1/athlete/0/activities/manual': r => { posted.push(JSON.parse(r.body)); return { status: 201, body: '{"id":"i99"}' }; },
  'intervals.icu/api/v1/athlete/0/activities\\?': r => ({ body: JSON.stringify([
    { id: 'i1', name: 'Morgenlauf', type: 'Run', start_date_local: '2026-10-26T07:10:00', moving_time: 2700, distance: 9100, average_heartrate: 148.4, max_heartrate: 171, icu_training_load: 52 },
    { id: 'i2', name: 'Schwimmen', type: 'Swim', start_date_local: '2026-10-27T06:30:00', moving_time: 3300, distance: 2350, average_heartrate: 131 }]) }),
  'intervals.icu/api/v1/athlete/0/events': () => ({ body: JSON.stringify([{ id: 5, category: 'WORKOUT', name: 'Rad Grundlage', type: 'Ride', start_date_local: '2026-10-28T00:00:00', moving_time: 5400 }, { id: 6, category: 'RACE_A', name: 'Stadttriathlon', start_date_local: '2026-11-20T00:00:00' }]) }),
  'intervals.icu/api/v1/athlete/0/wellness': () => ({ body: JSON.stringify([{ id: '2026-10-25', ctl: 41, atl: 47, hrv: 70, restingHR: 47 }, { id: '2026-10-26', ctl: 42.3, atl: 55.1, hrv: 58, restingHR: 52, sleepSecs: 26100, sleepScore: 78 }]) }),
};
const { api, sandbox } = await load({ routes, cfg: { key: K, icu: 'icukey', repo: 'jannikbuhlrich-hue/tricoach' }, now: '2026-10-26T20:15:00' });
const say = async q => { const r = await api.run(q); const t = typeof r === 'string' ? r : r.text; console.log(`\n» ${q}\n  ${t}`); return r; };
const t1 = await say('Was steht morgen an');
assert.match(t1, /Morgen, Dienstag/); assert.match(t1, /Schule 8 bis 12:25/); assert.match(t1, /Entfall: Mathe um 9:50/); assert.match(t1, /Klausur in Biologie/); assert.match(t1, /Run: Easy 45min/); assert.match(t1, /Raum R5 statt R3/);
assert.match(t1, /Mathe: S. 135/);
await say('heute');
await say('Mittwoch');
const w = await say('wie war meine Woche'); assert.match(w, /Laufen 9,1 Kilometer/);
const f = await say('wie ist meine form'); assert.match(f, /Form minus 13/); assert.match(f, /unter deinem Schnitt/);
await say('gibt es vertretung');
const hw = await say('welche hausaufgaben habe ich'); assert.match(hw, /1 offene Hausaufgabe/);
await say('wann ist die nächste klausur');
const rc = await say('nächster wettkampf'); assert.match(rc, /Stadttriathlon/);
await say('letzte einheit');
await say('hilfe');
const lg = await say('eintragen Lauf 45 Minuten 9,5 Kilometer locker Puls 145');
assert.equal(posted[0].type, 'Run'); assert.equal(posted[0].moving_time, 2700); assert.equal(posted[0].distance, 9500); assert.equal(posted[0].average_heartrate, 145); assert.ok(lg.saved); assert.equal(JSON.parse(JSON.stringify(lg.health)).typ, 'Laufen');
await say('trag ein kitesurfen anderthalb stunden'); assert.equal(posted[1].type, 'Kitesurf'); assert.equal(posted[1].moving_time, 5400);
await say('eintragen Schwimmen 2,35 km 55 min 50er Bahn'); assert.equal(posted[2].distance, 2350);
await say('eintragen gestern um 18 uhr athletik 40 minuten hart'); assert.equal(posted[3].type, 'WeightTraining'); assert.equal(posted[3].start_date_local, '2026-10-25T18:00:00');
await say('eintragen Lauf');
await say('eintragen 30 minuten');
// Parser-Einzelfälle
const P = s => api.parseLog(s, new Date('2026-10-26T20:00:00'));
const cases = [['Radfahrt 2 Stunden 15 Minuten 62 km', 'bike', 8100, 62000], ['Lauf 1:05 h 12 km', 'run', 3900, 12000], ['eine Stunde laufen zehn Kilometer', 'run', 3600, 10000], ['Freiwasser 1500 m 30 min', 'swim', 1800, 1500], ['40 bahnen schwimmen 50 minuten', 'swim', 3000, 1000], ['dreiviertel stunde stabi', 'strength', 2700, 0], ['fünfundvierzig minuten joggen', 'run', 2700, 0]];
for (const [s, sp, d, m] of cases) { const o = P(s); assert.equal(o.sport, sp, s); assert.equal(o.dur, d, s + ' dur ' + o.dur); assert.equal(o.dist, m, s + ' dist ' + o.dist); }
assert.equal(P('Freiwasser 1500 m 30 min').where, 'ow');
// Widget
const wd = await api.buildWidget(new Date('2026-10-27T07:00:00'));
console.log('\nWidget:', wd.items.map(i => i.text).join(' | '));
// Einrichtung per Link
const setup = Buffer.from(JSON.stringify({ k: 'neu', i: 'abc', r: 'x/y', s: 'TriCoach', w: 68 })).toString('base64url');
console.log('\nSetup:', api.setupFrom(setup));
console.log('\nALLE TESTS OK');
