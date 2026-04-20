const CACHE_NAME = 'sarhan-net-v4';
const urlsToCache = [
    'index.html',
    'login.html',
    'admin.html',
    'user_dashboard.html',
    'pay.html',
    'waiting.html',
    'config.js',
    'manifest.json',
    'https://cdn.tailwindcss.com',
    'https://fonts.googleapis.com/css2?family=Cairo:wght@400;700;900&display=swap',
    'https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css'
];

self.addEventListener('install', event => {
    console.log('[Service Worker] Installing...');
    event.waitUntil(
        caches.open(CACHE_NAME).then(cache => {
            console.log('[Service Worker] Caching app shell');
            return cache.addAll(urlsToCache);
        })
    );
    self.skipWaiting();
});

self.addEventListener('activate', event => {
    console.log('[Service Worker] Activating...');
    event.waitUntil(
        caches.keys().then(keyList => {
            return Promise.all(keyList.map(key => {
                if (key !== CACHE_NAME) {
                    console.log('[Service Worker] Removing old cache', key);
                    return caches.delete(key);
                }
            }));
        })
    );
    self.clients.claim();
});

self.addEventListener('fetch', event => {
    const url = event.request.url;
    
    if (url.includes('firebaseio.com') || url.includes('api.telegram.org')) {
        event.respondWith(fetch(event.request));
        return;
    }
    
    if (url.includes('.html') || url === event.request.url.split('?')[0].slice(-1) === '/' || url.endsWith('/')) {
        event.respondWith(
            fetch(event.request)
                .then(response => {
                    const responseClone = response.clone();
                    caches.open(CACHE_NAME).then(cache => {
                        cache.put(event.request, responseClone);
                    });
                    return response;
                })
                .catch(() => {
                    return caches.match(event.request)
                        .then(cachedResponse => {
                            if (cachedResponse) {
                                return cachedResponse;
                            }
                            return caches.match('index.html');
                        });
                })
        );
        return;
    }
    
    event.respondWith(
        caches.match(event.request)
            .then(cachedResponse => {
                if (cachedResponse) {
                    fetch(event.request).then(response => {
                        caches.open(CACHE_NAME).then(cache => {
                            cache.put(event.request, response);
                        });
                    }).catch(() => {});
                    return cachedResponse;
                }
                return fetch(event.request).then(response => {
                    const responseClone = response.clone();
                    caches.open(CACHE_NAME).then(cache => {
                        cache.put(event.request, responseClone);
                    });
                    return response;
                });
            })
            .catch(() => {
                if (event.request.url.match(/\.(jpg|jpeg|png|gif|svg)$/)) {
                    return new Response('', { status: 200, statusText: 'OK' });
                }
                return new Response('Network error', { status: 408, statusText: 'Timeout' });
            })
    );
});

self.addEventListener('push', event => {
    let title = 'السرحان NET';
    let options = {
        body: event.data ? event.data.text() : 'لديك إشعار جديد من الشبكة',
        icon: 'https://cdn-icons-png.flaticon.com/512/7269/7269100.png',
        badge: 'https://cdn-icons-png.flaticon.com/512/7269/7269100.png',
        vibrate: [200, 100, 200],
        data: {
            url: '/user_dashboard.html'
        }
    };
    
    event.waitUntil(
        self.registration.showNotification(title, options)
    );
});

self.addEventListener('notificationclick', event => {
    event.notification.close();
    event.waitUntil(
        clients.openWindow(event.notification.data.url || '/')
    );
});
