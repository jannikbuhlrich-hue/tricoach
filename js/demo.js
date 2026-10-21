'use strict';
/* TriCoach – Demo-Daten (deterministisch, 150 Tage Triathlon-Training) */

const Demo = (() => {
  const CENTER = [53.0793, 8.8017];
  const loop = (d, R) => { const a = d / R, w = 1 + .08 * Math.sin(a * 5); return [CENTER[0] + R * (Math.cos(a) - 1) * w / 111320, CENTER[1] + R * Math.sin(a) * w / (111320 * Math.cos(CENTER[0] * Math.PI / 180))]; };

  function kmLaps(s) {
    const laps = []; let i0 = 0, mark = 1000;
    s.forEach((x, i) => {
      if (x.d >= mark || i === s.length - 1) {
        const t0 = i0 ? s[i0 - 1].t : 0, d0 = i0 ? s[i0 - 1].d : 0, sl = s.slice(i0, i + 1);
        laps.push({ dur: x.t - t0, dist: x.d - d0, hr: mean(sl.map(y => y.hr)), v: (x.d - d0) / (x.t - t0), interval: false });
        i0 = i + 1; mark += 1000;
      }
    });
    return laps;
  }

  function run(day, hour, kind, minutes, fit, r) {
    const start = new Date(day.getTime() + (hour * 60 + Math.floor(r() * 30)) * 60000);
    const thr = thrSpeed() * fit; let segs, name;
    if (kind === 'easy') { segs = [[minutes * 60, .78, 0]]; name = 'Lockerer Lauf'; }
    else if (kind === 'long') { segs = [[minutes * 60, .8, 0]]; name = 'Langer Lauf'; }
    else if (kind === 'int') { segs = [[900, .75, 0]]; for (let i = 0; i < 6; i++) segs.push([240, 1.03, 1], [120, .6, 0]); segs.push([Math.max(5, minutes - 51) * 60, .72, 0]); name = 'Intervalle 6×4 min'; }
    else { segs = [[900, .75, 0], [5000 / (thr * 1.06), 1.06, 1], [600, .65, 0]]; name = '5-km-Test'; }
    const s = [], laps = []; let t = 0, d = 0, hr = P.rhr + 35;
    for (const [len, inten, isInt] of segs) {
      const t0 = t, d0 = d, hrs = [];
      for (let k = 0; k < Math.round(len / DT); k++) {
        const v = thr * inten * (1 + noise(r, .03)); d += v * DT; t += DT;
        const i = v / thr, target = P.rhr + (P.lthr - P.rhr) * i ** 1.8 + t / 3600 * 4;
        hr += (target - hr) * .15; const cad = 162 + 18 * i + noise(r, 2), ll = loop(d, 1600);
        s.push({ t, hr: Math.round(hr + noise(r, 1.5)), v, p: Math.round(1.04 * P.weight * v + noise(r, 8)), cad, alt: 5 + 3 * Math.sin(d / 1600 * 3), d, lat: ll[0], lon: ll[1], gct: 330 - 30 * v + noise(r, 4), vo: 8.6 + noise(r, .3), stride: v * 60 / cad });
        hrs.push(hr);
      }
      if (kind === 'int' || kind === 'test') laps.push({ dur: t - t0, dist: d - d0, hr: mean(hrs), v: (d - d0) / (t - t0), interval: !!isInt });
    }
    return finalize({ id: 'demo-run-' + start.getTime(), source: 'demo', sport: 'run', name, start, dur: t, dist: d, samples: s, laps: (kind === 'easy' || kind === 'long') ? kmLaps(s) : laps, elev: 18, te: kind === 'int' ? 3.4 : kind === 'long' ? 3.1 : kind === 'test' ? 3.9 : 2.4 });
  }

  function bike(day, hour, kind, minutes, fit, prog, r) {
    const start = new Date(day.getTime() + (hour * 60 + Math.floor(r() * 30)) * 60000);
    const ftp = P.ftp * fit, cda = .335 - .03 * prog, M = sysMass(); let segs, name;
    if (kind === 'end') { segs = [[minutes * 60, .66, 0]]; name = 'Grundlage Rad'; }
    else if (kind === 'ss') { segs = [[900, .6, 0]]; for (let i = 0; i < 3; i++) { segs.push([900, .9, 1]); if (i < 2) segs.push([300, .55, 0]); } segs.push([Math.max(5, minutes - 70) * 60, .6, 0]); name = 'Sweet Spot 3×15 min'; }
    else { segs = [[1200, .6, 0], [1200, 1.05, 1], [900, .55, 0]]; name = 'FTP-Test 20 min'; }
    const s = [], laps = []; let t = 0, d = 0, hr = P.rhr + 30; const bl = P.lthr - 5;
    for (const [len, inten, isInt] of segs) {
      const t0 = t, d0 = d, hrs = [], ps = [];
      for (let k = 0; k < Math.round(len / DT); k++) {
        const p = Math.max(0, ftp * inten * (1 + noise(r, .07))), g = .005 * Math.sin(d / 3000), v = aeroV(p, cda * (1 + noise(r, .02)), M, g);
        d += v * DT; t += DT;
        hr += (P.rhr + (bl - P.rhr) * (p / ftp) ** 1.5 + t / 3600 * 3 - hr) * .12;
        const ll = loop(d, 6000);
        s.push({ t, hr: Math.round(hr + noise(r, 1.5)), v, p: Math.round(p), cad: Math.round((isInt ? 92 : 87) + noise(r, 3)), alt: 8 + 10 * Math.sin(d / 3000), d, lat: ll[0], lon: ll[1] });
        hrs.push(hr); ps.push(p);
      }
      laps.push({ dur: t - t0, dist: d - d0, hr: mean(hrs), v: (d - d0) / (t - t0), p: mean(ps), interval: !!isInt });
    }
    return finalize({ id: 'demo-bike-' + start.getTime(), source: 'demo', sport: 'bike', name, start, dur: t, dist: d, samples: s, laps, te: kind === 'end' ? 3.0 : 3.6 });
  }

  function swim(day, hour, kind, meters, fit, prog, r) {
    const start = new Date(day.getTime() + (hour * 60 + Math.floor(r() * 20)) * 60000);
    const n = Math.max(8, Math.floor(meters / 25)), css = cssSpeed() * fit, base = 17.5 - 2 * prog;
    const name = kind === 'end' ? 'Ausdauer 4×600' : kind === 'css' ? 'CSS-Serie 10×100' : 'Technik + Drills';
    const lengths = [], laps = []; let t = 0, hr = P.rhr + 30;
    for (let i = 0; i < n; i++) {
      let f = kind === 'end' ? .9 : kind === 'css' ? (i < 16 ? .86 : .985) : .82, type = 'free';
      if (kind === 'tech' && i % 4 === 3) { type = 'drill'; f = .7; }
      if (i > n * 3 / 4) f *= .98;
      const v = css * f * (1 + noise(r, .03)), dd = 25 / v;
      const strokes = type === 'drill' ? 0 : Math.round(base + noise(r, 1) + (f - .9) * 12);
      hr += (P.rhr + 95 * f - hr) * .25;
      lengths.push({ i, dur: dd, strokes, type, hr: Math.round(hr + noise(r, 3)), t: t + dd });
      t += dd;
      if ((i + 1) % 4 === 0) { const l4 = lengths.slice(-4), ld = l4.reduce((a, b) => a + b.dur, 0); laps.push({ dur: ld, dist: 100, hr: mean(l4.map(x => x.hr)), v: 100 / ld, interval: kind === 'css' && i >= 16 }); t += kind === 'css' ? 15 : 10; }
    }
    return finalize({ id: 'demo-swim-' + start.getTime(), source: 'demo', sport: 'swim', name, start, dur: t, dist: n * 25, laps, lengths, swim: { pool: 25 }, samples: lengths.map(l => ({ t: l.t, hr: l.hr, v: 25 / l.dur, cad: l.strokes / l.dur * 60 })), te: kind === 'css' ? 3.3 : 2.6 });
  }

  function activities(days = 150) {
    const out = [], today = sod(new Date());
    for (let back = 0; back < days; back++) {
      const day = addDays(today, -back), dn = Math.floor((day.getTime() + DAY / 2) / DAY), r = rng(dn * 7919);
      const prog = 1 - back / days, fit = .94 + .06 * prog;
      const rec = Math.floor(dn / 7) % 4 === 3, test = Math.floor(dn / 7) % 6 === 0, vol = rec ? .65 : 1;
      if (!test && r() < .08) continue;
      switch (day.getDay()) {
        case 1: out.push(swim(day, 7, 'end', 2400 * vol, fit, prog, r)); break;
        case 2: out.push(run(day, 18, test ? 'test' : 'int', 62, fit, r)); break;
        case 3: out.push(bike(day, 18, test ? 'ftp' : 'ss', 80 * vol, fit, prog, r)); break;
        case 4: out.push(swim(day, 7, 'css', 2800 * vol, fit, prog, r)); out.push(run(day, 18, 'easy', 45 * vol, fit, r)); break;
        case 5: out.push(swim(day, 7, 'tech', 2000, fit, prog, r)); break;
        case 6: out.push(bike(day, 9, 'end', (150 + r() * 60) * vol, fit, prog, r)); break;
        default: out.push(run(day, 9, 'long', (75 + r() * 30) * vol, fit, r));
      }
    }
    return out.filter(a => a.start.getTime() + a.dur * 1000 <= Date.now());
  }

  function wellness(days = 150) {
    const out = [], today = sod(new Date());
    for (let back = days - 1; back >= 0; back--) {
      const day = addDays(today, -back), dn = Math.floor((day.getTime() + DAY / 2) / DAY), r = rng(dn * 104729), prog = 1 - back / days;
      const hrv = 62 + 8 * prog + noise(r, 8), total = (7.2 + noise(r, .7)) * 3600;
      out.push({
        date: day, hrv, rhr: P.rhr + 2 - Math.round(prog * 2) + Math.round(noise(r, 2)),
        sleep: { total, deep: total * .18, light: total * .55, rem: total * .22, awake: total * .05, score: Math.round(75 + noise(r, 13)) },
        stress: Math.round(30 + noise(r, 9)), bb: Math.round(85 + noise(r, 12)),
        readiness: Math.round(clamp(45 + (hrv - 60) * 2 + noise(r, 12), 5, 100)),
        vo2: Math.round((55 + 3 * prog) * 10) / 10, steps: Math.round(11000 + noise(r, 3000))
      });
    }
    return out;
  }
  return { activities, wellness };
})();
