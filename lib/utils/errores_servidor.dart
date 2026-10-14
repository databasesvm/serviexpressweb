// lib/utils/errores_servidor.dart
//
// Traduce los rechazos del candado de estados del servidor
// (trigger trg_aa_candado_estado) a mensajes claros. Pasa cuando la
// pantalla tenía datos viejos: p. ej. la central canceló el servicio
// y el móvil tocó FINALIZAR antes de que le llegara el cambio.

String textoError(Object e) {
  final t = e.toString();
  if (t.contains('servicio_cerrado')) {
    final est = RegExp(r'ya está (\w+)').firstMatch(t)?.group(1) ?? '';
    final legible = switch (est) {
      'cancelado' => 'fue cancelado',
      'finalizado' ||
      'finalizado_con_problema' ||
      'finalizado_por_demora' =>
        'ya fue finalizado',
      _ => 'ya está cerrado',
    };
    return 'Este servicio $legible. La pantalla se actualizará.';
  }
  if (t.contains('estado_invalido')) {
    return 'El servicio cambió mientras lo tenías abierto. La pantalla se actualizará.';
  }
  if (t.contains('no_es_tuyo')) {
    return 'Este servicio ya no está asignado a ti.';
  }
  if (t.contains('muy_pronto')) {
    return 'Debes esperar al menos 5 minutos desde tu llegada a la sede antes de finalizar.';
  }
  return 'Error: $e';
}
