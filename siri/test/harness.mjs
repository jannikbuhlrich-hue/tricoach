// Testumgebung für siri/TriCoach.js: ahmt die Scriptable-API nach (Keychain, Request, FileManager, Alert …)
import { readFileSync, mkdirSync, writeFileSync, existsSync, statSync, readdirSync, rmSync } from 'node:fs';
import { join } from 'node:path';
import vm from 'node:vm';
export function load({ routes = {}, cfg = null, now = null, widgetFamily = 'medium', cacheDir = '/tmp/tc-test-cache', runMain = false, conf = {}, args = {} } = {}) {
  rmSync(cacheDir, { recursive: true, force: true }); mkdirSync(cacheDir, { recursive: true });
  const kc = new Map(); if (cfg) kc.set('tricoach.cfg', JSON.stringify(cfg));
  const calls = [];
  class Request { constructor(u) { this.url = u; this.headers = {}; this.method = 'GET'; }
    async loadString() { calls.push({ url: this.url, method: this.method, body: this.body, headers: this.headers });
      for (const [re, fn] of Object.entries(routes)) if (new RegExp(re).test(this.url)) { const r = await fn(this); this.response = { statusCode: r.status ?? 200 }; return r.body ?? ''; }
      this.response = { statusCode: 404 }; return 'not found'; } }
  const fm = { cacheDirectory: () => cacheDir, documentsDirectory: () => cacheDir, joinPath: (a, b) => join(a, b), fileExists: p => existsSync(p), createDirectory: p => mkdirSync(p, { recursive: true }),
    readString: p => readFileSync(p, 'utf8'), writeString: (p, s) => writeFileSync(p, s), modificationDate: p => statSync(p).mtime, listContents: p => readdirSync(p), remove: p => rmSync(p) };
  const sandbox = {
    module: { __test: !runMain, exports: {}, filename: join(cacheDir, 'TriCoach.js') }, console, Uint8Array, Uint32Array, Int32Array, JSON, Math, Date: now ? fakeDate(now) : Date, String, Object, Array, Number, Promise, Error, RegExp, Map, Set, encodeURIComponent, parseFloat, parseInt, isFinite,
    Keychain: { contains: k => kc.has(k), get: k => kc.get(k), set: (k, v) => kc.set(k, v), remove: k => kc.delete(k) },
    Request, FileManager: { local: () => fm, iCloud: () => fm }, config: { runsInWidget: false, runsInApp: false, runsWithSiri: true, widgetFamily, ...conf }, args,
    Alert: class { constructor() { this.acts = []; } addAction(a) { this.acts.push(a); } addCancelAction() { } addTextField() { } async presentAlert() { sandbox._alert = this.message; return 0; } async presentSheet() { return 0; } textFieldValue() { return ''; } },
    WebView: class { async loadHTML() { } async evaluateJavaScript() { return ''; } },
    Script: { name: () => 'TriCoach', setShortcutOutput: v => { sandbox._out = v; }, complete: () => { }, setWidget: w => { sandbox._widget = w; } },
    Speech: { speak: t => { sandbox._spoken = t; } },
    ListWidget: class { constructor() { this.items = []; } addText(t) { const o = { text: t }; this.items.push(o); return o; } addSpacer() { } setPadding() { } },
    Color: class { constructor(c) { this.c = c; } }, Font: { boldSystemFont: () => 'b', systemFont: () => 'r', semiboldSystemFont: () => 's' },
  };
  const code = readFileSync(new URL('../TriCoach.js', import.meta.url), 'utf8');
  vm.createContext(sandbox);
  return vm.runInContext(`(async () => {${code}\n})()`, sandbox).then(() => ({ api: sandbox.module.exports, calls, sandbox, kc }));
}
function fakeDate(nowIso) {
  const RealDate = Date, fixed = new RealDate(nowIso).getTime();
  class D extends RealDate { constructor(...a) { if (a.length) super(...a); else super(fixed); } static now() { return fixed; } }
  return D;
}
