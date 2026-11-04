const CACHE = 'ftpunk-web-v5';
const ASSETS = ['./', './index.html', './manifest.webmanifest', './assets/icon-256.png', './assets/icon-512.png', './src/app.mjs', './src/style.css', './src/domain.mjs', './src/training.mjs', './src/workouts.mjs', './src/city.mjs', './src/protocol.mjs', './src/bluetooth.mjs', './src/controller.mjs', './src/storage.mjs', './src/archive.mjs', './src/export.mjs', './src/intervals.mjs', './src/scene.mjs'];
self.addEventListener('install', event => event.waitUntil(caches.open(CACHE).then(cache => cache.addAll(ASSETS))));
// Never force an update into an active ride. New workers activate after old tabs close.
self.addEventListener('activate', event => event.waitUntil(caches.keys().then(keys => Promise.all(keys.filter(k => k.startsWith('ftpunk-web-') && k !== CACHE).map(k => caches.delete(k))))));
self.addEventListener('fetch', event => {
  const url = new URL(event.request.url);
  if (event.request.method !== 'GET' || url.origin !== self.location.origin || !ASSETS.some(p => new URL(p, self.registration.scope).pathname === url.pathname)) return;
  event.respondWith(fetch(event.request).then(response => { if (response.ok) { const copy = response.clone(); event.waitUntil(caches.open(CACHE).then(c => c.put(event.request, copy))); } return response; }).catch(() => caches.match(event.request)));
});
