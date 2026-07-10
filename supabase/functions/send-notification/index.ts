// supabase/functions/send-notification/index.ts
// Proxy entre Flutter y OneSignal.
// La REST API Key vive aquí como secret (ONESIGNAL_REST_KEY) — nunca en el APK.
//
// Acciones:
//   POST { action: 'cancel', notification_id: '...' }  → cancela un misil programado
//   POST { app_id, include_external_user_ids, ... }     → dispara notificación normal

const ONESIGNAL_APP_ID = '207d1d0a-0218-46e0-9f35-7d8d88f6765a';
const ONESIGNAL_API   = 'https://onesignal.com/api/v1/notifications';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  const restKey = Deno.env.get('ONESIGNAL_REST_KEY') ?? '';

  try {
    const body = await req.json();

    // ── ACCIÓN: CANCELAR MISIL PROGRAMADO ─────────────────────────────────
    if (body.action === 'cancel') {
      const notifId = body.notification_id as string | undefined;
      if (!notifId) {
        return new Response(JSON.stringify({ error: 'notification_id requerido' }), {
          status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        });
      }

      const r = await fetch(
        `${ONESIGNAL_API}/${notifId}?app_id=${ONESIGNAL_APP_ID}`,
        {
          method: 'DELETE',
          headers: { Authorization: `Basic ${restKey}` },
        },
      );

      const data = await r.json().catch(() => ({}));
      return new Response(JSON.stringify(data), {
        status: r.status,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // ── ACCIÓN: DISPARO NORMAL ─────────────────────────────────────────────
    // Asegurar que el app_id venga correcto (por si el cliente no lo envía)
    body.app_id = ONESIGNAL_APP_ID;

    // FIX CRÍTICO: cuando se usan include_external_user_ids, la API v1 de
    // OneSignal requiere channel_for_external_user_ids = 'push'. Sin este
    // campo la solicitud devuelve 200 OK pero recipients = 0 (silencio total).
    if (body.include_external_user_ids && !body.channel_for_external_user_ids) {
      body.channel_for_external_user_ids = 'push';
    }

    const r = await fetch(ONESIGNAL_API, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json; charset=utf-8',
        Authorization: `Basic ${restKey}`,
      },
      body: JSON.stringify(body),
    });

    const data = await r.json().catch(() => ({}));
    return new Response(JSON.stringify(data), {
      status: r.status,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });

  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
