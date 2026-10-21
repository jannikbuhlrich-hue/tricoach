/* TriCoach – holt den TrainingPeaks-Plan über den privaten iCal-Link, verschlüsselt ihn mit TRICOACH_KEY
   und schreibt ihn nach out/tp.enc (GitHub-Job .github/workflows/tp.yml legt die Datei in den Branch „tp-daten“).
   Kein TrainingPeaks-Passwort nötig – nur der iCal-Link aus TrainingPeaks (Settings → Account → Calendar).

   Link hinterlegen (einmalig, landet nur verschlüsselt im Repo):
     TRICOACH_KEY=… node tools/tp-sync.mjs --set "webcal://www.trainingpeaks.com/ical/….ics"
   Alternativ als GitHub-Secret TP_ICAL. */
import { readFileSync, writeFileSync, existsSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { encrypt, decrypt } from './untis-sync.mjs';

const HERE = dirname(fileURLToPath(import.meta.url)), ZUGANG = join(HERE, 'tp-zugang.enc');
const KEY = (process.env.TRICOACH_KEY || '').trim();
const norm = s => String(s || '').trim().replace(/^webcal:/i, 'https:');

async function loadLink() {
  if (existsSync(ZUGANG) && KEY) {
    try { const z = await decrypt(readFileSync(ZUGANG, 'utf8'), KEY); if (z.ical) return { link: norm(z.ical), via: 'tools/tp-zugang.enc' }; }
    catch (e) { throw new Error('tools/tp-zugang.enc lässt sich mit TRICOACH_KEY nicht öffnen – stimmt das Secret?'); }
  }
  if (process.env.TP_ICAL) return { link: norm(process.env.TP_ICAL), via: 'Secret TP_ICAL' };
  return null;
}

export async function fetchIcs(link) {
  const r = await fetch(link, { headers: { 'User-Agent': 'TriCoach/2.5 (+github actions)', Accept: 'text/calendar,*/*' } });
  if (r.status === 404 || r.status === 410) throw new Error(`TrainingPeaks kennt den Link nicht (mehr) (${r.status}) – in TrainingPeaks neu kopieren.`);
  if (!r.ok) throw new Error(`TrainingPeaks antwortet mit ${r.status}`);
  const ics = await r.text();
  if (!ics.includes('BEGIN:VCALENDAR')) throw new Error('Antwort ist keine Kalenderdatei – ist das der iCal-Link?');
  return ics;
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) (async () => {
  const args = process.argv.slice(2);
  if (args[0] === '--set') {
    if (!KEY) { console.error('TRICOACH_KEY fehlt.'); process.exit(1); }
    const link = norm(args[1]);
    if (!/^https:\/\/\S+$/i.test(link)) { console.error('Bitte den iCal-Link (webcal://… oder https://…) angeben.'); process.exit(1); }
    writeFileSync(ZUGANG, await encrypt({ ical: link }, KEY));
    console.log('OK: tools/tp-zugang.enc geschrieben.');
    return;
  }
  const out = args[0] || 'out/tp.enc';
  if (!KEY) { console.log('TRICOACH_KEY fehlt – nichts zu tun.'); process.exit(0); }
  let z;
  try { z = await loadLink(); } catch (e) { console.error('Fehler:', e.message); process.exit(1); }
  if (!z) { console.log('Kein TrainingPeaks-iCal-Link hinterlegt (tools/tp-zugang.enc oder Secret TP_ICAL) – nichts zu tun.'); process.exit(0); }
  console.log('Hole TrainingPeaks-Plan · Link aus ' + z.via);
  let ics;
  try { ics = await fetchIcs(z.link); } catch (e) { console.error('Fehler:', e.message, '– der zuletzt veröffentlichte Plan bleibt erhalten.'); process.exit(1); }
  const n = (ics.match(/BEGIN:VEVENT/g) || []).length;
  mkdirSync(dirname(out), { recursive: true });
  writeFileSync(out, await encrypt({ at: new Date().toISOString(), n, ics }, KEY));
  console.log(`OK: ${n} Einträge aus TrainingPeaks.`);
})();
