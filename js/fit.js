'use strict';
/* TriCoach – FIT-Decoder (Garmin-Aktivitätsdateien) – liest Sessions, Runden, Messpunkte und Schwimmbahnen.
   Multisport-Dateien (Triathlon) werden in einzelne Aktivitäten pro Disziplin aufgeteilt. */

const FIT = (() => {
  const EPOCH = 631065600; // 1989-12-31 UTC
  const SIZE = { 0: 1, 1: 1, 2: 1, 3: 2, 4: 2, 5: 4, 6: 4, 7: 1, 8: 4, 9: 8, 10: 1, 11: 2, 12: 4, 13: 1, 14: 8, 15: 8, 16: 8 };

  async function maybeGunzip(buf) {
    const b = new Uint8Array(buf);
    if (b[0] === 0x1f && b[1] === 0x8b) {
      const ds = new DecompressionStream('gzip');
      return await new Response(new Blob([b]).stream().pipeThrough(ds)).arrayBuffer();
    }
    return buf;
  }

  function isFit(buf) {
    const b = new Uint8Array(buf);
    return b.length > 12 && String.fromCharCode(b[8], b[9], b[10], b[11]) === '.FIT';
  }

  function decode(buf) {
    const b = new Uint8Array(buf), dv = new DataView(buf);
    if (!isFit(buf)) throw new Error('Keine FIT-Datei');
    const hs = b[0], end = Math.min(b.length, hs + dv.getUint32(4, true));
    const defs = {}, msgs = []; let i = hs, lastTs = 0;

    const read = (def) => {
      const v = {};
      for (const f of def.fields) {
        if (i + f.size > end) throw new Error('Datei abgeschnitten');
        const bt = f.type & 0x1f, sz = SIZE[bt];
        if (sz === f.size && bt !== 7 && bt !== 8 && bt !== 9 && bt < 14) {
          const le = !def.big; let x;
          switch (bt) {
            case 0: case 2: case 10: case 13: x = dv.getUint8(i); if (x === 0xff || (bt === 10 && x === 0)) x = null; break;
            case 1: x = dv.getInt8(i); if (x === 0x7f) x = null; break;
            case 3: x = dv.getInt16(i, le); if (x === 0x7fff) x = null; break;
            case 4: case 11: x = dv.getUint16(i, le); if (x === 0xffff || (bt === 11 && x === 0)) x = null; break;
            case 5: x = dv.getInt32(i, le); if (x === 0x7fffffff) x = null; break;
            case 6: case 12: x = dv.getUint32(i, le); if (x === 0xffffffff || (bt === 12 && x === 0)) x = null; break;
          }
          if (x != null) v[f.num] = x;
        }
        i += f.size;
      }
      i += def.dev;
      return { g: def.g, v };
    };

    while (i < end) {
      const h = b[i++];
      if (h & 0x80) { // komprimierter Zeitstempel
        const def = defs[(h >> 5) & 3]; if (!def) throw new Error('Definition fehlt');
        const m = read(def), off = h & 0x1f;
        let ts = (lastTs & 0xffffffe0) + off; if (off < (lastTs & 0x1f)) ts += 0x20;
        lastTs = ts; m.v[253] = ts; msgs.push(m);
      } else if (h & 0x40) { // Definition
        const big = b[i + 1] === 1, g = big ? dv.getUint16(i + 2, false) : dv.getUint16(i + 2, true), n = b[i + 4]; i += 5;
        const fields = []; for (let k = 0; k < n; k++) { fields.push({ num: b[i], size: b[i + 1], type: b[i + 2] }); i += 3; }
        let dev = 0; if (h & 0x20) { const dn = b[i++]; for (let k = 0; k < dn; k++) { dev += b[i + 1]; i += 3; } }
        defs[h & 0x0f] = { g, big, fields, dev };
      } else {
        const def = defs[h & 0x0f]; if (!def) throw new Error('Definition fehlt');
        const m = read(def); if (m.v[253] != null) lastTs = m.v[253]; msgs.push(m);
      }
    }
    return msgs;
  }

  const date = ts => new Date((ts + EPOCH) * 1000);
  const SPORT = { 1: 'run', 2: 'bike', 5: 'swim', 11: 'run' };
  const STROKE = { 0: 'free', 1: 'back', 2: 'breast', 3: 'fly', 4: 'drill', 5: 'mixed' };
  const NAMES = { run: 'Lauf', bike: 'Radfahrt', swim: 'Schwimmen', other: 'Aktivität' };

  /* FIT-Messages → Aktivitäten (eine pro Session) */
  function toActivities(msgs, fileId, source = 'fit') {
    const sessions = msgs.filter(m => m.g === 18 && m.v[2] != null);
    const records = msgs.filter(m => m.g === 20 && m.v[253] != null);
    const laps = msgs.filter(m => m.g === 19 && m.v[2] != null);
    const lengths = msgs.filter(m => m.g === 101 && m.v[2] != null);
    return sessions.map((s, idx) => {
      const sv = s.v, t0 = sv[2], durS = (sv[7] ?? sv[8] ?? 0) / 1000, t1 = t0 + durS + 1;
      const sport = SPORT[sv[5]] || 'other';
      const inRange = m => m.v[253] >= t0 && m.v[253] <= t1;
      const recs = records.filter(inRange);

      // auf 10-s-Raster mitteln
      const bins = new Map();
      for (const r of recs) {
        const v = r.v, k = Math.floor((v[253] - t0) / DT);
        const o = bins.get(k) || bins.set(k, { n: {}, s: {} }).get(k);
        const put = (key, val) => { if (val == null || !isFinite(val)) return; o.s[key] = (o.s[key] || 0) + val; o.n[key] = (o.n[key] || 0) + 1; };
        put('hr', v[3]); put('p', v[7]);
        const sp = v[73] ?? v[6]; if (sp != null) put('v', sp / 1000);
        let cad = v[4]; if (cad != null && sport === 'run') cad *= 2; put('cad', cad);
        const alt = v[78] ?? v[2]; if (alt != null) put('alt', alt / 5 - 500);
        put('gct', v[41] != null ? v[41] / 10 : null); put('vo', v[39] != null ? v[39] / 100 : null); put('stride', v[85] != null ? v[85] / 10000 : null);
        if (v[5] != null) o.d = v[5] / 100;
        if (v[0] != null && v[1] != null) { o.lat = v[0] * 180 / 2147483648; o.lon = v[1] * 180 / 2147483648; }
      }
      const samples = [...bins.entries()].sort((a, b) => a[0] - b[0]).map(([k, o]) => {
        const x = { t: (k + 1) * DT }; for (const key in o.s) x[key] = o.s[key] / o.n[key];
        if (o.d != null) x.d = o.d; if (o.lat != null) { x.lat = o.lat; x.lon = o.lon; } return x;
      });
      // fehlende Geschwindigkeit aus Distanz ableiten
      for (let k = 1; k < samples.length; k++) if (samples[k].v == null && samples[k].d != null && samples[k - 1].d != null) samples[k].v = (samples[k].d - samples[k - 1].d) / (samples[k].t - samples[k - 1].t);

      const sl = laps.filter(l => l.v[2] >= t0 - 1 && l.v[2] <= t1);
      const hasRest = sl.some(l => [1, 4].includes(l.v[23]));
      const lapList = sl.map(l => {
        const d = (l.v[8] ?? l.v[7] ?? 0) / 1000, dist = (l.v[9] ?? 0) / 100, sp = l.v[110] ?? l.v[13];
        return { dur: d, dist, hr: l.v[15] ?? null, v: sp != null ? sp / 1000 : (d ? dist / d : 0), p: l.v[19] ?? null, interval: l.v[23] === 5 || (l.v[23] === 0 && hasRest) };
      });

      const act = {
        id: `${source}-${fileId}${sessions.length > 1 ? '-' + idx : ''}`, source, sport, name: NAMES[sport],
        start: date(t0), dur: durS, dist: (sv[9] ?? 0) / 100,
        avgHr: sv[16] ?? null, maxHr: sv[17] ?? null, elev: sv[22] ?? null,
        te: sv[24] != null ? sv[24] / 10 : null, samples, laps: lapList
      };
      if (sport === 'bike' && sv[34]) act.bike = { np: sv[34], ap: sv[20] ?? null, cad: sv[18] ?? null };
      if (sport === 'swim') {
        const pool = sv[44] != null ? sv[44] / 100 : null;
        const ls = lengths.filter(l => l.v[2] >= t0 - 1 && l.v[2] <= t1 && (l.v[12] ?? 1) === 1).map((l, i) => {
          const d = (l.v[4] ?? 0) / 1000; return { i, dur: d, strokes: l.v[5] ?? 0, type: STROKE[l.v[7]] || 'mixed', t: date(l.v[2]).getTime() / 1000 - t0 + d };
        });
        act.lengths = ls; act.swim = { pool: pool || 25 };
        if (!samples.some(x => x.v) && ls.length && pool) act.samples = ls.map(l => ({ t: l.t, v: pool / l.dur, cad: l.strokes / l.dur * 60, hr: samples.find(x => x.t >= l.t)?.hr }));
        if (!pool) act.name = 'Freiwasser';
      }
      return finalize(act);
    }).filter(a => a.dur > 60);
  }

  async function parse(buf, fileId, source) {
    const raw = await maybeGunzip(buf);
    return toActivities(decode(raw), fileId, source);
  }
  return { parse, isFit, maybeGunzip };
})();
