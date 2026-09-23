-- ─────────────────────────────────────────────────────────────────────────────
-- CONFIG-CASCADA-A: Tiempos de cascada configurables desde la interfaz
--
-- Todos los valores son offsets en SEGUNDOS desde T=0 (creación del servicio).
-- Defaults = comportamiento actual hardcodeado (30s entre cada fase).
-- ─────────────────────────────────────────────────────────────────────────────

-- ── ServiExpress ─────────────────────────────────────────────────────────────
ALTER TABLE config_sistema
  ADD COLUMN IF NOT EXISTS cascada_se_f2_seg int NOT NULL DEFAULT 30,
  ADD COLUMN IF NOT EXISTS cascada_se_f3_seg int NOT NULL DEFAULT 60,
  ADD COLUMN IF NOT EXISTS cascada_se_f4_seg int NOT NULL DEFAULT 90;

COMMENT ON COLUMN config_sistema.cascada_se_f2_seg IS
  'SE — Fase 2: segundos desde T=0 hasta auto-asignar al #1 de la fila del paradero';
COMMENT ON COLUMN config_sistema.cascada_se_f3_seg IS
  'SE — Fase 3: segundos desde T=0 hasta push a todos dentro de 1km del punto de recogida';
COMMENT ON COLUMN config_sistema.cascada_se_f4_seg IS
  'SE — Fase 4: segundos desde T=0 hasta push a todos los disponibles (sin límite de distancia)';

-- ── FN La Cascada ─────────────────────────────────────────────────────────────
ALTER TABLE config_sistema
  ADD COLUMN IF NOT EXISTS cascada_fn_f2_seg         int NOT NULL DEFAULT 30,
  ADD COLUMN IF NOT EXISTS cascada_fn_f3_seg         int NOT NULL DEFAULT 60,
  ADD COLUMN IF NOT EXISTS cascada_fn_f4_seg         int NOT NULL DEFAULT 90,
  ADD COLUMN IF NOT EXISTS cascada_fn_f2_timeout_seg int NOT NULL DEFAULT 30;

COMMENT ON COLUMN config_sistema.cascada_fn_f2_seg IS
  'FN — Fase 2: segundos desde T=0 hasta ofrecer el servicio al móvil más cercano a la sede (debe aceptar)';
COMMENT ON COLUMN config_sistema.cascada_fn_f3_seg IS
  'FN — Fase 3: segundos desde T=0 hasta push a no-Masters dentro de 2km de la sede';
COMMENT ON COLUMN config_sistema.cascada_fn_f4_seg IS
  'FN — Fase 4: segundos desde T=0 hasta push global a todos los disponibles conectados';
COMMENT ON COLUMN config_sistema.cascada_fn_f2_timeout_seg IS
  'FN — Timeout F2: segundos que tiene el móvil pre-asignado para aceptar antes de liberar a F3';
