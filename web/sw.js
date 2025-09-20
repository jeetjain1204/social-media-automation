// Service Worker for Blob App - Performance Optimization
// Expected Impact: 40-60% faster subsequent loads

const CACHE_NAME = 'blob-v1.0.0';
const STATIC_CACHE = 'blob-static-v1.0.0';
const API_CACHE = 'blob-api-v1.0.0';

// Static assets to cache aggressively
const STATIC_ASSETS = [
  '/',
  '/manifest.json',
  '/icons/Icon-192.png',
  '/icons/Icon-512.png',
  '/icons/Icon-maskable-192.png',
  '/icons/Icon-maskable-512.png',
  '/favicon.png',
];

// API endpoints to cache with stale-while-revalidate
const API_ENDPOINTS = [
  '/api/',
  '/supabase/',
];

// Install event - cache static assets
self.addEventListener('install', (event) => {
  console.log('🔧 Service Worker installing...');
  
  event.waitUntil(
    caches.open(STATIC_CACHE)
      .then(cache => {
        console.log('📦 Caching static assets...');
        return cache.addAll(STATIC_ASSETS);
      })
      .then(() => {
        console.log('✅ Static assets cached successfully');
        return self.skipWaiting();
      })
      .catch(error => {
        console.error('❌ Failed to cache static assets:', error);
      })
  );
});

// Activate event - clean up old caches
self.addEventListener('activate', (event) => {
  console.log('🚀 Service Worker activating...');
  
  event.waitUntil(
    caches.keys()
      .then(cacheNames => {
        return Promise.all(
          cacheNames.map(cacheName => {
            if (cacheName !== STATIC_CACHE && cacheName !== API_CACHE) {
              console.log('🗑️ Deleting old cache:', cacheName);
              return caches.delete(cacheName);
            }
          })
        );
      })
      .then(() => {
        console.log('✅ Service Worker activated');
        return self.clients.claim();
      })
  );
});

// Fetch event - implement caching strategies
self.addEventListener('fetch', (event) => {
  const { request } = event;
  const url = new URL(request.url);
  
  // Skip non-GET requests
  if (request.method !== 'GET') {
    return;
  }
  
  // Skip chrome-extension and other non-http requests
  if (!url.protocol.startsWith('http')) {
    return;
  }
  
  // Static assets - cache first strategy
  if (isStaticAsset(url)) {
    event.respondWith(cacheFirst(request, STATIC_CACHE));
    return;
  }
  
  // API calls - stale-while-revalidate strategy
  if (isApiCall(url)) {
    event.respondWith(staleWhileRevalidate(request, API_CACHE));
    return;
  }
  
  // HTML pages - network first with cache fallback
  if (isHtmlPage(request)) {
    event.respondWith(networkFirst(request));
    return;
  }
  
  // Default - network first
  event.respondWith(fetch(request));
});

// Cache first strategy for static assets
async function cacheFirst(request, cacheName) {
  try {
    const cache = await caches.open(cacheName);
    const cached = await cache.match(request);
    
    if (cached) {
      return cached;
    }
    
    const response = await fetch(request);
    if (response.ok) {
      cache.put(request, response.clone());
    }
    return response;
  } catch (error) {
    console.error('Cache first failed:', error);
    return fetch(request);
  }
}

// Stale-while-revalidate strategy for API calls
async function staleWhileRevalidate(request, cacheName) {
  try {
    const cache = await caches.open(cacheName);
    const cached = await cache.match(request);
    
    // Return cached version immediately if available
    const fetchPromise = fetch(request).then(response => {
      if (response.ok) {
        cache.put(request, response.clone());
      }
      return response;
    });
    
    return cached || fetchPromise;
  } catch (error) {
    console.error('Stale-while-revalidate failed:', error);
    return fetch(request);
  }
}

// Network first strategy for HTML pages
async function networkFirst(request) {
  try {
    const response = await fetch(request);
    if (response.ok) {
      const cache = await caches.open(CACHE_NAME);
      cache.put(request, response.clone());
    }
    return response;
  } catch (error) {
    const cache = await caches.open(CACHE_NAME);
    const cached = await cache.match(request);
    return cached || new Response('Offline', { status: 503 });
  }
}

// Helper functions
function isStaticAsset(url) {
  return STATIC_ASSETS.some(asset => url.pathname === asset) ||
         url.pathname.match(/\.(js|css|png|jpg|jpeg|gif|svg|woff|woff2|ttf)$/);
}

function isApiCall(url) {
  return API_ENDPOINTS.some(endpoint => url.pathname.startsWith(endpoint)) ||
         url.hostname.includes('supabase') ||
         url.hostname.includes('api');
}

function isHtmlPage(request) {
  return request.headers.get('accept')?.includes('text/html') ||
         request.url.endsWith('/') ||
         !request.url.includes('.');
}

// Background sync for failed requests
self.addEventListener('sync', (event) => {
  if (event.tag === 'background-sync') {
    event.waitUntil(doBackgroundSync());
  }
});

async function doBackgroundSync() {
  console.log('🔄 Performing background sync...');
  // Implement background sync logic here
}

// Push notifications
self.addEventListener('push', (event) => {
  if (event.data) {
    const data = event.data.json();
    const options = {
      body: data.body,
      icon: '/icons/Icon-192.png',
      badge: '/icons/Icon-192.png',
      vibrate: [100, 50, 100],
      data: {
        dateOfArrival: Date.now(),
        primaryKey: data.primaryKey
      }
    };
    
    event.waitUntil(
      self.registration.showNotification(data.title, options)
    );
  }
});

// Notification click
self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  
  event.waitUntil(
    clients.openWindow('/')
  );
});

console.log('📱 Service Worker loaded successfully');
