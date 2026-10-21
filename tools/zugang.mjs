// TriCoach – WebUntis-Zugangsdaten verschlüsselt ablegen, damit der GitHub-Job nur noch das Secret TRICOACH_KEY braucht.
// Aufruf: TRICOACH_KEY=… node tools/zugang.mjs "untis://setschool?url=…&school=…&user=…&key=…"
//     oder: TRICOACH_KEY=… node tools/zugang.mjs   (dann Zugangsdaten über die Standardeingabe, z. B. „Server: …“-Zeilen)
// Schreibt tools/untis-zugang.enc. Ohne TRICOACH_KEY lässt sich die Datei nicht öffnen.
import { writeFileSync, readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseZugang, encrypt, decrypt, totp } from './untis-sync.mjs';

const KEY = (process.env.TRICOACH_KEY || '').trim();
if (!KEY) { console.error('TRICOACH_KEY fehlt.'); process.exit(1); }
const text = process.argv[2] || readFileSync(0, 'utf8');
const z = parseZugang(text);
if (!z) { console.error('Unvollständig: Server, Schule, Benutzer und Schlüssel (oder Passwort) werden gebraucht.'); process.exit(1); }
if (z.key) totp(z.key);   // prüft, ob der Schlüssel gültig aussieht
const file = join(dirname(fileURLToPath(import.meta.url)), 'untis-zugang.enc');
writeFileSync(file, await encrypt({ ...z, at: new Date().toISOString() }, KEY) + '\n');
const back = await decrypt(readFileSync(file, 'utf8'), KEY);
console.log(`Gespeichert: ${file} · ${back.user} @ ${back.school} (${back.server}) · ${back.key ? 'App-Schlüssel' : 'Passwort'}`);
