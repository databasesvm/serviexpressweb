-- Tipo de plan del móvil y número real separado del campo usuario
-- tipo_plan_movil   : suscripcion (01-100) | prediario (200-299) | postdia (200-299)
-- numero_movil      : número entero del móvil, único entre activos
-- eliminado_por     : quién eliminó la cuenta (usuario | sistema | central)
-- ultima_servicio_completado_at : para medir inactividad real (no pings)

ALTER TABLE usuarios ADD COLUMN IF NOT EXISTS tipo_plan_movil              text;
ALTER TABLE usuarios ADD COLUMN IF NOT EXISTS numero_movil                 integer;
ALTER TABLE usuarios ADD COLUMN IF NOT EXISTS eliminado_por                text;
ALTER TABLE usuarios ADD COLUMN IF NOT EXISTS ultima_servicio_completado_at timestamptz;

ALTER TABLE usuarios DROP CONSTRAINT IF EXISTS tipo_plan_movil_valido;
ALTER TABLE usuarios ADD CONSTRAINT tipo_plan_movil_valido
  CHECK (tipo_plan_movil IS NULL OR tipo_plan_movil IN ('suscripcion', 'prediario', 'postdia'));

ALTER TABLE usuarios DROP CONSTRAINT IF EXISTS eliminado_por_valido;
ALTER TABLE usuarios ADD CONSTRAINT eliminado_por_valido
  CHECK (eliminado_por IS NULL OR eliminado_por IN ('usuario', 'sistema', 'central'));
