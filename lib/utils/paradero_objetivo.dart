import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// F1 SE (T=0, Masters) lo manda el SERVIDOR: trigger trg_se_f1_servidor
// cuando la app pone servicios.se_f1_motivo = 'nuevo' / 'liberado'.

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
