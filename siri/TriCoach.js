// TriCoach für Siri, Kurzbefehle und Widget – läuft in der kostenlosen iOS-App „Scriptable“.
// Einrichten: in TriCoach → Einstellungen → „Siri & Kurzbefehle“. Dieses Skript aktualisiert sich selbst.
//
// Befehle (als Text an das Skript, per Siri, Kurzbefehl oder scriptable:///run/TriCoach?cmd=…):
//   heute · morgen · übermorgen · montag … sonntag   → Tagesüberblick: Schule, Training, Hausaufgaben, Prüfungen
//   woche · letzte woche                             → Wochenbilanz Schwimmen/Rad/Laufen/Athletik
//   form · bereitschaft · schlaf                     → Fitness, Ermüdung, Form, HRV, Ruhepuls, Schlaf
//   schule · stundenplan · vertretung                → Änderungen der nächsten Schultage
//   hausaufgaben · prüfungen · wettkampf · letzte einheit
//   eintragen <frei gesprochen>                      → z. B. „eintragen Lauf 45 Minuten 9 Kilometer locker“
//   hilfe
const VERSION = '1.1.0';
const IS_TEST = typeof module !== 'undefined' && module.__test;

/* ===================== Einstellungen (Schlüsselbund des iPhones) ===================== */
const CFG_KEY = 'tricoach.cfg';
function loadCfg() { try { return Keychain.contains(CFG_KEY) ? JSON.parse(Keychain.get(CFG_KEY)) : {}; } catch (e) { return {}; } }
function saveCfg(c) { Keychain.set(CFG_KEY, JSON.stringify(c)); }
let CFG = loadCfg();
const REPO = () => CFG.repo || 'jannikbuhlrich-hue/tricoach';
const RAW = branch => `https://raw.githubusercontent.com/${REPO()}/${branch}`;
const APP_URL = () => { const [o, r] = REPO().split('/'); return `https://${o}.github.io/${r}/`; };

/* ===================== Kleine Helfer ===================== */
const DAY = 86400000;
const WD = ['Sonntag', 'Montag', 'Dienstag', 'Mittwoch', 'Donnerstag', 'Freitag', 'Samstag'];
const MON = ['Januar', 'Februar', 'März', 'April', 'Mai', 'Juni', 'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember'];
const pad = n => String(n).padStart(2, '0');
const sod = d => { const x = new Date(d); x.setHours(0, 0, 0, 0); return x; };
const addDays = (d, n) => { const x = new Date(d); x.setDate(x.getDate() + n); return x; };
const iso = d => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
const isoLocal = d => `${iso(d)}T${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`;
const hhmm = d => `${d.getHours()}:${pad(d.getMinutes())}`;
const uhr = s => { const [h, m] = String(s).split(':').map(Number); return m ? `${h}:${pad(m)}` : `${h}`; };
const weekStart = d => { const x = sod(d); return addDays(x, -((x.getDay() + 6) % 7)); };
const fmt = (v, d = 0) => (Math.round(v * 10 ** d) / 10 ** d).toFixed(d).replace('.', ',');
const plural = (n, a, b) => `${n} ${n === 1 ? a : b}`;
const dur = s => { const m = Math.round(s / 60); return m >= 60 ? `${Math.floor(m / 60)} Stunde${Math.floor(m / 60) === 1 ? '' : 'n'}${m % 60 ? ' ' + (m % 60) + ' Minuten' : ''}` : `${m} Minuten`; };
const durShort = s => { const m = Math.round(s / 60); return m >= 60 ? `${Math.floor(m / 60)}:${pad(m % 60)} h` : `${m} min`; };
const list = a => a.length < 2 ? (a[0] || '') : a.slice(0, -1).join(', ') + ' und ' + a[a.length - 1];
const dayName = (d, now = new Date()) => { const n = Math.round((sod(d) - sod(now)) / DAY); return n === 0 ? 'Heute' : n === 1 ? 'Morgen' : n === 2 ? 'Übermorgen' : n === -1 ? 'Gestern' : `${WD[d.getDay()]}, ${d.getDate()}. ${MON[d.getMonth()]}`; };
const dnl = (d, now) => { const s = dayName(d, now); return /^(Heute|Morgen|Übermorgen|Gestern)$/.test(s) ? s.toLowerCase() : s; };
const SPORT = { swim: 'Schwimmen', bike: 'Rad', run: 'Laufen', strength: 'Athletik', other: 'Sonstiges' };

/* ===================== Krypto (AES-256-GCM, PBKDF2-SHA256) – reines JavaScript ===================== */
const B64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
function b64dec(s) {
  s = String(s).replace(/[^A-Za-z0-9+/_-]/g, '').replace(/-/g, '+').replace(/_/g, '/');
  const out = new Uint8Array(Math.floor(s.length * 3 / 4)); let o = 0, buf = 0, bits = 0;
  for (const ch of s) { buf = (buf << 6) | B64.indexOf(ch); bits += 6; if (bits >= 8) { bits -= 8; out[o++] = (buf >> bits) & 255; } }
  return out.subarray(0, o);
}
function b64enc(u) {
  let s = '', i = 0;
  for (; i + 2 < u.length; i += 3) { const n = (u[i] << 16) | (u[i + 1] << 8) | u[i + 2]; s += B64[n >> 18] + B64[(n >> 12) & 63] + B64[(n >> 6) & 63] + B64[n & 63]; }
  if (i < u.length) { const n = (u[i] << 16) | ((u[i + 1] || 0) << 8); s += B64[n >> 18] + B64[(n >> 12) & 63] + (i + 1 < u.length ? B64[(n >> 6) & 63] : '=') + '='; }
  return s;
}
function utf8dec(u) {
  let s = '', i = 0;
  while (i < u.length) {
    let c = u[i++];
    if (c >= 0xF0) c = ((c & 7) << 18) | ((u[i++] & 63) << 12) | ((u[i++] & 63) << 6) | (u[i++] & 63);
    else if (c >= 0xE0) c = ((c & 15) << 12) | ((u[i++] & 63) << 6) | (u[i++] & 63);
    else if (c >= 0xC0) c = ((c & 31) << 6) | (u[i++] & 63);
    s += String.fromCodePoint(c);
  }
  return s;
}
function utf8enc(s) { const out = []; for (const ch of s) { let c = ch.codePointAt(0); if (c < 128) out.push(c); else if (c < 2048) out.push(192 | c >> 6, 128 | c & 63); else if (c < 65536) out.push(224 | c >> 12, 128 | (c >> 6) & 63, 128 | c & 63); else out.push(240 | c >> 18, 128 | (c >> 12) & 63, 128 | (c >> 6) & 63, 128 | c & 63); } return new Uint8Array(out); }

/* SHA-256 (für PBKDF2-Notfallweg, wenn kein WebKit-Krypto verfügbar ist) */
const K256 = new Int32Array([0x428a2f98, 0x71374491, -0x4a3f0431, -0x164a245b, 0x3956c25b, 0x59f111f1, -0x6dc07d5c, -0x54e3a12b, -0x27f85568, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, -0x7f214e02, -0x6423f959, -0x3e640e8c, -0x1b64963f, -0x1041b87a, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da, -0x67c1aeae, -0x57ce3993, -0x4ffcd838, -0x40a68039, -0x391ff40d, -0x2a586eb9, 0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, -0x7e3d36d2, -0x6d8dd37b, -0x5d40175f, -0x57e599b5, -0x3db47490, -0x3893ae5d, -0x2e6d17e7, -0x2966f9dc, -0xbf1ca7b, 0x106aa070, 0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, -0x7b3787ec, -0x7338fdf8, -0x6f410006, -0x5baf9315, -0x41065c09, -0x398e870e]);
const H0 = [0x6a09e667, -0x4498517b, 0x3c6ef372, -0x5ab00ac6, 0x510e527f, -0x64fa9774, 0x1f83d9ab, 0x5be0cd19];
const W = new Int32Array(64);
function compress(st, m) { // st: Int32Array(8), m: Int32Array(16)
  for (let i = 0; i < 16; i++) W[i] = m[i];
  for (let i = 16; i < 64; i++) { const a = W[i - 15], b = W[i - 2]; W[i] = (((a >>> 7) | (a << 25)) ^ ((a >>> 18) | (a << 14)) ^ (a >>> 3)) + W[i - 7] + (((b >>> 17) | (b << 15)) ^ ((b >>> 19) | (b << 13)) ^ (b >>> 10)) + W[i - 16] | 0; }
  let a = st[0], b = st[1], c = st[2], d = st[3], e = st[4], f = st[5], g = st[6], h = st[7];
  for (let i = 0; i < 64; i++) {
    const t1 = h + (((e >>> 6) | (e << 26)) ^ ((e >>> 11) | (e << 21)) ^ ((e >>> 25) | (e << 7))) + ((e & f) ^ (~e & g)) + K256[i] + W[i] | 0;
    const t2 = (((a >>> 2) | (a << 30)) ^ ((a >>> 13) | (a << 19)) ^ ((a >>> 22) | (a << 10))) + ((a & b) ^ (a & c) ^ (b & c)) | 0;
    h = g; g = f; f = e; e = d + t1 | 0; d = c; c = b; b = a; a = t1 + t2 | 0;
  }
  st[0] += a; st[1] += b; st[2] += c; st[3] += d; st[4] += e; st[5] += f; st[6] += g; st[7] += h;
}
function sha256(bytes) {
  const st = new Int32Array(H0), l = bytes.length, n = ((l + 9 + 63) >> 6) << 6, buf = new Uint8Array(n);
  buf.set(bytes); buf[l] = 0x80; const bl = l * 8; buf[n - 4] = bl >>> 24; buf[n - 3] = bl >>> 16; buf[n - 2] = bl >>> 8; buf[n - 1] = bl; buf[n - 5] = Math.floor(l / 0x20000000);
  const m = new Int32Array(16);
  for (let o = 0; o < n; o += 64) { for (let i = 0; i < 16; i++) m[i] = (buf[o + 4 * i] << 24) | (buf[o + 4 * i + 1] << 16) | (buf[o + 4 * i + 2] << 8) | buf[o + 4 * i + 3]; compress(st, m); }
  const out = new Uint8Array(32); for (let i = 0; i < 8; i++) { out[4 * i] = st[i] >>> 24; out[4 * i + 1] = st[i] >>> 16; out[4 * i + 2] = st[i] >>> 8; out[4 * i + 3] = st[i]; }
  return out;
}
function pbkdf2Js(pass, salt, iter) {
  let key = utf8enc(pass); if (key.length > 64) key = sha256(key);
  const kb = new Uint8Array(64); kb.set(key);
  const pre = x => { const st = new Int32Array(H0), m = new Int32Array(16); for (let i = 0; i < 16; i++) m[i] = ((kb[4 * i] ^ x) << 24) | ((kb[4 * i + 1] ^ x) << 16) | ((kb[4 * i + 2] ^ x) << 8) | (kb[4 * i + 3] ^ x); compress(st, m); return st; };
  const ist = pre(0x36), ost = pre(0x5c);
  const hmac = msg => { // msg beliebig lang → über sha256 mit vorgeschaltetem Block
    const i1 = new Uint8Array(64 + msg.length); for (let i = 0; i < 64; i++) i1[i] = kb[i] ^ 0x36; i1.set(msg, 64);
    const ih = sha256(i1), o1 = new Uint8Array(96); for (let i = 0; i < 64; i++) o1[i] = kb[i] ^ 0x5c; o1.set(ih, 64);
    return sha256(o1);
  };
  const s1 = new Uint8Array(salt.length + 4); s1.set(salt); s1[salt.length + 3] = 1;
  const u = hmac(s1), t = new Int32Array(8), uw = new Int32Array(16);
  for (let i = 0; i < 8; i++) { uw[i] = t[i] = (u[4 * i] << 24) | (u[4 * i + 1] << 16) | (u[4 * i + 2] << 8) | u[4 * i + 3]; }
  uw[8] = 0x80000000; for (let i = 9; i < 15; i++) uw[i] = 0; uw[15] = (64 + 32) * 8;
  const st = new Int32Array(8);
  for (let k = 1; k < iter; k++) {
    st.set(ist); compress(st, uw); for (let i = 0; i < 8; i++) uw[i] = st[i];
    st.set(ost); compress(st, uw); for (let i = 0; i < 8; i++) { uw[i] = st[i]; t[i] ^= st[i]; }
  }
  const out = new Uint8Array(32); for (let i = 0; i < 8; i++) { out[4 * i] = t[i] >>> 24; out[4 * i + 1] = t[i] >>> 16; out[4 * i + 2] = t[i] >>> 8; out[4 * i + 3] = t[i]; }
  return out;
}

/* AES-256 (nur Verschlüsseln eines Blocks – GCM braucht kein Entschlüsseln) */
const SBOX = new Uint8Array(256), T0 = new Uint32Array(256), T1 = new Uint32Array(256), T2 = new Uint32Array(256), T3 = new Uint32Array(256);
(() => {
  const exp = new Uint8Array(256), log = new Uint8Array(256); let x = 1;
  for (let i = 0; i < 255; i++) { exp[i] = x; log[x] = i; x ^= (x << 1) ^ (x & 0x80 ? 0x11b : 0); x &= 255; }
  for (let i = 0; i < 256; i++) {
    let v = i ? exp[(255 - log[i]) % 255] : 0, s = v; for (let k = 0; k < 4; k++) { v = ((v << 1) | (v >> 7)) & 255; s ^= v; } s ^= 0x63; SBOX[i] = s;
    const s2 = ((s << 1) ^ (s & 0x80 ? 0x11b : 0)) & 255, s3 = s2 ^ s;
    T0[i] = ((s2 << 24) | (s << 16) | (s << 8) | s3) >>> 0; T1[i] = ((s3 << 24) | (s2 << 16) | (s << 8) | s) >>> 0; T2[i] = ((s << 24) | (s3 << 16) | (s2 << 8) | s) >>> 0; T3[i] = ((s << 24) | (s << 16) | (s3 << 8) | s2) >>> 0;
  }
})();
function aesKey(key) {
  const w = new Uint32Array(60); let rc = 1;
  for (let i = 0; i < 8; i++) w[i] = ((key[4 * i] << 24) | (key[4 * i + 1] << 16) | (key[4 * i + 2] << 8) | key[4 * i + 3]) >>> 0;
  for (let i = 8; i < 60; i++) {
    let t = w[i - 1];
    if (i % 8 === 0) { t = ((SBOX[(t >>> 16) & 255] << 24) | (SBOX[(t >>> 8) & 255] << 16) | (SBOX[t & 255] << 8) | SBOX[t >>> 24]) ^ (rc << 24); rc = ((rc << 1) ^ (rc & 0x80 ? 0x11b : 0)) & 255; }
    else if (i % 8 === 4) t = (SBOX[t >>> 24] << 24) | (SBOX[(t >>> 16) & 255] << 16) | (SBOX[(t >>> 8) & 255] << 8) | SBOX[t & 255];
    w[i] = (w[i - 8] ^ t) >>> 0;
  }
  return w;
}
function aesBlock(w, inp, out) { // inp/out: Uint32Array(4)
  let s0 = inp[0] ^ w[0], s1 = inp[1] ^ w[1], s2 = inp[2] ^ w[2], s3 = inp[3] ^ w[3], k = 4;
  for (let r = 1; r < 14; r++) {
    const t0 = T0[s0 >>> 24] ^ T1[(s1 >>> 16) & 255] ^ T2[(s2 >>> 8) & 255] ^ T3[s3 & 255] ^ w[k++];
    const t1 = T0[s1 >>> 24] ^ T1[(s2 >>> 16) & 255] ^ T2[(s3 >>> 8) & 255] ^ T3[s0 & 255] ^ w[k++];
    const t2 = T0[s2 >>> 24] ^ T1[(s3 >>> 16) & 255] ^ T2[(s0 >>> 8) & 255] ^ T3[s1 & 255] ^ w[k++];
    const t3 = T0[s3 >>> 24] ^ T1[(s0 >>> 16) & 255] ^ T2[(s1 >>> 8) & 255] ^ T3[s2 & 255] ^ w[k++];
    s0 = t0; s1 = t1; s2 = t2; s3 = t3;
  }
  const f = (a, b, c, d) => ((SBOX[a >>> 24] << 24) | (SBOX[(b >>> 16) & 255] << 16) | (SBOX[(c >>> 8) & 255] << 8) | SBOX[d & 255]) >>> 0;
  out[0] = (f(s0, s1, s2, s3) ^ w[k++]) >>> 0; out[1] = (f(s1, s2, s3, s0) ^ w[k++]) >>> 0; out[2] = (f(s2, s3, s0, s1) ^ w[k++]) >>> 0; out[3] = (f(s3, s0, s1, s2) ^ w[k++]) >>> 0;
}
function gmul(x, y) { // GF(2^128), x/y: Uint32Array(4) → Ergebnis in x
  let z0 = 0, z1 = 0, z2 = 0, z3 = 0, v0 = y[0], v1 = y[1], v2 = y[2], v3 = y[3];
  for (let i = 0; i < 128; i++) {
    if ((x[i >>> 5] >>> (31 - (i & 31))) & 1) { z0 ^= v0; z1 ^= v1; z2 ^= v2; z3 ^= v3; }
    const lsb = v3 & 1; v3 = (v3 >>> 1) | (v2 << 31); v2 = (v2 >>> 1) | (v1 << 31); v1 = (v1 >>> 1) | (v0 << 31); v0 = v0 >>> 1; if (lsb) v0 ^= 0xe1000000;
  }
  x[0] = z0 >>> 0; x[1] = z1 >>> 0; x[2] = z2 >>> 0; x[3] = z3 >>> 0;
}
function gcmDecrypt(key, iv, data) {
  if (iv.length !== 12) throw new Error('IV-Länge');
  const w = aesKey(key), ct = data.subarray(0, data.length - 16), tag = data.subarray(data.length - 16);
  const H = new Uint32Array(4); aesBlock(w, new Uint32Array(4), H);
  const rd = (u, o) => ((u[o] << 24) | (u[o + 1] << 16) | (u[o + 2] << 8) | u[o + 3]) >>> 0;
  const J0 = new Uint32Array([rd(iv, 0), rd(iv, 4), rd(iv, 8), 1]), ctr = new Uint32Array(J0), ks = new Uint32Array(4), y = new Uint32Array(4), out = new Uint8Array(ct.length);
  for (let o = 0; o < ct.length; o += 16) {
    const n = Math.min(16, ct.length - o), blk = new Uint8Array(16); blk.set(ct.subarray(o, o + n));
    y[0] ^= rd(blk, 0); y[1] ^= rd(blk, 4); y[2] ^= rd(blk, 8); y[3] ^= rd(blk, 12); gmul(y, H);
    ctr[3] = (ctr[3] + 1) >>> 0; aesBlock(w, ctr, ks);
    for (let i = 0; i < n; i++) out[o + i] = ct[o + i] ^ ((ks[i >> 2] >>> (24 - 8 * (i & 3))) & 255);
  }
  const bits = ct.length * 8; y[2] ^= Math.floor(bits / 0x100000000); y[3] ^= bits >>> 0; gmul(y, H);
  const s = new Uint32Array(4); aesBlock(w, J0, s);
  for (let i = 0; i < 16; i++) if ((((s[i >> 2] ^ y[i >> 2]) >>> (24 - 8 * (i & 3))) & 255) !== tag[i]) throw new Error('Schlüssel passt nicht');
  return out;
}
/* Schlüsselableitung: schnell über WebKit (Krypto des Systems), sonst JavaScript. Ergebnis je „Salz“ im Schlüsselbund. */
async function deriveKey(pass, saltB64) {
  const ck = 'tricoach.dk';
  try { const c = JSON.parse(Keychain.contains(ck) ? Keychain.get(ck) : 'null'); if (c && c.s === saltB64 && c.p === b64enc(sha256(utf8enc(pass))).slice(0, 12)) return b64dec(c.k); } catch (e) { }
  let k = null;
  if (typeof WebView !== 'undefined' && !(typeof config !== 'undefined' && config.runsInWidget)) {
    try {
      const wv = new WebView(); await wv.loadHTML('<html><body></body></html>', APP_URL());
      const r = await wv.evaluateJavaScript(`(async()=>{try{const e=new TextEncoder(),b=await crypto.subtle.importKey('raw',e.encode(${JSON.stringify(pass)}),'PBKDF2',false,['deriveBits']);const s=Uint8Array.from(atob(${JSON.stringify(saltB64)}),c=>c.charCodeAt(0));const k=new Uint8Array(await crypto.subtle.deriveBits({name:'PBKDF2',salt:s,iterations:120000,hash:'SHA-256'},b,256));completion(btoa(String.fromCharCode(...k)));}catch(x){completion('')}})()`, true);
      if (r) k = b64dec(r);
    } catch (e) { }
  }
  if (!k) k = pbkdf2Js(pass, b64dec(saltB64), 120000);
  Keychain.set(ck, JSON.stringify({ s: saltB64, k: b64enc(k), p: b64enc(sha256(utf8enc(pass))).slice(0, 12) }));
  return k;
}
async function decryptFile(txt, pass) {
  const o = JSON.parse(txt), key = await deriveKey(pass, o.salt);
  return JSON.parse(utf8dec(gcmDecrypt(key, b64dec(o.iv), b64dec(o.ct))));
}

/* ===================== Netz & Zwischenspeicher ===================== */
const FM = () => FileManager.local();
const cachePath = n => { const fm = FM(), dir = fm.joinPath(fm.cacheDirectory(), 'tricoach'); if (!fm.fileExists(dir)) fm.createDirectory(dir, true); return fm.joinPath(dir, n); };
function cacheGet(n, maxMin) { try { const fm = FM(), p = cachePath(n); if (!fm.fileExists(p)) return null; if (maxMin != null && Date.now() - fm.modificationDate(p).getTime() > maxMin * 60000) return null; return JSON.parse(fm.readString(p)); } catch (e) { return null; } }
function cachePut(n, v) { try { FM().writeString(cachePath(n), JSON.stringify(v)); } catch (e) { } }
async function http(url, opt = {}) {
  const r = new Request(url); r.timeoutInterval = opt.timeout || 15; r.method = opt.method || 'GET';
  r.headers = opt.headers || {}; if (opt.body != null) { r.body = typeof opt.body === 'string' ? opt.body : JSON.stringify(opt.body); r.headers['Content-Type'] = 'application/json'; }
  const txt = await r.loadString(), st = r.response ? r.response.statusCode : 0;
  return { status: st, ok: st >= 200 && st < 300, text: txt };
}
/* Verschlüsselte Datei aus dem GitHub-Branch (Schule / TrainingPeaks-Plan) */
async function encData(name, branch, file, freshMin) {
  const hit = cacheGet(name, freshMin);
  if (hit || !CFG.key) return hit || cacheGet(name);
  try {
    const r = await http(`${RAW(branch)}/${file}?t=${Math.floor(Date.now() / 60000)}`);
    if (!r.ok) return cacheGet(name);
    const d = await decryptFile(r.text, CFG.key); cachePut(name, d); return d;
  } catch (e) { if (/passt nicht/.test(e.message)) throw new Error('Der TriCoach-Schlüssel passt nicht. In TriCoach unter Siri und Kurzbefehle neu verbinden.'); return cacheGet(name); }
}
const school = () => encData('school.json', 'schule-daten', 'schule.enc', 10);
const tpPlan = () => encData('tp.json', 'tp-daten', 'tp.enc', 20);

/* intervals.icu */
const icuAuth = () => ({ Authorization: 'Basic ' + b64enc(utf8enc('API_KEY:' + CFG.icu)), Accept: 'application/json' });
async function icu(path, opt = {}) {
  if (!CFG.icu) return null;
  const r = await http('https://intervals.icu/api/v1' + path, { ...opt, headers: { ...icuAuth(), ...(opt.headers || {}) } });
  if (r.status === 401 || r.status === 403) throw new Error('intervals.icu nimmt den API-Key nicht an. In TriCoach unter Siri und Kurzbefehle neu verbinden.');
  if (!r.ok) throw new Error(`intervals.icu antwortet mit Fehler ${r.status}.`);
  try { return JSON.parse(r.text); } catch (e) { return null; }
}
async function icuCached(name, path, freshMin) { const hit = cacheGet(name, freshMin); if (hit) return hit; try { const d = await icu(path); if (d) cachePut(name, d); return d || cacheGet(name); } catch (e) { const c = cacheGet(name); if (c) return c; throw e; } }
const sportOfType = t => /swim/i.test(t) ? 'swim' : /ride|cycl|bike/i.test(t) ? 'bike' : /run/i.test(t) ? 'run' : /weight|strength|workout|crossfit|hiit|pilates|yoga/i.test(t) ? 'strength' : 'other';

/* ===================== Kalender-Daten aufbereiten ===================== */
function guessSport(t) {
  if (/schwimm|swim|🏊|freiwasser|\bcss\b|kraul/i.test(t)) return 'swim';
  if (/\brad\b|radfahr|bike|ride|cycl|🚴|zwift|\bftp\b|sweet ?spot/i.test(t)) return 'bike';
  if (/lauf|run|🏃|jog|\btrab/i.test(t)) return 'run';
  if (/athletik|kraft|stabi|core|strength|gym|mobility|🏋|yoga|zirkel/i.test(t)) return 'strength';
  return null;
}
function tpMinutes(t, strict) {
  let m = t.match(/(?:planned (?:time|duration)|geplante (?:zeit|dauer)|dauer|duration)\s*:?\s*(\d{1,2}):(\d{2})(?::\d{2})?/i) || t.match(/\b(\d{1,2}):(\d{2})(?::\d{2})?\s*h\b/i);
  if (m) return +m[1] * 60 + +m[2];
  if (strict) return null;
  if ((m = t.match(/\b(\d{2,3})\s*(?:min|minuten|')(?![a-z])/i))) return +m[1];
  if ((m = t.match(/\b(\d(?:[.,]\d+)?)\s*(?:h|std|stunden?)\b/i))) return Math.round(parseFloat(m[1].replace(',', '.')) * 60);
  return null;
}
function parseIcs(text) {
  const lines = text.replace(/\r\n[ \t]/g, '').replace(/\n[ \t]/g, '').split(/\r?\n/), out = [];
  const unesc = s => s.replace(/\\n/gi, '\n').replace(/\\([,;\\])/g, '$1');
  const dt = (v, p) => { if (/VALUE=DATE(?!-)/.test(p) || /^\d{8}$/.test(v)) return { d: new Date(+v.slice(0, 4), +v.slice(4, 6) - 1, +v.slice(6, 8)), allDay: true }; const m = v.match(/^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})?(Z)?/); if (!m) return null; return { d: m[7] ? new Date(Date.UTC(+m[1], m[2] - 1, +m[3], +m[4], +m[5])) : new Date(+m[1], m[2] - 1, +m[3], +m[4], +m[5]), allDay: false }; };
  let ev = null, alarm = false;
  for (const line of lines) {
    if (line === 'BEGIN:VEVENT') { ev = {}; continue; } if (!ev) continue;
    if (line === 'BEGIN:VALARM') { alarm = true; continue; } if (line === 'END:VALARM') { alarm = false; continue; }
    if (line === 'END:VEVENT') { if (ev.start) out.push(ev); ev = null; continue; }
    if (alarm) continue;
    const c = line.indexOf(':'); if (c < 0) continue;
    const [name, ...pr] = line.slice(0, c).split(';'), val = line.slice(c + 1), p = pr.join(';');
    if (name === 'SUMMARY') ev.summary = unesc(val); else if (name === 'DESCRIPTION') ev.desc = unesc(val); else if (name === 'LOCATION') ev.loc = unesc(val);
    else if (name === 'DTSTART') ev.start = dt(val, p); else if (name === 'DTEND') ev.end = dt(val, p); else if (name === 'UID') ev.uid = val;
  }
  return out.map(e => {
    const title = (e.summary || 'Termin').replace(/^[^\p{L}\p{N}]+/u, '').trim() || 'Termin', all = `${e.summary || ''} ${e.desc || ''}`, sport = guessSport(all);
    const race = /wettkampf|race|rennen|triathlon|marathon|🏁|ironman|70\.3/i.test(e.summary || '') && !/training|einheit/i.test(e.summary || '');
    let min = e.end && !e.start.allDay ? Math.round((e.end.d - e.start.d) / 60000) : null; const tm = tpMinutes(e.summary || '') || tpMinutes(e.desc || '', true); if (tm) min = tm;
    return { src: 'tp', title, date: e.start.d, allDay: e.start.allDay, sport: sport || (race ? null : 'other'), race, min, notes: e.desc || '', uid: e.uid || '' };
  });
}
const isRaceCat = c => /^RACE_/.test(c || '');
function icuEventItem(e) {
  const date = new Date(e.start_date_local), cat = e.category || '';
  return { src: 'icu', title: e.name || (cat === 'NOTE' ? 'Notiz' : 'Training'), date, allDay: /T00:00:00$/.test(e.start_date_local || ''), sport: e.type ? sportOfType(e.type) : guessSport(e.name || '') || 'other', race: isRaceCat(cat), prio: isRaceCat(cat) ? cat.slice(-1) : '', note: cat === 'NOTE', min: e.moving_time ? Math.round(e.moving_time / 60) : null, done: !!e.paired_activity_id, notes: e.description || '' };
}
async function plannedBetween(from, to) {
  const out = [];
  const tp = await tpPlan().catch(() => null);
  if (tp && tp.ics) parseIcs(tp.ics).forEach(p => { if (p.date >= from && p.date < to) out.push(p); });
  if (CFG.icu) {
    try { (await icuCached(`ev-${iso(from)}-${iso(to)}.json`, `/athlete/0/events?oldest=${iso(from)}&newest=${iso(addDays(to, -1))}`, 15) || []).forEach(e => { const p = icuEventItem(e); if (p.date >= from && p.date < to && !out.some(q => sameish(q, p))) out.push(p); }); } catch (e) { }
  }
  return out.sort((a, b) => a.date - b.date);
}
const sameish = (a, b) => sod(a.date).getTime() === sod(b.date).getTime() && a.title.toLowerCase().slice(0, 12) === b.title.toLowerCase().slice(0, 12);
async function activitiesBetween(from, to, freshMin = 5) {
  if (!CFG.icu) return null;
  const list = await icuCached(`act-${iso(from)}-${iso(to)}.json`, `/athlete/0/activities?oldest=${iso(from)}&newest=${iso(to)}`, freshMin) || [];
  return list.map(a => ({ id: a.id, name: a.name || '', sport: sportOfType(a.type || ''), type: a.type || '', start: new Date(a.start_date_local || a.start_date), dur: a.moving_time || a.elapsed_time || 0, dist: a.distance || 0, hr: a.average_heartrate || null, max: a.max_heartrate || null, load: a.icu_training_load || null, rpe: a.icu_rpe || a.perceived_exertion || null }))
    .filter(a => a.start >= from && a.start < addDays(to, 1)).sort((a, b) => a.start - b.start);
}

/* Schule */
const SUBJ = { M: 'Mathe', MA: 'Mathe', MAT: 'Mathe', D: 'Deutsch', DE: 'Deutsch', E: 'Englisch', EN: 'Englisch', F: 'Französisch', L: 'Latein', S: 'Spanisch', BIO: 'Biologie', BI: 'Biologie', CH: 'Chemie', PH: 'Physik', GE: 'Geschichte', EK: 'Erdkunde', POL: 'Politik', PW: 'Politik', SW: 'Sozialwissenschaften', WI: 'Wirtschaft', INF: 'Informatik', IF: 'Informatik', KU: 'Kunst', MU: 'Musik', SP: 'Sport', RE: 'Religion', ER: 'Religion', KR: 'Religion', PL: 'Philosophie', WN: 'Werte und Normen', DS: 'Darstellendes Spiel' };
function subj(su, sd) {
  if (!su) return '';
  const long = sd && (sd.lessons || []).find(l => l.su === su && l.sul && l.sul !== su); if (long) return long.sul;
  const up = String(su).toUpperCase(); if (SUBJ[up]) return SUBJ[up];
  const m = up.match(/^([A-ZÄÖÜ]+?)(?:[GLEK]\d|\d|[-_ ]).*$/) || up.match(/^([A-ZÄÖÜ]{1,4})/); if (m && SUBJ[m[1]]) return SUBJ[m[1]];
  const pre = Object.keys(SUBJ).filter(k => k.length >= 2 && up.startsWith(k)).sort((a, b) => b.length - a.length)[0];
  return pre ? SUBJ[pre] : su;
}
function lessonsOn(sd, day) {
  if (!sd) return [];
  const k = iso(day), ls = sd.lessons.filter(l => l.d === k).sort((a, b) => a.s.localeCompare(b.s));
  const out = [];
  for (const l of ls) { const p = out[out.length - 1]; if (p && p.su === l.su && p.code === l.code && p.ro === l.ro && p.te === l.te && p.info === l.info && p.e <= l.s) p.e = l.e, p.n++; else out.push({ ...l, n: 1 }); }
  return out;
}
function hwDue(sd, day) { return (sd && sd.homework || []).filter(h => !h.done && h.due === iso(day)); }
function hwOpenList(sd) { const t = iso(sod(new Date())); return (sd && sd.homework || []).filter(h => !h.done && h.due >= t).sort((a, b) => a.due.localeCompare(b.due)); }
const examsOn = (sd, day) => (sd && sd.exams || []).filter(x => x.d === iso(day));
function schoolLine(sd, day, short) {
  const ls = lessonsOn(sd, day); if (!ls.length) return null;
  const active = ls.filter(l => l.code !== 'cancelled'), cancel = ls.filter(l => l.code === 'cancelled');
  const parts = [];
  if (!active.length) parts.push('Der ganze Unterricht fällt aus.');
  else parts.push(`Schule ${uhr(active[0].s)} bis ${uhr(active[active.length - 1].e)} Uhr${short ? '' : `, ${plural(active.reduce((s, l) => s + l.n, 0), 'Stunde', 'Stunden')}`}.`);
  if (cancel.length && active.length) parts.push(`Entfall: ${list(cancel.map(l => `${subj(l.su, sd)} um ${uhr(l.s)}`))}.`);
  const chg = active.filter(l => l.code === 'irregular' || l.subst || l.roOrg || l.teOrg);
  chg.forEach(l => parts.push(`${subj(l.su, sd)} ${uhr(l.s)}: ${[l.subst || (l.code === 'irregular' ? 'Änderung' : ''), l.roOrg ? `Raum ${l.ro} statt ${l.roOrg}` : '', l.teOrg ? `Vertretung ${l.te}` : ''].filter(Boolean).join(', ')}.`));
  active.filter(l => l.info).forEach(l => parts.push(`Info ${subj(l.su, sd)}: ${l.info.slice(0, 140)}.`));
  return parts.join(' ');
}

/* ===================== Befehle ===================== */
const WDAYS = { sonntag: 0, montag: 1, dienstag: 2, mittwoch: 3, donnerstag: 4, freitag: 5, samstag: 6 };
function dayFromText(t, now = new Date()) {
  if (/übermorgen|uebermorgen/.test(t)) return addDays(sod(now), 2);
  if (/morgen/.test(t) && !/heute morgen/.test(t)) return addDays(sod(now), 1);
  if (/gestern/.test(t)) return addDays(sod(now), -1);
  for (const [k, v] of Object.entries(WDAYS)) if (t.includes(k)) { let n = (v - now.getDay() + 7) % 7; if (n === 0 && /nächste|naechste/.test(t)) n = 7; return addDays(sod(now), n); }
  const m = t.match(/(\d{1,2})\.\s?(\d{1,2})\.?/); if (m) { const d = new Date(now.getFullYear(), +m[2] - 1, +m[1]); if (d < addDays(sod(now), -60)) d.setFullYear(d.getFullYear() + 1); return d; }
  return sod(now);
}
function detect(t) {
  t = ' ' + t.toLowerCase().replace(/[?!.]/g, ' ') + ' ';
  if (/eintrag|trag .*ein|protokollier|speicher|log /.test(t) || /\b(bin|habe|hab|war)\b.*\b(gelaufen|geschwommen|gefahren|geradelt|trainiert|gejoggt|gemacht|kiten|surfen)/.test(t)) return 'log';
  if (/hilfe|was kannst|befehle/.test(t)) return 'help';
  if (/hausaufgabe|\bha\b|aufgaben/.test(t)) return 'hw';
  if (/prüfung|pruefung|klausur|\btest\b|arbeit schreib/.test(t)) return 'exams';
  if (/wettkampf|rennen|\brace\b|triathlon/.test(t)) return 'race';
  if (/letzte (einheit|training|aktivität)|zuletzt|letztes training/.test(t)) return 'last';
  if (/form\b|fitness|bereitschaft|erholung|müde|muede|schlaf|hrv|ruhepuls|belastung/.test(t)) return 'form';
  if (/woche|wochenbilanz|kilometer|umfang|bilanz/.test(t)) return 'week';
  if (/stundenplan|vertretung|entfall|ausfall|fällt|faellt|schule/.test(t) && !/heute|morgen|tag|montag|dienstag|mittwoch|donnerstag|freitag/.test(t)) return 'school';
  return 'day';
}

async function cmdDay(text, now = new Date()) {
  const day = dayFromText(text.toLowerCase(), now), next = addDays(day, 1);
  const [sd, plan, acts] = await Promise.all([school().catch(e => ({ _err: e.message })), plannedBetween(day, next), activitiesBetween(day, day).catch(() => null)]);
  const parts = [`${dayName(day, now)}${Math.abs((sod(day) - sod(now)) / DAY) <= 2 ? ', ' + WD[day.getDay()] : ''}:`];
  if (sd && sd._err) parts.push(sd._err);
  const sl = schoolLine(sd && !sd._err ? sd : null, day); if (sl) parts.push(sl);
  const sdd = sd && !sd._err ? sd : null;
  examsOn(sdd, day).forEach(x => parts.push(`Achtung, ${x.type || 'Prüfung'} in ${subj(x.su, sdd)}${x.s ? ' um ' + uhr(x.s) : ''}${x.text && x.text !== x.type ? ': ' + x.text : ''}.`));
  const done = acts || [];
  const workouts = plan.filter(p => !p.note && !p.race), races = plan.filter(p => p.race), notes = plan.filter(p => p.note);
  races.forEach(r => parts.push(`Wettkampf: ${r.title}${r.allDay ? '' : ' um ' + hhmm(r.date)}.`));
  if (workouts.length) parts.push(`Training: ${list(workouts.map(p => `${p.title}${p.min && !/\d\s*(min|h)/i.test(p.title) ? ', ' + durShort(p.min * 60) : ''}${p.allDay ? '' : ' um ' + hhmm(p.date)}${p.done || done.some(a => a.sport === p.sport) ? ' (erledigt)' : ''}`))}.`);
  else if (!done.length && !races.length) parts.push('Kein Training geplant.');
  const extra = done.filter(a => !workouts.some(p => p.sport === a.sport));
  if (extra.length) parts.push(`Erledigt: ${list(extra.map(a => `${a.name || SPORT[a.sport]}${a.dist ? ' ' + km(a) : ''}, ${durShort(a.dur)}${a.hr ? ', Puls ' + Math.round(a.hr) : ''}`))}.`);
  notes.forEach(n => parts.push(`Notiz: ${n.title}.`));
  const hwTxt = hs => list(hs.map(h => `${subj(h.su, sdd)}: ${h.text.slice(0, 80)}`));
  const isToday = day.getTime() === sod(now).getTime(), dueSame = isToday ? [] : hwDue(sdd, day), dueNext = hwDue(sdd, addDays(day, 1));
  if (dueSame.length) parts.push(`Hausaufgaben bis dahin: ${hwTxt(dueSame)}.`);
  if (dueNext.length) parts.push(`Hausaufgaben für ${isToday ? 'morgen' : dnl(addDays(day, 1), now).replace(/,.*/, '')}: ${hwTxt(dueNext)}.`);
  return parts.join(' ');
}
const km = a => a.sport === 'swim' ? `${fmt(a.dist / 1000, 2)} Kilometer` : `${fmt(a.dist / 1000, a.sport === 'bike' ? 0 : 1)} Kilometer`;
async function cmdWeek(text, now = new Date()) {
  if (!CFG.icu) return 'Für die Wochenbilanz brauche ich deinen intervals.icu-Zugang. In TriCoach unter Siri und Kurzbefehle verbinden.';
  const last = /letzte|vorige|vergangene/.test(text), ws = addDays(weekStart(now), last ? -7 : 0), we = last ? addDays(ws, 6) : sod(now);
  const acts = await activitiesBetween(ws, we, 5), prev = await activitiesBetween(addDays(ws, -7), addDays(ws, -1), 60).catch(() => []);
  if (!acts.length) return last ? 'Letzte Woche hast du keine Einheiten erfasst.' : 'Diese Woche noch keine Einheit – heute ist ein guter Tag dafür.';
  const by = {}; acts.forEach(a => { const b = by[a.sport] || (by[a.sport] = { n: 0, dist: 0, dur: 0 }); b.n++; b.dist += a.dist; b.dur += a.dur; });
  const order = ['swim', 'bike', 'run', 'strength', 'other'].filter(s => by[s]);
  const tot = acts.reduce((s, a) => s + a.dur, 0), ptot = (prev || []).reduce((s, a) => s + a.dur, 0), load = acts.reduce((s, a) => s + (a.load || 0), 0);
  const parts = [`${last ? 'Letzte Woche' : 'Diese Woche'}: ${plural(acts.length, 'Einheit', 'Einheiten')}, ${dur(tot)}${load ? `, Belastung ${Math.round(load)}` : ''}.`];
  parts.push(order.map(s => `${SPORT[s]} ${by[s].dist ? (s === 'swim' ? fmt(by[s].dist / 1000, 2) : fmt(by[s].dist / 1000, s === 'bike' ? 0 : 1)) + ' Kilometer' : durShort(by[s].dur)}`).join(', ') + '.');
  if (ptot && !last) parts.push(`Vorwoche gesamt ${durShort(ptot)}.`);
  return parts.join(' ');
}
async function cmdForm() {
  if (!CFG.icu) return 'Für Form und Schlaf brauche ich deinen intervals.icu-Zugang. In TriCoach unter Siri und Kurzbefehle verbinden.';
  const now = new Date(), w = (await icuCached('well.json', `/athlete/0/wellness?oldest=${iso(addDays(now, -28))}&newest=${iso(now)}`, 30) || []).sort((a, b) => String(a.id).localeCompare(String(b.id)));
  if (!w.length) return 'Noch keine Wellness-Daten in intervals.icu.';
  const t = w[w.length - 1], y = w.filter(x => x.ctl != null).pop() || t, base = arr => { const v = arr.filter(x => x != null); return v.length ? v.reduce((s, x) => s + x, 0) / v.length : null; };
  const parts = [];
  if (y.ctl != null) { const tsb = Math.round(y.ctl - y.atl); parts.push(`Fitness ${Math.round(y.ctl)}, Ermüdung ${Math.round(y.atl)}, Form ${tsb > 0 ? 'plus ' : tsb < 0 ? 'minus ' : ''}${Math.abs(tsb)}.`); parts.push(tsb < -30 ? 'Du bist sehr ermüdet – heute nur locker oder Pause.' : tsb < -10 ? 'Gute Trainingsbelastung, auf Erholung achten.' : tsb <= 5 ? 'Ausgeglichen – normales Training passt.' : 'Frisch und erholt – gut für eine harte Einheit.'); }
  const hrv = t.hrv ?? t.hrvSDNN, hb = base(w.slice(-8, -1).map(x => x.hrv ?? x.hrvSDNN));
  if (hrv) parts.push(`HRV ${Math.round(hrv)}${hb ? (hrv < hb * 0.9 ? ', unter deinem Schnitt' : hrv > hb * 1.1 ? ', über deinem Schnitt' : ', normal') : ''}.`);
  const rhr = t.restingHR, rb = base(w.slice(-8, -1).map(x => x.restingHR));
  if (rhr) parts.push(`Ruhepuls ${rhr}${rb && rhr > rb + 4 ? ', erhöht' : ''}.`);
  if (t.sleepSecs) parts.push(`Schlaf ${dur(t.sleepSecs)}${t.sleepScore ? `, Score ${t.sleepScore}` : ''}.`);
  if (t.readiness) parts.push(`Garmin-Bereitschaft ${t.readiness}.`);
  return parts.join(' ') || 'Für heute liegen noch keine Werte vor.';
}
async function cmdSchool(now = new Date()) {
  const sd = await school(); if (!sd) return 'Noch keine Schuldaten. In TriCoach unter Siri und Kurzbefehle verbinden.';
  const out = []; let d = sod(now), n = 0;
  while (n < 3 && d < addDays(now, 14)) { const ls = lessonsOn(sd, d); if (ls.length) { n++; const ch = ls.filter(l => l.code || l.subst || l.roOrg || l.teOrg || l.info); if (ch.length) out.push(`${dayName(d, now)}: ${schoolLine(sd, d, true)}`); } d = addDays(d, 1); }
  return out.length ? out.join(' ') : 'Keine Änderungen im Stundenplan für die nächsten Schultage.';
}
async function cmdHw(now = new Date()) {
  const sd = await school(); if (!sd) return 'Noch keine Schuldaten.';
  const open = hwOpenList(sd); if (!open.length) return 'Keine offenen Hausaufgaben laut Untis. 🎉';
  return `${plural(open.length, 'offene Hausaufgabe', 'offene Hausaufgaben')}: ` + open.slice(0, 6).map(h => `${subj(h.su, sd)} bis ${dnl(new Date(h.due + 'T00:00:00'), now)}: ${h.text.slice(0, 90)}`).join('. ') + '.';
}
async function cmdExams(now = new Date()) {
  const sd = await school(); if (!sd) return 'Noch keine Schuldaten.';
  const t = iso(sod(now)), ex = (sd.exams || []).filter(x => x.d >= t).sort((a, b) => a.d.localeCompare(b.d));
  if (!ex.length) return 'Keine Prüfungen eingetragen.';
  return ex.slice(0, 5).map(x => { const d = new Date(x.d + 'T00:00:00'), n = Math.round((d - sod(now)) / DAY); return `${x.type || 'Prüfung'} ${subj(x.su, sd)} ${dnl(d, now)}${n > 2 ? ` (in ${n} Tagen)` : ''}${x.s ? ' um ' + uhr(x.s) : ''}`; }).join('. ') + '.';
}
async function cmdRace(now = new Date()) {
  const plan = await plannedBetween(sod(now), addDays(now, 365)), r = plan.find(p => p.race);
  if (!r) return 'Kein Wettkampf in TrainingPeaks oder intervals.icu eingetragen.';
  const n = Math.round((sod(r.date) - sod(now)) / DAY);
  return `Nächster Wettkampf: ${r.title}${r.prio ? ` (${r.prio}-Rennen)` : ''}, ${dnl(r.date, now)}${n > 2 ? ` – noch ${n} Tage, also ${fmt(n / 7, 1)} Wochen` : ''}.`;
}
async function cmdLast() {
  if (!CFG.icu) return 'Dafür brauche ich deinen intervals.icu-Zugang.';
  const acts = await activitiesBetween(addDays(new Date(), -21), new Date(), 3), a = acts && acts[acts.length - 1];
  if (!a) return 'In den letzten drei Wochen keine Einheit gefunden.';
  return `Letzte Einheit: ${a.name || SPORT[a.sport]}, ${dnl(a.start)} um ${hhmm(a.start)}. ${durShort(a.dur)}${a.dist ? ', ' + km(a) : ''}${a.hr ? `, Puls Schnitt ${Math.round(a.hr)}${a.max ? ', maximal ' + Math.round(a.max) : ''}` : ''}${a.load ? `, Belastung ${Math.round(a.load)}` : ''}.`;
}
const HELP = 'Frag mich zum Beispiel: Was steht heute an? Was steht morgen an? Wie war meine Woche? Wie ist meine Form? Gibt es Vertretung? Welche Hausaufgaben habe ich? Wann ist die nächste Klausur? Oder sag: Eintragen Lauf 45 Minuten 9 Kilometer locker.';

/* ===================== Einheit per Sprache eintragen ===================== */
const NUMW = { null: 0, ein: 1, eine: 1, einen: 1, einem: 1, eins: 1, zwei: 2, drei: 3, vier: 4, fünf: 5, fuenf: 5, sechs: 6, sieben: 7, acht: 8, neun: 9, zehn: 10, elf: 11, zwölf: 12, zwoelf: 12, fünfzehn: 15, zwanzig: 20, dreißig: 30, dreissig: 30, vierzig: 40, fünfzig: 50, sechzig: 60, siebzig: 70, achtzig: 80, neunzig: 90, hundert: 100 };
const OTHER = [[/kite|kiten/, 'Kitesurfen', 'Kitesurf'], [/windsurf/, 'Windsurfen', 'Windsurf'], [/wellenreit|surfen|surf/, 'Surfen', 'Surfing'], [/\bsup\b|stand ?up/, 'SUP', 'StandUpPaddling'], [/wander/, 'Wandern', 'Hike'], [/spazier|gehen\b/, 'Spaziergang', 'Walk'], [/ruder/, 'Rudern', 'Rowing'], [/kletter|bouldern/, 'Klettern', 'RockClimbing'], [/yoga/, 'Yoga', 'Yoga'], [/ski\b|skifahr|langlauf/, 'Ski', 'NordicSki'], [/fußball|fussball/, 'Fußball', 'Soccer'], [/tennis/, 'Tennis', 'Tennis'], [/inline|skaten/, 'Inlineskaten', 'InlineSkate']];
function parseLog(raw, now = new Date()) {
  let t = ' ' + String(raw || '').toLowerCase().replace(/(\d),(\d)/g, '$1.$2').replace(/[!?]/g, ' ').replace(/\s+/g, ' ') + ' ';
  t = t.replace(/eineinhalb|anderthalb/g, '1.5').replace(/dreiviertel ?stunde/g, '45 minuten').replace(/(eine )?halbe stunde/g, '30 minuten').replace(/viertelstunde/g, '15 minuten');
  t = t.replace(/\b([a-zäöüß]+)und([a-zäöüß]+zig)\b/g, (m, a, b) => NUMW[a] != null && NUMW[b] != null ? String(NUMW[a] + NUMW[b]) : m);
  t = t.replace(/\b([a-zäöüß]+)\b/g, (m, w) => NUMW[w] != null && !/^ein(e[nm]?)?$/.test(w) ? String(NUMW[w]) : m).replace(/\b(eine?[nm]?) (stunde|kilometer|km|minute)/g, '1 $2');
  const o = { sport: null, art: '', dur: 0, dist: 0, rpe: null, hr: null, where: null, start: null, notes: String(raw || '').trim() };
  if (/schwimm|geschwommen|kraul|bahnen|freiwasser|\bswim/.test(t)) o.sport = 'swim';
  else if (/\brad\b|radfahr|gefahren|geradelt|radeln|rennrad|mtb|mountainbike|gravel|\bbike|rolle|zwift|indoor ?cycling|spinning/.test(t)) o.sport = 'bike';
  else if (/lauf|gelaufen|joggen|gejoggt|\brun\b|intervalle auf der bahn|tempodauerlauf/.test(t)) o.sport = 'run';
  else if (/athletik|kraft|stabi|gym|fitnessstudio|krafttraining|core|zirkel|mobility/.test(t)) o.sport = 'strength';
  else { for (const [re, art] of OTHER) if (re.test(t)) { o.sport = 'other'; o.art = art; break; } }
  if (!o.sport && /\b(training|trainiert|sport)\b/.test(t)) o.sport = 'other';
  let m;
  const take = re => { const r = t.match(re); if (r) t = t.replace(r[0], ' '); return r; };
  if ((m = take(/(\d{1,2}):(\d{2})\s*(stunden?|std|h)\b/))) o.dur = (+m[1] * 60 + +m[2]) * 60;
  if (!o.dur && (m = take(/(\d+(?:\.\d+)?)\s*(stunden?|std\.?|h)\b(?:\s*(?:und)?\s*(\d{1,2})\s*(minuten|min)\b)?/))) o.dur = Math.round((parseFloat(m[1]) * 60 + (+m[3] || 0)) * 60);
  if (!o.dur && (m = take(/(\d{1,3})\s*(minuten|minute|min|mins)\b/))) o.dur = +m[1] * 60;
  if (!o.dur && (m = take(/\b(\d{1,2}):(\d{2})\b(?!\s*uhr)/))) o.dur = (+m[1] >= 3 ? +m[1] : +m[1] * 60 + +m[2]) * 60 + (+m[1] >= 3 ? +m[2] : 0);
  if ((m = take(/(\d+(?:\.\d+)?)\s*(kilometer|km|k)\b/))) o.dist = Math.round(parseFloat(m[1]) * 1000);
  else if ((m = take(/(\d{2,5})\s*(meter|m)\b/))) o.dist = +m[1];
  if ((m = take(/(\d{1,3})\s*bahnen/))) { const pool = /50/.test(t) ? 50 : 25; if (!o.dist) o.dist = +m[1] * pool; o.where = pool; }
  if (o.sport === 'swim') { if (/freiwasser|see\b|meer|nordsee|elbe|weser/.test(t)) o.where = 'ow'; else if (/50 ?(er|m)|langbahn/.test(t)) o.where = 50; else if (/25 ?(er|m)|kurzbahn|halle|becken/.test(t)) o.where = 25; }
  if ((m = take(/(?:rpe|anstrengung|belastung|gefühl)\s*(?:von\s*)?(\d{1,2})/))) o.rpe = Math.min(10, Math.max(1, +m[1]));
  else if (/sehr locker|regeneration|ganz leicht/.test(t)) o.rpe = 2; else if (/locker|leicht|easy|ruhig|\bga ?1\b/.test(t)) o.rpe = 3; else if (/sehr hart|brutal|am limit/.test(t)) o.rpe = 9; else if (/hart|intervall|schwer|anstrengend/.test(t)) o.rpe = 7; else if (/zügig|tempo|flott/.test(t)) o.rpe = 6; else if (/mittel|moderat|normal/.test(t)) o.rpe = 5;
  if ((m = take(/(?:puls|hf|herzfrequenz)\s*(?:von|schnitt|durchschnitt|im schnitt)?\s*(\d{2,3})/))) o.hr = +m[1];
  let day = sod(now);
  if (/vorgestern/.test(t)) day = addDays(day, -2); else if (/gestern/.test(t)) day = addDays(day, -1);
  if ((m = t.match(/um (\d{1,2})(?::(\d{2})| uhr (\d{1,2})| uhr)?/))) o.start = new Date(day.getFullYear(), day.getMonth(), day.getDate(), +m[1], +(m[2] || m[3] || 0));
  else if (/heute (früh|morgen)|morgens/.test(t)) o.start = new Date(day.getFullYear(), day.getMonth(), day.getDate(), 7, 0);
  else if (/mittags/.test(t)) o.start = new Date(day.getFullYear(), day.getMonth(), day.getDate(), 12, 30);
  else if (/abends|heute abend/.test(t)) o.start = new Date(day.getFullYear(), day.getMonth(), day.getDate(), 18, 30);
  else if (day < sod(now)) o.start = new Date(day.getFullYear(), day.getMonth(), day.getDate(), 17, 0);
  else o.start = new Date(now.getTime() - (o.dur || 3600) * 1000);
  if (o.start > now) o.start = new Date(now.getTime() - (o.dur || 3600) * 1000);
  return o;
}
const ICU_TYPE = { swim: 'Swim', bike: 'Ride', run: 'Run', strength: 'WeightTraining' };
const logName = o => o.sport === 'other' ? (o.art || 'Training') : { swim: 'Schwimmen', bike: 'Radfahrt', run: 'Lauf', strength: 'Athletik' }[o.sport];
const estKcal = (sp, dur, rpe, kg = 68) => Math.round(({ swim: 8, bike: 7.5, run: 10, strength: 5, other: 6 }[sp] || 6) * (.55 + (rpe || 5) * .09) * kg * dur / 3600);
const HEALTH = { swim: 'Schwimmen', bike: 'Radfahren', run: 'Laufen', strength: 'Funktionelles Krafttraining' };
function healthPayload(o) {
  return { typ: HEALTH[o.sport] || ({ Kitesurfen: 'Wassersport', Windsurfen: 'Wassersport', Surfen: 'Surfen', SUP: 'Paddelsport', Wandern: 'Wandern', Yoga: 'Yoga', Rudern: 'Rudern', Klettern: 'Klettern' }[o.art] || 'Andere'), sport: o.sport, name: logName(o), start: `${iso(o.start)} ${pad(o.start.getHours())}:${pad(o.start.getMinutes())}`, dauer_min: Math.round(o.dur / 60), ort: o.where === 'ow' ? 'Freiwasser' : o.where ? 'Becken' : '', bahn_m: typeof o.where === 'number' ? o.where : 0, distanz_km: o.dist ? +(o.dist / 1000).toFixed(2) : 0, distanz_m: o.dist || 0, kcal: estKcal(o.sport, o.dur, o.rpe, CFG.kg || 68), rpe: o.rpe, notiz: o.notes };
}
async function cmdLog(text) {
  const body = text.replace(/^\s*(bitte\s+)?(eintragen|trag(e)?( mir)?( bitte)?( ein)?|protokollier(e|en)?|speicher(n)?|log)\b[:,]?\s*/i, '');
  if (!body.trim() && typeof Alert !== 'undefined' && !IS_TEST && config.runsInApp) { const a = new Alert(); a.title = 'Einheit eintragen'; a.message = 'z. B. „Lauf 45 Minuten 9 km locker“ oder „Kitesurfen 2 Stunden“'; a.addTextField('Was hast du trainiert?', ''); a.addAction('Eintragen'); a.addCancelAction('Abbrechen'); if (await a.presentAlert() < 0) return { text: 'Abgebrochen.' }; return cmdLog(a.textFieldValue(0)); }
  const o = parseLog(body);
  if (!o.sport) return { text: 'Welche Sportart? Sag zum Beispiel: Eintragen Lauf 45 Minuten 9 Kilometer.' };
  if (!o.dur) return { text: `Wie lange warst du ${o.sport === 'swim' ? 'schwimmen' : o.sport === 'run' ? 'laufen' : o.sport === 'bike' ? 'auf dem Rad' : 'beim Training'}? Sag zum Beispiel: ${logName(o)} 45 Minuten.` };
  const name = logName(o), sum = `${name}${o.dist ? ', ' + (o.sport === 'swim' ? fmt(o.dist / 1000, 2) : fmt(o.dist / 1000, 1)) + ' Kilometer' : ''}, ${dur(o.dur)}${o.rpe ? `, Anstrengung ${o.rpe}` : ''}`;
  const out = { text: '', health: healthPayload(o), saved: false };
  if (CFG.icu) {
    const desc = [o.notes, o.rpe ? `RPE ${o.rpe}/10` : '', o.where === 'ow' ? 'Freiwasser' : o.where ? `${o.where}-m-Bahn` : '', '(per Siri über TriCoach)'].filter(Boolean).join('\n');
    const base = { start_date_local: isoLocal(o.start), name, moving_time: o.dur, elapsed_time: o.dur, distance: o.dist || 0, description: desc, external_id: 'tricoach-siri-' + o.start.getTime() };
    if (o.hr) base.average_heartrate = o.hr;
    const type = o.sport === 'other' ? ((OTHER.find(x => x[1] === o.art) || [])[2] || 'Other') : o.sport === 'swim' && o.where === 'ow' ? 'OpenWaterSwim' : ICU_TYPE[o.sport];
    try {
      let r = await http('https://intervals.icu/api/v1/athlete/0/activities/manual', { method: 'POST', headers: icuAuth(), body: { ...base, type } });
      if (!r.ok && r.status >= 400 && r.status < 500 && r.status !== 401 && r.status !== 403) r = await http('https://intervals.icu/api/v1/athlete/0/activities/manual', { method: 'POST', headers: icuAuth(), body: { ...base, type: o.sport === 'other' ? 'Workout' : type } });
      if (r.status === 401 || r.status === 403) throw new Error('intervals.icu nimmt den API-Key nicht an.');
      if (!r.ok) throw new Error('intervals.icu Fehler ' + r.status);
      out.saved = true; out.text = `Eingetragen: ${sum}. TriCoach holt es beim nächsten Öffnen.`;
      try { const fm = FM(); fm.listContents(fm.joinPath(fm.cacheDirectory(), 'tricoach')).filter(f => /^act-/.test(f)).forEach(f => fm.remove(fm.joinPath(fm.joinPath(fm.cacheDirectory(), 'tricoach'), f))); } catch (e) { }
    } catch (e) { out.text = `Konnte nicht speichern: ${e.message} Erkannt hatte ich: ${sum}.`; }
  } else out.text = `Erkannt: ${sum}. Es geht an Apple Health und von dort zu TrainingPeaks. In der TriCoach-App erscheint es, sobald intervals.icu verbunden ist.`;
  return out;
}

/* ===================== Widget „Mein Tag“ ===================== */
async function buildWidget(now = new Date()) {
  const fam = (typeof config !== 'undefined' && config.widgetFamily) || 'medium';
  const day = now.getHours() >= 17 ? addDays(sod(now), 1) : sod(now);
  let sd = null, plan = [], acts = []; try { sd = await school(); } catch (e) { } try { plan = await plannedBetween(day, addDays(day, 1)); } catch (e) { } try { acts = await activitiesBetween(day, day) || []; } catch (e) { }
  const w = new ListWidget(); w.backgroundColor = new Color('#0b0d12'); w.setPadding(12, 14, 12, 14); w.url = 'scriptable:///run/' + encodeURIComponent(Script.name()) + '?cmd=' + (day > sod(now) ? 'morgen' : 'heute');
  const head = w.addText(`${dayName(day, now)} · ${WD[day.getDay()].slice(0, 2)} ${day.getDate()}.`); head.font = Font.boldSystemFont(fam === 'small' ? 13 : 15); head.textColor = new Color('#ffffff');
  w.addSpacer(6);
  const line = (txt, color, size = 12, bold) => { const t = w.addText(txt); t.font = bold ? Font.semiboldSystemFont(size) : Font.systemFont(size); t.textColor = new Color(color); t.lineLimit = fam === 'large' ? 3 : 1; t.minimumScaleFactor = .75; return t; };
  const ls = lessonsOn(sd, day), act = ls.filter(l => l.code !== 'cancelled');
  if (ls.length) {
    line(act.length ? `🎓 ${uhr(act[0].s)}–${uhr(act[act.length - 1].e)} · ${act.reduce((s, l) => s + l.n, 0)} Std.` : '🎓 alles fällt aus', '#c9a7ff', 12, true);
    ls.filter(l => l.code === 'cancelled').slice(0, fam === 'large' ? 4 : 1).forEach(l => line(`✕ ${subj(l.su, sd)} ${uhr(l.s)} Entfall`, '#ff5a6e', 11));
    ls.filter(l => l.code !== 'cancelled' && (l.code || l.subst || l.roOrg || l.teOrg)).slice(0, fam === 'large' ? 4 : 1).forEach(l => line(`↻ ${subj(l.su, sd)} ${uhr(l.s)} ${l.roOrg ? 'Raum ' + l.ro : l.subst || 'Änderung'}`, '#ffb020', 11));
  }
  examsOn(sd, day).forEach(x => line(`📝 ${x.type || 'Prüfung'} ${subj(x.su, sd)}`, '#ff5a6e', 12, true));
  const tr = plan.filter(p => !p.note);
  if (tr.length) tr.slice(0, fam === 'large' ? 5 : 2).forEach(p => line(`${p.race ? '🏁' : { swim: '🏊', bike: '🚴', run: '🏃', strength: '🏋️' }[p.sport] || '•'} ${p.title}${p.min && !/\d\s*(min|h)/i.test(p.title) ? ' · ' + durShort(p.min * 60) : ''}${p.done || acts.some(a => a.sport === p.sport) ? ' ✓' : ''}`, '#4dd973', 12));
  else if (acts.length) acts.slice(0, 2).forEach(a => line(`✓ ${a.name || SPORT[a.sport]} · ${durShort(a.dur)}`, '#4dd973', 12));
  else line('Kein Training geplant', '#8a91a6', 12);
  if (fam !== 'small') { const hw = hwOpenList(sd).filter(h => h.due <= iso(addDays(day, 1))); if (hw.length) line(`📚 ${hw.length} Hausaufgabe${hw.length === 1 ? '' : 'n'} fällig: ${subj(hw[0].su, sd)}`, '#ffb020', 11); }
  w.addSpacer();
  const ft = w.addText(sd ? `Stand ${hhmm(new Date(sd.at))}` : 'TriCoach'); ft.font = Font.systemFont(9); ft.textColor = new Color('#8a91a6');
  w.refreshAfterDate = new Date(Date.now() + 30 * 60000);
  return w;
}

/* ===================== Einrichtung & Selbst-Update ===================== */
function setupFrom(q) {
  try {
    const o = JSON.parse(utf8dec(b64dec(q)));
    CFG = { ...CFG, key: o.k || CFG.key || '', icu: o.i != null ? o.i : (CFG.icu || ''), repo: o.r || CFG.repo, sc: o.s || CFG.sc || 'TriCoach', kg: o.w || CFG.kg, health: o.h !== 0 };
    saveCfg(CFG); try { Keychain.remove('tricoach.dk'); } catch (e) { }
    return `TriCoach ist verbunden${CFG.key ? ' – Schule und Trainingsplan' : ''}${CFG.icu ? (CFG.key ? ' sowie' : ' –') + ' intervals.icu' : ''}. Sag jetzt zum Beispiel: Was steht morgen an?`;
  } catch (e) { return 'Der Einrichtungslink ist unvollständig. Bitte in TriCoach nochmal auf „Siri verbinden“ tippen.'; }
}
async function selfUpdate(force) {
  try {
    if (!force) { const last = +(Keychain.contains('tricoach.upd') ? Keychain.get('tricoach.upd') : 0); if (Date.now() - last < 20 * 3600000) return null; }
    Keychain.set('tricoach.upd', String(Date.now()));
    const r = await http(`${RAW('main')}/siri/TriCoach.js?t=${Date.now()}`), m = r.ok && r.text.match(/const VERSION = '([\d.]+)'/);
    if (!m) return null;
    const newer = (a, b) => { const x = a.split('.').map(Number), y = b.split('.').map(Number); for (let i = 0; i < 3; i++) if ((x[i] || 0) !== (y[i] || 0)) return (x[i] || 0) > (y[i] || 0); return false; };
    if (!newer(m[1], VERSION)) return null;
    const fm = module.filename.includes('Mobile Documents') ? FileManager.iCloud() : FileManager.local();
    fm.writeString(module.filename, r.text);
    return m[1];
  } catch (e) { return null; }
}

/* ===================== Ablauf ===================== */
async function run(input) {
  const t = String(input || '').trim(), kind = detect(t);
  switch (kind) {
    case 'log': return cmdLog(t);
    case 'help': return HELP;
    case 'hw': return cmdHw();
    case 'exams': return cmdExams();
    case 'race': return cmdRace();
    case 'last': return cmdLast();
    case 'form': return cmdForm();
    case 'week': return cmdWeek(t.toLowerCase());
    case 'school': return cmdSchool();
    default: return cmdDay(t || 'heute');
  }
}
async function main() {
  const q = args.queryParameters || {};
  if (q.setup) { const msg = setupFrom(q.setup); const a = new Alert(); a.title = 'TriCoach'; a.message = msg; a.addAction('OK'); await a.presentAlert(); Script.complete(); return; }
  if (config.runsInWidget) { Script.setWidget(await buildWidget()); Script.complete(); return; }
  let input = q.cmd || (typeof args.shortcutParameter === 'string' ? args.shortcutParameter : args.shortcutParameter && (args.shortcutParameter.text || args.shortcutParameter.befehl)) || (args.plainTexts && args.plainTexts[0]) || '';
  if (!input && config.runsInApp) {
    const upd = await selfUpdate(false); if (upd) { const u = new Alert(); u.title = 'TriCoach aktualisiert'; u.message = `Neue Version ${upd} ist installiert. Bitte das Skript einmal neu starten.`; u.addAction('OK'); await u.presentAlert(); Script.complete(); return; }
    const a = new Alert(); a.title = 'TriCoach'; a.message = `${CFG.key || CFG.icu ? 'Verbunden' : 'Noch nicht verbunden – in TriCoach unter Einstellungen → Siri & Kurzbefehle „Siri verbinden“ tippen.'} · Version ${VERSION}`;
    const opts = [['Heute', 'heute'], ['Morgen', 'morgen'], ['Woche', 'woche'], ['Form & Schlaf', 'form'], ['Stundenplan-Änderungen', 'schule'], ['Hausaufgaben', 'hausaufgaben'], ['Prüfungen', 'prüfungen'], ['Nächster Wettkampf', 'wettkampf'], ['Letzte Einheit', 'letzte einheit'], ['Einheit eintragen', 'eintragen'], ['Widget-Vorschau', '__widget'], ['Nach Update suchen', '__update']];
    opts.forEach(o => a.addAction(o[0])); a.addCancelAction('Schließen');
    const i = await a.presentSheet(); if (i < 0) { Script.complete(); return; }
    input = opts[i][1];
    if (input === '__widget') { const w = await buildWidget(); await w.presentMedium(); Script.complete(); return; }
    if (input === '__update') { const v = await selfUpdate(true); const u = new Alert(); u.title = 'TriCoach'; u.message = v ? `Version ${v} installiert – bitte neu starten.` : `Du hast die neueste Version (${VERSION}).`; u.addAction('OK'); await u.presentAlert(); Script.complete(); return; }
  } else if (!config.runsWithSiri) selfUpdate(false);
  let res;
  try { res = await run(input); } catch (e) { res = `Das hat nicht geklappt: ${e.message}`; }
  const text = typeof res === 'string' ? res : res.text;
  if (typeof res === 'object' && res.health && CFG.health !== false) Script.setShortcutOutput({ antwort: text, health: JSON.stringify(res.health), gespeichert: !!res.saved });
  else Script.setShortcutOutput(text);
  if (config.runsWithSiri) Speech.speak(text);
  else if (config.runsInApp) { const a = new Alert(); a.title = 'TriCoach'; a.message = text; a.addAction('OK'); await a.presentAlert(); }
  Script.complete();
}

if (IS_TEST) module.exports = { aesKey, aesBlock, SBOX, gmul, b64dec, b64enc, utf8dec, utf8enc, sha256, pbkdf2Js, gcmDecrypt, decryptFile, parseLog, detect, dayFromText, parseIcs, subj, lessonsOn, schoolLine, run, cmdDay, cmdWeek, cmdForm, cmdLog, cmdSchool, cmdHw, cmdExams, cmdRace, cmdLast, buildWidget, setupFrom, healthPayload, setCfg: c => { CFG = c; } };
else await main();
