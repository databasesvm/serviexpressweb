Para Servicios de ServiExpress (No aplica para FN)servicios y notificaciones de 30s Master, 30 segundos despues al #1 Paradero, 30s mas al cercano 1km, 30 segundos mas a todos los conectados siempre y cuando su rango permita llevar mas servicios
 
30s Master, 30s después al #1 paradero, 30s después al más cercano 1km, 30 segundos después a todos los disponibles respetando los rangos y todo lo que ya está. En total serían 2 minutos para que lleguen hasta todos los conectados

Al liberar el servicio se reinicia el servicio y las notificaciones

Con los servicios de FN La Cascada es asi:
T=0: Push a Masters (aceptan voluntariamente). 
T+30s: Verifica si el móvil mas cercano está libre, y lo auto-asigna. Si está ocupado, lo salta — el servicio queda para FASE 3/4
T+60s: Push a no-Masters dentro de 2km (excl. fase2)
T+90s: Push al resto global
Al auto-asignar, el pg_cron cancela fn_notif_fase3 y fn_notif_fase4 para que no lleguen notificaciones innecesarias