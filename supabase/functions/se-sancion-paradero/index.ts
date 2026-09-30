// supabase/functions/se-sancion-paradero/index.ts
//
// Invocado por public.se_sancion_paradero_check() (pg_cron cada 10s),
// solo cuando hay ofertas vencidas — SANC-D/E
// Detecta móviles con oferta F2 paradero SE vencida y aplica sanciones.
//
// IMPORTANTE: desplegar con verify_jwt = false (el pg_cron no envía Authorization).
//
// Fuente: usuarios.paradero_oferta_expira_at (sobrevive aunque el servicio
// sea aceptado/cancelado). Solo se sanciona si:
//   - el #1 tuvo sus 30s completos de F2 y no aceptó (v10), y
//   - el móvil está en un paradero (el "más cercano" nunca se sanciona) (v11).
//
// Sanciones escalonadas (por rechazos del mismo día Colombia, se reinicia a medianoche):
//   1ª vez hoy  → expulsado del paradero (regístrate de nuevo manualmente)
//   2ª vez hoy  → suspendido 1 hora del paradero
//   3ª+ vez hoy → suspendido 24 horas del paradero
//
// v12: el push lleva data.tipo = 'sancion_paradero' (+ nivel, titulo, mensaje,
//      hasta) para que la app muestre un banner de 30 s con su propio sonido,
//      y textos que explican qué pasa si vuelve a ocurrir hoy.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SEND_NOTIF_URL   = 'https://oukiofdtargjrclualgm.supabase.co/functions/v1/send-notification';
const ONESIGNAL_APP_ID = '207d1d0a-0218-46e0-9f35-7d8d88f6765a';
const CANAL_ALARMA     = 'serviexpress_alerta_v2';

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
);

function horaBogota(d: Date): string {
  return d.toLocaleTimeString('es-CO', {
    timeZone: 'America/Bogota', hour: 'numeric', minute: '2-digit', hour12: true,
  });
}

async function enviarPush(
  movilId: string, titulo: string, mensaje: string, data: Record<string, unknown>,
) {
  try {
    await fetch(SEND_NOTIF_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        app_id: ONESIGNAL_APP_ID,
        include_external_user_ids: [movilId],
        channel_for_external_user_ids: 'push',
        headings: { en: titulo, es: titulo },
        contents: { en: mensaje, es: mensaje },
        priority: 10,
        android_sound: 'movil_paradero',
        ios_sound: 'movil_paradero.mp3',
        existing_android_channel_id: CANAL_ALARMA,
        data,
      }),
    });
  } catch (e) {
    console.warn(`[sancion-paradero] Error push a ${movilId}:`, e);
  }
}

Deno.serve(async () => {
  const ahora = new Date().toISOString();

  // "Hoy" en hora Colombia (UTC-5, sin DST)
  const bogotaNow = new Date(Date.now() - 5 * 60 * 60 * 1000);
  const hoy = bogotaNow.toISOString().split('T')[0]; // YYYY-MM-DD

  const { data: pendientes, error: fetchErr } = await supabase
    .from('usuarios')
    .select('id, rechazos_paradero_hoy, fecha_rechazos, paradero_actual')
    .not('paradero_oferta_expira_at', 'is', null)
    .lte('paradero_oferta_expira_at', ahora);

  if (fetchErr) {
    console.error('[sancion-paradero] Error consultando usuarios:', fetchErr.message);
    return new Response('error', { status: 500 });
  }

  if (!pendientes || pendientes.length === 0) {
    return new Response('ok-noop', { status: 200 });
  }

  for (const movil of pendientes) {
    const movilId    = movil.id.toString();
    const movilIdInt = movil.id as number;

    // Reclamar la oferta de forma atómica (evita doble sanción)
    const { data: reclamado } = await supabase
      .from('usuarios')
      .update({ paradero_oferta_expira_at: null })
      .eq('id', movilIdInt)
      .not('paradero_oferta_expira_at', 'is', null)
      .lte('paradero_oferta_expira_at', ahora)
      .select('id');
    if (!reclamado || reclamado.length === 0) continue;

    // Limpiar paradero_ofrecido_id/at en servicios pendientes (desbloquea F4)
    await supabase
      .from('servicios')
      .update({ paradero_ofrecido_id: null, paradero_ofrecido_at: null })
      .eq('paradero_ofrecido_id', movilId)
      .eq('estado', 'pendiente');

    // Validar que el #1 realmente tuvo sus 30s de F2 y no aceptó.
    const { data: srvs } = await supabase
      .from('servicios')
      .select('id, estado, movil_id, created_at, liberacion_at, accepted_at, updated_at')
      .eq('paradero_auto_movil_id', movilId)
      .gte('created_at', new Date(Date.now() - 20 * 60 * 1000).toISOString())
      .order('id', { ascending: false })
      .limit(1);
    const srv = srvs?.[0];
    let sancionValida = false;
    if (srv && srv.movil_id?.toString() !== movilId) {
      const creado = new Date(srv.created_at).getTime();
      const liber  = srv.liberacion_at ? new Date(srv.liberacion_at).getTime() : 0;
      const finF2  = Math.max(creado, liber) + 55 * 1000;
      if (srv.estado === 'pendiente') {
        sancionValida = true;
      } else if (srv.estado === 'cancelado') {
        sancionValida = new Date(srv.updated_at).getTime() >= finF2;
      } else if (srv.accepted_at) {
        sancionValida = new Date(srv.accepted_at).getTime() >= finF2;
      }
    }
    if (!sancionValida) {
      console.log(`[sancion-paradero] Móvil ${movilId}: srv ${srv?.id ?? '-'} tomado/cancelado antes de cerrar F2 → sin sanción`);
      continue;
    }

    // La sanción es SOLO para el #1 del paradero.
    if (!movil.paradero_actual) {
      console.log(`[sancion-paradero] Móvil ${movilId}: no está en paradero → sin sanción`);
      continue;
    }

    let rechazosHoy = (movil.rechazos_paradero_hoy ?? 0) as number;
    if (movil.fecha_rechazos !== hoy) rechazosHoy = 0;
    const vez = rechazosHoy + 1;

    const updateMovil: Record<string, unknown> = {
      rechazos_paradero_hoy:     vez,
      fecha_rechazos:            hoy,
      paradero_oferta_expira_at: null,
      paradero_actual:           null,
      ingreso_fila:              null,
    };
    let titulo: string;
    let mensaje: string;
    let hasta: string | null = null;
    let nivel: number;

    if (vez === 1) {
      nivel   = 1;
      titulo  = '⚠️ Expulsado del paradero (1ª vez hoy)';
      mensaje = 'No aceptaste tu turno en 30 s. Regístrate de nuevo cuando estés listo. ' +
                'Si vuelve a pasar hoy: 2ª vez → suspendido 1 hora; 3ª vez → suspendido 24 horas.';
    } else if (vez === 2) {
      nivel = 2;
      const suspHasta = new Date(Date.now() + 60 * 60 * 1000);
      hasta = suspHasta.toISOString();
      updateMovil.suspendido_hasta = hasta;
      titulo  = '❌ Suspendido 1 hora (2ª vez hoy)';
      mensaje = `No aceptaste tu turno por segunda vez. Puedes volver al paradero a las ${horaBogota(suspHasta)}. ` +
                'Si pasa una 3ª vez hoy quedarás suspendido 24 horas.';
    } else {
      nivel = 3;
      const suspHasta = new Date(Date.now() + 24 * 60 * 60 * 1000);
      hasta = suspHasta.toISOString();
      updateMovil.suspendido_hasta = hasta;
      titulo  = `🚫 Suspendido 24 horas (${vez}ª vez hoy)`;
      mensaje = `No aceptaste tu turno por ${vez === 3 ? 'tercera' : `${vez}ª`} vez hoy. ` +
                `Puedes volver al paradero mañana a las ${horaBogota(suspHasta)}.`;
    }

    const { error: updateErr } = await supabase
      .from('usuarios')
      .update(updateMovil)
      .eq('id', movilIdInt);
    if (updateErr) {
      console.error(`[sancion-paradero] Error sancionando móvil ${movilId}:`, updateErr.message);
      continue;
    }

    await enviarPush(movilId, titulo, mensaje, {
      tipo: 'sancion_paradero', nivel, vez, titulo, mensaje, hasta,
    });
    console.log(`[sancion-paradero] Móvil ${movilId} sancionado (${vez}ª vez hoy).`);
  }

  return new Response('ok', { status: 200 });
});
