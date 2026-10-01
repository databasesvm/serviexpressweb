// lib/utils/cascada_config.dart
//
// Helper compartido para leer los tiempos de cascada desde config_sistema.
// Usado por cualquier pantalla que programe misiles OneSignal al crear servicios.
//
// Uso:
//   final cascada = await CascadaConfig.cargar();
//   segundosRetardo: cascada.seF3Seg   // en vez de hardcodear 60
//   segundosRetardo: cascada.fnF4Seg   // en vez de hardcodear 90
//
// Si la BD no responde devuelve los defaults (comportamiento original).

import 'package:supabase_flutter/supabase_flutter.dart';

class CascadaConfig {
  // ── ServiExpress ──────────────────────────────────────────────────────────
  /// T=0 + seF2Seg → auto-asigna #1 del paradero (edge fn)
  final int seF2Seg;
  /// T=0 + seF3Seg → push a todos dentro de 1km del punto de recogida
  final int seF3Seg;
  /// T=0 + seF4Seg → push a todos los disponibles (sin límite de distancia)
  final int seF4Seg;

  // ── FN La Cascada ─────────────────────────────────────────────────────────
  /// T=0 + fnF2Seg → ofrece el servicio al móvil más cercano (debe aceptar)
  final int fnF2Seg;
  /// Segundos que tiene el móvil pre-asignado para aceptar antes de liberar a F3
  final int fnF2TimeoutSeg;
  /// T=0 + fnF3Seg → push a no-Masters dentro de 2km de la sede
  final int fnF3Seg;
  /// T=0 + fnF4Seg → push global a todos los disponibles conectados
  final int fnF4Seg;

  const CascadaConfig({
    this.seF2Seg       = 30,
    this.seF3Seg       = 60,
    this.seF4Seg       = 90,
    this.fnF2Seg       = 30,
    this.fnF2TimeoutSeg = 30,
    this.fnF3Seg       = 60,
    this.fnF4Seg       = 90,
  });

  /// Carga los tiempos desde config_sistema. Si falla, retorna los defaults
  /// (equivalente al comportamiento hardcodeado original).
  // Caché en memoria (5 min): antes cada tarjeta de servicio volvía a
  // consultar los tiempos al aparecer (~4.000 consultas/día).
  static Future<CascadaConfig>? _cacheFut;
  static DateTime? _cacheAt;

  static Future<CascadaConfig> cargar() {
    final ahora = DateTime.now();
    if (_cacheFut == null ||
        _cacheAt == null ||
        ahora.difference(_cacheAt!).inMinutes >= 5) {
      _cacheAt = ahora;
      _cacheFut = _cargarDesdeBd();
    }
    return _cacheFut!;
  }

  /// Fuerza recarga en el próximo uso (p. ej. tras editar los tiempos).
  static void invalidar() => _cacheFut = null;

  static Future<CascadaConfig> _cargarDesdeBd() async {
    try {
      final row = await Supabase.instance.client
          .from('config_sistema')
          .select(
            'cascada_se_f2_seg, cascada_se_f3_seg, cascada_se_f4_seg, '
            'cascada_fn_f2_seg, cascada_fn_f2_timeout_seg, '
            'cascada_fn_f3_seg, cascada_fn_f4_seg',
          )
          .eq('id', 1)
          .single();
      return CascadaConfig(
        seF2Seg:        (row['cascada_se_f2_seg']          as int?) ?? 30,
        seF3Seg:        (row['cascada_se_f3_seg']          as int?) ?? 60,
        seF4Seg:        (row['cascada_se_f4_seg']          as int?) ?? 90,
        fnF2Seg:        (row['cascada_fn_f2_seg']          as int?) ?? 30,
        fnF2TimeoutSeg: (row['cascada_fn_f2_timeout_seg']  as int?) ?? 30,
        fnF3Seg:        (row['cascada_fn_f3_seg']          as int?) ?? 60,
        fnF4Seg:        (row['cascada_fn_f4_seg']          as int?) ?? 90,
      );
    } catch (_) {
      // Si hay error de red o BD, usa defaults (comportamiento original)
      _cacheFut = null; // reintentar en el próximo uso
      return const CascadaConfig();
    }
  }
}
