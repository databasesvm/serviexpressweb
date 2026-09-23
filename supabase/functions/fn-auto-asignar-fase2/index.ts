// supabase/functions/fn-auto-asignar-fase2/index.ts
//
// Corre cada minuto via pg_cron.
// Maneja TRES flujos:
//
//   0. [CONFIG-CASCADA-B] Liberar FN pre-asignados (directo_presel) que superaron
//      el timeout de aceptación (cascada_fn_f2_timeout_seg) → resetear a cascada F3/F4.
//
//   1. Servicios FN (tipo_fn = true):
//      Busca fn_fase2_movil_id + fn_radar_t0 ≥ cascada_fn_f2_seg atrás.
//      Pre-asigna al más cercano. Si libre → cancela F3/F4. Si ocupado → solo push.
//
//   2. Servicios no-FN (tipo_fn = false / null):
//      Busca paradero_auto_movil_id + created_at/liberacion_at ≥ cascada_se_f2_seg.
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

const restKey    = Deno.env.get('ONESIGNAL_REST_API_KEY') ?? '';
const authHeader = restKey.startsWith('os_v2_') ? `Key ${restKey}` : `Basic ${restKey}`;

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

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
    console.warn(`[auto-asignar] Error headsup a ${movilId}:`, e);
  }
}

async function enviarPushGrupo(ids: string[], titulo: string, mensaje: string) {
  if (ids.length === 0) return;
  try {
    await fetch(SEND_NOTIF_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        app_id: ONESIGNAL_APP_ID,
        include_external_user_ids: ids,
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
    console.warn(`[auto-asignar] Error push grupo:`, e);
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

// Auto-asignación SE: cambia estado a en_ruta_origen (el #1 del paradero queda activo).
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
    .eq('estado', 'pendiente')
    .is('movil_id', null); // guard anti-doble-asignación

  if (error) {
    console.error(`[auto-asignar] Error asignando srv ${srvId}:`, error.message);
    return false;
  }

  for (const n of notifCancelar) await cancelarNotif(n);
  await enviarHeadsup(movilId, titulo, mensaje);
  console.log(`[auto-asignar] Srv ${srvId} → móvil ${movilId} ✓`);
  return true;
}

// Pre-asignación FN: el móvil debe confirmar. Si está libre cancela F3/F4.
async function preasignarFn(
  srvId: number,
  movilId: string,
  notifCancelar: (string | null)[],
): Promise<void> {
  const ocupado = await movilEstaOcupado(movilId);

  if (!ocupado) {
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

    for (const n of notifCancelar) await cancelarNotif(n);
    await enviarHeadsup(movilId, '🎯 SERVICIO FN PARA TI', 'Un servicio FN quedó asignado a ti — confírmalo en la app');
    console.log(`[fn-fase2] Srv ${srvId} pre-asignado libre → móvil ${movilId} ✓`);
  } else {
    // Ocupado: solo push. El servicio sigue en cascada abierta (F3/F4).
    await enviarHeadsup(movilId, '🔵 SERVICIO FN CERCANO', 'Hay un servicio FN cerca — revisa si te conviene la ruta');
    console.log(`[fn-fase2] Srv ${srvId} → móvil ${movilId} ocupado, solo push`);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Handler principal
// ─────────────────────────────────────────────────────────────────────────────

Deno.serve(async () => {
  // ── Leer tiempos de cascada configurados en BD ────────────────────────────
  const { data: cfg } = await supabase
    .from('config_sistema')
    .select('cascada_se_f2_seg, cascada_fn_f2_seg, cascada_fn_f2_timeout_seg')
    .single();

  const seFase2Ms   = (cfg?.cascada_se_f2_seg          ?? 30) * 1000;
  const fnFase2Ms   = (cfg?.cascada_fn_f2_seg           ?? 30) * 1000;
  const fnTimeoutMs = (cfg?.cascada_fn_f2_timeout_seg   ?? 30) * 1000;

  // Umbral SE: cuándo ha pasado suficiente tiempo para auto-asignar #1 paradero
  const umbralSE = new Date(Date.now() - seFase2Ms).toISOString();

  // Umbral FN F2: cuándo ofrecer al móvil más cercano
  const umbralFN = new Date(Date.now() - fnFase2Ms).toISOString();

  // Umbral de release: fn_radar_t0 debe ser anterior a (ahora - f2 - timeout)
  // Ej: f2=30s, timeout=30s → el servicio lleva ≥60s sin ser aceptado
  const umbralRelease = new Date(Date.now() - (fnFase2Ms + fnTimeoutMs)).toISOString();

  // ── 0. LIBERAR FN pre-asignados que no aceptaron en el timeout ────────────
  {
    const { data: expirados } = await supabase
      .from('servicios')
      .select('id, movil_id')
      .eq('fn_asignacion_tipo', 'directo_presel')
      .eq('estado', 'pendiente')
      .not('movil_id', 'is', null)
      .lte('fn_radar_t0', umbralRelease);

    for (const srv of expirados ?? []) {
      // Liberar: quitar movil_id y volver a modo radar para F3/F4
      const { error } = await supabase
        .from('servicios')
        .update({ movil_id: null, fn_asignacion_tipo: 'radar' })
        .eq('id', srv.id)
        .eq('fn_asignacion_tipo', 'directo_presel'); // guard anti-doble

      if (error) {
        console.error(`[fn-timeout] Error liberando srv ${srv.id}:`, error.message);
        continue;
      }

      console.log(`[fn-timeout] Srv ${srv.id} — timeout F2, liberando a cascada F3/F4`);

      // Informar al móvil que perdió la ventana
      await enviarHeadsup(
        srv.movil_id.toString(),
        '⏰ Tiempo agotado',
        'No aceptaste el servicio FN a tiempo — fue liberado a otros',
      );

      // Re-disparar push a no-Masters FN disponibles (F3 + F4 combinados).
      // Los misiles OneSignal originales ya fueron cancelados al pre-asignar,
      // así que notificamos directamente desde aquí.
      const { data: disponibles } = await supabase
        .from('usuarios')
        .select('id')
        .eq('en_linea', true)
        .eq('tiene_fn', true)
        .eq('activo', true)
        .neq('rango_movil', 'master')
        .neq('id', srv.movil_id)
        .or('suspendido.is.null,suspendido.eq.false')
        .or('bloqueado_inactividad.is.null,bloqueado_inactividad.eq.false');

      const ids = (disponibles ?? []).map((u: { id: number }) => u.id.toString());
      await enviarPushGrupo(
        ids,
        '🟣 SERVICIO FN DISPONIBLE',
        'Un servicio FN quedó disponible — revísalo ahora',
      );
      console.log(`[fn-timeout] Srv ${srv.id} — re-push a ${ids.length} no-Masters disponibles`);
    }
  }

  // ── 1. SERVICIOS FN — pre-asignar al más cercano ─────────────────────────
  {
    const { data: serviciosFN } = await supabase
      .from('servicios')
      .select('id, fn_fase2_movil_id, fn_notif_fase3, fn_notif_fase4, fn_notif_fase4b')
      .eq('fn_asignacion_tipo', 'radar')
      .eq('estado', 'pendiente')
      .eq('tipo_fn', true)
      .not('fn_fase2_movil_id', 'is', null)
      .is('movil_id', null)
      .lte('fn_radar_t0', umbralFN);

    for (const srv of serviciosFN ?? []) {
      await preasignarFn(
        srv.id,
        srv.fn_fase2_movil_id as string,
        // fn_notif_fase4b = re-alerta Masters T+90s — también cancela para no spamear
        [srv.fn_notif_fase3, srv.fn_notif_fase4, srv.fn_notif_fase4b],
      );
    }
  }

  // ── 2. SERVICIOS NO-FN — #1 DEL PARADERO ─────────────────────────────────
  // El anchor de tiempo es GREATEST(created_at, COALESCE(liberacion_at, created_at)).
  {
    const { data: serviciosNormal } = await supabase
      .from('servicios')
      .select('id, paradero_auto_movil_id, onesignal_2m, onesignal_5m, liberacion_at, created_at')
      .eq('estado', 'pendiente')
      .is('tipo_fn', null)    // no-FN
      .not('paradero_auto_movil_id', 'is', null)
      .is('movil_id', null)
      .lte('created_at', umbralSE);

    for (const srv of serviciosNormal ?? []) {
      // Si liberacion_at existe y es más reciente, verificar que también pasaron seFase2Ms
      if (srv.liberacion_at) {
        const libAt = new Date(srv.liberacion_at).getTime();
        if (Date.now() - libAt < seFase2Ms) continue;
      }

      const movilId = srv.paradero_auto_movil_id as string;
      if (await movilEstaOcupado(movilId)) continue;

      const asignado = await autoAsignar(
        srv.id,
        movilId,
        [srv.onesignal_2m, srv.onesignal_5m], // cancelar F3/F4 para no spamear
        '📍 TU TURNO EN EL PARADERO',
        'Un servicio está esperando por ti',
      );

      // Si se asignó exitosamente, sacar al móvil de la fila del paradero
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
