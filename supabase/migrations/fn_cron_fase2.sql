-- Habilitar extensiones requeridas (si no están activas)
create extension if not exists pg_cron;
create extension if not exists pg_net;

-- Eliminar job existente si ya hay uno con el mismo nombre
select cron.unschedule('fn-auto-asignar-fase2') where exists (
  select 1 from cron.job where jobname = 'fn-auto-asignar-fase2'
);

-- Crear job: corre cada minuto, llama la Edge Function
select cron.schedule(
  'fn-auto-asignar-fase2',
  '* * * * *',
  $$
  select net.http_post(
    url      := 'https://oukiofdtargjrclualgm.supabase.co/functions/v1/fn-auto-asignar-fase2',
    headers  := jsonb_build_object(
      'Content-Type',  'application/json',
      'Authorization', 'Bearer ' || current_setting('app.supabase_service_role_key', true)
    ),
    body     := '{}'::jsonb
  ) as request_id;
  $$
);

-- ALTERNATIVA si current_setting no funciona en tu plan:
-- Reemplaza la línea Authorization con el service role key literal:
--   'Authorization', 'Bearer eyJhbGc...<tu service role key>'
