'use strict';
/* TriCoach – Einheiten eintragen und bearbeiten:
   Schwimmen (km oder Bahnen × Becken), Rad, Laufen, Athletik (Übungen mit Sätzen, Wdh, kg), Sonstiges (z. B. Kitesurfen).
   Uhr-Einheiten lassen sich korrigieren (z. B. geschwommene km) – die Korrektur bleibt auch nach jedem Sync erhalten. */

const RPE_TXT = ['', 'sehr leicht', 'leicht', 'leicht', 'moderat', 'moderat', 'etwas hart', 'hart', 'sehr hart', 'extrem hart', 'maximal'];

function newLog(date, sport = 'swim', fromPlan) {
  const d = { sport, art: '', name: '', start: new Date(date), dur: 3600, dist: null, rpe: 5, avgHr: null, kcal: null, notes: '', ex: [], toTp: true, where: lastWhere(), lanes: null };
  if (fromPlan) Object.assign(d, { sport: fromPlan.sport || 'other', art: fromPlan.art || '', name: fromPlan.title, start: new Date(fromPlan.date), dur: (fromPlan.min || 60) * 60, dist: fromPlan.dist || null, notes: fromPlan.notes || '' });
  return d;
}
/* Standard: wo du zuletzt geschwommen bist */
function lastWhere() { const a = ACTS.find(x => x.sport === 'swim' && swimWhere(x)); return a ? swimWhere(a) : 25; }
function openLog(date, sport) { S.sheet = { t: 'log', id: null, d: newLog(date, sport) }; render(); }
function openLogEdit(id) {
  const a = byId(id); if (!a) return;
  const manual = a.source === 'manual';
  S.sheet = { t: 'log', id, watch: !manual, d: { sport: a.sport, art: a.art || '', name: a.name, start: new Date(a.start), dur: a.dur, dist: a.dist || null, rpe: a.rpe ?? (manual ? 5 : null), avgHr: a.avgHr ?? null, kcal: a.kcal ?? null, notes: a.notes || '', ex: (a.ex || []).map(x => ({ ...x })), toTp: false, where: swimWhere(a) || 25, lanes: null } };
  render();
}

function logSheet() {
  const s = S.sheet, d = s.d, w = s.watch, sp = d.sport;
  let b = '';
  if (!w) b += `<div class="sportpick">${ALL.map(x => `<button type="button" class="${sp === x ? 'on' : ''}" style="--c:${C[x]}" data-act="lsport:${x}">${sicon(x)}<span>${NAME[x]}</span></button>`).join('')}</div>`;
  else b += `<div class="ins"><span class="dot" style="background:${C[sp]}"></span><div><b>Einheit von deiner Uhr</b><span>Messdaten bleiben unverändert. Was du hier korrigierst, bleibt auch nach jedem Sync erhalten.</span></div></div>`;
  const rows = [`<input name="l-name" class="big" placeholder="${logTitle(d)}" value="${esc(d.name)}" autocomplete="off">`];
  if (sp === 'other') rows.push(frow('Art', `<input name="l-art" list="othertypes2" value="${esc(d.art)}" placeholder="z. B. Kitesurfen"><datalist id="othertypes2">${OTHER_TYPES.map(x => `<option value="${x}">`).join('')}</datalist>`));
  b += fg(rows);
  if (!w) b += fg([frow('Datum', `<span class="pair"><input type="date" name="l-date" value="${isoDay(d.start)}" max="${isoDay(addDays(TODAY, 1))}"><input type="time" name="l-time" value="${time(d.start)}"></span>`),
    frow('Dauer (h:mm)', `<input name="l-dur" inputmode="numeric" value="${minTxt(Math.round(d.dur / 60))}" placeholder="1:00" required>`)]);
  if (sp === 'swim') b += `<div class="fgroup"><div class="frow"><span>Wo geschwommen?</span></div><div class="seg fill">${[[25, '25-m-Bahn'], [50, '50-m-Bahn'], ['ow', 'Freiwasser']].map(([k, l]) => `<button type="button" class="${d.where === k ? 'on' : ''}" data-act="lwhere:${k}">${l}</button>`).join('')}</div>${w ? '<span class="cap">Von der Uhr erkannt – hier korrigierbar.</span>' : ''}</div>`;
  if (hasDist(sp)) {
    const kmVal = d.dist ? +(d.dist / 1000).toFixed(sp === 'swim' ? 2 : 1) : '';
    const dr = [frow(sp === 'swim' ? 'Geschwommen (km)' : 'Distanz (km)', `<input name="l-dist" type="number" inputmode="decimal" step="${sp === 'swim' ? '0.05' : '0.1'}" min="0" max="${sp === 'bike' ? 500 : 100}" value="${kmVal}" placeholder="${sp === 'swim' ? 'z. B. 1,8' : 'z. B. 42,5'}" data-input="lpace">`)];
    if (sp === 'swim' && d.where !== 'ow') {
      dr.push(frow(`oder Bahnen <em class="cap">à ${d.where} m</em>`, `<input name="l-lanes" type="number" inputmode="numeric" min="1" max="400" placeholder="Anzahl" value="${d.lanes || ''}" data-input="llanes">`));
    }
    dr.push(`<div class="cap" id="lpace">${paceHint(sp, d.dist, d.dur)}</div>`);
    b += fg(dr);
  }
  if (sp === 'strength') {
    b += `<div class="fgroup"><div class="frow"><span>Übungen <em class="cap">optional</em></span><button type="button" class="linkbtn" data-act="lexadd">${icon('plus', 14)} Übung</button></div>
      ${d.ex.length ? `<div class="extable"><span class="cap">Übung</span><span class="cap">Sätze</span><span class="cap">Wdh/Zeit</span><span class="cap">kg</span><span></span>${d.ex.map((x, i) => `<input name="ex-n${i}" value="${esc(x.n)}" placeholder="z. B. Kniebeuge"><input name="ex-s${i}" type="number" inputmode="numeric" min="1" max="20" value="${x.s ?? ''}"><input name="ex-r${i}" value="${esc(x.r ?? '')}" placeholder="10 / 45s"><input name="ex-w${i}" type="number" inputmode="decimal" step="0.5" min="0" value="${x.w ?? ''}"><button type="button" class="xbtn" data-act="lexdel:${i}" aria-label="Übung entfernen">×</button>`).join('')}</div>
` : '<span class="cap">Z. B. Kniebeuge 3 × 10 mit 40 kg, Plank 3 × 45 s.</span>'}</div>`;
  }
  b += fg([`<div class="frow"><span>Anstrengung (RPE)</span><b id="rpev">${d.rpe ? `${d.rpe} · ${RPE_TXT[d.rpe]}` : '–'}</b></div><input type="range" name="l-rpe" min="1" max="10" step="1" value="${d.rpe || 5}" data-input="rpe">`,
    !w ? frow('Ø Herzfrequenz', `<input name="l-hr" type="number" inputmode="numeric" min="40" max="220" placeholder="optional" value="${d.avgHr ? Math.round(d.avgHr) : ''}">`) : '',
    !w ? frow('Kalorien', `<input name="l-kcal" type="number" inputmode="numeric" min="0" max="10000" placeholder="wird geschätzt" value="${d.kcal || ''}">`) : '']);
  b += fg([`<textarea name="l-notes" rows="3" placeholder="Notizen für dich und deine Trainerin – z. B. Hauptserie, Gefühl, Material">${esc(d.notes)}</textarea>`]);
  if (!s.id) b += fg([`<label class="frow"><span>${ICON.tp} An TrainingPeaks senden <em class="cap">über Apple Health</em></span><input type="checkbox" name="l-tp" ${d.toTp ? 'checked' : ''}></label>`,
    icuPushOn() || (SET.source === 'icu' && SET.icuKey) ? `<label class="frow"><span>${icon('sync', 16)} Auf allen Geräten <em class="cap">über intervals.icu – auch für Siri</em></span><input type="checkbox" name="l-icu" ${SET.icuPush !== false ? 'checked' : ''}></label>` : '']);
  if (s.id && !w) b += `<button type="button" class="btn danger" data-act="delact:${s.id}">Einheit löschen</button>`;
  return sheetWrap(s.id ? 'Einheit bearbeiten' : 'Einheit eintragen', b, 'logform');
}
const logTitle = d => d.sport === 'strength' ? 'Athletik' : d.sport === 'other' ? (d.art || 'Training') : { swim: 'Schwimmen', bike: 'Radfahrt', run: 'Lauf' }[d.sport];
function paceHint(sp, dist, dur) {
  if (!dist || !dur) return '';
  const v = dist / dur;
  return sp === 'swim' ? `Ø ${spaceS(v)}` : sp === 'bike' ? `Ø ${kmh(v)}` : `Ø ${pace(v)}`;
}
function readLogForm() {
  const f = document.getElementById('logform'); if (!f) return;
  const g = n => f.elements[n], v = n => g(n)?.value ?? '', d = S.sheet.d;
  if (g('l-name')) d.name = v('l-name').trim();
  if (g('l-art')) d.art = v('l-art').trim();
  if (g('l-date')) { const [Y, M, D] = v('l-date').split('-').map(Number), [hh, mm] = (v('l-time') || '12:00').split(':').map(Number); if (Y) d.start = new Date(Y, M - 1, D, hh || 0, mm || 0); }
  if (g('l-dur')) { const m = durMin(v('l-dur')); if (m > 0) d.dur = Math.round(m * 60); }
  if (g('l-dist')) { const x = parseFloat(v('l-dist').replace(',', '.')); d.dist = x > 0 ? Math.round(x * 1000) : null; }
  if (g('l-lanes')) d.lanes = +v('l-lanes') || null;
  if (g('l-rpe')) d.rpe = +v('l-rpe');
  if (g('l-hr')) d.avgHr = +v('l-hr') || null;
  if (g('l-kcal')) d.kcal = +v('l-kcal') || null;
  if (g('l-notes')) d.notes = v('l-notes');
  if (g('l-tp')) d.toTp = g('l-tp').checked;
  if (g('l-icu') && (SET.icuPush !== false) !== g('l-icu').checked) { SET.icuPush = g('l-icu').checked; saveSettings(); }
  d.ex = d.ex.map((x, i) => g('ex-n' + i) ? { n: v('ex-n' + i).trim(), s: +v('ex-s' + i) || null, r: v('ex-r' + i).trim(), w: parseFloat(v('ex-w' + i).replace(',', '.')) || null } : x);
}
const estKcal = (sp, dur, rpe) => Math.round(({ swim: 8, bike: 7.5, run: 10, strength: 5, other: 6 }[sp] || 6) * (.55 + (rpe || 5) * .09) * P.weight * dur / 3600);

async function saveLog() {
  readLogForm();
  const s = S.sheet, d = s.d;
  if (!(d.dur > 0) && !s.watch) { toast('Bitte eine Dauer eintragen'); return; }
  if (s.watch) {
    const a = byId(s.id), e = EDITS[s.id] || {};
    const set = (k, val, orig) => { if (val === orig || (val == null && orig == null) || val === '') delete e[k]; else e[k] = val; };
    set('name', d.name || a._orig?.name || a.name, a._orig?.name ?? a.name);
    if (hasDist(a.sport)) set('dist', d.dist, a._orig?.dist ?? a.dist);
    if (a.sport === 'swim') { const auto = a.swim ? (a.swim.ow ? 'ow' : Math.round(a.swim.pool || 25)) : null; if (d.where === auto) delete e.where; else e.where = d.where; }
    set('rpe', d.rpe, null); set('notes', d.notes || undefined, undefined);
    if (a.sport === 'other' && d.art) e.art = d.art;
    EDITS[s.id] = e; saveEdits(); recompute(); S.sheet = null; render(); toast('Änderungen gesichert'); return;
  }
  const old = s.id ? byId(s.id) : null;
  const a = {
    id: s.id || 'man-' + Date.now().toString(36), source: 'manual', sport: d.sport, art: d.art || undefined, name: d.name || logTitle(d),
    start: d.start, dur: d.dur, dist: hasDist(d.sport) ? (d.dist || 0) : 0, rpe: d.rpe, avgHr: d.avgHr, maxHr: null, kcal: d.kcal || estKcal(d.sport, d.dur, d.rpe),
    notes: d.notes, ex: d.sport === 'strength' ? d.ex.filter(x => x.n) : undefined, where: d.sport === 'swim' ? d.where : undefined, tp: old?.tp || null, samples: [], laps: [],
    extId: old?.extId, icuId: old?.icuId
  };
  a.tss = tss(a);
  try { await DB.put('acts', [a]); } catch (e) { toast('Speichern fehlgeschlagen: ' + e.message); return; }
  ACTS = ACTS.filter(x => x.id !== a.id); ACTS.push(a); recompute();
  const toTp = !s.id && d.toTp;
  S.sheet = null; render();
  toast(s.id ? 'Einheit aktualisiert' : `${a.name} eingetragen${a.dist ? ' · ' + distTxt(a.sport, a.dist) : ''}`);
  icuMirror(a, !!old);
  if (toTp) sendToHealth(a);
}
/* intervals.icu spiegeln: neue Einträge anlegen, geänderte aktualisieren (Fehler stören nicht – der Eintrag ist lokal gesichert) */
const icuPushOn = () => SET.source === 'icu' && !!SET.icuKey && SET.icuPush !== false;
async function icuMirror(a, isEdit) {
  if (!icuPushOn() || !navigator.onLine) return;
  try {
    if (a.icuId) { if (isEdit) await ICU.update(a.icuId, a); return; }
    const id = await ICU.push(a);
    if (id) { a.icuId = id; a.extId = id; await DB.put('acts', [a]); }
  } catch (e) { console.warn('intervals.icu', e); toast(`Lokal gesichert – intervals.icu: ${e.message}`); }
}

/* Geplantes Training mit einem Tipp als erledigt eintragen */
function planToLog() {
  readPlanForm();
  const p = S.sheet.d;
  S.sheet = { t: 'log', id: null, d: newLog(p.date, p.sport, p) }; render();
}

/* Live-Felder im Formular (ohne neu zu zeichnen, damit die Tastatur offen bleibt) */
document.addEventListener('input', e => {
  const k = e.target.dataset.input; if (!k || !S.sheet) return;
  const f = document.getElementById('logform');
  if (k === 'rpe') { const v = +e.target.value; S.sheet.d.rpe = v; const o = document.getElementById('rpev'); if (o) o.textContent = `${v} · ${RPE_TXT[v]}`; }
  if (k === 'llanes' && f) {
    const n = +f.elements['l-lanes'].value, pool = +S.sheet.d.where || 25;
    if (n > 0) f.elements['l-dist'].value = +(n * pool / 1000).toFixed(2);
  }
  if ((k === 'lpace' || k === 'llanes') && f) {
    const dist = parseFloat((f.elements['l-dist']?.value || '').replace(',', '.')) * 1000, m = durMin(f.elements['l-dur']?.value), o = document.getElementById('lpace');
    if (o) o.textContent = paceHint(S.sheet.d.sport, dist, (m || S.sheet.d.dur / 60) * 60);
  }
});
