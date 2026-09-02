-- Columnas de auditoría para transferencias de servicio entre móviles.
-- transferido: true cuando el servicio fue cedido por un móvil a otro.
-- transferido_de_movil_id: ID del móvil que cedió el servicio.
-- transferido_at: momento exacto en que el receptor aceptó.
-- Permite a la Central y soporte reconstruir quién tenía el servicio y
-- cuándo cambió de manos, sin depender de logs externos.

ALTER TABLE servicios ADD COLUMN IF NOT EXISTS transferido boolean DEFAULT false;
ALTER TABLE servicios ADD COLUMN IF NOT EXISTS transferido_de_movil_id text;
ALTER TABLE servicios ADD COLUMN IF NOT EXISTS transferido_at timestamptz;

-- Auditoría de rechazos de transferencia
ALTER TABLE servicios ADD COLUMN IF NOT EXISTS transferencia_rechazada boolean DEFAULT false;
ALTER TABLE servicios ADD COLUMN IF NOT EXISTS transferencia_rechazada_por text;
ALTER TABLE servicios ADD COLUMN IF NOT EXISTS transferencia_rechazada_at timestamptz;
