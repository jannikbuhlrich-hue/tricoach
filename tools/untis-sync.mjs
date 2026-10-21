// TriCoach – WebUntis-Abruf für den GitHub-Job (.github/workflows/schule.yml)
// Holt Stundenplan (inkl. Ausfall/Vertretung/Infos), Hausaufgaben, Prüfungen und Nachrichten des Tages,
// verschlüsselt alles mit TRICOACH_KEY (AES-256-GCM, Schlüssel per PBKDF2) und schreibt eine Datei,
// die nur die TriCoach-App mit deinem Schlüssel lesen kann. Keine Abhängigkeiten, Node 20+.
//
// Benötigte GitHub-Secrets: UNTIS_SERVER (z. B. neilo.webuntis.com), UNTIS_SCHOOL (Schulname aus der WebUntis-Adresse),
// UNTIS_USER, UNTIS_PASSWORD, TRICOACH_KEY (in TriCoach unter Einstellungen → Schule erzeugen).
// Test ohne Schule: node tools/untis-sync.mjs out.enc --demo

import { webcrypto as crypto } from 'node:crypto';
import { writeFileSync, mkdirSync } from 'node:fs';
import { dirname } from 'node:path';

const out = process.argv[2] || 'out/schule.enc';
const demo = process.argv.includes('--demo');
const env = k => (process.env[k] || '').trim();
const KEY = env('TRICOACH_KEY');

const pad = n => String(n).padStart(2, '0');
const untisDate = d => `${d.getFullYear()}${pad(d.getMonth() + 1)}${pad(d.getDate())}`;
const isoFromUntis = n => { const s = String(n); return `${s.slice(0, 4)}-${s.slice(4, 6)}-${s.slice(6, 8)}`; };
const timeFromUntis = n => { const s = String(n).padStart(4, '0'); return `${s.slice(0, 2)}:${s.slice(2)}`; };
const addDays = (d, n) => { const x = new Date(d); x.setDate(x.getDate() + n); return x; };
const strip = s => String(s || '').replace(/<br\s*\/?>/gi, '\n').replace(/<\/p>/gi, '\n').replace(/<[^>]+>/g, '').replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/\n{3,}/g, '\n\n').trim();

async function encrypt(obj, pass) {
  const salt = crypto.getRandomValues(new Uint8Array(16)), iv = crypto.getRandomValues(new Uint8Array(12));
  const base = await crypto.subtle.importKey('raw', new TextEncoder().encode(pass), 'PBKDF2', false, ['deriveKey']);
  const key = await crypto.subtle.deriveKey({ name: 'PBKDF2', salt, iterations: 120000, hash: 'SHA-256' }, base, { name: 'AES-GCM', length: 256 }, false, ['encrypt']);
  const ct = new Uint8Array(await crypto.subtle.encrypt({ name: 'AES-GCM', iv }, key, new TextEncoder().encode(JSON.stringify(obj))));
  const b64 = u => Buffer.from(u).toString('base64');
  return JSON.stringify({ v: 1, salt: b64(salt), iv: b64(iv), ct: b64(ct) });
}

/* ---------- WebUntis ---------- */
async function untis() {
  const host = env('UNTIS_SERVER').replace(/^https?:\/\//, '').replace(/\/.*$/, ''), school = env('UNTIS_SCHOOL');
  const base = `https://${host}/WebUntis`, headers = { 'Content-Type': 'application/json', 'Cache-Control': 'no-cache', 'X-Requested-With': 'XMLHttpRequest', 'User-Agent': 'Mozilla/5.0 TriCoach' };
  let cookie = '';
  const rpc = async (method, params = {}) => {
    const r = await fetch(`${base}/jsonrpc.do?school=${encodeURIComponent(school)}`, { method: 'POST', headers: { ...headers, Cookie: cookie }, body: JSON.stringify({ id: 'TriCoach', method, params, jsonrpc: '2.0' }) });
    const j = await r.json().catch(() => ({}));
    if (j.error) throw new Error(`${method}: ${j.error.message || JSON.stringify(j.error)}`);
    return j.result;
  };
  const rest = async (path, q) => {
    const r = await fetch(`${base}${path}?${new URLSearchParams(q)}`, { headers: { ...headers, Cookie: cookie } });
    if (!r.ok) throw new Error(`${path}: HTTP ${r.status}`);
    return (await r.json()).data;
  };
  const auth = await rpc('authenticate', { user: env('UNTIS_USER'), password: env('UNTIS_PASSWORD'), client: 'TriCoach' });
  if (!auth?.sessionId) throw new Error('Login fehlgeschlagen – Server, Schulname, Benutzer und Passwort prüfen.');
  cookie = `JSESSIONID=${auth.sessionId}; schoolname="_${Buffer.from(school).toString('base64')}"`;
  const now = new Date(), err = [], data = { at: now.toISOString(), lessons: [], homework: [], exams: [], news: [], err };
  try {
    const raw = await rpc('getTimetable', { options: {
      element: { id: auth.personId, type: auth.personType || 5 }, startDate: untisDate(addDays(now, -7)), endDate: untisDate(addDays(now, 21)),
      showLsText: true, showSubstText: true, showInfo: true, showStudentgroup: true,
      klasseFields: ['name'], roomFields: ['name', 'longname'], subjectFields: ['name', 'longname'], teacherFields: ['name', 'longname']
    } });
    data.lessons = (raw || []).map(l => ({
      id: l.id, d: isoFromUntis(l.date), s: timeFromUntis(l.startTime), e: timeFromUntis(l.endTime),
      su: l.su?.[0]?.name || l.lstext || (l.activityType && l.activityType !== 'Unterricht' ? l.activityType : 'Unterricht'), sul: l.su?.[0]?.longname || '',
      ro: (l.ro || []).map(x => x.name).filter(Boolean).join(', '), roOrg: (l.ro || []).map(x => x.orgname).filter(Boolean).join(', '),
      te: (l.te || []).map(x => x.name).filter(Boolean).join(', '), teOrg: (l.te || []).map(x => x.orgname).filter(Boolean).join(', '),
      code: l.code || '', info: strip(l.info), subst: strip(l.substText), ls: strip(l.lstext)
    }));
  } catch (e) { err.push('Stundenplan: ' + e.message); }
  try {
    const hw = await rest('/api/homeworks/lessons', { startDate: untisDate(addDays(now, -14)), endDate: untisDate(addDays(now, 42)) });
    const subj = new Map((hw.lessons || []).map(l => [l.id, l.subject]));
    data.homework = (hw.homeworks || []).map(h => ({ id: h.id, su: subj.get(h.lessonId) || '', text: strip(h.text), remark: strip(h.remark), date: isoFromUntis(h.date), due: isoFromUntis(h.dueDate), done: !!h.completed }));
  } catch (e) { err.push('Hausaufgaben: ' + e.message); }
  try {
    const ex = await rest('/api/exams', { startDate: untisDate(addDays(now, -7)), endDate: untisDate(addDays(now, 120)), klasseId: -1, withGrades: false });
    data.exams = (ex.exams || []).map(x => ({ id: x.id, d: isoFromUntis(x.examDate), s: timeFromUntis(x.startTime), e: timeFromUntis(x.endTime), su: x.subject || '', name: x.name || '', type: x.examType || '', text: strip(x.text), ro: (x.rooms || []).join(', ') }));
  } catch (e) { err.push('Prüfungen: ' + e.message); }
  try {
    const nw = await rest('/api/public/news/newsWidgetData', { date: untisDate(now) });
    data.news = (nw.messagesOfDay || []).map(m => ({ subject: strip(m.subject), text: strip(m.text) })).filter(m => m.subject || m.text);
  } catch (e) { /* Nachrichten sind optional */ }
  await rpc('logout').catch(() => { });
  return data;
}

/* Testdaten, damit sich die App ohne Schulzugang ausprobieren lässt */
function demoData() {
  const mon = addDays(new Date(), -((new Date().getDay() + 6) % 7)), iso = d => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
  const grid = [['07:45', '08:30'], ['08:30', '09:15'], ['09:35', '10:20'], ['10:20', '11:05'], ['11:25', '12:10'], ['12:10', '12:55'], ['13:40', '14:25'], ['14:25', '15:10']];
  const plan = [['M', 'M', 'D', 'D', 'BIO', 'E', 'SP', 'SP'], ['E', 'E', 'PH', 'PH', 'GE', 'M'], ['D', 'BIO', 'BIO', 'CH', 'CH', 'POL', 'KU', 'KU'], ['M', 'M', 'E', 'INF', 'INF', 'D'], ['PH', 'GE', 'D', 'D', 'E', 'E']];
  const lessons = [];
  for (let w = -1; w < 3; w++) for (let i = 0; i < 5; i++) plan[i].forEach((su, k) => {
    const d = iso(addDays(mon, w * 7 + i)), code = w === 0 && i === 2 && k === 3 ? 'cancelled' : w === 0 && i === 3 && k === 0 ? 'irregular' : '';
    lessons.push({ id: +(`${w + 2}${i}${k}`), d, s: grid[k][0], e: grid[k][1], su, sul: '', ro: code === 'irregular' ? 'R 204' : 'R 1' + (k + 10), roOrg: code === 'irregular' ? 'R 110' : '', te: code === 'irregular' ? 'MÜL' : 'SCH', teOrg: code === 'irregular' ? 'BEC' : '', code, info: code === 'cancelled' ? 'Aufgaben im Moodle-Kurs bearbeiten' : '', subst: code === 'irregular' ? 'Vertretung' : '', ls: '' });
  });
  return { at: new Date().toISOString(), lessons, news: [{ subject: 'Wandertag', text: 'Am Freitag in zwei Wochen ist Wandertag. Feste Schuhe mitbringen.' }], err: [],
    homework: [{ id: 1, su: 'M', text: 'S. 112 Nr. 4a–d', remark: '', date: iso(mon), due: iso(addDays(new Date(), 1)), done: false }, { id: 2, su: 'E', text: 'Vocabulary unit 3 lernen', remark: 'Test möglich', date: iso(mon), due: iso(addDays(new Date(), 2)), done: false }, { id: 3, su: 'BIO', text: 'Protokoll Zellatmung fertig schreiben', remark: '', date: iso(addDays(mon, -3)), due: iso(addDays(new Date(), -1)), done: true }],
    exams: [{ id: 9, d: iso(addDays(new Date(), 6)), s: '08:30', e: '10:20', su: 'M', name: 'Klassenarbeit Mathe', type: 'Klassenarbeit', text: 'Quadratische Funktionen', ro: 'R 112' }] };
}

(async () => {
  if (!KEY) { console.log('TRICOACH_KEY fehlt – in TriCoach unter Einstellungen → Schule einen Schlüssel erzeugen und als GitHub-Secret eintragen.'); process.exit(0); }
  if (!demo && (!env('UNTIS_SERVER') || !env('UNTIS_SCHOOL') || !env('UNTIS_USER') || !env('UNTIS_PASSWORD'))) { console.log('WebUntis-Secrets fehlen (UNTIS_SERVER, UNTIS_SCHOOL, UNTIS_USER, UNTIS_PASSWORD) – nichts zu tun.'); process.exit(0); }
  let data;
  try { data = demo ? demoData() : await untis(); }
  catch (e) { console.error('Fehler:', e.message, '– die zuletzt veröffentlichten Daten bleiben erhalten.'); process.exit(1); }
  mkdirSync(dirname(out), { recursive: true });
  writeFileSync(out, await encrypt(data, KEY));
  console.log(`OK: ${data.lessons.length} Stunden, ${data.homework.length} Hausaufgaben, ${data.exams.length} Prüfungen${data.err.length ? ' · Hinweise: ' + data.err.join(' | ') : ''}`);
})();
