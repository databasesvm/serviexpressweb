import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:serviexpress_app/utils/onesignal_api.dart';
import 'package:serviexpress_app/utils/textos_push.dart';

/// F1 SE (T=0) para pedidos de invitado: push solo a Masters en línea, con SE,
/// sin suspensión y con la Billetera al día, con el sonido/canal de Master.
/// [ruta] = texto "ORIGEN → DESTINO" (ver TextosPush.ruta).
Future<void> notificarMastersF1Invitado(String ruta) async {
  final String titulo = TextosPush.f1Titulo;
  final String mensaje = TextosPush.f1Mensaje(ruta);
  try {
    final masters = await Supabase.instance.client
        .from('usuarios')
        .select('id')
        .eq('rol', 'movil')
        .eq('rango_movil', 'MASTER')
        .eq('tiene_se', true)
        .eq('en_linea', true)
        .neq('suspendido', true)
        .or('wallet_bloqueado.is.null,wallet_bloqueado.eq.false');
    final ids = masters.map((u) => u['id'].toString()).toList();
    if (ids.isEmpty) return;
    await MotorNotificaciones.dispararRafa(
      idsDestinos: ids,
      titulo: titulo,
      mensaje: mensaje,
      urgente: true,
      sonido: 'master',
      canalAndroidId: MotorNotificaciones.canalMasterId,
    );
  } catch (_) {}
}

/// Paradero objetivo para la F2 SE de servicios de cliente / invitado.
///
/// La F2 la resuelve el servidor (función SQL `se_f2_huecos`) usando
/// `servicios.paradero_origen`: ofrece al #1 de ese paradero y, si está vacío,
/// al móvil más cercano al origen (con todos los filtros de fase, rango,
/// billetera y suspensión). Las apps ya NO eligen móvil ni mandan el push F2.
///
/// Devuelve el nombre (MAYÚSCULAS) del paradero activo más cercano a
/// (lat, lng), o null si no hay coordenadas o no se pudo consultar.
Future<String?> paraderoMasCercano(double? lat, double? lng) async {
  if (lat == null || lng == null) return null;
  try {
    final paraderos = await Supabase.instance.client
        .from('paraderos')
        .select('nombre, latitud, longitud')
        .eq('activo', true)
        // Solo paraderos de día: de noche el servidor usa NOCTURNO para todos
        .or('es_nocturno.is.null,es_nocturno.eq.false');
    String? mejor;
    double menor = double.infinity;
    for (final p in paraderos) {
      final pLat = (p['latitud'] as num?)?.toDouble();
      final pLng = (p['longitud'] as num?)?.toDouble();
      if (pLat == null || pLng == null) continue;
      final d = const Distance().as(
        LengthUnit.Meter,
        LatLng(lat, lng),
        LatLng(pLat, pLng),
      );
      if (d < menor) {
        menor = d;
        mejor = p['nombre'].toString().trim().toUpperCase();
      }
    }
    return mejor;
  } catch (_) {
    return null;
  }
}
