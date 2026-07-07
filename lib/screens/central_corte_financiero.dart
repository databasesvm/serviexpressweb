part of 'central_screen.dart';
// // Corte financiero de local

class _CorteFinancieroDialog extends StatefulWidget {
  const _CorteFinancieroDialog();
  @override
  State<_CorteFinancieroDialog> createState() => _CorteFinancieroDialogState();
}

class _CorteFinancieroDialogState extends State<_CorteFinancieroDialog> {
  late DateTime _fechaInicio;
  late DateTime _fechaFin;
  @override
  void initState() {
    super.initState();
    final ahora = DateTime.now();
    _fechaInicio = DateTime(ahora.year, ahora.month, ahora.day);
    _fechaFin = DateTime(ahora.year, ahora.month, ahora.day, 23, 59, 59);
  }

  String _formatearFecha(DateTime fecha) {
    return "${fecha.day.toString().padLeft(2, '0')}/${fecha.month.toString().padLeft(2, '0')}/${fecha.year}";
  }

  Future<void> _seleccionarRango() async {
    final DateTimeRange? rango = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _fechaInicio, end: _fechaFin),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Colors.black,
              onPrimary: Color(0xff3AF500),
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );
    if (rango != null) {
      setState(() {
        _fechaInicio = rango.start;
        _fechaFin = DateTime(
          rango.end.year,
          rango.end.month,
          rango.end.day,
          23,
          59,
          59,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      backgroundColor: Colors.white,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.analytics, color: Colors.blue),
              SizedBox(width: 8),
              Text(
                'AUDITORÍA FINANCIERA',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ],
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: _seleccionarRango,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.black26),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.date_range, size: 16, color: Colors.black87),
                  const SizedBox(width: 8),
                  Text(
                    '${_formatearFecha(_fechaInicio)}  ➔  ${_formatearFecha(_fechaFin)}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.edit, size: 14, color: Colors.blue),
                ],
              ),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: FutureBuilder(
          future: Future.wait([
            Supabase.instance.client
                .from('usuarios')
                .select('id, nombre')
                .eq('rol', 'movil'),
            Supabase.instance.client
                .from('servicios')
                .select('movil_id, tarifa')
                .eq('estado', 'finalizado')
                .gte('created_at', _fechaInicio.toUtc().toIso8601String())
                .lte('created_at', _fechaFin.toUtc().toIso8601String()),
          ]),
          builder: (context, AsyncSnapshot<List<dynamic>> snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting)
              return const Center(
                child: CircularProgressIndicator(color: Colors.black),
              );
            if (snapshot.hasError)
              return Center(child: Text('Error: ${snapshot.error}'));
            final moviles = snapshot.data![0] as List<dynamic>;
            final serviciosFiltrados = snapshot.data![1] as List<dynamic>;
            List<Map<String, dynamic>> estadisticas = [];
            double totalFlota = 0;
            for (var movil in moviles) {
              final susServicios = serviciosFiltrados
                  .where((s) => s['movil_id'] == movil['id'])
                  .toList();
              if (susServicios.isEmpty) continue;
              final int cantidad = susServicios.length;
              final double producido = susServicios.fold(
                0.0,
                (sum, item) => sum + ((item['tarifa'] ?? 0) as num).toDouble(),
              );
              totalFlota += producido;
              estadisticas.add({
                'nombre': movil['nombre'],
                'cantidad': cantidad,
                'producido': producido,
              });
            }
            estadisticas.sort(
              (a, b) => b['producido'].compareTo(a['producido']),
            );
            if (estadisticas.isEmpty)
              return const Center(
                child: Text(
                  'No hay producción registrada en este rango.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.black54,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              );
            return Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green[400]!),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'TOTAL GENERADO:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                      Text(
                        '\$$totalFlota',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: Colors.black,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView.builder(
                    itemCount: estadisticas.length,
                    itemBuilder: (ctx, i) {
                      final est = estadisticas[i];
                      return Card(
                        elevation: 0,
                        color: Colors.grey[100],
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: const BorderSide(color: Colors.black12),
                        ),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.black,
                            child: Text(
                              '${i + 1}',
                              style: const TextStyle(
                                color: Color(0xff3AF500),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          title: Text(
                            est['nombre'],
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            '${est['cantidad']} servicios completados',
                          ),
                          trailing: Text(
                            '\$${est['producido']}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: Colors.green[700],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('CERRAR'),
        ),
      ],
    );
  }
}

// ============================================================
// PANEL LOCALES PENDIENTES — aprobación por Central
// ============================================================
