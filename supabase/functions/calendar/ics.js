// TriCoach – Kalender-Datei (.ics) bauen. Reines JavaScript, läuft in Deno (Supabase) und Node (Tests).

const SPORT = { swim: 'Schwimmen', bike: 'Rad', run: 'Laufen', strength: 'Athletik', other: 'Sonstiges' };
const ICON = { swim: '🏊', bike: '🚴', run: '🏃', strength: '🏋️', other: '⚡' };

/** Text für ICS maskieren (RFC 5545, Abschnitt 3.3.11) */
export function escapeText(s) {
  return String(s ?? '')
    .replace(/\\/g, '\\\\')
    .replace(/;/g, '\\;')
    .replace(/,/g, '\\,')
    .replace(/\r?\n/g, '\\n');
}

/** Zeilen über 75 Byte falten – ohne UTF-8-Zeichen zu zerreißen */
export function fold(line) {
  const enc = new TextEncoder();
  if (enc.encode(line).length <= 75) return line;
  const out = [];
  let cur = '', bytes = 0, limit = 75;
  for (const ch of line) {
    const b = enc.encode(ch).length;
    if (bytes + b > limit) { out.push(cur); cur = ''; bytes = 0; limit = 74; }
    cur += ch; bytes += b;
  }
  out.push(cur);
  return out.join('\r\n ');
}

/** Datum → 20261024T150000Z */
export function utc(d) {
  const x = new Date(d);
  return x.toISOString().replace(/[-:]/g, '').replace(/\.\d{3}/, '');
}
const dateOnly = d => { const x = new Date(d); return `${x.getUTCFullYear()}${String(x.getUTCMonth() + 1).padStart(2, '0')}${String(x.getUTCDate()).padStart(2, '0')}`; };

function km(sport, m) {
  if (!m) return '';
  const v = m / 1000;
  return (sport === 'swim' ? v.toFixed(2) : v.toFixed(1)).replace('.', ',') + ' km';
}
function hm(sec) {
  const m = Math.round(sec / 60);
  return m >= 60 ? `${Math.floor(m / 60)}:${String(m % 60).padStart(2, '0')} h` : `${m} min`;
}

/** Absolvierte Einheit → VEVENT-Zeilen */
export function activityEvent(a, stamp) {
  const sportName = a.sport === 'other' && a.art ? a.art : SPORT[a.sport] || 'Training';
  const title = `✓ ${ICON[a.sport] || ''} ${a.name || sportName}`.replace(/\s+/g, ' ').trim();
  const desc = [
    `${sportName} · ${hm(a.duration_s)}${a.distance_m ? ' · ' + km(a.sport, a.distance_m) : ''}`,
    a.avg_hr ? `Ø Puls ${a.avg_hr}` : '',
    a.rpe ? `RPE ${a.rpe}/10` : '',
    a.tss ? `TSS ${Math.round(a.tss)}` : '',
    a.notes || ''
  ].filter(Boolean).join('\n');
  const start = new Date(a.start_at);
  const end = new Date(start.getTime() + Math.max(60, a.duration_s) * 1000);
  return [
    'BEGIN:VEVENT',
    `UID:act-${a.id}@tricoach.app`,
    `DTSTAMP:${utc(stamp)}`,
    `DTSTART:${utc(start)}`,
    `DTEND:${utc(end)}`,
    `SUMMARY:${escapeText(title)}`,
    `DESCRIPTION:${escapeText(desc)}`,
    `CATEGORIES:${escapeText('TriCoach,' + sportName)}`,
    'TRANSP:OPAQUE',
    'END:VEVENT'
  ];
}

/** Geplante Einheit / Termin / Wettkampf → VEVENT-Zeilen */
export function plannedEvent(p, stamp) {
  const sportName = p.sport ? SPORT[p.sport] : '';
  const prefix = p.kind === 'race' ? `🏁 ${p.race_prio ? p.race_prio + '-Wettkampf: ' : ''}` : p.kind === 'workout' ? `${ICON[p.sport] || '📅'} ` : '';
  const title = `${prefix}${p.title || sportName || 'Termin'}`;
  const desc = [p.minutes ? `Geplant: ${hm(p.minutes * 60)}${p.distance_m ? ' · ' + km(p.sport, p.distance_m) : ''}` : '', p.notes || ''].filter(Boolean).join('\n');
  const start = new Date(p.starts_at);
  const lines = ['BEGIN:VEVENT', `UID:plan-${p.id}@tricoach.app`, `DTSTAMP:${utc(stamp)}`];
  if (p.all_day) {
    lines.push(`DTSTART;VALUE=DATE:${dateOnly(start)}`, `DTEND;VALUE=DATE:${dateOnly(new Date(start.getTime() + 86400000))}`);
  } else {
    const end = new Date(start.getTime() + Math.max(15, p.minutes || 60) * 60000);
    lines.push(`DTSTART:${utc(start)}`, `DTEND:${utc(end)}`);
  }
  lines.push(`SUMMARY:${escapeText(title)}`);
  if (desc) lines.push(`DESCRIPTION:${escapeText(desc)}`);
  lines.push(`CATEGORIES:${escapeText('TriCoach,' + (p.kind === 'race' ? 'Wettkampf' : 'Plan'))}`);
  if (p.kind === 'workout' && !p.all_day) {
    // Erinnerung 1 h vorher
    lines.push('BEGIN:VALARM', 'ACTION:DISPLAY', `DESCRIPTION:${escapeText(title)}`, 'TRIGGER:-PT1H', 'END:VALARM');
  }
  lines.push('END:VEVENT');
  return lines;
}

/** Komplette Kalender-Datei */
export function buildCalendar({ name = 'TriCoach', activities = [], planned = [], now = new Date() }) {
  const lines = [
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//TriCoach//Training//DE',
    'CALSCALE:GREGORIAN',
    'METHOD:PUBLISH',
    `X-WR-CALNAME:${escapeText(name)}`,
    'X-WR-TIMEZONE:Europe/Berlin',
    'REFRESH-INTERVAL;VALUE=DURATION:PT1H',
    'X-PUBLISHED-TTL:PT1H'
  ];
  for (const p of planned) if (!p.deleted_at) lines.push(...plannedEvent(p, now));
  for (const a of activities) if (!a.deleted_at) lines.push(...activityEvent(a, now));
  lines.push('END:VCALENDAR');
  return lines.map(fold).join('\r\n') + '\r\n';
}
