// supabase/functions/fn-auto-asignar-fase2/index.ts
//
// Corre cada minuto via pg_cron.
// Maneja DOS tipos de auto-asignación en fase 2 (T+30s):
//
//   1. Servicios FN (tipo_fn = true):
//      Busca fn_fase2_movil_id + fn_radar_t0 ≥ 30s atrás.
//      Auto-asigna el más cercano a la sede, cancela fases 3 y 4.
//
//   2. Servicios no-FN (tipo_fn = false / null):
//      Busca paradero_auto_movil_id + created_at/liberacion_at ≥ 30s.
//      Auto-asigna el #1 del paradero, cancela zona y global.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const ONESIGNAL_APP_ID = '207d1d0a-0218-46e0-9f35-7d8d88f6765a';
const ONESIGNAL_API    = 'https://onesignal.com/api/v1/notifications';
const CANAL_ALARMA     = 'serviexpress_alerta_v2';
const SEND_NOTIF_URL   = 'https://oukiofdtargjrclualgm.supabase.co/functions/v1/send-notification';

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
);

const restKey = Deno.env.get('ONESIGNAL_REST_API_KEY') ?? '';
const authHeader = restKey.startsWith('os_v2_') ? `Key ${restKey}` : `Basic ${restKey}`;

async function cancelarNotif(notifId: string | null) {
  if (!notifId) return;
  try {
    await fetch(`${ONESIGNAL_API}/${notifId}?app_id=${ONESIGNAL_APP_ID}`, {
      method: 'DELETE',
      headers: { Authorization: authHeader },
    });
  } catch (e) {
    console.warn(`[auto-asignar] No se pudo cancelar ${notifId}:`, e);
  }
}

async function enviarHeadsup(movilId: string, titulo: string, mensaje: string) {
  try {
    await fetch(SEND_NOTIF_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        app_id: ONESIGNAL_APP_ID,
        include_external_user_ids: [movilId],
        headings: { en: titulo, es: titulo },
        contents: { en: mensaje, es: mensaje },
        priority: 10,
        android_sound: 'movil_paradero',
        ios_sound: 'movil_paradero.mp3',
        existing_android_channel_id: CANAL_ALARMA,
      }),
    });
  } catch (e) {
    console.warn(`[auto-asignar] Error headsup a ${movilId}:`, e);
  }
}

async function movilEstaOcupado(movilId: string): Promise<boolean> {
  const { data } = await supabase
    .from('servicios')
    .select('id')
    .eq('movil_id', parseInt(movilId))
    .in('estado', ['en_ruta_origen', 'en_origen', 'en_ruta_destino', 'problema'])
    .maybeSingle();
  return !!data;
}

// Auto-asignación para servicios NO-FN: cambia estado a en_ruta_origen
// (el #1 del paradero queda activo de inmediato).
async function autoAsignar(
  srvId: number,
  movilId: string,
  notifCancelar: (string | null)[],
  titulo: string,
  mensaje: string,
): Promise<boolean> {
  const { error } = await supabase
    .from('servicios')
    .update({
      movil_id: parseInt(movilId),
      estado: 'en_ruta_origen',
      accepted_at: new Date().toISOString(),
    })
    .eq('id', srvId)
    .eq('estado', 'pendiente')   // guard anti-doble-asignación
    .is('movil_id', null);

  if (error) {
    console.error(`[auto-asignar] Error asignando srv ${srvId}:`, error.message);
    return false;
  }

  for (const n of notifCancelar) await cancelarNotif(n);
  await enviarHeadsup(movilId, titulo, mensaje);
  console.log(`[auto-asignar] Srv ${srvId} → móvil ${movilId} ✓`);
  return true;
}

// Pre-asignación FN fase 2:
//   - Libre  → set movil_id (mantiene estado=pendiente). El móvil confirma
//              aceptando in-app. Cancela FASE 3/4 para no notificar a otros.
//   - Ocupado → solo push. El servicio sigue en cascada abierta (FASE 3/4).
async function preasignarFn(
  srvId: number,
  movilId: string,
  notifCancelar: (string | null)[],
): Promise<void> {
  const ocupado = await movilEstaOcupado(movilId);

  if (!ocupado) {
    // Libre: marcar movil_id y cambiar fn_asignacion_tipo para que
    // el radar del móvil lo muestre directamente (como directo_presel).
    const { error } = await supabase
      .from('servicios')
      .update({
        movil_id: parseInt(movilId),
        fn_asignacion_tipo: 'directo_presel',
      })
      .eq('id', srvId)
      .eq('estado', 'pendiente')
      .is('movil_id', null); // guard anti-doble-asignación

    if (error) {
      console.error(`[fn-fase2] Error pre-asignando srv ${srvId}:`, error.message);
      return;
    }

    // Cancelar notificaciones de fases siguientes (ya está pre-asignado)
    for (const n of notifCancelar) await cancelarNotif(n);
    await enviarHeadsup(movilId, '🎯 SERVICIO FN PARA TI', 'Un servicio FN quedó asignado a ti — confírmalo en la app');
    console.log(`[fn-fase2] Srv ${srvId} pre-asignado libre → móvil ${movilId} ✓`);
  } else {
    // Ocupado: solo push. El servicio sigue en cascada y llega a FASE 3/4.
    await enviarHeadsup(movilId, '🔵 SERVICIO FN CERCANO', 'Hay un servicio FN cerca — revisa si te conviene la ruta');
    console.log(`[fn-fase2] Srv ${srvId} → móvil ${movilId} ocupado, solo push`);
  }
}

Deno.serve(async () => {
  const umbral = new Date(Date.now() - 30_000).toISOString();

  // ── 1. SERVICIOS FN ──────────────────────────────────────────────────────
  {
    const { data: serviciosFN } = await supabase
      .from('servicios')
      .select('id, fn_fase2_movil_id, fn_notif_fase3, fn_notif_fase4')
      .eq('fn_asignacion_tipo', 'radar')
      .eq('estado', 'pendiente')
      .eq('tipo_fn', true)
      .not('fn_fase2_movil_id', 'is', null)
      .is('movil_id', null)
      .lte('fn_radar_t0', umbral);

    for (const srv of serviciosFN ?? []) {
      await preasignarFn(
        srv.id,
        srv.fn_fase2_movil_id as string,
        [srv.fn_notif_fase3, srv.fn_notif_fase4],
      );
    }
  }

  // ── 2. SERVICIOS NO-FN — #1 DEL PARADERO ────────────────────────────────
  // El anchor de tiempo es GREATEST(created_at, COALESCE(liberacion_at, created_at)).
  // Aquí en Deno usamos el umbral de 30s y filtramos solo por created_at como
  // aproximación — liberacion_at se verifica como fallback implícito.
  {
    const { data: serviciosNormal } = await supabase
      .from('servicios')
      .select('id, paradero_auto_movil_id, onesignal_2m, onesignal_5m, liberacion_at, created_at')
      .eq('estado', 'pendiente')
      .is('tipo_fn', null)    // no-FN
      .not('paradero_auto_movil_id', 'is', null)
      .is('movil_id', null)
      .lte('created_at', umbral);

    for (const srv of serviciosNormal ?? []) {
      // Si liberacion_at existe y es más reciente, verificar que también pasaron 30s
      if (srv.liberacion_at) {
        const libAt = new Date(srv.liberacion_at).getTime();
        if (Date.now() - libAt < 30_000) continue;
      }

      const movilId = srv.paradero_auto_movil_id as string;
      if (await movilEstaOcupado(movilId)) continue;

      const asignado = await autoAsignar(
        srv.id,
        movilId,
        [], // No cancelamos onesignal_2m / onesignal_5m — si el móvil estaba libre y acepta,
            // los receptores de fase3/4 verán el servicio ya asignado y no podrán aceptar.
            // Cancelar requeriría llamadas extras; los mobiles simplemente ignorarán la notif.
        '📍 TU TURNO EN EL PARADERO',
        'Un servicio está esperando por ti',
      );

      // Si se asignó exitosamente, limpiar la cola del paradero
      if (asignado) {
        await supabase
          .from('usuarios')
          .update({ paradero_actual: null, ingreso_fila: null })
          .eq('id', parseInt(movilId));
      }
    }
  }

  return new Response('ok', { status: 200 });
});
