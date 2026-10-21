'use strict';
/* TriCoach – Einstellungen: Uhr verbinden, Design, Profil, Wettkampf, Installation, Updates */

const DESIGNS = [
  { id: 'nacht', name: 'Nacht', desc: 'Dunkel, kräftige Sportfarben – der Standard.', sw: ['#0b0d12', '#151822', '#f24566', '#33b8f2', '#ff9426', '#4dd973'], theme: '#0b0d12' },
  { id: 'gletscher', name: 'Gletscher', desc: 'Hell und luftig, gut lesbar draußen in der Sonne.', sw: ['#eef2f6', '#ffffff', '#2453ff', '#0a8fd1', '#e36b00', '#11a34a'], theme: '#eef2f6' },
  { id: 'asphalt', name: 'Asphalt', desc: 'Grafit mit Signalorange, kantig wie eine Startnummer.', sw: ['#18191c', '#222327', '#ff6a13', '#4cc3ff', '#ffb000', '#9be564'], theme: '#18191c' },
  { id: 'nordsee', name: 'Nordsee', desc: 'Tiefes Petrol mit Korallen-Akzent, ruhig und warm.', sw: ['#06222b', '#0b3340', '#ff7a59', '#5fd4ff', '#ffc15e', '#7ef0a8'], theme: '#06222b' },
];

function applyDesign() {
  document.documentElement.dataset.design = SET.design;
  const d = DESIGNS.find(x => x.id === SET.design) || DESIGNS[0];
  document.querySelector('meta[name=theme-color]')?.setAttribute('content', d.theme);
}

const isIOS = () => /iPad|iPhone|iPod/.test(navigator.userAgent) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
const isStandalone = () => window.matchMedia('(display-mode: standalone)').matches || navigator.standalone === true;

function vSettings() {
  let h = header('Einstellungen');
  const src = SET.source;

  // Uhr verbinden
  h += `<div class="card"><h3>${icon('watch')} Forerunner verbinden <small>${src === 'icu' ? 'automatisch' : src === 'fit' ? 'FIT-Import' : 'Demo-Daten aktiv'}</small></h3>
    <div class="opt ${src === 'icu' ? 'on' : ''}"><b>Automatisch nach jedem Training <span class="tag">empfohlen</span></b>
      <span class="cap fg">Deine Uhr synct per Bluetooth mit der Garmin-Connect-App. Von dort schickt der kostenlose Dienst intervals.icu jede beendete Einheit sofort weiter, TriCoach holt sie beim Öffnen und alle 5 Minuten ab – inklusive Schlaf, HRV und Ruhepuls.</span>
      <ol class="steps"><li>Auf <a href="https://intervals.icu" target="_blank" rel="noopener">intervals.icu</a> kostenlos registrieren.</li><li>Dort <b>Settings → Connections → Garmin Connect → Connect</b> und Garmin-Login bestätigen (inkl. „Wellness“).</li><li>In intervals.icu <b>Settings → Developer Settings → API Key</b> erzeugen und hier einfügen.</li></ol>
      <form id="icuform" class="plan"><label style="grid-column:1/-1">API-Key<input id="icukey" type="password" autocomplete="off" placeholder="z. B. 3k9…" value="${esc(SET.icuKey)}"></label><label>Erster Import<select id="icudays">${[30, 90, 120, 180, 365].map(d => `<option value="${d}" ${SET.syncDays === d ? 'selected' : ''}>${d} Tage</option>`).join('')}</select></label><button class="btn primary" type="submit">${src === 'icu' ? 'Speichern & synchronisieren' : 'Verbinden'}</button></form>
      ${src === 'icu' ? `<div class="row" style="flex-wrap:wrap"><button class="btn" data-act="sync">${icon('sync', 14)} Jetzt synchronisieren</button><span class="cap">${SET.lastSync ? 'Zuletzt: ' + new Date(SET.lastSync).toLocaleString('de-DE') : ''} · ${ACTS.length} Einheiten</span></div>` : ''}
    </div>
    <div class="opt ${src === 'fit' ? 'on' : ''}"><b>Direkt per USB-Kabel (PC)</b><span class="cap fg">Uhr per Kabel anstecken, dann den Ordner <b>GARMIN/Activity</b> auf der Uhr wählen (Chrome/Edge). Oder einzelne .fit-Dateien auswählen, z. B. aus Garmin Connect exportiert.</span>
      <div class="row" style="flex-wrap:wrap"><button class="btn" data-act="watchfolder">Uhr-Ordner wählen</button><label class="btn" for="fitfiles" style="cursor:pointer">FIT-Dateien wählen</label><input id="fitfiles" type="file" accept=".fit,.FIT" multiple hidden></div></div>
    <div class="opt"><b>Live-Puls per Bluetooth</b><span class="cap fg">Die Uhr als Pulsgurt nutzen, z. B. beim Indoor-Training am PC.</span><div><button class="btn" data-act="nav:pulse">Live-Puls öffnen</button></div></div>
    <label class="toggle"><input type="checkbox" id="demo" data-change="demo" ${src === 'demo' ? 'checked' : ''}> Demo-Daten anzeigen</label></div>`;

  // TrainingPeaks & Schule
  h += tpSettingsCard();
  h += schoolSettingsCard();

  // Kalender & Hinweise
  const perm = window.Notification?.permission;
  h += `<div class="card"><h3>${icon('bell')} Kalender &amp; Hinweise</h3><span class="cap fg">Hinweise (z. B. „1 Tag vorher“) zeigt TriCoach, solange die App offen ist. Zuverlässig auch bei geschlossener App: im Kalender <b>„An Apple Kalender senden“</b> – dann erinnert dich Apple Kalender, inklusive Wiederholungen.</span>
    <div class="row" style="flex-wrap:wrap">${perm === 'granted' ? '<b class="good">✓ Mitteilungen erlaubt</b>' : `<button class="btn" data-act="notify">${icon('bell', 14)} Mitteilungen erlauben</button>`}<button class="btn" data-act="ics">${icon('share', 14)} An Apple Kalender senden</button></div>
    <span class="cap">Siri &amp; Kurzbefehle: Ein Kurzbefehl „URL öffnen“ mit <code>${esc(location.origin + location.pathname)}#log</code> öffnet direkt „Einheit eintragen“ – z. B. „Hey Siri, Training eintragen“.</span></div>`;

  // Design
  h += `<div class="card"><h3>Design</h3><div class="designs">${DESIGNS.map(d => `<button class="design ${SET.design === d.id ? 'on' : ''}" data-act="design:${d.id}"><span class="swatch" style="background:${d.sw[0]}"><i style="background:${d.sw[1]}"></i><em style="background:${d.sw[2]}"></em><u style="background:${d.sw[3]}"></u><u style="background:${d.sw[4]}"></u><u style="background:${d.sw[5]}"></u></span><b>${d.name}</b><span class="cap">${d.desc}</span></button>`).join('')}</div></div>`;

  // Profil
  const f = (id, label, val, attrs = '') => `<label>${label}<input id="${id}" value="${val}" ${attrs}></label>`;
  h += `<div class="card"><h3>Profil &amp; Schwellenwerte</h3><form id="profform" class="plan">
    ${f('p-weight', 'Gewicht (kg)', P.weight, 'type="number" step="0.1" min="35" max="150"')}${f('p-ftp', 'FTP (W)', P.ftp, 'type="number" min="80" max="600"')}${f('p-lthr', 'Laktatschwelle HF', P.lthr, 'type="number" min="100" max="220"')}${f('p-maxhr', 'Max. HF', P.maxHr, 'type="number" min="120" max="240"')}${f('p-rhr', 'Ruhepuls', P.rhr, 'type="number" min="25" max="100"')}${f('p-pace', 'Schwellenpace (min/km)', pv(P.thrPace), 'pattern="\\d{1,2}:\\d{2}"')}${f('p-css', 'CSS (min/100 m)', pv(P.css), 'pattern="\\d{1,2}:\\d{2}"')}${f('p-bike', 'Radgewicht (kg)', P.bikeKg, 'type="number" step="0.1" min="5" max="25"')}
    <button class="btn primary" type="submit">Speichern</button></form><span class="cap">Bestimmt Zonen, Trainingsbelastung (TSS) und Prognosen.</span></div>`;

  // Wettkampf
  h += `<div class="card"><h3>${icon('flag')} Saisonziel</h3><form id="raceform" class="plan">
    <label>Name<input id="r-name" value="${esc(RACE.name)}"></label><label>Datum<input id="r-date" type="date" value="${isoDay(RACE.date)}"></label>
    <label>Distanz<select id="r-fmt">${Object.entries(FMT).map(([k, v]) => `<option value="${k}" ${RACE.fmt === k ? 'selected' : ''}>${v.name}</option>`).join('')}</select></label>
    <label>Temperatur (°C)<input id="r-temp" type="number" min="5" max="40" value="${RACE.temp ?? 20}"></label>
    <label>Radstrecke<select id="r-hills">${[[0, 'flach'], [.4, 'wellig'], [.8, 'hügelig']].map(([v, l]) => `<option value="${v}" ${(RACE.hills || 0) == v ? 'selected' : ''}>${l}</option>`).join('')}</select></label>
    <button class="btn primary" type="submit">Speichern</button></form></div>`;

  // Installieren
  const inst = isStandalone() ? `<b class="good">✓ TriCoach ist auf diesem Gerät installiert.</b>` :
    isIOS() ? `<ol class="steps"><li>Diese Seite in <b>Safari</b> öffnen.</li><li>Unten auf <b>Teilen</b> (Quadrat mit Pfeil) tippen.</li><li><b>„Zum Home-Bildschirm“</b> → <b>Hinzufügen</b>. Das TriCoach-Icon erscheint auf dem Startbildschirm.</li></ol>` :
    (DEFERRED_INSTALL ? `<div><button class="btn primary" data-act="install">TriCoach installieren</button></div>` : '') + `<ol class="steps"><li><b>PC (Edge/Chrome):</b> In der Adressleiste auf das Symbol „App installieren“ klicken. TriCoach erscheint im Startmenü und läuft im eigenen Fenster.</li><li><b>Android:</b> Chrome-Menü ⋮ → <b>App installieren</b>.</li><li><b>iPhone/iPad:</b> in Safari Teilen → <b>Zum Home-Bildschirm</b>.</li></ol>`;
  h += `<div class="card"><h3>App installieren</h3>${inst}</div>`;

  // Updates & Daten
  h += `<div class="card"><h3>Updates &amp; Daten</h3><div class="row" style="flex-wrap:wrap"><span>Version <b>${APP_VERSION}</b></span><button class="btn" data-act="checkupdate">Nach Updates suchen</button></div><span class="cap">Updates kommen automatisch: Beim nächsten Öffnen erscheint „Neue Version verfügbar“, ein Tipp genügt.</span>
    <div class="row" style="flex-wrap:wrap"><button class="btn" data-act="backup">Daten sichern (Datei)</button><button class="btn" data-act="wipe">Alle Trainingsdaten auf diesem Gerät löschen</button></div>${S.confirmWipe ? `<div class="row"><b class="warnc">Wirklich alles löschen?</b><button class="btn primary" data-act="wipe-yes">Ja, löschen</button><button class="btn" data-act="wipe-no">Abbrechen</button></div>` : ''}</div>`;
  return h;
}

async function handleSettingsSubmit(id) {
  if (id === 'tpform') { SET.shortcut = document.getElementById('tp-sc').value.trim() || 'TriCoach'; saveSettings(); toast('Gesichert'); render(); }
  if (id === 'tpical') { SET.tpIcal = document.getElementById('tp-ical').value.trim(); saveSettings(); if (SET.tpIcal) { toast('Hole Plan …'); await fetchTpIcal(true); } render(); }
  if (id === 'icuform') {
    SET.icuKey = document.getElementById('icukey').value.trim();
    SET.syncDays = +document.getElementById('icudays').value;
    if (!SET.icuKey) { toast('Bitte API-Key einfügen'); return; }
    try { const who = await ICU.test(); toast(`Verbunden: ${who}`); }
    catch (e) { toast(e.message.includes('API-Key') ? e.message : 'Keine Verbindung zu intervals.icu: ' + e.message); return; }
    if (SET.source !== 'icu') { SET.source = 'icu'; SET.lastSync = null; }
    saveSettings(); await loadData(); render(); runSync(true);
  }
  if (id === 'profform') {
    const g = x => document.getElementById(x).value, mmss = s => { const [m, ss] = s.split(':').map(Number); return m * 60 + (ss || 0); };
    P.weight = +g('p-weight'); P.ftp = +g('p-ftp'); P.lthr = +g('p-lthr'); P.maxHr = +g('p-maxhr'); P.rhr = +g('p-rhr'); P.bikeKg = +g('p-bike');
    if (/^\d{1,2}:\d{2}$/.test(g('p-pace'))) P.thrPace = mmss(g('p-pace'));
    if (/^\d{1,2}:\d{2}$/.test(g('p-css'))) P.css = mmss(g('p-css'));
    saveSettings(); if (SET.source === 'demo') await loadData(); else recompute(); toast('Profil gespeichert'); render();
  }
  if (id === 'raceform') {
    RACE.name = document.getElementById('r-name').value || 'Wettkampf';
    RACE.date = new Date(document.getElementById('r-date').value + 'T08:00:00');
    RACE.fmt = document.getElementById('r-fmt').value; RACE.temp = +document.getElementById('r-temp').value; RACE.hills = +document.getElementById('r-hills').value;
    saveSettings(); toast('Saisonziel gespeichert'); render();
  }
}

function backup() {
  const data = JSON.stringify({ version: APP_VERSION, settings: { ...SET, icuKey: undefined }, plan: PLAN, edits: EDITS, activities: SET.source === 'demo' ? ACTS.filter(a => a.source === 'manual') : ACTS, wellness: WELL }, null, 0);
  const url = URL.createObjectURL(new Blob([data], { type: 'application/json' }));
  const a = document.createElement('a'); a.href = url; a.download = `TriCoach-Backup-${isoDay(new Date())}.json`; document.body.appendChild(a); a.click(); a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 5000);
}
