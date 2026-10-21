import { load } from './harness.mjs';
import { encrypt } from '../../tools/untis-sync.mjs';
import { readFileSync } from 'node:fs';
import assert from 'node:assert';
const real = readFileSync(process.argv[2], 'utf8');
const routes = { 'schule-daten/schule.enc': () => ({ body: real }), 'tp-daten': () => ({ status: 404 }) };
// 1) Einrichtung per Link
const setup = Buffer.from(JSON.stringify({ k: process.env.K, i: '', r: 'jannikbuhlrich-hue/tricoach', s: 'TriCoach', w: 68 })).toString('base64url');
let r = await load({ routes, runMain: true, conf: { runsWithSiri: false, runsInApp: true }, args: { queryParameters: { setup } } });
console.log('Setup-Alert:', r.sandbox._alert); const cfg = JSON.parse(r.kc.get('tricoach.cfg')); assert.equal(cfg.key, process.env.K);
// 2) Siri mit echten Schuldaten (Datum: Dienstag 27.10.)
r = await load({ routes, cfg, runMain: true, now: '2026-10-26T19:00:00', args: { shortcutParameter: 'Was steht morgen an?' } });
console.log('Siri sagt:', r.sandbox._spoken); assert.ok(r.sandbox._spoken.startsWith('Morgen, Dienstag'));
// 3) Widget
r = await load({ routes, cfg, runMain: true, now: '2026-10-27T07:00:00', conf: { runsInWidget: true, runsWithSiri: false } });
console.log('Widget:', r.sandbox._widget.items.map(i => i.text).join(' | '));
// 4) Eintragen ohne intervals.icu → Ausgabe für Health
r = await load({ routes, cfg, runMain: true, args: { shortcutParameter: 'eintragen Athletik 30 Minuten' } });
console.log('Ausgabe:', JSON.stringify(r.sandbox._out)); assert.ok(r.sandbox._out.health);
console.log('MAIN OK');
