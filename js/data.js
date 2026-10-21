'use strict';
/* TriCoach – Datenhaltung: Einstellungen, IndexedDB, Sync mit intervals.icu, FIT-Import */

const DEFAULT_PROFILE = { weight: 68, height: 182, ftp: 260, lthr: 172, rhr: 48, maxHr: 195, thrPace: 250, css: 95, bikeKg: 8.5 };
let SET = loadSettings();
let P = SET.profile;
let RACE = SET.race;
let ACTS = [], WELL = [], PMC = [], LOAD = null, NOW = new Date(), TODAY = sod(NOW);
let PLAN = loadPlan();

function loadSettings() {
  let s = {};
  try { s = JSON.parse(localStorage.getItem('tricoach-settings') || '{}'); } catch (e) { }
  const race = s.race || { name: 'Saisonhöhepunkt', date: isoDay(addDays(new Date(), 70)), fmt: 'sprint', temp: 20, hills: 0 };
  if (!s.sprintV && race.fmt === 'olympic') race.fmt = 'sprint';   // 2.4: Sprint ist jetzt die Standarddistanz
  return {
    profile: { ...DEFAULT_PROFILE, ...(s.profile || {}) },
    race, source: s.source || 'demo', icuKey: s.icuKey || '', design: s.design || 'nacht',
    lastSync: s.lastSync || null, syncDays: s.syncDays || 120, wetsuit: s.wetsuit ?? true, cda: s.cda || null,
    calView: s.calView || 'month', calHidden: s.calHidden || [], showDone: s.showDone ?? true,
    sprintV: 1, goals: s.goals || null, yearGoals: s.yearGoals || null, shortcut: s.shortcut || 'TriCoach', tpIcal: s.tpIcal || '', tpIcalAt: s.tpIcalAt || null, tpAt: s.tpAt || null, tpVia: s.tpVia || '', tpSeen: s.tpSeen || 0
  };
}
function saveSettings() {
  SET.profile = P; SET.race = RACE;
  try { localStorage.setItem('tricoach-settings', JSON.stringify(SET)); } catch (e) { }
}
RACE.date = new Date(RACE.date);

/* Kalender-Einträge. Alte Einträge {id,date,sport,title,min} bleiben gültig (kind = 'workout'). */
function loadPlan() { try { const raw = localStorage.getItem('tricoach-plan'); if (raw) return JSON.parse(raw).map(p => ({ kind: 'workout', ...p, date: new Date(p.date) })); } catch (e) { } return []; }
function savePlan() { try { localStorage.setItem('tricoach-plan', JSON.stringify(PLAN)); } catch (e) { } }

/* ---------- IndexedDB ---------- */
const DB = (() => {
  let dbp;
  const open = () => dbp || (dbp = new Promise((res, rej) => {
    const r = indexedDB.open('tricoach', 1);
    r.onupgradeneeded = () => { const d = r.result; d.createObjectStore('acts', { keyPath: 'id' }); d.createObjectStore('well', { keyPath: 'key' }); };
    r.onsuccess = () => res(r.result); r.onerror = () => rej(r.error);
  }));
  const tx = async (store, mode, fn) => { const d = await open(); return new Promise((res, rej) => { const t = d.transaction(store, mode), st = t.objectStore(store); const out = fn(st); t.oncomplete = () => res(out?.result ?? out); t.onerror = () => rej(t.error); }); };
  return {
    all: store => tx(store, 'readonly', st => st.getAll()),
    put: (store, items) => tx(store, 'readwrite', st => { items.forEach(i => st.put(i)); }),
    del: (store, key) => tx(store, 'readwrite', st => st.delete(key)),
    clear: store => tx(store, 'readwrite', st => st.clear())
  };
})();

/* ---------- Laden & Ableiten ---------- */
async function loadData() {
  if (SET.source === 'demo') {
    ACTS = Demo.activities(); WELL = Demo.wellness();
    try { ACTS.push(...(await DB.all('acts')).filter(a => a.source === 'manual')); } catch (e) { } // eigene Einträge auch im Demo-Modus
  }
  else {
    try { ACTS = await DB.all('acts'); WELL = (await DB.all('well')).map(w => ({ ...w, date: new Date(w.date) })); }
    catch (e) { ACTS = []; WELL = []; toast('Lokaler Speicher nicht verfügbar: ' + e.message); }
  }
  recompute();
}
/* Doppelte Einheiten (gleiche Sportart, Start < 3 min auseinander) zusammenführen. Eigene Einträge bleiben immer erhalten. */
function dedupe(list) {
  const out = [];
  for (const a of [...list].sort((x, y) => (y.samples?.length || 0) - (x.samples?.length || 0))) {
    if (a.source === 'manual' || !out.some(b => b.source !== 'manual' && b.sport === a.sport && Math.abs(b.start - a.start) < 180000)) out.push(a);
  }
  return out;
}
/* Korrekturen an Uhr-Einheiten (z. B. geschwommene km, Name, RPE, Notizen, TrainingPeaks-Status) – überleben jeden Sync */
let EDITS = (() => { try { return JSON.parse(localStorage.getItem('tricoach-edits') || '{}'); } catch (e) { return {}; } })();
function saveEdits() { try { localStorage.setItem('tricoach-edits', JSON.stringify(EDITS)); } catch (e) { } }
function applyEdit(a) {
  const e = EDITS[a.id]; if (!e) return;
  if (a._orig === undefined) a._orig = { name: a.name, dist: a.dist };
  for (const k of ['name', 'dist', 'rpe', 'notes', 'tp', 'art', 'where']) if (e[k] !== undefined) a[k] = e[k];
}
function recompute() {
  NOW = new Date(); TODAY = sod(NOW);
  ACTS.forEach(a => { a.start = new Date(a.start); applyEdit(a); a.tss = tss(a); });
  ACTS = dedupe(ACTS).sort((a, b) => b.start - a.start);
  WELL.sort((a, b) => a.date - b.date);
  PMC = pmc(ACTS, addDays(TODAY, -180), TODAY);
  LOAD = PMC[PMC.length - 1] || { ctl: 0, atl: 0, tsb: 0 };
}
const byId = id => ACTS.find(a => a.id === id);
const planOn = d => PLAN.filter(p => sameDay(p.date, d)).sort((a, b) => a.date - b.date);
const doneFor = p => ACTS.find(a => a.sport === (p.sport || 'other') && sameDay(a.start, p.date));
const isDone = p => (p.kind || 'workout') === 'workout' && !!doneFor(p);

async function saveActivities(list) {
  if (!list.length) return;
  await DB.put('acts', list);
  if (SET.source !== 'demo') {
    const ids = new Set(list.map(a => a.id)), ext = new Set(list.map(a => a.extId).filter(Boolean));
    ACTS = ACTS.filter(a => !ids.has(a.id) && !(a.partial && ext.has(a.extId)));
    ACTS.push(...list); recompute();
  }
}

/* ---------- intervals.icu (bekommt die Einheiten automatisch aus Garmin Connect) ---------- */
const ICU = (() => {
  const base = 'https://intervals.icu/api/v1';
  const auth = () => ({ Authorization: 'Basic ' + btoa('API_KEY:' + SET.icuKey.trim()) });
  async function get(path, asBuffer) {
    const r = await fetch(base + path, { headers: auth() });
    if (r.status === 401 || r.status === 403) throw new Error('API-Key wird nicht akzeptiert. Bitte in den Einstellungen prüfen.');
    if (!r.ok) throw new Error(`intervals.icu antwortet mit ${r.status}`);
    return asBuffer ? r.arrayBuffer() : r.json();
  }
  const sportOf = t => /swim/i.test(t) ? 'swim' : /ride|cycl|bike/i.test(t) ? 'bike' : /run/i.test(t) ? 'run' : /weight|strength|workout|crossfit|hiit|pilates|yoga/i.test(t) ? 'strength' : 'other';

  async function test() { const a = await get('/athlete/0'); return a.name || a.firstname || 'verbunden'; }

  async function activityFromIcu(item) {
    const id = item.id, name = item.name;
    for (const p of [`/activity/${id}/file`, `/activity/${id}/fit-file`]) {
      try {
        const buf = await FIT.maybeGunzip(await get(p, true));
        if (FIT.isFit(buf)) {
          const acts = await FIT.parse(buf, id, 'icu');
          acts.forEach(a => { a.extId = String(id); if (name && acts.length === 1) a.name = name; });
          if (acts.length) return acts;
        }
      } catch (e) { if (/API-Key/.test(e.message)) throw e; }
    }
    // Fallback: nur Zusammenfassung
    const sport = sportOf(item.type || '');
    const a = {
      id: 'icu-' + id, extId: String(id), source: 'icu', partial: true, sport, name: name || NAME[sport],
      art: sport === 'other' ? (item.type || '') : undefined,
      start: new Date(item.start_date_local || item.start_date), dur: item.moving_time || item.elapsed_time || 0, dist: item.distance || 0,
      avgHr: item.average_heartrate ?? null, maxHr: item.max_heartrate ?? null, elev: item.total_elevation_gain ?? null, samples: [], laps: []
    };
    if (sport === 'swim') a.where = /open/i.test(item.type || '') ? 'ow' : item.pool_length ? Math.round(item.pool_length) : null;
    if (sport === 'bike' && item.icu_weighted_avg_watts) a.bike = { np: item.icu_weighted_avg_watts, ap: item.icu_average_watts };
    return [finalize(a)];
  }

  function wellnessFromIcu(w) {
    const date = new Date(w.id + 'T00:00:00');
    return {
      key: w.id, date, rhr: w.restingHR ?? null, hrv: w.hrv ?? w.hrvSDNN ?? null,
      sleep: w.sleepSecs ? { total: w.sleepSecs, score: w.sleepScore ?? null } : null,
      stress: w.stress ?? null, readiness: w.readiness ?? null, vo2: w.vo2max ?? null, steps: w.steps ?? null, weight: w.weight ?? null
    };
  }

  async function sync(onProgress) {
    const since = SET.lastSync ? addDays(new Date(SET.lastSync), -7) : addDays(new Date(), -SET.syncDays);
    const oldest = isoDay(since), newest = isoDay(addDays(new Date(), 1));
    const list = await get(`/athlete/0/activities?oldest=${oldest}&newest=${newest}`);
    // Einheiten ohne Herzfrequenz-Kurve (z. B. Datei war beim letzten Sync noch nicht fertig) werden erneut geladen
    const known = new Set(ACTS.filter(a => !a.partial).map(a => a.extId).filter(Boolean));
    const todo = list.filter(x => !known.has(String(x.id)));
    let done = 0, added = 0; ICU.lastNew = null;
    const queue = [...todo];
    const worker = async () => {
      while (queue.length) {
        const item = queue.shift();
        try { const acts = await activityFromIcu(item); await saveActivities(acts); added += acts.length; if (acts[0] && (!ICU.lastNew || acts[0].start > ICU.lastNew.start)) ICU.lastNew = acts[0]; }
        catch (e) { if (/API-Key/.test(e.message)) throw e; console.warn('Aktivität übersprungen', item.id, e); }
        onProgress?.(++done, todo.length);
      }
    };
    await Promise.all([worker(), worker(), worker()]);
    try {
      const well = (await get(`/athlete/0/wellness?oldest=${isoDay(addDays(since, -1))}&newest=${newest}`)).map(wellnessFromIcu);
      await DB.put('well', well);
      const map = new Map(WELL.map(w => [isoDay(w.date), w])); well.forEach(w => map.set(w.key, w)); WELL = [...map.values()];
    } catch (e) { console.warn('Wellness nicht geladen', e); }
    SET.lastSync = Date.now(); saveSettings(); recompute();
    return added;
  }
  return { sync, test, lastNew: null };
})();

/* ---------- Synchronisation steuern ---------- */
const SYNC = { busy: false, msg: '' };
async function runSync(manual) {
  if (SYNC.busy || SET.source !== 'icu' || !SET.icuKey) return;
  if (!navigator.onLine) { if (manual) toast('Offline – Synchronisation später.'); return; }
  SYNC.busy = true; SYNC.msg = 'Synchronisiere …'; render();
  try {
    const n = await ICU.sync((d, t) => { SYNC.msg = `Lade Einheiten ${d}/${t} …`; updateSyncBadge(); });
    SYNC.msg = '';
    if (n) { const a = ICU.lastNew, h = a && hrSummary(a); toast(n === 1 && h ? `Neu: ${a.name} · Ø ${Math.round(h.avg)} bpm, max ${Math.round(h.max)}` : `${n} neue Einheit${n === 1 ? '' : 'en'} von deiner Uhr`); }
    else if (manual) toast('Alles aktuell');
  } catch (e) { SYNC.msg = ''; toast(e.message); }
  SYNC.busy = false; render();
}

/* ---------- FIT-Import (Datei oder USB-Ordner der Uhr) ---------- */
async function importFitFiles(files) {
  const known = new Set(ACTS.map(a => a.id.replace(/-\d+$/, '')));
  const before = SET.source === 'demo' ? 0 : ACTS.length;
  let added = 0, skipped = 0;
  for (const f of files) {
    if (!/\.fit$/i.test(f.name)) continue;
    const id = f.name.replace(/\.fit$/i, '');
    if (known.has('fit-' + id)) { skipped++; continue; }
    try { const acts = await FIT.parse(await f.arrayBuffer(), id, 'fit'); await DB.put('acts', acts); added += acts.length; }
    catch (e) { console.warn(f.name, e); }
  }
  if (added && SET.source === 'demo') { SET.source = 'fit'; saveSettings(); }
  await loadData();
  if (added) { const fresh = ACTS.length - before; skipped += added - fresh; added = fresh; }
  toast(added ? `${added} Einheit${added === 1 ? '' : 'en'} importiert${skipped ? `, ${skipped} schon vorhanden` : ''}` : (skipped ? 'Alle Dateien waren schon importiert' : 'Keine gültigen FIT-Dateien gefunden'));
  render();
}
async function importFromWatchFolder() {
  if (!window.showDirectoryPicker) { toast('Ordnerauswahl geht nur in Chrome oder Edge am PC. Nutze „FIT-Dateien wählen“.'); return; }
  try {
    const dir = await window.showDirectoryPicker({ id: 'garmin-activity', mode: 'read' });
    let target = dir;
    // Falls das Laufwerk statt des Ordners gewählt wurde: GARMIN/Activity suchen
    try { target = await (await dir.getDirectoryHandle('GARMIN')).getDirectoryHandle('Activity'); } catch (e) { try { target = await dir.getDirectoryHandle('Activity'); } catch (e2) { } }
    const files = [];
    for await (const [name, h] of target.entries()) if (h.kind === 'file' && /\.fit$/i.test(name)) files.push(await h.getFile());
    await importFitFiles(files);
  } catch (e) { if (e.name !== 'AbortError') toast(e.message); }
}
