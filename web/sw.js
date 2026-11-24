// Service worker do app: abre na hora a partir da 2ª vez e funciona sem internet.
//
// - O app (index, main.dart.js e partes, assets) fica num cache por versão do
//   site (__BUILD__, trocado pelo commit no deploy).
// - O motor gráfico (canvaskit/, ~7 MB) fica num cache por versão do Flutter
//   (__ENGINE__): não é baixado de novo a cada atualização do app.
// - Versão nova: instala em segundo plano e espera. A página avisa e, no
//   "Atualizar", ela assume e a página recarrega. Sem isso, entra na próxima
//   vez que o app for aberto do zero. Nunca mistura arquivos de versões
//   diferentes na mesma sessão.
const BUILD = '__BUILD__';
const ENGINE = '__ENGINE__';
const APP_CACHE = 'mt-app-' + BUILD;
const ENGINE_CACHE = 'mt-engine-' + ENGINE;

// O mínimo para abrir; o resto entra no cache quando é usado.
const CORE = [
  './',
  'index.html',
  'flutter_bootstrap.js',
  'flutter.js',
  'main.dart.js',
  'manifest.json',
  'favicon.png',
  'icons/Icon-192.png',
  'assets/AssetManifest.bin',
  'assets/AssetManifest.bin.json',
  'assets/FontManifest.json',
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(APP_CACHE).then((cache) =>
      // Um a um: um arquivo que falte não pode impedir a instalação.
      Promise.all(CORE.map((url) => cache.add(new Request(url, { cache: 'reload' })).catch(() => {}))),
    ),
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(
        keys
          .filter((k) => k.startsWith('mt-') && k !== APP_CACHE && k !== ENGINE_CACHE)
          .map((k) => caches.delete(k)),
      ),
    ).then(() => self.clients.claim()),
  );
});

self.addEventListener('message', (event) => {
  if (event.data === 'skipWaiting') self.skipWaiting();
});

self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (url.origin !== self.location.origin) return;
  // sw.js e version.json sempre da rede: é por eles que a atualização chega.
  if (url.pathname.endsWith('/sw.js') || url.pathname.endsWith('/version.json')) return;

  const isEngine = url.pathname.includes('/canvaskit/');
  const cacheName = isEngine ? ENGINE_CACHE : APP_CACHE;

  if (req.mode === 'navigate') {
    // A página do app: a do cache (instantânea); sem cache, a da rede.
    event.respondWith(
      caches.open(APP_CACHE).then((cache) =>
        cache.match('./').then((hit) => hit || fetch(req).then((res) => {
          if (res.ok) cache.put('./', res.clone());
          return res;
        })),
      ),
    );
    return;
  }

  event.respondWith(
    caches.open(cacheName).then((cache) =>
      cache.match(req, { ignoreSearch: true }).then((hit) => {
        if (hit) return hit;
        return fetch(req).then((res) => {
          if (res.ok && res.type === 'basic') cache.put(req, res.clone());
          return res;
        });
      }),
    ),
  );
});
