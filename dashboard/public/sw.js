// Kill-Switch-Service-Worker (Garfield, 2026-05-30 P0).
//
// Kill-Switch — retire (Datei löschen) wenn alle Clients clean (frühestens in
// ein paar Tagen). NICHT vorher löschen: sonst kriegt ein Alt-Gerät (v.a.
// ein PO-Mobilgerät) das Deregister-Signal nie. Wird via nuxt.config routeRules
// mit `Cache-Control: no-cache, no-store, must-revalidate` ausgeliefert, damit
// Browser ihn SOFORT beim nächsten Update-Check abholen statt erst nach ~24h.
// PWA/@vite-pwa ist sonst restlos raus (PO-Entscheidung) — siehe CLAUDE.md.
//
// Hintergrund: Der vorige @vite-pwa/nuxt-SW (Branch pwa-enable, master
// 67a1ead) hat das Dashboard stundenlang stale gerendert (gestriger Sprint,
// alte Heartbeats). Diese Datei ersetzt den alten SW: sie installiert sich,
// löscht ALLE Caches, deinstalliert sich selbst und navigiert offene Tabs zur
// frischen URL. Beim nächsten Reload danach läuft die Page ganz ohne SW.
//
// Wie Browser den Switch aufgreifen: Browser holt /sw.js periodisch ab
// (default ~24h, bei navigation freshness check oft schneller). Bekommt er
// dieses File statt des alten Workbox-SWs, ersetzt er die Registration → install
// → activate → skip + delete + unregister. Beim Folge-Reload existiert keine
// aktive Registration mehr, alles läuft direkt gegen den Server.

self.addEventListener('install', (event) => {
  // skipWaiting damit der neue (Kill-)SW sofort aktiv wird, ohne dass der User
  // alle Tabs schließen muss.
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    try {
      // 1) Alle vom alten Workbox-SW angelegten Caches platt machen.
      const keys = await caches.keys();
      await Promise.all(keys.map((k) => caches.delete(k)));
    } catch (e) {
      // Fail-safe: weiter mit Unregister auch wenn caches.delete einzeln scheitert.
      console.warn('[sw kill] cache cleanup partial:', e);
    }

    // 2) Diese Registration selbst aus dem Browser werfen.
    try {
      await self.registration.unregister();
    } catch (e) {
      console.warn('[sw kill] unregister failed:', e);
    }

    // 3) Alle offenen Clients zur gleichen URL navigieren → erzwingt frischen
    //    Network-Fetch (sonst rendert der Browser u.U. noch die letzte HTML-
    //    Variante aus dem disk-Cache).
    try {
      const clients = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
      for (const c of clients) {
        try { await c.navigate(c.url); } catch (_) { /* iOS Safari erlaubt navigate nicht immer */ }
      }
    } catch (e) {
      console.warn('[sw kill] client refresh failed:', e);
    }
  })());
});

// Während der Kill-SW noch lebt: alle fetches direkt durchreichen (kein Cache).
self.addEventListener('fetch', (event) => {
  event.respondWith(fetch(event.request));
});
