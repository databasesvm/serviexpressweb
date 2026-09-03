-- Cron: procesar cola de notificaciones push cada 2 minutos
-- verify_jwt=false en la función → no se necesita Authorization header.
-- La Edge Function lee SUPABASE_SERVICE_ROLE_KEY y ONESIGNAL_REST_API_KEY de sus secrets.

SELECT cron.unschedule('procesar-notificaciones-push')
WHERE EXISTS (
  SELECT 1 FROM cron.job WHERE jobname = 'procesar-notificaciones-push'
);

SELECT cron.schedule(
  'procesar-notificaciones-push',
  '*/2 * * * *',
  $$
  SELECT net.http_post(
    url     := 'https://oukiofdtargjrclualgm.supabase.co/functions/v1/procesar-notificaciones-push',
    headers := '{"Content-Type":"application/json"}'::jsonb,
    body    := '{}'::jsonb
  );
  $$
);
