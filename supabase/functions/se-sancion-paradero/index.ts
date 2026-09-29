// supabase/functions/se-sancion-paradero/index.ts
//
// Corre cada minuto via pg_cron — SANC-D/E
// Detecta ofertas F2 paradero SE vencidas sin respuesta y aplica sanciones escalonadas.
//
// El umbral de expiración es seF2Seg * 2 desde paradero_ofrecido_at (que se graba en T=0).
// Esto equivale a 60s desde que se creó el servicio = el #1 recibe el push a T+30s
// y tiene 30s reales para aceptar antes de que este cron lo sancione a T+60s.
//
// Sanciones:
//   0 rechazos hoy  → movido al último de la fila (permanece en paradero)
//   1 rechazo hoy   → suspendido 1 hora + sacado de fila
//   2+ rechazos hoy → suspendido 24 horas + sacado de fila
//
// IMPORTANTE: NO se limpia paradero_auto_movil_id — ese campo queda para
// que la visibilidad F3 en Flutter pueda excluir al #1 penalizado.
// Solo se limpian paradero_ofrecido_id y paradero_ofrecido_at.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SEND_NOTIF_URL   = 'https://oukiofdtargjrclualgm.supabase.co/functions/v1/send-notification';
const ONESIGNAL_APP_ID = '207d1d0a-0218-46e0-9f35-7d8d88f6765a';
const CANAL_ALARMA     = 'serviexpress_alerta_v2';

// Fecha máxima compatible con Dart DateTime.parse para poner al móvil de último en la fila.
// NO usar new Date(8640000000000000).toISOString() — produce "+275760-09-13T..." (año > 9999
// con prefijo "+") que Dart lanza FormatException, rompiendo el sort client-side en Flutter.
// '9999-12-31T23:59:59.000Z' es el máximo que DateTime.parse() de Dart puede manejar.
const FECHA_MAX_FILA = '9999-12-31T23:59:59.000Z';

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
);

async function enviarPush(movilId: string, titulo: string, mensaje: string) {
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
      }),
    });
  } catch (e) {
    console.warn(`[sancion-paradero] Error push a ${movilId}:`, e);
  }
}

Deno.serve(async () => {
  // Leer timeout F2 de config_sistema
  const { data: cfg } = await supabase
    .from('config_sistema')
    .select('cascada_se_f2_seg')
    .single();
  const seF2Seg = cfg?.cascada_se_f2_seg ?? 30;

  // paradero_ofrecido_at se graba en T=0 (creación del servicio).
  // Usamos seF2Seg * 2 para que el #1 tenga sus 30s reales:
  //   T=0: ofrecido_at grabado, push F2 programado con send_after=30s
  //   T+30s: push llega al #1
  //   T+60s: este cron detecta la oferta como vencida y sanciona
  const umbralOferta = new Date(Date.now() - seF2Seg * 2 * 1000).toISOString();

  // Servicios pendientes con oferta vencida
  const { data: expirados } = await supabase
    .from('servicios')
    .select('id, paradero_ofrecido_id')
    .eq('estado', 'pendiente')
    .not('paradero_ofrecido_id', 'is', null)
    .lte('paradero_ofrecido_at', umbralOferta);

  if (!expirados || expirados.length === 0) {
    return new Response('ok-noop', { status: 200 });
  }

  // "Hoy" en hora Colombia (UTC-5, sin DST)
  const bogotaNow = new Date(Date.now() - 5 * 60 * 60 * 1000);
  const hoy = bogotaNow.toISOString().split('T')[0]; // YYYY-MM-DD

  for (const srv of expirados) {
    const movilId = srv.paradero_ofrecido_id as string;
    const srvId   = srv.id as number;

    // Limpiar oferta — NO tocamos paradero_auto_movil_id
    // (Flutter lo usa para excluir al #1 de la visibilidad F3)
    const { error: clearErr } = await supabase
      .from('servicios')
      .update({
        paradero_ofrecido_id: null,
        paradero_ofrecido_at: null,
      })
      .eq('id', srvId)
      .eq('paradero_ofrecido_id', movilId); // guard idempotente

    if (clearErr) {
      console.error(`[sancion-paradero] Error limpiando srv ${srvId}:`, clearErr.message);
      continue;
    }

    // Leer datos actuales del móvil
    const { data: movil } = await supabase
      .from('usuarios')
      .select('rechazos_paradero_hoy, fecha_rechazos, paradero_actual')
      .eq('id', parseInt(movilId))
      .maybeSingle();

    if (!movil) {
      console.error(`[sancion-paradero] Móvil ${movilId} no encontrado`);
      continue;
    }

    // Calcular rechazos del día (resetear si es un nuevo día)
    let rechazosHoy = (movil.rechazos_paradero_hoy ?? 0) as number;
    if (movil.fecha_rechazos !== hoy) {
      rechazosHoy = 0;
    }

    // Preparar actualización del móvil
    const updateMovil: Record<string, unknown> = {
      rechazos_paradero_hoy: rechazosHoy + 1,
      fecha_rechazos: hoy,
    };
    let titulo: string;
    let mensaje: string;

    if (rechazosHoy === 0) {
      // 1er rechazo → mover al último de la fila
      // CRÍTICO: usar FECHA_MAX_FILA en vez de new Date(8640000000000000).toISOString()
      // porque el máximo de JS produce año 275760 con prefijo "+" que Dart no puede parsear.
      updateMovil.ingreso_fila = FECHA_MAX_FILA;
      titulo  = '⚠️ Movido al último puesto';
      mensaje = 'No aceptaste tu turno de paradero a tiempo. Fuiste movido al último puesto de la fila.';
      console.log(`[sancion-paradero] Srv ${srvId}: móvil ${movilId} → 1er rechazo, al último de la fila (${FECHA_MAX_FILA})`);

    } else if (rechazosHoy === 1) {
      // 2do rechazo → suspender 1 hora + sacar de fila
      const suspHasta = new Date(Date.now() + 60 * 60 * 1000);
      const horaStr   = suspHasta.toLocaleTimeString('es-CO', { timeZone: 'America/Bogota', hour: '2-digit', minute: '2-digit' });
      updateMovil.suspendido_hasta = suspHasta.toISOString();
      updateMovil.paradero_actual  = null;
      updateMovil.ingreso_fila     = null;
      titulo  = '❌ Suspendido 1 hora del paradero';
      mensaje = `Segunda vez hoy que no aceptas tu turno. Suspendido del paradero por 1 hora (hasta las ${horaStr}).`;
      console.log(`[sancion-paradero] Srv ${srvId}: móvil ${movilId} → 2do rechazo, suspendido 1h`);

    } else {
      // 3er rechazo o más → suspender 24 horas + sacar de fila
      const suspHasta = new Date(Date.now() + 24 * 60 * 60 * 1000);
      const horaStr   = suspHasta.toLocaleTimeString('es-CO', { timeZone: 'America/Bogota', hour: '2-digit', minute: '2-digit' });
      updateMovil.suspendido_hasta = suspHasta.toISOString();
      updateMovil.paradero_actual  = null;
      updateMovil.ingreso_fila     = null;
      titulo  = '🚫 Suspendido 24 horas del paradero';
      mensaje = `${rechazosHoy + 1}ª vez hoy que no aceptas tu turno. Suspendido del paradero por 24 horas (hasta mañana a las ${horaStr}).`;
      console.log(`[sancion-paradero] Srv ${srvId}: móvil ${movilId} → ${rechazosHoy + 1}o rechazo, suspendido 24h`);
    }

    const { error: updateErr } = await supabase
      .from('usuarios')
      .update(updateMovil)
      .eq('id', parseInt(movilId));

    if (updateErr) {
      console.error(`[sancion-paradero] Error sancionando móvil ${movilId}:`, updateErr.message);
    }

    await enviarPush(movilId, titulo, mensaje);
    console.log(`[sancion-paradero] Srv ${srvId} — oferta limpiada. Móvil ${movilId} sancionado. paradero_auto_movil_id conservado para excluir de F3.`);
  }

  return new Response('ok', { status: 200 });
});
