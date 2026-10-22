'use strict';
/* TriCoach – Schule (WebUntis) und „Mein Tag“.
   Daten kommen verschlüsselt aus dem Branch „schule-daten“ (GitHub-Job, siehe .github/workflows/schule.yml)
   und werden nur hier auf dem Gerät mit deinem Schlüssel entschlüsselt.
   Für Apple Kalender: WebUntis-iCal-Link direkt abonnieren (aktualisiert sich selbst) und
   Hausaufgaben/Prüfungen per .ics mit Erinnerung übernehmen. */

const SCH = {
  key: (() => { try { return localStorage.getItem('tricoach-schoolkey') || ''; } catch (e) { return ''; } })(),
  data: (() => { try { return JSON.parse(localStorage.getItem('tricoach-school') || 'null'); } catch (e) { return null; } })(),
  done: (() => { try { return JSON.parse(localStorage.getItem('tricoach-hwdone') || '{}'); } catch (e) { return {}; } })(),
  own: (() => { try { return JSON.parse(localStorage.getItem('tricoach-hw') || '[]'); } catch (e) { return []; } })(),
  busy: false, err: '', checked: null
};
const SUBJ = { M: 'Mathe', MA: 'Mathe', MAT: 'Mathe', DE: 'Deutsch', EN: 'Englisch', D: 'Deutsch', E: 'Englisch', F: 'Französisch', L: 'Latein', S: 'Spanisch', BIO: 'Biologie', BI: 'Biologie', CH: 'Chemie', PH: 'Physik', GE: 'Geschichte', EK: 'Erdkunde', POL: 'Politik', PW: 'Politik', SW: 'Sozialwiss.', WI: 'Wirtschaft', INF: 'Informatik', IF: 'Informatik', KU: 'Kunst', MU: 'Musik', SP: 'Sport', RE: 'Religion', ER: 'ev. Religion', KR: 'kath. Religion', PL: 'Philosophie', WN: 'Werte & Normen', DS: 'Darst. Spiel' };
/* Fachname: Langname aus WebUntis, sonst aus den Stunden desselben Kurses (z. B. „MatL1“ → Mathematik), sonst Kürzel-Liste */
function subjName(su, long) {
  if (long && long !== su) return long;
  if (!su) return '';
  const l = SCH.data?.lessons?.find(x => x.su === su && x.sul && x.sul !== su); if (l) return l.sul;
  const up = String(su).toUpperCase(); if (SUBJ[up]) return SUBJ[up];
  const pre = Object.keys(SUBJ).filter(k => k.length >= 2 && up.startsWith(k)).sort((a, b) => b.length - a.length)[0] || (SUBJ[up[0]] && /^[A-Z][^A-Z]/.test(String(su)) ? up[0] : null);
  return pre ? SUBJ[pre] : su;
}
const saveSch = () => { try { localStorage.setItem('tricoach-school', JSON.stringify(SCH.data)); localStorage.setItem('tricoach-hwdone', JSON.stringify(SCH.done)); localStorage.setItem('tricoach-hw', JSON.stringify(SCH.own)); localStorage.setItem('tricoach-schoolkey', SCH.key); } catch (e) { } };
const schoolOn = () => !!SCH.data;

/* Adresse der verschlüsselten Datei: aus der GitHub-Pages-Adresse abgeleitet, änderbar in den Einstellungen */
function schoolUrl() {
  if (SET.schoolUrl) return SET.schoolUrl;
  const owner = location.hostname.endsWith('.github.io') ? location.hostname.split('.')[0] : 'jannikbuhlrich-hue';
  const repo = location.hostname.endsWith('.github.io') ? (location.pathname.split('/')[1] || 'tricoach') : 'tricoach';
  return `https://raw.githubusercontent.com/${owner}/${repo}/schule-daten/schule.enc`;
}
const b64u = s => Uint8Array.from(atob(s), c => c.charCodeAt(0));
const DK = new Map();   // abgeleitete Schlüssel je Salz (seit 2.6 ist das Salz fest → nur einmal rechnen)
async function decryptSchool(txt, pass) {
  const o = JSON.parse(txt), ck = pass + '|' + o.salt;
  let key = DK.get(ck);
  if (!key) {
    const base = await crypto.subtle.importKey('raw', new TextEncoder().encode(pass), 'PBKDF2', false, ['deriveKey']);
    key = await crypto.subtle.deriveKey({ name: 'PBKDF2', salt: b64u(o.salt), iterations: 120000, hash: 'SHA-256' }, base, { name: 'AES-GCM', length: 256 }, false, ['decrypt']);
    DK.set(ck, key);
  }
  return JSON.parse(new TextDecoder().decode(await crypto.subtle.decrypt({ name: 'AES-GCM', iv: b64u(o.iv) }, key, b64u(o.ct))));
}
async function syncSchool(manual) {
  if (!SCH.key || SCH.busy) { if (manual && !SCH.key) toast('Erst den Schlüssel in den Einstellungen eintragen'); return; }
  if (!navigator.onLine) { if (manual) toast('Offline – Stundenplan vom letzten Abruf'); return; }
  SCH.busy = true; if (manual) render();
  try {
    const r = await fetch(schoolUrl() + '?t=' + Math.floor(Date.now() / 60000), { cache: 'no-store' });
    if (r.status === 404) throw new Error('Noch keine Schuldaten – läuft der GitHub-Job schon? (Einstellungen → Schule)');
    if (!r.ok) throw new Error('Abruf fehlgeschlagen (' + r.status + ')');
    const txt = await r.text();
    let d; try { d = await decryptSchool(txt, SCH.key); } catch (e) { throw new Error('Schlüssel passt nicht zum GitHub-Secret TRICOACH_KEY'); }
    const changed = !SCH.data || JSON.stringify(SCH.data.lessons?.filter(l => l.code)) !== JSON.stringify(d.lessons?.filter(l => l.code));
    SCH.data = d; SCH.err = ''; SCH.checked = Date.now(); saveSch();
    if (manual) toast(`Schule aktualisiert · Stand ${new Date(d.at).toLocaleString('de-DE', { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' })}`);
    else if (changed && SCH.checked) { const n = schoolChanges(TODAY, addDays(TODAY, 2)).length; if (n) toast(`Stundenplan: ${n} Änderung${n === 1 ? '' : 'en'} heute/morgen`); }
  } catch (e) { SCH.err = e.message; if (manual) toast(e.message); }
  SCH.busy = false; render();
}

/* ---------- Daten aufbereiten ---------- */
const lessonDate = (d, t) => { const [Y, M, D] = d.split('-').map(Number), [h, m] = t.split(':').map(Number); return new Date(Y, M - 1, D, h, m); };
/* Doppelstunden zusammenfassen */
function lessonsOn(day) {
  if (!SCH.data) return [];
  const k = isoDay(day), ls = SCH.data.lessons.filter(l => l.d === k).sort((a, b) => a.s.localeCompare(b.s) || (a.code === 'cancelled') - (b.code === 'cancelled'));
  const out = [];
  for (const l of ls) {
    const p = out[out.length - 1], gap = p ? (lessonDate(l.d, l.s) - lessonDate(p.d, p.e)) / 60000 : 99;
    if (p && p.su === l.su && p.code === l.code && p.ro === l.ro && p.te === l.te && gap >= 0 && gap <= 10 && p.info === l.info) p.e = l.e;
    else out.push({ ...l });
  }
  return out;
}
const schoolChanges = (from, to) => { const out = []; for (let d = sod(from); d < to; d = addDays(d, 1)) out.push(...lessonsOn(d).filter(l => l.code || l.info || l.subst).map(l => ({ ...l, day: new Date(d) }))); return out; };
const hwList = () => [...(SCH.data?.homework || []).map(h => ({ ...h, src: 'untis', key: 'u' + h.id })), ...SCH.own.map(h => ({ ...h, src: 'own', key: h.id }))]
  .map(h => ({ ...h, isDone: SCH.done[h.key] ?? h.done, dueD: new Date(h.due + 'T00:00:00') }));
const hwOpen = () => hwList().filter(h => !h.isDone).sort((a, b) => a.dueD - b.dueD);
const examsAhead = days => (SCH.data?.exams || []).map(x => ({ ...x, date: lessonDate(x.d, x.s || '08:00') })).filter(x => x.date >= TODAY && x.date < addDays(TODAY, days)).sort((a, b) => a.date - b.date);

/* Für den Kalender: Stunden und Prüfungen als (nicht bearbeitbare) Einträge der Ebene „Schule“ */
function schoolItems(from, to) {
  if (!SCH.data) return [];
  const out = [];
  for (let d = sod(from); d < to; d = addDays(d, 1)) lessonsOn(d).forEach(l => {
    const s = lessonDate(l.d, l.s), e = lessonDate(l.d, l.e);
    out.push({ id: 'su-' + l.d + '-' + l.s + '-' + l.su, occ: '', kind: 'school', title: (l.code === 'cancelled' ? 'Entfall: ' : '') + subjName(l.su, l.sul), date: s, min: (e - s) / 60000, location: l.ro, cancelled: l.code === 'cancelled', changed: l.code === 'irregular', lesson: l });
  });
  examsAhead(400).filter(x => x.date >= from && x.date < to).forEach(x => out.push({ id: 'ex-' + x.id, occ: '', kind: 'school', exam: true, title: `📝 ${x.name || 'Prüfung'}${x.su ? ' · ' + subjName(x.su) : ''}`, date: x.date, min: x.e ? (lessonDate(x.d, x.e) - x.date) / 60000 : 90, location: x.ro, examObj: x }));
  return out;
}
function lessonRow(l, compact) {
  const cls = l.code === 'cancelled' ? 'cancel' : l.code === 'irregular' || l.subst ? 'chg' : '';
  const note = [l.code === 'cancelled' ? 'Entfall' : l.code === 'irregular' ? (l.subst || 'Änderung') : l.subst, l.roOrg ? `Raum ${l.roOrg} → ${l.ro}` : '', l.teOrg ? `${l.teOrg} → ${l.te}` : '', l.info].filter(Boolean).join(' · ');
  return `<button class="lrow ${cls}" data-act="lesson:${l.d}|${l.s}"><span class="lt">${l.s}<br><small>${l.e}</small></span><span class="lmid"><b>${esc(subjName(l.su, l.sul))}</b><span>${[l.ro, compact ? '' : l.te].filter(Boolean).map(esc).join(' · ')}</span>${note ? `<em>${esc(note)}</em>` : ''}</span></button>`;
}

/* ---------- Mein Tag: Schule + Training + Termine + Hausaufgaben auf einen Blick ---------- */
function vToday() {
  const evening = NOW.getHours() >= 17 && S.todayOff == null, off = S.todayOff ?? (evening ? 1 : 0), day = addDays(TODAY, off);
  let h = `<div class="topline"><div><span class="muted">${off === 0 ? 'Heute' : off === 1 ? 'Morgen' : ''}</span><h1>${day.toLocaleDateString('de-DE', { weekday: 'long', day: 'numeric', month: 'long' })}</h1></div><div class="seg">${[[-1, '‹'], [0, 'Heute'], [1, 'Morgen'], [2, '›']].map(([v, l]) => `<button class="${(v === 0 || v === 1) && off === v ? 'on' : ''}" data-act="todayoff:${v === -1 ? off - 1 : v === 2 ? off + 1 : v}">${l}</button>`).join('')}</div></div>`;
  // Kurzüberblick
  const ls = lessonsOn(day), active = ls.filter(l => l.code !== 'cancelled'), first = active[0], last = active[active.length - 1];
  const train = calItems(day, addDays(day, 1), true).filter(p => p.kind !== 'school'), done = ACTS.filter(a => sameDay(a.start, day));
  const rd = ACTS.length ? readiness() : null, due = hwOpen().filter(hw => hw.dueD <= addDays(day, 1)), ex = examsAhead(14);
  h += `<div class="tiles">${schoolOn() ? tile('Schule', first ? first.s : 'frei', '', first ? `bis ${last.e}${ls.some(l => l.code) ? ` · ${ls.filter(l => l.code === 'cancelled').length} Entfall${ls.some(l => l.code === 'irregular') ? ` · ${ls.filter(l => l.code === 'irregular').length} Änderung` : ''}` : ` · ${active.length} Std.`}` : (ls.length ? 'alles fällt aus' : 'kein Unterricht'), 'var(--school)', 'school', 'nav:school') : ''}
    ${tile('Training', train.filter(p => p.kind === 'workout').length + done.length ? `${done.length}/${Math.max(done.length, train.filter(p => p.kind === 'workout').length)}` : '–', '', train.filter(p => p.kind === 'workout').map(p => p.title).join(', ') || (done.length ? done.map(a => a.name).join(', ') : 'nichts geplant'), 'var(--run)', 'run', 'nav:calendar')}
    ${schoolOn() || SCH.own.length ? tile('Hausaufgaben', due.length, 'offen', due.length ? 'bis ' + (off === 0 ? 'morgen' : 'übermorgen') : 'alles erledigt', due.length ? 'var(--warn)' : 'var(--good)', 'check', 'nav:school') : ''}
    ${rd ? tile('Bereitschaft', rd.score, '/100', `Form ${Math.round(LOAD.tsb)}`, { high: 'var(--good)', mid: 'var(--warn)', low: 'var(--bad)' }[rd.level], 'heart', 'nav:dashboard') : ''}</div>`;
  const tpm = off === 0 ? tpMissing(14).length : 0;
  if (tpm) h += `<button class="card tpnote" data-act="tpbulk"><span class="dot" style="background:var(--warn)"></span><span><b>${tpm} Einheit${tpm === 1 ? '' : 'en'} fehlen in TrainingPeaks</b><span class="cap">Antippen, um alle auf einmal nachzutragen – damit deine Trainerin alles sieht.</span></span></button>`;
  if (SCH.data?.news?.length && off === 0) h += `<div class="card news">${SCH.data.news.map(n => `<div class="ins"><span class="dot" style="background:var(--school)"></span><div><b>${esc(n.subject || 'Nachricht')}</b><span class="fg" style="white-space:pre-wrap">${esc(n.text)}</span></div></div>`).join('')}</div>`;
  // Zeitstrahl
  const items = [...ls.map(l => ({ t: lessonDate(l.d, l.s), html: lessonRow(l, true) })),
    ...train.filter(p => !p.allDay).map(p => ({ t: p.date, html: `<button class="lrow plan" style="--c:${pColor(p)}" data-act="edit:${ref(p)}"><span class="lt">${time(p.date)}<br><small>${time(endOf(p))}</small></span><span class="lmid"><b>${compliance(p)?.a ? '✓ ' : ''}${esc(p.title)}</b><span>${p.kind === 'race' ? 'Wettkampf' : p.kind === 'event' ? 'Termin' : NAME[p.sport] || ''}${p.location ? ' · ' + esc(p.location) : ''}</span></span></button>` })),
    ...done.filter(a => !train.some(p => compliance(p)?.a?.id === a.id)).map(a => ({ t: a.start, html: `<button class="lrow plan done" style="--c:${C[a.sport] || C.other}" data-act="open:${a.id}"><span class="lt">${time(a.start)}<br><small>${hm(a.dur)}</small></span><span class="lmid"><b>✓ ${esc(a.name)}</b><span>${a.dist ? distTxt(a.sport, a.dist) : NAME[a.sport]}</span></span></button>` }))].sort((a, b) => a.t - b.t);
  const allday = train.filter(p => p.allDay);
  h += `<div class="card"><h3>${icon('timer', 16)} Tagesablauf</h3>${allday.map(p => `<button class="ev ${p.kind}" style="--c:${pColor(p)};font-size:13px;padding:6px 10px" data-act="edit:${ref(p)}">${esc(p.title)}</button>`).join('')}
    ${items.length ? `<div class="timeline">${items.map((x, i) => (off === 0 && x.t > NOW && (i === 0 || items[i - 1].t <= NOW) ? '<div class="nowmark"><span>jetzt ' + time(NOW) + '</span></div>' : '') + x.html).join('')}</div>` : '<span class="muted">Nichts eingetragen.</span>'}
    <div class="row" style="flex-wrap:wrap"><button class="btn" data-act="new:${at(day, 17).getTime()}">${icon('plus', 14)} Training planen</button><button class="btn" data-act="hwadd">${icon('plus', 14)} Hausaufgabe</button><button class="btn" data-act="newk:event|${at(day, 15).getTime()}">${icon('cal', 14)} Termin</button></div></div>`;
  // Hausaufgaben & Prüfungen
  const open = hwOpen().slice(0, 8);
  if (open.length || ex.length) h += `<div class="cols two">${open.length ? `<div class="card"><h3>${icon('check', 16)} Hausaufgaben <small>${hwOpen().length} offen</small></h3>${open.map(hwRow).join('')}<div><button class="linkbtn" data-act="nav:school">Alle anzeigen</button></div></div>` : ''}${ex.length ? `<div class="card"><h3>📝 Prüfungen <small>nächste 14 Tage</small></h3>${ex.map(examRow).join('')}</div>` : ''}</div>`;
  if (!schoolOn()) h += `<div class="card">${empty('Stundenplan verbinden', 'Hol dir deinen WebUntis-Stundenplan mit Ausfall, Vertretung, Hausaufgaben und Prüfungen in TriCoach – einmal einrichten, danach aktualisiert er sich alle 30 Minuten.', `<button class="btn primary" data-act="nav:settings#schule">${icon('school', 14)} Einrichten</button>`)}</div>`;
  else if (SCH.err) h += `<div class="card"><span class="cap warnc">${esc(SCH.err)}</span></div>`;
  return h;
}
function hwRow(h) {
  const d = Math.round((h.dueD - TODAY) / DAY), when = d < 0 ? `seit ${-d} ${-d === 1 ? 'Tag' : 'Tagen'} fällig` : d === 0 ? 'heute' : d === 1 ? 'morgen' : `${h.dueD.toLocaleDateString('de-DE', { weekday: 'short', day: 'numeric', month: 'numeric' })}`;
  return `<div class="hw ${h.isDone ? 'done' : ''} ${d < 0 && !h.isDone ? 'late' : ''}"><button class="hwcheck" data-act="hwtoggle:${h.key}" aria-label="${h.isDone ? 'Als offen markieren' : 'Erledigt'}">${h.isDone ? ICON.check : ''}</button><div><b>${esc(subjName(h.su))}${h.src === 'own' ? ' <span class="cap">(eigene)</span>' : ''}</b><span class="fg">${esc(h.text)}</span>${h.remark ? `<span class="cap">${esc(h.remark)}</span>` : ''}</div><span class="cap hwdue">${when}${h.src === 'own' ? `<br><button class="linkbtn" data-act="hwdel:${h.key}">löschen</button>` : ''}</span></div>`;
}
const examRow = x => `<div class="ins"><span class="dot" style="background:var(--bad)"></span><div><b>${esc(x.name || x.type || 'Prüfung')}${x.su ? ' · ' + esc(subjName(x.su)) : ''}</b><span>${x.date.toLocaleDateString('de-DE', { weekday: 'long', day: 'numeric', month: 'long' })}${x.s ? ', ' + x.s + (x.e ? '–' + x.e : '') : ''}${x.ro ? ' · ' + esc(x.ro) : ''}${x.text ? ' · ' + esc(x.text) : ''}</span></div></div>`;

/* ---------- Schule: Wochenplan, Änderungen, Hausaufgaben, Prüfungen ---------- */
function vSchool() {
  let h = header('Schule');
  if (!schoolOn()) return h + `<div class="card">${empty('Noch kein Stundenplan', 'In den Einstellungen unter „Schule“ verbindest du WebUntis. Eigene Hausaufgaben kannst du schon jetzt eintragen.', `<div class="row" style="flex-wrap:wrap"><button class="btn primary" data-act="nav:settings#schule">Einrichten</button><button class="btn" data-act="hwadd">${icon('plus', 14)} Hausaufgabe</button></div>`)}</div>` + (SCH.own.length ? `<div class="card"><h3>Hausaufgaben</h3>${hwList().sort((a, b) => a.dueD - b.dueD).map(hwRow).join('')}</div>` : '');
  const ws = addDays(weekStart(TODAY), 7 * (S.schoolWeek || 0)), days = Array.from({ length: 5 }, (_, i) => addDays(ws, i));
  const st = new Date(SCH.data.at), hr = new Date().getHours(), age = hr >= 7 && hr < 23 ? (Date.now() - st) / 60000 : 0;   // nachts läuft der Job nicht – dann keine Warnung
  h += `<div class="row" style="justify-content:space-between;flex-wrap:wrap"><span class="cap ${age > 90 ? 'warnc' : ''}">Stand ${st.toLocaleString('de-DE', { weekday: 'short', hour: '2-digit', minute: '2-digit' })}${age > 90 ? ' – der GitHub-Job hat länger nicht aktualisiert' : ''}${SCH.data.err?.length ? ' · ' + esc(SCH.data.err.join(' | ')) : ''}</span><button class="btn small ${SCH.busy ? 'on' : ''}" data-act="schoolsync">${icon('sync', 14)} Aktualisieren</button></div>`;
  const ch = schoolChanges(TODAY, addDays(TODAY, 7));
  if (ch.length) h += `<div class="card"><h3>${icon('bell', 16, 'var(--warn)')} Änderungen <small>nächste 7 Tage</small></h3>${ch.map(l => `<div class="chgday"><span class="cap">${l.day.toLocaleDateString('de-DE', { weekday: 'short', day: 'numeric', month: 'numeric' })}</span>${lessonRow(l)}</div>`).join('')}</div>`;
  // Wochenplan
  const slots = [...new Set(days.flatMap(d => lessonsOn(d).map(l => l.s)))].sort();
  h += `<div class="card"><div class="row" style="justify-content:space-between"><button class="btn" data-act="schoolweek:-1" aria-label="Vorherige Woche">‹</button><h3>KW ${kw(ws)} · ${ws.toLocaleDateString('de-DE', { day: 'numeric', month: 'short' })} – ${addDays(ws, 4).toLocaleDateString('de-DE', { day: 'numeric', month: 'short' })}</h3><button class="btn" data-act="schoolweek:1" aria-label="Nächste Woche">›</button></div>
    <div class="sgrid" style="--n:5"><div></div>${days.map(d => `<div class="sgh ${sameDay(d, TODAY) ? 'now' : ''}">${WD[(d.getDay() + 6) % 7]} <b>${d.getDate()}.</b></div>`).join('')}
    ${slots.map(s => `<div class="sgt">${s}</div>${days.map(d => { const l = lessonsOn(d).filter(x => x.s === s); return `<div class="sgc">${l.map(x => `<button class="sgl ${x.code === 'cancelled' ? 'cancel' : x.code || x.subst ? 'chg' : ''}" data-act="lesson:${x.d}|${x.s}"><b>${esc(x.su)}</b><span>${esc(x.ro)}</span></button>`).join('')}</div>`; }).join('')}`).join('')}</div>
    <div class="legend"><span><i style="background:var(--school)"></i>normal</span><span><i style="background:var(--warn)"></i>Vertretung/Änderung</span><span><i style="background:var(--bad)"></i>Entfall</span></div></div>`;
  const all = hwList().sort((a, b) => a.isDone - b.isDone || a.dueD - b.dueD).filter(x => !x.isDone || x.dueD >= addDays(TODAY, -7));
  h += `<div class="cols two"><div class="card"><h3>${icon('check', 16)} Hausaufgaben <small>${hwOpen().length} offen</small></h3>${all.length ? all.map(hwRow).join('') : '<span class="muted">Keine Hausaufgaben 🎉</span>'}<div class="row" style="flex-wrap:wrap"><button class="btn" data-act="hwadd">${icon('plus', 14)} Eigene Hausaufgabe</button>${hwOpen().length ? `<button class="btn" data-act="hwics">${icon('share', 14)} In Apple Kalender</button>` : ''}</div></div>
    <div class="card"><h3>📝 Prüfungen</h3>${examsAhead(120).length ? examsAhead(120).map(examRow).join('') : '<span class="muted">Keine Prüfungen eingetragen.</span>'}${examsAhead(120).length ? `<div><button class="btn" data-act="exics">${icon('share', 14)} In Apple Kalender</button></div>` : ''}</div></div>`;
  return h;
}

/* Zahl am App-Symbol (iPhone ab iOS 16.4, wenn Mitteilungen erlaubt): fällige Hausaufgaben bis morgen + Stundenplan-Änderungen heute/morgen */
let lastBadge = -1;
function updateBadge() {
  if (!('setAppBadge' in navigator)) return;
  const n = hwOpen().filter(h => h.dueD >= TODAY && h.dueD <= addDays(TODAY, 1)).length + (SCH.data ? schoolChanges(TODAY, addDays(TODAY, 2)).filter(l => l.code).length : 0);
  if (n === lastBadge) return; lastBadge = n;
  (n ? navigator.setAppBadge(n) : navigator.clearAppBadge()).catch(() => { });
}

/* ---------- Sheets ---------- */
function lessonSheet() {
  const [d, s] = S.sheet.k.split('|'), l = lessonsOn(new Date(d + 'T00:00:00')).find(x => x.s === s); if (!l) return '';
  const hw = hwList().filter(h => h.su === l.su && (h.due === d || h.date === d));
  const row = (k, v) => v ? `<div class="frow"><span>${k}</span><b style="text-align:right">${esc(v)}</b></div>` : '';
  return sheetWrap(esc(subjName(l.su, l.sul)), `${l.code === 'cancelled' ? '<div class="ins"><span class="dot" style="background:var(--bad)"></span><div><b>Entfall</b><span>Diese Stunde fällt aus.</span></div></div>' : l.code === 'irregular' ? `<div class="ins"><span class="dot" style="background:var(--warn)"></span><div><b>${esc(l.subst || 'Änderung')}</b><span>Abweichend vom normalen Stundenplan.</span></div></div>` : ''}
    <div class="fgroup">${row('Wann', `${new Date(d + 'T00:00:00').toLocaleDateString('de-DE', { weekday: 'long', day: 'numeric', month: 'long' })}, ${l.s}–${l.e}`)}${row('Raum', l.roOrg ? `${l.ro} (statt ${l.roOrg})` : l.ro)}${row('Lehrkraft', l.teOrg ? `${l.te} (statt ${l.teOrg})` : l.te)}${row('Text', l.ls)}</div>
    ${l.info ? `<div class="card"><h3>Info der Lehrkraft</h3><span class="fg" style="white-space:pre-wrap">${esc(l.info)}</span></div>` : ''}${hw.length ? `<div class="card"><h3>Hausaufgaben</h3>${hw.map(hwRow).join('')}</div>` : ''}`, false);
}
function hwSheet() {
  const d = S.sheet.d, subs = [...new Set((SCH.data?.lessons || []).map(l => l.su))].sort();
  return sheetWrap('Hausaufgabe', fg([frow('Fach', `<input name="h-su" list="hwsubs" value="${esc(d.su)}" placeholder="z. B. Mathe" autocomplete="off">${subs.length ? `<datalist id="hwsubs">${subs.map(x => `<option value="${esc(x)}">${esc(subjName(x))}</option>`).join('')}</datalist>` : ''}`), frow('Fällig am', `<input type="date" name="h-due" value="${d.due}">`), `<textarea name="h-text" rows="3" placeholder="Was ist zu tun?" required>${esc(d.text)}</textarea>`]) + '<span class="cap">Eigene Hausaufgaben bleiben nur in TriCoach – nicht in TrainingPeaks.</span>', 'hwform');
}
function saveHw() {
  const f = document.getElementById('hwform'), v = n => f.elements[n].value.trim();
  if (!v('h-text')) { toast('Bitte eintragen, was zu tun ist'); return; }
  SCH.own.push({ id: 'h' + Date.now().toString(36), su: v('h-su'), text: v('h-text'), remark: '', date: isoDay(TODAY), due: v('h-due') || isoDay(addDays(TODAY, 1)), done: false });
  saveSch(); S.sheet = null; render(); toast('Hausaufgabe eingetragen');
}

/* ---------- Apple Kalender ---------- */
function hwIcs() {
  const items = hwOpen().map(h => ({ id: 'hw-' + h.key, kind: 'event', title: `📚 ${subjName(h.su)}: ${h.text.slice(0, 60)}`, date: h.dueD, allDay: true, days: 1, notes: [h.text, h.remark].filter(Boolean).join('\n'), alarm: 420 }));
  exportIcs(items, 'TriCoach-Hausaufgaben');
}
function examIcs() {
  const items = examsAhead(120).map(x => ({ id: 'ex-' + x.id, kind: 'event', title: `📝 ${x.name || 'Prüfung'}${x.su ? ' · ' + subjName(x.su) : ''}`, date: x.date, min: x.e ? (lessonDate(x.d, x.e) - x.date) / 60000 : 90, location: x.ro, notes: x.text, alarm: 2880, alarm2: 10080 }));
  exportIcs(items, 'TriCoach-Pruefungen');
}

/* ---------- Einstellungen ---------- */
function newSchoolKey() { const a = crypto.getRandomValues(new Uint8Array(18)); return btoa(String.fromCharCode(...a)).replace(/[+/=]/g, c => ({ '+': 'x', '/': 'y', '=': '' }[c])); }
/* Liegen die verschlüsselten Zugangsdaten schon im Repo? (dann braucht GitHub nur das Secret TRICOACH_KEY) */
async function checkZugang() {
  if (SCH.zugang != null || SCH.zugangBusy) return;
  SCH.zugangBusy = true;
  try { const r = await fetch(schoolUrl().replace('/schule-daten/schule.enc', '/main/tools/untis-zugang.enc') + '?t=' + Date.now(), { cache: 'no-store' }); SCH.zugang = r.ok; }
  catch (e) { SCH.zugang = false; }
  SCH.zugangBusy = false; if (S.view === 'settings') render();
}
/* Text für das GitHub-Secret UNTIS_ZUGANG aus den Angaben in WebUntis bauen (bleibt nur im Formular, wird nicht gespeichert) */
function zugangText() {
  const g = id => (document.getElementById(id)?.value || '').trim();
  const url = g('z-url').replace(/^https?:\/\//i, '').replace(/\/.*$/, ''), school = g('z-school'), user = g('z-user'), key = g('z-key').replace(/\s+/g, '').toUpperCase();
  if (!url || !school || !user || !key) return null;
  return `untis://setschool?url=${encodeURIComponent(url)}&school=${encodeURIComponent(school)}&user=${encodeURIComponent(user)}&key=${encodeURIComponent(key)}${g('z-nr') ? '&schoolNumber=' + encodeURIComponent(g('z-nr')) : ''}`;
}
function schoolSettingsCard() {
  checkZugang();
  const repoUrl = schoolUrl().replace('https://raw.githubusercontent.com/', 'https://github.com/').replace(/\/schule-daten\/schule\.enc$/, '');
  const hints = SCH.data?.err?.length ? `<div class="ins"><span class="dot" style="background:var(--warn)"></span><div><b>Hinweis vom letzten Abruf</b><span>${SCH.data.err.map(esc).join('<br>')}</span></div></div>` : '';
  const zOk = SCH.zugang === true;
  return `<div class="card" id="schule"><h3>${icon('school')} Schule (WebUntis) <small>${schoolOn() ? 'verbunden · Stand ' + new Date(SCH.data.at).toLocaleString('de-DE', { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' }) : 'nicht verbunden'}</small></h3>
    <span class="cap fg">Stundenplan mit Entfall und Vertretung, Infos der Lehrkräfte, Hausaufgaben und Prüfungen. Ein kleiner Job in deinem GitHub-Repo meldet sich alle 30 Minuten (6–22 Uhr) mit deinem <b>WebUntis-App-Schlüssel</b> an – genau wie die Untis-App, also auch an Schulen mit „Mit Microsoft anmelden“ – und legt die Daten verschlüsselt ab. Lesen kann sie nur TriCoach mit deinem Schlüssel.</span>
    <div class="opt"><b>1 · TriCoach-Schlüssel</b><form id="schoolkey" class="plan"><label style="grid-column:1/-1">Schlüssel (auf allen deinen Geräten gleich eintragen)<input id="sk" value="${esc(SCH.key)}" autocomplete="off" spellcheck="false"></label><button class="btn" type="button" data-act="skgen">Neu erzeugen</button><button class="btn" type="button" data-act="skcopy">Kopieren</button><button class="btn primary" type="submit">Speichern</button></form>
      <span class="cap">Nicht neu erzeugen, wenn alles schon läuft – sonst passt er nicht mehr zum GitHub-Secret.</span></div>
    <div class="opt ${zOk ? 'on' : ''}"><b>2 · WebUntis-Zugang ${zOk ? '<span class="tag">✓ liegt verschlüsselt im Repo</span>' : ''}</b>
      ${zOk ? `<span class="cap fg">Deine Zugangsdaten liegen verschlüsselt in <code>tools/untis-zugang.enc</code>. GitHub braucht deshalb nur noch das Secret <code>TRICOACH_KEY</code>.</span>` : `<span class="cap fg">In WebUntis (Browser) oben rechts auf deinen Namen → <b>Profil → Freigaben → Zugriff über Untis Mobile → Anzeigen</b>. Neben dem QR-Code stehen <b>Server/URL, Schule, Benutzer, Schlüssel</b> (und Schulnummer). Hier eintragen, dann den fertigen Text als Secret <code>UNTIS_ZUGANG</code> in GitHub einfügen. Die Angaben werden in TriCoach nicht gespeichert.</span>
      <form id="zugang" class="plan" onsubmit="return false"><label>Server / URL<input id="z-url" placeholder="z. B. neilo.webuntis.com" autocomplete="off" spellcheck="false"></label><label>Schule<input id="z-school" placeholder="z. B. fev-bremen" autocomplete="off" spellcheck="false"></label><label>Benutzer<input id="z-user" autocomplete="off" spellcheck="false"></label><label>Schlüssel<input id="z-key" placeholder="16 Zeichen, A–Z und 2–7" autocomplete="off" spellcheck="false"></label><label>Schulnummer <em class="cap">optional</em><input id="z-nr" inputmode="numeric" autocomplete="off"></label><button class="btn primary" type="button" data-act="zcopy">Text für GitHub kopieren</button></form>`}</div>
    <div class="opt"><b>3 · In GitHub eintragen <span class="tag">einmalig</span></b><ol class="steps">
      <li><a href="${repoUrl}/settings/secrets/actions/new" target="_blank" rel="noopener">Repo → Settings → Secrets and variables → Actions → New repository secret</a>.</li>
      <li>Name <code>TRICOACH_KEY</code>, Wert = dein Schlüssel aus Schritt 1 → <b>Add secret</b>.</li>
      ${zOk ? '' : '<li>Noch einmal <b>New repository secret</b>: Name <code>UNTIS_ZUGANG</code>, Wert = der kopierte Text aus Schritt 2.</li>'}
      <li><a href="${repoUrl}/actions/workflows/schule.yml" target="_blank" rel="noopener">Actions → „Schule (WebUntis)“</a> → <b>Run workflow</b> → grüner Button. Nach ca. 1 Minute hier „Jetzt abrufen“.</li></ol>
      <span class="cap">Erzeugst du in WebUntis die Freigabe neu, ändert sich der Schlüssel – dann Schritt 2 wiederholen. GitHub pausiert geplante Jobs, wenn 60 Tage nichts im Repo passiert; dann einmal „Run workflow“ drücken.</span>
      <div class="row" style="flex-wrap:wrap"><button class="btn primary" data-act="schoolsync">${icon('sync', 14)} Jetzt abrufen</button>${schoolOn() ? `<button class="btn" data-act="schooloff">Trennen</button>` : ''}</div>${SCH.err ? `<span class="cap warnc">${esc(SCH.err)}</span>` : ''}${hints}</div>
    <div class="opt"><b>Apple Kalender</b><span class="cap fg"><b>Stundenplan:</b> In WebUntis → <b>Profil → Freigaben → „Kalender veröffentlichen“</b> (bzw. in der Untis-App Kalender → Abo) den iCal-Link kopieren, dann am iPhone in der <b>Kalender-App → Kalender → Kalender hinzufügen → Kalenderabo hinzufügen</b> einfügen. Der Stundenplan aktualisiert sich dort selbst. <b>Hausaufgaben & Prüfungen:</b> in TriCoach unter Schule „In Apple Kalender“ – mit Erinnerung am Vorabend bzw. 2 Tage und 1 Woche vorher.</span></div></div>`;
}
