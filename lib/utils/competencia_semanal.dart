// Competencia semanal de puntos (premio de la semana).
//
// Puntos: +1 por servicio ServiExpress finalizado (+2 por PAP). Se reinician
// cada lunes. Premio (servidor, fn_calcular_premios_semanales): los 3 que más
// puntos hicieron entre quienes pasaron de 80 → 1° no paga semana, 2° 75 %,
// 3° 50 %. Aquí solo se calcula el PODIO para mostrarlo (👑 🥈 🥉) y que los
// móviles se vean entre sí y compitan.

import 'package:supabase_flutter/supabase_flutter.dart';

/// Puntos necesarios para clasificar al premio de la semana.
const int kPuntosPremioSemana = 80;

/// Podio de la semana: id del móvil → puesto (1, 2 o 3).
/// Solo cuentan móviles con puntos > 0. Mismo puntaje = mismo puesto.
Map<int, int> calcularPodioSemana(Iterable<Map<String, dynamic>> moviles) {
  final puntos = <int>{};
  for (final m in moviles) {
    if (m['eliminado'] == true) continue;
    final p = (m['puntos_semana'] as num?)?.toInt() ?? 0;
    if (p > 0) puntos.add(p);
  }
  final top = puntos.toList()..sort((a, b) => b.compareTo(a));
  final Map<int, int> res = {};
  for (final m in moviles) {
    if (m['eliminado'] == true) continue;
    final id = (m['id'] as num?)?.toInt();
    final p = (m['puntos_semana'] as num?)?.toInt() ?? 0;
    if (id == null || p <= 0) continue;
    final pos = top.indexOf(p) + 1;
    if (pos >= 1 && pos <= 3) res[id] = pos;
  }
  return res;
}

/// Emoji del RANGO (distinto a las medallas del podio para no confundir):
/// 🔰 NOVATO · ⚡ PRO · 💎 ÉLITE · 🦅 LEYENDA · 🎖️ MASTER
String emojiRango(String? rango) =>
    switch ((rango ?? '').toUpperCase().trim()) {
      'PRO' => '⚡',
      'ELITE' || 'ÉLITE' => '💎',
      'LEYENDA' => '🦅',
      'MASTER' => '🎖️',
      _ => '🔰',
    };

/// 👑 1° · 🥈 2° · 🥉 3° · '' resto
String emojiPodio(int? puesto) => switch (puesto) {
      1 => '👑',
      2 => '🥈',
      3 => '🥉',
      _ => '',
    };

/// Carga el podio desde el servidor (para pantallas que no tienen la lista
/// completa de móviles, p. ej. la fila del paradero en la app del móvil).
Future<Map<int, int>> cargarPodioSemana() async {
  try {
    final rows = await Supabase.instance.client
        .from('usuarios')
        .select('id, puntos_semana, eliminado')
        .eq('rol', 'movil')
        .eq('activo', true)
        .gt('puntos_semana', 0)
        .order('puntos_semana', ascending: false)
        .limit(30);
    return calcularPodioSemana(List<Map<String, dynamic>>.from(rows));
  } catch (_) {
    return {};
  }
}
