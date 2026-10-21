'use strict';
/* TriCoach – Basis: Hilfsfunktionen, Formatierung, Grafik-Bausteine */

const APP_VERSION = '2.6.1';
const DAY = 86400000;
const DT = 10; // alle Zeitreihen werden auf 10-s-Raster gebracht
const SPORTS = ['swim', 'bike', 'run'];                       // Triathlon-Disziplinen (Analysen, Prognosen)
const ALL = ['swim', 'bike', 'run', 'strength', 'other'];      // alles, was im Kalender und in den Summen zählt
const NAME = { swim: 'Schwimmen', bike: 'Rad', run: 'Laufen', strength: 'Athletik', other: 'Sonstiges' };
const C = { swim: 'var(--swim)', bike: 'var(--bike)', run: 'var(--run)', strength: 'var(--str)', other: 'var(--oth)' };
const hasDist = s => s === 'swim' || s === 'bike' || s === 'run';
/* Wo geschwommen: 25 | 50 (Bahnlänge in m) | 'ow' (Freiwasser) – eingetragen, korrigiert oder von der Uhr erkannt */
const swimWhere = a => a.sport !== 'swim' ? null : a.where != null ? a.where : a.swim ? (a.swim.ow ? 'ow' : Math.round(a.swim.pool || 25)) : a.pool ? Math.round(a.pool) : null;
const whereTxt = w => w === 'ow' ? 'Freiwasser' : w ? `${w}-m-Bahn` : '';
/* Distanzen: Schwimmen in km mit zwei Nachkommastellen (z. B. 2,35 km), sonst km */
const distTxt = (sport, m) => !m ? '' : sport === 'swim' ? de(m / 1000, m % 1000 ? 2 : 1) + ' km' : km(m, sport === 'bike' ? 0 : 1);

function rng(seed) { let a = seed >>> 0; return () => { a = (a + 0x6D2B79F5) | 0; let t = Math.imul(a ^ (a >>> 15), 1 | a); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; }; }
const noise = (r, a) => (r() * 2 - 1) * a;
const sod = d => { const x = new Date(d); x.setHours(0, 0, 0, 0); return x; };
const addDays = (d, n) => { const x = new Date(d); x.setDate(x.getDate() + n); return x; };
const weekStart = d => { const x = sod(d); return addDays(x, -((x.getDay() + 6) % 7)); };
const monthStart = d => new Date(d.getFullYear(), d.getMonth(), 1);
const sameDay = (a, b) => sod(a).getTime() === sod(b).getTime();
const isoDay = d => { const x = new Date(d); return `${x.getFullYear()}-${String(x.getMonth() + 1).padStart(2, '0')}-${String(x.getDate()).padStart(2, '0')}`; };
const at = (d, h, m = 0) => { const x = new Date(d); x.setHours(h, m, 0, 0); return x; };
const mean = a => a.length ? a.reduce((s, v) => s + v, 0) / a.length : null;
const median = a => { if (!a.length) return null; const s = [...a].sort((x, y) => x - y); const m = s.length >> 1; return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2; };
const sd = a => { const m = mean(a); return a.length > 1 ? Math.sqrt(a.reduce((s, v) => s + (v - m) ** 2, 0) / (a.length - 1)) : 0; };
const slope = a => { const n = a.length; if (n < 3) return 0; const mx = (n - 1) / 2, my = mean(a); let u = 0, d = 0; a.forEach((y, x) => { u += (x - mx) * (y - my); d += (x - mx) ** 2; }); return u / d; };
const clamp = (v, a, b) => Math.min(b, Math.max(a, v));
const num = v => typeof v === 'number' && isFinite(v);

const de = (v, d = 0) => num(v) ? v.toLocaleString('de-DE', { minimumFractionDigits: d, maximumFractionDigits: d }) : '–';
const dur = s => { s = Math.max(0, Math.round(s || 0)); const h = Math.floor(s / 3600), m = Math.floor(s % 3600 / 60), x = s % 60; return h ? `${h}:${String(m).padStart(2, '0')}:${String(x).padStart(2, '0')}` : `${m}:${String(x).padStart(2, '0')}`; };
const hm = s => { const m = Math.round((s || 0) / 60); return m >= 60 ? `${Math.floor(m / 60)}h ${String(m % 60).padStart(2, '0')}m` : `${m} min`; };
const pv = s => { if (!num(s)) return '–'; s = Math.round(s); return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`; };
const km = (m, d = 1) => de(m / 1000, d) + ' km';
const pace = v => v > .3 ? pv(1000 / v) + ' /km' : '–';
const spaceS = v => v > .1 ? pv(100 / v) + ' /100m' : '–';
const kmh = v => num(v) ? de(v * 3.6, 1) + ' km/h' : '–';
const dayTitle = d => d.toLocaleDateString('de-DE', { weekday: 'long', day: 'numeric', month: 'long' });
const shortDate = d => d.toLocaleDateString('de-DE', { day: 'numeric', month: 'short' });
const time = d => d.toLocaleTimeString('de-DE', { hour: '2-digit', minute: '2-digit' });
const sgn = (v, d = 0) => { if (!num(v)) return '–'; const r = +v.toFixed(d); return r === 0 ? de(0, d) : (r > 0 ? '+' : '−') + de(Math.abs(r), d); };
const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

/* ---------- Icons ---------- */
const ICON = {
  swim: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="16" cy="6" r="2.2"/><path d="M4 12l5-3 3 3 3-2"/><path d="M2 17c2 0 2-1.5 4-1.5S8 17 10 17s2-1.5 4-1.5 2 1.5 4 1.5 2-1.5 4-1.5"/></svg>',
  bike: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="5.5" cy="16.5" r="3.5"/><circle cx="18.5" cy="16.5" r="3.5"/><path d="M5.5 16.5l4-7h6l3 7M9.5 9.5l3 7h-7M14 6h3"/></svg>',
  run: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="14" cy="4.5" r="2"/><path d="M6 21l4-6 3 2 1 4M10 15l1-5 4 3 3 0M11 10l-4 1-2 3"/></svg>',
  other: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="8"/></svg>',
  dash: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="3" width="7.5" height="7.5" rx="2"/><rect x="13.5" y="3" width="7.5" height="7.5" rx="2"/><rect x="3" y="13.5" width="7.5" height="7.5" rx="2"/><rect x="13.5" y="13.5" width="7.5" height="7.5" rx="2"/></svg>',
  cal: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><rect x="3" y="5" width="18" height="16" rx="3"/><path d="M3 10h18M8 3v4M16 3v4"/></svg>',
  chart: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 20h18M5 16l4-5 4 3 6-8"/></svg>',
  flag: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M5 21V4M5 4h11l-2 4 2 4H5"/></svg>',
  moon: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round"><path d="M20 14.5A8 8 0 019.5 4 8 8 0 1020 14.5z"/></svg>',
  heart: '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M12 21s-7.5-4.6-9.5-9.3C1 8 3.3 4.5 7 4.5c2 0 3.5 1 5 3 1.5-2 3-3 5-3 3.7 0 6 3.5 4.5 7.2C19.5 16.4 12 21 12 21z"/></svg>',
  bolt: '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M13 2L4 14h7l-1 8 9-12h-7z"/></svg>',
  timer: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="12" cy="13" r="8"/><path d="M12 9v4l2.5 2M9 2h6"/></svg>',
  sum: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M18 5H6l6 7-6 7h12"/></svg>',
  watch: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="6"/><path d="M9 6l1-4h4l1 4M9 18l1 4h4l1-4M12 9.5V12l1.5 1.5"/></svg>',
  gear: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.7 1.7 0 00.3 1.8l.1.1a2 2 0 11-2.8 2.8l-.1-.1a1.7 1.7 0 00-1.8-.3 1.7 1.7 0 00-1 1.5V21a2 2 0 11-4 0v-.1a1.7 1.7 0 00-1.1-1.5 1.7 1.7 0 00-1.8.3l-.1.1a2 2 0 11-2.8-2.8l.1-.1a1.7 1.7 0 00.3-1.8 1.7 1.7 0 00-1.5-1H3a2 2 0 110-4h.1a1.7 1.7 0 001.5-1.1 1.7 1.7 0 00-.3-1.8l-.1-.1a2 2 0 112.8-2.8l.1.1a1.7 1.7 0 001.8.3H9a1.7 1.7 0 001-1.5V3a2 2 0 114 0v.1a1.7 1.7 0 001 1.5 1.7 1.7 0 001.8-.3l.1-.1a2 2 0 112.8 2.8l-.1.1a1.7 1.7 0 00-.3 1.8V9a1.7 1.7 0 001.5 1H21a2 2 0 110 4h-.1a1.7 1.7 0 00-1.5 1z"/></svg>',
  map: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round"><path d="M9 4L3 6v14l6-2 6 2 6-2V4l-6 2-6-2zM9 4v14M15 6v14"/></svg>',
  sync: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M20 11a8 8 0 00-14.3-4.3L4 9M4 4v5h5M4 13a8 8 0 0014.3 4.3L20 15M20 20v-5h-5"/></svg>',
  dot: '<svg viewBox="0 0 24 24" fill="currentColor"><circle cx="12" cy="12" r="6"/></svg>',
  strength: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M6.5 6.5v11M17.5 6.5v11M3.5 9v6M20.5 9v6M6.5 12h11"/></svg>',
  plus: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round"><path d="M12 5v14M5 12h14"/></svg>',
  edit: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M4 20h4L19 9l-4-4L4 16v4zM14 6l4 4"/></svg>',
  trophy: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M8 4h8v5a4 4 0 01-8 0V4zM8 6H4.5a3 3 0 003.5 4M16 6h3.5a3 3 0 01-3.5 4M12 13v4M8 21h8M9.5 17h5"/></svg>',
  share: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3v12M8 7l4-4 4 4M5 12v7a2 2 0 002 2h10a2 2 0 002-2v-7"/></svg>',
  search: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="11" cy="11" r="6.5"/><path d="M20 20l-4.2-4.2"/></svg>',
  bell: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M6 16V11a6 6 0 0112 0v5l2 2H4l2-2zM10 21h4"/></svg>',
  repeat: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M17 2l3 3-3 3M4 11V9a4 4 0 014-4h12M7 22l-3-3 3-3M20 13v2a4 4 0 01-4 4H4"/></svg>',
  pin: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round"><path d="M12 21s-6-5.6-6-11a6 6 0 0112 0c0 5.4-6 11-6 11z"/><circle cx="12" cy="10" r="2.2"/></svg>',
  list: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M9 6h11M9 12h11M9 18h11M4.5 6h.01M4.5 12h.01M4.5 18h.01"/></svg>',
  check: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12.5l4.5 4.5L19 7.5"/></svg>',
  tp: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 17l5-6 4 3 5-7 4 5"/><circle cx="17" cy="7" r="1.6" fill="currentColor"/></svg>',
  star: '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M12 3l2.7 5.6 6.1.9-4.4 4.3 1 6.1L12 17l-5.4 2.9 1-6.1L3.2 9.5l6.1-.9z"/></svg>',
  school: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M2 9l10-5 10 5-10 5L2 9z"/><path d="M6 11v5c3 2.5 9 2.5 12 0v-5M22 9v6"/></svg>',
  sun: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/></svg>',
  rings: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2"><circle cx="12" cy="12" r="9"/><circle cx="12" cy="12" r="5.5"/><circle cx="12" cy="12" r="2"/></svg>',
};
const sicon = s => ICON[s] || ICON.other;
const icon = (name, size = 16, color) => (ICON[name] || ICON.dot).replace('<svg', `<svg width="${size}" height="${size}"${color ? ` style="color:${color}"` : ''}`);

/* ---------- UI-Bausteine ---------- */
const tile = (t, v, unit, sub, color, ic = 'dot', act) =>
  `<${act ? `button data-act="${act}"` : 'div'} class="tile" style="--c:${color}"><div class="ic">${ICON[ic] || ICON.dot}</div><div class="t">${t}</div><div class="v">${v}${unit ? `<small>${unit}</small>` : ''}</div>${sub ? `<div class="s">${sub}</div>` : ''}</${act ? 'button' : 'div'}>`;
const prow = (t, frac, detail, color) => `<div class="prow"><div class="top"><span>${t}</span><span>${detail}</span></div><div class="bar"><i style="width:${clamp(frac || 0, 0, 1) * 100}%;--c:${color}"></i></div></div>`;
const zc = i => `var(--z${i + 1})`;
const empty = (title, text, action) => `<div class="empty"><b>${title}</b><span>${text}</span>${action || ''}</div>`;

function ticks(lo, hi, n = 4) {
  const span = hi - lo || 1, step0 = span / n, mag = 10 ** Math.floor(Math.log10(step0)), step = [1, 2, 2.5, 5, 10].map(m => m * mag).find(s => s >= step0);
  const out = []; for (let v = Math.ceil(lo / step) * step; v <= hi + 1e-9; v += step) out.push(+v.toFixed(6)); return out;
}
function chart({ w, h = 200, x0, x1, y0, y1, yt, yFmt = v => de(v, v % 1 ? 1 : 0), xt = [], layers, pad = [12, 12, 24, 42] }) {
  const [pt, pr, pb, pl] = pad, sx = x => pl + (x - x0) / ((x1 - x0) || 1) * (w - pl - pr), sy = y => h - pb - (y - y0) / ((y1 - y0) || 1) * (h - pt - pb);
  let s = `<svg class="chart" viewBox="0 0 ${w} ${h}" role="img">`;
  (yt || ticks(Math.min(y0, y1), Math.max(y0, y1))).forEach(v => { s += `<line class="grid" x1="${pl}" x2="${w - pr}" y1="${sy(v)}" y2="${sy(v)}"/><text class="axis" x="${pl - 6}" y="${sy(v) + 4}" text-anchor="end">${yFmt(v)}</text>`; });
  xt.forEach(t => { s += `<text class="axis" x="${sx(t.v)}" y="${h - 6}" text-anchor="middle">${t.l}</text>`; });
  return s + layers.map(f => f(sx, sy)).join('') + '</svg>';
}
const path = (pts, sx, sy) => pts.map((p, i) => (i ? 'L' : 'M') + sx(p.x).toFixed(1) + ' ' + sy(p.y).toFixed(1)).join('');
const line = (pts, color, wdt = 2.2, dash) => (sx, sy) => pts.length ? `<path d="${path(pts, sx, sy)}" fill="none" stroke="${color}" stroke-width="${wdt}" stroke-linejoin="round" ${dash ? 'stroke-dasharray="4 4"' : ''}/>` : '';
const area = (pts, color, base) => (sx, sy) => pts.length ? `<path d="${path(pts, sx, sy)}L${sx(pts[pts.length - 1].x)} ${sy(base)}L${sx(pts[0].x)} ${sy(base)}Z" fill="${color}" opacity=".16"/>` : '';
const dots = (pts, color, r = 3) => (sx, sy) => pts.map(p => `<circle cx="${sx(p.x)}" cy="${sy(p.y)}" r="${r}" fill="${color}"/>`).join('');
const dateTicks = (from, to, n, fmt) => { const out = []; for (let i = 0; i <= n; i++) { const v = from + (to - from) * i / n; out.push({ v, l: fmt(new Date(v)) }); } return out; };
function cw(half) { const c = document.getElementById('content'); const W = c ? c.clientWidth : 800; return Math.max(260, Math.floor((half && W >= 716 ? (W - 16) / 2 : W) - 34)); }
const rolling = (pts, n = 5) => pts.map((p, i) => ({ x: p.x, y: mean(pts.slice(Math.max(0, i - n + 1), i + 1).map(q => q.y)) }));

function ring(v, label, cap, color, size = 116) {
  const r = 48, c = 2 * Math.PI * r;
  return `<svg width="${size}" height="${size}" viewBox="0 0 116 116" style="flex:none"><circle cx="58" cy="58" r="${r}" fill="none" stroke="${color}" stroke-opacity=".18" stroke-width="12"/><circle cx="58" cy="58" r="${r}" fill="none" stroke="${color}" stroke-width="12" stroke-linecap="round" stroke-dasharray="${c * clamp(v, 0, 1)} ${c}" transform="rotate(-90 58 58)"/><text x="58" y="62" text-anchor="middle" style="font-family:var(--num)" font-weight="700" font-size="32" fill="var(--fg)">${label}</text><text x="58" y="80" text-anchor="middle" font-size="10" fill="var(--muted)">${cap}</text></svg>`;
}

/* GPS-Spur als SVG (ohne Kartenkacheln, funktioniert offline) */
function trackSvg(tracks, W, H = 240) {
  const all = tracks.flatMap(t => t.pts);
  if (all.length < 2) return '';
  const lat0 = mean(all.map(p => p[0])), k = Math.cos(lat0 * Math.PI / 180);
  const xs = all.map(p => p[1] * k), ys = all.map(p => -p[0]);
  const mnx = Math.min(...xs), mxx = Math.max(...xs), mny = Math.min(...ys), mxy = Math.max(...ys);
  const sc = Math.min((W - 30) / ((mxx - mnx) || 1e-6), (H - 30) / ((mxy - mny) || 1e-6));
  const ox = (W - (mxx - mnx) * sc) / 2, oy = (H - (mxy - mny) * sc) / 2;
  const P = p => `${((p[1] * k - mnx) * sc + ox).toFixed(1)} ${((-p[0] - mny) * sc + oy).toFixed(1)}`;
  return `<svg class="chart" viewBox="0 0 ${W} ${H}">${tracks.map(t => `<path d="M${t.pts.map(P).join('L')}" fill="none" stroke="${t.color}" stroke-opacity="${t.opacity ?? 1}" stroke-width="${t.width ?? 4}" stroke-linejoin="round" stroke-linecap="round"/>`).join('')}</svg>`;
}
