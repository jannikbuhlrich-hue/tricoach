/* TriCoach Service Worker – Offline-Betrieb und Updates.
   Für ein Update: VERSION erhöhen (und APP_VERSION in js/core.js). */
const VERSION = 'tricoach-2.6.2';
const FILES = ['./', 'index.html', 'manifest.webmanifest', 'css/app.css',
  'js/core.js', 'js/analytics.js', 'js/demo.js', 'js/fit.js', 'js/data.js', 'js/ble.js', 'js/views.js', 'js/calendar.js', 'js/log.js', 'js/tp.js', 'js/progress.js', 'js/school.js', 'js/siri.js', 'js/settings.js', 'js/app.js',
  'icons/icon-192.png', 'icons/icon-512.png', 'icons/apple-touch-icon.png'];

self.addEventListener('install', e => { e.waitUntil(caches.open(VERSION).then(c => c.addAll(FILES))); });
self.addEventListener('activate', e => {
  e.waitUntil(caches.keys().then(keys => Promise.all(keys.filter(k => !k.startsWith(VERSION)).map(k => caches.delete(k)))).then(() => self.clients.claim()));
});
self.addEventListener('message', e => { if (e.data === 'skipWaiting') self.skipWaiting(); });
self.addEventListener('fetch', e => {
  const url = new URL(e.request.url);
  if (e.request.method !== 'GET') return;
  if (url.origin === location.origin) {
    // App-Dateien: aus dem Cache (schnell & offline), Updates kommen über eine neue VERSION
    e.respondWith(caches.match(e.request, { ignoreSearch: true }).then(r => r || fetch(e.request)));
  } else if (url.hostname.endsWith('fonts.googleapis.com') || url.hostname.endsWith('fonts.gstatic.com')) {
    e.respondWith(caches.open(VERSION + '-fonts').then(async c => { const hit = await c.match(e.request); if (hit) return hit; const r = await fetch(e.request); c.put(e.request, r.clone()); return r; }));
  }
  // intervals.icu & andere APIs: immer live aus dem Netz
});
