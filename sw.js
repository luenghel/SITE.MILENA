// ═══════════════════════════════════════════════════════════════════
// SERVICE WORKER
//
// Es lo que convierte el sitio en app: lo hace abrir rápido,
// funcionar con mala señal, y avisar cuando hay una versión nueva.
//
// ⚠️ Al subir cambios, subí el número de VERSION de abajo.
//    Eso le avisa a los celulares que hay algo nuevo.
// ═══════════════════════════════════════════════════════════════════

const VERSION = 'cmm-v22';

// Lo que guardamos para que abra al instante
const BASICOS = [
  '/',
  '/index',
  '/styles.css',
  '/supabase-config.js',
  '/vendor/supabase-2.119.2.js',
  '/header-dinamico.js',
  '/manifest.json',
  '/icon-192.png',
  '/icon-512.png',
];

// ─── Al instalarse ─────────────────────────────────────────────────
self.addEventListener('install', e => {
  e.waitUntil(
    caches.open(VERSION)
      // cache:'reload' = pedirlos de verdad al servidor, no la copia vieja del navegador
      .then(c => Promise.all(BASICOS.map(u =>
        fetch(new Request(u, { cache: 'reload' }))
          .then(r => { if (r.ok) return c.put(u, r); })
          .catch(() => { /* si alguno falla, seguimos */ })
      )))
      .then(() => self.skipWaiting())
  );
});

// ─── Al activarse: borramos lo viejo ───────────────────────────────
self.addEventListener('activate', e => {
  e.waitUntil(
    caches.keys()
      .then(claves => Promise.all(
        claves.filter(k => k !== VERSION).map(k => caches.delete(k))
      ))
      .then(() => self.clients.claim())
  );
});

// ─── Qué hacer con cada pedido ─────────────────────────────────────
self.addEventListener('fetch', e => {
  const url = new URL(e.request.url);

  // Solo lo nuestro
  if (url.origin !== location.origin) return;
  if (e.request.method !== 'GET') return;

  // Nada de Supabase se guarda: siempre datos frescos
  if (url.pathname.includes('/rest/') || url.pathname.includes('/auth/')) return;

  const esPagina = e.request.mode === 'navigate' ||
                   e.request.headers.get('accept')?.includes('text/html');

  // El código (.js y .css) también va primero por la red: si queda una
  // copia vieja guardada, el sitio se rompe cuando cambia algo importante.
  const esCodigo = /\.(js|css)$/.test(url.pathname) && !url.pathname.startsWith('/vendor/');

  if (esPagina || esCodigo) {
    // Las páginas: primero la red, para que siempre vean lo último.
    // Si no hay señal, mostramos lo que teníamos guardado.
    e.respondWith(
      fetch(e.request, esCodigo ? { cache: 'no-cache' } : undefined)
        .then(r => {
          if (r.ok) {
            const copia = r.clone();
            caches.open(VERSION).then(c => c.put(e.request, copia));
          }
          return r;
        })
        .catch(() =>
          caches.match(e.request).then(r => r || (esPagina ? caches.match('/index') : Response.error()))
        )
    );
    return;
  }

  // Lo demás (estilos, imágenes): primero lo guardado, es más rápido
  e.respondWith(
    caches.match(e.request).then(guardado => {
      if (guardado) {
        // Igual lo actualizamos por detrás para la próxima vez
        fetch(e.request).then(r => {
          if (r.ok) caches.open(VERSION).then(c => c.put(e.request, r));
        }).catch(() => {});
        return guardado;
      }

      return fetch(e.request).then(r => {
        if (r.ok && r.type === 'basic') {
          const copia = r.clone();
          caches.open(VERSION).then(c => c.put(e.request, copia));
        }
        return r;
      });
    })
  );
});

// ─── Para avisar que hay versión nueva ─────────────────────────────
self.addEventListener('message', e => {
  if (e.data === 'actualizar') self.skipWaiting();
});
