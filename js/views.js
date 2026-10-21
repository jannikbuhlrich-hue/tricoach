'use strict';
/* TriCoach – Ansichten */

const SRC = { icu: 'Uhr', fit: 'FIT', live: 'Live', manual: 'eingetragen' };
const actRow = a => `<button class="act" data-act="open:${a.id}"><span class="sport" style="--c:${C[a.sport] || C.other}">${sicon(a.sport)}</span><span class="mid"><b>${esc(a.name)}</b><span>${shortDate(a.start)} · ${hm(a.dur)}${swimWhere(a) ? ' · ' + whereTxt(swimWhere(a)) : ''}${a.source === 'demo' ? '' : ' · ' + (SRC[a.source] || '')}${a.rpe && a.source === 'manual' ? ' · RPE ' + a.rpe : ''}${a.source === 'manual' ? (a.tp ? ' · ✓ TP' : ' · <em class="warnc">nicht in TP</em>') : ''}</span></span><span class="end"><b>${a.dist ? distTxt(a.sport, a.dist) : hm(a.dur)}</b><br><span>TSS ${Math.round(a.tss || 0)}</span></span></button>`;

function header(title, back) {
  let chip;
  if (SET.source === 'demo') chip = `<button class="chip" data-act="nav:settings">Demo-Daten · Uhr verbinden</button>`;
  else if (SET.source === 'icu') chip = `<button class="chip ${SYNC.busy ? 'busy' : ''}" data-act="sync" id="syncbadge">${icon('sync', 14)} ${SYNC.busy ? esc(SYNC.msg) : SET.lastSync ? 'Aktualisiert ' + time(new Date(SET.lastSync)) : 'Jetzt synchronisieren'}</button>`;
  else chip = `<button class="chip" data-act="nav:settings">${icon('watch', 14)} FIT-Daten</button>`;
  return `<div class="topline"><div>${back ? `<button class="back" data-act="back">‹ Zurück</button>` : ''}<h1>${title}</h1></div>${chip}</div>`;
}
function updateSyncBadge() { const b = document.getElementById('syncbadge'); if (b) b.innerHTML = `${icon('sync', 14)} ${esc(SYNC.msg)}`; }
const noData = () => `<div class="card">${empty('Noch keine Einheiten', 'Verbinde deine Forerunner in den Einstellungen. Neue Einheiten erscheinen dann automatisch nach jedem Training.', '<button class="btn primary" data-act="nav:settings">Uhr verbinden</button>')}</div>`;

/* ---------- Dashboard ---------- */
function vDashboard() {
  let h = header('Dashboard');
  if (!ACTS.length) return h + noData();
  const rd = readiness(), from = S.period === 'week' ? weekStart(TODAY) : monthStart(TODAY), to = S.period === 'week' ? addDays(from, 7) : new Date(from.getFullYear(), from.getMonth() + 1, 1);
  const pf = S.period === 'week' ? addDays(from, -7) : new Date(from.getFullYear(), from.getMonth() - 1, 1);
  const today = calItems(TODAY, addDays(TODAY, 1), true), rc = { high: 'var(--good)', mid: 'var(--warn)', low: 'var(--bad)' }[rd.level];
  h += `<div class="card hero-card"><div class="hero">${ring(rd.score / 100, rd.score, 'Bereitschaft', rc)}<div class="info"><span class="muted">${dayTitle(TODAY)}</span>` +
    (today.length ? today.map(p => `<div class="today" style="color:${isDone(p) ? 'var(--good)' : pColor(p)}">${isDone(p) ? '✓ ' : ''}${esc(p.title)}${p.allDay ? '' : ' · ' + (p.kind === 'event' ? time(p.date) : hm(p.min * 60))}</div>`).join('') : '<div class="today">Heute nichts geplant</div>') +
    `<div class="pills"><div class="pill"><b style="color:var(--fit)">${Math.round(LOAD.ctl)}</b><span>Fitness</span></div><div class="pill"><b style="color:var(--fat)">${Math.round(LOAD.atl)}</b><span>Ermüdung</span></div><div class="pill"><b style="color:var(--form)">${Math.round(LOAD.tsb)}</b><span>Form</span></div></div>` +
    `<span class="cap">Bereitschaft ${rd.src === 'Uhr' ? 'von deiner Uhr' : 'aus Schlaf, HRV und Belastung berechnet'}${rd.rec > 1 ? ` · Erholung noch ${Math.round(rd.rec)} h` : ''}</span></div></div></div>`;
  const latest = ACTS[0];
  if (latest && Date.now() - latest.start.getTime() < 48 * 3600 * 1000) h += latestCard(latest);
  h += `<div><div class="seg">${[['week', 'Woche'], ['month', 'Monat']].map(([k, l]) => `<button class="${S.period === k ? 'on' : ''}" data-act="period:${k}">${l}</button>`).join('')}</div></div>`;
  const vo = vo2Now();
  h += `<div class="tiles">` + ALL.map(s => { const t = totals(s, from, to), p = totals(s, pf, from), dl = p.dur ? (t.dur - p.dur) / p.dur * 100 : 0, cmp = p.dur ? ` · ${dl >= 0 ? '+' : ''}${Math.round(dl)} %` : '';
      if (!hasDist(s)) return tile(NAME[s], s === 'strength' ? t.n : hm(t.dur), s === 'strength' ? '×' : '', s === 'strength' ? `${hm(t.dur)}${cmp}` : `${t.n}×${cmp}`, C[s], s, 'calview:list');
      return tile(NAME[s], de(t.dist / 1000, s === 'bike' ? 0 : s === 'swim' ? (t.dist >= 10000 ? 1 : 2) : 1), 'km', `${t.n}× · ${hm(t.dur)}${cmp}`, C[s], s, 'nav:' + s); }).join('') +
    (() => { const t = totals(null, from, to); return tile('Gesamt', hm(t.dur), '', `TSS ${Math.round(t.tss)} · ${t.n} Einheiten`, 'var(--accent)', 'sum', 'nav:progress'); })() +
    (vo ? tile('VO2 Max', de(vo.v, 1), '', num(vo.d) ? `${sgn(vo.d, 1)} in 30 Tagen` : vo.src, 'var(--run)', 'run', 'nav:progress') : '') + `</div>`;

  const wk = weekly(null), W2 = cw(true), maxH = Math.max(1, ...wk.map(x => ALL.reduce((s, sp) => s + x[sp].dur, 0) / 3600)) * 1.1;
  const vol = chart({
    w: W2, x0: -.5, x1: wk.length - .5, y0: 0, y1: maxH, yFmt: v => de(v, v % 1 ? 1 : 0) + 'h', xt: wk.map((x, i) => ({ v: i, l: i % 2 ? '' : shortDate(x.week) })),
    layers: [(sx, sy) => wk.map((x, i) => { let y = 0; const bw = (sx(1) - sx(0)) * .62; return ALL.map(sp => { const hh = x[sp].dur / 3600, r = `<rect x="${sx(i) - bw / 2}" y="${sy(y + hh)}" width="${bw}" height="${Math.max(0, sy(y) - sy(y + hh))}" fill="${C[sp]}"/>`; y += hh; return r; }).join(''); }).join('')]
  });
  const pts = PMC.slice(-90), y0 = Math.min(0, ...pts.map(p => p.tsb)) - 5, y1 = Math.max(10, ...pts.map(p => Math.max(p.ctl, p.atl))) + 5, t0 = pts[0].date.getTime(), t1 = pts[pts.length - 1].date.getTime();
  const pmcSvg = chart({
    w: W2, x0: t0, x1: t1, y0, y1, xt: dateTicks(t0, t1, 3, shortDate),
    layers: [(sx, sy) => pts.map(p => `<rect x="${sx(p.date.getTime()) - 1.5}" y="${Math.min(sy(p.tsb), sy(0))}" width="3" height="${Math.abs(sy(p.tsb) - sy(0))}" fill="${p.tsb >= 0 ? 'var(--form)' : 'var(--faint)'}" opacity=".55"/>`).join(''),
    line(pts.map(p => ({ x: p.date.getTime(), y: p.atl })), 'var(--fat)', 1.6), line(pts.map(p => ({ x: p.date.getTime(), y: p.ctl })), 'var(--fit)', 2.6)]
  });
  h += `<div class="cols two"><div class="card"><h3>Umfang pro Woche</h3>${vol}<div class="legend">${ALL.map(s => `<span><i style="background:${C[s]}"></i>${NAME[s]}</span>`).join('')}</div></div>
    <div class="card"><h3>Fitness · Ermüdung · Form <small>90 Tage</small></h3>${pmcSvg}<div class="legend"><span><i style="background:var(--fit)"></i>Fitness (CTL)</span><span><i style="background:var(--fat)"></i>Ermüdung (ATL)</span><span><i style="background:var(--form)"></i>Form (TSB)</span></div></div></div>`;

  const z = hrZones(), tz = timeInZones(ACTS.filter(a => a.start >= from && a.start < to), z, 'hr'), tot = tz.reduce((a, b) => a + b, 0) || 1;
  const insCol = { good: 'var(--good)', focus: 'var(--bike)', warn: 'var(--warn)', info: 'var(--fit)' };
  h += `<div class="cols two"><div class="card"><h3>${icon('heart', 16, 'var(--bad)')} HF-Zonen <small>${S.period === 'week' ? 'diese Woche' : 'dieser Monat'}</small></h3>${z.map((zz, i) => prow(zz[0], tz[i] / tot, `${hm(tz[i])} · ${Math.round(tz[i] / tot * 100)} %`, zc(i))).join('')}</div>
    <div class="card"><h3>Stärken &amp; Schwächen</h3>${insights().map(i => `<div class="ins"><span class="dot" style="background:${insCol[i.k]}"></span><div><b>${i.t}</b><span>${i.d}</span></div></div>`).join('')}</div></div>`;

  const days = Math.round((sod(RACE.date) - TODAY) / DAY);
  if (days >= 0) {
    const pr = racePredict(SET.cda || .3, SET.wetsuit), f = FMT[RACE.fmt];
    h += `<button class="card" data-act="nav:race" style="text-align:left;cursor:pointer"><h3>${icon('flag')} Wettkampfvorbereitung <small>in ${days} Tagen</small></h3><b style="font-size:16px">${esc(RACE.name)}</b>${prow('Fitness (CTL) vs. Ziel', LOAD.ctl / f.ctl, Math.round(LOAD.ctl / f.ctl * 100) + ' %', 'var(--fit)')}${prow('Vorbereitung (16 Wochen)', 1 - Math.min(1, days / 112), Math.round((1 - Math.min(1, days / 112)) * 100) + ' %', 'var(--accent)')}<span class="cap">Prognose: ${dur(pr.total)} · ${f.name}</span></button>`;
  }
  const recs = recommendations();
  h += `<div class="card"><h3>Trainingsempfehlungen</h3>${recs.length ? recs.map((r, i) => `<div class="ins"><span class="dot" style="background:${r.sport ? C[r.sport] : 'var(--accent)'}"></span><div style="display:flex;flex-direction:column;gap:6px;align-items:flex-start"><div><b>${r.t}</b><span>${r.d}</span></div>${r.w ? `<button class="btn small" data-act="accept:${i}">In Kalender übernehmen · ${WDS[r.w.date.getDay()]} ${r.w.date.getDate()}.${r.w.date.getMonth() + 1}.</button>` : ''}</div></div>`).join('') : '<span class="muted">Alles im grünen Bereich.</span>'}${habitLine() ? `<span class="cap">${habitLine()}</span>` : ''}</div>`;
  h += `<div class="card"><h3>Letzte Einheiten</h3><div class="list">${ACTS.slice(0, 8).map(actRow).join('')}</div></div>`;
  return h;
}

function latestCard(a) {
  const hs = hrSummary(a);
  let h = `<button class="card" data-act="open:${a.id}" style="text-align:left;cursor:pointer"><h3>${icon(a.sport, 16, C[a.sport])} ${a.source === 'manual' ? 'Zuletzt eingetragen' : 'Neu von deiner Uhr'} <small>${shortDate(a.start)}, ${time(a.start)}</small></h3><b style="font-size:16px">${esc(a.name)} · ${hm(a.dur)}${a.dist ? ' · ' + distTxt(a.sport, a.dist) : ''}</b>`;
  if (hs) {
    h += `<div class="pills"><div class="pill"><b style="color:var(--bad)">${Math.round(hs.avg)}</b><span>Ø HF</span></div><div class="pill"><b>${num(hs.max) ? Math.round(hs.max) : '–'}</b><span>max HF</span></div>${hs.hasCurve ? `<div class="pill"><b>${hm(hs.above)}</b><span>über Schwelle</span></div>` : ''}<div class="pill"><b style="color:var(--bike)">${Math.round(a.tss || 0)}</b><span>TSS</span></div></div>`;
    if (hs.zones) h += zoneBar(hs.zones);
    else h += `<span class="cap">${a.partial ? 'HF-Kurve wird beim nächsten Sync automatisch nachgeladen.' : 'Für diese Einheit hat die Uhr nur Durchschnittswerte gespeichert.'}</span>`;
  } else h += `<span class="cap">Keine Herzfrequenz in dieser Einheit.</span>`;
  return h + `</button>`;
}

/* ---------- Analyse-Übersicht (iPhone-Tab) ---------- */
function vAnalyse() {
  let h = header('Mehr');
  const wf = weekStart(TODAY), wt = addDays(wf, 7);
  h += `<div class="card"><h3>Disziplinen</h3><div class="tiles">${SPORTS.map(s => { const t = totals(s, wf, wt); return tile(NAME[s], de(t.dist / 1000, s === 'swim' ? 2 : 1), 'km', `diese Woche · ${t.n}× · ${hm(t.dur)}`, C[s], s, 'nav:' + s); }).join('')}</div></div>`;
  const w = WELL[WELL.length - 1];
  h += `<div class="card"><h3>Werkzeuge</h3><div class="tiles">${tile('Schule', schoolOn() ? hwOpen().length : '–', schoolOn() ? 'Hausaufg.' : '', schoolOn() ? 'Stundenplan, Prüfungen' : 'WebUntis verbinden', 'var(--school)', 'school', 'nav:school')}${tile('Fortschritt', weekRings(wf).filter(r => r.k !== 'hours' && r.v >= r.g).length + '/4', 'Ziele', 'Ringe, Bestleistungen, VO2 Max', 'var(--good)', 'rings', 'nav:progress')}${tile('Wettkampf', ACTS.length ? dur(racePredict(SET.cda || .3, SET.wetsuit).total) : '–', '', 'Prognose, Taper, Fueling', 'var(--accent)', 'flag', 'nav:race')}${tile('Schlaf & Stress', w?.sleep ? hm(w.sleep.total) : '–', '', w ? `HRV ${num(w.hrv) ? Math.round(w.hrv) + ' ms' : '–'}` : 'keine Daten', 'var(--sleep)', 'moon', 'nav:wellness')}${tile('Live-Puls', BLE.st.connected ? (BLE.st.hr ?? '…') : 'Bluetooth', BLE.st.connected ? 'bpm' : '', 'Uhr als Pulsgurt', 'var(--bad)', 'heart', 'nav:pulse')}${tile('Karte', ACTS.filter(a => a.samples?.some(x => x.lat)).length, 'Strecken', 'alle GPS-Spuren', 'var(--fit)', 'map', 'nav:map')}</div></div>`;
  h += `<div class="card"><button class="act" data-act="nav:settings"><span class="sport" style="--c:var(--muted)">${ICON.gear}</span><span class="mid"><b>Einstellungen</b><span>Uhr, TrainingPeaks, Schule, Design, Profil, Updates</span></span><span class="end">›</span></button></div>`;
  return h;
}

/* ---------- Laufen ---------- */
function vRun() {
  let h = header('Laufen', true);
  const runs = ACTS.filter(a => a.sport === 'run');
  if (!runs.length) return h + `<div class="card">${empty('Noch keine Läufe', 'Sobald deine Uhr einen Lauf liefert, erscheinen hier Prognosen und Laufökonomie.')}</div>`;
  const v = estVdot(), W = cw(false), W2 = cw(true);
  const dists = [['5 km', 5000], ['10 km', 10000], ['Halbmarathon', 21097.5], ['Marathon', 42195]];
  h += `<div class="card"><h3>${icon('timer')} Tempoprognosen <small>VDOT ${de(v, 1)}</small></h3><div class="tiles">${dists.map(([n, d]) => { const t = predict(v, d); return tile(n, dur(t), '', pv(t / (d / 1000)) + ' /km', 'var(--run)', 'flag'); }).join('')}</div><span class="cap">Aus deinen schnellsten zusammenhängenden Abschnitten der letzten 60 Tage (Daniels-VDOT).</span></div>`;
  const wk = weekly('run', 12), mx = Math.max(5, ...wk.map(x => x.run.dist / 1000)) * 1.15;
  h += `<div class="card"><h3>Wochenkilometer</h3>${chart({ w: W, h: 180, x0: -.5, x1: wk.length - .5, y0: 0, y1: mx, xt: wk.map((x, i) => ({ v: i, l: i % 2 ? '' : shortDate(x.week) })), layers: [(sx, sy) => wk.map((x, i) => { const bw = (sx(1) - sx(0)) * .6; return `<rect x="${sx(i) - bw / 2}" y="${sy(x.run.dist / 1000)}" width="${bw}" height="${sy(0) - sy(x.run.dist / 1000)}" rx="4" fill="var(--run)" opacity="${i === wk.length - 1 ? 1 : .7}"/>`; }).join('')] })}</div>`;

  const sess = runs.filter(a => intervals(a)).slice(0, 10), sel = byId(S.intSel) || sess[0], ia = sel && intervals(sel);
  if (ia) {
    const reps = ia.reps, pmin = Math.min(...reps.map(r => 1000 / r.v)) - 8, pmax = Math.max(...reps.map(r => 1000 / r.v)) + 4;
    const svg = chart({ w: W2, h: 180, x0: .4, x1: reps.length + .6, y0: pmax + 4, y1: pmin, yt: ticks(pmin, pmax + 4), yFmt: pv, xt: reps.map((r, i) => ({ v: i + 1, l: 'Wdh ' + (i + 1) })), layers: [(sx, sy) => reps.map((r, i) => `<rect x="${sx(i + 1) - 14}" y="${sy(1000 / r.v)}" width="28" height="${sy(pmax + 4) - sy(1000 / r.v)}" rx="4" fill="var(--run)"/>${num(r.hr) ? `<text x="${sx(i + 1)}" y="${sy(1000 / r.v) - 6}" text-anchor="middle" class="axis">${Math.round(r.hr)}</text>` : ''}`).join('')] });
    h += `<div class="cols two"><div class="card"><h3>Intervallanalyse</h3><select class="sel" id="intsel" data-change="int">${sess.map(a => `<option value="${a.id}" ${a === sel ? 'selected' : ''}>${shortDate(a.start)} – ${esc(a.name)}</option>`).join('')}</select>${svg}<span class="cap">Balken: Pace pro Wiederholung (höher = schneller) · Zahl: Ø HF</span></div>
      <div class="card"><h3>Auswertung</h3><div class="tiles">${tile('Tempoverlust', de(ia.fade, 1), '%', 'letzte vs. erste Wdh.', ia.fade > 3 ? 'var(--warn)' : 'var(--good)')}${tile('Gleichmäßigkeit', de(ia.cv, 1), '% CV', ia.cv < 2 ? 'sehr gleichmäßig' : 'Pace schwankt', ia.cv > 3 ? 'var(--warn)' : 'var(--good)')}${ia.drift != null ? tile('HF-Drift', (ia.drift > 0 ? '+' : '') + ia.drift, 'bpm', 'über die Serie', 'var(--bad)', 'heart') : ''}</div></div></div>`;
  }
  const easy = runs.filter(a => !a.laps.some(l => l.interval) && ef(a)).sort((a, b) => a.start - b.start), pts = easy.map(a => ({ x: a.start.getTime(), y: ef(a) }));
  if (pts.length > 2) {
    const vals = pts.map(p => p.y), last = vals.slice(-12), trend = slope(last) * last.length / mean(last) * 100;
    const dec = mean(easy.filter(a => a.dur >= 3600 && a.start >= SINCE(30)).map(decoupling).filter(num));
    h += `<div class="card"><h3>Laufökonomie</h3>${chart({ w: W, h: 190, x0: pts[0].x, x1: pts[pts.length - 1].x, y0: Math.min(...vals) - .02, y1: Math.max(...vals) + .02, yFmt: v => de(v, 2), xt: dateTicks(pts[0].x, pts[pts.length - 1].x, 4, shortDate), layers: [dots(pts, 'var(--run)', 2.5), line(rolling(pts), 'var(--run)', 2.4)] })}
      <span class="cap">Efficiency Factor (m/min pro Herzschlag) lockerer Läufe, Linie = Schnitt der letzten 5. Trend: ${trend >= 0 ? '+' : ''}${de(trend, 1)} %${trend >= 0 ? ' (ökonomischer)' : ''}</span>${dec != null ? prow('Aerobe Entkopplung', dec / 10, de(dec, 1) + ' % (Ziel unter 5 %)', dec > 5 ? 'var(--warn)' : 'var(--good)') : ''}</div>`;
  }
  const r = runs.find(a => a.run?.gct || a.run?.cad)?.run;
  if (r) h += `<div class="card"><h3>Laufdynamik <small>letzter Lauf mit Daten</small></h3><div class="tiles">${num(r.cad) ? tile('Kadenz', de(r.cad), 'spm', '', 'var(--run)') : ''}${num(r.stride) ? tile('Schrittlänge', de(r.stride, 2), 'm', '', 'var(--run)') : ''}${num(r.gct) ? tile('Bodenkontaktzeit', de(r.gct), 'ms', r.gct < 240 ? 'sehr gut' : r.gct < 270 ? 'gut' : 'ausbaufähig', 'var(--run)') : ''}${num(r.vo) ? tile('Vertikale Bewegung', de(r.vo, 1), 'cm', '', 'var(--run)') : ''}${num(r.vr) ? tile('Vertikales Verhältnis', de(r.vr, 1), '%', '', 'var(--run)') : ''}${num(r.power) ? tile('Laufleistung', de(r.power), 'W', '', 'var(--run)', 'bolt') : ''}</div></div>`;
  h += `<div class="card"><h3>Läufe</h3><div class="list">${runs.slice(0, 8).map(actRow).join('')}</div></div>`;
  return h;
}

/* ---------- Rad ---------- */
function vBike() {
  let h = header('Radfahren', true);
  const rides = ACTS.filter(a => a.sport === 'bike');
  if (!rides.length) return h + `<div class="card">${empty('Noch keine Radfahrten', 'Mit Wattmessung bekommst du hier FTP, Leistungskurve und Aero-Trend.')}</div>`;
  const f = estFtp(), curve = bestCurve(S.curveDays), aero = aeroTrend(), W = cw(false), W2 = cw(true);
  h += `<div class="card"><h3>${icon('bolt', 16, 'var(--bike)')} FTP-Schätzung</h3><div class="tiles">${tile('FTP', f.w, 'W', f.src, 'var(--bike)', 'bolt')}${tile('Watt/kg', de(f.w / P.weight, 2), 'W/kg', `bei ${de(P.weight)} kg`, 'var(--bike)')}${tile('Profil-FTP', P.ftp, 'W', 'Basis für Zonen und TSS', 'var(--bike)')}</div>${Math.abs(f.w - P.ftp) > Math.max(5, P.ftp / 40) ? `<div><button class="btn primary" data-act="applyftp:${f.w}">Profil-FTP auf ${f.w} W setzen</button></div>` : ''}</div>`;
  if (curve.length > 2) {
    const lbl = s => s < 60 ? s + 's' : s < 3600 ? s / 60 + 'm' : s / 3600 + 'h', cp = curve.map((c, i) => ({ x: i, y: c.w })), ymax = Math.max(...curve.map(c => c.w)) * 1.08;
    h += `<div class="card"><h3>Leistungskurve</h3><div><div class="seg">${[42, 90, 150].map(d => `<button class="${S.curveDays === d ? 'on' : ''}" data-act="curve:${d}">${d} Tage</button>`).join('')}</div></div>${chart({ w: W, h: 210, x0: 0, x1: cp.length - 1, y0: 0, y1: ymax, yFmt: v => de(v) + ' W', pad: [12, 16, 24, 52], xt: curve.map((c, i) => ({ v: i, l: lbl(c.s) })), layers: [area(cp, 'var(--bike)', 0), line(cp, 'var(--bike)', 2.6), dots(cp, 'var(--bike)', 3)] })}<span class="cap">Beste Durchschnittsleistung je Dauer (Mean-Max).</span></div>`;
  }
  const z = powerZones(), tz = timeInZones(rides.filter(a => a.start >= SINCE(28)), z, 'p'), tot = tz.reduce((a, b) => a + b, 0);
  let right = `<div class="card"><h3>Aerodynamik-Trend (CdA)</h3>${empty('Zu wenig Daten', 'Benötigt Fahrten mit Leistung, Tempo und Höhe.')}</div>`;
  if (aero.length > 3) {
    const ap = aero.map(a => ({ x: a.date.getTime(), y: a.cda })), first = mean(aero.slice(0, 5).map(a => a.cda)), last = mean(aero.slice(-5).map(a => a.cda)), watts = aeroP(10, first, sysMass()) - aeroP(10, last, sysMass());
    right = `<div class="card"><h3>Aerodynamik-Trend (CdA)</h3>${chart({ w: W2, h: 190, x0: ap[0].x, x1: ap[ap.length - 1].x, y0: Math.min(...ap.map(p => p.y)) - .005, y1: Math.max(...ap.map(p => p.y)) + .005, yFmt: v => de(v, 3), pad: [12, 12, 24, 46], xt: dateTicks(ap[0].x, ap[ap.length - 1].x, 3, shortDate), layers: [dots(ap, 'var(--bike)', 3), line(rolling(ap), 'var(--bike)', 2)] })}<span class="cap">Veränderung ${de((last - first) / first * 100, 1)} % CdA ≈ ${Math.round(watts)} W Unterschied bei 36 km/h. Aus flachen, gleichmäßigen Abschnitten geschätzt, als Trend lesen.</span></div>`;
  }
  h += `<div class="cols two"><div class="card"><h3>Leistungszonen <small>28 Tage</small></h3>${tot ? z.map((zz, i) => prow(zz[0], tz[i] / tot, `${Math.round(zz[1])}–${zz[2] > 2000 ? '∞' : Math.round(zz[2])} W · ${hm(tz[i])}`, zc(i))).join('') : empty('Keine Wattdaten', 'In den letzten 4 Wochen keine Fahrt mit Leistungsmesser.')}</div>${right}</div>`;
  h += `<div class="card"><h3>Ausfahrten</h3><div class="list">${rides.slice(0, 8).map(actRow).join('')}</div></div>`;
  return h;
}

/* ---------- Schwimmen ---------- */
function vSwim() {
  let h = header('Schwimmen', true);
  const swims = ACTS.filter(a => a.sport === 'swim');
  if (!swims.length) return h + `<div class="card">${empty('Noch keine Schwimmeinheiten', 'Beckenschwimmen liefert Bahnen, Züge und SWOLF für die Analyse.')}</div>`;
  const css = estCss(), tr = swimTrend(), bins = strokeBins(), opt = optimalStrokes(), W = cw(false), W2 = cw(true), last = tr[tr.length - 1];
  h += `<div class="card"><h3>Schwimmform</h3><div class="tiles">${tile('CSS (geschätzt)', css ? pv(css) : '–', '/100m', `Profil: ${pv(P.css)}`, 'var(--swim)', 'timer')}${last ? tile('Ø SWOLF', de(last.swolf, 1), '', 'letzte Einheit', 'var(--swim)', 'swim') : ''}${last?.dps ? tile('Distanz pro Zug', de(last.dps, 2), 'm', '', 'var(--swim)') : ''}${opt ? tile('Optimale Zugzahl', opt.k, '/Bahn', `SWOLF ${de(opt.s, 1)}`, 'var(--swim)') : ''}</div>${css && Math.abs(css - P.css) >= 2 ? `<div><button class="btn primary" data-act="applycss:${Math.round(css)}">Profil-CSS auf ${pv(css)} setzen</button></div>` : ''}</div>`;
  if (tr.length > 2) {
    const sp = tr.map(t => ({ x: t.date.getTime(), y: t.swolf }));
    h += `<div class="card"><h3>SWOLF-Trend</h3>${chart({ w: W, h: 190, x0: sp[0].x, x1: sp[sp.length - 1].x, y0: Math.floor(Math.min(...sp.map(p => p.y)) - 1), y1: Math.ceil(Math.max(...sp.map(p => p.y)) + 1), xt: dateTicks(sp[0].x, sp[sp.length - 1].x, 4, shortDate), layers: [dots(sp, 'var(--swim)', 2.5), line(rolling(sp), 'var(--swim)', 2.6)] })}<span class="cap">Punkte: einzelne Einheiten · Linie: Schnitt der letzten 5. SWOLF = Sekunden + Züge pro Bahn (nur Kraul, ohne Drills). Niedriger ist besser.</span></div>`;
  }
  const techAct = swims.find(a => technique(a)), tech = techAct && technique(techAct);
  let left = `<div class="card"><h3>Frequenzanalyse</h3>${empty('Zu wenig Bahnen', 'Benötigt Beckenschwimmen mit Zugzählung.')}</div>`;
  if (bins.length > 1) {
    const best = [...bins].sort((a, b) => b.v - a.v)[0], pmin = Math.min(...bins.map(b => 100 / b.v)) - 4, pmax = Math.max(...bins.map(b => 100 / b.v)) + 2;
    left = `<div class="card"><h3>Frequenzanalyse</h3>${chart({ w: W2, h: 190, x0: -.5, x1: bins.length - .5, y0: pmax + 3, y1: pmin, yt: ticks(pmin, pmax + 3), yFmt: pv, xt: bins.map((b, i) => ({ v: i, l: b.rate + '/min' })), layers: [(sx, sy) => bins.map((b, i) => { const bw = Math.min(40, (sx(1) - sx(0)) * .6); return `<rect x="${sx(i) - bw / 2}" y="${sy(100 / b.v)}" width="${bw}" height="${sy(pmax + 3) - sy(100 / b.v)}" rx="4" fill="var(--swim)" opacity="${b === best ? 1 : .35}"/>`; }).join('')] })}<span class="cap">Pace je Zugfrequenz (höher = schneller). Am schnellsten bei etwa ${best.rate} Zügen/min (${spaceS(best.v)}).</span></div>`;
  }
  const right = tech ? `<div class="card"><h3>Technikindikatoren <small>${shortDate(techAct.start)}</small></h3><div class="tiles">${tile('Zugzahl-Konstanz', de(tech.cv, 1), '% CV', '', tech.cv > 8 ? 'var(--warn)' : 'var(--good)')}${tile('Tempoabfall', de(tech.drop, 1), '%', '', tech.drop > 5 ? 'var(--warn)' : 'var(--good)')}</div>${tech.tips.map(t => `<div class="ins"><span class="dot" style="background:var(--form)"></span><div><span class="fg">${t}</span></div></div>`).join('')}</div>` : '';
  h += `<div class="cols two">${left}${right}</div>`;
  const wh = { 25: 0, 50: 0, ow: 0 }; swims.filter(a => a.start >= SINCE(90)).forEach(a => { const w = swimWhere(a); const k = w === 'ow' ? 'ow' : w >= 45 ? 50 : 25; wh[k] += a.dist || 0; });
  const whTot = wh[25] + wh[50] + wh.ow;
  if (whTot) h += `<div class="card"><h3>Wo du schwimmst <small>90 Tage</small></h3>${[[25, '25-m-Bahn'], [50, '50-m-Bahn'], ['ow', 'Freiwasser']].map(([k, l]) => prow(l, wh[k] / whTot, `${de(wh[k] / 1000, 1)} km · ${Math.round(wh[k] / whTot * 100)} %`, k === 'ow' ? 'var(--fit)' : 'var(--swim)')).join('')}${wh.ow / whTot < .1 && ['volks', 'sprint', 'olympic', 'middle', 'full'].includes(RACE.fmt) ? '<span class="cap">Triathlon wird meist im Freiwasser geschwommen – ab und zu draußen (oder mit Neo) trainieren lohnt sich.</span>' : ''}</div>`;
  h += `<div class="card"><h3>Einheiten</h3><div class="list">${swims.slice(0, 8).map(actRow).join('')}</div></div>`;
  return h;
}

/* ---------- Schlaf & Stress ---------- */
function vWellness() {
  let h = header('Schlaf & Stress', true);
  if (!WELL.length) return h + `<div class="card">${empty('Keine Tageswerte', 'Schlaf, HRV und Ruhepuls kommen über intervals.icu automatisch von deiner Uhr.', '<button class="btn primary" data-act="nav:settings">Uhr verbinden</button>')}</div>`;
  const w = WELL[WELL.length - 1], l28 = WELL.slice(-28), base = mean(l28.map(x => x.hrv).filter(num)), W = cw(false), W2 = cw(true);
  h += `<div class="tiles">${w.sleep ? tile('Schlaf', hm(w.sleep.total), '', w.sleep.score ? `Score ${w.sleep.score}/100` : '', 'var(--sleep)', 'moon') : ''}${num(w.hrv) ? tile('HRV', Math.round(w.hrv), 'ms', base ? `Basis ${Math.round(base)} ms` : '', 'var(--good)') : ''}${num(w.rhr) ? tile('Ruhepuls', w.rhr, 'bpm', '', 'var(--bad)', 'heart') : ''}${num(w.stress) ? tile('Stress', w.stress, '', '', 'var(--warn)') : ''}${num(w.bb) ? tile('Body Battery', w.bb, '', '', 'var(--fit)', 'bolt') : ''}${num(w.vo2) ? tile('VO2 Max', de(w.vo2, 1), 'ml/kg/min', '', 'var(--run)', 'run', 'nav:progress') : ''}${num(w.steps) ? tile('Schritte', de(w.steps), '', '', 'var(--muted)') : ''}</div>`;
  const l14 = WELL.slice(-14).filter(x => x.sleep);
  if (l14.length) {
    const hasStages = l14.some(x => x.sleep.deep), stg = hasStages ? [['deep', 'Tief', 'var(--z2)'], ['light', 'Leicht', 'var(--fit)'], ['rem', 'REM', 'var(--sleep)'], ['awake', 'Wach', 'var(--z5)']] : [['total', 'Schlaf', 'var(--sleep)']];
    h += `<div class="card"><h3>Schlaf <small>${l14.length} Nächte</small></h3>${chart({ w: W, h: 200, x0: -.5, x1: l14.length - .5, y0: 0, y1: 10, yFmt: v => v + 'h', xt: l14.map((x, i) => ({ v: i, l: i % 2 ? '' : shortDate(x.date) })), layers: [(sx, sy) => l14.map((x, i) => { let y = 0; const bw = (sx(1) - sx(0)) * .6; return stg.map(([k, , c]) => { const hh = (x.sleep[k] || 0) / 3600, r = `<rect x="${sx(i) - bw / 2}" y="${sy(y + hh)}" width="${bw}" height="${sy(y) - sy(y + hh)}" fill="${c}"/>`; y += hh; return r; }).join(''); }).join('')] })}<div class="legend">${stg.map(([, n, c]) => `<span><i style="background:${c}"></i>${n}</span>`).join('')}</div></div>`;
  }
  const hp = l28.filter(x => num(x.hrv)).map(x => ({ x: x.date.getTime(), y: x.hrv })), rp = l28.filter(x => num(x.rhr)).map(x => ({ x: x.date.getTime(), y: x.rhr }));
  let row = '';
  if (hp.length > 2) { const x0 = hp[0].x, x1 = hp[hp.length - 1].x; row += `<div class="card"><h3>HRV-Trend <small>28 Tage</small></h3>${chart({ w: W2, h: 180, x0, x1, y0: Math.min(...hp.map(p => p.y)) - 4, y1: Math.max(...hp.map(p => p.y)) + 4, xt: dateTicks(x0, x1, 3, shortDate), layers: [line(hp, 'var(--good)', 2.2), (sx, sy) => `<line x1="${sx(x0)}" x2="${sx(x1)}" y1="${sy(base)}" y2="${sy(base)}" stroke="var(--muted)" stroke-dasharray="4 4"/><text class="axis" x="${sx(x1)}" y="${sy(base) - 6}" text-anchor="end">Ø ${Math.round(base)} ms</text>`] })}<span class="cap">Liegt die HRV mehrere Tage deutlich unter der Basis, braucht der Körper Erholung.</span></div>`; }
  if (rp.length > 2) { const x0 = rp[0].x, x1 = rp[rp.length - 1].x; row += `<div class="card"><h3>Ruhepuls</h3>${chart({ w: W2, h: 180, x0, x1, y0: Math.min(...rp.map(p => p.y)) - 3, y1: Math.max(...rp.map(p => p.y)) + 3, xt: dateTicks(x0, x1, 3, shortDate), layers: [line(rp, 'var(--bad)', 2.2), dots(rp, 'var(--bad)', 2)] })}<span class="cap">Ein steigender Ruhepuls über mehrere Tage kann auf Ermüdung oder Infekt hindeuten.</span></div>`; }
  if (row) h += `<div class="cols two">${row}</div>`;
  return h;
}

/* ---------- Wettkampf ---------- */
function vRace() {
  let h = header('Wettkampf');
  if (SET.cda == null) { const a = aeroTrend().slice(-5).map(x => x.cda); SET.cda = a.length ? Math.round(median(a) * 100) / 100 : .3; }
  const f = FMT[RACE.fmt], pr = racePredict(SET.cda, SET.wetsuit), days = Math.round((sod(RACE.date) - TODAY) / DAY), fp = fuelPlan(pr), W2 = cw(true);
  h += `<div class="card"><h3>${esc(RACE.name)} <small>${dayTitle(RACE.date)}${days >= 0 ? ` · in ${days} Tagen` : ''}</small></h3><div><div class="seg">${['volks', 'sprint', 'olympic'].map(k => `<button class="${RACE.fmt === k ? 'on' : ''}" data-act="rfmt:${k}">${FMT[k].name}</button>`).join('')}</div></div><span class="muted">Split-Prognose ${f.name} (${de(f.swim / 1000, 2).replace(/,?0+$/, '')} / ${de(f.bike / 1000)} / ${de(f.run / 1000, 1).replace(/,0$/, '')} km) · <button class="linkbtn" data-act="nav:settings">Saisonziel ändern</button></span><div class="bignum">${dur(pr.total)}</div>
    <div class="tiles">${tile('Schwimmen', dur(pr.swim), '', pv(pr.swimPace) + ' /100m', 'var(--swim)', 'swim')}${tile('Wechsel', dur(pr.t1 + pr.t2), '', 'T1 + T2', 'var(--muted)')}${tile('Rad', dur(pr.bike), '', `${Math.round(pr.power)} W · ${kmh(pr.v)}`, 'var(--bike)', 'bike')}${tile('Laufen', dur(pr.run), '', pv(pr.runPace) + ' /km', 'var(--run)', 'run')}</div>
    <label class="toggle"><input type="checkbox" id="wetsuit" data-change="wetsuit" ${SET.wetsuit ? 'checked' : ''}> Neoprenanzug</label>
    <label for="cda" class="cap fg">CdA (Aeroposition): <b>${de(SET.cda, 2)}</b> m²</label><input type="range" id="cda" min="0.20" max="0.40" step="0.01" value="${SET.cda}" data-change="cda">
    <button class="btn primary big" data-act="live-open">▶ Wettkampfmodus starten</button></div>`;
  h += `<div class="card"><h3>${icon('repeat', 16)} Wettkampf simulieren <small>Zielwerte aus der Prognose</small></h3>${simSessions(pr).map((x, i) => `<div class="ins"><span class="dot" style="background:${C[x.sport]}"></span><div style="display:flex;flex-direction:column;gap:6px;align-items:flex-start"><div><b>${esc(x.title)} · ${hm(x.min * 60)}</b><span>${x.d}</span></div><button class="btn small" data-act="simadd:${i}">In Kalender übernehmen</button></div></div>`).join('')}</div>`;
  const races = PLAN.filter(p => p.kind === 'race' && endOf(p) >= TODAY).sort((a, b) => a.date - b.date);
  h += `<div class="card"><h3>${icon('cal', 16)} Wettkampfkalender <small>${races.length ? races.filter(r => !r.tp).length ? races.filter(r => !r.tp).length + ' noch nicht in TrainingPeaks' : 'alle in TrainingPeaks' : ''}</small></h3>${races.length ? `<div class="list">${races.map(p => agendaRow(p, true)).join('')}</div>` : '<span class="muted">Noch keine Wettkämpfe eingetragen. Mit Priorität A/B/C planst du die Saison – A-Rennen werden zum Saisonziel.</span>'}<div><button class="btn primary" data-act="newk:race|${at(addDays(TODAY, 30), 9).getTime()}">${icon('plus', 14)} Wettkampf eintragen</button></div></div>`;
  let row = '';
  if (days > 3 && ACTS.length) {
    const tp = taperBest(), pts = tp.proj, x0 = pts[0].date.getTime(), x1 = pts[pts.length - 1].date.getTime();
    row += `<div class="card"><h3>Tapering-Analyse</h3><b style="font-size:16px">Optimal: ${tp.days} Tage Taper, Umfang −${Math.round(tp.red * 100)} %</b>${chart({ w: W2, h: 180, x0, x1, y0: Math.min(...pts.map(p => p.tsb)) - 5, y1: Math.max(...pts.map(p => p.ctl)) + 5, xt: dateTicks(x0, x1, 3, shortDate), layers: [(sx, sy) => `<line x1="${sx(x0)}" x2="${sx(x1)}" y1="${sy(0)}" y2="${sy(0)}" stroke="var(--faint)"/>`, line(pts.map(p => ({ x: p.date.getTime(), y: p.ctl })), 'var(--fit)', 2.4), line(pts.map(p => ({ x: p.date.getTime(), y: p.tsb })), 'var(--form)', 2)] })}<div class="legend"><span><i style="background:var(--fit)"></i>Fitness</span><span><i style="background:var(--form)"></i>Form</span></div>
    <div class="tiles">${tile('Form am Renntag', (tp.tsb >= 0 ? '+' : '') + Math.round(tp.tsb), '', 'Ziel +5 bis +25', 'var(--form)')}${tile('Fitnessverlust', de(tp.loss, 1), '%', 'gegenüber dem Höchstwert', 'var(--fit)')}</div></div>`;
  }
  row += `<div class="card"><h3>Race-Day-Fueling</h3><div class="tiles">${tile('Kohlenhydrate', fp.target.carbs, 'g/h', '', 'var(--bike)')}${tile('Flüssigkeit', Math.round(fp.target.fluid), 'ml/h', '', 'var(--swim)')}${tile('Natrium', Math.round(fp.target.na), 'mg/h', '', 'var(--muted)')}</div>
    <div class="tablewrap"><table><thead><tr><th>Minute</th><th>Disziplin</th><th>Was</th><th>KH</th></tr></thead><tbody>${fp.steps.map(s => `<tr><td>${s.m}</td><td style="color:${C[s.sport]}">${NAME[s.sport]}</td><td>${s.item.n}</td><td>${s.item.c} g</td></tr>`).join('')}</tbody></table></div><span class="cap">Richtwerte. Verträglichkeit in langen Trainingseinheiten testen.</span></div>`;
  return h + `<div class="cols two">${row}</div>`;
}

function vLive() {
  const L = S.live, pr = racePredict(SET.cda || .3, SET.wetsuit), names = ['Schwimmen', 'T1', 'Rad', 'T2', 'Laufen'], plan = [pr.swim, pr.t1, pr.bike, pr.t2, pr.run];
  const now = liveNow(), segEl = L.started ? now - L.segStart : 0, done = L.splits.length === 5;
  const proj = done ? L.splits.reduce((a, b) => a + b, 0) : liveProjection(pr, L.splits, segEl), delta = proj - pr.total;
  const elapsed = done ? L.splits.reduce((a, b) => a + b, 0) : now, eMin = Math.floor(elapsed / 60), next = fuelPlan(pr).steps.find(s => s.m >= eMin);
  const fl = L.fuel.reduce((a, f) => ({ c: a.c + f.c, fl: a.fl + f.fl }), { c: 0, fl: 0 });
  let h = header('Wettkampfmodus', true);
  h += `<div class="card" style="align-items:stretch"><div class="clock">${dur(elapsed)}</div><div style="text-align:center"><div class="muted">${done ? 'Zielzeit' : 'Prognose Ziel'}</div><div class="bignum" style="font-size:34px">${dur(proj)}</div><b class="${delta <= 0 ? 'good' : 'warnc'}">${delta <= 0 ? '−' : '+'}${dur(Math.abs(delta))} gegenüber Plan</b></div>
    ${!done ? `<button class="btn primary big" data-act="live-next" style="${L.started ? '' : 'background:var(--good)'}">${L.started ? names[L.splits.length] + ' beendet' : 'Start'}</button>` : ''}
    <label class="toggle"><input type="checkbox" id="speed" data-change="speed" ${S.speed > 1 ? 'checked' : ''}> Zeitraffer ×60 zum Ausprobieren</label></div>`;
  h += `<div class="card"><h3>Splits</h3>${names.map((n, i) => { const d = L.splits[i]; return `<div class="split ${i === L.splits.length && L.started ? 'cur' : ''}"><b>${n}</b><span class="cap">Plan ${dur(plan[i])}</span><span>${d != null ? `${dur(d)} <span class="${d <= plan[i] ? 'good' : 'warnc'}">${d <= plan[i] ? '−' : '+'}${dur(Math.abs(d - plan[i]))}</span>` : i === L.splits.length && L.started ? `<b class="acc">${dur(segEl)}</b>` : '–'}</span></div>`; }).join('')}</div>`;
  if (L.started && !done) h += `<div class="card"><h3>Fueling</h3>${next ? `<b class="${next.m - eMin <= 2 ? 'warnc' : ''}" style="font-size:16px">In ${next.m - eMin} min: ${next.item.n}</b>` : ''}<span class="cap">Bisher ${fl.c} g Kohlenhydrate (${Math.round(fl.c / Math.max(elapsed / 3600, .1))} g/h) · ${fl.fl} ml</span><div class="fuelgrid">${FUEL.map((f, i) => `<button class="btn" data-act="fuel:${i}">${f.n}</button>`).join('')}</div></div>`;
  return h;
}

/* ---------- Live-Puls (Bluetooth) ---------- */
function vPulse() {
  const b = BLE.st;
  let h = header('Live-Puls', true);
  if (!b.supported) {
    return h + `<div class="card">${empty('Bluetooth im Browser ist hier nicht verfügbar', isIOS() ? 'Apple erlaubt Bluetooth für Web-Apps auf iPhone und iPad nicht. Nutze den Live-Puls am PC (Chrome/Edge) oder Android – oder auf dem iPhone die kostenlose App „Bluefy“ als Browser.' : 'Öffne TriCoach in Chrome oder Edge, dort ist Web Bluetooth verfügbar.')}</div>` + pulseHelp();
  }
  h += `<div class="card" style="align-items:center;text-align:center"><div class="pulse ${b.connected ? 'on' : ''}" id="livehr">${b.connected ? (b.hr ?? '…') : '–'}</div><div class="muted" id="livezone">${b.connected && b.hr ? hrZones()[zoneOf(b.hr)][0] : 'nicht verbunden'}</div>
    <div class="row" style="flex-wrap:wrap;justify-content:center">${b.connected ? `<button class="btn" data-act="ble-off">Trennen</button>` : `<button class="btn primary" data-act="ble-on">${icon('watch', 16)} Uhr verbinden</button>`}
    ${b.connected ? (b.rec ? `<button class="btn primary" data-act="ble-stop">Speichern</button><button class="btn" data-act="ble-cancel">Verwerfen</button>` : `<select class="sel" id="blesport" data-change="blesport">${['run', 'bike', 'swim', 'other'].map(s => `<option value="${s}" ${b.sport === s ? 'selected' : ''}>${NAME[s]}</option>`).join('')}</select><button class="btn primary" data-act="ble-rec">● Aufzeichnen</button>`) : ''}</div>
    ${b.rec ? `<span class="cap" id="recinfo">Aufnahme läuft · ${dur((Date.now() - b.recStart) / 1000)}</span>` : ''}${b.err ? `<span class="cap warnc">${esc(b.err)}</span>` : ''}</div>
    <div class="card"><h3>Verlauf <small>letzte 15 min</small></h3><div id="hrchart">${hrChart()}</div></div>`;
  return h + pulseHelp();
}
function hrChart() {
  const pts = BLE.st.hist.map(p => ({ x: p.t, y: p.hr }));
  if (pts.length < 2) return '<span class="muted">Noch keine Messwerte.</span>';
  const now = Date.now();
  return chart({ w: cw(false), h: 180, x0: now - 15 * 60000, x1: now, y0: Math.min(...pts.map(p => p.y)) - 5, y1: Math.max(...pts.map(p => p.y)) + 5, xt: [{ v: now - 15 * 60000, l: '−15 min' }, { v: now - 7.5 * 60000, l: '−7,5 min' }, { v: now, l: 'jetzt' }], layers: [line(pts, 'var(--bad)', 2)] });
}
function renderLiveHr() {
  const el = document.getElementById('livehr'); if (!el) return;
  el.textContent = BLE.st.hr ?? '…';
  const z = document.getElementById('livezone'); if (z && BLE.st.hr) z.textContent = hrZones()[zoneOf(BLE.st.hr)][0];
  const c = document.getElementById('hrchart'); if (c) c.innerHTML = hrChart();
  const r = document.getElementById('recinfo'); if (r) r.textContent = `Aufnahme läuft · ${dur((Date.now() - BLE.st.recStart) / 1000)}`;
}
const pulseHelp = () => `<div class="card"><h3>So sendet die Forerunner 265 den Puls</h3><ol class="steps"><li>Auf der Uhr: <b>Menü (lange UP) → Einstellungen → Sensoren und Zubehör → Pulsmesser am Handgelenk → HF übertragen</b>. Alternativ während einer Aktivität im Menü „HF übertragen“.</li><li>Hier auf <b>Uhr verbinden</b> tippen und die Forerunner in der Liste wählen.</li><li>Fertig: Puls und Zone laufen live mit, mit „Aufzeichnen“ speicherst du die Einheit.</li></ol><span class="cap">Hinweis: Per Bluetooth gibt die Uhr nur den Live-Puls frei. Komplette Einheiten (GPS, Pace, Watt, SWOLF) kommen automatisch über den Sync oder per USB-Import.</span></div>`;

/* ---------- Karte ---------- */
function vMap() {
  let h = header('Karte', true);
  const acts = ACTS.filter(a => a.start >= SINCE(S.mapDays) && (S.mapSport === 'all' || a.sport === S.mapSport) && a.samples?.some(x => x.lat));
  h += `<div class="row" style="flex-wrap:wrap"><div class="seg">${[['all', 'Alle'], ['bike', 'Rad'], ['run', 'Laufen'], ['swim', 'Schwimmen']].map(([k, l]) => `<button class="${S.mapSport === k ? 'on' : ''}" data-act="mapsport:${k}">${l}</button>`).join('')}</div><div class="seg">${[[30, '30 T'], [90, '90 T'], [365, '1 Jahr']].map(([k, l]) => `<button class="${S.mapDays === k ? 'on' : ''}" data-act="mapdays:${k}">${l}</button>`).join('')}</div></div>`;
  if (!acts.length) return h + `<div class="card">${empty('Keine GPS-Strecken', 'Im gewählten Zeitraum gibt es keine Einheiten mit GPS.')}</div>`;
  const tracks = acts.map(a => { const s = a.samples.filter(x => x.lat), st = Math.max(1, Math.floor(s.length / 250)); return { pts: s.filter((_, i) => i % st === 0).map(x => [x.lat, x.lon]), color: C[a.sport], opacity: .35, width: 3 }; });
  return h + `<div class="card"><h3>Heatmap <small>${acts.length} Einheiten</small></h3>${trackSvg(tracks, cw(false), 420)}<span class="cap">Häufig gefahrene und gelaufene Strecken leuchten stärker.</span></div>`;
}

/* ---------- Aktivität ---------- */
function vActivity() {
  const a = byId(S.act), W = cw(false); if (!a) return header('Nicht gefunden', true);
  const sp = a.dur ? a.dist / a.dur : 0, paceVal = a.sport === 'bike' ? de(sp * 3.6, 1) : pv(a.sport === 'swim' ? 100 / sp : 1000 / sp), paceUnit = a.sport === 'bike' ? 'km/h' : a.sport === 'swim' ? '/100m' : '/km';
  let h = header(esc(a.name), true) + `<div class="row" style="flex-wrap:wrap;justify-content:space-between"><span class="muted">${dayTitle(a.start)}, ${time(a.start)} Uhr · ${a.source === 'manual' ? 'eingetragen' : a.source === 'demo' ? 'Demo' : 'von der Uhr'}${swimWhere(a) ? ' · ' + whereTxt(swimWhere(a)) : ''}${a.art && !a.name.includes(a.art) ? ' · ' + esc(a.art) : ''}</span><div class="row" style="flex-wrap:wrap"><button class="btn small" data-act="editact:${a.id}">${icon('edit', 14)} Bearbeiten</button><button class="btn small ${a.tp ? '' : 'primary'}" data-act="tpact:${a.id}">${ICON.tp} ${a.tp ? 'In TrainingPeaks ✓' : 'An TrainingPeaks'}</button></div></div>`;
  if (a.notes) h += `<div class="card"><h3>Notizen</h3><span class="fg" style="white-space:pre-wrap">${esc(a.notes)}</span></div>`;
  if (a.ex?.length) h += `<div class="card"><h3>${icon('strength', 16, 'var(--str)')} Übungen</h3><div class="tablewrap"><table><thead><tr><th>Übung</th><th>Sätze</th><th>Wdh/Zeit</th><th>Gewicht</th></tr></thead><tbody>${a.ex.map(x => `<tr><td>${esc(x.n)}</td><td>${x.s ?? '–'}</td><td>${esc(x.r || '–')}</td><td>${x.w ? de(x.w, x.w % 1 ? 1 : 0) + ' kg' : '–'}</td></tr>`).join('')}</tbody></table></div></div>`;
  h += `<div class="tiles">${tile('Dauer', dur(a.dur), '', '', C[a.sport] || C.other, 'timer')}${a.dist ? tile('Distanz', de(a.dist / 1000, 2), 'km', a.sport === 'swim' ? de(a.dist) + ' m' : '', C[a.sport], a.sport) : ''}${a.rpe ? tile('Anstrengung', a.rpe, '/10', RPE_TXT[a.rpe], 'var(--warn)') : ''}${a.kcal ? tile('Kalorien', de(a.kcal), 'kcal', a.source === 'manual' ? 'geschätzt oder eingetragen' : '', 'var(--muted)') : ''}${a.dist ? tile(a.sport === 'bike' ? 'Geschwindigkeit' : 'Pace', paceVal, paceUnit, '', C[a.sport]) : ''}${num(a.avgHr) && !hrSummary(a)?.hasCurve ? tile('Ø Herzfrequenz', Math.round(a.avgHr), 'bpm', num(a.maxHr) ? 'max ' + Math.round(a.maxHr) : '', 'var(--bad)', 'heart') : ''}${tile('TSS', Math.round(a.tss || 0), '', num(a.te) ? 'Aerober Trainingseffekt ' + de(a.te, 1) : '', 'var(--bike)')}${a.elev > 1 ? tile('Höhenmeter', de(a.elev), 'm', '', 'var(--muted)') : ''}</div>`;
  const hs = hrSummary(a);
  if (hs?.hasCurve) {
    const tot = hs.zones.reduce((x, y) => x + y, 0) || 1, dom = hs.zones.indexOf(Math.max(...hs.zones));
    h += `<div class="card"><h3>${icon('heart', 16, 'var(--bad)')} Herzfrequenz-Auswertung</h3><div class="tiles">${tile('Ø Herzfrequenz', Math.round(hs.avg), 'bpm', `Minimum ${Math.round(hs.min)}`, 'var(--bad)', 'heart')}${tile('Max. Herzfrequenz', Math.round(hs.max), 'bpm', `${Math.round(hs.max / P.maxHr * 100)} % deiner max. HF`, 'var(--bad)', 'heart')}${tile('Hauptzone', hs.zoneNames[dom][0].split(' ')[0], '', `${hs.zoneNames[dom][0].split(' ').slice(1).join(' ')} · ${Math.round(hs.zones[dom] / tot * 100)} %`, zc(dom))}${tile('Über Schwelle', hm(hs.above), '', `ab ${P.lthr} bpm`, 'var(--z5)')}${num(hs.drift) ? tile('HF-Drift', sgn(hs.drift, 1), 'bpm', '2. vs. 1. Hälfte', Math.abs(hs.drift) > 8 ? 'var(--warn)' : 'var(--good)') : ''}${num(hs.dec) && a.sport !== 'swim' ? tile('Entkopplung', sgn(hs.dec, 1), '%', hs.dec > 5 ? 'Tempo:HF driftet' : 'stabil', hs.dec > 5 ? 'var(--warn)' : 'var(--good)') : ''}</div>${zoneBar(hs.zones)}<div class="legend">${hs.zoneNames.map((z, i) => `<span><i style="background:${zc(i)}"></i>${z[0].split(' ')[0]} ${hm(hs.zones[i])}</span>`).join('')}</div></div>`;
  } else if (a.partial) h += `<div class="card"><span class="cap">Die Herzfrequenz-Kurve dieser Einheit wird beim nächsten Sync automatisch nachgeladen.</span></div>`;
  const gps = (a.samples || []).filter(x => x.lat);
  if (gps.length > 5) h += `<div class="card"><h3>Strecke</h3>${trackSvg([{ pts: gps.map(x => [x.lat, x.lon]), color: C[a.sport] }], W, 240)}</div>`;
  const has = k => (a.samples || []).some(x => num(x[k]));
  const metrics = [['hr', 'HF', 'var(--bad)'], ['v', a.sport === 'bike' ? 'km/h' : 'Pace', C[a.sport]], ['p', 'Leistung', C[a.sport]], ['cad', 'Kadenz', C[a.sport]], ['alt', 'Höhe', 'var(--muted)']].filter(m => has(m[0]) && !(a.sport === 'swim' && m[0] === 'alt'));
  if (metrics.length) {
    const m = metrics.find(x => x[0] === S.metric) || metrics[0], step = Math.max(1, Math.floor(a.samples.length / 300));
    const val = s => m[0] === 'v' ? (s.v > .2 ? (a.sport === 'bike' ? s.v * 3.6 : a.sport === 'swim' ? 100 / s.v : 1000 / s.v) : null) : s[m[0]];
    const pts = a.samples.filter((_, i) => i % step === 0).map(s => ({ x: s.t / 60, y: val(s) })).filter(p => num(p.y));
    if (pts.length > 1) {
      let ys = pts.map(p => p.y).sort((x, y) => x - y); const lo = ys[Math.floor(ys.length * .01)], hi = ys[Math.ceil(ys.length * .99) - 1], padY = (hi - lo) * .08 || 1, inv = m[0] === 'v' && a.sport !== 'bike';
      const cl = pts.map(p => ({ x: p.x, y: clamp(p.y, lo - padY, hi + padY) }));
      h += `<div class="card"><h3>Verlauf</h3><div><div class="seg">${metrics.map(([k, l]) => `<button class="${m[0] === k ? 'on' : ''}" data-act="metric:${k}">${l}</button>`).join('')}</div></div>${chart({ w: W, h: 210, x0: 0, x1: pts[pts.length - 1].x, y0: inv ? hi + padY : lo - padY, y1: inv ? lo - padY : hi + padY, yt: ticks(lo - padY, hi + padY), yFmt: inv ? pv : v => de(v, v % 1 ? 1 : 0), xt: ticks(0, pts[pts.length - 1].x, 6).map(v => ({ v, l: v + ' min' })), layers: [line(cl, m[2], 1.6)] })}`;
      if (m[0] === 'hr') { const z = hrZones(), tz = timeInZones([a], z, 'hr'), tot = tz.reduce((x, y) => x + y, 0) || 1; h += z.map((zz, i) => prow(zz[0], tz[i] / tot, hm(tz[i]), zc(i))).join(''); }
      h += `</div>`;
    }
  }
  if (a.run && (num(a.run.gct) || num(a.run.cad))) h += `<div class="card"><h3>Laufdynamik</h3><div class="tiles">${num(a.run.cad) ? tile('Kadenz', de(a.run.cad), 'spm', '', 'var(--run)') : ''}${num(a.run.stride) ? tile('Schrittlänge', de(a.run.stride, 2), 'm', '', 'var(--run)') : ''}${num(a.run.gct) ? tile('Bodenkontakt', de(a.run.gct), 'ms', '', 'var(--run)') : ''}${num(a.run.vo) ? tile('Vert. Bewegung', de(a.run.vo, 1), 'cm', '', 'var(--run)') : ''}</div></div>`;
  if (a.bike?.np) h += `<div class="card"><h3>Leistung</h3><div class="tiles">${num(a.bike.ap) ? tile('Ø Leistung', Math.round(a.bike.ap), 'W', '', 'var(--bike)', 'bolt') : ''}${tile('Normalized Power', Math.round(a.bike.np), 'W', 'IF ' + de(a.bike.np / P.ftp, 2), 'var(--bike)', 'bolt')}${num(a.bike.ap) ? tile('Variability Index', de(a.bike.np / a.bike.ap, 2), '', '', 'var(--bike)') : ''}${num(a.bike.cad) ? tile('Kadenz', Math.round(a.bike.cad), 'rpm', '', 'var(--bike)') : ''}</div></div>`;
  if (a.lengths?.some(l => l.strokes > 0)) {
    const ls = a.lengths.filter(l => l.strokes > 0).map(l => ({ x: l.i + 1, y: Math.round(l.dur) + l.strokes })), y0 = Math.min(...ls.map(l => l.y)) - 3;
    h += `<div class="card"><h3>Bahnen &amp; SWOLF</h3>${chart({ w: W, h: 170, x0: 0, x1: a.lengths.length + 1, y0, y1: Math.max(...ls.map(l => l.y)) + 2, xt: ticks(1, a.lengths.length, 6).map(v => ({ v, l: 'Bahn ' + v })), layers: [(sx, sy) => ls.map(l => `<rect x="${sx(l.x) - Math.max(1, (sx(1) - sx(0)) * .35)}" y="${sy(l.y)}" width="${Math.max(2, (sx(1) - sx(0)) * .7)}" height="${sy(y0) - sy(l.y)}" fill="var(--swim)"/>`).join('')] })}<div class="legend"><span>Ø SWOLF ${de(a.swim?.swolf, 1)}</span><span>${de(a.swim?.rate)} Züge/min</span><span>${de(a.swim?.dps, 2)} m/Zug</span></div></div>`;
  }
  if (a.laps?.length > 1) h += `<div class="card"><h3>Runden</h3><div class="tablewrap"><table><thead><tr><th>#</th><th>Zeit</th><th>Distanz</th><th>${a.sport === 'bike' ? 'km/h' : 'Pace'}</th><th>HF</th>${a.sport === 'bike' ? '<th>Watt</th>' : ''}</tr></thead><tbody>${a.laps.map((l, i) => `<tr><td style="color:${l.interval ? C[a.sport] : 'inherit'}">${i + 1}</td><td>${dur(l.dur)}</td><td>${a.sport === 'swim' ? de(l.dist) + ' m' : km(l.dist, 2)}</td><td>${a.sport === 'bike' ? kmh(l.v) : a.sport === 'swim' ? spaceS(l.v) : pace(l.v)}</td><td>${num(l.hr) ? Math.round(l.hr) : '–'}</td>${a.sport === 'bike' ? `<td>${num(l.p) ? Math.round(l.p) : '–'}</td>` : ''}</tr>`).join('')}</tbody></table></div></div>`;
  if (a.source !== 'demo') h += `<div><button class="btn small danger" data-act="delact:${a.id}">Einheit löschen</button></div>`;
  return h;
}
