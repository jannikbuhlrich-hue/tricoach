'use strict';
/* TriCoach – Fortschritt. Ideen aus anderen Apps, auf Triathlon zugeschnitten:
   Apple Fitness  → Wochenringe, Serien, Trends (90 Tage vs. 365 Tage), Auszeichnungen
   Strava         → Bestleistungen (schnellste 1/5/10 km, beste Watt), Jahresziele mit Hochrechnung
   Garmin         → VO2 Max mit Verlauf
   TrainingPeaks  → Plan vs. Ist der Woche (Erfüllung) */

const DEF_GOALS = { swim: 6, bike: 120, run: 30, strength: 2, hours: 8 };
const DEF_YEAR = { swim: 200, bike: 5000, run: 1200 };
const goals = () => ({ ...DEF_GOALS, ...(SET.goals || {}) });
const yearGoals = () => ({ ...DEF_YEAR, ...(SET.yearGoals || {}) });

/* Wochenwerte gegen Ziele */
function weekRings(ws) {
  const we = addDays(ws, 7), g = goals(), t = s => totals(s, ws, we);
  return [
    { k: 'swim', l: 'Schwimmen', v: t('swim').dist / 1000, g: g.swim, u: 'km', c: C.swim },
    { k: 'bike', l: 'Rad', v: t('bike').dist / 1000, g: g.bike, u: 'km', c: C.bike },
    { k: 'run', l: 'Laufen', v: t('run').dist / 1000, g: g.run, u: 'km', c: C.run },
    { k: 'strength', l: 'Athletik', v: t('strength').n, g: g.strength, u: '×', c: C.strength },
    { k: 'hours', l: 'Gesamt', v: totals(null, ws, we).dur / 3600, g: g.hours, u: 'h', c: 'var(--accent)' }
  ];
}
function ringStack(rs, size = 150) {
  const sw = size * .085, gap = sw * 1.25, cx = size / 2;
  return `<svg width="${size}" height="${size}" viewBox="0 0 ${size} ${size}" style="flex:none">${rs.map((r, i) => {
    const rad = cx - sw / 2 - i * gap, c = 2 * Math.PI * rad, f = r.g ? r.v / r.g : 0, over = f > 1;
    return `<circle cx="${cx}" cy="${cx}" r="${rad}" fill="none" stroke="${r.c}" stroke-opacity=".17" stroke-width="${sw}"/><circle cx="${cx}" cy="${cx}" r="${rad}" fill="none" stroke="${r.c}" stroke-width="${sw}" stroke-linecap="round" stroke-dasharray="${c * clamp(f, 0, 1)} ${c}" transform="rotate(-90 ${cx} ${cx})"/>${over ? `<circle cx="${cx}" cy="${cx}" r="${rad}" fill="none" stroke="${r.c}" stroke-width="${sw}" stroke-linecap="round" stroke-dasharray="${c * clamp(f - 1, 0, 1)} ${c}" transform="rotate(-90 ${cx} ${cx})" style="filter:brightness(1.35)"/>` : ''}`;
  }).join('')}</svg>`;
}
const metGoal = ws => weekRings(ws).filter(r => r.k !== 'hours').every(r => !r.g || r.v >= r.g * .999);
const weekActive = ws => totals(null, ws, addDays(ws, 7)).n > 0;

/* Serien */
function streaks() {
  let goalW = 0, actW = 0, ws = weekStart(TODAY);
  const curDone = metGoal(ws);
  for (let w = curDone ? ws : addDays(ws, -7), i = 0; i < 260 && metGoal(w); w = addDays(w, -7), i++) goalW++;
  for (let w = weekActive(ws) ? ws : addDays(ws, -7), i = 0; i < 260 && weekActive(w); w = addDays(w, -7), i++) actW++;
  const days = new Set(ACTS.map(a => isoDay(a.start)));
  let dRun = 0; for (let d = days.has(isoDay(TODAY)) ? TODAY : addDays(TODAY, -1); days.has(isoDay(d)); d = addDays(d, -1)) dRun++;
  let best = 0, cur = 0; [...days].sort().forEach((k, i, arr) => { cur = i && (new Date(k) - new Date(arr[i - 1])) / DAY === 1 ? cur + 1 : 1; best = Math.max(best, cur); });
  let bestGoal = 0; { let c = 0; for (let w = addDays(ws, -7 * 104); w <= ws; w = addDays(w, 7)) { c = metGoal(w) ? c + 1 : 0; bestGoal = Math.max(bestGoal, c); } }
  return { goalW, actW, dRun, best, bestGoal };
}

/* Trends wie in Apple Fitness: Schnitt der letzten 90 Tage vs. 365 Tage */
function trendRows() {
  const avg = (days, f) => { const xs = f(days).filter(num); return xs.length ? mean(xs) : null; };
  const wl = d => WELL.filter(w => w.date >= SINCE(d));
  const first = ACTS.length ? Math.min(...ACTS.map(a => a.start.getTime())) : Date.now(), span = d => Math.max(7, Math.min(d, (Date.now() - first) / DAY));
  const perWeek = (s, d) => [totals(s, SINCE(d), NOW)[s === 'strength' ? 'n' : 'dist'] / (span(d) / 7) / (s === 'strength' ? 1 : 1000)];
  const efs = d => ACTS.filter(a => a.sport === 'run' && a.start >= SINCE(d) && !a.laps?.some(l => l.interval)).map(ef);
  const swp = d => ACTS.filter(a => a.sport === 'swim' && a.start >= SINCE(d) && a.dist >= 800 && a.dur).map(a => a.dur / (a.dist / 100));
  const rows = [
    ['VO2 Max', 'run', d => wl(d).map(w => w.vo2), v => de(v, 1), 1],
    ['Ruhepuls', 'heart', d => wl(d).map(w => w.rhr), v => de(v) + ' bpm', -1],
    ['HRV', 'heart', d => wl(d).map(w => w.hrv), v => de(v) + ' ms', 1],
    ['Laufökonomie (EF)', 'run', efs, v => de(v, 2), 1],
    ['Schwimm-Pace', 'swim', swp, v => pv(v) + ' /100m', -1],
    ['Schwimmen pro Woche', 'swim', d => perWeek('swim', d), v => de(v, 1) + ' km', 1],
    ['Rad pro Woche', 'bike', d => perWeek('bike', d), v => de(v) + ' km', 1],
    ['Laufen pro Woche', 'run', d => perWeek('run', d), v => de(v, 1) + ' km', 1],
    ['Athletik pro Woche', 'strength', d => perWeek('strength', d), v => de(v, 1) + '×', 1]
  ];
  return rows.map(([l, ic, f, fmt, dir]) => { const a = avg(90, f), b = avg(365, f); if (a == null || b == null) return null; const ch = b ? (a - b) / Math.abs(b) : 0; return { l, ic, a, b, fmt, up: Math.abs(ch) < .015 ? 0 : (ch > 0 ? 1 : -1), good: Math.abs(ch) < .015 ? 0 : (ch * dir > 0 ? 1 : -1) }; }).filter(Boolean);
}

/* Bestleistungen (Strava „Best Efforts“) */
function fastest(a, D) {
  const s = a.samples?.filter(x => num(x.d)); if (!s || s.length < 3 || a.dist < D) return null;
  let j = 0, best = Infinity;
  for (let i = 0; i < s.length; i++) { while (j < s.length && s[j].d - s[i].d < D) j++; if (j >= s.length) break; const t = s[j].t - s[i].t; if (t < best) best = t; }
  return best < Infinity ? best : null;
}
function bests() {
  const out = [], runs = ACTS.filter(a => a.sport === 'run');
  [[1000, '1 km'], [5000, '5 km'], [10000, '10 km'], [21097.5, 'Halbmarathon']].forEach(([D, l]) => {
    let b = null; runs.forEach(a => { const t = fastest(a, D); if (t && (!b || t < b.t)) b = { t, a }; });
    if (b) out.push({ sport: 'run', l, v: dur(b.t), s: pv(b.t / (D / 1000)) + ' /km', a: b.a });
  });
  const longest = s => ACTS.filter(a => a.sport === s && a.dist).sort((x, y) => y.dist - x.dist)[0];
  const ls = longest('swim'); if (ls) out.push({ sport: 'swim', l: 'Längste Schwimmeinheit', v: distTxt('swim', ls.dist), s: hm(ls.dur), a: ls });
  const sw = ACTS.filter(a => a.sport === 'swim' && a.dist >= 1000 && a.dur).sort((x, y) => x.dur / x.dist - y.dur / y.dist)[0];
  if (sw) out.push({ sport: 'swim', l: 'Schnellste Pace (≥ 1 km)', v: pv(sw.dur / (sw.dist / 100)), s: '/100m · ' + distTxt('swim', sw.dist), a: sw });
  [[300, '5 min'], [1200, '20 min'], [3600, '60 min']].forEach(([k, l]) => {
    let b = null; ACTS.forEach(a => { const w = a.bike?.curve?.[k]; if (w && (!b || w > b.w)) b = { w, a }; });
    if (b) out.push({ sport: 'bike', l: `Beste ${l}`, v: b.w + ' W', s: de(b.w / P.weight, 2) + ' W/kg', a: b.a });
  });
  const lb = longest('bike'); if (lb) out.push({ sport: 'bike', l: 'Längste Ausfahrt', v: distTxt('bike', lb.dist), s: hm(lb.dur), a: lb });
  const lr = longest('run'); if (lr) out.push({ sport: 'run', l: 'Längster Lauf', v: distTxt('run', lr.dist), s: hm(lr.dur), a: lr });
  return out;
}

/* Auszeichnungen (Apple Fitness „Awards“) */
function awards() {
  const wk = ws => totals(null, ws, addDays(ws, 7)), weeks = []; for (let w = weekStart(TODAY), i = 0; i < 104; i++, w = addDays(w, -7)) weeks.push(w);
  const firstWhere = (list, f) => list.filter(f).sort((a, b) => a.start - b.start)[0];
  const st = streaks(), maxWeekH = Math.max(0, ...weeks.map(w => wk(w).dur / 3600));
  const yr = new Date(TODAY.getFullYear(), 0, 1), ytd = s => totals(s, yr, addDays(TODAY, 1)).dist / 1000;
  const early = ACTS.filter(a => a.start.getHours() < 7).length, str = ACTS.filter(a => a.sport === 'strength').length;
  const A = (ic, c, t, d, got, prog) => ({ ic, c, t, d, got, prog });
  const a1 = firstWhere(ACTS, a => a.sport === 'bike' && a.dist >= 100000), a2 = firstWhere(ACTS, a => a.sport === 'run' && a.dist >= 21097), a3 = firstWhere(ACTS, a => a.sport === 'swim' && a.dist >= 3800);
  return [
    A('bike', C.bike, 'Hunderter', '100 km am Stück geradelt', a1 && shortDate(a1.start), a1 ? 1 : Math.max(0, ...ACTS.filter(a => a.sport === 'bike').map(a => a.dist)) / 100000),
    A('run', C.run, 'Halbmarathon', '21,1 km am Stück gelaufen', a2 && shortDate(a2.start), a2 ? 1 : Math.max(0, ...ACTS.filter(a => a.sport === 'run').map(a => a.dist)) / 21097),
    A('swim', C.swim, 'Langdistanz-Schwimmer', '3,8 km am Stück geschwommen', a3 && shortDate(a3.start), a3 ? 1 : Math.max(0, ...ACTS.filter(a => a.sport === 'swim').map(a => a.dist)) / 3800),
    A('timer', 'var(--accent)', '10-Stunden-Woche', '10 h Training in einer Woche', maxWeekH >= 10 && 'geschafft', maxWeekH / 10),
    A('rings', 'var(--good)', 'Ringe geschlossen', '4 Wochen in Folge alle Wochenziele', st.bestGoal >= 4 && `${st.bestGoal} Wochen`, st.bestGoal / 4),
    A('strength', C.strength, 'Athletik-Profi', '25 Athletik-Einheiten', str >= 25 && `${str}×`, str / 25),
    A('star', 'var(--form)', 'Frühaufsteher', '10 Einheiten vor 7 Uhr', early >= 10 && `${early}×`, early / 10),
    A('swim', C.swim, `${de(yearGoals().swim)} km Schwimmen ${yr.getFullYear()}`, 'Jahresziel Schwimmen', ytd('swim') >= yearGoals().swim && 'erreicht', ytd('swim') / yearGoals().swim),
    A('flag', 'var(--accent)', 'Finisher', 'Einen Wettkampf aus dem Kalender gefinisht', PLAN.some(p => p.kind === 'race' && p.date < NOW && ACTS.some(a => sameDay(a.start, p.date))) && 'geschafft', PLAN.some(p => p.kind === 'race' && p.date < NOW && ACTS.some(a => sameDay(a.start, p.date))) ? 1 : 0)
  ];
}

/* VO2 Max: von der Uhr (über intervals.icu), sonst aus den Läufen geschätzt */
function vo2Series() {
  const w = WELL.filter(x => num(x.vo2)).map(x => ({ x: x.date.getTime(), y: x.vo2 }));
  return w.length ? { pts: w, src: 'Uhr' } : null;
}
function vo2Now() {
  const s = vo2Series(); if (s) { const last = s.pts[s.pts.length - 1], old = s.pts.filter(p => p.x <= last.x - 30 * DAY).pop(); return { v: last.y, d: old ? last.y - old.y : null, src: 'von deiner Uhr' }; }
  const v = ACTS.some(a => a.sport === 'run' && a.start >= SINCE(60) && a.samples?.length) ? estVdot() : null;
  return v ? { v, d: null, src: 'aus deinen Läufen geschätzt (VDOT)' } : null;
}
function vo2Card() {
  const n = vo2Now(); if (!n) return `<div class="card"><h3>${icon('run', 16, 'var(--run)')} VO2 Max</h3>${empty('Noch kein VO2 Max', 'Kommt automatisch von deiner Forerunner (über intervals.icu) oder wird aus Läufen mit GPS geschätzt.')}</div>`;
  const s = vo2Series(), W = cw(true);
  let chartSvg = '';
  if (s && s.pts.length > 3) {
    const pts = s.pts.filter(p => p.x >= Date.now() - 180 * DAY), ys = pts.map(p => p.y), x0 = pts[0].x, x1 = pts[pts.length - 1].x;
    chartSvg = chart({ w: W, h: 170, x0, x1, y0: Math.floor(Math.min(...ys)) - 1, y1: Math.ceil(Math.max(...ys)) + 1, yFmt: v => de(v), xt: dateTicks(x0, x1, 3, shortDate), layers: [area(pts, 'var(--run)', Math.floor(Math.min(...ys)) - 1), line(pts, 'var(--run)', 2.4)] });
  }
  return `<div class="card"><h3>${icon('run', 16, 'var(--run)')} VO2 Max <small>${n.src}</small></h3><div class="row" style="align-items:baseline;gap:10px;flex-wrap:wrap"><span class="bignum" style="font-size:54px;color:var(--run)">${de(n.v, 1)}</span><span class="muted">ml/kg/min</span>${num(n.d) ? `<b class="${n.d >= 0 ? 'good' : 'warnc'}">${sgn(n.d, 1)} in 30 Tagen</b>` : ''}</div>${chartSvg}<span class="cap">Maximale Sauerstoffaufnahme – der wichtigste Wert für deine aerobe Leistungsfähigkeit. Steigt mit regelmäßiger Grundlage und Intervallen.</span></div>`;
}

/* Plan vs. Ist (TrainingPeaks-Erfüllung) */
function planVsActual(ws) {
  const we = addDays(ws, 7), items = calItems(ws, we, true).filter(p => (p.kind || 'workout') === 'workout');
  const planned = items.reduce((s, p) => s + (p.min || 0) * 60, 0), past = items.filter(p => sod(p.date) <= TODAY), done = past.filter(p => doneFor(p));
  return { items, planned, actual: totals(null, ws, we).dur, n: items.length, past: past.length, done: done.length };
}

function vProgress() {
  let h = header('Fortschritt');
  if (!ACTS.length) return h + noData();
  const ws = weekStart(TODAY), rs = weekRings(ws), st = streaks(), pva = planVsActual(ws);
  const dayLeft = 7 - ((TODAY.getDay() + 6) % 7);
  h += `<div class="card"><h3>${icon('rings', 16, 'var(--accent)')} Wochenziele <small>KW ${kw(ws)} · noch ${dayLeft} ${dayLeft === 1 ? 'Tag' : 'Tage'}</small></h3><div class="hero ringhero">${ringStack(rs.slice(0, 4))}<div class="info ringlist">${rs.map(r => `<div class="ringrow"><i style="background:${r.c}"></i><span>${r.l}</span><b>${r.u === '×' ? de(r.v) : de(r.v, r.v < 10 && r.u !== 'h' ? 1 : 0)}<small> / ${de(r.g)} ${r.u}</small></b>${r.v >= r.g ? `<em class="good">${ICON.check}</em>` : `<em class="cap">${r.u === '×' ? de(r.g - r.v) : de(r.g - r.v, r.g - r.v < 10 ? 1 : 0)} ${r.u} fehlen</em>`}</div>`).join('')}</div></div>
    <div class="row" style="flex-wrap:wrap;justify-content:space-between"><span class="cap">${pva.n ? `Plan: ${hm(pva.planned)} · erledigt ${hm(pva.actual)} · ${pva.done}/${pva.past} geplante Einheiten bisher geschafft` : 'Plane Einheiten im Kalender, dann siehst du hier Plan vs. Ist.'}</span><button class="btn small" data-act="goals">${icon('edit', 14)} Ziele</button></div></div>`;
  // letzte 8 Wochen als Mini-Ringe
  h += `<div class="card"><h3>Letzte Wochen</h3><div class="weekstrip">${Array.from({ length: 8 }, (_, i) => addDays(ws, -7 * (7 - i))).map(w => `<div class="wk ${metGoal(w) ? 'met' : ''}">${ringStack(weekRings(w).slice(0, 4), 54)}<span class="cap">KW ${kw(w)}</span></div>`).join('')}</div>
    <div class="tiles">${tile('Wochenziel-Serie', st.goalW, st.goalW === 1 ? 'Woche' : 'Wochen', `Rekord ${st.bestGoal}`, 'var(--good)', 'rings')}${tile('Aktive Wochen', st.actW, 'in Folge', 'mit mind. 1 Einheit', 'var(--accent)', 'cal')}${tile('Tage in Folge', st.dRun, '', `Rekord ${st.best} Tage`, 'var(--form)', 'star')}</div></div>`;
  h += `<div class="cols two">${vo2Card()}${yearCard()}</div>`;
  const tr = trendRows();
  if (tr.length) h += `<div class="card"><h3>${icon('chart', 16)} Trends <small>letzte 90 Tage vs. 365 Tage</small></h3><div class="trends">${tr.map(t => `<div class="trend"><span class="arrow ${t.good > 0 ? 'up' : t.good < 0 ? 'down' : 'flat'}">${t.up > 0 ? '▲' : t.up < 0 ? '▼' : '▶'}</span><div><b>${t.l}</b><span class="cap">${t.fmt(t.a)} <span class="faint">· Jahr ${t.fmt(t.b)}</span></span></div></div>`).join('')}</div><span class="cap">Grün = Entwicklung in die richtige Richtung (beim Ruhepuls und bei der Schwimm-Pace ist weniger besser).</span></div>`;
  const b = bests();
  if (b.length) h += `<div class="card"><h3>${icon('trophy', 16, 'var(--form)')} Bestleistungen</h3><div class="tiles">${b.map(x => `<button class="tile" data-act="open:${x.a.id}" style="--c:${C[x.sport]}"><div class="ic">${sicon(x.sport)}</div><div class="t">${x.l}</div><div class="v">${x.v}</div><div class="s">${x.s} · ${shortDate(x.a.start)}</div></button>`).join('')}</div></div>`;
  const aw = awards();
  h += `<div class="card"><h3>${icon('star', 16, 'var(--form)')} Auszeichnungen <small>${aw.filter(a => a.got).length} von ${aw.length}</small></h3><div class="awards">${aw.map(a => `<div class="award ${a.got ? 'got' : ''}" style="--c:${a.c}"><span class="medal">${ICON[a.ic] || ICON.star}</span><b>${a.t}</b><span class="cap">${a.got ? a.got : a.d}</span>${a.got ? '' : `<div class="bar"><i style="width:${clamp(a.prog || 0, 0, 1) * 100}%;--c:${a.c}"></i></div>`}</div>`).join('')}</div></div>`;
  return h;
}
function yearCard() {
  const y = TODAY.getFullYear(), from = new Date(y, 0, 1), frac = (NOW - from) / (new Date(y + 1, 0, 1) - from), yg = yearGoals();
  return `<div class="card"><h3>${icon('flag', 16)} Jahresziele ${y} <small>${Math.round(frac * 100)} % des Jahres</small></h3>${['swim', 'bike', 'run'].map(s => {
    const v = totals(s, from, addDays(TODAY, 1)).dist / 1000, g = yg[s], proj = frac > .02 ? v / frac : null, ok = v >= g * frac;
    return `<div class="prow"><div class="top"><span style="color:${C[s]}">${NAME[s]}</span><span>${de(v, s === 'swim' ? 1 : 0)} / ${de(g)} km${proj ? ` · Hochrechnung ${de(proj)} km` : ''}</span></div><div class="bar ybar"><i style="width:${clamp(v / g, 0, 1) * 100}%;--c:${C[s]}"></i><u style="left:${frac * 100}%"></u></div><span class="cap ${ok ? 'good' : 'warnc'}">${ok ? 'im Plan' : `${de(g * frac - v, s === 'swim' ? 1 : 0)} km hinter dem Plan`}</span></div>`;
  }).join('')}<span class="cap">Strich = wo du heute sein müsstest. Ziele änderst du unter „Ziele“.</span></div>`;
}
function goalsSheet() {
  const g = goals(), y = yearGoals(), f = (n, l, v, st = '1') => frow(l, `<input name="${n}" type="number" inputmode="decimal" min="0" step="${st}" value="${v}">`);
  return sheetWrap('Ziele', `<b class="cap">Pro Woche</b>${fg([f('g-swim', 'Schwimmen (km)', g.swim, '0.5'), f('g-bike', 'Rad (km)', g.bike, '5'), f('g-run', 'Laufen (km)', g.run), f('g-strength', 'Athletik (Einheiten)', g.strength), f('g-hours', 'Training gesamt (h)', g.hours, '0.5')])}
    <b class="cap">Pro Jahr</b>${fg([f('y-swim', 'Schwimmen (km)', y.swim, '5'), f('y-bike', 'Rad (km)', y.bike, '100'), f('y-run', 'Laufen (km)', y.run, '50')])}
    <span class="cap">Tipp: Wochenziele aus dem Plan deiner Trainerin übernehmen – dann zeigen die Ringe, ob du die Woche geschafft hast.</span>`, 'goalform');
}
function saveGoals() {
  const f = document.getElementById('goalform'), v = n => parseFloat(String(f.elements[n].value).replace(',', '.')) || 0;
  SET.goals = { swim: v('g-swim'), bike: v('g-bike'), run: v('g-run'), strength: v('g-strength'), hours: v('g-hours') };
  SET.yearGoals = { swim: v('y-swim'), bike: v('y-bike'), run: v('y-run') };
  saveSettings(); S.sheet = null; render(); toast('Ziele gesichert');
}
