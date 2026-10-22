'use strict';
/* TriCoach – Siri, Kurzbefehle, Widget und Aufruf-Links.
   iPhone/iPad: Apple lässt Kurzbefehle weder eine Web-App öffnen noch deren Daten lesen – „URL öffnen“ landet immer in Safari
   (mit leerem Speicher). Deshalb läuft Siri über das kostenlose Skript-Programm „Scriptable“: Das Skript siri/TriCoach.js liest
   dieselben Quellen wie die App (Schule + TrainingPeaks-Plan verschlüsselt von GitHub, Einheiten/Form aus intervals.icu)
   und trägt per Sprache Einheiten in intervals.icu ein – dadurch erscheinen sie auf allen Geräten in TriCoach.
   PC/Android/Safari: Aufruf-Links wie …/#log oder …/?do=log&sport=run&min=45&km=9 öffnen direkt die passende Stelle. */

const SIRI_SCRIPT = 'TriCoach';
const SIRI = { code: null, busy: false };
const appUrl = () => location.origin + location.pathname;
/* Skript schon beim Anzeigen laden, damit „Kopieren“ im selben Fingertipp klappt (Safari verlangt das fürs Kopieren) */
function prefetchSiriScript() {
  if (SIRI.code || SIRI.busy || !navigator.onLine) return;
  SIRI.busy = true;
  fetch('siri/TriCoach.js?t=' + Math.floor(Date.now() / 3600000), { cache: 'no-store' }).then(r => r.ok ? r.text() : null).then(t => { SIRI.code = t; }).catch(() => { }).finally(() => { SIRI.busy = false; });
}
async function copySiriScript() {
  if (SIRI.code && await copyText(SIRI.code)) { toast('Skript kopiert – jetzt in Scriptable einfügen'); return; }
  try {   // Safari: Zwischenablage mit „Versprechen“, damit das Laden die Geste nicht verbraucht
    const blob = fetch('siri/TriCoach.js', { cache: 'no-store' }).then(r => r.text()).then(t => { SIRI.code = t; return new Blob([t], { type: 'text/plain' }); });
    await navigator.clipboard.write([new ClipboardItem({ 'text/plain': blob })]);
    toast('Skript kopiert – jetzt in Scriptable einfügen');
  } catch (e) { toast('Kopieren klappt hier nicht – unten „Skript anzeigen“ und von Hand kopieren'); }
}
const b64url = s => btoa(String.fromCharCode(...new TextEncoder().encode(s))).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
function siriRepo() { const u = schoolUrl().match(/githubusercontent\.com\/([^/]+)\/([^/]+)\//); return u ? `${u[1]}/${u[2]}` : 'jannikbuhlrich-hue/tricoach'; }
/* Einrichtungs-Link: übergibt Schlüssel lokal an Scriptable (bleibt auf dem Gerät, geht über keinen Server) */
function siriSetupUrl() {
  const o = { k: SCH.key || '', i: SET.source === 'icu' ? SET.icuKey || '' : '', r: siriRepo(), s: SET.shortcut || 'TriCoach', w: P.weight, h: 1, l: SET.scList ? 1 : 0 };
  return `scriptable:///run?scriptName=${encodeURIComponent(SIRI_SCRIPT)}&setup=${b64url(JSON.stringify(o))}`;
}
function siriConnect() {
  if (!isIOS()) { toast('Siri-Verbindung geht auf iPhone/iPad – dort in TriCoach öffnen'); return; }
  if (!SCH.key && !(SET.source === 'icu' && SET.icuKey)) { toast('Erst TriCoach-Schlüssel (Schule) oder intervals.icu eintragen'); return; }
  SET.siriAt = Date.now(); saveSettings(); location.href = siriSetupUrl();
}

const SIRI_SHORTCUTS = [
  ['Frag TriCoach', 'Alles in einem: Siri fragt „Was möchtest du wissen?“ – du antwortest frei, z. B. „Was steht morgen an?“, „Wie ist meine Form?“ oder „Trag 45 Minuten Lauf ein“.', 'ask', 'Was möchtest du wissen?'],
  ['Mein Tag', 'Schule mit Entfall/Vertretung, Training, Hausaufgaben und Prüfungen für heute.', 'heute'],
  ['Was steht morgen an', 'Dasselbe für morgen – ideal abends.', 'morgen'],
  ['Training eintragen', 'Siri fragt „Was hast du trainiert?“ – z. B. „Lauf 50 Minuten 10 Kilometer locker“, „Schwimmen 2,4 km 55 Minuten 50er-Bahn“, „Kitesurfen zwei Stunden“. Landet in intervals.icu (→ TriCoach auf allen Geräten) und über Apple Health in TrainingPeaks.', 'log', 'Was hast du trainiert?'],
  ['Meine Form', 'Fitness, Ermüdung, Form, HRV, Ruhepuls und Schlaf – mit Empfehlung.', 'form'],
  ['Wochenbilanz', 'Kilometer und Stunden pro Sportart in dieser Woche.', 'woche'],
  ['Vertretungsplan', 'Entfall, Vertretung und Raumänderungen der nächsten Schultage.', 'schule'],
  ['Hausaufgaben', 'Offene Hausaufgaben nach Fälligkeit.', 'hausaufgaben'],
  ['Nächste Klausur', 'Kommende Prüfungen mit Countdown.', 'prüfungen'],
  ['Nächster Wettkampf', 'Countdown zum nächsten Rennen aus TrainingPeaks/intervals.icu.', 'wettkampf'],
  ['Letzte Einheit', 'Deine letzte Uhr-Einheit mit Puls und Belastung.', 'letzte einheit'],
];
function shortcutSteps(x) {
  const [name, , cmd, ask] = x;
  const run = `Aktion <b>„Run Script“</b> von Scriptable (Suche: „Scriptable“) → Script <b>${SIRI_SCRIPT}</b>, bei <b>Parameter</b> (ältere Version: <b>Texts</b>) ${ask ? '<b>Angegebene Eingabe</b> wählen' : `den Text <code>${esc(cmd)}</code> eintragen`}. <b>Run In App</b> aus, <b>Show When Run</b> an.`;
  const steps = ask ? [`Aktion <b>„Nach Eingabe fragen“</b> → Frage <code>${esc(ask)}</code>, Typ Text.`, run] : [run];
  if (cmd === 'log') steps.push(`<em>Für TrainingPeaks:</em> Aktion <b>„Wörterbuchwert abrufen“</b> → Schlüssel <code>health</code> aus <b>Skriptergebnis</b>, dann <b>„Kurzbefehl ausführen“</b> → <b>${esc(SET.shortcut)}</b> mit diesem Wert als Eingabe.`);
  return `<details class="scut"><summary><b>„${esc(name)}“</b> <span class="cap">${esc(x[1])}</span></summary><ol class="steps"><li>Kurzbefehle → <b>+</b> → oben Namen <b>${esc(name)}</b> eingeben (das ist später der Siri-Satz).</li>${steps.map(s => `<li>${s}</li>`).join('')}<li>Fertig. Ausprobieren: <b>„Hey Siri, ${esc(name)}“</b>.</li></ol></details>`;
}
function siriSettingsCard() {
  prefetchSiriScript();
  const ios = isIOS(), link = `${appUrl()}`, ready = SCH.key || (SET.source === 'icu' && SET.icuKey);
  const src = [SCH.key ? 'Schule' : '', SCH.key ? 'TrainingPeaks-Plan' : '', SET.source === 'icu' && SET.icuKey ? 'intervals.icu (Einheiten, Form, Eintragen)' : ''].filter(Boolean);
  return `<div class="card" id="siri"><h3>${icon('bolt')} Siri, Kurzbefehle &amp; Widget <small>${SET.siriAt ? 'verbunden ' + new Date(SET.siriAt).toLocaleDateString('de-DE') : 'nicht eingerichtet'}</small></h3>
    <span class="cap fg">Apple lässt Kurzbefehle keine Web-App öffnen – „URL öffnen“ landet immer in Safari ohne deine Daten. Deshalb läuft Siri über die kostenlose App <b>Scriptable</b>: Sie liest dieselben Daten wie TriCoach${src.length ? ` (${src.join(', ')})` : ''} und antwortet per Sprache, auch im Sperrbildschirm und als Widget „Mein Tag“.</span>
    ${!ready ? `<div class="ins"><span class="dot" style="background:var(--warn)"></span><div><b>Zuerst verbinden</b><span>Trag unten bei „Schule“ deinen TriCoach-Schlüssel ein und/oder verbinde oben intervals.icu – das sind die Datenquellen für Siri.</span></div></div>` : ''}
    <div class="opt"><b>1 · Scriptable laden <span class="tag">kostenlos</span></b><span class="cap fg">Im App Store „Scriptable“ (Simon Støvring) installieren.</span><div><a class="btn" href="https://apps.apple.com/app/scriptable/id1405459188" target="_blank" rel="noopener">App Store öffnen</a></div></div>
    <div class="opt"><b>2 · Skript einfügen <span class="tag">einmalig</span></b><ol class="steps"><li><b>Skript kopieren</b> tippen.</li><li>Scriptable öffnen → <b>+</b> → in die leere Seite tippen → <b>Einsetzen</b>.</li><li>Oben auf den Titel tippen, Namen <b>${SIRI_SCRIPT}</b> geben → <b>Fertig</b>.</li></ol>
      <div class="row" style="flex-wrap:wrap"><button class="btn primary" data-act="siricopy">${icon('share', 14)} Skript kopieren</button><a class="linkbtn" href="siri/TriCoach.js" target="_blank" rel="noopener">Skript anzeigen</a></div><span class="cap">Das Skript aktualisiert sich danach selbst.</span></div>
    <div class="opt"><b>3 · Siri verbinden</b><span class="cap fg">Übergibt deine Schlüssel direkt an Scriptable auf diesem Gerät. Danach kurz „OK“ tippen.</span><div><button class="btn primary" data-act="siriconnect" ${ready ? '' : 'disabled'}>${icon('bolt', 14)} Siri verbinden</button></div></div>
    <div class="opt"><b>4 · Kurzbefehle anlegen</b><span class="cap fg">Für jeden Siri-Satz einen Kurzbefehl – jeweils 1–2 Aktionen. Der Name ist der Satz, den du zu Siri sagst. Am wichtigsten ist <b>„Frag TriCoach“</b> – damit geht schon alles.</span>${SIRI_SHORTCUTS.map(shortcutSteps).join('')}</div>
    <div class="opt"><b>5 · Widget „Mein Tag“</b><ol class="steps"><li>Home-Bildschirm lange drücken → <b>Bearbeiten</b> → <b>Widget hinzufügen</b> → <b>Scriptable</b> → mittlere Größe.</li><li>Widget antippen → Script <b>${SIRI_SCRIPT}</b> → bei „When Interacting“ <b>Run Script</b>.</li></ol><span class="cap">Zeigt Schule (Entfall/Vertretung), Training, Prüfungen und fällige Hausaufgaben – ab 17 Uhr schon für morgen. Aktualisiert sich etwa alle 30 Minuten.</span></div>
    <details><summary class="cap">Für PC, Android und Profis: Aufruf-Links</summary>
      <span class="cap fg">Öffnen TriCoach direkt an der richtigen Stelle (am PC z. B. als Desktop-Verknüpfung oder per Rechtsklick auf das App-Symbol; am iPhone öffnen sie Safari).</span>
      <ul class="steps">${[['#today', 'Mein Tag'], ['#log', 'Einheit eintragen'], ['?do=log&sport=run&min=45&km=9&rpe=4', 'Lauf 45 min/9 km vorausgefüllt'], ['?do=log&sport=swim&km=2.4&min=55&where=50', 'Schwimmen vorausgefüllt'], ['?do=plan&sport=bike&min=90&date=morgen', 'Radeinheit für morgen planen'], ['?do=hw', 'Hausaufgabe eintragen'], ['?do=sync', 'Uhr-Daten holen'], ['#calendar', 'Kalender'], ['#school', 'Schule']].map(([q, l]) => `<li>${l}: <code>${esc(link + q)}</code></li>`).join('')}</ul></details></div>`;
}

/* ---------- Aufruf-Links (#ansicht und ?do=…) ---------- */
function parseWhen(v) {
  if (!v) return null;
  const t = String(v).toLowerCase();
  if (t === 'heute') return at(TODAY, Math.max(6, NOW.getHours()));
  if (t === 'morgen') return at(addDays(TODAY, 1), 17);
  if (t === 'übermorgen' || t === 'uebermorgen') return at(addDays(TODAY, 2), 17);
  const d = new Date(v.length <= 10 ? v + 'T17:00:00' : v); return isNaN(d) ? null : d;
}
function handleLink(fromStart) {
  const q = new URLSearchParams(location.search), hash = location.hash.slice(1), act = (q.get('do') || '').toLowerCase();
  let handled = false;
  if (hash && VIEWS[hash] && !['activity', 'live'].includes(hash)) { S.view = hash; S.sheet = null; handled = true; }
  if (hash === 'log' || act === 'log') {
    const d = newLog(parseWhen(q.get('date')) || at(TODAY, Math.max(6, NOW.getHours() - 1)), ALL.includes(q.get('sport')) ? q.get('sport') : 'swim');
    if (q.get('min')) d.dur = Math.round(parseFloat(q.get('min').replace(',', '.')) * 60) || d.dur;
    if (q.get('km')) d.dist = Math.round(parseFloat(q.get('km').replace(',', '.')) * 1000) || null;
    if (q.get('rpe')) d.rpe = clamp(+q.get('rpe') || 5, 1, 10);
    if (q.get('where')) d.where = q.get('where') === 'ow' ? 'ow' : +q.get('where') || d.where;
    if (q.get('name')) d.name = q.get('name');
    if (q.get('art')) d.art = q.get('art');
    S.sheet = { t: 'log', id: null, d }; handled = true;
  } else if (hash === 'new' || act === 'new') { S.sheet = { t: 'add' }; handled = true; }
  else if (act === 'plan') {
    const d = newDraft('workout', +(parseWhen(q.get('date')) || at(addDays(TODAY, 1), 17)));
    if (ALL.includes(q.get('sport'))) d.sport = q.get('sport');
    if (q.get('min')) d.min = +q.get('min') || d.min;
    if (q.get('title')) d.title = q.get('title');
    S.view = 'calendar'; S.sheet = { t: 'plan', id: null, d }; handled = true;
  } else if (act === 'hw') { S.view = 'today'; S.sheet = { t: 'hw', d: { su: q.get('su') || '', text: q.get('text') || '', due: isoDay(parseWhen(q.get('due')) || addDays(TODAY, 1)) } }; handled = true; }
  else if (act === 'sync') { setTimeout(() => { runSync(true); syncSchool(false); fetchTpIcal(false); }, 300); handled = true; }
  else if (act && VIEWS[act]) { S.view = act; handled = true; }
  // Link nur einmal ausführen (sonst öffnet ein Neuladen das Formular erneut)
  if (handled && (location.search || location.hash)) try { history.replaceState(null, '', location.pathname); } catch (e) { }
  if (handled && !fromStart) render();
  return handled;
}
window.addEventListener('hashchange', () => { if (location.hash.length > 1) handleLink(false); });
