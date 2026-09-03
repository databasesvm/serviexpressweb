-- Sistema de inactividad y descanso para móviles
-- bloqueado_inactividad : se activa al 3er día consecutivo sin conectar (sin contar descansos)
-- eliminado             : soft-delete tras 7 días bloqueado sin reconectar
-- dias_inactivos_acumulados: contador diario; se reinicia cuando el móvil hace ping
-- dia_descanso_semanal  : día fijo libre cada semana (0=dom … 6=sab), excluido del conteo

ALTER TABLE usuarios ADD COLUMN IF NOT EXISTS bloqueado_inactividad      boolean   DEFAULT false;
ALTER TABLE usuarios ADD COLUMN IF NOT EXISTS eliminado                   boolean   DEFAULT false;
ALTER TABLE usuarios ADD COLUMN IF NOT EXISTS eliminado_at                timestamptz;
ALTER TABLE usuarios ADD COLUMN IF NOT EXISTS dias_inactivos_acumulados  integer   DEFAULT 0;
ALTER TABLE usuarios ADD COLUMN IF NOT EXISTS dia_descanso_semanal       integer;   -- null = sin día fijo
