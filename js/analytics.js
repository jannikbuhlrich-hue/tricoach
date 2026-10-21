'use strict';
/* TriCoach – Trainingsanalysen (TSS/PMC, Prognosen, FTP, CSS, Aero, Taper, Fueling) */

const thrSpeed = () => 1000 / P.thrPace;
const cssSpeed = () => 100 / P.css;
const sysMass = () => P.weight + P.bikeKg;
const SINCE = d => new Date(Date.now() - d * DAY);

/* ---------- Physik & Modelle ---------- */
const aeroP = (v, cda, m, g = 0) => (0.5 * 1.225 * cda * v ** 3 + 0.004 * m * 9.81 * v + m * 9.81 * g * v) / 0.977;
function aeroV(p, cda, m, g = 0) { let lo = .5, hi = 25; for (let i = 0; i < 40; i++) { const mid = (lo + hi) / 2; aeroP(mid, cda, m, g) > p ? hi = mid : lo = mid; } return (lo + hi) / 2; }
function cdaEst(p, v, m) { if (!(v > 6) || !(p > 80)) return null; const c = (p * .977 - .004 * m * 9.81 * v) / (.5 * 1.225 * v ** 3); return c >= .15 && c <= .6 ? c : null; }
function vdot(d, t) { t /= 60; const v = d / t; return (-4.6 + .182258 * v + .000104 * v * v) / (.8 + .1894393 * Math.exp(-.012778 * t) + .2989558 * Math.exp(-.1932605 * t)); }
function predict(target, d) { let lo = d / 8, hi = d; for (let i = 0; i < 70; i++) { const m = (lo + hi) / 2; vdot(d, m) > target ? lo = m : hi = m; } return (lo + hi) / 2; }
function meanMax(vals, n) { n = Math.round(n); if (n <= 0 || vals.length < n) return null; let s = 0; for (let i = 0; i < n; i++) s += vals[i]; let b = s; for (let i = n; i < vals.length; i++) { s += vals[i] - vals[i - n]; if (s > b) b = s; } return b / n; }
function npower(vals) { const n = Math.max(1, Math.round(30 / DT)); if (vals.length < n) return null; let s = 0; for (let i = 0; i < n; i++) s += vals[i]; let acc = (s / n) ** 4, c = 1; for (let i = n; i < vals.length; i++) { s += vals[i] - vals[i - n]; acc += (s / n) ** 4; c++; } return (acc / c) ** .25; }
const CURVE = [10, 30, 60, 120, 300, 480, 600, 1200, 1800, 3600, 7200];

/* Ergänzt abgeleitete Werte einer Aktivität (für Demo-, FIT- und Live-Daten) */
function finalize(a) {
  const s = a.samples || (a.samples = []);
  a.laps = a.laps || [];
  const hrs = s.map(x => x.hr).filter(num);
  if (!num(a.avgHr) && hrs.length) a.avgHr = mean(hrs);
  if (!num(a.maxHr) && hrs.length) a.maxHr = Math.max(...hrs);
  if (!num(a.elev)) { let g = 0; for (let i = 1; i < s.length; i++) if (num(s[i].alt) && num(s[i - 1].alt)) g += Math.max(0, s[i].alt - s[i - 1].alt); a.elev = g; }
  if (a.sport === 'bike' && s.some(x => num(x.p))) {
    const pw = s.map(x => x.p || 0), curve = {};
    CURVE.forEach(c => { const m = meanMax(pw, c / DT); if (m) curve[c] = Math.round(m); });
    a.bike = Object.assign({ ap: mean(pw), np: npower(pw), cad: mean(s.map(x => x.cad).filter(v => v > 0)) }, a.bike || {}, { curve });
  }
  if (a.sport === 'run' && !a.run) {
    const f = k => mean(s.map(x => x[k]).filter(num));
    const stride = f('stride'), vo = f('vo');
    a.run = { cad: f('cad'), stride, gct: f('gct'), vo, vr: vo && stride ? vo / (stride * 100) * 100 : null, power: f('p') };
  }
  if (a.sport === 'swim' && a.lengths?.length && !a.swim?.swolf) {
    const act = a.lengths.filter(l => l.type === 'free' && l.strokes > 0), pool = a.swim?.pool || 25;
    a.swim = { pool, swolf: mean(act.map(l => Math.round(l.dur) + l.strokes)), rate: mean(act.map(l => l.strokes / l.dur * 60)), dps: act.length ? pool * act.length / act.reduce((x, y) => x + y.strokes, 0) : null };
  }
  a.tss = tss(a);
  return a;
}

/* Gefühlte Anstrengung (RPE 1–10, wie in TrainingPeaks) → Intensitätsfaktor für eingetragene Einheiten ohne Messdaten */
const RPE_IF = [0, .5, .55, .6, .65, .7, .77, .84, .91, .98, 1.05];
function tss(a) {
  const h = a.dur / 3600;
  if (a.sport === 'bike' && a.bike?.np) return h * (a.bike.np / P.ftp) ** 2 * 100;
  if (a.sport === 'run' && a.dist > 0) return h * (a.dist / a.dur / thrSpeed()) ** 2 * 100;
  if (a.sport === 'swim' && a.dist > 0) return h * Math.min(1.6, (a.dist / a.dur / cssSpeed())) ** 3 * 100;
  if (num(a.rpe) && !a.samples?.length) { const i = RPE_IF[clamp(Math.round(a.rpe), 1, 10)]; return h * i * i * 100; }
  if (num(a.avgHr)) { const i = clamp((a.avgHr - P.rhr) / (P.lthr - P.rhr), .3, 1.2); return h * i * i * 100; }
  return h * (a.sport === 'strength' ? 45 : 40);
}

/* ---------- Belastung ---------- */
function pmc(acts, from, to, future = {}, c0 = 0, a0 = 0) {
  const daily = {};
  acts.forEach(a => { const k = sod(a.start).getTime(); daily[k] = (daily[k] || 0) + (a.tss || 0); });
  for (const k in future) daily[k] = (daily[k] || 0) + future[k];
  let ctl = c0, atl = a0; const pts = [];
  const first = acts.length ? sod(Math.min(...acts.map(a => a.start.getTime()))) : sod(from);
  for (let d = first < from ? first : sod(from); d <= to; d = addDays(d, 1)) {
    const t = daily[d.getTime()] || 0, tsb = ctl - atl;
    ctl += (t - ctl) / 42; atl += (t - atl) / 7;
    if (d >= sod(from)) pts.push({ date: d, tss: t, ctl, atl, tsb });
  }
  return pts;
}
function totals(sport, from, to) {
  const r = { n: 0, dist: 0, dur: 0, tss: 0, elev: 0 };
  if (to < from) return r;
  ACTS.forEach(a => { if ((!sport || a.sport === sport) && a.start >= from && a.start < to) { r.n++; r.dist += a.dist || 0; r.dur += a.dur || 0; r.tss += a.tss || 0; r.elev += a.elev || 0; } });
  return r;
}
function weekly(sport, weeks = 10) {
  const ws = weekStart(TODAY), out = [];
  for (let b = weeks - 1; b >= 0; b--) { const s = addDays(ws, -7 * b), e = addDays(s, 7); out.push({ week: s, ...Object.fromEntries((sport ? [sport] : ALL).map(sp => [sp, totals(sp, s, e)])) }); }
  return out;
}

/* ---------- Zonen ---------- */
function hrZones() { const l = P.lthr; return [['Z1 Regeneration', 0, l * .85], ['Z2 Grundlage', l * .85, l * .9], ['Z3 Tempo', l * .9, l * .95], ['Z4 Schwelle', l * .95, l], ['Z5 VO2 Max', l, 260]]; }
function powerZones() { const f = P.ftp; return [['Z1 Aktive Erholung', 0, .55], ['Z2 Ausdauer', .55, .75], ['Z3 Tempo', .75, .9], ['Z4 Schwelle', .9, 1.05], ['Z5 VO2 Max', 1.05, 1.2], ['Z6 Anaerob', 1.2, 1.5], ['Z7 Neuromuskulär', 1.5, 12]].map(([n, a, b]) => [n, a * f, b * f]); }
function timeInZones(acts, zones, key) {
  const res = zones.map(() => 0);
  acts.forEach(a => { const s = a.samples || []; for (let i = 1; i < s.length; i++) { const dt = s[i].t - s[i - 1].t, v = s[i][key]; if (dt <= 0 || dt > 60 || !num(v)) continue; const z = zones.findIndex(([, lo, hi]) => v >= lo && v < hi); if (z >= 0) res[z] += dt; } });
  return res;
}
const zoneOf = hr => { const z = hrZones(); const i = z.findIndex(([, lo, hi]) => hr >= lo && hr < hi); return i < 0 ? 0 : i; };

/* ---------- Herzfrequenz einer Einheit ---------- */
function hrSummary(a) {
  const s = (a.samples || []).filter(x => num(x.hr) && x.hr > 30);
  if (!s.length && !num(a.avgHr)) return null;
  const z = hrZones(), tz = s.length ? timeInZones([a], z, 'hr') : null;
  const hrs = s.map(x => x.hr), half = s.length >> 1;
  // HF-Drift: Anstieg 2. Hälfte vs. 1. Hälfte (ohne erste 10 min) bei vergleichbarer Belastung
  const body = s.filter(x => x.t > 600), h = body.length >> 1;
  const drift = body.length > 40 ? (mean(body.slice(h).map(x => x.hr)) - mean(body.slice(0, h).map(x => x.hr))) : null;
  const above = s.length ? s.filter(x => x.hr >= P.lthr).length * DT : 0;
  const peak = s.length ? s.reduce((b, x) => x.hr > b.hr ? x : b, s[0]) : null;
  return { avg: s.length ? mean(hrs) : a.avgHr, max: s.length ? Math.max(...hrs) : a.maxHr, min: s.length ? Math.min(...hrs) : null, zones: tz, zoneNames: z, drift, above, peakAt: peak?.t ?? null, hasCurve: s.length > 5, dec: decoupling(a) };
}
function zoneBar(tz) {
  const tot = tz.reduce((a, b) => a + b, 0) || 1;
  return `<div class="zbar">${tz.map((t, i) => t > 0 ? `<i style="width:${t / tot * 100}%;background:${zc(i)}" title="Z${i + 1}: ${hm(t)}"></i>` : '').join('')}</div>`;
}

/* ---------- Bereitschaft ---------- */
function readiness() {
  const w = WELL[WELL.length - 1];
  const recent = ACTS.filter(a => (Date.now() - a.start) / 1000 - a.dur < 72 * 3600);
  const rec = Math.max(0, ...recent.map(a => Math.min(72, (a.tss || 0) * .35) - ((Date.now() - a.start) / 1000 - a.dur) / 3600));
  let score, src;
  if (w && num(w.readiness) && sameDay(w.date, TODAY)) { score = w.readiness; src = 'Uhr'; }
  else {
    score = 55; src = 'berechnet';
    const prev = WELL.slice(-8, -1);
    if (w?.sleep?.score) score += (w.sleep.score - 70) * .5;
    const hb = mean(prev.map(x => x.hrv).filter(num)); if (num(w?.hrv) && hb) score += (w.hrv / hb - 1) * 150;
    const rb = mean(prev.map(x => x.rhr).filter(num)); if (num(w?.rhr) && rb) score -= (w.rhr - rb) * 3;
    if (LOAD) score += LOAD.tsb * .8;
    score -= rec * .4;
  }
  score = Math.round(clamp(score, 0, 100));
  return { score, level: score < 40 ? 'low' : score < 70 ? 'mid' : 'high', rec, src };
}

/* ---------- Laufen ---------- */
function estVdot() {
  let best = 0;
  ACTS.filter(a => a.sport === 'run' && a.start >= SINCE(60) && a.samples?.length).forEach(a => {
    const v = a.samples.map(x => x.v || 0);
    [720, 1200, 2400].forEach(d => { if (a.dur < d) return; const m = meanMax(v, d / DT); if (m > 1.5 && m < 7) best = Math.max(best, vdot(m * d, d) * (d < 1000 ? .97 : 1)); });
  });
  return best || vdot(10000, P.thrPace * 10 * 1.04);
}
function intervals(a) {
  const w = (a.laps || []).filter(l => l.interval && l.v > 0); if (w.length < 2) return null;
  const v = w.map(l => l.v);
  return { reps: w, fade: (v[0] - v[v.length - 1]) / v[0] * 100, cv: sd(v) / mean(v) * 100, drift: num(w[0].hr) && num(w[w.length - 1].hr) ? Math.round(w[w.length - 1].hr - w[0].hr) : null };
}
const ef = a => num(a.avgHr) && a.dur > 0 ? a.dist / a.dur * 60 / a.avgHr : null;
function decoupling(a) {
  const s = (a.samples || []).filter(x => x.t > 600 && x.v > 0 && x.hr > 0); if (s.length < 40) return null;
  const h = s.length >> 1, e = x => mean(x.map(y => y.v)) / mean(x.map(y => y.hr));
  const e1 = e(s.slice(0, h)), e2 = e(s.slice(h));
  return (e1 - e2) / e1 * 100;
}

/* ---------- Rad ---------- */
function bestCurve(days) {
  const best = {};
  ACTS.filter(a => a.sport === 'bike' && a.start >= SINCE(days) && a.bike?.curve).forEach(a => { for (const k in a.bike.curve) best[k] = Math.max(best[k] || 0, a.bike.curve[k]); });
  return CURVE.filter(c => best[c]).map(c => ({ s: c, w: best[c] }));
}
function estFtp() {
  const c = Object.fromEntries(bestCurve(42).map(x => [x.s, x.w])); const cand = [];
  if (c[1200]) cand.push([c[1200] * .95, '95 % der besten 20 min']);
  if (c[3600]) cand.push([c[3600], 'beste 60 min']);
  if (c[480]) cand.push([c[480] * .9, '90 % der besten 8 min']);
  const b = cand.sort((x, y) => y[0] - x[0])[0];
  if (b && b[0] >= P.ftp * .93) return { w: Math.round(b[0]), src: b[1] };
  return { w: P.ftp, src: 'Profilwert (kein Maximaltest in 6 Wochen)' };
}
function aeroTrend() {
  return ACTS.filter(a => a.sport === 'bike' && a.samples?.some(x => num(x.p))).map(a => {
    const s = a.samples, est = [], m = sysMass();
    for (let i = 1; i < s.length; i++) {
      const dt = s[i].t - s[i - 1].t; if (!(dt > 0) || !num(s[i].alt) || !num(s[i - 1].alt)) continue;
      if (Math.abs(s[i].alt - s[i - 1].alt) / Math.max(s[i].v * dt, 1) < .004 && Math.abs(s[i].v - s[i - 1].v) < .3) { const c = cdaEst(s[i].p, s[i].v, m); if (c) est.push(c); }
    }
    return est.length > 30 ? { date: a.start, cda: median(est) } : null;
  }).filter(Boolean).sort((a, b) => a.date - b.date);
}

/* ---------- Schwimmen ---------- */
const freeLengths = a => (a.lengths || []).filter(l => l.type === 'free' && l.strokes > 0 && l.dur > 0);
function estCss() {
  let b2 = Infinity, b4 = Infinity;
  const win = (v, n) => { if (v.length < n) return Infinity; let s = 0; for (let i = 0; i < n; i++) s += v[i]; let b = s; for (let i = n; i < v.length; i++) { s += v[i] - v[i - n]; b = Math.min(b, s); } return b; };
  ACTS.filter(a => a.sport === 'swim' && a.start >= SINCE(60)).forEach(a => {
    const pool = a.swim?.pool || 25, t = freeLengths(a).map(l => l.dur);
    b2 = Math.min(b2, win(t, Math.round(200 / pool))); b4 = Math.min(b4, win(t, Math.round(400 / pool)));
  });
  return isFinite(b2) && isFinite(b4) && b4 > b2 ? (b4 - b2) / 2 : null;
}
function swimTrend() {
  return ACTS.filter(a => a.sport === 'swim' && freeLengths(a).length).map(a => {
    const l = freeLengths(a), pool = a.swim?.pool || 25;
    return { date: a.start, swolf: mean(l.map(x => Math.round(x.dur) + x.strokes)), dps: a.swim?.dps, pace: l.reduce((s, x) => s + x.dur, 0) / (pool * l.length) * 100 };
  }).sort((a, b) => a.date - b.date);
}
function strokeBins() {
  const g = {};
  ACTS.filter(a => a.sport === 'swim' && a.start >= SINCE(60)).forEach(a => { const pool = a.swim?.pool || 25; freeLengths(a).forEach(l => { const r = Math.round(l.strokes / l.dur * 60 / 5) * 5; (g[r] = g[r] || []).push([pool / l.dur, Math.round(l.dur) + l.strokes]); }); });
  return Object.entries(g).filter(([, v]) => v.length >= 5).map(([r, v]) => ({ rate: +r, v: mean(v.map(x => x[0])), swolf: mean(v.map(x => x[1])), n: v.length })).sort((a, b) => a.rate - b.rate);
}
function optimalStrokes() {
  const g = {};
  ACTS.filter(a => a.sport === 'swim').forEach(a => freeLengths(a).forEach(l => (g[l.strokes] = g[l.strokes] || []).push(Math.round(l.dur) + l.strokes)));
  return Object.entries(g).filter(([, v]) => v.length >= 10).map(([k, v]) => ({ k: +k, s: mean(v) })).sort((a, b) => a.s - b.s)[0];
}
function technique(a) {
  const l = freeLengths(a); if (l.length < 8) return null;
  const st = l.map(x => x.strokes), q = Math.max(1, l.length >> 2);
  const f = mean(l.slice(0, q).map(x => x.dur)), la = mean(l.slice(-q).map(x => x.dur));
  const cv = sd(st) / mean(st) * 100, drop = (la - f) / f * 100, tips = [];
  if (cv > 8) tips.push('Zugzahl schwankt stark. Kurze Serien mit fester Zugzahl schwimmen.');
  if (drop > 5) tips.push(`Tempo bricht hinten raus ein (${de(drop, 1)} %). Mehr CSS-Serien mit kurzen Pausen.`);
  if (a.swim?.dps && a.swim.dps < 1.4) tips.push(`Wenig Vortrieb pro Zug (${de(a.swim.dps, 2)} m). Catch-up- und Abschlag-Drills.`);
  if (!tips.length) tips.push('Stabile Technik über die ganze Einheit.');
  return { cv, drop, tips };
}

/* ---------- Stärken, Schwächen, Empfehlungen ---------- */
function scores() {
  const v = estVdot(), f = estFtp(), css = estCss() || P.css;
  const n = (x, a, b) => clamp((x - a) / (b - a) * 100, 0, 100);
  const freq = s => ACTS.filter(a => a.sport === s && a.start >= SINCE(28)).length / 4;
  return [
    { sport: 'swim', perf: n(-css, -140, -75), freq: freq('swim'), label: `CSS ${pv(css)} /100m` },
    { sport: 'bike', perf: n(f.w / P.weight, 2, 5), freq: freq('bike'), label: `${de(f.w / P.weight, 1)} W/kg` },
    { sport: 'run', perf: n(v, 35, 70), freq: freq('run'), label: `VDOT ${de(v, 1)}` }
  ];
}
function insights() {
  if (!ACTS.length) return [];
  const out = [], sc = scores(), by = [...sc].sort((a, b) => b.perf - a.perf), best = by[0], worst = by[2];
  out.push({ k: 'good', t: `Stärke: ${NAME[best.sport]}`, d: `${best.label} – Leistungsindex ${Math.round(best.perf)}/100.` });
  out.push({ k: 'focus', sport: worst.sport, t: `Potenzial: ${NAME[worst.sport]}`, d: `${worst.label} – größter Hebel für deine Gesamtzeit. Schlüsseleinheiten hier priorisieren.` });
  sc.filter(s => s.freq < 1.5).forEach(s => out.push({ k: 'warn', t: `Wenig ${NAME[s.sport]}`, d: `Nur ${de(s.freq, 1)} Einheiten/Woche. Für Fortschritt mindestens 2–3.` }));
  const tz = timeInZones(ACTS.filter(a => a.start >= SINCE(28)), hrZones(), 'hr'), tot = tz.reduce((a, b) => a + b, 0);
  if (tot) { const easy = (tz[0] + tz[1]) / tot, mid = tz[2] / tot; if (mid > .25) out.push({ k: 'warn', t: 'Zu viel Grauzone', d: `${Math.round(mid * 100)} % in Z3. Locker wirklich locker, hart wirklich hart.` }); else out.push({ k: 'info', t: 'Intensitätsverteilung', d: `${Math.round(easy * 100)} % in Z1–Z2, ${Math.round(mid * 100)} % in Z3 (letzte 4 Wochen).` }); }
  const dec = mean(ACTS.filter(a => a.sport === 'run' && a.dur >= 3600 && a.start >= SINCE(30)).map(decoupling).filter(num));
  if (dec != null) out.push({ k: dec > 5 ? 'warn' : 'info', t: `Aerobe Entkopplung ${de(dec, 1)} %`, d: dec > 5 ? 'Pace:HF driftet in langen Läufen. Mehr lockere Z2-Läufe.' : 'Lange Läufe bleiben stabil (Ziel unter 5 %).' });
  if (LOAD && LOAD.tsb < -30) out.push({ k: 'warn', t: 'Hohe Ermüdung', d: `Form ${Math.round(LOAD.tsb)}. Entlastung einplanen.` });
  return out;
}
function nextSat(off = 0) { let d = addDays(TODAY, 1); while (d.getDay() !== 6) d = addDays(d, 1); return at(addDays(d, off), 9); }

/* ---------- Deine Gewohnheiten & was deine Trainerin gerne plant ---------- */
const WDS = ['So', 'Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa'];   // nach getDay()
const STD_NAME = /^(lauf|laufen|radfahrt|rad|schwimmen|athletik(training)?|aktivität|training|freiwasser|einheit)$/i;
const coachWorkouts = (days = 120) => PLAN.filter(p => p.from === 'tp' && p.kind === 'workout' && p.date >= addDays(TODAY, -days));
function topTitles(list) { const m = new Map(); list.forEach(t => { const k = String(t || '').trim(); if (k && !STD_NAME.test(k)) m.set(k, (m.get(k) || 0) + 1); }); return [...m].sort((a, b) => b[1] - a[1]); }
function habits() {
  const since = SINCE(90), out = {};
  for (const s of ALL) {
    const xs = ACTS.filter(a => a.sport === s && a.start >= since), cw = coachWorkouts().filter(p => p.sport === s);
    if (!xs.length && !cw.length) continue;
    const wd = Array(7).fill(0); xs.forEach(a => wd[a.start.getDay()]++);
    const days = wd.map((n, i) => [i, n]).filter(([, n]) => n >= Math.max(2, xs.length * .15)).sort((a, b) => b[1] - a[1]).map(([i]) => i);
    const wh = xs.map(swimWhere).filter(Boolean), whereTop = wh.length ? [...wh.reduce((m, w) => m.set(w, (m.get(w) || 0) + 1), new Map())].sort((a, b) => b[1] - a[1])[0][0] : null;
    const HARD = /\d\s*[x×]|interv|schwelle|css|tempo|vo2|sweet|fahrtspiel|steiger|pyramide|sprint|rennpace|threshold|koppel/i;
    const hardW = cw.filter(p => HARD.test(p.title + ' ' + (p.notes || ''))), ct = topTitles(hardW.map(p => p.title)), favP = ct[0] && hardW.filter(p => p.title.trim() === ct[0][0]).sort((a, b) => b.date - a.date)[0];
    out[s] = {
      n: xs.length, perWeek: xs.length / 13, min: xs.length ? median(xs.map(a => a.dur / 60)) : null, long: xs.length ? Math.max(...xs.map(a => a.dur / 60)) : null,
      dist: median(xs.filter(a => a.dist).map(a => a.dist)), days, hour: xs.length ? median(xs.map(a => a.start.getHours() + a.start.getMinutes() / 60)) : null, where: s === 'swim' ? whereTop : null,
      own: topTitles(xs.map(a => a.name))[0]?.[0] || null,
      coach: cw.length ? { n: cw.length, min: median(cw.map(p => p.min || 60)), fav: favP && ct[0][1] >= 2 ? { title: favP.title.trim(), notes: favP.notes || '', min: favP.min || null, count: ct[0][1] } : null } : null
    };
  }
  return out;
}
/* Nächster freier Tag für eine Einheit: bevorzugt deine üblichen Trainingstage, nie auf Tage mit Plan deiner Trainerin */
function nextFree(sport, prefer) {
  const h = habits()[sport], hour = h?.hour != null ? Math.min(20, Math.max(6, Math.round(h.hour))) : 17, want = prefer || h?.days || [];
  const busy = d => PLAN.some(p => p.kind === 'workout' && sod(p.date).getTime() === d.getTime() && (p.from === 'tp' || p.sport === sport));
  let first = null;
  for (let i = 1; i <= 10; i++) { const d = addDays(TODAY, i); if (busy(d)) continue; first = first || d; if (!want.length || want.includes(d.getDay())) return at(d, hour); }
  return at(first || addDays(TODAY, 1), hour);
}
function habitLine() {
  const H = habits(), parts = SPORTS.filter(s => H[s]?.n >= 3).map(s => { const h = H[s]; return `${NAME[s]} ${h.days.length ? h.days.slice(0, 3).sort((a, b) => ((a + 6) % 7) - ((b + 6) % 7)).map(d => WDS[d]).join('/') + ' ' : ''}~${hm(h.min * 60)}${h.where ? ' (' + whereTxt(h.where) + ')' : ''}`; });
  const cn = coachWorkouts().length;
  return parts.length || cn ? `Typisch für dich: ${parts.join(' · ') || '–'}${cn ? ` · Plan deiner Trainerin: ${cn} Einheiten in 4 Monaten berücksichtigt` : ''}` : '';
}
const LONG = { volks: { bike: 75, run: 50 }, sprint: { bike: 105, run: 60 }, olympic: { bike: 150, run: 80 }, middle: { bike: 210, run: 105 }, full: { bike: 270, run: 150 } };
const r5 = x => Math.round(x / 5) * 5;

function recommendations() {
  if (!ACTS.length) return [];
  const out = [], rd = readiness(), ins = insights(), H = habits(), short = ['volks', 'sprint'].includes(RACE.fmt);
  const soon = PLAN.filter(p => p.from === 'tp' && p.kind === 'workout' && p.date >= TODAY && p.date < addDays(TODAY, 7)).sort((a, b) => a.date - b.date);
  if (soon.length) out.push({ p: 0, t: `Deine Trainerin hat ${soon.length} Einheit${soon.length === 1 ? '' : 'en'} geplant`, d: `Ihr Plan geht vor: ${soon.slice(0, 4).map(p => `${WDS[p.date.getDay()]} ${esc(p.title)}`).join(' · ')}${soon.length > 4 ? ' …' : ''}. Vorschläge von TriCoach landen nur auf freien Tagen.` });
  if (rd.level === 'low' || LOAD.tsb < -30) out.push({ p: 1, t: 'Heute Regeneration', d: `Bereitschaft ${rd.score}/100, Form ${Math.round(LOAD.tsb)}. 30–40 min locker (Z1) oder Ruhetag.`, w: { date: nextFree('swim'), sport: 'swim', title: 'Lockeres Ausschwimmen', min: 30 } });
  const days = Math.round((sod(RACE.date) - TODAY) / DAY);
  if (days >= 0 && days <= (TAPER_RANGE[RACE.fmt]?.[1] || 21) + 4) { const tp = taperBest(); out.push({ p: 1, t: `Taper (${days} Tage bis ${esc(RACE.name)})`, d: `Empfehlung für ${FMT[RACE.fmt].name}: ${tp.days} Tage, Umfang −${Math.round(tp.red * 100)} %. Intensität kurz und knackig halten.` }); }
  const weak = ins.find(i => i.k === 'focus')?.sport;
  if (rd.level !== 'low' && weak) {
    const h = H[weak] || {}, ow = weak === 'swim' && h.where === 'ow';
    const T = {
      swim: short ? (ow ? { t: 'Schlüsseleinheit Freiwasser', d: `15 min einschwimmen, 6×3 min @ Renntempo (${pv(P.css + 2)}/100m) mit Orientierung alle 6–8 Züge, 1 min locker. 4× Wendeboje üben.`, title: 'Freiwasser 6×3 min', min: 50 }
        : { t: 'Schlüsseleinheit Schwimmen', d: `300 m ein, 6×50 m steigern, 8×100 m @ CSS (${pv(P.css)}/100m) mit 15 s Pause, 4×25 m Sprint, 200 m aus.`, title: 'CSS 8×100 + Sprints', min: 50 })
        : { t: 'Schlüsseleinheit Schwimmen', d: `10×100 m @ CSS (${pv(P.css)}/100m), 15 s Pause. Vorher 4×50 m Technik.`, title: 'CSS 10×100', min: 55 },
      bike: short ? { t: 'Schlüsseleinheit Rad', d: `4×6 min @ ${Math.round(P.ftp * 1.0)}–${Math.round(P.ftp * 1.05)} W (VO2 Max/Schwelle), 4 min locker. Sprint-Rad ist kurz und hart.`, title: 'Rad 4×6 min', min: 70 }
        : { t: 'Schlüsseleinheit Rad', d: `3×15 min Sweet Spot @ ${Math.round(P.ftp * .88)}–${Math.round(P.ftp * .93)} W, 5 min Pause.`, title: 'Sweet Spot 3×15', min: 80 },
      run: short ? { t: 'Schlüsseleinheit Laufen', d: `6×800 m @ 5-km-Tempo (${pv(P.thrPace * .96)}/km), 2 min Trabpause.`, title: 'Laufen 6×800 m', min: 55 }
        : { t: 'Schlüsseleinheit Laufen', d: `5×1 km @ Schwelle (${pv(P.thrPace)}/km), 90 s Trabpause.`, title: 'Schwelle 5×1 km', min: 60 }
    }[weak];
    let min = h.min ? Math.min(T.min * 1.3, Math.max(T.min * .8, r5((T.min + h.min) / 2))) : T.min;
    let d = T.d + (h.n >= 4 ? ` Dauer an deine üblichen Einheiten (~${hm(h.min * 60)}) angepasst.` : '');
    let title = T.title, notes = T.d;
    const fav = h.coach?.fav;
    if (fav) { title = fav.title; min = fav.min || min; notes = fav.notes || T.d; d = `Orientiert an deiner Trainerin: Sie plant dir hier am häufigsten „${esc(fav.title)}“ (${fav.count}× in 4 Monaten).${fav.notes ? ' ' + esc(fav.notes.slice(0, 160)) + (fav.notes.length > 160 ? ' …' : '') : ''} Alternative: ${T.d}`; }
    out.push({ p: 2, sport: weak, t: T.t, d, w: { date: nextFree(weak), sport: weak, title, min: Math.round(min), notes } });
  }
  const L = LONG[RACE.fmt] || LONG.sprint;
  for (const s of ['bike', 'run']) {
    const target = L[s], h = H[s] || {};
    if (ACTS.some(a => a.sport === s && a.start >= SINCE(10) && a.dur >= target * 60 * .8)) continue;
    const min = r5(Math.min(target, Math.max(target * .7, (h.long || target) * 1.1)));
    const wkend = [6, 0].filter(x => !h.days?.length || h.days.includes(x));
    const txt = s === 'bike' ? `Seit 10 Tagen keine Ausfahrt über ${hm(target * 48)}. ${hm(min * 60)} in Z2 (${Math.round(P.ftp * .6)}–${Math.round(P.ftp * .75)} W)${short ? ' – für Sprint reicht das als lange Einheit.' : '.'}` : `${hm(min * 60)} locker bei ${pv(P.thrPace / .8)}/km${short ? ', die letzten 10 min zügig im 10-km-Tempo.' : '.'}`;
    out.push({ p: 3, sport: s, t: s === 'bike' ? 'Lange Radausfahrt fehlt' : 'Langer Lauf fehlt', d: txt, w: { date: nextFree(s, wkend.length ? wkend : [6, 0]), sport: s, title: s === 'bike' ? 'Lange Grundlage' : 'Langer Lauf', min } });
  }
  if (short && !ACTS.some(a => a.start >= SINCE(14) && /koppel|brick/i.test(a.name + ' ' + (a.notes || '')))) out.push({ p: 3, sport: 'run', t: 'Koppeltraining einbauen', d: `Für Sprint entscheidend: nach dem Rad direkt 10–15 min laufen, die ersten 5 min im Renntempo. Fertige Vorschläge unter Wettkampf → „Wettkampf simulieren“.` });
  if (LOAD.tsb > 10 && rd.level === 'high') out.push({ p: 2, t: 'Du bist frisch', d: `Form +${Math.round(LOAD.tsb)} und hohe Bereitschaft: guter Tag für einen Test (FTP, CSS oder 5 km).` });
  return out.sort((a, b) => a.p - b.p);
}

/* ---------- Wettkampf ---------- */
const FMT = {
  sprint: { name: 'Sprint', swim: 750, bike: 20000, run: 5000, ifb: .92, runF: 1.04, swimOff: 0, ctl: 50, trans: 150 },
  volks: { name: 'Volksdistanz', swim: 500, bike: 20000, run: 5000, ifb: .93, runF: 1.03, swimOff: -1, ctl: 40, trans: 150 },
  olympic: { name: 'Olympisch', swim: 1500, bike: 40000, run: 10000, ifb: .88, runF: 1.07, swimOff: 2, ctl: 65, trans: 180 },
  middle: { name: 'Mitteldistanz (70.3)', swim: 1900, bike: 90000, run: 21097.5, ifb: .78, runF: 1.13, swimOff: 4, ctl: 80, trans: 300 },
  full: { name: 'Langdistanz', swim: 3800, bike: 180000, run: 42195, ifb: .70, runF: 1.25, swimOff: 7, ctl: 100, trans: 480 }
};
function racePredict(cda, wetsuit) {
  const f = FMT[RACE.fmt], temp = RACE.temp ?? 20, swimPace = P.css + f.swimOff - (wetsuit ? 3 : 0), power = P.ftp * f.ifb, v = aeroV(power, cda, sysMass()) * (1 - .08 * (RACE.hills || 0));
  const runPace = P.thrPace * f.runF * (1 + Math.max(0, temp - 18) * .01);
  const r = { swim: f.swim / 100 * swimPace, t1: f.trans * .55, bike: f.bike / v, t2: f.trans * .45, run: f.run / 1000 * runPace, power, v, runPace, swimPace };
  r.total = r.swim + r.t1 + r.bike + r.t2 + r.run; return r;
}
function liveProjection(pred, done, cur) {
  const plan = [pred.swim, pred.t1, pred.bike, pred.t2, pred.run]; let total = done.reduce((a, b) => a + b, 0); const i = done.length;
  if (i >= plan.length) return total;
  const sofar = plan.slice(0, i).reduce((a, b) => a + b, 0), ratio = sofar ? total / sofar : 1, damp = 1 + (ratio - 1) * .5;
  total += Math.max(cur, plan[i] * damp); for (let k = i + 1; k < plan.length; k++) total += plan[k] * damp; return total;
}
function taperSim(days, red) {
  const base = ACTS.filter(a => a.start >= SINCE(28)).reduce((s, a) => s + (a.tss || 0), 0) / 28, race = sod(RACE.date), ts = addDays(race, -days), fut = {};
  for (let d = addDays(TODAY, 1); d <= race; d = addDays(d, 1)) fut[d.getTime()] = d >= race ? 0 : d >= ts ? base * (1 - red) : base;
  const proj = pmc([], addDays(TODAY, 1), race, fut, LOAD?.ctl || 0, LOAD?.atl || 0), last = proj[proj.length - 1], peak = Math.max(...proj.map(p => p.ctl));
  return { days, red, proj, tsb: last.tsb, ctl: last.ctl, loss: peak > 0 ? (peak - last.ctl) / peak * 100 : 0 };
}
const TAPER_RANGE = { volks: [3, 8], sprint: [3, 10], olympic: [5, 14], middle: [7, 18], full: [9, 21] };
function taperBest() { let best, bs = Infinity; const [d0, d1] = TAPER_RANGE[RACE.fmt] || [5, 21]; for (let d = d0; d <= d1; d++) for (let r = .3; r <= .601; r += .05) { const x = taperSim(d, r), s = Math.abs(x.tsb - 15) + x.loss * .8; if (s < bs) { bs = s; best = x; } } return best; }
const FUEL = [{ n: 'Gel', c: 25, fl: 0, na: 50 }, { n: 'Koffein-Gel', c: 25, fl: 0, na: 50, caf: 75 }, { n: 'Iso-Flasche 750 ml', c: 60, fl: 750, na: 500 }, { n: 'Riegel', c: 40, fl: 0, na: 100 }, { n: 'Wasser 500 ml', c: 0, fl: 500, na: 0 }, { n: 'Salztablette', c: 0, fl: 0, na: 250 }];
function fuelPlan(pr) {
  const temp = RACE.temp ?? 20, h = pr.total / 3600, carbs = h < 1.25 ? 30 : h < 2.5 ? 60 : h < 4 ? 75 : 90;
  const target = { carbs, fluid: clamp(500 + (temp - 15) * 20 + (P.weight - 70) * 3, 400, 1000), na: clamp(400 + (temp - 15) * 25, 300, 1000) };
  const steps = [], bs = Math.round((pr.swim + pr.t1) / 60), be = bs + Math.round(pr.bike / 60), rs = be + Math.round(pr.t2 / 60), re = rs + Math.round(pr.run / 60);
  for (let m = bs + 15, c = 0; m < be - 10; m += 20, c++) steps.push({ m, sport: 'bike', item: c % 3 === 0 ? FUEL[2] : (pr.bike > 10800 && c % 3 === 1 ? FUEL[3] : FUEL[0]) });
  for (let m = rs + 20; m < re - 10; m += 28) steps.push({ m, sport: 'run', item: (m - rs) > pr.run / 60 * .6 ? FUEL[1] : FUEL[0] });
  return { target, steps };
}

/* Wettkampf im Training simulieren: Einheiten mit den Zielwerten aus der Prognose */
function simSessions(pr) {
  const f = FMT[RACE.fmt], w = Math.round(pr.power), rp = pv(pr.runPace), sp = pv(pr.swimPace), km = x => de(x / 1000, x % 1000 ? 2 : 0).replace(/(,\d)0$/, '$1');
  const shortRace = ['volks', 'sprint'].includes(RACE.fmt);
  const legBike = shortRace ? 5000 : 10000, legRun = shortRace ? 1500 : 2500, reps = shortRace ? 3 : 3;
  const swimRep = shortRace ? (RACE.fmt === 'volks' ? 100 : 250) : 500, swimN = Math.max(2, Math.round(f.swim / swimRep));
  const generalMin = Math.round(pr.total / 60 + 25);
  return [
    { sport: 'bike', title: `Koppeltraining ${reps}× Rad/Lauf`, min: Math.round(reps * (legBike / pr.v + legRun / 1000 * pr.runPace) / 60 + 25),
      d: `Einfahren 15 min, dann ${reps}× (${km(legBike)} km Rad @ ${w} W → schnell wechseln → ${km(legRun)} km Lauf @ ${rp}/km), 3 min locker zwischen den Blöcken. Übt die schweren Beine nach dem Rad.` },
    { sport: 'swim', title: `Renntempo ${swimN}×${swimRep} m`, min: Math.round((swimN * swimRep / 100 * pr.swimPace + 1200) / 60 / 5) * 5,
      d: `Einschwimmen 400 m, dann ${swimN}×${swimRep} m @ ${sp}/100m${SET.wetsuit ? ' (mit Neo gerechnet)' : ''}, 20 s Pause. Ergibt genau deine ${km(f.swim)} km im Renntempo. Wenn möglich im Freiwasser.` },
    { sport: 'other', art: 'Koppeltraining', title: `Generalprobe ${f.name}`, min: generalMin,
      d: `Komplette ${f.name} am Stück (${km(f.swim)} / ${km(f.bike)} / ${km(f.run)} km) mit Wechseln – 10–14 Tage vor dem Rennen, mit dem Wettkampfmodus in TriCoach stoppen. Ziel: ${dur(pr.total)}. Fueling wie am Renntag testen.` },
    { sport: 'run', title: `Rennpace ${shortRace ? '5×1' : '4×2'} km`, min: shortRace ? 45 : 60,
      d: `${shortRace ? '5×1 km' : '4×2 km'} @ ${rp}/km (Lauftempo nach dem Rad laut Prognose), 90 s Trabpause. Hilft, das Tempo im Rennen nicht zu überziehen.` }
  ];
}
