// TriCoach – WebUntis-Abruf für den GitHub-Job (.github/workflows/schule.yml)
// Holt Stundenplan (inkl. Ausfall/Vertretung/Infos), Hausaufgaben, Prüfungen und Nachrichten des Tages,
// verschlüsselt alles mit TRICOACH_KEY (AES-256-GCM, Schlüssel per PBKDF2) und schreibt eine Datei,
// die nur die TriCoach-App mit deinem Schlüssel lesen kann. Keine Abhängigkeiten, Node 20+.
//
// Anmeldung – eine dieser Varianten genügt (in dieser Reihenfolge geprüft):
//  1. Datei tools/untis-zugang.enc (Zugangsdaten, verschlüsselt mit TRICOACH_KEY) → dann ist nur das Secret TRICOACH_KEY nötig.
//     Erzeugen: TRICOACH_KEY=… node tools/zugang.mjs "untis://setschool?url=…&school=…&user=…&key=…"
//  2. Secret UNTIS_ZUGANG = Text/Link aus WebUntis → Profil → Freigaben → „Zugriff über Untis Mobile“
//     (z. B. untis://setschool?url=neilo.webuntis.com&school=…&user=…&key=…) oder JSON.
//  3. Einzelne Secrets UNTIS_SERVER, UNTIS_SCHOOL, UNTIS_USER und UNTIS_KEY (App-Schlüssel) oder UNTIS_PASSWORD.
// Der App-Schlüssel funktioniert auch an Schulen mit „Mit Microsoft anmelden“ – so meldet sich auch die Untis-App an.
// Test ohne Schule: node tools/untis-sync.mjs out.enc --demo

import { webcrypto as crypto, createHmac } from 'node:crypto';
import { writeFileSync, mkdirSync, readFileSync, existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const out = process.argv[2] || 'out/schule.enc';
const demo = process.argv.includes('--demo');
const env = k => (process.env[k] || '').trim();
const KEY = env('TRICOACH_KEY');

const pad = n => String(n).padStart(2, '0');
const untisDate = d => `${d.getFullYear()}${pad(d.getMonth() + 1)}${pad(d.getDate())}`;
const isoDate = d => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
const isoFromUntis = n => { const s = String(n); return `${s.slice(0, 4)}-${s.slice(4, 6)}-${s.slice(6, 8)}`; };
const timeFromUntis = n => { const s = String(n).padStart(4, '0'); return `${s.slice(0, 2)}:${s.slice(2)}`; };
const addDays = (d, n) => { const x = new Date(d); x.setDate(x.getDate() + n); return x; };
const strip = s => String(s || '').replace(/<br\s*\/?>/gi, '\n').replace(/<\/p>/gi, '\n').replace(/<[^>]+>/g, '').replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/\n{3,}/g, '\n\n').trim();

/* ---------- Verschlüsselung (gleiches Format wie in der App) ---------- */
const b64 = u => Buffer.from(u).toString('base64');
async function deriveKey(pass, salt, use) {
  const base = await crypto.subtle.importKey('raw', new TextEncoder().encode(pass), 'PBKDF2', false, ['deriveKey']);
  return crypto.subtle.deriveKey({ name: 'PBKDF2', salt, iterations: 120000, hash: 'SHA-256' }, base, { name: 'AES-GCM', length: 256 }, false, [use]);
}
/* Festes Salz: der Schlüssel (TRICOACH_KEY, 18 Zufallsbytes) ist selbst zufällig genug. So muss die App bzw. das Siri-Skript
   den Schlüssel nur einmal ableiten (PBKDF2) und nicht bei jedem Abruf neu – wichtig für Siri und das Widget. Die IV bleibt zufällig. */
const SALT = new Uint8Array((await crypto.subtle.digest('SHA-256', new TextEncoder().encode('TriCoach-Salz-v1'))).slice(0, 16));
export async function encrypt(obj, pass) {
  const salt = SALT, iv = crypto.getRandomValues(new Uint8Array(12));
  const ct = new Uint8Array(await crypto.subtle.encrypt({ name: 'AES-GCM', iv }, await deriveKey(pass, salt, 'encrypt'), new TextEncoder().encode(JSON.stringify(obj))));
  return JSON.stringify({ v: 1, salt: b64(salt), iv: b64(iv), ct: b64(ct) });
}
export async function decrypt(txt, pass) {
  const o = JSON.parse(txt), u = s => Uint8Array.from(Buffer.from(s, 'base64'));
  const pt = await crypto.subtle.decrypt({ name: 'AES-GCM', iv: u(o.iv) }, await deriveKey(pass, u(o.salt), 'decrypt'), u(o.ct));
  return JSON.parse(new TextDecoder().decode(pt));
}

/* ---------- Zugangsdaten ---------- */
// Akzeptiert den Link aus dem QR-Code (untis://setschool?…), eine WebUntis-Adresse, JSON oder „Feld: Wert“-Zeilen.
export function parseZugang(text) {
  const t = String(text || '').trim(); if (!t) return null;
  let o = {};
  if (t.startsWith('{')) o = JSON.parse(t);
  else if (!/\n/.test(t) && (/^untis:\/\//i.test(t) || /^https?:\/\/.*[?&](user|key)=/i.test(t))) {
    const q = new URL(t.replace(/^untis:\/\/[^?]*/i, 'https://x/')).searchParams;
    for (const [k, v] of q) o[k] = v;
  } else for (const line of t.split(/\r?\n/)) {
    const m = line.match(/^\s*([\wäöüÄÖÜ -]+?)\s*[:=]\s*(.+?)\s*$/); if (!m) continue;
    const k = m[1].toLowerCase();
    if (/server|url|adresse/.test(k)) o.url = m[2]; else if (/nummer|number/.test(k)) o.schoolNumber = m[2];
    else if (/schule|school/.test(k)) o.school = m[2]; else if (/benutzer|user/.test(k)) o.user = m[2];
    else if (/schlüssel|schluessel|key|secret/.test(k)) o.key = m[2]; else if (/passwort|password/.test(k)) o.password = m[2];
  }
  const z = {
    server: String(o.server || o.url || '').replace(/^https?:\/\//i, '').replace(/\/.*$/, '').trim(),
    school: String(o.school || o.schoolName || '').trim(), user: String(o.user || o.username || '').trim(),
    key: String(o.key || o.secret || '').replace(/\s+/g, '').trim(), password: String(o.password || ''), schoolNumber: String(o.schoolNumber || o.schoolnumber || '')
  };
  return z.server && z.school && z.user && (z.key || z.password) ? z : null;
}
async function loadZugang() {
  const file = join(HERE, 'untis-zugang.enc');
  if (existsSync(file)) {
    try { const z = await decrypt(readFileSync(file, 'utf8'), KEY); if (z?.server) return { ...z, via: 'tools/untis-zugang.enc' }; }
    catch (e) { console.log('Hinweis: tools/untis-zugang.enc lässt sich mit diesem TRICOACH_KEY nicht öffnen – prüfe das Secret. Versuche die anderen Varianten …'); }
  }
  if (env('UNTIS_ZUGANG')) { const z = parseZugang(env('UNTIS_ZUGANG')); if (z) return { ...z, via: 'Secret UNTIS_ZUGANG' }; console.log('Hinweis: UNTIS_ZUGANG ist unvollständig (Server, Schule, Benutzer und Schlüssel nötig).'); }
  const z = { server: env('UNTIS_SERVER').replace(/^https?:\/\//i, '').replace(/\/.*$/, ''), school: env('UNTIS_SCHOOL'), user: env('UNTIS_USER'), key: env('UNTIS_KEY').replace(/\s+/g, ''), password: process.env.UNTIS_PASSWORD || '' };
  return z.server && z.school && z.user && (z.key || z.password) ? { ...z, via: 'einzelne Secrets' } : null;
}

/* ---------- Einmalcode aus dem App-Schlüssel (TOTP nach RFC 6238, wie die Untis-App) ---------- */
function base32(s) {
  const A = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567', out = []; let bits = 0, val = 0;
  for (const c of s.replace(/[\s=-]/g, '').toUpperCase()) {
    const i = A.indexOf(c); if (i < 0) throw new Error('Der WebUntis-Schlüssel enthält ungültige Zeichen – bitte genau so kopieren, wie er in WebUntis steht.');
    val = (val << 5) | i; bits += 5; if (bits >= 8) { out.push((val >>> (bits - 8)) & 255); bits -= 8; }
  }
  return Buffer.from(out);
}
export function totp(secret, t = Date.now(), digits = 6) {
  const msg = Buffer.alloc(8); msg.writeBigUInt64BE(BigInt(Math.floor(t / 30000)));
  const h = createHmac('sha1', base32(secret)).update(msg).digest(), o = h[h.length - 1] & 15;
  const code = (((h[o] & 127) << 24) | (h[o + 1] << 16) | (h[o + 2] << 8) | h[o + 3]) % 10 ** digits;
  return String(code).padStart(digits, '0');
}

/* ---------- WebUntis ---------- */
async function untis(z) {
  const base = env('UNTIS_TEST_BASE') || `https://${z.server}/WebUntis`, school = z.school;   // UNTIS_TEST_BASE nur für lokale Tests
  const H = { 'Content-Type': 'application/json', Accept: 'application/json', 'Cache-Control': 'no-cache', 'X-Requested-With': 'XMLHttpRequest', 'User-Agent': 'Mozilla/5.0 (TriCoach)' };
  const jar = new Map([['schoolname', `"_${Buffer.from(school).toString('base64')}"`]]);
  const cookie = () => [...jar].map(([k, v]) => `${k}=${v}`).join('; ');
  const keep = r => { for (const c of r.headers.getSetCookie?.() || []) { const [kv] = c.split(';'), i = kv.indexOf('='); if (i > 0) jar.set(kv.slice(0, i).trim(), kv.slice(i + 1).trim()); } };
  const call = async (url, method, params) => {
    const r = await fetch(url, { method: 'POST', headers: { ...H, Cookie: cookie() }, body: JSON.stringify({ id: 'TriCoach', method, params, jsonrpc: '2.0' }) });
    keep(r);
    const txt = await r.text(); let j; try { j = JSON.parse(txt); } catch (e) { throw new Error(`${method}: keine gültige Antwort (HTTP ${r.status}) – stimmt der Server „${z.server}“?`); }
    if (j.error) { const e = new Error(`${method}: ${j.error.message || JSON.stringify(j.error)}`); e.code = j.error.code; throw e; }
    return j.result;
  };
  const rpc = (method, params = {}) => call(`${base}/jsonrpc.do?school=${encodeURIComponent(school)}`, method, params);
  // Internes API der Untis-App: jede Anfrage trägt einen frischen Einmalcode
  const intern1 = (method, params) => call(`${base}/jsonrpc_intern.do?m=${method}&school=${encodeURIComponent(school)}&v=i2.2`, method,
    [{ ...params, auth: { user: z.user, otp: totp(z.key), clientTime: Date.now() } }]);
  const intern = async (method, params = {}, retry = true) => {   // Code läuft alle 30 s ab – bei Ablehnung einmal mit frischem Code
    try { return await intern1(method, params); }
    catch (e) { if (!retry || !/credential|otp|-8504|-8509/i.test(e.message + (e.code || ''))) throw e; await new Promise(r => setTimeout(r, 2000)); return intern1(method, params); }
  };
  let bearer = '';
  const rest = async (path, q) => {
    const go = () => fetch(`${base}${path}?${new URLSearchParams(q)}`, { headers: { ...H, Cookie: cookie(), ...(bearer ? { Authorization: 'Bearer ' + bearer } : {}) } });
    let r = await go();
    if ((r.status === 401 || r.status === 403) && !bearer) {   // neuere WebUntis-Versionen wollen zusätzlich ein Token
      const t = await fetch(`${base}/api/token/new`, { headers: { ...H, Cookie: cookie() } });
      if (t.ok) { bearer = (await t.text()).trim().replace(/^"|"$/g, ''); r = await go(); }
    }
    if (!r.ok) throw new Error(`${path}: HTTP ${r.status}`);
    const j = await r.json(); return j.data ?? j;
  };

  /* Anmelden */
  let person = { id: null, type: 5, typeName: 'STUDENT' }, master = null;
  const TYPES = { CLASS: 1, TEACHER: 2, SUBJECT: 3, ROOM: 4, STUDENT: 5 };
  if (z.key) {
    let ud;
    try { ud = await intern('getUserData2017', { elementId: 0, deviceOs: 'AND', deviceOsVersion: '' }); }
    catch (e) {
      if (/-8504|-8509|-8998|otp|auth|bad credentials|invalid/i.test(e.message + (e.code || ''))) throw new Error(`Anmeldung mit App-Schlüssel abgelehnt (${e.message}). Prüfe Benutzer, Schulname und Schlüssel – der Schlüssel ändert sich, wenn du in WebUntis die Freigabe neu erzeugst.`);
      throw e;
    }
    master = ud?.masterData || null;
    const u = ud?.userData || {};
    if (u.elemId) person = { id: u.elemId, type: TYPES[u.elemType] || 5, typeName: u.elemType || 'STUDENT' };
    if (!person.id) {
      try {
        const cfg = await rest('/api/app/config', {}), lu = cfg?.loginServiceConfig?.user, p = lu?.persons?.find(x => x.id === lu.personId);
        if (lu?.personId) person = { id: lu.personId, type: TYPES[p?.type] || 5, typeName: p?.type || 'STUDENT' };
      } catch (e) { }
    }
    if (!person.id) throw new Error('Angemeldet, aber WebUntis nennt keine Person zu diesem Benutzer.');
  } else {
    const auth = await rpc('authenticate', { user: z.user, password: z.password, client: 'TriCoach' });
    if (!auth?.sessionId) throw new Error('Login fehlgeschlagen – Server, Schulname, Benutzer und Passwort prüfen.');
    jar.set('JSESSIONID', auth.sessionId);
    person = { id: auth.personId, type: auth.personType || 5, typeName: 'STUDENT' };
  }

  const now = new Date(), err = [], data = { at: now.toISOString(), lessons: [], homework: [], exams: [], news: [], err };
  const from = addDays(now, -7), to = addDays(now, 21);
  const byId = (list, id) => (list || []).find(x => x.id === id);
  const teacherName = t => t ? (t.name || t.lastName || [t.firstName, t.lastName].filter(Boolean).join(' ')) : '';

  /* Stundenplan: erst wie im Browser, sonst über das App-API */
  try {
    const raw = await rpc('getTimetable', { options: {
      element: { id: person.id, type: person.type }, startDate: untisDate(from), endDate: untisDate(to),
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
  } catch (e1) {
    if (!z.key) err.push('Stundenplan: ' + e1.message);
    else try {
      const r = await intern('getTimetable2017', { id: person.id, type: person.typeName, startDate: isoDate(from), endDate: isoDate(to), masterDataTimestamp: 0, timetableTimestamp: 0, timetableTimestamps: [] });
      master = r?.masterData?.subjects ? r.masterData : master;
      const M = master || {};
      data.lessons = (r?.timetable?.periods || []).map(p => {
        const els = t => (p.elements || []).filter(x => x.type === t);
        const names = (t, list, f = x => x?.name) => els(t).map(x => f(byId(list, x.id))).filter(Boolean).join(', ');
        const orgs = (t, list, f = x => x?.name) => els(t).filter(x => x.orgId).map(x => f(byId(list, x.orgId))).filter(Boolean).join(', ');
        const su = byId(M.subjects, els('SUBJECT')[0]?.id), is = p.is || [];
        return {
          id: p.id, d: String(p.startDateTime).slice(0, 10), s: String(p.startDateTime).slice(11, 16), e: String(p.endDateTime).slice(11, 16),
          su: su?.name || strip(p.text?.lesson) || 'Unterricht', sul: su?.longName || '',
          ro: names('ROOM', M.rooms), roOrg: orgs('ROOM', M.rooms), te: names('TEACHER', M.teachers, teacherName), teOrg: orgs('TEACHER', M.teachers, teacherName),
          code: is.includes('CANCELLED') ? 'cancelled' : is.some(x => ['IRREGULAR', 'SUBSTITUTION', 'ROOMSUBSTITUTION', 'ADDITIONAL', 'SHIFT'].includes(x)) ? 'irregular' : '',
          info: strip(p.text?.info), subst: strip(p.text?.substitution), ls: strip(p.text?.lesson), _hw: p.homeWorks || []
        };
      });
    } catch (e2) { err.push('Stundenplan: ' + e2.message); }
  }

  /* Hausaufgaben */
  try {
    const hw = await rest('/api/homeworks/lessons', { startDate: untisDate(addDays(now, -14)), endDate: untisDate(addDays(now, 42)) });
    const subj = new Map((hw.lessons || []).map(l => [l.id, l.subject]));
    data.homework = (hw.homeworks || []).map(h => ({ id: h.id, su: subj.get(h.lessonId) || '', text: strip(h.text), remark: strip(h.remark), date: isoFromUntis(h.date), due: isoFromUntis(h.dueDate), done: !!h.completed }));
  } catch (e1) {
    if (!z.key) err.push('Hausaufgaben: ' + e1.message);
    else try {
      const r = await intern('getHomeWork2017', { id: person.id, type: person.typeName, startDate: isoDate(addDays(now, -14)), endDate: isoDate(addDays(now, 42)) });
      const les = new Map((r?.lessons || []).map(l => [l.id, l.subject])), M = master || {};
      const subjOf = id => { const s = les.get(id); return typeof s === 'string' ? s : byId(M.subjects, s)?.name || ''; };
      data.homework = (r?.homeWorks || []).map(h => ({ id: h.id, su: subjOf(h.lessonId), text: strip(h.text), remark: strip(h.remark), date: String(h.startDate).slice(0, 10), due: String(h.endDate).slice(0, 10), done: !!h.completed }));
    } catch (e2) {
      // letzter Versuch: Hausaufgaben, die im Stundenplan stecken
      const seen = new Set(), M = master || {};
      data.lessons.forEach(l => (l._hw || []).forEach(h => { if (seen.has(h.id)) return; seen.add(h.id); data.homework.push({ id: h.id, su: l.su, text: strip(h.text), remark: strip(h.remark), date: String(h.startDate || l.d).slice(0, 10), due: String(h.endDate || l.d).slice(0, 10), done: !!h.completed }); }));
      if (!data.homework.length) err.push('Hausaufgaben: ' + e2.message);
    }
  }
  data.lessons.forEach(l => delete l._hw);

  /* Prüfungen */
  try {
    const ex = await rest('/api/exams', { startDate: untisDate(addDays(now, -7)), endDate: untisDate(addDays(now, 120)), klasseId: -1, withGrades: false });
    data.exams = (ex.exams || []).map(x => ({ id: x.id, d: isoFromUntis(x.examDate), s: timeFromUntis(x.startTime), e: timeFromUntis(x.endTime), su: x.subject || '', name: x.name || '', type: x.examType || '', text: strip(x.text), ro: (x.rooms || []).join(', ') }));
  } catch (e1) {
    if (!z.key) err.push('Prüfungen: ' + e1.message);
    else try {
      const r = await intern('getExams2017', { id: person.id, type: person.typeName, startDate: isoDate(addDays(now, -7)), endDate: isoDate(addDays(now, 120)) }), M = master || {};
      data.exams = (r?.exams || []).map(x => ({ id: x.id, d: String(x.startDateTime).slice(0, 10), s: String(x.startDateTime).slice(11, 16), e: String(x.endDateTime).slice(11, 16), su: byId(M.subjects, x.subjectId)?.name || '', name: x.name || '', type: x.examType || '', text: strip(x.text), ro: (x.roomIds || []).map(id => byId(M.rooms, id)?.name).filter(Boolean).join(', ') }));
    } catch (e2) { err.push('Prüfungen: ' + e2.message); }
  }

  /* Nachrichten des Tages (optional) */
  try {
    const nw = await rest('/api/public/news/newsWidgetData', { date: untisDate(now) });
    data.news = (nw.messagesOfDay || []).map(m => ({ subject: strip(m.subject), text: strip(m.text) })).filter(m => m.subject || m.text);
  } catch (e) { }

  if (!z.key) await rpc('logout').catch(() => { });
  if (!data.lessons.length && err.length) throw new Error(err.join(' | '));
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

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) (async () => {
  if (!KEY) { console.log('TRICOACH_KEY fehlt – in TriCoach unter Einstellungen → Schule den Schlüssel kopieren und als GitHub-Secret TRICOACH_KEY eintragen.'); process.exit(0); }
  const z = demo ? null : await loadZugang();
  if (!demo && !z) { console.log('Keine WebUntis-Zugangsdaten gefunden (tools/untis-zugang.enc, Secret UNTIS_ZUGANG oder UNTIS_SERVER/UNTIS_SCHOOL/UNTIS_USER/UNTIS_KEY) – nichts zu tun.'); process.exit(0); }
  if (z) console.log(`Melde an: ${z.user} @ ${z.school} (${z.server}) per ${z.key ? 'App-Schlüssel' : 'Passwort'} · Daten aus ${z.via}`);
  let data;
  try { data = demo ? demoData() : await untis(z); }
  catch (e) { console.error('Fehler:', e.message, '– die zuletzt veröffentlichten Daten bleiben erhalten.'); process.exit(1); }
  mkdirSync(dirname(out), { recursive: true });
  writeFileSync(out, await encrypt(data, KEY));
  console.log(`OK: ${data.lessons.length} Stunden, ${data.homework.length} Hausaufgaben, ${data.exams.length} Prüfungen, ${data.news.length} Nachrichten${data.err.length ? ' · Hinweise: ' + data.err.join(' | ') : ''}`);
})();
