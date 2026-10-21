'use strict';
/* TriCoach – Brücke zu TrainingPeaks.
   TrainingPeaks hat keine offene Schnittstelle für eigene Apps. Deshalb drei Wege, die ohne fremde Server funktionieren:
   1. Apple Health: TriCoach startet den Kurzbefehl „TriCoach“, der die Einheit in Health speichert.
      Die TrainingPeaks-App holt Health-Workouts der letzten 7 Tage beim Aktualisieren des Kalenders.
   2. FIT-Datei: echte Garmin-FIT-Aktivität erzeugen und in TrainingPeaks auf den Kalendertag ziehen.
   3. Übergabe: Zusammenfassung kopieren, TrainingPeaks öffnen, einfügen (z. B. für Wettkampf-Events). */

const TP_URL = 'https://app.trainingpeaks.com/';
const TP_EVENT = { sprint: 'Triathlon', volks: 'Triathlon', olympic: 'Triathlon', middle: 'Triathlon', full: 'Triathlon', r5: 'Run', r10: 'Run', rhm: 'Run', rm: 'Run', duath: 'Duathlon', bike: 'Road Bike', swim: 'Open Water Swim', other: 'Other' };
/* Workout-Typ für Apple Health (so heißen die Typen im Kurzbefehl „Training protokollieren“) */
const HEALTH_TYPE = { swim: 'Schwimmen', bike: 'Radfahren', run: 'Laufen', strength: 'Funktionelles Krafttraining' };
const healthType = a => HEALTH_TYPE[a.sport] || ({ Kitesurfen: 'Wassersport', Windsurfen: 'Wassersport', Surfen: 'Surfen', SUP: 'Paddelsport', Wandern: 'Wandern', Yoga: 'Yoga', Rudern: 'Rudern', Klettern: 'Klettern' }[a.art] || 'Andere');

/* ---------- 1. Apple Health über Kurzbefehl ---------- */
function healthPayload(a) {
  return {
    typ: healthType(a), sport: a.sport, name: a.name,
    start: `${isoDay(a.start)} ${time(a.start)}`,
    dauer_min: Math.round(a.dur / 60), ort: swimWhere(a) === 'ow' ? 'Freiwasser' : swimWhere(a) ? 'Becken' : '', bahn_m: typeof swimWhere(a) === 'number' ? swimWhere(a) : 0, distanz_km: a.dist ? +(a.dist / 1000).toFixed(2) : 0,
    distanz_m: Math.round(a.dist || 0), kcal: a.kcal || estKcal(a.sport, a.dur, a.rpe), rpe: a.rpe || null, notiz: a.notes || ''
  };
}
function sendToHealth(a) {
  if (!isIOS()) { S.sheet = { t: 'tp', id: a.id }; render(); toast('Apple Health geht nur auf iPhone/iPad – nimm hier die FIT-Datei'); return; }
  const text = JSON.stringify(healthPayload(a));
  markTp(a.id, 'health');
  location.href = `shortcuts://run-shortcut?name=${encodeURIComponent(SET.shortcut || 'TriCoach')}&input=text&text=${encodeURIComponent(text)}`;
}
function markTp(id, how) {
  const a = byId(id); if (!a) return;
  const v = how ? { how, at: Date.now() } : null;
  a.tp = v;
  if (a.source === 'manual') DB.put('acts', [a]).catch(() => { });
  else { EDITS[id] = { ...(EDITS[id] || {}), tp: v }; saveEdits(); }
}

/* ---------- 2. FIT-Datei (Garmin-Format, das TrainingPeaks, Garmin Connect, Strava und intervals.icu lesen) ---------- */
const FIT_SPORT = { swim: [5, 0], bike: [2, 0], run: [1, 0], strength: [10, 20] };
const FIT_OTHER = { Kitesurfen: [44, 0], Windsurfen: [43, 0], Surfen: [38, 0], SUP: [37, 0], Wandern: [17, 0], Rudern: [15, 0], Yoga: [10, 43], Ski: [13, 0], Spaziergang: [11, 0], Klettern: [31, 0] };
const fitSport = a => a.sport === 'swim' ? [5, swimWhere(a) === 'ow' ? 18 : swimWhere(a) ? 17 : 0] : FIT_SPORT[a.sport] || FIT_OTHER[a.art] || [0, 0];
const CRC_T = [0x0000, 0xCC01, 0xD801, 0x1400, 0xF001, 0x3C00, 0x2800, 0xE401, 0xA001, 0x6C00, 0x7800, 0xB401, 0x5000, 0x9C01, 0x8801, 0x4400];
function fitCrc(bytes, crc = 0) {
  for (const b of bytes) {
    let t = CRC_T[crc & 0xF]; crc = (crc >> 4) & 0x0FFF; crc = crc ^ t ^ CRC_T[b & 0xF];
    t = CRC_T[crc & 0xF]; crc = (crc >> 4) & 0x0FFF; crc = crc ^ t ^ CRC_T[(b >> 4) & 0xF];
  }
  return crc;
}
/* Basistypen: [Größe, FIT-Typ-Code] */
const FT = { enum: [1, 0x00], u8: [1, 0x02], u16: [2, 0x84], u32: [4, 0x86], u32z: [4, 0x8C], s32: [4, 0x85] };
const FIT_NA = { enum: 0xFF, u8: 0xFF, u16: 0xFFFF, u32: 0xFFFFFFFF, u32z: 0, s32: 0x7FFFFFFF };
function buildFit(a) {
  const out = [], put = (...b) => out.push(...b);
  const w16 = v => [v & 0xFF, (v >>> 8) & 0xFF], w32 = v => [v & 0xFF, (v >>> 8) & 0xFF, (v >>> 16) & 0xFF, (v >>> 24) & 0xFF];
  const enc = (t, v) => { if (v == null || !isFinite(v)) v = FIT_NA[t]; v = Math.round(v); return FT[t][0] === 1 ? [v & 0xFF] : FT[t][0] === 2 ? w16(v) : w32(v >>> 0); };
  let local = 0;
  const msg = (global, fields, rows) => {
    const l = local++ & 0xF;
    put(0x40 | l, 0, 0, ...w16(global), fields.length); fields.forEach(([num, t]) => put(num, FT[t][0], FT[t][1]));
    rows.forEach(vals => { put(l); fields.forEach(([, t], i) => put(...enc(t, vals[i]))); });
  };
  const ts = d => Math.floor(d.getTime() / 1000) - 631065600;
  const t0 = ts(a.start), dur = Math.max(60, Math.round(a.dur)), t1 = t0 + dur, dist = Math.round((a.dist || 0) * 100), [sport, sub] = fitSport(a);
  const hr = num(a.avgHr) ? Math.round(a.avgHr) : null, mx = num(a.maxHr) ? Math.round(a.maxHr) : hr, kcal = a.kcal || estKcal(a.sport, dur, a.rpe);
  const tzOff = -a.start.getTimezoneOffset() * 60;
  msg(0, [[0, 'enum'], [1, 'u16'], [2, 'u16'], [3, 'u32z'], [4, 'u32']], [[4, 255, 1, (t0 % 4000000000) + 1, t0]]);           // file_id: Aktivität, Hersteller „development“
  msg(49, [[0, 'u16'], [1, 'u16']], [[1, 220]]);                                                                       // file_creator
  msg(21, [[253, 'u32'], [0, 'enum'], [1, 'enum']], [[t0, 0, 0]]);                                                     // event: Timer Start
  const recs = [[t0, 0, hr]]; if (dist || hr) { const n = Math.min(60, Math.max(1, Math.floor(dur / 60))); for (let i = 1; i <= n; i++) recs.push([t0 + Math.round(dur * i / n), Math.round(dist * i / n), hr]); } else recs.push([t1, 0, hr]);
  msg(20, [[253, 'u32'], [5, 'u32'], [3, 'u8']], recs);                                                                // record
  msg(21, [[253, 'u32'], [0, 'enum'], [1, 'enum']], [[t1, 0, 4]]);                                                     // event: Timer Stop
  const sum = [[253, 'u32'], [2, 'u32'], [7, 'u32'], [8, 'u32'], [9, 'u32'], [11, 'u16'], [0, 'enum'], [1, 'enum']];
  msg(19, [...sum, [15, 'u8'], [16, 'u8'], [25, 'enum'], [39, 'enum']], [[t1, t0, dur * 1000, dur * 1000, dist, kcal, 9, 1, hr, mx, sport, sub]]);      // lap
  const lane = sport === 5 && typeof swimWhere(a) === 'number' ? swimWhere(a) : null;   // Bahnlänge für Beckenschwimmen
  msg(18, [...sum, [16, 'u8'], [17, 'u8'], [5, 'enum'], [6, 'enum'], [25, 'u16'], [26, 'u16'], ...(lane ? [[44, 'u16'], [46, 'enum']] : [])], [[t1, t0, dur * 1000, dur * 1000, dist, kcal, 8, 1, hr, mx, sport, sub, 0, 1, ...(lane ? [lane * 100, 0] : [])]]); // session
  msg(34, [[253, 'u32'], [0, 'u32'], [1, 'u16'], [2, 'enum'], [3, 'enum'], [4, 'enum'], [5, 'u32']], [[t1, dur * 1000, 1, 1, 26, 1, t1 + tzOff]]);     // activity
  const hdr = [14, 0x20, ...w16(2132), ...w32(out.length), 0x2E, 0x46, 0x49, 0x54];
  const head = [...hdr, ...w16(fitCrc(hdr))], all = [...head, ...out];
  return new Uint8Array([...all, ...w16(fitCrc(all))]);
}
const fitName = a => `TriCoach_${isoDay(a.start)}_${time(a.start).replace(':', '')}_${(a.name || NAME[a.sport]).replace(/[^\wäöüÄÖÜß-]+/g, '-').slice(0, 30)}.fit`;
async function downloadFit(id) {
  const a = byId(id); if (!a) return;
  const file = new File([buildFit(a)], fitName(a), { type: 'application/octet-stream' });
  if (isIOS() && navigator.canShare?.({ files: [file] })) { try { await navigator.share({ files: [file], title: file.name }); markTp(id, 'fit'); render(); return; } catch (e) { if (e.name === 'AbortError') return; } }
  const url = URL.createObjectURL(file), el = document.createElement('a'); el.href = url; el.download = file.name; document.body.appendChild(el); el.click(); el.remove();
  setTimeout(() => URL.revokeObjectURL(url), 10000);
  markTp(id, 'fit'); render(); toast('FIT-Datei gespeichert – in TrainingPeaks auf den Kalendertag ziehen');
}

/* ---------- 3. Übergabe-Text ---------- */
function actSummary(a) {
  const L = [`${a.name} – ${NAME[a.sport]}${a.art && !a.name.includes(a.art) ? ' (' + a.art + ')' : ''}`, `${dayTitle(a.start)}, ${time(a.start)} Uhr`, `Dauer: ${dur(a.dur)}${a.dist ? ' · Distanz: ' + distTxt(a.sport, a.dist) : ''}${a.dist && a.dur ? ' · ' + paceHint(a.sport, a.dist, a.dur) : ''}`];
  if (swimWhere(a)) L.push(`Wo: ${whereTxt(swimWhere(a))}`);
  if (num(a.avgHr)) L.push(`Ø HF ${Math.round(a.avgHr)} bpm`);
  if (a.rpe) L.push(`RPE ${a.rpe}/10 (${RPE_TXT[a.rpe]})`);
  if (a.ex?.length) L.push('Übungen: ' + a.ex.map(x => `${x.n}${x.s ? ' ' + x.s + '×' : ''}${x.r ? x.r : ''}${x.w ? ' @ ' + de(x.w, x.w % 1 ? 1 : 0) + ' kg' : ''}`).join(', '));
  if (a.notes) L.push(a.notes);
  return L.join('\n');
}
function raceSummary(p) {
  return [`${p.title}`, `${dayTitle(p.date)}${p.allDay ? '' : ', ' + time(p.date) + ' Uhr'}`, `Typ: ${TP_EVENT[p.fmt] || 'Other'} · ${RACE_FMT[p.fmt] || ''}`, `Priorität: ${p.prio || 'A'}`, p.goal ? `Zielzeit: ${p.goal}` : '', p.location ? `Ort: ${p.location}` : '', p.url || '', p.notes || ''].filter(Boolean).join('\n');
}
async function copyText(t) {
  try { await navigator.clipboard.writeText(t); return true; }
  catch (e) { const ta = document.createElement('textarea'); ta.value = t; document.body.appendChild(ta); ta.select(); let ok = false; try { ok = document.execCommand('copy'); } catch (e2) { } ta.remove(); return ok; }
}

/* ---------- Sheets ---------- */
function tpSheet() {
  const a = byId(S.sheet.id); if (!a) return '';
  const st = a.tp ? `<div class="ins"><span class="dot" style="background:var(--good)"></span><div><b>Als „in TrainingPeaks“ markiert</b><span>${{ health: 'über Apple Health', fit: 'per FIT-Datei', manual: 'von Hand' }[a.tp.how] || ''} · ${new Date(a.tp.at).toLocaleString('de-DE', { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' })}</span></div></div>` : '';
  const fromWatch = a.source === 'icu' || a.source === 'fit';
  let b = `<b style="font-size:16px">${esc(a.name)}</b><span class="muted">${shortDate(a.start)}, ${time(a.start)} · ${hm(a.dur)}${a.dist ? ' · ' + distTxt(a.sport, a.dist) : ''}</span>${st}`;
  if (fromWatch) b += `<div class="ins"><span class="dot" style="background:var(--fit)"></span><div><b>Kommt von deiner Uhr</b><span>Wenn Garmin Connect mit TrainingPeaks verbunden ist, ist diese Einheit dort schon automatisch – hier nichts weiter nötig.</span></div></div>`;
  b += `<div class="opt"><b>1 · Über Apple Health <span class="tag">automatisch</span></b><span class="cap fg">Startet deinen Kurzbefehl „${esc(SET.shortcut)}“, der die Einheit in Apple Health speichert. Die TrainingPeaks-App holt sie beim nächsten Öffnen (Kalender nach unten ziehen) und fragt nach dem Import.</span><div class="row" style="flex-wrap:wrap"><button class="btn primary" data-act="tp-health:${a.id}">${icon('heart', 14)} An Apple Health senden</button><button class="linkbtn" data-act="nav:settings#tp">Kurzbefehl einrichten</button></div></div>`;
  b += `<div class="opt"><b>2 · FIT-Datei</b><span class="cap fg">Echte Aktivitätsdatei mit Sportart, Zeit, Distanz${num(a.avgHr) ? ', Puls' : ''} und Kalorien. Am PC in TrainingPeaks einfach auf den Kalendertag ziehen.</span><div><button class="btn" data-act="tp-fit:${a.id}">${icon('share', 14)} FIT-Datei erzeugen</button></div></div>`;
  b += `<div class="opt"><b>3 · Von Hand</b><span class="cap fg">Zusammenfassung kopieren und in TrainingPeaks bei der Einheit unter „Kommentar“ bzw. als neue Einheit einfügen.</span><div class="row" style="flex-wrap:wrap"><button class="btn" data-act="tp-copy:${a.id}">Text kopieren</button><a class="btn" href="${TP_URL}" target="_blank" rel="noopener">TrainingPeaks öffnen</a></div></div>`;
  b += `<div class="row" style="flex-wrap:wrap">${a.tp ? `<button class="btn" data-act="tp-mark:${a.id}|">Markierung entfernen</button>` : `<button class="btn" data-act="tp-mark:${a.id}|manual">${icon('check', 14)} Ist in TrainingPeaks</button>`}</div>`;
  return sheetWrap('An TrainingPeaks', b, false);
}
function tpRaceSheet() {
  const p = S.sheet.p, txt = raceSummary(p);
  let b = `<span class="cap fg">Wettkämpfe lassen sich nicht automatisch übertragen (TrainingPeaks lässt keine fremden Apps in den Kalender). So geht's in 20 Sekunden:</span>
    <ol class="steps"><li><b>Daten kopieren</b> (unten).</li><li><b>TrainingPeaks öffnen</b> → Kalendertag <b>${p.date.toLocaleDateString('de-DE')}</b> → <b>+</b> → <b>Event</b>.</li><li>Typ <b>${TP_EVENT[p.fmt] || 'Other'}</b>, Priorität <b>${p.prio || 'A'}</b> wählen, Name einfügen, sichern.</li></ol>
    <pre class="handoff">${esc(txt)}</pre>
    <div class="row" style="flex-wrap:wrap"><button class="btn primary" data-act="tp-rcopy">Daten kopieren</button><a class="btn" href="${TP_URL}" target="_blank" rel="noopener">TrainingPeaks öffnen</a></div>
    <span class="cap">Deine Trainerin sieht das Event dann sofort und kann den Plan (Taper, A/B/C) darauf ausrichten.</span>
    <button class="btn ${p.tp ? '' : 'primary'}" data-act="tp-rdone">${p.tp ? 'Markierung entfernen' : icon('check', 14) + ' Ist in TrainingPeaks eingetragen'}</button>`;
  return sheetWrap('Wettkampf an TrainingPeaks', b, false);
}

const tpRepoUrl = () => tpDataUrl().replace('https://raw.githubusercontent.com/', 'https://github.com/').replace(/\/tp-daten\/tp\.enc$/, '');
function tpPlanStatus() {
  if (!SET.tpIcalAt) return { tag: ' <small>noch nicht verbunden</small>', line: '' };
  const n = PLAN.filter(p => p.from === 'tp' && p.date >= TODAY).length;
  const st = new Date(SET.tpAt || SET.tpIcalAt).toLocaleString('de-DE', { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' });
  return { tag: ` <span class="tag">${SET.tpVia === 'github' ? 'automatisch' : 'nur dieses Gerät'}</span>`, line: `<span class="cap">Stand ${st} · ${n} kommende Einträge</span>` };
}

/* Anleitung in den Einstellungen */
function tpSettingsCard() {
  const open = PLAN.filter(p => p.kind === 'race' && !p.tp && p.date >= TODAY).length, todo = ACTS.filter(a => a.source === 'manual' && !a.tp && a.start >= addDays(TODAY, -14)).length;
  return `<div class="card" id="tp"><h3>${ICON.tp} TrainingPeaks <small>${todo || open ? `${todo ? todo + ' Einheiten' : ''}${todo && open ? ' · ' : ''}${open ? open + ' Wettkämpfe' : ''} offen` : 'alles übertragen'}</small></h3>
    <span class="cap fg">Damit deine Trainerin alles sieht: Uhr-Einheiten laufen über <b>Garmin Connect → TrainingPeaks</b> (in Garmin Connect unter <b>Einstellungen → Drittanbieter-Apps → TrainingPeaks</b> verbinden, falls noch nicht geschehen). Für alles, was du hier einträgst, ist Apple Health die Brücke:</span>
    <div class="opt"><b>Einmalig: Kurzbefehl „TriCoach“ anlegen <span class="tag">ca. 5 min</span></b>
      <ol class="steps">
        <li>App <b>Kurzbefehle</b> → <b>+</b> → Name <b>${esc(SET.shortcut)}</b>.</li>
        <li>Aktion <b>„Wörterbuch abrufen“</b> mit <b>Kurzbefehl-Eingabe</b>.</li>
        <li><b>„Wörterbuchwert abrufen“</b> für <code>start</code> → danach <b>„Datumsangaben aus Eingabe abrufen“</b>. Genauso Werte für <code>dauer_min</code>, <code>distanz_km</code>, <code>kcal</code> und <code>typ</code> holen.</li>
        <li><b>„Wenn“</b> <code>typ</code> ist <b>Schwimmen</b> → <b>„Training protokollieren“</b>: Typ Schwimmen, Datum = Datum, Dauer = dauer_min (Minuten), Distanz = distanz_km (km), Energie = kcal. Ebenso Blöcke für <b>Laufen</b>, <b>Radfahren</b>, <b>Funktionelles Krafttraining</b>, <b>Andere</b>.</li>
        <li>In der <b>TrainingPeaks-App</b>: Mehr → <b>App-Verbindungen</b> → <b>Apple Health</b> verbinden, alle Berechtigungen an.</li>
      </ol>
      <span class="cap">Beim Eintragen in TriCoach „An TrainingPeaks senden“ anhaken – der Kurzbefehl läuft, TrainingPeaks fragt beim nächsten Aktualisieren nach dem Import (Health-Workouts der letzten 7 Tage). Am besten einmal mit einer Test-Einheit prüfen.</span>
      <form id="tpform" class="plan"><label>Name des Kurzbefehls<input id="tp-sc" value="${esc(SET.shortcut)}" autocomplete="off"></label><button class="btn" type="submit">Speichern</button></form></div>
    <div class="opt"><b>Am PC: FIT-Datei</b><span class="cap fg">Bei jeder Einheit „An TrainingPeaks“ → „FIT-Datei“. Die Datei in TrainingPeaks (Web) auf den Kalendertag ziehen – fertig.</span></div>
    <div class="opt"><b>Wettkämpfe & Events</b><span class="cap fg">Beim Wettkampf „An TrainingPeaks übergeben“: Daten werden kopiert, du legst das Event in TrainingPeaks mit gleicher Priorität A/B/C an. TriCoach merkt sich, was schon drin ist.</span></div>
    <div class="opt"><b>Plan deiner Trainerin in TriCoach${tpPlanStatus().tag}</b>${tpPlanStatus().line}
      <span class="cap fg">Geplante Einheiten und Events erscheinen im TriCoach-Kalender mit Ampel (grün = erledigt, rot = verpasst). Ändert oder löscht deine Trainerin etwas, zieht TriCoach mit. Ein TrainingPeaks-Passwort braucht es dafür nicht – nur den privaten iCal-Link aus TrainingPeaks (Web) unter <b>Settings → Account → Calendar</b>.</span>
      ${SET.tpVia === 'github' ? '<details><summary class="cap">Einrichtung</summary>' : ''}<ol class="steps"><li>Link kopieren und an Claude schicken – er landet nur verschlüsselt im Repo (oder selbst als GitHub-Secret <b>TP_ICAL</b> eintragen).</li>
      <li><a href="${tpRepoUrl()}/actions/workflows/tp.yml" target="_blank" rel="noopener">Actions → „TrainingPeaks-Plan“</a> → <b>Run workflow</b>. Danach läuft der Job stündlich von allein.</li>
      <li>Hier „Plan holen“ – ab dann holt TriCoach den Plan beim Öffnen und alle 30 Minuten selbst.</li></ol>${SET.tpVia === 'github' ? '</details>' : ''}
      <div class="row" style="flex-wrap:wrap"><button class="btn primary" data-act="tpnow">${icon('sync', 14)} Plan holen</button></div>${TP.err ? `<span class="cap warnc">${esc(TP.err)}</span>` : ''}
      <details><summary class="cap">Link nur auf diesem Gerät nutzen (ohne GitHub)</summary>
      <form id="tpical" class="plan"><label style="grid-column:1/-1">iCal-Link<input id="tp-ical" type="url" placeholder="webcal://…trainingpeaks.com/…ics" value="${esc(SET.tpIcal || '')}" autocomplete="off"></label><button class="btn" type="submit">Speichern & holen</button></form>
      <span class="cap">Klappt das Holen nicht (Browser blockiert), den Link in Safari öffnen, Datei sichern und unter Kalender → „Kalenderdatei importieren“ laden. Tipp: Denselben Link in Apple Kalender unter <b>Kalender hinzufügen → Kalenderabonnement</b> eintragen, dann ist der Plan auch dort.</span></details></div></div>`;
}

/* Plan deiner Trainerin: bevorzugt verschlüsselt vom GitHub-Job (Branch „tp-daten“, siehe .github/workflows/tp.yml),
   sonst direkt über den iCal-Link (klappt nur, wenn der Browser es zulässt). Vom Trainer gelöschte Einheiten verschwinden auch hier. */
const TP = { busy: false, err: '' };
const tpDataUrl = () => schoolUrl().replace(/\/schule-daten\/schule\.enc$/, '/tp-daten/tp.enc');
async function fetchTpIcal(manual) {
  if (TP.busy) return;
  if (!navigator.onLine) { if (manual) toast('Offline – Plan vom letzten Abruf'); return; }
  TP.busy = true; if (manual) render();
  let ics = null, at = null, via = '';
  try {
    if (SCH.key) {
      const r = await fetch(tpDataUrl() + '?t=' + Math.floor(Date.now() / 60000), { cache: 'no-store' });
      if (r.ok) {
        let d; try { d = await decryptSchool(await r.text(), SCH.key); } catch (e) { throw new Error('Schlüssel passt nicht zum GitHub-Secret TRICOACH_KEY'); }
        ics = d.ics; at = d.at; via = 'github';
      }
    }
    if (!ics && SET.tpIcal) {
      try {
        const r = await fetch(SET.tpIcal.trim().replace(/^webcal:/i, 'https:'), { cache: 'no-store' });
        if (!r.ok) throw new Error('Status ' + r.status);
        ics = await r.text(); at = new Date().toISOString(); via = 'direct';
      } catch (e) { throw new Error(`Direkt holen klappt hier nicht (${e.message}). Am besten den Link über GitHub laufen lassen (siehe unten).`); }
    }
    if (!ics) { if (manual) toast(SCH.key ? 'Noch kein Plan von GitHub – läuft der Job „TrainingPeaks-Plan“ schon?' : 'Erst den TriCoach-Schlüssel (Einstellungen → Schule) eintragen'); return; }
    if (!ics.includes('BEGIN:VCALENDAR')) throw new Error('Antwort ist keine Kalenderdatei');
    const res = importIcs(ics, 'tp', true);
    let removed = 0;
    if (res.lo) {
      const lo = sod(res.lo), hi = new Date(Math.max(+addDays(sod(res.hi), 1), +addDays(TODAY, 8)));   // TrainingPeaks liefert mind. ~2 Wochen voraus
      PLAN = PLAN.filter(p => { const gone = p.from === 'tp' && p.date >= lo && p.date < hi && !res.ids.has(p.id) && !isDone(p); if (gone) removed++; return !gone; });
      savePlan();
    }
    const parts = [res.added && `${res.added} neu`, res.changed && `${res.changed} geändert`, removed && `${removed} entfernt`].filter(Boolean);
    if (manual) toast('TrainingPeaks-Plan aktualisiert · ' + (parts.join(', ') || 'keine Änderungen'));
    else if (parts.length && SET.tpSeen) toast('Trainerin hat den Plan geändert: ' + parts.join(', '));
    SET.tpIcalAt = Date.now(); SET.tpAt = at; SET.tpVia = via; SET.tpSeen = 1; saveSettings(); TP.err = '';
  } catch (e) { TP.err = e instanceof TypeError ? 'Keine Verbindung zu GitHub – später nochmal' : e.message; if (manual) toast(TP.err); }
  finally { TP.busy = false; render(); }
}
