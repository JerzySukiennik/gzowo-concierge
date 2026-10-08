// Gzowo Concierge - service worker: Web Push notifications only (no caching, so updates always load fresh).
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', e => e.waitUntil(self.clients.claim()));

self.addEventListener('push', e => {
  let d = {};
  try { d = e.data ? e.data.json() : {}; } catch { d = { body: e.data ? e.data.text() : '' }; }
  e.waitUntil(self.registration.showNotification(d.title || 'Concierge', {
    body: d.body || '',
    tag: d.tag || 'concierge',
    icon: 'icon-192.png',
    badge: 'icon-192.png',
    data: { url: d.url || './' },
  }));
});

self.addEventListener('notificationclick', e => {
  e.notification.close();
  const raw = (e.notification.data && e.notification.data.url) || './';
  const target = new URL(raw, self.registration.scope);
  const thread = target.searchParams.get('thread');
  e.waitUntil((async () => {
    const wins = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
    for (const w of wins) {
      if (new URL(w.url).origin === target.origin) {
        await w.focus();
        if (thread) w.postMessage({ type: 'open-thread', thread });
        return;
      }
    }
    await self.clients.openWindow(target.href);
  })());
});
