-- ─────────────────────────────────────────────────────────────────────────────
-- TRIGGER: resetear contador cuando el móvil hace ping (se conecta)
-- No toca bloqueado_inactividad → solo Central puede reactivar manualmente.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_reset_contador_al_conectar()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.ultimo_ping IS DISTINCT FROM OLD.ultimo_ping AND NEW.ultimo_ping IS NOT NULL THEN
    NEW.dias_inactivos_acumulados := 0;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_reset_inactividad ON usuarios;
CREATE TRIGGER trg_reset_inactividad
  BEFORE UPDATE OF ultimo_ping ON usuarios
  FOR EACH ROW
  EXECUTE FUNCTION fn_reset_contador_al_conectar();

-- ─────────────────────────────────────────────────────────────────────────────
-- FUNCIÓN PRINCIPAL: control diario de inactividad
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_control_inactividad()
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  hoy        date := (now() AT TIME ZONE 'America/Bogota')::date;
  dia_semana int  := EXTRACT(DOW FROM (now() AT TIME ZONE 'America/Bogota'))::int;
  mov        RECORD;
  en_descanso boolean;
  ping_hoy    boolean;
BEGIN

  -- ── 1. AUTO-APROBAR solicitudes pendientes cuya fecha_inicio ya llegó ──────
  UPDATE solicitudes_descanso
  SET    estado       = 'aprobado',
         aprobado_por = 'sistema',
         aprobado_at  = now()
  WHERE  estado       = 'pendiente'
    AND  fecha_inicio <= hoy;

  -- Encolar notificación de aprobación automática al móvil
  INSERT INTO notificaciones_push_pendientes
    (destinatario_id, titulo, cuerpo, tipo)
  SELECT sd.movil_id,
         '✅ Descanso aprobado',
         'Tu solicitud de descanso fue aprobada automáticamente por el sistema.',
         'descanso_aprobado'
  FROM   solicitudes_descanso sd
  WHERE  sd.aprobado_por = 'sistema'
    AND  sd.aprobado_at::date = hoy;

  -- ── 2. Procesar cada móvil activo ──────────────────────────────────────────
  FOR mov IN
    SELECT id, usuario, dia_descanso_semanal,
           bloqueado_inactividad, dias_inactivos_acumulados,
           COALESCE(ultimo_ping, created_at) AS ultimo_ping_real
    FROM   usuarios
    WHERE  rol    = 'movil'
      AND  (eliminado  IS NULL OR eliminado  = false)
      AND  (suspendido IS NULL OR suspendido = false)
  LOOP

    -- ¿Está de descanso hoy?
    en_descanso := false;

    IF mov.dia_descanso_semanal IS NOT NULL
       AND mov.dia_descanso_semanal = dia_semana THEN
      en_descanso := true;
    END IF;

    IF NOT en_descanso THEN
      SELECT EXISTS (
        SELECT 1 FROM solicitudes_descanso
        WHERE  movil_id    = mov.id
          AND  estado      = 'aprobado'
          AND  fecha_inicio <= hoy
          AND  fecha_fin   >= hoy
      ) INTO en_descanso;
    END IF;

    CONTINUE WHEN en_descanso;

    -- ¿No se conectó hoy? → incrementar contador
    ping_hoy := (mov.ultimo_ping_real::date >= hoy);

    IF NOT ping_hoy THEN
      UPDATE usuarios
      SET    dias_inactivos_acumulados = dias_inactivos_acumulados + 1
      WHERE  id = mov.id
      RETURNING dias_inactivos_acumulados INTO mov.dias_inactivos_acumulados;
    END IF;

    -- ── 3 días: bloquear y notificar a Central ─────────────────────────────
    IF mov.dias_inactivos_acumulados >= 3 AND NOT mov.bloqueado_inactividad THEN
      UPDATE usuarios SET bloqueado_inactividad = true WHERE id = mov.id;

      INSERT INTO notificaciones_push_pendientes
        (destinatario_id, destinatario_rol, titulo, cuerpo, tipo)
      VALUES
        (null, 'central',
         '⚠️ Móvil inactivo',
         mov.usuario || ' lleva 3 días sin conectarse. ¿Reactivar o liberar número?',
         'inactividad_bloqueo');
    END IF;

    -- ── Bloqueado + sin conectar 7 días adicionales: eliminar ──────────────
    IF mov.bloqueado_inactividad
       AND mov.ultimo_ping_real < now() - interval '7 days' THEN
      UPDATE usuarios
      SET    eliminado    = true,
             eliminado_at = now(),
             activo       = false
      WHERE  id = mov.id;

      INSERT INTO notificaciones_push_pendientes
        (destinatario_id, titulo, cuerpo, tipo)
      VALUES
        (mov.id,
         '⛔ Cuenta desactivada',
         'Tu cuenta fue desactivada por inactividad prolongada. Contacta a soporte para reactivarla.',
         'inactividad_eliminacion');
    END IF;

  END LOOP;
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- CRON JOB: cada día a las 00:05 hora Colombia (05:05 UTC)
-- ─────────────────────────────────────────────────────────────────────────────
SELECT cron.unschedule('control-inactividad-moviles') WHERE EXISTS (
  SELECT 1 FROM cron.job WHERE jobname = 'control-inactividad-moviles'
);

SELECT cron.schedule(
  'control-inactividad-moviles',
  '5 5 * * *',
  'SELECT fn_control_inactividad()'
);
