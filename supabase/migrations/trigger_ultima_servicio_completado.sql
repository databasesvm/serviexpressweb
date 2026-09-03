-- Trigger: cuando un servicio cambia a 'completado', actualiza ultima_servicio_completado_at
-- en el móvil asignado. Esto es lo que resetea el contador de inactividad.

CREATE OR REPLACE FUNCTION fn_actualizar_ultima_servicio()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.estado = 'completado' AND (OLD.estado IS DISTINCT FROM 'completado') THEN
    IF NEW.movil_id IS NOT NULL THEN
      UPDATE usuarios
      SET    ultima_servicio_completado_at = now()
      WHERE  id = NEW.movil_id;
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_ultima_servicio_completado ON servicios;
CREATE TRIGGER trg_ultima_servicio_completado
  AFTER UPDATE OF estado ON servicios
  FOR EACH ROW
  EXECUTE FUNCTION fn_actualizar_ultima_servicio();
