-- Agregar columna paradero_origen a la tabla servicios
-- Guarda desde qué paradero se despachó un servicio manual desde la central
ALTER TABLE servicios ADD COLUMN IF NOT EXISTS paradero_origen text;
COMMENT ON COLUMN servicios.paradero_origen IS 'Paradero desde el cual la central despachó este servicio (EXPUENTE, MEMOS, NOCTURNO). Nulo si no aplica.';
