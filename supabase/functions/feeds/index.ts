// @ts-nocheck
// TriCoach – Verbindungen für alle Nutzer: WebUntis (Stundenplan, Hausaufgaben, Prüfungen) und TrainingPeaks (iCal-Plan).
// Die App ruft diese Funktion mit dem Login des Nutzers auf. Zugangsdaten liegen nur hier auf dem Server
// (Tabelle public.integrations, ohne Lesezugriff für die App) – das WebUntis-Passwort wird nie gespeichert:
// Es wird einmal benutzt, um wie die Untis-App einen App-Schlüssel zu bekommen.
// WebUntis-Abruf = derselbe Code wie tools/untis-sync.mjs (GitHub-Job), hier für Deno.
//
// Aktionen (POST, JSON { action, … }):
//   searchSchool { q }                          → { schools: [{ server, school, name, address }] }   (ohne Login)
//   status                                      → { links: { webuntis?: { label, at }, trainingpeaks?: { label, at } } }
//   untisConnect { zugang } | { server, school, user, password }  → { label, data }
//   untisFetch                                  → { data }
//   tpConnect { ical }                          → { label, ics, at }
//   tpFetch                                     → { ics, at }
//   disconnect { kind: 'webuntis' | 'trainingpeaks' }
import { createClient } from 'npm:@supabase/supabase-js@2';

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
const json = (o, status = 200) => new Response(JSON.stringify(o), { status, headers: { ...CORS, 'Content-Type': 'application/json' } });
class UserError extends Error {}

function serviceKey() {
  const legacy = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (legacy) return legacy;
  try {
    const keys = JSON.parse(Deno.env.get('SUPABASE_SECRET_KEYS') ?? '{}');
    return keys.default ?? Object.values(keys)[0] ?? '';
  } catch (_) {
    return '';
  }
}

const b64 = s => btoa(String.fromCharCode(...new TextEncoder().encode(s)));

/* ---------- Hilfen (aus tools/untis-sync.mjs) ---------- */
const pad = n => String(n).padStart(2, '0');
const untisDate = d => `${d.getFullYear()}${pad(d.getMonth() + 1)}${pad(d.getDate())}`;
const isoDate = d => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
const isoFromUntis = n => { const s = String(n); return `${s.slice(0, 4)}-${s.slice(4, 6)}-${s.slice(6, 8)}`; };
const timeFromUntis = n => { const s = String(n).padStart(4, '0'); return `${s.slice(0, 2)}:${s.slice(2)}`; };
const addDays = (d, n) => { const x = new Date(d); x.setDate(x.getDate() + n); return x; };
const strip = s => String(s || '').replace(/<br\s*\/?>/gi, '\n').replace(/<\/p>/gi, '\n').replace(/<[^>]+>/g, '').replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/\n{3,}/g, '\n\n').trim();

/* ---------- Zugangsdaten (Link aus „Zugriff über Untis Mobile“, JSON oder Feld: Wert) ---------- */
function parseZugang(text) {
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

/* ---------- Einmalcode aus dem App-Schlüssel (TOTP nach RFC 6238, wie die Untis-App) ---------- */
function base32(s) {
  const A = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567', out = []; let bits = 0, val = 0;
  for (const c of s.replace(/[\s=-]/g, '').toUpperCase()) {
    const i = A.indexOf(c); if (i < 0) throw new UserError('Der WebUntis-Schlüssel enthält ungültige Zeichen – bitte genau so kopieren, wie er in WebUntis steht.');
    val = (val << 5) | i; bits += 5; if (bits >= 8) { out.push((val >>> (bits - 8)) & 255); bits -= 8; }
  }
  return new Uint8Array(out);
}
async function totp(secret, t = Date.now(), digits = 6) {
  const msg = new Uint8Array(8), view = new DataView(msg.buffer);
  view.setBigUint64(0, BigInt(Math.floor(t / 30000)));
  const key = await crypto.subtle.importKey('raw', base32(secret), { name: 'HMAC', hash: 'SHA-1' }, false, ['sign']);
  const h = new Uint8Array(await crypto.subtle.sign('HMAC', key, msg)), o = h[h.length - 1] & 15;
  const code = (((h[o] & 127) << 24) | (h[o + 1] << 16) | (h[o + 2] << 8) | h[o + 3]) % 10 ** digits;
  return String(code).padStart(digits, '0');
}

/* ---------- WebUntis ---------- */
async function untis(z) {
  const base = `https://${z.server}/WebUntis`, school = z.school;   // UNTIS_TEST_BASE nur für lokale Tests
  const H = { 'Content-Type': 'application/json', Accept: 'application/json', 'Cache-Control': 'no-cache', 'X-Requested-With': 'XMLHttpRequest', 'User-Agent': 'Mozilla/5.0 (TriCoach)' };
  const jar = new Map([['schoolname', `"_${b64(school)}"`]]);
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
  const intern1 = async (method, params) => call(`${base}/jsonrpc_intern.do?m=${method}&school=${encodeURIComponent(school)}&v=i2.2`, method,
    [{ ...params, auth: { user: z.user, otp: await totp(z.key), clientTime: Date.now() } }]);
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


/* ---------- Schule suchen (wie in der Untis-App) ---------- */
async function searchSchool(q) {
  if (q.trim().length < 3) return [];
  const r = await fetch('https://mobile.webuntis.com/ms/schoolquery2', {
    method: 'POST', headers: { 'Content-Type': 'application/json', 'User-Agent': 'Mozilla/5.0 (TriCoach)' },
    body: JSON.stringify({ id: 'TriCoach', method: 'searchSchool', params: [{ search: q.trim() }], jsonrpc: '2.0' }),
  });
  const j = await r.json().catch(() => ({}));
  if (j.error) {
    if (String(j.error.code) === '-6003' || /too many/i.test(j.error.message || '')) throw new UserError('Zu viele Treffer – bitte genauer suchen (z. B. mit Ort).');
    throw new UserError('Schulsuche gerade nicht möglich');
  }
  return (j.result?.schools || []).slice(0, 25).map(s => ({
    server: String(s.server || '').replace(/^https?:\/\//, '').replace(/\/.*$/, ''),
    school: s.loginName || s.loginSchool || '', name: s.displayName || s.loginName || '', address: s.address || '',
  })).filter(s => s.server && s.school);
}

/* App-Schlüssel mit Benutzer + Passwort holen (so richtet sich die Untis-App ein) – das Passwort wird danach vergessen */
async function sharedSecret(server, school, user, password) {
  const r = await fetch(`https://${server}/WebUntis/jsonrpc_intern.do?m=getAppSharedSecret&school=${encodeURIComponent(school)}&v=i3.5`, {
    method: 'POST', headers: { 'Content-Type': 'application/json', 'User-Agent': 'Mozilla/5.0 (TriCoach)' },
    body: JSON.stringify({ id: 'TriCoach', method: 'getAppSharedSecret', params: [{ userName: user, password }], jsonrpc: '2.0' }),
  });
  const j = await r.json().catch(() => ({}));
  if (typeof j.result === 'string' && j.result.length >= 8) return j.result;
  const m = String(j.error?.message || '');
  if (/bad credentials|invalid|-8504|password/i.test(m + (j.error?.code ?? ''))) throw new UserError('Benutzername oder Passwort stimmt nicht.');
  throw new UserError('Diese Schule erlaubt die Anmeldung mit Passwort nicht (z. B. Microsoft-Login). Bitte den Link aus „Zugriff über Untis Mobile“ einfügen.');
}

/* ---------- TrainingPeaks / beliebiger iCal-Kalender ---------- */
function normIcal(s) {
  const t = String(s || '').trim().replace(/^webcal:\/\//i, 'https://');
  let u; try { u = new URL(t); } catch (_) { throw new UserError('Das ist kein Link – bitte den iCal-Link aus TrainingPeaks einfügen.'); }
  if (u.protocol !== 'https:') throw new UserError('Bitte einen https- oder webcal-Link einfügen.');
  return u.toString();
}
async function fetchIcs(link) {
  const r = await fetch(link, { headers: { 'User-Agent': 'TriCoach/3 (+supabase)', Accept: 'text/calendar,*/*' } });
  if (!r.ok) throw new UserError(`Kalender nicht erreichbar (HTTP ${r.status}) – ist der Link noch gültig?`);
  const ics = await r.text();
  if (!ics.includes('BEGIN:VCALENDAR')) throw new UserError('Unter dem Link liegt keine Kalenderdatei.');
  return ics;
}

/* ---------- Anfrage ---------- */
Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  let body = {};
  try { body = await req.json(); } catch (_) {}
  const action = String(body.action || '');
  try {
    if (action === 'searchSchool') return json({ schools: await searchSchool(String(body.q || '')) });

    const db = createClient(Deno.env.get('SUPABASE_URL'), serviceKey(), { auth: { persistSession: false } });
    const jwt = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '');
    const { data: auth } = jwt ? await db.auth.getUser(jwt) : { data: null };
    const uid = auth?.user?.id;
    if (!uid) return json({ error: 'Bitte zuerst in TriCoach anmelden.' }, 401);

    const load = async kind => (await db.from('integrations').select('config, label, updated_at').eq('user_id', uid).eq('kind', kind).maybeSingle()).data;
    const save = async (kind, config, label) => {
      const { error } = await db.from('integrations').upsert({ user_id: uid, kind, config, label, updated_at: new Date().toISOString() });
      if (error) throw new Error('Speichern fehlgeschlagen: ' + error.message);
    };

    switch (action) {
      case 'status': {
        const { data } = await db.from('integrations').select('kind, label, updated_at').eq('user_id', uid);
        return json({ links: Object.fromEntries((data || []).map(r => [r.kind, { label: r.label, at: r.updated_at }])) });
      }
      case 'untisConnect': {
        let z;
        if (body.zugang) {
          z = parseZugang(String(body.zugang));
          if (!z) throw new UserError('Im eingefügten Text fehlen Server, Schule, Benutzer oder Schlüssel – bitte den ganzen Link aus „Zugriff über Untis Mobile“ kopieren.');
        } else {
          const server = String(body.server || '').replace(/^https?:\/\//, '').replace(/\/.*$/, ''), school = String(body.school || ''), user = String(body.user || '').trim();
          if (!server || !school || !user || !body.password) throw new UserError('Bitte Schule, Benutzername und Passwort angeben.');
          z = { server, school, user, key: await sharedSecret(server, school, user, String(body.password)), password: '' };
        }
        if (!z.key) throw new UserError('Für die dauerhafte Verbindung braucht TriCoach den App-Schlüssel (Link aus „Zugriff über Untis Mobile“).');
        const data = await untis({ ...z, password: '' });
        const label = `${body.name || z.school} · ${z.user}`;
        await save('webuntis', { server: z.server, school: z.school, user: z.user, key: z.key }, label);
        return json({ label, data });
      }
      case 'untisFetch': {
        const row = await load('webuntis');
        if (!row) return json({ error: 'WebUntis ist nicht verbunden.', code: 'none' }, 404);
        return json({ data: await untis({ ...row.config, password: '' }) });
      }
      case 'tpConnect': {
        const link = normIcal(body.ical), ics = await fetchIcs(link);
        const label = /trainingpeaks/i.test(link) ? 'TrainingPeaks' : new URL(link).hostname;
        await save('trainingpeaks', { ical: link }, label);
        return json({ label, ics, at: new Date().toISOString() });
      }
      case 'tpFetch': {
        const row = await load('trainingpeaks');
        if (!row) return json({ error: 'TrainingPeaks ist nicht verbunden.', code: 'none' }, 404);
        return json({ ics: await fetchIcs(row.config.ical), at: new Date().toISOString() });
      }
      case 'disconnect': {
        await db.from('integrations').delete().eq('user_id', uid).eq('kind', String(body.kind || ''));
        return json({ ok: true });
      }
      default:
        return json({ error: 'Unbekannte Aktion' }, 400);
    }
  } catch (e) {
    const user = e instanceof UserError || /^(Anmeldung|Login|Angemeldet|getTimetable|Stundenplan)/.test(e.message || '');
    return json({ error: String(e.message || e) }, user ? 400 : 502);
  }
});
