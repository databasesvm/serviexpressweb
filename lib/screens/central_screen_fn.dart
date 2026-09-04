// ignore_for_file: use_build_context_synchronously
part of 'central_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Lógica FN para la central: canal Realtime de solicitudes desde sedes,
// diálogo de cotización, renegociación, toggle alta demanda.
// ─────────────────────────────────────────────────────────────────────────────

extension CentralScreenFn on _CentralScreenState {
  // ── Canal Realtime para servicios fn_origen='sede' ──────────────────────
  void _construirCanalFn() {
    _canalFn?.unsubscribe();
    _canalFn = Supabase.instance.client
        .channel('central_fn_sedes')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'servicios',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'fn_origen',
            value: 'sede',
          ),
          callback: (payload) {
            if (!mounted) return;
            final s = payload.newRecord;
            if (s.isEmpty) return;
            // Solo 'cotizacion' activa el sonido especial FN
            if (s['estado']?.toString() == 'cotizacion') {
              _sonidos.reproducir(Sonidos.fnCotizacion);
            }
          },
        )
        .subscribe();
  }

  // ── Diálogo cotización FN — llamado desde el monitor con servicio FN sede ──
  Future<void> _mostrarDialogoCotizacionFn(
      Map<String, dynamic> servicio) async {
    final int? serviceId = servicio['id'] is int
        ? servicio['id'] as int
        : int.tryParse(servicio['id']?.toString() ?? '');
    if (serviceId == null) return;

    // Datos de recogidas y destino
    final recogidas = servicio['recogidas'] is List
        ? (servicio['recogidas'] as List).cast<Map<String, dynamic>>()
        : <Map<String, dynamic>>[];
    final destino = servicio['destino']?.toString() ?? '—';
    final consec = servicio['fn_consecutivo']?.toString() ?? '#$serviceId';
    final observacion = servicio['observacion']?.toString() ?? '';
    final instrucciones =
        servicio['instrucciones_especiales']?.toString() ?? '';
    final facturaNum = servicio['fn_factura_numero']?.toString() ?? '';
    final facturaVal = (servicio['fn_factura_valor'] as num?)?.toInt();
    final pagarProducto = servicio['fn_pagar_producto'] == true;
    final altaDemanda = servicio['fn_alta_demanda'] == true;
    final recotizacion = (servicio['fn_recotizacion'] as int?) ?? 1;

    // Recargo pre-calculado por la sede (sedes extra + datáfono, sin precio destino)
    final recargoCalculado = (servicio['fn_recargo_calculado'] as num?)?.toInt();

    // Precio sugerido si viene de renegociación
    final precioSugerido = (servicio['fn_precio_sugerido_sede'] as num?)?.toInt();

    // Pre-poblar tarifa: renegociación > recargo calculado > vacío
    String tarifaInicial = servicio['tarifa']?.toString() ?? '';
    if (tarifaInicial.isEmpty && precioSugerido != null) {
      tarifaInicial = precioSugerido.toString();
    } else if (tarifaInicial.isEmpty && recargoCalculado != null && recargoCalculado > 0) {
      tarifaInicial = recargoCalculado.toString();
    }
    final tarifaCtrl = TextEditingController(text: tarifaInicial);

    bool guardarEnRed = false;
    String? movilPreselId;

    // Cargar móviles conectados para selector de pre-asignación
    List<Map<String, dynamic>> movilesConectados = [];
    try {
      final raw = await Supabase.instance.client
          .from('usuarios')
          .select('id, numero_movil, nombre')
          .eq('rol', 'movil')
          .eq('en_linea', true)
          .eq('activo', true)
          .neq('suspendido', true)
          .order('numero_movil');
      movilesConectados = List<Map<String, dynamic>>.from(raw as List);
    } catch (_) {}

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Row(
          children: [
            const Icon(Icons.local_pharmacy, color: Colors.indigo, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Cotización FN — $consec',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ),
            if (altaDemanda)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.orange[900],
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text('ALTA DEMANDA',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.bold)),
              ),
          ],
        ),
        content: SizedBox(
          width: 360,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Indicador de recotización
                if (recotizacion > 1)
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.deepPurple[900]!.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.deepPurple[400]!),
                    ),
                    child: Text(
                      '🔄 Recotización #$recotizacion${precioSugerido != null ? ' — la sede sugiere \$${_milesStr(precioSugerido)}' : ''}',
                      style: const TextStyle(
                          color: Colors.purple, fontSize: 12),
                    ),
                  ),

                // Recogidas
                ...recogidas.map((r) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          const Icon(Icons.local_pharmacy_outlined,
                              size: 13, color: Colors.indigo),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _labelSedeFn(r),
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                          if (r['cobertura'] == 'fuera' ||
                              r['cobertura'] == 'por_evaluar')
                            const Tooltip(
                              message: 'Fuera de cobertura',
                              child: Icon(Icons.warning_amber,
                                  size: 14, color: Colors.orange),
                            ),
                        ],
                      ),
                    )),

                const SizedBox(height: 6),

                // Destino
                Row(
                  children: [
                    const Icon(Icons.place_outlined, size: 14),
                    const SizedBox(width: 6),
                    Expanded(
                        child: Text(destino,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 13))),
                  ],
                ),

                // Observación
                if (observacion.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.amber[50],
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.amber[300]!),
                    ),
                    child: Text('📋 $observacion',
                        style: const TextStyle(fontSize: 12)),
                  ),
                ],

                // Instrucciones especiales
                if (instrucciones.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text('📝 $instrucciones',
                      style: const TextStyle(
                          fontSize: 12, color: Colors.black54)),
                ],

                // Datos de factura
                if (facturaNum.isNotEmpty || facturaVal != null || pagarProducto) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    children: [
                      if (facturaNum.isNotEmpty)
                        _chipFn('Fac. $facturaNum', Colors.blueGrey),
                      if (facturaVal != null)
                        _chipFn('\$${_milesStr(facturaVal)}', Colors.blueGrey),
                      if (pagarProducto)
                        _chipFn('PAGAR PRODUCTO', Colors.red[800]!),
                      if (servicio['metodo_pago'] == 'Datafono')
                        _chipFn('DATÁFONO', Colors.blue[800]!),
                    ],
                  ),
                ],

                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),

                // Recargo pre-calculado por la sede (sin precio destino)
                if (recargoCalculado != null && recargoCalculado > 0 &&
                    servicio['tarifa'] == null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: Colors.amber[50],
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.amber[400]!),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.calculate_outlined,
                            size: 15, color: Colors.orange),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'La sede ya calculó \$${_milesStr(recargoCalculado)} (sedes extra + datáfono). '
                            'Solo falta el precio al destino — el campo ya incluye este valor como punto de partida.',
                            style: const TextStyle(
                                fontSize: 11, color: Colors.orange),
                          ),
                        ),
                      ],
                    ),
                  ),

                // Campo tarifa
                TextField(
                  controller: tarifaCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Tarifa a cobrar (\$)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.attach_money),
                    isDense: true,
                  ),
                ),

                // Selector: pre-asignar móvil (opcional)
                if (movilesConectados.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Divider(height: 1),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: movilPreselId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: '🎯 Pre-asignar móvil (opcional)',
                      border: OutlineInputBorder(),
                      isDense: true,
                      helperText: 'Si la sede aprueba, va directo a este móvil',
                      helperStyle: TextStyle(fontSize: 10),
                    ),
                    items: [
                      const DropdownMenuItem<String>(
                        value: null,
                        child: Text('— Sin pre-asignación (cascada normal) —',
                            style: TextStyle(fontSize: 12, color: Colors.black54)),
                      ),
                      ...movilesConectados.map((m) {
                        final num = m['numero_movil']?.toString() ?? '?';
                        final nombre = m['nombre']?.toString() ?? '';
                        return DropdownMenuItem<String>(
                          value: m['id'].toString(),
                          child: Text('Móvil$num — $nombre',
                              style: const TextStyle(fontSize: 13)),
                        );
                      }),
                    ],
                    onChanged: (v) => setD(() => movilPreselId = v),
                  ),
                ],

                // Toggle: guardar en red de direcciones
                const SizedBox(height: 10),
                SwitchListTile(
                  value: guardarEnRed,
                  onChanged: (v) => setD(() => guardarEnRed = v),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    '💾 Guardar dirección en red de esta sede',
                    style: TextStyle(fontSize: 12),
                  ),
                  subtitle: const Text(
                    'La próxima vez la sede verá el precio sugerido automáticamente',
                    style: TextStyle(fontSize: 10, color: Colors.black54),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          // Rechazar
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _rechazarCotizacionFn(serviceId);
            },
            child: const Text('Rechazar', style: TextStyle(color: Colors.red)),
          ),
          // Enviar cotización
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1A237E),
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.send_rounded, size: 16),
            label: const Text('Cotizar'),
            onPressed: () async {
              final tarifa = int.tryParse(tarifaCtrl.text.trim());
              if (tarifa == null || tarifa <= 0) return;
              Navigator.pop(ctx);
              await _enviarCotizacionFn(serviceId, tarifa, movilPreselId: movilPreselId);

              // Guardar en red de direcciones si el toggle está activo
              if (guardarEnRed) {
                await _guardarEnRedFn(
                  sedeId: servicio['fn_sede_solicitante_id'],
                  destino: destino,
                  tarifa: tarifa,
                );
              }
            },
          ),
        ],
      )),
    );
    tarifaCtrl.dispose();
  }

  // ── Guardar dirección en fn_red_direcciones ──────────────────────────────
  Future<void> _guardarEnRedFn({
    required dynamic sedeId,
    required String destino,
    required int tarifa,
  }) async {
    if (sedeId == null || destino.isEmpty) return;
    final sid = sedeId is int ? sedeId : int.tryParse(sedeId.toString());
    if (sid == null) return;
    try {
      // Verificar si ya existe una entrada con ese destino para esa sede
      final existing = await Supabase.instance.client
          .from('fn_red_direcciones')
          .select('id')
          .eq('sede_id', sid)
          .ilike('direccion', destino.trim())
          .maybeSingle();

      if (existing != null) {
        // Actualizar precio si ya existe
        await Supabase.instance.client
            .from('fn_red_direcciones')
            .update({'precio': tarifa, 'activo': true})
            .eq('id', existing['id']);
      } else {
        // Crear nueva entrada usando el destino como nombre y dirección
        await Supabase.instance.client.from('fn_red_direcciones').insert({
          'sede_id': sid,
          'nombre': destino.trim().length > 30
              ? '${destino.trim().substring(0, 30)}…'
              : destino.trim(),
          'direccion': destino.trim().toUpperCase(),
          'precio': tarifa,
          'activo': true,
        });
      }
    } catch (e) {
      debugPrint('Error guardando en red FN: $e');
    }
  }

  // ── Enviar cotización a la sede ─────────────────────────────────────────
  Future<void> _enviarCotizacionFn(int serviceId, int tarifa,
      {String? movilPreselId}) async {
    try {
      await Supabase.instance.client.from('servicios').update({
        'estado': 'cotizada',
        'tarifa': tarifa,
        if (movilPreselId != null)
          'fn_movil_preseleccionado_id': int.tryParse(movilPreselId),
      }).eq('id', serviceId);

      // Notificar a la sede FN
      final servicio = await Supabase.instance.client
          .from('servicios')
          .select('fn_sede_solicitante_id, fn_consecutivo')
          .eq('id', serviceId)
          .maybeSingle();

      if (servicio != null) {
        final sedeId = servicio['fn_sede_solicitante_id']?.toString();
        final consec = servicio['fn_consecutivo']?.toString() ?? '#$serviceId';

        if (sedeId != null) {
          // Buscar usuario de la sede para enviar push personalizado
          final userSede = await Supabase.instance.client
              .from('usuarios')
              .select('id')
              .eq('fn_sede_id', int.tryParse(sedeId) ?? 0)
              .maybeSingle();

          if (userSede != null) {
            await MotorNotificaciones.dispararMisil(
              idDestino: userSede['id'].toString(),
              titulo: '✅ Cotización lista — $consec',
              mensaje: 'La central cotizó tu servicio en \$${_milesStr(tarifa)}',
              urgente: false,
              sonido: Sonidos.fnCotizacion,
              canalAndroidId: MotorNotificaciones.canalFnCotizacionId,
            );
          }
        }
      }
    } catch (e) {
      debugPrint('Error cotizando FN: $e');
    }
  }

  // ── Rechazar solicitud (vuelve a estado 'fn_rechazado') ─────────────────
  Future<void> _rechazarCotizacionFn(int serviceId) async {
    try {
      await Supabase.instance.client.from('servicios').update({
        'estado': 'fn_rechazado',
        'observacion': 'CENTRAL: Solicitud rechazada.',
      }).eq('id', serviceId);
    } catch (e) {
      debugPrint('Error rechazando FN: $e');
    }
  }



  // ── Helpers ─────────────────────────────────────────────────────────────
  String _labelSedeFn(Map<String, dynamic> r) {
    final tipo = r['tipo']?.toString() ?? '';
    final num = r['numero']?.toString() ?? '';
    final nombre = r['nombre']?.toString() ?? r['zona']?.toString() ?? '';
    return tipo == 'FN' && num.isNotEmpty ? 'FN$num — $nombre' : nombre;
  }

  String _milesStr(int v) {
    final s = v.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  Widget _chipFn(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Text(label,
            style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.bold)),
      );

}
