// supabase/functions/procesar-notificaciones-push/index.ts
//
// Procesador de cola de notificaciones push.
// Llamado cada 2 minutos por pg_cron vía pg_net.
// NO requiere JWT — se autentica internamente con SUPABASE_SERVICE_ROLE_KEY.
//
// Flujo:
//   1. Lee notificaciones_push_pendientes WHERE procesado = false (máx 50)
//   2. Por cada registro → dispara a OneSignal según destinatario_id o destinatario_rol
//   3. Marca como procesado = true, procesado_at = now()
//
// Sonidos por tipo (actualizar cuando llegue tarea #6):
//   inactividad_bloqueo    → 'alerta'   (central)
//   inactividad_eliminacion→ 'alerta'   (móvil)
//   descanso_aprobado      → 'mensaje'  (móvil)
//   descanso_rechazado     → 'alerta'   (móvil)
//   descanso_solicitud     → 'alerta'   (central)

import 'jsr:@supabase/functions-js/edge-runtime.d.ts';

const ONESIGNAL_APP_ID = '207d1d0a-0218-46e0-9f35-7d8d88f6765a';
const ONESIGNAL_API    = 'https://onesignal.com/api/v1/notifications';
const CANAL_ALARMA_ID  = 'serviexpress_alerta_v2';

// Sonido según tipo de notificación
function sonidoPorTipo(tipo: string): string {
  switch (tipo) {
    case 'descanso_aprobado':  return 'mensaje';
    case 'descanso_rechazado': return 'alerta';
    case 'descanso_solicitud': return 'alerta';
    case 'inactividad_bloqueo':     return 'alerta';
    case 'inactividad_eliminacion': return 'alerta';
    default: return 'alerta';
  }
}

// ¿Requiere canal urgente en Android?
function esUrgente(tipo: string): boolean {
  return tipo !== 'descanso_aprobado';
}

Deno.serve(async (_req: Request) => {
  const supabaseUrl     = Deno.env.get('SUPABASE_URL') ?? '';
  const serviceRoleKey  = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
  const restKey         = Deno.env.get('ONESIGNAL_REST_API_KEY') ?? '';

  if (!serviceRoleKey || !restKey) {
    return new Response(JSON.stringify({ error: 'Secrets no configurados' }), { status: 500 });
  }

  const authHeader = restKey.startsWith('os_v2_')
    ? `Key ${restKey}`
    : `Basic ${restKey}`;

  const dbHeaders = {
    'Content-Type':  'application/json',
    'apikey':        serviceRoleKey,
    'Authorization': `Bearer ${serviceRoleKey}`,
  };

  // ── 1. Leer cola pendiente ───────────────────────────────────────────────
  const fetchUrl = `${supabaseUrl}/rest/v1/notificaciones_push_pendientes`
    + `?procesado=eq.false&order=created_at.asc&limit=50`;

  const fetchRes = await fetch(fetchUrl, { headers: dbHeaders });
  if (!fetchRes.ok) {
    const txt = await fetchRes.text();
    return new Response(JSON.stringify({ error: 'Error leyendo cola', detail: txt }), { status: 500 });
  }

  const pendientes: Array<{
    id: number;
    destinatario_id: number | null;
    destinatario_rol: string | null;
    titulo: string;
    cuerpo: string;
    tipo: string;
  }> = await fetchRes.json();

  if (pendientes.length === 0) {
    return new Response(JSON.stringify({ procesados: 0, mensaje: 'Cola vacía' }), { status: 200 });
  }

  const procesadosIds: number[] = [];
  const errores: string[] = [];

  // ── 2. Procesar cada notificación ───────────────────────────────────────
  for (const notif of pendientes) {
    const sonido  = sonidoPorTipo(notif.tipo);
    const urgente = esUrgente(notif.tipo);

    // Construir payload base
    const payload: Record<string, unknown> = {
      app_id:       ONESIGNAL_APP_ID,
      headings:     { en: notif.titulo, es: notif.titulo },
      contents:     { en: notif.cuerpo, es: notif.cuerpo },
      priority:     10,
      android_sound: sonido,
      ios_sound:    `${sonido}.mp3`,
      data:         { tipo: notif.tipo },
    };

    if (urgente) {
      payload['existing_android_channel_id'] = CANAL_ALARMA_ID;
    }

    // Destinatario: por ID de usuario o por rol
    if (notif.destinatario_id !== null) {
      payload['include_external_user_ids']     = [String(notif.destinatario_id)];
      payload['channel_for_external_user_ids'] = 'push';
    } else if (notif.destinatario_rol) {
      payload['filters'] = [
        { field: 'tag', key: 'rol', relation: '=', value: notif.destinatario_rol },
      ];
    } else {
      // Sin destinatario definido → marcar como procesado sin enviar
      procesadosIds.push(notif.id);
      errores.push(`id=${notif.id}: sin destinatario, ignorado`);
      continue;
    }

    // Enviar a OneSignal
    try {
      const osRes = await fetch(ONESIGNAL_API, {
        method:  'POST',
        headers: {
          'Content-Type': 'application/json; charset=utf-8',
          Authorization:  authHeader,
        },
        body: JSON.stringify(payload),
      });

      if (osRes.ok || osRes.status === 200) {
        procesadosIds.push(notif.id);
      } else {
        const txt = await osRes.text();
        errores.push(`id=${notif.id}: OneSignal ${osRes.status} → ${txt.substring(0, 200)}`);
        // Marcar igualmente para no reintentar indefinidamente
        procesadosIds.push(notif.id);
      }
    } catch (e) {
      errores.push(`id=${notif.id}: excepción → ${e}`);
      procesadosIds.push(notif.id);
    }
  }

  // ── 3. Marcar como procesados ────────────────────────────────────────────
  if (procesadosIds.length > 0) {
    const idsStr = procesadosIds.join(',');
    const patchUrl = `${supabaseUrl}/rest/v1/notificaciones_push_pendientes`
      + `?id=in.(${idsStr})`;

    await fetch(patchUrl, {
      method:  'PATCH',
      headers: dbHeaders,
      body: JSON.stringify({
        procesado:    true,
        procesado_at: new Date().toISOString(),
      }),
    });
  }

  return new Response(
    JSON.stringify({
      procesados: procesadosIds.length,
      errores:    errores.length > 0 ? errores : undefined,
    }),
    { status: 200, headers: { 'Content-Type': 'application/json' } },
  );
});
