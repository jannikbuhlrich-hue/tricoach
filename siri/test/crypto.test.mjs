import { load } from './harness.mjs';
import { pbkdf2Sync, createHash, webcrypto } from 'node:crypto';
import { readFileSync } from 'node:fs';
import assert from 'node:assert';
const { api } = await load();
// SHA-256
for (const s of ['', 'abc', 'x'.repeat(55), 'y'.repeat(56), 'ü€😀'.repeat(40)]) assert.equal(Buffer.from(api.sha256(api.utf8enc(s))).toString('hex'), createHash('sha256').update(s).digest('hex'), 'sha ' + s.length);
// PBKDF2
const salt = new Uint8Array([1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16]);
let t = Date.now(); const mine = api.pbkdf2Js('9xmM-test-ä', salt, 120000); const ms = Date.now() - t;
assert.equal(Buffer.from(mine).toString('hex'), pbkdf2Sync('9xmM-test-ä', Buffer.from(salt), 120000, 32, 'sha256').toString('hex'));
console.log('pbkdf2 ok', ms + 'ms');
// AES-GCM gegen WebCrypto, verschiedene Längen
for (const len of [0, 1, 15, 16, 17, 100, 5000]) {
  const key = webcrypto.getRandomValues(new Uint8Array(32)), iv = webcrypto.getRandomValues(new Uint8Array(12)), pt = webcrypto.getRandomValues(new Uint8Array(len));
  const k = await webcrypto.subtle.importKey('raw', key, 'AES-GCM', false, ['encrypt']);
  const ct = new Uint8Array(await webcrypto.subtle.encrypt({ name: 'AES-GCM', iv }, k, pt));
  assert.deepEqual(Buffer.from(api.gcmDecrypt(key, iv, ct)), Buffer.from(pt), 'gcm ' + len);
  ct[0] ^= len ? 1 : 0; if (len) assert.throws(() => api.gcmDecrypt(key, iv, ct), /passt nicht/);
}
console.log('aes-gcm ok');
// base64
const r = webcrypto.getRandomValues(new Uint8Array(101)); assert.equal(api.b64enc(r), Buffer.from(r).toString('base64')); assert.deepEqual(Buffer.from(api.b64dec(Buffer.from(r).toString('base64'))), Buffer.from(r));
// echte Schuldatei
const enc = readFileSync(process.argv[2], 'utf8');
t = Date.now(); const d = await api.decryptFile(enc, process.env.K); console.log('schule.enc entschlüsselt', d.lessons.length, 'Stunden', Date.now() - t + 'ms');
t = Date.now(); await api.decryptFile(enc, process.env.K); console.log('2. Mal (Schlüssel im Cache)', Date.now() - t + 'ms');
