'use strict';
/* TriCoach – App-Steuerung: Navigation, Ereignisse, Service Worker, Auto-Sync */

const S = { view: 'dashboard', back: null, period: 'week', metric: 'hr', month: monthStart(new Date()), day: sod(new Date()), intSel: null, curveDays: 90, act: null, form: false, live: null, speed: 1, mapSport: 'all', mapDays: 90, confirmWipe: false };
let DEFERRED_INSTALL = null, WAITING_SW = null;

const NAV = [
  ['Übersicht', [['dashboard', 'Dashboard', 'dash'], ['calendar', 'Kalender', 'cal']]],
  ['Disziplinen', [['swim', 'Schwimmen', 'swim'], ['bike', 'Radfahren', 'bike'], ['run', 'Laufen', 'run']]],
  ['Werkzeuge', [['race', 'Wettkampf', 'flag'], ['wellness', 'Schlaf & Stress', 'moon'], ['pulse', 'Live-Puls', 'heart'], ['map', 'Karte', 'map']]],
  ['', [['settings', 'Einstellungen', 'gear']]]
];
const TABS = [['dashboard', 'Start', 'dash'], ['calendar', 'Kalender', 'cal'], ['analyse', 'Analyse', 'chart'], ['race', 'Wettkampf', 'flag'], ['settings', 'Mehr', 'gear']];
const NAVCOLOR = { swim: 'var(--swim)', bike: 'var(--bike)', run: 'var(--run)', race: 'var(--accent)', wellness: 'var(--sleep)', pulse: 'var(--bad)', map: 'var(--fit)' };
const VIEWS = { dashboard: vDashboard, calendar: vCalendar, analyse: vAnalyse, run: vRun, bike: vBike, swim: vSwim, wellness: vWellness, race: vRace, live: vLive, activity: vActivity, settings: vSettings, pulse: vPulse, map: vMap };

function shell() {
  const cur = S.view === 'activity' ? S.back : S.view === 'live' ? 'race' : S.view;
  document.getElementById('side').innerHTML = `<div class="brand"><i>${ICON.bolt}</i>TriCoach</div>` +
    NAV.map(([h, items]) => `<div class="navgroup">${h ? `<h4>${h}</h4>` : ''}${items.map(([id, l, ic]) => `<button class="navbtn ${cur === id ? 'on' : ''}" data-act="nav:${id}"><span style="color:${NAVCOLOR[id] || 'var(--fg)'}">${ICON[ic]}</span>${l}</button>`).join('')}</div>`).join('') +
    `<div class="note">Version ${APP_VERSION}${SET.source === 'icu' && SET.lastSync ? `<br>Sync: ${time(new Date(SET.lastSync))}` : ''}</div>`;
  const tabCur = ['swim', 'bike', 'run', 'wellness', 'analyse', 'pulse', 'map'].includes(cur) ? 'analyse' : cur;
  document.getElementById('tabbar').innerHTML = TABS.map(([id, l, ic]) => `<button class="${tabCur === id ? 'on' : ''}" data-act="nav:${id}">${ICON[ic]}<span>${l}</span></button>`).join('');
}
function render() {
  shell();
  const c = document.getElementById('content');
  try { c.innerHTML = VIEWS[S.view](); }
  catch (e) { console.error(e); c.innerHTML = header('Fehler') + `<div class="card">${empty('Diese Ansicht konnte nicht geladen werden', esc(e.message))}</div>`; }
}
function toast(msg) {
  const t = document.getElementById('toast'); t.textContent = msg; t.hidden = false;
  clearTimeout(t._h); t._h = setTimeout(() => { t.hidden = true; }, 3500);
}

/* ---------- Navigation ---------- */
function go(view) {
  if (view !== S.view && !['activity', 'live'].includes(S.view)) S.back = S.view;
  S.view = view; S.form = false; S.confirmWipe = false; window.scrollTo(0, 0); render(); syncLiveTimer();
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
    case 'month': S.month = new Date(S.month.getFullYear(), S.month.getMonth() + +v, 1); render(); break;
    case 'day': S.day = new Date(+v); S.form = false; render(); break;
    case 'form': S.form = true; render(); break;
    case 'del': PLAN = PLAN.filter(p => p.id !== v); savePlan(); render(); break;
    case 'ics': exportIcs(); break;
    case 'accept': { const r = recommendations()[+v]; if (r?.w) { PLAN.push({ id: 'p' + Date.now(), date: r.w.date, sport: r.w.sport, title: r.w.title, min: r.w.min }); savePlan(); el.outerHTML = '<span class="cap good">✓ Im Kalender eingetragen</span>'; } break; }
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
    case 'delact': await DB.del('acts', v); ACTS = ACTS.filter(a => a.id !== v); recompute(); S.view = S.back || 'dashboard'; render(); break;
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
  if (t.id === 'f-sport') document.getElementById('f-title').value = { run: 'Lauf', bike: 'Radeinheit', swim: 'Schwimmen' }[t.value];
});
document.addEventListener('input', e => {
  if (e.target.dataset.change === 'cda') {
    SET.cda = +e.target.value; clearTimeout(window._cd);
    window._cd = setTimeout(() => { saveSettings(); const y = window.scrollY; render(); window.scrollTo(0, y); document.getElementById('cda')?.focus(); }, 120);
  }
});
document.addEventListener('submit', async e => {
  e.preventDefault();
  const id = e.target.id;
  if (id === 'planform') {
    const [hh, mm] = document.getElementById('f-time').value.split(':').map(Number), d = at(S.day, hh || 18, mm || 0);
    PLAN.push({ id: 'p' + Date.now(), date: d, sport: document.getElementById('f-sport').value, title: document.getElementById('f-title').value || 'Training', min: +document.getElementById('f-min').value || 60 });
    savePlan(); S.form = false; render();
  } else await handleSettingsSubmit(id);
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
document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'visible') { recompute(); autoSync(); checkForUpdate(false); render(); } });
setInterval(() => { if (document.visibilityState === 'visible') autoSync(); }, 5 * 60000);
window.addEventListener('online', autoSync);

/* ---------- Start ---------- */
(async () => {
  applyDesign();
  const hash = location.hash.slice(1);
  if (VIEWS[hash] && !['activity', 'live'].includes(hash)) S.view = hash;
  await loadData();
  render();
  autoSync();
})();
