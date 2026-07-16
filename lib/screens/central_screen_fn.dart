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
    final tarifaCtrl = TextEditingController(
      text: servicio['tarifa']?.toString() ?? '',
    );
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

    // Precio sugerido si viene de renegociación
    final precioSugerido = (servicio['fn_precio_sugerido_sede'] as num?)?.toInt();
    if (precioSugerido != null && tarifaCtrl.text.isEmpty) {
      tarifaCtrl.text = precioSugerido.toString();
    }

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
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
              await _enviarCotizacionFn(serviceId, tarifa);
            },
          ),
        ],
      ),
    );
    tarifaCtrl.dispose();
  }

  // ── Enviar cotización a la sede ─────────────────────────────────────────
  Future<void> _enviarCotizacionFn(int serviceId, int tarifa) async {
    try {
      await Supabase.instance.client.from('servicios').update({
        'estado': 'cotizada',
        'tarifa': tarifa,
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
              urgente: true,
              sonido: Sonidos.fnCotizacion,
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

  // ── Toggle alta demanda FN desde panel de control ───────────────────────
  Future<void> _toggleAltaDemandaFn(bool valor) async {
    try {
      await Supabase.instance.client
          .from('config_sistema')
          .update({'alta_demanda_fn': valor}).eq('id', 1);
    } catch (e) {
      debugPrint('Error toggling alta_demanda_fn: $e');
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

  // ── Toggle alta demanda en el panel de control ──────────────────────────
  // Devuelve un widget listo para incrustar en _construirPanelControl()
  Widget _buildToggleAltaDemandaFn() {
    return FutureBuilder<bool>(
      future: _cargarAltaDemandaFn(),
      builder: (context, snap) {
        final activo = snap.data ?? false;
        return SwitchListTile(
          dense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
          title: const Text('⚠ Alta demanda FN',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          subtitle: const Text(
            'Avisa a todas las sedes de demora en el servicio',
            style: TextStyle(fontSize: 11),
          ),
          value: activo,
          onChanged: (v) => _toggleAltaDemandaFn(v),
          activeColor: Colors.orange[700],
        );
      },
    );
  }

  Future<bool> _cargarAltaDemandaFn() async {
    try {
      final row = await Supabase.instance.client
          .from('config_sistema')
          .select('alta_demanda_fn')
          .eq('id', 1)
          .maybeSingle();
      return row?['alta_demanda_fn'] == true;
    } catch (_) {
      return false;
    }
  }
}
