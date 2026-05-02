const CACHE_NAME = 'sarhan-net-v6';
const urlsToCache = [
    'index.html',
    'login.html',
    'admin.html',
    'user_dashboard.html',
    'pay.html',
    'waiting.html',
    'config.js',
    'manifest.json'
];

self.addEventListener('install', event => {
    event.waitUntil(
        caches.open(CACHE_NAME).then(cache => cache.addAll(urlsToCache))
    );
    self.skipWaiting();
});

self.addEventListener('fetch', event => {
    const url = event.request.url;
    if (url.includes('firebaseio.com') || url.includes('api.telegram.org')) {
        event.respondWith(fetch(event.request));
        return;
    }
    event.respondWith(
        caches.match(event.request).then(response => {
            return response || fetch(event.request);
        })
    );
});

self.addEventListener('push', event => {
    event.waitUntil(
        self.registration.showNotification('السرحان NET', {
            body: event.data ? event.data.text() : 'لديك إشعار جديد',
            icon: 'https://cdn-icons-png.flaticon.com/512/7269/7269100.png'
        })
    );
});
