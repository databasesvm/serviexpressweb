// Reemplaza al service worker de la app vieja: borra lo guardado en el
// teléfono, se elimina y recarga la página (que redirige a serviexpress.app).
self.addEventListener('install', function () { self.skipWaiting(); });
self.addEventListener('activate', function (e) {
  e.waitUntil((async function () {
    var keys = await caches.keys();
    await Promise.all(keys.map(function (k) { return caches.delete(k); }));
    await self.registration.unregister();
    var clientes = await self.clients.matchAll({ type: 'window' });
    clientes.forEach(function (c) { c.navigate(c.url); });
  })());
});
