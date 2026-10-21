'use strict';
/* TriCoach – App-Steuerung: Navigation, Ereignisse, Service Worker, Auto-Sync */

const S = { view: 'dashboard', back: null, period: 'week', metric: 'hr', day: sod(new Date()), intSel: null, curveDays: 90, act: null, live: null, speed: 1, mapSport: 'all', mapDays: 90, confirmWipe: false, sheet: null, calQ: '', calSearch: false, calFilter: false };
let DEFERRED_INSTALL = null, WAITING_SW = null;

const NAV = [
  ['Übersicht', [['dashboard', 'Dashboard', 'dash'], ['calendar', 'Kalender', 'cal'], ['progress', 'Fortschritt', 'rings']]],
  ['Disziplinen', [['swim', 'Schwimmen', 'swim'], ['bike', 'Radfahren', 'bike'], ['run', 'Laufen', 'run']]],
  ['Werkzeuge', [['race', 'Wettkampf', 'flag'], ['wellness', 'Schlaf & Stress', 'moon'], ['pulse', 'Live-Puls', 'heart'], ['map', 'Karte', 'map']]],
  ['', [['settings', 'Einstellungen', 'gear']]]
];
const TABS = [['dashboard', 'Start', 'dash'], ['calendar', 'Kalender', 'cal'], ['progress', 'Fortschritt', 'rings'], ['analyse', 'Analyse', 'chart'], ['settings', 'Mehr', 'gear']];
const NAVCOLOR = { swim: 'var(--swim)', bike: 'var(--bike)', run: 'var(--run)', race: 'var(--accent)', wellness: 'var(--sleep)', pulse: 'var(--bad)', map: 'var(--fit)', progress: 'var(--good)' };
const VIEWS = { dashboard: vDashboard, calendar: vCalendar, progress: vProgress, analyse: vAnalyse, run: vRun, bike: vBike, swim: vSwim, wellness: vWellness, race: vRace, live: vLive, activity: vActivity, settings: vSettings, pulse: vPulse, map: vMap };

function shell() {
  const cur = S.view === 'activity' ? S.back : S.view === 'live' ? 'race' : S.view;
  document.getElementById('side').innerHTML = `<div class="brand"><i>${ICON.bolt}</i>TriCoach</div>` +
    NAV.map(([h, items]) => `<div class="navgroup">${h ? `<h4>${h}</h4>` : ''}${items.map(([id, l, ic]) => `<button class="navbtn ${cur === id ? 'on' : ''}" data-act="nav:${id}"><span style="color:${NAVCOLOR[id] || 'var(--fg)'}">${ICON[ic]}</span>${l}</button>`).join('')}</div>`).join('') +
    `<div class="note">Version ${APP_VERSION}${SET.source === 'icu' && SET.lastSync ? `<br>Sync: ${time(new Date(SET.lastSync))}` : ''}</div>`;
  const tabCur = ['swim', 'bike', 'run', 'wellness', 'analyse', 'pulse', 'map', 'race'].includes(cur) ? 'analyse' : cur;
  document.getElementById('tabbar').innerHTML = TABS.map(([id, l, ic]) => `<button class="${tabCur === id ? 'on' : ''}" data-act="nav:${id}">${ICON[ic]}<span>${l}</span></button>`).join('');
}
const SHEETS = { plan: planSheet, log: logSheet, tp: tpSheet, tprace: tpRaceSheet, add: addMenuSheet, goals: goalsSheet };
function render() {
  shell();
  const c = document.getElementById('content');
  try { c.innerHTML = VIEWS[S.view](); }
  catch (e) { console.error(e); c.innerHTML = header('Fehler') + `<div class="card">${empty('Diese Ansicht konnte nicht geladen werden', esc(e.message))}</div>`; }
  renderSheet();
  document.getElementById('fab').hidden = !!S.sheet || ['live', 'settings', 'pulse'].includes(S.view);
}
function renderSheet() {
  const el = document.getElementById('sheet'), was = el.dataset.open;
  let html = '';
  try { html = S.sheet ? SHEETS[S.sheet.t]() : ''; } catch (e) { console.error(e); html = ''; S.sheet = null; }
  const sb = el.querySelector('.sheet-body'), top = sb ? sb.scrollTop : 0;
  el.innerHTML = html; el.dataset.open = S.sheet ? S.sheet.t : '';
  document.body.classList.toggle('noscroll', !!S.sheet);
  if (S.sheet && was === S.sheet.t) { const nb = el.querySelector('.sheet-body'); if (nb) nb.scrollTop = top; }
}
/* Formular-Stand sichern und Sheet neu aufbauen (z. B. nach Wechsel der Sportart) */
function refreshSheet() { if (S.sheet?.t === 'plan') readPlanForm(); if (S.sheet?.t === 'log') readLogForm(); renderSheet(); }
const closeSheet = () => { S.sheet = null; render(); };
function toast(msg) {
  const t = document.getElementById('toast'); t.textContent = msg; t.hidden = false;
  clearTimeout(t._h); t._h = setTimeout(() => { t.hidden = true; }, 3500);
}

/* ---------- Navigation ---------- */
function go(view) {
  const [v, anchor] = view.split('#');
  if (v !== S.view && !['activity', 'live'].includes(S.view)) S.back = S.view;
  S.view = v; S.sheet = null; S.confirmWipe = false; window.scrollTo(0, 0); render(); syncLiveTimer();
  if (anchor) setTimeout(() => document.getElementById(anchor)?.scrollIntoView({ behavior: 'smooth', block: 'start' }), 60);
}
function calMove(n) {
  const v = SET.calView, d = S.day;
  S.day = v === 'day' ? addDays(d, n) : v === 'week' ? addDays(d, 7 * n) : v === 'year' ? new Date(d.getFullYear() + n, d.getMonth(), 1) : v === 'list' ? addDays(d, 30 * n) : new Date(d.getFullYear(), d.getMonth() + n, 1);
}
let liveTimer = null, pulseTimer = null;
function syncLiveTimer() {
  clearInterval(liveTimer); clearInterval(pulseTimer);
  if (S.view === 'live' && S.live?.started && S.live.splits.length < 5) liveTimer = setInterval(render, 250);
  if (S.view === 'pulse' && BLE.st.rec) pulseTimer = setInterval(renderLiveHr, 1000);
}
function liveNow() { const L = S.live; return L?.started ? (performance.now() - L.t0) / 1000 * S.speed + L.offset : 0; }

document.addEventListener('click', async e => {
  const el = e.target.closest('[data-act]'); if (!el) return;
  const [k, v] = el.dataset.act.split(/:(.*)/s);
  switch (k) {
    case 'nav': S.back = null; go(v); break;
    case 'back': { const b = S.view === 'live' ? 'race' : (S.back && S.back !== S.view ? S.back : (['swim', 'bike', 'run', 'wellness', 'pulse', 'map'].includes(S.view) ? 'analyse' : 'dashboard')); S.back = null; S.view = b; window.scrollTo(0, 0); render(); syncLiveTimer(); break; }
    case 'open': S.back = S.view; S.act = v; S.metric = 'hr'; S.view = 'activity'; window.scrollTo(0, 0); render(); break;
    case 'period': S.period = v; render(); break;
    case 'metric': S.metric = v; render(); break;
    case 'curve': S.curveDays = +v; render(); break;
    case 'mapsport': S.mapSport = v; render(); break;
    case 'mapdays': S.mapDays = +v; render(); break;
    case 'day': S.day = new Date(+v); render(); break;
    case 'calview': SET.calView = v; S.calQ = ''; S.calSearch = false; saveSettings(); if (S.view !== 'calendar') go('calendar'); else render(); break;
    case 'calmove': calMove(+v); render(); break;
    case 'caltoday': S.day = sod(new Date()); render(); break;
    case 'gotoday': S.day = new Date(+v); SET.calView = 'day'; saveSettings(); render(); break;
    case 'gomonth': S.day = new Date(+v); SET.calView = 'month'; saveSettings(); render(); break;
    case 'calsearch': S.calSearch = !S.calSearch; if (!S.calSearch) S.calQ = ''; render(); if (S.calSearch) document.getElementById('calq')?.focus(); break;
    case 'calfilter': S.calFilter = !S.calFilter; render(); break;
    case 'caltoggle': SET.calHidden = SET.calHidden.includes(v) ? SET.calHidden.filter(x => x !== v) : [...SET.calHidden, v]; saveSettings(); render(); break;
    case 'ics': exportIcs(); break;
    case 'addmenu': S.sheet = { t: 'add' }; render(); break;
    case 'sheet-close': if (e.target === el || el.tagName === 'BUTTON') closeSheet(); break;
    case 'new': S.sheet = { t: 'plan', id: null, d: newDraft('workout', +v) }; render(); break;
    case 'newk': { const [k, t] = v.split('|'); S.sheet = { t: 'plan', id: null, d: newDraft(k, +t) }; render(); break; }
    case 'edit': openPlanEditor(v); break;
    case 'kind': readPlanForm(); S.sheet.d.kind = v; if (v === 'workout' && !S.sheet.d.sport) S.sheet.d.sport = 'run'; if (v === 'race' && S.sheet.d.alarm == null) S.sheet.d.alarm = 1440; renderSheet(); break;
    case 'pdel': deletePlan(v); break;
    case 'pdup': duplicatePlan(); break;
    case 'pics': readPlanForm(); exportIcs([{ ...masterOf(S.sheet.id), ...(!S.sheet.occ ? S.sheet.d : {}) }], (S.sheet.d.title || 'Termin').replace(/[^\wäöüÄÖÜß-]+/g, '-')); break;
    case 'plan2log': planToLog(); break;
    case 'log': openLog(+v, S.view === 'swim' ? 'swim' : undefined); break;
    case 'lsport': readLogForm(); S.sheet.d.sport = v; S.sheet.d.art = ''; if (!hasDist(v)) S.sheet.d.dist = null; renderSheet(); break;
    case 'lkm': readLogForm(); S.sheet.d.dist = Math.round(+v * 1000); S.sheet.d.lanes = null; renderSheet(); break;
    case 'lexadd': readLogForm(); S.sheet.d.ex.push({ n: '', s: 3, r: '10', w: null }); renderSheet(); setTimeout(() => document.querySelector(`[name="ex-n${S.sheet.d.ex.length - 1}"]`)?.focus(), 30); break;
    case 'lexdel': readLogForm(); S.sheet.d.ex.splice(+v, 1); renderSheet(); break;
    case 'editact': openLogEdit(v); break;
    case 'tpact': S.sheet = { t: 'tp', id: v }; render(); break;
    case 'tp-health': { const a = byId(v); if (a) sendToHealth(a); render(); break; }
    case 'tp-fit': downloadFit(v); break;
    case 'tp-copy': { const a = byId(v); if (a && await copyText(actSummary(a))) toast('Kopiert – in TrainingPeaks einfügen'); break; }
    case 'tp-mark': { const [id, how] = v.split('|'); markTp(id, how || null); render(); break; }
    case 'tp-race': readPlanForm(); S.sheet = { t: 'tprace', p: { ...S.sheet.d, id: S.sheet.id }, back: S.sheet }; render(); break;
    case 'tp-rcopy': if (await copyText(raceSummary(S.sheet.p))) toast('Kopiert – jetzt TrainingPeaks öffnen'); break;
    case 'tp-rdone': { const m = masterOf(S.sheet.p.id); if (m) { m.tp = !m.tp; savePlan(); toast(m.tp ? 'Als „in TrainingPeaks“ markiert' : 'Markierung entfernt'); } S.sheet = null; render(); break; }
    case 'goals': S.sheet = { t: 'goals' }; render(); break;
    case 'notify': if (window.Notification) { const r = await Notification.requestPermission(); toast(r === 'granted' ? 'Mitteilungen erlaubt' : 'Mitteilungen nicht erlaubt'); render(); } else toast('Mitteilungen gehen auf dem iPhone nur, wenn TriCoach auf dem Home-Bildschirm installiert ist.'); break;
    case 'accept': { const r = recommendations()[+v]; if (r?.w) { PLAN.push({ id: 'p' + Date.now(), kind: 'workout', date: r.w.date, sport: r.w.sport, title: r.w.title, min: r.w.min }); savePlan(); el.outerHTML = '<span class="cap good">✓ Im Kalender eingetragen</span>'; } break; }
    case 'applyftp': P.ftp = +v; saveSettings(); recompute(); toast(`FTP auf ${v} W gesetzt`); render(); break;
    case 'applycss': P.css = +v; saveSettings(); recompute(); toast(`CSS auf ${pv(+v)} gesetzt`); render(); break;
    case 'live-open': S.live = { started: false, splits: [], fuel: [], t0: 0, offset: 0, segStart: 0 }; S.back = 'race'; S.view = 'live'; window.scrollTo(0, 0); render(); requestWakeLock(); break;
    case 'live-next': { const L = S.live, n = liveNow(); if (!L.started) { L.started = true; L.t0 = performance.now(); L.offset = 0; L.segStart = 0; } else { L.splits.push(n - L.segStart); L.segStart = n; } navigator.vibrate?.(80); render(); syncLiveTimer(); break; }
    case 'fuel': S.live.fuel.push(FUEL[+v]); render(); break;
    case 'sync': runSync(true); break;
    case 'watchfolder': importFromWatchFolder(); break;
    case 'design': SET.design = v; saveSettings(); applyDesign(); render(); break;
    case 'install': if (DEFERRED_INSTALL) { DEFERRED_INSTALL.prompt(); await DEFERRED_INSTALL.userChoice; DEFERRED_INSTALL = null; render(); } break;
    case 'checkupdate': await checkForUpdate(true); break;
    case 'update': if (WAITING_SW) WAITING_SW.postMessage('skipWaiting'); else location.reload(); break;
    case 'backup': backup(); break;
    case 'wipe': S.confirmWipe = true; render(); break;
    case 'wipe-no': S.confirmWipe = false; render(); break;
    case 'wipe-yes': await DB.clear('acts'); await DB.clear('well'); SET.lastSync = null; saveSettings(); S.confirmWipe = false; await loadData(); toast('Trainingsdaten gelöscht'); render(); break;
    case 'delact': await DB.del('acts', v); ACTS = ACTS.filter(a => a.id !== v); recompute(); S.sheet = null; if (S.view === 'activity') S.view = S.back || 'dashboard'; render(); toast('Einheit gelöscht'); break;
    case 'ble-on': await BLE.connect(); break;
    case 'ble-off': BLE.disconnect(); break;
    case 'ble-rec': BLE.start(); syncLiveTimer(); break;
    case 'ble-stop': await BLE.stop(true); syncLiveTimer(); break;
    case 'ble-cancel': await BLE.stop(false); syncLiveTimer(); break;
  }
});
document.addEventListener('change', async e => {
  const t = e.target, k = t.dataset.change;
  if (k === 'int') { S.intSel = t.value; render(); }
  if (k === 'wetsuit') { SET.wetsuit = t.checked; saveSettings(); render(); }
  if (k === 'blesport') BLE.st.sport = t.value;
  if (k === 'demo') { SET.source = t.checked ? 'demo' : (SET.icuKey ? 'icu' : 'fit'); saveSettings(); await loadData(); render(); if (SET.source === 'icu') runSync(); }
  if (k === 'speed') { if (S.live?.started) { const n = liveNow(); S.live.offset = n; S.live.t0 = performance.now(); } S.speed = t.checked ? 60 : 1; render(); }
  if (t.id === 'fitfiles' && t.files?.length) importFitFiles([...t.files]);
  if (k === 'sheet') refreshSheet();
  if (k === 'showdone') { SET.showDone = t.checked; saveSettings(); render(); }
  if (t.id === 'icsfile' && t.files?.[0]) { importIcs(await t.files[0].text()); t.value = ''; }
});
document.addEventListener('input', e => {
  if (e.target.dataset.change === 'calq') { S.calQ = e.target.value; clearTimeout(window._cq); window._cq = setTimeout(() => { const pos = e.target.selectionStart; render(); const q = document.getElementById('calq'); if (q) { q.focus(); q.setSelectionRange(pos, pos); } }, 180); return; }
  if (e.target.dataset.change === 'cda') {
    SET.cda = +e.target.value; clearTimeout(window._cd);
    window._cd = setTimeout(() => { saveSettings(); const y = window.scrollY; render(); window.scrollTo(0, y); document.getElementById('cda')?.focus(); }, 120);
  }
});
document.addEventListener('submit', async e => {
  e.preventDefault();
  const id = e.target.id;
  if (id === 'planform') savePlanSheet(e.submitter?.value || 'all');
  else if (id === 'logform') await saveLog();
  else if (id === 'goalform') saveGoals();
  else await handleSettingsSubmit(id);
});
let rz; window.addEventListener('resize', () => { clearTimeout(rz); rz = setTimeout(render, 150); });

/* ---------- Bildschirm an lassen im Wettkampfmodus ---------- */
async function requestWakeLock() { try { await navigator.wakeLock?.request('screen'); } catch (e) { } }

/* ---------- Installation & Updates ---------- */
window.addEventListener('beforeinstallprompt', e => { e.preventDefault(); DEFERRED_INSTALL = e; if (S.view === 'settings') render(); });
window.addEventListener('appinstalled', () => { DEFERRED_INSTALL = null; toast('TriCoach installiert'); });

function showUpdateBanner() {
  const b = document.getElementById('updatebar'); b.hidden = false;
}
async function checkForUpdate(manual) {
  const reg = await navigator.serviceWorker?.getRegistration();
  if (!reg) { if (manual) toast('Updates funktionieren, sobald TriCoach über seine Web-Adresse läuft.'); return; }
  await reg.update();
  if (reg.waiting) { WAITING_SW = reg.waiting; showUpdateBanner(); }
  else if (manual) toast('Du hast die neueste Version');
}
if ('serviceWorker' in navigator && location.protocol.startsWith('http')) {
  navigator.serviceWorker.register('sw.js').then(reg => {
    if (reg.waiting) { WAITING_SW = reg.waiting; showUpdateBanner(); }
    reg.addEventListener('updatefound', () => {
      const nw = reg.installing;
      nw?.addEventListener('statechange', () => { if (nw.state === 'installed' && navigator.serviceWorker.controller) { WAITING_SW = nw; showUpdateBanner(); } });
    });
  }).catch(e => console.warn('Service Worker', e));
  let reloaded = false;
  navigator.serviceWorker.addEventListener('controllerchange', () => { if (!reloaded) { reloaded = true; location.reload(); } });
}

/* ---------- Auto-Sync: beim Öffnen, beim Zurückkehren und alle 5 Minuten ---------- */
function autoSync() { if (SET.source === 'icu' && (!SET.lastSync || Date.now() - SET.lastSync > 3 * 60000)) runSync(false); }
document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'visible') { recompute(); autoSync(); checkForUpdate(false); checkAlarms(); if (!S.sheet) render(); } });
setInterval(() => { if (document.visibilityState === 'visible') { autoSync(); checkAlarms(); } }, 60000);
document.addEventListener('keydown', e => { if (e.key === 'Escape' && S.sheet) closeSheet(); });
window.addEventListener('online', autoSync);

/* ---------- Start ---------- */
(async () => {
  applyDesign();
  const hash = location.hash.slice(1);
  if (VIEWS[hash] && !['activity', 'live'].includes(hash)) S.view = hash;
  await loadData();
  if (hash === 'log') S.sheet = { t: 'log', id: null, d: newLog(at(TODAY, Math.max(6, NOW.getHours() - 1))) };   // Kurzbefehl/Siri: „TriCoach eintragen“
  if (hash === 'new') S.sheet = { t: 'add' };
  render();
  autoSync(); checkAlarms();
  if (SET.tpIcal && (!SET.tpIcalAt || Date.now() - SET.tpIcalAt > 6 * 3600000)) fetchTpIcal(false);
})();
