-- Columna para solicitudes de transferencia entre móviles.
-- El móvil que transfiere guarda aquí el ID del receptor.
-- El receptor ve un diálogo ACEPTAR/RECHAZAR en su teléfono.
-- Al aceptar: movil_id se actualiza y este campo vuelve a NULL.
-- Al rechazar: este campo vuelve a NULL sin cambiar movil_id.

ALTER TABLE servicios ADD COLUMN IF NOT EXISTS transferencia_a_movil_id text;
