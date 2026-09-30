/// Textos únicos de los push SE que envían las apps (F1, servicio liberado y
/// asignación directa). F2, F3, F4, programados y sanciones los arma el
/// servidor con el mismo formato: el título dice la fase y el mensaje explica
/// qué está pasando, con ORIGEN → DESTINO y qué hacer.
class TextosPush {
  TextosPush._();

  /// "ORIGEN → DESTINO" (en mayúsculas). Si falta alguno, usa el que haya.
  static String ruta(String? origen, String? destino) {
    final o = (origen ?? '').trim().toUpperCase();
    final d = (destino ?? '').trim().toUpperCase();
    if (o.isNotEmpty && d.isNotEmpty) return '$o → $d';
    if (o.isNotEmpty) return o;
    if (d.isNotEmpty) return 'Destino $d';
    return 'Nuevo servicio';
  }

  // ── F1 (T=0): solo Masters ────────────────────────────────────────────────
  static const String f1Titulo = '👑 F1 · Turno Master';
  static String f1Mensaje(String ruta) =>
      'Tienes 30 s de prioridad como Master. $ruta. Abre el radar para aceptarlo.';

  // ── Servicio liberado por un móvil (la cascada vuelve a empezar en F1) ────
  static const String liberadoTitulo = '🔄 F1 · Servicio liberado';
  static String liberadoMensaje(String ruta) =>
      'Un móvil soltó este servicio y la cascada vuelve a empezar. $ruta. '
      'Tienes 30 s de prioridad como Master.';

  // ── Asignación directa (exclusivo) ────────────────────────────────────────
  static const String asignadoTitulo = '📌 Servicio asignado a ti';
  static String asignadoMensaje(String quien, String ruta) =>
      '$quien te asignó $ruta. Solo tú lo ves. Abre el radar.';
}
