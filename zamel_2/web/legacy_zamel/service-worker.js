const CACHE_NAME = 'zamel-shell-v2';
const PRECACHE_URLS = [
  './',
  './index.html',
  './admin.html',
  './banned.html',
  './manifest.json',
  './icon.png'
];

const CACHEABLE_EXTENSIONS = ['.css', '.js', '.mjs', '.json', '.png', '.jpg', '.jpeg', '.svg', '.webp', '.ico', '.woff', '.woff2', '.ttf', '.eot'];
const CACHEABLE_ORIGINS = ['https://unpkg.com', 'https://cdnjs.cloudflare.com', 'https://cdn.jsdelivr.net', 'https://www.gstatic.com'];

function isLikelyApiRequest(url) {
  return url.pathname.includes('/api/') ||
    url.pathname.includes('/firestore') ||
    url.pathname.includes('/googleapis') ||
    url.hostname.includes('firebaseio.com') ||
    url.hostname.includes('firebaseapp.com') ||
    url.hostname.includes('googleapis.com') ||
    url.hostname.includes('gstatic.com');
}

function shouldCacheRequest(request) {
  if (request.method !== 'GET') return false;

  const url = new URL(request.url);
  if (isLikelyApiRequest(url)) return false;

  if (url.origin === self.location.origin) {
    return PRECACHE_URLS.some((cachedUrl) => cachedUrl === './' || cachedUrl === './index.html' || cachedUrl === './admin.html' || cachedUrl === './banned.html' || cachedUrl === './manifest.json' || cachedUrl === './icon.png')
      || url.pathname.endsWith('.html')
      || url.pathname.endsWith('.css')
      || url.pathname.endsWith('.js')
      || url.pathname.endsWith('.mjs')
      || url.pathname.endsWith('.json')
      || url.pathname.endsWith('.png')
      || url.pathname.endsWith('.jpg')
      || url.pathname.endsWith('.jpeg')
      || url.pathname.endsWith('.svg')
      || url.pathname.endsWith('.webp')
      || url.pathname.endsWith('.ico')
      || url.pathname.endsWith('.woff')
      || url.pathname.endsWith('.woff2')
      || url.pathname.endsWith('.ttf')
      || url.pathname.endsWith('.eot');
  }

  return CACHEABLE_ORIGINS.includes(url.origin) && CACHEABLE_EXTENSIONS.some((ext) => url.pathname.endsWith(ext));
}

self.addEventListener('install', (event) => {
  self.skipWaiting();
  event.waitUntil((async () => {
    const cache = await caches.open(CACHE_NAME);
    const precachePromises = PRECACHE_URLS.map(async (url) => {
      try {
        const response = await fetch(url, { cache: 'no-cache' });
        if (response.ok) {
          await cache.put(url, response.clone());
        }
      } catch (error) {
        console.warn('Failed to precache', url, error);
      }
    });

    await Promise.all(precachePromises);
  })());
});

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    const cacheNames = await caches.keys();
    await Promise.all(cacheNames.filter((name) => name !== CACHE_NAME).map((name) => caches.delete(name)));
    await self.clients.claim();
  })());
});

self.addEventListener('fetch', (event) => {
  const { request } = event;
  if (request.method !== 'GET' || !shouldCacheRequest(request)) {
    return;
  }

  if (request.mode === 'navigate') {
    event.respondWith(networkFirst(request));
    return;
  }

  event.respondWith(staleWhileRevalidate(request));
});

async function networkFirst(request) {
  try {
    const networkResponse = await fetch(request);
    if (networkResponse && networkResponse.ok) {
      const cache = await caches.open(CACHE_NAME);
      cache.put(request, networkResponse.clone());
    }
    return networkResponse;
  } catch (error) {
    const cachedResponse = await caches.match(request);
    if (cachedResponse) {
      return cachedResponse;
    }
    return caches.match('./index.html');
  }
}

async function staleWhileRevalidate(request) {
  const cachedResponse = await caches.match(request);
  const fetchPromise = fetch(request).then((networkResponse) => {
    if (networkResponse && networkResponse.ok) {
      const cache = caches.open(CACHE_NAME).then((cache) => cache.put(request, networkResponse.clone()));
      return cache.then(() => networkResponse);
    }
    return networkResponse;
  }).catch(() => cachedResponse);

  return cachedResponse || fetchPromise;
}

self.addEventListener('message', (event) => {
  if (event.data && event.data.type === 'SKIP_WAITING') {
    self.skipWaiting();
  }
});