import 'package:supabase_flutter/supabase_flutter.dart';

/// Reloj alineado con el servidor.
///
/// Los tiempos de la cascada (created_at, liberacion_at, se_cascade_t0,
/// accepted_at…) los pone el servidor. Si el teléfono tiene la hora corrida,
/// comparar contra DateTime.now() muestra fases y contadores equivocados.
/// [ahoraUtc] devuelve la hora del teléfono corregida con la diferencia
/// medida contra el servidor (RPC `hora_servidor`).
class HoraServidor {
  HoraServidor._();

  static Duration _desfase = Duration.zero;
  static DateTime? _ultimaSync;

  /// Hora actual en UTC, alineada con el servidor.
  static DateTime ahoraUtc() => DateTime.now().toUtc().add(_desfase);

  /// Mide la diferencia con el servidor. Si falla, se queda con la anterior
  /// (al inicio, cero = hora del teléfono, como antes).
  static Future<void> sincronizar({bool forzar = false}) async {
    if (!forzar &&
        _ultimaSync != null &&
        DateTime.now().difference(_ultimaSync!).inMinutes < 5) {
      return;
    }
    try {
      final antes = DateTime.now().toUtc();
      final r = await Supabase.instance.client.rpc('hora_servidor');
      final despues = DateTime.now().toUtc();
      final servidor = DateTime.parse(r.toString()).toUtc();
      // Compensa la demora de la red: el servidor respondió a mitad del viaje.
      final medio = antes.add(despues.difference(antes) ~/ 2);
      _desfase = servidor.difference(medio);
      _ultimaSync = DateTime.now();
    } catch (_) {}
  }
}
