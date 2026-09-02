-- Migración: añadir columna 'sector' a red_direcciones
-- Ejecutar en Supabase SQL Editor

ALTER TABLE red_direcciones ADD COLUMN IF NOT EXISTS sector text;

-- Índice para filtrar por sector rápidamente
CREATE INDEX IF NOT EXISTS idx_red_direcciones_sector ON red_direcciones(sector);

-- Ejemplos de sectores para clasificar las direcciones existentes:
-- UPDATE red_direcciones SET sector = 'TRAPICHES' WHERE nombre ILIKE '%trapiche%';
-- UPDATE red_direcciones SET sector = 'PRADOS DEL ESTE' WHERE nombre ILIKE '%prado%';
-- UPDATE red_direcciones SET sector = 'CENTRO' WHERE nombre ILIKE '%centro%';
-- UPDATE red_direcciones SET sector = 'EL BOSQUE' WHERE nombre ILIKE '%bosque%';
