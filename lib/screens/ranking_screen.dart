import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/widgets_compartidos.dart';
import '../utils/competencia_semanal.dart';
import 'historico_premios_screen.dart';

class RankingScreen extends StatefulWidget {
  /// Si lo abre un móvil: para resaltar sus semanas en el histórico.
  final int? miMovilId;
  const RankingScreen({super.key, this.miMovilId});

  @override
  State<RankingScreen> createState() => _RankingScreenState();
}

class _RankingScreenState extends State<RankingScreen> {
  List<Map<String, dynamic>> _ranking = [];
  bool _cargando = true;
  Map<int, int> _minutosHoyPorMovil = {}; // movil_id → minutos activos hoy
  // id → posición de premio semanal (1=🏆, 2=🥈, 3=🥉) para móviles con ≥80 pts
  Map<int, int> _premiosSemana = {};
  // Podio de la semana (👑 🥈 🥉) por puntos, clasifiquen o no todavía
  Map<int, int> _podio = {};

  @override
  void initState() {
    super.initState();
    _calcularRankingSemanal();
    _cargarHorasHoy();
  }

  Future<void> _cargarHorasHoy() async {
    try {
      final hoy = DateTime.now();
      final fechaHoy =
          '${hoy.year}-${hoy.month.toString().padLeft(2, '0')}-${hoy.day.toString().padLeft(2, '0')}';
      final rows = await Supabase.instance.client
          .from('sesiones_movil')
          .select('movil_id, duracion_minutos')
          .eq('fecha', fechaHoy)
          .not('duracion_minutos', 'is', null);
      final Map<int, int> map = {};
      for (final r in rows) {
        final mid = r['movil_id'] as int?;
        if (mid == null) continue;
        map[mid] = (map[mid] ?? 0) + ((r['duracion_minutos'] as num?)?.toInt() ?? 0);
      }
      if (mounted) setState(() => _minutosHoyPorMovil = map);
    } catch (_) {}
  }

  String _fmtMinutos(int mins) {
    if (mins == 0) return '—';
    final h = mins ~/ 60;
    final m = mins % 60;
    return h > 0 ? '${h}h${m.toString().padLeft(2, '0')}m' : '${m}m';
  }

  Future<void> _calcularRankingSemanal() async {
    try {
      // Solo móviles activos — no necesitamos central, locales ni clientes
      final usuariosResp = await Supabase.instance.client
          .from('usuarios')
          .select('id, nombre, usuario, rol, rango_movil, puntuacion, foto_perfil_url, puntos_semana')
          .eq('activo', true)
          .eq('rol', 'movil');
      final List<dynamic> usuarios = usuariosResp;

      final haceUnaSemana = DateTime.now()
          .subtract(const Duration(days: 7))
          .toUtc()
          .toIso8601String();
      // Solo servicios con móvil asignado (movil_id != null)
      final serviciosResp = await Supabase.instance.client
          .from('servicios')
          .select('movil_id, estado, observacion')
          .gte('created_at', haceUnaSemana)
          .neq('estado', 'pendiente')
          .neq('estado', 'en_curso')
          .not('movil_id', 'is', null);

      final List<dynamic> servicios = serviciosResp;

      Map<int, List<double>> puntajesPorMovil = {};

      for (var servicio in servicios) {
        final int? movilId = servicio['movil_id'];
        if (movilId == null) continue;

        double puntos = 5.0;
        final estado = servicio['estado'];
        final obs = servicio['observacion'] ?? '';

        if (estado == 'finalizado') {
          if (obs.contains('PRÓRROGA')) {
            puntos = 3.5;
          } else {
            puntos = 5.0;
          }
        } else if (estado == 'finalizado_con_problema' ||
            estado == 'finalizado_por_demora' ||
            estado == 'cancelado' ||
            obs.contains('[MARCA DE FALLA]')) {
          puntos = 1.0;
        }

        puntajesPorMovil.putIfAbsent(movilId, () => []).add(puntos);
      }

      List<Map<String, dynamic>> listaTemporal = [];
      for (var u in usuarios) {
        final rol = u['rol'];

        if (rol == 'master' || rol == 'central') continue;

        if (rol == 'movil') {
          final puntajes = puntajesPorMovil[u['id']] ?? [];

          // Calificación y rango vienen del SERVIDOR (recalcular_puntuacion_movil):
          // +0,1 por servicio finalizado (tope 5,0). Rango automático:
          // NOVATO <3,8 · PRO ≥3,8 · ÉLITE ≥4,3. LEYENDA (≥4,8) solo con
          // autorización de la central; MASTER solo manual.
          final String rangoBD =
              (u['rango_movil']?.toString() ?? '').toUpperCase().trim();
          final bool esMaster = rangoBD == 'MASTER';
          final double promedio = esMaster
              ? 5.0
              : ((u['puntuacion'] as num?)?.toDouble() ?? 0.0);
          // Distintivo azul: rangos que da la central (LEYENDA / MASTER)
          final bool esManual = esMaster || rangoBD == 'LEYENDA';
          final String rangoNombre = switch (rangoBD) {
            'MASTER' => 'MASTER',
            'LEYENDA' => 'LEYENDA',
            'ELITE' || 'ÉLITE' => 'ÉLITE',
            'PRO' => 'PRO',
            _ => 'NOVATO',
          };

          // Emoji del rango (👑 🥈 🥉 quedan solo para el podio de puntos)
          final String rangoIcono = emojiRango(rangoNombre);

          listaTemporal.add({
            'id': u['id'],
            'nombre': u['nombre'],
            'usuario': u['usuario'], // MOVIL## para mostrar en ranking
            'foto_perfil_url': u['foto_perfil_url'],
            'rango_nombre': rangoNombre,
            'rango_icono': rangoIcono,
            'promedio': promedio,
            'puntuacion_actual': esMaster ? 5.0 : (u['puntuacion'] as num?)?.toDouble() ?? 0.0,
            'viajes': puntajes.length,
            'tiene_manual': esManual,
            'puntos_semana': (u['puntos_semana'] as int?) ?? 0,
          });
        }
      }

      // Calcular premios semanales: top 3 con ≥80 puntos, ordenados desc
      final elegibles = listaTemporal
          .where((m) => (m['puntos_semana'] as int) >= 80)
          .toList()
        ..sort((a, b) =>
            (b['puntos_semana'] as int).compareTo(a['puntos_semana'] as int));
      final Map<int, int> premios = {};
      for (int i = 0; i < elegibles.length && i < 3; i++) {
        premios[elegibles[i]['id'] as int] = i + 1;
      }

      // Ordenar por PUNTOS DE LA SEMANA (el que más lleva arriba);
      // empate → número de MOVIL## ascendente
      listaTemporal.sort((a, b) {
        final pts = (b['puntos_semana'] as int).compareTo(a['puntos_semana'] as int);
        if (pts != 0) return pts;
        final numA = int.tryParse(
                (a['usuario'] ?? '').toString().replaceAll(RegExp(r'[^0-9]'), '')) ??
            9999;
        final numB = int.tryParse(
                (b['usuario'] ?? '').toString().replaceAll(RegExp(r'[^0-9]'), '')) ??
            9999;
        return numA.compareTo(numB);
      });

      setState(() {
        _ranking = listaTemporal;
        _premiosSemana = premios;
        _podio = calcularPodioSemana(listaTemporal);
        _cargando = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error al cargar ranking: $e')));
      }
      setState(() => _cargando = false);
    }
  }

  // (ver _ChipPremio al final del archivo)
  Color _colorRango(String rango) {
    switch (rango) {
      case 'LEYENDA': return const Color(0xFFFF9800);
      case 'MASTER':  return const Color(0xFFE040FB);
      case 'ÉLITE':
      case 'ELITE':   return const Color(0xFF2196F3);
      case 'PRO':     return const Color(0xFF4CAF50);
      default:        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        title: const Text(
          'Rendimiento Semanal',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          // Histórico de las semanas y sus premios
          TextButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    HistoricoPremiosScreen(miMovilId: widget.miMovilId),
              ),
            ),
            icon: const Text('🏆', style: TextStyle(fontSize: 16)),
            label: const Text('Histórico',
                style: TextStyle(
                    color: Color(0xFFFFD54F), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: Colors.black))
          : Column(
              children: [
                // Cabecera de la competencia semanal
                Container(
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF3A2A00), Color(0xFF111111)],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                  child: Column(children: [
                    const Text(
                      '🏆 PREMIO DE LA SEMANA',
                      style: TextStyle(
                        color: Color(0xFFFFD54F),
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Llega a $kPuntosPremioSemana pts y queda entre los 3 que más hagan',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 6,
                      runSpacing: 4,
                      children: const [
                        _ChipPremio('🥇 1°', 'No paga semana', Color(0xFFFFD54F)),
                        _ChipPremio('🥈 2°', '75% desc.', Color(0xFFE0E0E0)),
                        _ChipPremio('🥉 3°', '50% desc.', Color(0xFFFFAB40)),
                      ],
                    ),
                  ]),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _ranking.length,
                    itemBuilder: (context, index) {
                      final item = _ranking[index];
                      final bool esManual = item['tiene_manual'];

                      final double puntActual = item['puntuacion_actual'] as double;
                      final double puntSemanal = item['promedio'] as double;
                      final Color rangoColor = _colorRango(item['rango_nombre'] as String);

                      // ── Competencia semanal ──────────────────────────────
                      final int pts = item['puntos_semana'] as int? ?? 0;
                      final int? puesto = _podio[item['id'] as int?];
                      final String medalla = emojiPodio(puesto);
                      final bool clasificado = pts >= kPuntosPremioSemana;
                      final int ptsLider = _ranking.isNotEmpty
                          ? (_ranking.first['puntos_semana'] as int? ?? 0)
                          : 0;
                      // Empate en el podio: otro móvil con los mismos puntos
                      final bool empatado = puesto != null && pts > 0 &&
                          _ranking.where((r) => (r['puntos_semana'] as int? ?? 0) == pts).length > 1;
                      final Color colorPodio = puesto == 1
                          ? const Color(0xFFFFD54F)
                          : puesto == 2
                              ? const Color(0xFFE0E0E0)
                              : puesto == 3
                                  ? const Color(0xFFFFAB40)
                                  : Colors.transparent;

                      return Card(
                        elevation: puesto != null ? 6 : 2,
                        color: puesto == 1
                            ? const Color(0xFF2E2300)
                            : const Color(0xFF1A1A1A),
                        margin: const EdgeInsets.only(bottom: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: puesto != null
                              ? BorderSide(color: colorPodio, width: puesto == 1 ? 2 : 1.2)
                              : BorderSide.none,
                        ),
                        child: ListTile(
                          leading: () {
                            final fotoUrl = item['foto_perfil_url']?.toString();
                            final tieneFoto = fotoUrl != null && fotoUrl.isNotEmpty;
                            final avatar = CircleAvatar(
                              backgroundColor: rangoColor.withAlpha(30),
                              backgroundImage: tieneFoto ? NetworkImage(fotoUrl) : null,
                              onBackgroundImageError: tieneFoto ? (_, __) {} : null,
                              child: !tieneFoto
                                  ? Text(item['rango_icono'], style: const TextStyle(fontSize: 20))
                                  : null,
                            );
                            // Puesto en la tabla (#1, #2…) y medalla encima
                            return SizedBox(
                              width: 48,
                              height: 48,
                              child: Stack(clipBehavior: Clip.none, children: [
                                Positioned(left: 4, top: 4, child: avatar),
                                if (medalla.isNotEmpty)
                                  Positioned(
                                    right: -4,
                                    top: -6,
                                    child: Text(medalla, style: TextStyle(fontSize: puesto == 1 ? 22 : 18)),
                                  )
                                else
                                  Positioned(
                                    left: 0,
                                    top: 0,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: Colors.black,
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: Colors.white24),
                                      ),
                                      child: Text('#${index + 1}',
                                          style: const TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.bold)),
                                    ),
                                  ),
                              ]),
                            );
                          }(),
                          title: Row(
                            children: [
                              if (medalla.isNotEmpty) ...[
                                Text(medalla, style: const TextStyle(fontSize: 14)),
                                const SizedBox(width: 4),
                              ],
                              Flexible(
                                child: Text(
                                  movilLabel(item).toUpperCase(),
                                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (esManual) ...[
                                const SizedBox(width: 6),
                                const Icon(Icons.verified, size: 14, color: Colors.blue),
                              ],
                            ],
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 8, height: 8,
                                    decoration: BoxDecoration(color: rangoColor, shape: BoxShape.circle),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${item['rango_icono']} ${item['rango_nombre']}',
                                    style: TextStyle(color: rangoColor, fontWeight: FontWeight.bold, fontSize: 12),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${item['viajes']} servicios esta semana',
                                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                                  ),
                                ],
                              ),
                              if (!esManual && puntActual < 5.0)
                                Text(
                                  // Cada servicio limpio vale +0,02 (servidor)
                                  puntActual < 3.8
                                      ? 'Faltan ${(((3.8 - puntActual) * 100).round() / 2).ceil()} servicios para PRO'
                                      : puntActual < 4.3
                                          ? 'Faltan ${(((4.3 - puntActual) * 100).round() / 2).ceil()} servicios para ÉLITE'
                                          : puntActual < 4.8
                                              ? 'Faltan ${(((4.8 - puntActual) * 100).round() / 2).ceil()} servicios para LEYENDA'
                                              : 'Puede ser LEYENDA (la central lo autoriza)',
                                  style: const TextStyle(color: Colors.white30, fontSize: 10),
                                ),
                              // ── Avance al premio de la semana ──────────────
                              const SizedBox(height: 5),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: (pts / kPuntosPremioSemana).clamp(0.0, 1.0),
                                  minHeight: 6,
                                  backgroundColor: Colors.white10,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    clasificado
                                        ? Colors.greenAccent
                                        : (puesto != null ? colorPodio : Colors.orangeAccent),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                clasificado
                                    ? '✅ Clasificado al premio'
                                        '${puesto != null && puesto > 1 && ptsLider > pts ? ' · a ${ptsLider - pts} pts del 🥇' : ''}'
                                    : pts == 0
                                        ? 'Sin puntos esta semana'
                                        : 'Faltan ${kPuntosPremioSemana - pts} pts para clasificar'
                                            '${puesto != 1 && ptsLider > pts ? ' · a ${ptsLider - pts} del 🥇' : ''}',
                                style: TextStyle(
                                  color: clasificado ? Colors.greenAccent : Colors.white54,
                                  fontSize: 10,
                                  fontWeight: clasificado ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                              if (empatado)
                                const Padding(
                                  padding: EdgeInsets.only(top: 2),
                                  child: Text(
                                    '⚖️ Empate — si sigue así, decide la Central. ¡Suma un servicio más!',
                                    style: TextStyle(
                                        color: Color(0xFFFFD54F),
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold),
                                  ),
                                ),
                            ],
                          ),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              // PUNTOS DE LA SEMANA — lo más visible de la fila
                              Text(
                                '$pts',
                                style: TextStyle(
                                  fontSize: puesto == 1 ? 26 : 22,
                                  fontWeight: FontWeight.w900,
                                  color: puesto != null
                                      ? colorPodio
                                      : (clasificado ? Colors.greenAccent : Colors.white),
                                  height: 1.0,
                                ),
                              ),
                              Text(
                                _premiosSemana.containsKey(item['id'] as int?)
                                    ? 'PTS · PREMIO'
                                    : 'PTS SEMANA',
                                style: TextStyle(
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold,
                                  color: _premiosSemana.containsKey(item['id'] as int?)
                                      ? Colors.greenAccent
                                      : Colors.white38,
                                ),
                              ),
                              const SizedBox(height: 3),
                              // Calificación (secundaria)
                              Text(
                                '★ ${puntSemanal.toStringAsFixed(2)}',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: puntSemanal >= 4.8 ? Colors.green[400] : rangoColor,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.access_time, size: 10, color: Colors.white30),
                                  const SizedBox(width: 2),
                                  Text(
                                    _fmtMinutos(_minutosHoyPorMovil[item['id'] as int? ?? -1] ?? 0),
                                    style: const TextStyle(fontSize: 10, color: Colors.white38),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}

/// Chip del premio en la cabecera: "👑 1° · No paga semana".
class _ChipPremio extends StatelessWidget {
  final String puesto;
  final String premio;
  final Color color;
  const _ChipPremio(this.puesto, this.premio, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withAlpha(150)),
      ),
      child: Text(
        '$puesto · $premio',
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }
}
