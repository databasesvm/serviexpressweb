-- Toggle para activar/desactivar el bloqueo automático por inactividad
-- Desactivado por defecto (modo beta/mantenimiento)
ALTER TABLE config_sistema ADD COLUMN IF NOT EXISTS bloqueo_inactividad_activo boolean NOT NULL DEFAULT false;
