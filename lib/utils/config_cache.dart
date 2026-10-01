// lib/utils/config_cache.dart
//
// Caché en memoria para consultas que antes se repetían en cada redibujo
// de pantalla (FutureBuilder con la consulta escrita dentro de build).
// Ahorra miles de consultas al día a Supabase sin cambiar lo que se ve.

import 'package:supabase_flutter/supabase_flutter.dart';

class ConfigCache {
  // ── "Cómo y dónde pagar" (config_sistema.info_recarga_wallet) ───────────
  // Casi nunca cambia: se guarda 10 min.
  static Future<Map<String, dynamic>?>? _infoRecargaFut;
  static DateTime? _infoRecargaAt;

  static Future<Map<String, dynamic>?> infoRecarga() {
    final ahora = DateTime.now();
    if (_infoRecargaFut == null ||
        _infoRecargaAt == null ||
        ahora.difference(_infoRecargaAt!).inMinutes >= 10) {
      _infoRecargaAt = ahora;
      _infoRecargaFut = Supabase.instance.client
          .from('config_sistema')
          .select('info_recarga_wallet')
          .eq('id', 1)
          .maybeSingle()
          .catchError((_) {
        _infoRecargaFut = null; // reintentar en el próximo uso
        return null;
      });
    }
    return _infoRecargaFut!;
  }

  // ── Solicitud de pago/recarga pendiente del móvil ───────────────────────
  // Se vuelve a consultar solo si:
  //  • cambia el estado de la billetera en el perfil (central aprobó/bloqueó),
  //  • el móvil acaba de enviar una solicitud (invalidarSolicitudes),
  //  • o pasaron 2 min (por si la central la rechazó).
  static final Map<String, Future<List<dynamic>>> _solFut = {};
  static final Map<String, DateTime> _solAt = {};
  static final Map<String, String> _solEstado = {};

  static Future<List<dynamic>> solicitudPendiente({
    required dynamic movilId,
    required String columnas,
    List<String>? tipos,
    required String estadoBilletera,
  }) {
    final clave = '$movilId|$columnas|${tipos?.join(",") ?? "*"}';
    final ahora = DateTime.now();
    final previo = _solFut[clave];
    final vencido = _solAt[clave] == null ||
        ahora.difference(_solAt[clave]!).inMinutes >= 2;
    if (previo != null && !vencido && _solEstado[clave] == estadoBilletera) {
      return previo;
    }
    var q = Supabase.instance.client
        .from('solicitudes_recarga_wallet')
        .select(columnas)
        .eq('movil_id', movilId)
        .eq('estado', 'pendiente');
    if (tipos != null) q = q.inFilter('tipo_solicitud', tipos);
    final fut = q
        .order('created_at', ascending: false)
        .limit(1)
        .then((d) => List<dynamic>.from(d))
        .catchError((_) {
      _solFut.remove(clave);
      return <dynamic>[];
    });
    _solFut[clave] = fut;
    _solAt[clave] = ahora;
    _solEstado[clave] = estadoBilletera;
    return fut;
  }

  /// Llamar después de que el móvil envía una solicitud nueva.
  static void invalidarSolicitudes() {
    _solFut.clear();
    _solAt.clear();
    _solEstado.clear();
  }

  /// Clave del estado de billetera del perfil: si cambia, se re-consulta.
  static String estadoBilletera(Map<String, dynamic> perfil) =>
      '${perfil['wallet_bloqueado']}|${perfil['saldo_wallet']}|'
      '${perfil['tipo_plan_movil']}|${perfil['recargo_mora_activo']}';
}
