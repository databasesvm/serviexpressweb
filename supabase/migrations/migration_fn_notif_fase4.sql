-- Agrega columna fn_notif_fase4 para almacenar el ID de la notificación
-- OneSignal de la fase global de la cascada FN (T+90s).
-- Se usa para cancelar la notificación al liberar o aceptar el servicio.

ALTER TABLE servicios ADD COLUMN IF NOT EXISTS fn_notif_fase4 text;
