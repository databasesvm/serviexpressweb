-- Cola de notificaciones push que el pg_cron genera y una Edge Function envía a OneSignal.
-- destinatario_id  : ID del usuario destino (null = broadcast por rol)
-- destinatario_rol : 'central' | 'master' | 'movil' (usado cuando destinatario_id es null)
-- tipo             : identifica el sonido y la pantalla destino en el cliente Flutter

CREATE TABLE IF NOT EXISTS notificaciones_push_pendientes (
  id               bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  destinatario_id  bigint,
  destinatario_rol text,
  titulo           text        NOT NULL,
  cuerpo           text        NOT NULL,
  tipo             text        NOT NULL,  -- inactividad_bloqueo | inactividad_eliminacion | descanso_aprobado | descanso_rechazado | descanso_solicitud
  procesado        boolean     NOT NULL DEFAULT false,
  procesado_at     timestamptz,
  created_at       timestamptz NOT NULL DEFAULT now()
);
