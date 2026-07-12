// lib/screens/reporte_financiero_screen.dart
//
// CAMBIOS VS VERSIÓN ANTERIOR
// ============================
// [FIX #3 - DATO ERRÓNEO] La producción ahora se agrupa por `movil_id` (ID del
//   conductor), no por `creador` (nombre del cliente que pidió el servicio).
//   Antes: el reporte mostraba "JUAN PÉREZ → $15.000" (cliente, no conductor).
//   Ahora: muestra "PEDRO GÓMEZ → $85.000" (conductor real que generó la plata).
//
// [MEJORA DE RENDIMIENTO] El filtro de fechas ahora es SERVER-SIDE.
//   Antes: Supabase enviaba TODOS los servicios finalizados y Flutter filtraba
//   en el dispositivo (podían ser miles de registros).
//   Ahora: la query solo trae los registros del período seleccionado.
//
// [REFACTOR] Reemplaza StreamBuilder por FutureBuilder.
//   Un reporte financiero no necesita WebSocket abierto 24/7.
//   Se refresca manualmente o al cambiar el rango de fechas.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ReporteFinancieroScreen extends StatefulWidget {
  const ReporteFinancieroScreen({super.key});

  @override
  State<ReporteFinancieroScreen> createState() =>
      _ReporteFinancieroScreenState();
}

class _ReporteFinancieroScreenState extends State<ReporteFinancieroScreen> {
  DateTime _fechaInicio = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    DateTime.now().day,
    0, 0, 0,
  );
  DateTime _fechaFin = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    DateTime.now().day,
    23, 59, 59,
  );

  // El Future se reconstruye cada vez que cambia el rango o se refresca
  late Future<Map<String, dynamic>> _futureReporte;

  @override
  void initState() {
    super.initState();
    _futureReporte = _cargarDatosReporte();
  }

  // =========================================================================
  // NÚCLEO: Carga con filtro en servidor + join a nombres de conductores
  // =========================================================================
  Future<Map<String, dynamic>> _cargarDatosReporte() async {
    // 1. Solo traemos lo del período — filtro SERVER-SIDE
    final servicios = await Supabase.instance.client
        .from('servicios')
        .select('movil_id, tarifa')
        .eq('estado', 'finalizado')
        .gte('created_at', _fechaInicio.toUtc().toIso8601String())
        .lte('created_at', _fechaFin.toUtc().toIso8601String());

    // 2. Extraemos los IDs únicos de conductores que trabajaron
    final Set<int> movilIds = servicios
        .where((s) => s['movil_id'] != null)
        .map<int>((s) => s['movil_id'] as int)
        .toSet();

    // 3. Una sola query para traer todos los nombres necesarios
    Map<int, String> nombresPorId = {};
    if (movilIds.isNotEmpty) {
      final conductores = await Supabase.instance.client
          .from('usuarios')
          .select('id, nombre')
          .inFilter('id', movilIds.toList());
      for (var c in conductores) {
        nombresPorId[c['id'] as int] = c['nombre'] as String;
      }
    }

    // 4. Agrupamos producción por conductor (no por cliente)
    double totalBruto = 0;
    Map<String, double> produccionPorMovil = {};

    for (var servicio in servicios) {
      final double tarifa = (servicio['tarifa'] ?? 0).toDouble();
      totalBruto += tarifa;

      final int? movilId = servicio['movil_id'];
      final String nombre = movilId != null
          ? (nombresPorId[movilId] ?? 'Móvil #$movilId')
          : 'Sin Asignar';

      produccionPorMovil[nombre] =
          (produccionPorMovil[nombre] ?? 0) + tarifa;
    }

    // 5. Ordenamos de mayor a menor producción
    final ordenados = Map.fromEntries(
      produccionPorMovil.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value)),
    );

    return {
      'totalBruto': totalBruto,
      'produccion': ordenados,
      'totalServicios': servicios.length,
    };
  }

  Future<void> _seleccionarRangoFechas() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2025),
      lastDate: DateTime.now().add(const Duration(days: 30)),
      initialDateRange: DateTimeRange(start: _fechaInicio, end: _fechaFin),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xff3AF500),
              onPrimary: Colors.black,
              surface: Colors.black,
              onSurface: Colors.white,
            ),
            dialogBackgroundColor: Colors.grey[900],
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _fechaInicio = DateTime(
          picked.start.year, picked.start.month, picked.start.day,
          0, 0, 0,
        );
        _fechaFin = DateTime(
          picked.end.year, picked.end.month, picked.end.day,
          23, 59, 59,
        );
        // Recargamos el reporte con el nuevo rango
        _futureReporte = _cargarDatosReporte();
      });
    }
  }

  void _refrescarReporte() {
    setState(() => _futureReporte = _cargarDatosReporte());
  }

  String _formatearFecha(DateTime fecha) =>
      '${fecha.day}/${fecha.month}/${fecha.year}';

  // =========================================================================
  // UI
  // =========================================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        title: Text(
          'CORTE OPERATIVO',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        backgroundColor: Colors.black,
        iconTheme: IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white70),
            tooltip: 'Actualizar',
            onPressed: _refrescarReporte,
          ),
          IconButton(
            icon: const Icon(Icons.calendar_month, color: Color(0xff3AF500)),
            tooltip: 'Cambiar período',
            onPressed: _seleccionarRangoFechas,
          ),
        ],
      ),
      body: Column(
        children: [
          // INDICADOR DEL RANGO
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
            color: Colors.black87,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Filtrando período:',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
                Text(
                  '${_formatearFecha(_fechaInicio)} al ${_formatearFecha(_fechaFin)}',
                  style: const TextStyle(
                    color: Color(0xff3AF500),
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),

          // REPORTE
          Expanded(
            child: FutureBuilder<Map<String, dynamic>>(
              future: _futureReporte,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: Colors.black),
                  );
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline,
                              color: Colors.red, size: 40),
                          const SizedBox(height: 12),
                          Text(
                            'Error al cargar: ${snapshot.error}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.red),
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.black),
                            onPressed: _refrescarReporte,
                            icon: const Icon(Icons.refresh,
                                color: Color(0xff3AF500)),
                            label: const Text('REINTENTAR',
                                style: TextStyle(color: Color(0xff3AF500))),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                final data = snapshot.data!;
                final double totalBruto = data['totalBruto'] as double;
                final int totalServicios = data['totalServicios'] as int;
                final Map<String, double> produccion =
                    data['produccion'] as Map<String, double>;

                if (totalServicios == 0) {
                  return const Center(
                    child: Text(
                      'No hay servicios finalizados en este período.',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.white54,
                      ),
                    ),
                  );
                }

                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _tarjetaEstadistica(
                      'FACTURACIÓN BRUTA EN EL RANGO',
                      '\$${totalBruto.toStringAsFixed(0)}',
                      Colors.black,
                      subtitulo: '$totalServicios servicios finalizados',
                    ),
                    _tarjetaEstadistica(
                      'COMISIÓN NETA SERVIEXPRESS (20%)',
                      '\$${(totalBruto * 0.2).toStringAsFixed(0)}',
                      const Color(0xff3AF500),
                    ),

                    const SizedBox(height: 20),
                    const Text(
                      'RENDIMIENTO DESGLOSADO POR CONDUCTOR',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.white54,
                        fontSize: 12,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 8),

                    if (produccion.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Center(
                          child: Text(
                            'Ningún conductor registra producción en estas fechas.',
                            style: TextStyle(
                              color: Colors.black54,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      )
                    else
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: const [
                            BoxShadow(color: Colors.black12, blurRadius: 4),
                          ],
                        ),
                        child: Column(
                          children: produccion.entries.map((entry) {
                            // Porcentaje del total para la barra de progreso
                            final double porcentaje = totalBruto > 0
                                ? entry.value / totalBruto
                                : 0;

                            return Column(
                              children: [
                                ListTile(
                                  leading: const CircleAvatar(
                                    backgroundColor: Colors.black,
                                    child: Icon(
                                      Icons.motorcycle,
                                      color: Color(0xff3AF500),
                                      size: 18,
                                    ),
                                  ),
                                  title: Text(
                                    entry.key.toUpperCase(),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                  subtitle: Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: LinearProgressIndicator(
                                      value: porcentaje,
                                      backgroundColor: const Color(0xFF0D0D0D),
                                      color: const Color(0xff3AF500),
                                      borderRadius: BorderRadius.circular(4),
                                      minHeight: 5,
                                    ),
                                  ),
                                  trailing: Text(
                                    '\$${entry.value.toStringAsFixed(0)}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black87,
                                      fontSize: 15,
                                    ),
                                  ),
                                  isThreeLine: true,
                                ),
                                const Divider(
                                    height: 1, indent: 16, endIndent: 16),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                    const SizedBox(height: 24),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _tarjetaEstadistica(
    String titulo,
    String valor,
    Color color, {
    String? subtitulo,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            titulo,
            style: TextStyle(
              color: color == Colors.black ? Colors.white70 : Colors.black87,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            valor,
            style: TextStyle(
              color: color == Colors.black ? Colors.white : Colors.black,
              fontSize: 26,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (subtitulo != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitulo,
              style: TextStyle(
                color:
                    color == Colors.black ? Colors.white54 : Colors.black54,
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
