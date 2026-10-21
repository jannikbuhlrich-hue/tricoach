'use strict';
/* TriCoach – Kalender im Stil von Apple Kalender:
   Tag · Woche · Monat · Jahr · Liste, ganztägige und mehrtägige Einträge, Wiederholungen (auch eigene Wochentage),
   zwei Hinweise, Ort, URL, Notizen, Kalender ein-/ausblenden, Suche, Drag & Drop, Duplizieren,
   Wettkämpfe mit Priorität A/B/C, Termine, .ics-Export (inkl. Wiederholung + Erinnerung) und .ics-Import. */

const CALS = [['swim', 'Schwimmen'], ['bike', 'Rad'], ['run', 'Laufen'], ['strength', 'Athletik'], ['other', 'Sonstiges'], ['race', 'Wettkämpfe'], ['event', 'Termine'], ['school', 'Schule']];
const calKey = p => p.kind === 'race' ? 'race' : p.kind === 'event' ? 'event' : p.kind === 'school' ? 'school' : (p.sport || 'other');
const calColor = k => ({ race: 'var(--accent)', event: 'var(--fit)', school: 'var(--school)' }[k] || C[k] || C.other);
const pColor = p => calColor(calKey(p));
const pIcon = p => p.kind === 'race' ? ICON.flag : p.kind === 'event' ? ICON.cal : p.kind === 'school' ? ICON.school : sicon(p.sport);
const calVisible = k => !SET.calHidden.includes(k);
const ALERTS = [['', 'Keiner'], [0, 'Zum Zeitpunkt'], [5, '5 Minuten vorher'], [15, '15 Minuten vorher'], [30, '30 Minuten vorher'], [60, '1 Stunde vorher'], [120, '2 Stunden vorher'], [1440, '1 Tag vorher'], [2880, '2 Tage vorher'], [10080, '1 Woche vorher']];
const REPEATS = [['', 'Nie'], ['daily', 'Täglich'], ['weekly', 'Wöchentlich'], ['biweekly', 'Alle 2 Wochen'], ['monthly', 'Monatlich'], ['yearly', 'Jährlich'], ['custom', 'Eigene …']];
const WD = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
const ICS_WD = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];
const STR_FOCUS = ['Kraft', 'Stabi & Core', 'Mobility', 'Plyometrie', 'Lauf-ABC', 'Yoga', 'Zirkel'];
const OTHER_TYPES = ['Kitesurfen', 'Wandern', 'Yoga', 'SUP', 'Rudern', 'Ski', 'Mannschaftssport', 'Spaziergang', 'Klettern'];
const RACE_FMT = { sprint: 'Triathlon Sprint', olympic: 'Triathlon Olympisch', middle: 'Triathlon 70.3', full: 'Triathlon Langdistanz', r5: 'Lauf 5 km', r10: 'Lauf 10 km', rhm: 'Halbmarathon', rm: 'Marathon', duath: 'Duathlon', bike: 'Radrennen', swim: 'Freiwasserschwimmen', other: 'Sonstiges' };
const COMPL = { good: ['var(--good)', 'Plan erfüllt'], warn: ['var(--warn)', 'teilweise'], orange: ['var(--z5)', 'abweichend'], bad: ['var(--bad)', 'verpasst'] };

const endOf = p => p.allDay ? addDays(sod(p.date), p.days || 1) : new Date(p.date.getTime() + (p.min || 60) * 60000);
const minTxt = m => `${Math.floor(m / 60)}:${String(Math.round(m % 60)).padStart(2, '0')}`;
const durMin = s => { s = String(s || '').trim().replace(',', '.'); if (!s) return null; if (s.includes(':')) { const [h, m] = s.split(':').map(Number); return (h || 0) * 60 + (m || 0); } const n = +s; return isFinite(n) ? n : null; };
function kw(d) { const t = new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate())), dn = (t.getUTCDay() + 6) % 7; t.setUTCDate(t.getUTCDate() - dn + 3); const y = new Date(Date.UTC(t.getUTCFullYear(), 0, 4)); return 1 + Math.round(((t - y) / DAY - 3 + (y.getUTCDay() + 6) % 7) / 7); }
const ref = p => `${p.id}|${p.occ || ''}`;
const masterOf = id => PLAN.find(p => p.id === id);

/* ---------- Wiederholungen ---------- */
function* recurDates(p) {
  const r = p.rrule, b = new Date(p.date), iv = Math.max(1, r.interval || 1);
  if (r.freq === 'weekly') {
    const days = (r.byday?.length ? r.byday : [(b.getDay() + 6) % 7]).slice().sort((x, y) => x - y), ws = weekStart(b);
    for (let w = 0; w < 5300; w += iv) for (const wd of days) { const d = addDays(ws, w * 7 + wd); d.setHours(b.getHours(), b.getMinutes(), 0, 0); if (d >= b) yield d; }
  } else for (let k = 0; k < 20000; k++) {
    const d = new Date(b);
    if (r.freq === 'daily') d.setDate(b.getDate() + k * iv);
    else if (r.freq === 'monthly') { d.setDate(1); d.setMonth(b.getMonth() + k * iv); if (new Date(d.getFullYear(), d.getMonth() + 1, 0).getDate() < b.getDate()) continue; d.setDate(b.getDate()); }
    else if (r.freq === 'yearly') { d.setDate(1); d.setFullYear(b.getFullYear() + k * iv); if (new Date(d.getFullYear(), b.getMonth() + 1, 0).getDate() < b.getDate()) continue; d.setDate(b.getDate()); }
    else return;
    yield d;
  }
}
function occurrences(p, from, to) {
  if (!p.rrule) return endOf(p) > from && p.date < to ? [p] : [];
  const out = [], r = p.rrule, until = r.until ? addDays(sod(new Date(r.until + 'T00:00:00')), 1) : null, span = endOf(p) - p.date; let n = 0;
  for (const d of recurDates(p)) {
    if (d >= to || (until && d >= until) || (r.count && n >= r.count)) break;
    n++;
    const key = isoDay(d);
    if ((p.ex || []).includes(key)) continue;
    if (d.getTime() + span > from.getTime()) out.push({ ...p, date: d, occ: key });
  }
  return out;
}
/* all = alle eigenen Einträge (ohne Filter, ohne Schule) – für Erinnerungen, Plan-Erfüllung, Tagesübersicht */
function calItems(from, to, all) {
  return [...PLAN.flatMap(p => occurrences(p, from, to)), ...(!all && calVisible('school') ? schoolItems(from, to) : [])].filter(p => all || calVisible(calKey(p)))
    .sort((a, b) => (b.allDay ? 1 : 0) - (a.allDay ? 1 : 0) || a.date - b.date);
}
const actsIn = (from, to) => SET.showDone ? ACTS.filter(a => a.start >= from && a.start < to && calVisible(a.sport)) : [];
function repeatTxt(r) {
  if (!r) return '';
  const base = { daily: 'täglich', weekly: 'wöchentlich', monthly: 'monatlich', yearly: 'jährlich' }[r.freq];
  let t = r.interval > 1 ? `alle ${r.interval} ${{ daily: 'Tage', weekly: 'Wochen', monthly: 'Monate', yearly: 'Jahre' }[r.freq]}` : base;
  if (r.freq === 'weekly' && r.byday?.length) t += ' am ' + r.byday.map(i => WD[i]).join(', ');
  if (r.until) t += ` bis ${new Date(r.until + 'T00:00:00').toLocaleDateString('de-DE')}`; else if (r.count) t += `, ${r.count}×`;
  return t;
}

/* ---------- Plan-Erfüllung wie in TrainingPeaks (grün / gelb / orange / rot) ---------- */
function compliance(p) {
  if ((p.kind || 'workout') !== 'workout') return null;
  const a = doneFor(p);
  if (a) { const r = p.min ? a.dur / (p.min * 60) : 1; return { a, k: r >= .8 && r <= 1.2 ? 'good' : r >= .5 && r <= 1.5 ? 'warn' : 'orange' }; }
  return sod(p.date) < TODAY ? { k: 'bad' } : null;
}
const cplDot = c => c ? `<i class="cdot" style="background:${COMPL[c.k][0]}" title="${COMPL[c.k][1]}"></i>` : '';

/* ---------- Ansicht ---------- */
const CAL_VIEWS = [['day', 'Tag'], ['week', 'Woche'], ['month', 'Monat'], ['year', 'Jahr'], ['list', 'Liste']];
function calTitle() {
  const d = S.day, v = SET.calView;
  if (S.calQ) return 'Suche';
  if (v === 'day') return dayTitle(d) + (sameDay(d, TODAY) ? ' · heute' : '');
  if (v === 'week') { const a = weekStart(d), b = addDays(a, 6); return `KW ${kw(a)} · ${a.getDate()}.${a.getMonth() !== b.getMonth() ? ' ' + a.toLocaleDateString('de-DE', { month: 'short' }) : ''} – ${b.toLocaleDateString('de-DE', { day: 'numeric', month: 'short', year: 'numeric' })}`; }
  if (v === 'month') return d.toLocaleDateString('de-DE', { month: 'long', year: 'numeric' });
  if (v === 'year') return String(d.getFullYear());
  return 'Demnächst';
}
function vCalendar() {
  const v = SET.calView;
  let h = header('Kalender');
  h += `<div class="card calcard"><div class="calbar"><div class="seg">${CAL_VIEWS.map(([k, l]) => `<button class="${v === k && !S.calQ ? 'on' : ''}" data-act="calview:${k}">${l}</button>`).join('')}</div>
    <div class="row calnav"><button class="btn" data-act="calmove:-1" aria-label="Zurück">‹</button><button class="btn" data-act="caltoday">Heute</button><button class="btn" data-act="calmove:1" aria-label="Weiter">›</button>
    <button class="btn ${S.calSearch ? 'on' : ''}" data-act="calsearch" aria-label="Suchen">${icon('search', 16)}</button><button class="btn ${S.calFilter ? 'on' : ''}" data-act="calfilter">${icon('list', 16)} Kalender</button><button class="btn primary" data-act="addmenu">${icon('plus', 16)} Neu</button></div></div>
    ${S.calSearch ? `<input class="search" id="calq" type="search" placeholder="Titel, Ort, Notizen, Sportart …" value="${esc(S.calQ || '')}" data-change="calq" autocomplete="off">` : ''}
    ${S.calFilter ? calFilterPanel() : ''}
    <h2 class="caltitle">${calTitle()}</h2>`;
  if (S.calQ) h += calSearchResults();
  else h += ({ day: calDay, week: calWeek, month: calMonth, year: calYear, list: calList }[v] || calMonth)();
  h += `</div>`;
  if (!S.calQ && (v === 'month' || v === 'week')) h += dayAgenda(S.day);
  return h;
}
function calFilterPanel() {
  return `<div class="calfilter"><div class="chips">${CALS.map(([k, l]) => `<button class="fchip ${calVisible(k) ? 'on' : ''}" data-act="caltoggle:${k}" style="--c:${calColor(k)}"><i></i>${l}</button>`).join('')}</div>
    <label class="toggle"><input type="checkbox" data-change="showdone" ${SET.showDone ? 'checked' : ''}> Erledigte Einheiten von der Uhr anzeigen</label>
    <div class="row" style="flex-wrap:wrap"><button class="btn small" data-act="ics">${icon('share', 14)} An Apple Kalender senden (.ics)</button><label class="btn small" for="icsfile" style="cursor:pointer">${icon('cal', 14)} Kalenderdatei importieren</label><input id="icsfile" type="file" accept=".ics,text/calendar" hidden></div>
    <span class="cap">Export enthält Wiederholungen und Hinweise – Apple Kalender erinnert dich dann zuverlässig, auch wenn TriCoach zu ist. Import: z. B. den Trainingsplan aus TrainingPeaks (iCal-Export) oder einen anderen Kalender.</span></div>`;
}

/* Monat: Apple-Raster mit Kalenderwochen, Einträge als Chips (schmal: Punkte) */
function calMonth() {
  const m = monthStart(S.day), gs = weekStart(m), last = new Date(m.getFullYear(), m.getMonth() + 1, 0), ge = addDays(weekStart(last), 7);
  const items = calItems(gs, ge).filter(p => p.kind !== 'school' || p.exam || p.cancelled || p.changed), acts = actsIn(gs, ge);
  let g = '<div class="kwh">KW</div>' + WD.map(d => `<div class="wd">${d}</div>`).join('');
  for (let ws = gs; ws < ge; ws = addDays(ws, 7)) {
    g += `<div class="kw">${kw(ws)}</div>`;
    for (let i = 0; i < 7; i++) {
      const d = addDays(ws, i), e = addDays(d, 1), its = items.filter(p => p.date < e && endOf(p) > d);
      const matched = new Set(its.map(p => compliance(p)?.a?.id).filter(Boolean)), extra = acts.filter(a => sameDay(a.start, d) && !matched.has(a.id));
      const chips = [...its.map(p => { const c = compliance(p); return `<span class="ev ${p.kind || 'workout'} ${c?.a ? 'done' : ''} ${p.cancelled ? 'cancelled' : ''}" style="--c:${pColor(p)}" data-act="edit:${ref(p)}" ${p.kind === 'school' ? '' : `draggable="true" data-drag="${ref(p)}"`}>${cplDot(c)}${p.allDay || !sameDay(p.date, d) ? '' : `<em>${time(p.date)}</em>`}${esc(p.title)}</span>`; }),
        ...extra.map(a => `<span class="ev done act" style="--c:${C[a.sport] || C.other}" data-act="open:${a.id}">✓ ${esc(a.name)}</span>`)];
      const dots = [...its.map(p => `<i class="${compliance(p)?.a ? '' : 'ring'}" style="${compliance(p)?.a ? 'background' : 'border-color'}:${pColor(p)}"></i>`), ...extra.map(a => `<i style="background:${C[a.sport] || C.other}"></i>`)];
      g += `<div role="button" tabindex="0" data-act="day:${d.getTime()}" data-drop="${d.getTime()}" class="mc ${d.getMonth() !== m.getMonth() ? 'out' : ''} ${sameDay(d, S.day) ? 'sel' : ''} ${sameDay(d, TODAY) ? 'now' : ''}"><span class="dn">${d.getDate()}</span><span class="evs">${chips.slice(0, 3).join('')}${chips.length > 3 ? `<span class="more">+${chips.length - 3} weitere</span>` : ''}</span><span class="dots">${dots.slice(0, 4).join('')}</span></div>`;
    }
  }
  return `<div class="mgrid">${g}</div><div class="legend"><span><i style="background:var(--muted)"></i>erledigt</span><span><i style="border:1.5px solid var(--muted)"></i>geplant</span>${Object.values(COMPL).map(([c, l]) => `<span><i style="background:${c}"></i>${l}</span>`).join('')}</div>`;
}

/* Woche / Tag: Zeitraster mit Stunden, Überlappungen nebeneinander, rote Jetzt-Linie */
const PXH = 46;
function layout(blocks) {
  blocks.sort((a, b) => a.s - b.s || b.e - a.e);
  let cl = [], cols = [], end = -Infinity;
  const flush = () => { cl.forEach(b => b.n = cols.length); cl = []; cols = []; };
  for (const b of blocks) {
    if (cl.length && b.s >= end) flush();
    let c = cols.findIndex(e => e <= b.s); if (c < 0) { c = cols.length; cols.push(0); }
    cols[c] = b.e; b.col = c; cl.push(b); end = cl.length === 1 ? b.e : Math.max(end, b.e);
  }
  flush(); return blocks;
}
function timeGrid(days) {
  const from = days[0], to = addDays(days[days.length - 1], 1), items = calItems(from, to), acts = actsIn(from, to);
  const timed = items.filter(p => !p.allDay), allday = items.filter(p => p.allDay);
  let h0 = 6, h1 = 22;
  [...timed.map(p => [p.date, endOf(p)]), ...acts.map(a => [a.start, new Date(a.start.getTime() + a.dur * 1000)])].forEach(([s, e]) => { if (sameDay(s, e) || e - s < DAY) { h0 = Math.min(h0, s.getHours()); h1 = Math.max(h1, Math.min(24, (sameDay(s, e) ? e.getHours() : 23) + 1)); } });
  const one = days.length === 1;
  let head = `<div class="tg-head" style="--n:${days.length}"><div></div>${days.map(d => `<button class="tg-day ${sameDay(d, TODAY) ? 'now' : ''}" data-act="${one ? 'calview:day' : 'gotoday:' + d.getTime()}"><span>${WD[(d.getDay() + 6) % 7]}</span><b>${d.getDate()}</b></button>`).join('')}</div>`;
  if (allday.length) head += `<div class="tg-all" style="--n:${days.length}"><div class="cap">ganzt.</div>${days.map(d => `<div>${allday.filter(p => p.date < addDays(d, 1) && endOf(p) > d).map(p => `<span class="ev ${p.kind}" style="--c:${pColor(p)}" data-act="edit:${ref(p)}">${esc(p.title)}</span>`).join('')}</div>`).join('')}</div>`;
  let body = `<div class="tg-body" style="--n:${days.length};height:${(h1 - h0) * PXH}px"><div class="tg-hours">${Array.from({ length: h1 - h0 }, (_, i) => `<span style="top:${i * PXH}px">${String(h0 + i).padStart(2, '0')}:00</span>`).join('')}</div>`;
  for (const d of days) {
    const ds = d.getTime(), mins = x => (x - ds) / 60000 - h0 * 60;
    const its = timed.filter(p => sameDay(p.date, d)), matched = new Set(its.map(p => compliance(p)?.a?.id).filter(Boolean));
    const blocks = layout([...its.map(p => ({ s: mins(p.date), e: Math.max(mins(p.date) + 22, mins(endOf(p))), p })), ...acts.filter(a => sameDay(a.start, d) && !matched.has(a.id)).map(a => ({ s: mins(a.start), e: Math.max(mins(a.start) + 22, mins(a.start) + a.dur / 60), a }))]);
    body += `<div class="tg-col ${sameDay(d, TODAY) ? 'now' : ''}" data-drop="${ds}" data-h0="${h0}">${Array.from({ length: (h1 - h0) * 2 }, (_, i) => `<button class="slot" style="top:${i * PXH / 2}px;height:${PXH / 2}px" data-act="new:${ds + (h0 * 60 + i * 30) * 60000}" aria-label="Neuer Eintrag ${String(h0 + (i >> 1)).padStart(2, '0')}:${i % 2 ? '30' : '00'}"></button>`).join('')}`;
    for (const b of blocks) {
 const hgt = Math.max(18, (b.e - b.s) / 60 * PXH - 2), sh = hgt < 32 ? 'short' : '';
      const st = `top:${b.s / 60 * PXH}px;height:${hgt}px;left:calc(${b.col} * 100% / ${b.n});width:calc(100% / ${b.n} - 3px)`;
      if (b.p) { const p = b.p, c = compliance(p); body += `<button class="blk ${sh} ${p.kind || 'workout'} ${c?.a ? 'done' : ''} ${p.cancelled ? 'cancelled' : ''} ${p.changed ? 'changed' : ''}" style="${st};--c:${pColor(p)}" data-act="edit:${ref(p)}" ${p.kind === 'school' ? '' : `draggable="true" data-drag="${ref(p)}"`}><b>${cplDot(c)}${esc(p.title)}</b><span>${time(p.date)}${p.location ? ' · ' + esc(p.location) : ''}</span></button>`; }
      else { const a = b.a; body += `<button class="blk ${sh} act done" style="${st};--c:${C[a.sport] || C.other}" data-act="open:${a.id}"><b>✓ ${esc(a.name)}</b><span>${time(a.start)} · ${hm(a.dur)}</span></button>`; }
    }
    if (sameDay(d, NOW)) { const n = (NOW - ds) / 60000 - h0 * 60; if (n > 0 && n < (h1 - h0) * 60) body += `<div class="nowline" style="top:${n / 60 * PXH}px"></div>`; }
    body += `</div>`;
  }
  return `<div class="tgrid">${head}${body}</div></div>`;
}
const calWeek = () => timeGrid(Array.from({ length: 7 }, (_, i) => addDays(weekStart(S.day), i)));
const calDay = () => timeGrid([sod(S.day)]) + dayAgenda(S.day, true);

/* Jahr: zwölf Mini-Monate, Tage nach Trainingszeit eingefärbt, Wettkämpfe markiert */
function calYear() {
  const y = S.day.getFullYear(), from = new Date(y, 0, 1), to = new Date(y + 1, 0, 1), dayDur = {};
  ACTS.forEach(a => { if (a.start >= from && a.start < to) { const k = isoDay(a.start); dayDur[k] = (dayDur[k] || 0) + a.dur; } });
  const races = new Set(calItems(from, to, true).filter(p => p.kind === 'race').map(p => isoDay(p.date))), plans = new Set(calItems(from, to).map(p => isoDay(p.date)));
  let h = '<div class="ygrid">';
  for (let mo = 0; mo < 12; mo++) {
    const m = new Date(y, mo, 1), gs = weekStart(m), last = new Date(y, mo + 1, 0);
    let tot = 0, g = WD.map(d => `<i class="yw">${d[0]}</i>`).join('');
    for (let d = gs; d <= last; d = addDays(d, 1)) {
      if (d < m) { g += '<i></i>'; continue; }
      const k = isoDay(d), s = dayDur[k] || 0; tot += s;
      const lv = s ? Math.min(4, 1 + Math.floor(s / 2700)) : 0;
      g += `<button class="yd l${lv} ${races.has(k) ? 'race' : ''} ${!s && plans.has(k) ? 'plan' : ''} ${sameDay(d, TODAY) ? 'now' : ''}" data-act="gotoday:${d.getTime()}" title="${d.toLocaleDateString('de-DE')}${s ? ' · ' + hm(s) : ''}">${d.getDate()}</button>`;
    }
    h += `<div class="ym"><button class="linkbtn" data-act="gomonth:${m.getTime()}">${m.toLocaleDateString('de-DE', { month: 'long' })}</button><span class="cap">${tot ? hm(tot) : ''}</span><div class="ymg">${g}</div></div>`;
  }
  return h + `</div><div class="legend"><span><i style="background:color-mix(in srgb,var(--accent) 35%,transparent)"></i>wenig</span><span><i style="background:var(--accent)"></i>viel Training</span><span><i style="border:2px solid var(--accent)"></i>Wettkampf</span></div>`;
}

/* Liste: die nächsten 90 Tage, nach Tagen gruppiert */
function calList() {
  const items = calItems(TODAY, addDays(TODAY, 90)).filter(p => p.kind !== 'school' || p.exam || p.cancelled || p.changed);
  if (!items.length) return empty('Nichts geplant', 'In den nächsten 90 Tagen stehen keine Einträge im Kalender.', `<button class="btn primary" data-act="addmenu">${icon('plus', 14)} Neu</button>`);
  const groups = new Map(); items.forEach(p => { const k = isoDay(p.date); (groups.get(k) || groups.set(k, []).get(k)).push(p); });
  return [...groups.entries()].map(([k, ps]) => `<div class="lday"><h4>${dayTitle(new Date(k + 'T00:00:00'))}</h4><div class="list">${ps.map(agendaRow).join('')}</div></div>`).join('');
}
function calSearchResults() {
  const q = S.calQ.trim().toLowerCase(), hit = (...t) => t.some(x => String(x || '').toLowerCase().includes(q));
  const ps = PLAN.filter(p => hit(p.title, p.location, p.notes, p.art, NAME[p.sport], RACE_FMT[p.fmt], p.kind === 'race' ? 'wettkampf' : '')).sort((a, b) => a.date - b.date);
  const as = ACTS.filter(a => hit(a.name, a.notes, a.art, NAME[a.sport])).slice(0, 30);
  if (!ps.length && !as.length) return empty('Keine Treffer', `Nichts gefunden für „${esc(S.calQ)}“.`);
  return `${ps.length ? `<div class="lday"><h4>Kalender (${ps.length})</h4><div class="list">${ps.map(p => agendaRow(p, true)).join('')}</div></div>` : ''}${as.length ? `<div class="lday"><h4>Einheiten (${as.length}${as.length === 30 ? '+' : ''})</h4><div class="list">${as.map(actRow).join('')}</div></div>` : ''}`;
}

function agendaRow(p, withDate) {
  const c = compliance(p), when = p.allDay ? (p.days > 1 ? `${p.days} Tage` : 'ganztägig') : `${time(p.date)}–${time(endOf(p))}`;
  return `<button class="act" data-act="edit:${ref(p)}"><span class="sport" style="--c:${pColor(p)}">${pIcon(p)}</span><span class="mid"><b class="${p.cancelled ? 'strike' : ''}">${c?.a ? '✓ ' : ''}${esc(p.title)}${p.kind === 'race' ? ` <span class="prio p${p.prio || 'A'}">${p.prio || 'A'}</span>` : ''}</b><span>${withDate ? shortDate(p.date) + ' · ' : ''}${when}${p.dist ? ' · ' + distTxt(p.sport, p.dist) : ''}${p.location ? ' · ' + esc(p.location) : ''}${p.rrule ? ' · ↻' : ''}${p.alarm != null ? ' · 🔔' : ''}</span></span><span class="end">${c ? `<span class="cpl" style="--c:${COMPL[c.k][0]}">${COMPL[c.k][1]}</span>` : ''}${p.kind === 'race' ? (p.tp ? '<span class="cpl" style="--c:var(--good)">in TP</span>' : '<span class="cpl" style="--c:var(--warn)">nicht in TP</span>') : ''}</span></button>`;
}
function dayAgenda(d, compact) {
  const items = calItems(sod(d), addDays(sod(d), 1)), matched = new Set(items.map(p => compliance(p)?.a?.id).filter(Boolean)), acts = ACTS.filter(a => sameDay(a.start, d) && !matched.has(a.id));
  return `<div class="card"><h3>${compact ? 'Einträge' : dayTitle(d)} <small>${items.length + acts.length ? `${items.length} geplant · ${acts.length + matched.size} erledigt` : ''}</small></h3>
    ${!items.length && !acts.length ? '<span class="muted">Keine Einträge</span>' : ''}<div class="list">${items.map(p => agendaRow(p)).join('')}${acts.map(actRow).join('')}</div>
    <div class="row" style="flex-wrap:wrap"><button class="btn primary" data-act="new:${at(d, 18).getTime()}">${icon('plus', 14)} Training planen</button><button class="btn" data-act="log:${at(d, sameDay(d, TODAY) ? Math.max(6, NOW.getHours() - 1) : 18).getTime()}">${icon('check', 14)} Einheit eintragen</button><button class="btn" data-act="newk:race|${at(d, 9).getTime()}">${icon('flag', 14)} Wettkampf</button><button class="btn" data-act="newk:event|${at(d, 12).getTime()}">${icon('cal', 14)} Termin</button></div></div>`;
}

/* ---------- Neu-Menü ---------- */
function addMenuSheet() {
  const t = at(S.view === 'calendar' ? S.day : TODAY, 18).getTime(), now = at(TODAY, Math.max(6, NOW.getHours() - 1)).getTime();
  const opt = (act, ic, col, t1, t2) => `<button class="addopt" data-act="${act}"><span class="sport" style="--c:${col}">${ic}</span><span class="mid"><b>${t1}</b><span>${t2}</span></span></button>`;
  return sheetWrap('Neu', `<div class="list">
    ${opt('log:' + now, ICON.check, 'var(--good)', 'Einheit eintragen', 'Erledigt – z. B. Schwimm-km, Athletik, Kitesurfen. Auf Wunsch weiter an TrainingPeaks.')}
    ${opt('new:' + t, ICON.run, 'var(--run)', 'Training planen', 'Mit Wiederholung, Hinweis, Ort und Notizen')}
    ${opt('newk:race|' + at(S.view === 'calendar' ? S.day : TODAY, 9).getTime(), ICON.flag, 'var(--accent)', 'Wettkampf / Event', 'Priorität A/B/C, Distanz, Zielzeit')}
    ${opt('newk:event|' + at(S.view === 'calendar' ? S.day : TODAY, 12).getTime(), ICON.cal, 'var(--fit)', 'Termin', 'Alles andere, z. B. Physio, Trainingslager')}</div>`, false);
}

/* ---------- Editor (Bottom-Sheet wie in Apple Kalender) ---------- */
function newDraft(kind, date) {
  const d = new Date(date);
  return { kind, sport: kind === 'workout' ? 'run' : undefined, title: '', date: d, allDay: false, min: kind === 'race' ? 150 : 60, days: 1, location: '', notes: '', url: '', alarm: kind === 'race' ? 1440 : null, alarm2: null, rrule: null, prio: 'A', fmt: 'olympic', goal: '', season: false, dist: null, art: '', tp: false };
}
function openPlanEditor(r) {
  const [id, occ] = r.split('|');
  if (id.startsWith('su-')) { S.sheet = { t: 'lesson', k: `${id.slice(3, 13)}|${id.slice(14, 19)}` }; render(); return; }
  if (id.startsWith('ex-')) { go('school'); return; }
  const m = masterOf(id); if (!m) return;
  const d = { ...m, date: occ ? new Date(occurrences(m, sod(new Date(occ + 'T00:00:00')), addDays(sod(new Date(occ + 'T00:00:00')), 1))[0]?.date || m.date) : new Date(m.date) };
  if (m.rrule) d.rrule = { ...m.rrule };
  S.sheet = { t: 'plan', id, occ: m.rrule ? occ : null, occDate: new Date(d.date), d }; render();
}
const defaultTitle = d => d.kind === 'race' ? 'Wettkampf' : d.kind === 'event' ? 'Termin' : d.sport === 'strength' ? 'Athletik' : d.sport === 'other' ? (d.art || 'Training') : { run: 'Lauf', bike: 'Radeinheit', swim: 'Schwimmen' }[d.sport];

function sheetWrap(title, body, form, foot = '') {
  const inner = `<div class="sheet-head"><button type="button" class="linkbtn" data-act="sheet-close">Abbrechen</button><b>${title}</b>${form ? `<button class="linkbtn strong" type="submit" name="scope" value="all">Sichern</button>` : '<span></span>'}</div><div class="sheet-body">${body}</div>${foot}`;
  return `<div class="sheet-bg" data-act="sheet-close"></div>${form ? `<form class="sheet" id="${form}" novalidate>${inner}</form>` : `<div class="sheet">${inner}</div>`}`;
}
const fg = rows => `<div class="fgroup">${rows.filter(Boolean).join('')}</div>`;
const frow = (label, ctrl, extra = '') => `<label class="frow ${extra}"><span>${label}</span>${ctrl}</label>`;
const opts = (list, val) => list.map(([v, l]) => `<option value="${v}" ${String(v) === String(val ?? '') ? 'selected' : ''}>${l}</option>`).join('');

function planSheet() {
  const s = S.sheet, d = s.d, k = d.kind || 'workout', rep = d.rrule ? (d.rrule.ui || (d.rrule.freq === 'weekly' && d.rrule.interval === 2 && !d.rrule.byday?.length ? 'biweekly' : d.rrule.interval > 1 || d.rrule.byday?.length ? 'custom' : d.rrule.freq)) : '';
  const rend = d.rrule?.until ? 'until' : d.rrule?.count ? 'count' : '';
  let b = `<div class="seg kseg">${[['workout', 'Training'], ['race', 'Wettkampf'], ['event', 'Termin']].map(([v, l]) => `<button type="button" class="${k === v ? 'on' : ''}" data-act="kind:${v}">${l}</button>`).join('')}</div>`;
  b += fg([`<input name="f-title" class="big" placeholder="${defaultTitle(d)}" value="${esc(d.title)}" autocomplete="off">`, `<input name="f-loc" placeholder="Ort" value="${esc(d.location || '')}" autocomplete="off">`]);
  if (k === 'workout') {
    b += fg([frow('Sportart', `<select name="f-sport" data-change="sheet">${opts(ALL.map(x => [x, NAME[x]]), d.sport)}</select>`),
      d.sport === 'other' ? frow('Art', `<input name="f-art" list="othertypes" value="${esc(d.art || '')}" placeholder="z. B. Kitesurfen"><datalist id="othertypes">${OTHER_TYPES.map(x => `<option value="${x}">`).join('')}</datalist>`) : '',
      hasDist(d.sport) ? frow('Distanz (km)', `<input name="f-dist" type="number" inputmode="decimal" step="${d.sport === 'swim' ? '0.05' : '0.1'}" min="0" value="${d.dist ? +(d.dist / 1000).toFixed(2) : ''}" placeholder="optional">`) : '']);
  }
  if (k === 'race') b += fg([frow('Priorität', `<select name="f-prio">${opts([['A', 'A – Saisonhöhepunkt'], ['B', 'B – wichtig'], ['C', 'C – Trainingswettkampf']], d.prio)}</select>`),
    frow('Distanz', `<select name="f-fmt">${opts(Object.entries(RACE_FMT), d.fmt)}</select>`), frow('Zielzeit', `<input name="f-goal" placeholder="z. B. 2:25:00" value="${esc(d.goal || '')}" inputmode="numeric">`),
    `<label class="frow"><span>Saisonziel <em class="cap">Prognose, Taper, Countdown</em></span><input type="checkbox" name="f-season" ${d.season ? 'checked' : ''}></label>`]);
  b += fg([`<label class="frow"><span>Ganztägig</span><input type="checkbox" name="f-allday" data-change="sheet" ${d.allDay ? 'checked' : ''}></label>`,
    frow(d.allDay ? 'Datum' : 'Beginn', `<span class="pair"><input type="date" name="f-date" value="${isoDay(d.date)}" required>${d.allDay ? '' : `<input type="time" name="f-time" value="${time(d.date)}">`}</span>`),
    d.allDay ? frow('Dauer (Tage)', `<input type="number" name="f-days" min="1" max="60" value="${d.days || 1}">`) : k === 'event' ? frow('Ende', `<input type="time" name="f-end" value="${time(endOf(d))}">`) : frow('Dauer (h:mm)', `<input name="f-min" inputmode="numeric" value="${minTxt(d.min || 60)}" placeholder="1:00">`)]);
  b += fg([frow('Wiederholen', `<select name="f-rep" data-change="sheet">${opts(REPEATS, rep)}</select>`),
    rep === 'custom' ? frow('Alle', `<span class="pair"><input type="number" name="f-rint" min="1" max="52" value="${d.rrule?.interval || 1}" style="max-width:70px"><select name="f-rfreq" data-change="sheet">${opts([['daily', 'Tage'], ['weekly', 'Wochen'], ['monthly', 'Monate'], ['yearly', 'Jahre']], d.rrule?.freq || 'weekly')}</select></span>`) : '',
    rep === 'custom' && (d.rrule?.freq || 'weekly') === 'weekly' ? `<div class="frow wdrow"><span>An</span><span class="wds">${WD.map((w, i) => `<label><input type="checkbox" name="f-wd${i}" ${(d.rrule?.byday?.length ? d.rrule.byday : [(d.date.getDay() + 6) % 7]).includes(i) ? 'checked' : ''}><b>${w}</b></label>`).join('')}</span></div>` : '',
    rep ? frow('Wiederholung endet', `<select name="f-rend" data-change="sheet">${opts([['', 'Nie'], ['until', 'Am Datum'], ['count', 'Nach Anzahl']], rend)}</select>`) : '',
    rep && rend === 'until' ? frow('Endet am', `<input type="date" name="f-runtil" value="${d.rrule?.until || isoDay(addDays(d.date, 84))}">`) : '',
    rep && rend === 'count' ? frow('Anzahl', `<input type="number" name="f-rcount" min="1" max="500" value="${d.rrule?.count || 10}">`) : '']);
  b += fg([frow('Hinweis', `<select name="f-alarm" data-change="sheet">${opts(ALERTS, d.alarm)}</select>`), d.alarm != null ? frow('Zweiter Hinweis', `<select name="f-alarm2">${opts(ALERTS, d.alarm2)}</select>`) : '']);
  b += fg([`<input name="f-url" type="url" placeholder="URL (z. B. Ausschreibung, Trainingsplan)" value="${esc(d.url || '')}" autocomplete="off">`, `<textarea name="f-notes" rows="3" placeholder="Notizen – z. B. Ablauf: 15' ein, 5×1 km @ Schwelle, 10' aus">${esc(d.notes || '')}</textarea>`]);
  if (k === 'race') b += fg([`<label class="frow"><span>In TrainingPeaks eingetragen</span><input type="checkbox" name="f-tp" ${d.tp ? 'checked' : ''}></label>`]);
  // Aktionen für bestehende Einträge
  if (s.id) {
    const acts = [];
    if (k === 'race') acts.push(`<button type="button" class="btn" data-act="tp-race">${ICON.tp} An TrainingPeaks übergeben</button>`);
    if (k === 'workout' && sod(d.date) <= TODAY) acts.push(`<button type="button" class="btn" data-act="plan2log">${ICON.check} Als erledigt eintragen</button>`);
    acts.push(`<button type="button" class="btn" data-act="pdup">Duplizieren</button>`, `<button type="button" class="btn" data-act="pics">${ICON.share} In Apple Kalender</button>`);
    b += `<div class="row" style="flex-wrap:wrap">${acts.join('')}</div>`;
    b += s.occ ? `<div class="fgroup del"><b class="cap">Löschen</b><div class="row" style="flex-wrap:wrap"><button type="button" class="btn danger" data-act="pdel:one">Nur dieser Termin</button><button type="button" class="btn danger" data-act="pdel:future">Alle zukünftigen</button><button type="button" class="btn danger" data-act="pdel:all">Alle</button></div></div>`
      : `<button type="button" class="btn danger" data-act="pdel:all">Löschen</button>`;
  }
  const foot = s.occ ? `<div class="sheet-foot"><span class="cap">Wiederholender Eintrag (${repeatTxt(masterOf(s.id)?.rrule)}) – Änderungen sichern für:</span><div class="row"><button class="btn" type="submit" name="scope" value="one">Nur diesen Termin</button><button class="btn primary" type="submit" name="scope" value="all">Alle Termine</button></div></div>` : '';
  return sheetWrap(s.id ? 'Bearbeiten' : k === 'race' ? 'Neuer Wettkampf' : k === 'event' ? 'Neuer Termin' : 'Neues Training', b, 'planform', foot);
}
function readPlanForm() {
  const f = document.getElementById('planform'); if (!f) return;
  const g = n => f.elements[n], v = n => g(n)?.value ?? '', d = S.sheet.d;
  if (g('f-title')) d.title = v('f-title').trim();
  if (g('f-loc')) d.location = v('f-loc').trim();
  if (g('f-sport')) d.sport = v('f-sport');
  if (g('f-art')) d.art = v('f-art').trim(); else if (d.sport !== 'strength' && d.sport !== 'other') d.art = '';
  if (g('f-dist')) { const x = parseFloat(v('f-dist').replace(',', '.')); d.dist = x > 0 ? Math.round(x * 1000) : null; } else if (d.kind !== 'workout' || !hasDist(d.sport)) d.dist = null;
  if (g('f-prio')) { d.prio = v('f-prio'); d.fmt = v('f-fmt'); d.goal = v('f-goal').trim(); d.season = g('f-season').checked; }
  if (g('f-tp')) d.tp = g('f-tp').checked;
  const wasAll = d.allDay; d.allDay = !!g('f-allday')?.checked;
  const [Y, M, D] = v('f-date').split('-').map(Number), [hh, mm] = (v('f-time') || (wasAll ? '18:00' : time(d.date))).split(':').map(Number);
  if (Y) d.date = d.allDay ? new Date(Y, M - 1, D) : new Date(Y, M - 1, D, hh || 0, mm || 0);
  if (d.allDay) d.days = Math.max(1, +v('f-days') || d.days || 1);
  else if (g('f-end')) { const [eh, em] = v('f-end').split(':').map(Number); if (num(eh)) { let e = new Date(d.date); e.setHours(eh, em || 0, 0, 0); if (e <= d.date) e = addDays(e, 1); d.min = Math.round((e - d.date) / 60000); } }
  else if (g('f-min')) { const m = durMin(v('f-min')); if (m > 0) d.min = Math.round(m); }
  const rep = v('f-rep');
  if (!rep) d.rrule = null;
  else {
    const r = { ui: rep, freq: rep === 'biweekly' ? 'weekly' : rep === 'custom' ? (v('f-rfreq') || d.rrule?.freq || 'weekly') : rep, interval: rep === 'biweekly' ? 2 : rep === 'custom' ? Math.max(1, +v('f-rint') || 1) : 1 };
    if (rep === 'custom' && r.freq === 'weekly') { const by = [0, 1, 2, 3, 4, 5, 6].filter(i => g('f-wd' + i)?.checked); if (by.length) r.byday = by; else if (d.rrule?.byday) r.byday = d.rrule.byday; }
    const re = g('f-rend') ? v('f-rend') : (d.rrule?.until ? 'until' : d.rrule?.count ? 'count' : '');
    if (re === 'until') r.until = v('f-runtil') || d.rrule?.until || isoDay(addDays(d.date, 84));
    if (re === 'count') r.count = Math.max(1, +v('f-rcount') || d.rrule?.count || 10);
    d.rrule = r;
  }
  if (g('f-alarm')) { d.alarm = v('f-alarm') === '' ? null : +v('f-alarm'); d.alarm2 = d.alarm == null ? null : (g('f-alarm2') ? (v('f-alarm2') === '' ? null : +v('f-alarm2')) : d.alarm2); }
  if (g('f-url')) d.url = v('f-url').trim();
  if (g('f-notes')) d.notes = v('f-notes');
}
const newId = () => 'p' + Date.now().toString(36) + Math.floor(Math.random() * 1e4).toString(36);
function savePlanSheet(scope) {
  readPlanForm();
  const s = S.sheet, d = s.d;
  if (!d.title) d.title = defaultTitle(d);
  const clean = { ...d }; delete clean.occ;
  if (!s.id) PLAN.push({ ...clean, id: newId() });
  else {
    const m = masterOf(s.id); if (!m) { S.sheet = null; render(); return; }
    if (m.rrule && s.occ && scope === 'one') { m.ex = [...(m.ex || []), s.occ]; PLAN.push({ ...clean, id: newId(), rrule: null, ex: undefined }); }
    else if (m.rrule && s.occ) { const delta = clean.date - s.occDate; Object.assign(m, clean, { id: m.id, date: new Date(m.date.getTime() + delta), ex: m.ex }); }
    else Object.assign(m, clean, { id: m.id });
  }
  if (d.kind === 'race' && d.season) setSeasonRace(d);
  savePlan(); S.sheet = null; render(); toast(d.kind === 'race' && !d.tp ? 'Gesichert · Tipp: über „An TrainingPeaks übergeben“ auch dort eintragen' : 'Gesichert');
}
/* Wettkampf als Saisonziel → Prognose, Taper und Countdown */
function setSeasonRace(d) {
  PLAN.forEach(p => { if (p.kind === 'race' && p.season && !(p.title === d.title && sameDay(p.date, d.date))) p.season = false; });
  RACE.name = d.title; RACE.date = new Date(d.date);
  if (FMT[d.fmt]) RACE.fmt = d.fmt;
  saveSettings();
}
function deletePlan(scope) {
  const s = S.sheet, m = masterOf(s.id); if (!m) return;
  if (scope === 'one' && s.occ) m.ex = [...(m.ex || []), s.occ];
  else if (scope === 'future' && s.occ) { m.rrule = { ...m.rrule, until: isoDay(addDays(new Date(s.occ + 'T00:00:00'), -1)), count: undefined }; if (sod(new Date(s.occ + 'T00:00:00')) <= sod(m.date)) PLAN = PLAN.filter(p => p !== m); }
  else PLAN = PLAN.filter(p => p !== m);
  savePlan(); S.sheet = null; render(); toast('Gelöscht');
}
function duplicatePlan() {
  readPlanForm();
  const d = { ...S.sheet.d, title: S.sheet.d.title || defaultTitle(S.sheet.d), tp: false };
  S.sheet = { t: 'plan', id: null, d }; render(); toast('Kopie – Datum anpassen und sichern');
}
/* Drag & Drop: Eintrag auf anderen Tag (Monat) oder andere Uhrzeit (Woche/Tag) ziehen */
function movePlan(r, target, minutes) {
  const [id, occ] = r.split('|'), m = masterOf(id); if (!m) return;
  const src = occ ? new Date(occ + 'T00:00:00') : sod(m.date), cur = occ ? occurrences(m, src, addDays(src, 1))[0] : m; if (!cur) return;
  const nd = new Date(target); if (minutes != null && !cur.allDay) nd.setHours(0, minutes, 0, 0); else nd.setHours(cur.date.getHours(), cur.date.getMinutes(), 0, 0);
  if (m.rrule && occ) { m.ex = [...(m.ex || []), occ]; PLAN.push({ ...m, id: newId(), date: nd, rrule: null, ex: undefined }); toast('Nur dieser Termin verschoben'); }
  else m.date = nd;
  savePlan(); render();
}
document.addEventListener('dragstart', e => { const el = e.target.closest?.('[data-drag]'); if (!el) return; e.dataTransfer.setData('text/plain', el.dataset.drag); e.dataTransfer.effectAllowed = 'move'; el.classList.add('dragging'); });
document.addEventListener('dragover', e => { const t = e.target.closest?.('[data-drop]'); if (t) { e.preventDefault(); t.classList.add('over'); } });
document.addEventListener('dragleave', e => { e.target.closest?.('[data-drop]')?.classList.remove('over'); });
document.addEventListener('drop', e => {
  const t = e.target.closest?.('[data-drop]'); if (!t) return; e.preventDefault();
  const r = e.dataTransfer.getData('text/plain'); if (!r) return;
  let minutes = null;
  if (t.dataset.h0 != null) { const y = e.clientY - t.getBoundingClientRect().top; minutes = Math.round((+t.dataset.h0 * 60 + y / PXH * 60) / 15) * 15; }
  movePlan(r, +t.dataset.drop, minutes);
});

/* ---------- .ics Export ---------- */
const icsEsc = s => String(s || '').replace(/\\/g, '\\\\').replace(/;/g, '\\;').replace(/,/g, '\\,').replace(/\r?\n/g, '\\n');
const icsDT = d => `${d.getFullYear()}${String(d.getMonth() + 1).padStart(2, '0')}${String(d.getDate()).padStart(2, '0')}T${String(d.getHours()).padStart(2, '0')}${String(d.getMinutes()).padStart(2, '0')}00`;
const icsD = d => isoDay(d).replace(/-/g, '');
function icsFold(l) { const out = []; while (l.length > 74) { out.push(l.slice(0, 74)); l = ' ' + l.slice(74); } out.push(l); return out.join('\r\n'); }
function icsEvent(p) {
  const L = ['BEGIN:VEVENT', `UID:${p.id}@tricoach`, `DTSTAMP:${new Date().toISOString().replace(/[-:]/g, '').replace(/\.\d{3}/, '')}`];
  if (p.allDay) L.push(`DTSTART;VALUE=DATE:${icsD(p.date)}`, `DTEND;VALUE=DATE:${icsD(addDays(sod(p.date), p.days || 1))}`);
  else L.push(`DTSTART:${icsDT(p.date)}`, `DTEND:${icsDT(endOf(p))}`);
  const emo = p.kind === 'race' ? '🏁' : { swim: '🏊', bike: '🚴', run: '🏃', strength: '🏋️' }[p.sport] || '';
  L.push(`SUMMARY:${icsEsc((emo ? emo + ' ' : '') + p.title)}`);
  if (p.location) L.push(`LOCATION:${icsEsc(p.location)}`);
  const det = [p.kind === 'race' ? `Wettkampf (${p.prio || 'A'}) · ${RACE_FMT[p.fmt] || ''}${p.goal ? ' · Ziel ' + p.goal : ''}` : p.kind === 'workout' ? `${NAME[p.sport] || ''}${p.art ? ' · ' + p.art : ''}${p.dist ? ' · ' + distTxt(p.sport, p.dist) : ''}` : '', p.notes].filter(Boolean).join('\n');
  if (det) L.push(`DESCRIPTION:${icsEsc(det)}`);
  if (p.url) L.push(`URL:${icsEsc(p.url)}`);
  L.push(`CATEGORIES:${icsEsc(CALS.find(c => c[0] === calKey(p))?.[1] || 'TriCoach')}`);
  if (p.rrule) {
    const r = p.rrule, parts = [`FREQ=${r.freq.toUpperCase()}`];
    if (r.interval > 1) parts.push(`INTERVAL=${r.interval}`);
    if (r.freq === 'weekly' && r.byday?.length) parts.push(`BYDAY=${r.byday.map(i => ICS_WD[i]).join(',')}`);
    if (r.until) parts.push(`UNTIL=${r.until.replace(/-/g, '')}T235959`); else if (r.count) parts.push(`COUNT=${r.count}`);
    L.push(`RRULE:${parts.join(';')}`);
    (p.ex || []).forEach(x => { const d = new Date(x + 'T00:00:00'); d.setHours(p.date.getHours(), p.date.getMinutes()); L.push(p.allDay ? `EXDATE;VALUE=DATE:${x.replace(/-/g, '')}` : `EXDATE:${icsDT(d)}`); });
  }
  [p.alarm, p.alarm2].filter(a => a != null).forEach(a => L.push('BEGIN:VALARM', 'ACTION:DISPLAY', `DESCRIPTION:${icsEsc(p.title)}`, `TRIGGER:${a ? '-PT' + a + 'M' : 'PT0M'}`, 'END:VALARM'));
  L.push('END:VEVENT');
  return L;
}
async function exportIcs(items, name = 'TriCoach-Kalender') {
  items = items || PLAN.filter(p => p.rrule || endOf(p) >= addDays(TODAY, -1));
  if (!items.length) { toast('Keine kommenden Einträge zum Exportieren'); return; }
  const text = ['BEGIN:VCALENDAR', 'VERSION:2.0', 'PRODID:-//TriCoach//DE', 'CALSCALE:GREGORIAN', 'X-WR-CALNAME:TriCoach', ...items.flatMap(icsEvent), 'END:VCALENDAR'].map(icsFold).join('\r\n');
  const file = new File([text], name + '.ics', { type: 'text/calendar' });
  if (isIOS() && navigator.canShare?.({ files: [file] })) { try { await navigator.share({ files: [file], title: name }); return; } catch (e) { if (e.name === 'AbortError') return; } }
  const url = URL.createObjectURL(file);
  if (isIOS()) { location.href = url; } // Safari zeigt „Zum Kalender hinzufügen“
  else { const a = document.createElement('a'); a.href = url; a.download = file.name; document.body.appendChild(a); a.click(); a.remove(); }
  setTimeout(() => URL.revokeObjectURL(url), 20000);
  toast(`${items.length} Einträge exportiert`);
}

/* ---------- .ics Import (z. B. iCal-Export aus TrainingPeaks) ---------- */
function guessSport(t) {
  if (/schwimm|swim|🏊|freiwasser|\bcss\b|kraul/i.test(t)) return 'swim';
  if (/\brad\b|radfahr|bike|ride|cycl|🚴|zwift|\bftp\b|sweet ?spot/i.test(t)) return 'bike';
  if (/lauf|run|🏃|jog|\btrab/i.test(t)) return 'run';
  if (/athletik|kraft|stabi|core|strength|gym|mobility|🏋|yoga|zirkel/i.test(t)) return 'strength';
  return null;
}
function parseIcsDate(v, params) {
  if (/VALUE=DATE(?!-)/.test(params) || /^\d{8}$/.test(v)) return { d: new Date(+v.slice(0, 4), +v.slice(4, 6) - 1, +v.slice(6, 8)), allDay: true };
  const m = v.match(/^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})?(Z)?/); if (!m) return null;
  const d = m[7] ? new Date(Date.UTC(+m[1], m[2] - 1, +m[3], +m[4], +m[5])) : new Date(+m[1], m[2] - 1, +m[3], +m[4], +m[5]);
  return { d, allDay: false };
}
function importIcs(text, src) {
  const lines = text.replace(/\r\n[ \t]/g, '').replace(/\n[ \t]/g, '').split(/\r?\n/);
  const unesc = s => s.replace(/\\n/gi, '\n').replace(/\\([,;\\])/g, '$1');
  let ev = null, inAlarm = false, added = 0, updated = 0;
  for (const line of lines) {
    if (line === 'BEGIN:VEVENT') { ev = { ex: [] }; continue; }
    if (!ev) continue;
    if (line === 'BEGIN:VALARM') { inAlarm = true; continue; }
    if (line === 'END:VALARM') { inAlarm = false; continue; }
    if (line === 'END:VEVENT') {
      if (ev.start) {
        const text2 = `${ev.summary || ''} ${ev.desc || ''}`, sport = guessSport(text2), race = /wettkampf|race|rennen|triathlon|marathon|🏁|ironman|70\.3/i.test(ev.summary || '') && !/training|einheit/i.test(ev.summary || '');
        const p = {
          id: (src === 'tp' ? 'tp-' : 'ics-') + (ev.uid || ev.summary + ev.start.d.getTime()).replace(/[^\w-]/g, '').slice(0, 60), kind: race ? 'race' : sport ? 'workout' : 'event', sport: sport || (race ? undefined : undefined),
          title: (ev.summary || 'Termin').replace(/^[^\p{L}\p{N}]+/u, '').trim() || 'Termin', date: ev.start.d, allDay: ev.start.allDay, location: ev.loc || '', notes: ev.desc || '', url: ev.url || '',
          alarm: ev.alarm ?? null, alarm2: null, rrule: ev.rrule || null, ex: ev.ex, prio: 'A', fmt: 'other', tp: src === 'tp' || race, from: src || 'ics'
        };
        if (p.kind === 'workout' && !p.sport) p.sport = 'other';
        if (ev.end) { if (p.allDay) p.days = Math.max(1, Math.round((ev.end.d - ev.start.d) / DAY)); else p.min = Math.max(5, Math.round((ev.end.d - ev.start.d) / 60000)); }
        else if (ev.dur) p.min = ev.dur; else p.min = 60;
        const i = PLAN.findIndex(x => x.id === p.id);
        if (i >= 0) { const keep = PLAN[i]; PLAN[i] = { ...keep, ...p, alarm: keep.alarm ?? p.alarm, prio: keep.prio || p.prio, fmt: keep.fmt !== 'other' ? keep.fmt : p.fmt, kind: keep.kind || p.kind }; updated++; } else { PLAN.push(p); added++; }
      }
      ev = null; continue;
    }
    const c = line.indexOf(':'); if (c < 0) continue;
    const head = line.slice(0, c), val = line.slice(c + 1), [name, ...pr] = head.split(';'), params = pr.join(';');
    if (inAlarm) { if (name === 'TRIGGER') { const m = val.match(/-?P(?:(\d+)D)?T?(?:(\d+)H)?(?:(\d+)M)?/); if (m) ev.alarm = (+m[1] || 0) * 1440 + (+m[2] || 0) * 60 + (+m[3] || 0); } continue; }
    if (name === 'UID') ev.uid = val;
    else if (name === 'SUMMARY') ev.summary = unesc(val);
    else if (name === 'LOCATION') ev.loc = unesc(val);
    else if (name === 'DESCRIPTION') ev.desc = unesc(val);
    else if (name === 'URL') ev.url = val;
    else if (name === 'DTSTART') ev.start = parseIcsDate(val, params);
    else if (name === 'DTEND') ev.end = parseIcsDate(val, params);
    else if (name === 'DURATION') { const m = val.match(/P(?:(\d+)D)?T?(?:(\d+)H)?(?:(\d+)M)?/); if (m) ev.dur = (+m[1] || 0) * 1440 + (+m[2] || 0) * 60 + (+m[3] || 0); }
    else if (name === 'EXDATE') val.split(',').forEach(x => { const d = parseIcsDate(x, params); if (d) ev.ex.push(isoDay(d.d)); });
    else if (name === 'RRULE') {
      const o = Object.fromEntries(val.split(';').map(x => x.split('='))), f = (o.FREQ || '').toLowerCase();
      if (['daily', 'weekly', 'monthly', 'yearly'].includes(f)) {
        const r = { freq: f, interval: +o.INTERVAL || 1 };
        if (o.BYDAY && f === 'weekly') r.byday = o.BYDAY.split(',').map(x => ICS_WD.indexOf(x.slice(-2))).filter(i => i >= 0);
        if (o.UNTIL) r.until = `${o.UNTIL.slice(0, 4)}-${o.UNTIL.slice(4, 6)}-${o.UNTIL.slice(6, 8)}`; if (o.COUNT) r.count = +o.COUNT;
        r.ui = r.interval === 2 && f === 'weekly' && !r.byday?.length ? 'biweekly' : r.interval > 1 || (r.byday?.length > 1) ? 'custom' : f;
        ev.rrule = r;
      }
    }
  }
  savePlan(); render();
  toast(added || updated ? `${added} Einträge importiert${updated ? `, ${updated} aktualisiert` : ''}` : 'Keine Termine in der Datei gefunden');
}

/* ---------- Hinweise, solange TriCoach offen ist (zuverlässig: über den Apple-Kalender-Export) ---------- */
function checkAlarms() {
  const now = Date.now(), seen = (() => { try { return JSON.parse(sessionStorage.getItem('tricoach-alarms') || '[]'); } catch (e) { return []; } })();
  calItems(addDays(TODAY, -1), addDays(TODAY, 8), true).forEach(p => [p.alarm, p.alarm2].forEach(a => {
    if (a == null) return;
    const key = `${ref(p)}|${a}`, t = p.date.getTime() - a * 60000;
    if (now >= t && now < p.date.getTime() + 5 * 60000 && !seen.includes(key)) {
      seen.push(key);
      const msg = `${a >= 1440 ? (a === 1440 ? 'Morgen' : `In ${a / 1440} Tagen`) : a ? `In ${a >= 60 ? a / 60 + ' h' : a + ' min'}` : 'Jetzt'}: ${p.title}${p.allDay ? '' : ' um ' + time(p.date)}`;
      toast(msg);
      if (window.Notification?.permission === 'granted') navigator.serviceWorker?.getRegistration().then(r => r?.showNotification('TriCoach', { body: msg, icon: 'icons/icon-192.png', tag: key })).catch(() => { });
    }
  }));
  try { sessionStorage.setItem('tricoach-alarms', JSON.stringify(seen.slice(-200))); } catch (e) { }
}
