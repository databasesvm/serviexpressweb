import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RankingScreen extends StatefulWidget {
  const RankingScreen({super.key});

  @override
  State<RankingScreen> createState() => _RankingScreenState();
}

class _RankingScreenState extends State<RankingScreen> {
  List<Map<String, dynamic>> _ranking = [];
  bool _cargando = true;
  Map<int, int> _minutosHoyPorMovil = {}; // movil_id → minutos activos hoy

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
      for (final r in rows as List) {
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
          .select('id, nombre, usuario, rol, rango_movil, puntuacion, foto_perfil_url')
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
          double promedio = puntajes.isNotEmpty
              ? (puntajes.reduce((a, b) => a + b) / puntajes.length)
              : 0.0;

          String? rangoManual = u['rango_movil'];
          String rangoNombre;
          bool esManual = false;

          // MASTER: puntaje fijo 5.0, rango inmune a revocación automática
          final bool esMaster = rangoManual?.toUpperCase() == 'MASTER';

          // --- MOTOR DE REVOCACIÓN AUTOMÁTICA (no aplica a MASTER) ---
          bool perdioRango = false;
          if (!esMaster && rangoManual != null && rangoManual.isNotEmpty) {
            if (puntajes.isEmpty) {
              perdioRango = true; // Castigo por inactividad
            } else if (promedio < 4.0) {
              perdioRango = true; // Castigo por mal rendimiento
            }
          }

          if (perdioRango) {
            // Limpiamos el rango en la base de datos silenciosamente
            await Supabase.instance.client
                .from('usuarios')
                .update({'rango_movil': null})
                .eq('id', u['id']);
            rangoManual = null; // Lo anulamos localmente para forzar el cálculo
          }
          // ----------------------------------------

          if (esMaster) {
            rangoNombre = 'MASTER';
            promedio = 5.0; // Puntaje fijo para Masters
            esManual = true;
          } else if (rangoManual != null && rangoManual.isNotEmpty) {
            rangoNombre = rangoManual;
            esManual = true;
          } else {
            if (puntajes.isEmpty) {
              rangoNombre = 'NOVATO';
            } else if (promedio >= 4.8) {
              rangoNombre = 'LEYENDA';
            } else if (promedio >= 4.3) {
              rangoNombre = 'ÉLITE';
            } else if (promedio >= 3.8) {
              rangoNombre = 'PRO';
            } else {
              rangoNombre = 'NOVATO';
            }
          }

          String rangoIcono;
          if (rangoNombre == 'MASTER') {
            rangoIcono = '🏆';
          } else if (rangoNombre == 'LEYENDA') {
            rangoIcono = '👑';
          } else if (rangoNombre == 'ÉLITE') {
            rangoIcono = '⭐';
          } else if (rangoNombre == 'PRO') {
            rangoIcono = '⚡';
          } else {
            rangoIcono = '🔰';
          }

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
          });
        }
      }

      // Ordenar por número de MOVIL## ascendente
      listaTemporal.sort((a, b) {
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
        _cargando = false;
      });
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error al cargar ranking: $e')));
      setState(() => _cargando = false);
    }
  }

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
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: Colors.black))
          : Column(
              children: [
                Container(
                  width: double.infinity,
                  color: Colors.black87,
                  padding: const EdgeInsets.all(12),
                  child: const Text(
                    'CALIDAD OPERATIVA (ÚLTIMOS 7 DÍAS)',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xff3AF500),
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
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

                      return Card(
                        elevation: 2,
                        color: const Color(0xFF1A1A1A),
                        margin: const EdgeInsets.only(bottom: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: ListTile(
                          leading: () {
                            final fotoUrl = item['foto_perfil_url']?.toString();
                            final tieneFoto = fotoUrl != null && fotoUrl.isNotEmpty;
                            return CircleAvatar(
                              backgroundColor: rangoColor.withAlpha(30),
                              backgroundImage: tieneFoto ? NetworkImage(fotoUrl) : null,
                              onBackgroundImageError: tieneFoto ? (_, __) {} : null,
                              child: !tieneFoto
                                  ? Text(item['rango_icono'], style: const TextStyle(fontSize: 20))
                                  : null,
                            );
                          }(),
                          title: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  (item['usuario'] ?? item['nombre']).toString().toUpperCase(),
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
                                    item['rango_nombre'] as String,
                                    style: TextStyle(color: rangoColor, fontWeight: FontWeight.bold, fontSize: 12),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${item['viajes']} servicios esta semana',
                                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                                  ),
                                ],
                              ),
                              if (puntActual > 0)
                                Text(
                                  'Puntuación acumulada: ${puntActual.toStringAsFixed(2)}',
                                  style: const TextStyle(color: Colors.white30, fontSize: 10),
                                ),
                            ],
                          ),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              const Text('SEMANA', style: TextStyle(fontSize: 9, color: Colors.grey)),
                              Text(
                                puntSemanal > 0 ? puntSemanal.toStringAsFixed(1) : '—',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: puntSemanal >= 4.8
                                      ? Colors.green[400]
                                      : (puntSemanal > 0 && puntSemanal < 3.8
                                            ? Colors.red[400]
                                            : Colors.white54),
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
