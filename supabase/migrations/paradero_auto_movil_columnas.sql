-- Columna para auto-asignación al #1 del paradero en servicios no-FN.
-- El pg_cron (fn-auto-asignar-fase2) la usa a T+30s para asignar
-- automáticamente al móvil sin que deba aceptar.

ALTER TABLE servicios ADD COLUMN IF NOT EXISTS paradero_auto_movil_id text;

-- fn_notif_fase4 (FN — por si no se corrió la migración anterior)
ALTER TABLE servicios ADD COLUMN IF NOT EXISTS fn_notif_fase4 text;
