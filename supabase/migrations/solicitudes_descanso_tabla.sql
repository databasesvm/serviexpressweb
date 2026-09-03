-- Solicitudes de descanso que el móvil envía a Central.
-- Central puede aprobar o rechazar.
-- Si Central no responde antes de fecha_inicio → se auto-aprueba por el cron.
-- Durante los días aprobados el contador de inactividad no se incrementa.

CREATE TABLE IF NOT EXISTS solicitudes_descanso (
  id                bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  movil_id          bigint      NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
  fecha_inicio      date        NOT NULL,
  fecha_fin         date        NOT NULL,
  dias_solicitados  integer     NOT NULL,
  razon             text        NOT NULL,
  estado            text        NOT NULL DEFAULT 'pendiente',  -- pendiente | aprobado | rechazado
  aprobado_por      text,       -- nombre del operador de Central o 'sistema'
  aprobado_at       timestamptz,
  rechazado_motivo  text,
  created_at        timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT solicitudes_estado_valido CHECK (estado IN ('pendiente', 'aprobado', 'rechazado')),
  CONSTRAINT solicitudes_fechas_validas CHECK (fecha_fin >= fecha_inicio)
);
