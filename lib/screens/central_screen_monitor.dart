// ignore_for_file: use_build_context_synchronously
part of 'central_screen.dart';

extension CentralScreenMonitor on _CentralScreenState {

  Future<void> _abrirMenuGestion(BuildContext context, Map<String, dynamic> servicio) async {
    final String estado = servicio['estado'];
    final int id = servicio['id'];

    final double tarifaActual = (servicio['tarifa'] is num)
        ? (servicio['tarifa'] as num).toDouble()
        : 0.0;
    final String textoInicial = (tarifaActual == 0.0)
        ? ''
        : _formatearMonedaCentral(tarifaActual);
    final tarifaController = TextEditingController(text: textoInicial);

    // Desglose capturado por CampoTarifaInteligente en esta cotización.
    Map<String, dynamic>? detalleCotizacion;

    final bool esVip = servicio['es_vip'] == true;

    if (estado == 'cotizacion') {
      // FAST-PATH: si el motor tiene alta confianza, ofrecemos resolución en 1 tap.
      // Si el usuario elige "Revisar manualmente" (null), caemos al diálogo completo.
      // Si la llamada falla o confianza != 'alta', también caemos al diálogo completo.
      final bool resueltoPorMotor = await _fastPathCotizacion(context, servicio, esVip);
      if (resueltoPorMotor) return;

      if (!mounted) return;
      showDialog(
        context: context, // ignore: use_build_context_synchronously
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          title: esVip
              ? ShaderMask(
                  shaderCallback: (bounds) => const LinearGradient(
                    colors: [
                      Color(0xFFB8860B),
                      Color(0xFFFFD700),
                      Color(0xFFFFF0A0),
                      Color(0xFFFFD700),
                      Color(0xFFB8860B),
                    ],
                    stops: [0.0, 0.25, 0.5, 0.75, 1.0],
                  ).createShader(bounds),
                  child: Text(
                    '👑 COTIZACIÓN VIP #$id',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                )
              : Text(
                  'RESOLVER COTIZACIÓN #$id',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.orange,
                  ),
                ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '🏢 Origen: ${servicio['creador'].toString().toUpperCase()}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Text('🏁 Va para: ${servicio['destino']}'),
              const SizedBox(height: 16),
              // Motor de tarifas: sugiere precio basado en historial
              // usando el origen/destino de la cotización
              CampoTarifaInteligente(
                origenController: TextEditingController(
                  text: servicio['creador']?.toString() ?? '',
                ),
                destinoController: TextEditingController(
                  text: servicio['destino']?.toString() ?? '',
                ),
                tarifaController: tarifaController,
                destinoLat: (servicio['destino_lat'] as num?)?.toDouble(),
                destinoLng: (servicio['destino_lng'] as num?)?.toDouble(),
                tipoServicio: servicio['tipo_servicio']?.toString(),
                onDetalleChanged: (d) => detalleCotizacion = d,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CERRAR'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.black),
              onPressed: () async {
                // --- INYECCIÓN DE LIMPIEZA TÁCTICA ---
                String tarifaLimpia = tarifaController.text
                    .replaceAll('\$', '')
                    .replaceAll('.', '')
                    .replaceAll(',', '')
                    .trim();
                double precioAsignado = double.tryParse(tarifaLimpia) ?? 0.0;

                if (precioAsignado <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Ingresa un precio para enviar la cotización.',
                      ),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                if (precioAsignado > 0) {
                  // Si es VIP se suman $3.000 automáticamente
                  final double tarifaFinal = esVip ? precioAsignado + 3000 : precioAsignado;
                  await Supabase.instance.client
                      .from('servicios')
                      .update({
                        'tarifa': tarifaFinal,
                        'tarifa_detalle': detalleCotizacion != null
                            ? {...detalleCotizacion!, 'total': tarifaFinal}
                            : {'total': tarifaFinal, 'fuente': 'central_cotizacion'},
                        'estado': 'cotizada',
                      })
                      .eq('id', id);
                  if (context.mounted) Navigator.pop(context);
                }
              },
              child: const Text(
                'ENVIAR PRECIO',
                style: TextStyle(
                  color: Color(0xff3AF500),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      );
      return;
    }

    if (estado == 'cotizada') {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          title: Text(
            'COTIZACIÓN ENVIADA #$id',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.blue,
            ),
          ),
          content: Text(
            'Ya enviaste una tarifa de ${fmtPeso(servicio['tarifa'])}. Esperando respuesta del cliente o local.',
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await Supabase.instance.client
                    .from('servicios')
                    .update({
                      'estado': 'cancelado',
                      'observacion':
                          'Central canceló la cotización por falta de respuesta.',
                    })
                    .eq('id', id);
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text(
                'CANCELAR COTIZACIÓN',
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.black),
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'ESPERAR',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'CONTROL DE ORDEN #$id',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        content: SingleChildScrollView(
          child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── FICHA COMPLETA DEL SERVICIO ──────────────────────────
            Container(
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(4)),
                      child: Text((servicio['tipo_servicio'] ?? 'domicilio').toString().toUpperCase(),
                          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(color: Colors.blueGrey[700], borderRadius: BorderRadius.circular(4)),
                      child: Text(estado.toUpperCase().replaceAll('_', ' '),
                          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                    if (servicio['es_vip'] == true) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(color: Colors.amber[700], borderRadius: BorderRadius.circular(4)),
                        child: const Text('👑 VIP', style: TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ]),
                  const SizedBox(height: 8),
                  Text('📍 Origen: ${servicio['origen']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  Text('🏁 Destino: ${servicio['destino']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  if (servicio['created_at'] != null) ...[
                    const SizedBox(height: 4),
                    Text('🕐 Creado: ${() {
                        try {
                          final dt = DateTime.parse(servicio['created_at'].toString()).toLocal();
                          return '\${dt.day.toString().padLeft(2,'0')}/\${dt.month.toString().padLeft(2,'0')} \${dt.hour.toString().padLeft(2,'0')}:\${dt.minute.toString().padLeft(2,'0')}';
                        } catch (_) { return servicio['created_at'].toString(); }
                      }()}',
                      style: const TextStyle(fontSize: 12, color: Colors.black54)),
                  ],
                  const SizedBox(height: 4),
                  Text('💵 Tarifa: \${tarifaActual == 0.0 ? "Sin fijar" : _formatearMonedaCentral(tarifaActual)}',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold,
                        color: tarifaActual == 0.0 ? Colors.orange[800] : Colors.green[800])),
                  if (servicio['telefono_receptor'] != null) ...[
                    const SizedBox(height: 4),
                    Text('📞 Tel. Receptor: \${servicio['telefono_receptor']}',
                        style: const TextStyle(fontSize: 12, color: Colors.blue, fontWeight: FontWeight.bold)),
                  ],
                  if (servicio['numero_local'] != null || servicio['numero_cliente'] != null) ...[
                    const SizedBox(height: 4),
                    Row(children: [
                      if (servicio['numero_local'] != null)
                        Text('🏪 Local #\${servicio['numero_local']}  ', style: const TextStyle(fontSize: 12)),
                      if (servicio['numero_cliente'] != null)
                        Text('👤 Cliente #\${servicio['numero_cliente']}', style: const TextStyle(fontSize: 12)),
                    ]),
                  ],
                  if (servicio['instrucciones_especiales'] != null &&
                      servicio['instrucciones_especiales'].toString().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(color: Colors.amber[50], borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.amber[300]!)),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('📝 ', style: TextStyle(fontSize: 12)),
                        Expanded(child: Text(servicio['instrucciones_especiales'].toString(),
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500))),
                      ]),
                    ),
                  ],
                  if (servicio['observacion'] != null && servicio['observacion'].toString().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(6)),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('⚠️ ', style: TextStyle(fontSize: 12)),
                        Expanded(child: Text(servicio['observacion'].toString(),
                            style: const TextStyle(fontSize: 11, color: Colors.black87))),
                      ]),
                    ),
                  ],
                ],
              ),
            ),
            // (tel. receptor ya aparece en la ficha superior)
            Row(
              children: [
                Expanded(
                  child: TextField(
                    inputFormatters: [CurrencyInputFormatter()],
                    controller: tarifaController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: (tarifaActual == 0.0)
                          ? 'Fijar Tarifa de Central (\$)'
                          : 'Modificar Tarifa',
                      border: const OutlineInputBorder(),
                      isDense: true,
                      filled: true,
                      fillColor: Colors.green[50],
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        tooltip: 'Borrar',
                        onPressed: () => tarifaController.clear(),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green[800],
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    onPressed: () async {
                      // --- INYECCIÓN DE LIMPIEZA TÁCTICA ---
                      String tarifaLimpia = tarifaController.text
                          .replaceAll('\$', '')
                          .replaceAll('.', '')
                          .replaceAll(',', '')
                          .trim();
                      double nuevoPrecio = double.tryParse(tarifaLimpia) ?? 0.0;

                      if (nuevoPrecio > 0) {
                        await Supabase.instance.client
                            .from('servicios')
                            .update({
                              'tarifa': nuevoPrecio,
                              'tarifa_detalle': {
                                'total': nuevoPrecio,
                                'fuente': 'central_manual',
                                'ajuste_manual': nuevoPrecio,
                              },
                            })
                            .eq('id', id);
                        if (context.mounted) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('✅ Tarifa inyectada con éxito'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      }
                    },
                    child: const Text(
                      'FIJAR',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            // (observación ya aparece en la ficha superior)
            const SizedBox(height: 15),
            const Text(
              'LÍNEAS DIRECTAS:',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 6),

            // FILA DEL MÓVIL
            if (servicio['movil_id'] != null)
              FutureBuilder<Map<String, dynamic>?>(
                future: Supabase.instance.client
                    .from('usuarios')
                    .select('telefono, nombre, usuario, rol')
                    .eq('id', servicio['movil_id'])
                    .maybeSingle(),
                builder: (ctx, snap) {
                  final tel = snap.data?['telefono']?.toString() ?? '';
                  final nom = _formatearNombreCentral(snap.data);
                  bool alarmaMovil = servicio['chat_movil_central'] == true;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xff25D366),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                            ),
                            onPressed: () => _abrirWhatsAppCentral(tel, id),
                            icon: const Icon(Icons.wechat, size: 14),
                            label: const Text(
                              'WS MÓVIL',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: alarmaMovil
                                  ? Colors.red[700]
                                  : Colors.black,
                              foregroundColor: alarmaMovil
                                  ? Colors.white
                                  : Colors.blue,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                            ),
                            onPressed: () {
                              final salaMovil = 'soporte_movil_$id';
                              setState(() => _noLeidos.remove(salaMovil));
                              Supabase.instance.client
                                  .from('servicios')
                                  .update({'chat_movil_central': false})
                                  .eq('id', id);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ChatScreen(
                                    salaId: salaMovil,
                                    miId: 0,
                                    miNombre: 'Central',
                                    titulo: 'Chat con $nom',
                                    servicioId: id,
                                    alarmaLocal: 'chat_movil_central',
                                    alarmaDestino: 'chat_central_movil',
                                    destinatarioId: servicio['movil_id'] as int?,
                                    tipoFaq: TipoFaqChat.central,
                                  ),
                                ),
                              );
                            },
                            icon: Icon(
                              alarmaMovil
                                  ? Icons.mark_email_unread
                                  : Icons.chat,
                              size: 14,
                            ),
                            label: Builder(builder: (_) {
                              final cnt = _noLeidos['soporte_movil_$id'] ?? 0;
                              return Text(
                                alarmaMovil
                                    ? (cnt > 0 ? '$cnt SIN LEER' : 'NUEVO MSG')
                                    : 'CHAT MÓVIL',
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              );
                            }),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),

            // FILA DEL CLIENTE
            if (servicio['cliente_id'] != null)
              FutureBuilder<Map<String, dynamic>?>(
                future: Supabase.instance.client
                    .from('usuarios')
                    .select('telefono, nombre')
                    .eq('id', servicio['cliente_id'])
                    .maybeSingle(),
                builder: (ctx, snap) {
                  final tel = snap.data?['telefono']?.toString() ?? '';
                  final nom = snap.data?['nombre']?.toString() ?? 'Cliente';
                  bool alarmaCliente = servicio['chat_cliente_central'] == true;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xff128C7E),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                            ),
                            onPressed: () => _abrirWhatsAppCentral(tel, id),
                            icon: const Icon(Icons.wechat, size: 14),
                            label: const Text(
                              'WS CLIENTE',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: alarmaCliente
                                  ? Colors.red[700]
                                  : Colors.black,
                              foregroundColor: alarmaCliente
                                  ? Colors.white
                                  : const Color(0xff3AF500),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                            ),
                            onPressed: () {
                              final salaCliente = 'soporte_cliente_$id';
                              setState(() => _noLeidos.remove(salaCliente));
                              Supabase.instance.client
                                  .from('servicios')
                                  .update({'chat_cliente_central': false})
                                  .eq('id', id);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ChatScreen(
                                    salaId: salaCliente,
                                    miId: 0,
                                    miNombre: 'Central',
                                    titulo: 'Chat con $nom',
                                    servicioId: id,
                                    alarmaLocal: 'chat_cliente_central',
                                    alarmaDestino: 'chat_central_cliente',
                                    destinatarioId: servicio['cliente_id'] as int?,
                                    tipoFaq: TipoFaqChat.central,
                                  ),
                                ),
                              );
                            },
                            icon: Icon(
                              alarmaCliente
                                  ? Icons.mark_email_unread
                                  : Icons.chat,
                              size: 14,
                            ),
                            label: Builder(builder: (_) {
                              final cnt = _noLeidos['soporte_cliente_$id'] ?? 0;
                              return Text(
                                alarmaCliente
                                    ? (cnt > 0
                                        ? '$cnt SIN LEER'
                                        : 'NUEVO MSG')
                                    : 'CHAT CLIENTE',
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              );
                            }),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
          ],
        ),  // Column
        ),  // SingleChildScrollView
        actions: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            alignment: WrapAlignment.end,
            children: [
              // ---> INYECTA EL BOTÓN DE FUSIÓN AQUÍ <---
              if (estado == 'pendiente')
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purple[800],
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 0,
                    ),
                  ),
                  onPressed: () => _mostrarMenuFusion(context, servicio),
                  child: const Text(
                    'FUSIONAR',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),
              // ------------------------------------------

              // ── BOTÓN GPS (solo servicios activos) ───────────────────
              if (!['finalizado', 'finalizado_por_demora',
                    'finalizado_con_problema', 'cancelado', 'caducado']
                  .contains(estado))
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[700],
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 0),
                  ),
                  icon: const Icon(Icons.my_location,
                      color: Colors.white, size: 13),
                  label: const Text(
                    'PEDIR GPS',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 11),
                  ),
                  onPressed: () async {
                    final link =
                        'https://oukiofdtargjrclualgm.supabase.co'
                        '/functions/v1/capturar-ubicacion?id=$id';
                    final mensaje = Uri.encodeComponent(
                      'Hola 👋 Para que el conductor llegue exactamente '
                      'donde estás, toca este enlace y activa tu GPS '
                      '(un segundo):\n$link',
                    );
                    final uri = Uri.parse('https://wa.me/?text=$mensaje');
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri,
                          mode: LaunchMode.externalApplication);
                    }
                  },
                ),
              // ── FIN BOTÓN GPS ─────────────────────────────────────────
              if ([
                'cancelado',
                'finalizado_por_demora',
                'finalizado_con_problema',
                'caducado',
              ].contains(estado))
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xff3AF500),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 0,
                    ),
                  ),
                  onPressed: () async {
                    await Supabase.instance.client
                        .from('servicios')
                        .update({
                          'estado': 'pendiente',
                          'movil_id': null,
                          'observacion': null,
                          'accepted_at': null,
                          'picked_up_at': null,
                          'extension_minutes': 0,
                        })
                        .eq('id', id);
                    if (context.mounted) Navigator.pop(context);
                  },
                  child: const Text(
                    'REACTIVAR',
                    style: TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue[800],
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 0,
                  ),
                ),
                onPressed: () => _mostrarMenuAsignacion(context, id),
                child: const Text(
                  'REASIGNAR',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ),
              if (estado != 'cancelado' && estado != 'finalizado')
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red[800],
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 0,
                    ),
                  ),
                  onPressed: () async {
                    await Supabase.instance.client
                        .from('servicios')
                        .update({'estado': 'cancelado'})
                        .eq('id', id);
                    if (context.mounted) Navigator.pop(context);
                  },
                  child: const Text(
                    'CANCELAR',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),
              if (estado != 'finalizado')
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 0,
                    ),
                  ),
                  onPressed: () async {
                    String obsAnterior = servicio['observacion'] ?? '';
                    String nuevaObs = obsAnterior;
                    if ([
                      'cancelado',
                      'finalizado_por_demora',
                      'finalizado_con_problema',
                    ].contains(estado)) {
                      nuevaObs =
                          '[MARCA DE FALLA] ${obsAnterior.isEmpty ? 'Cerrado forzoso por Central' : obsAnterior}';
                    }
                    await Supabase.instance.client
                        .from('servicios')
                        .update({
                          'estado': 'finalizado',
                          'observacion': nuevaObs.isEmpty ? null : nuevaObs,
                        })
                        .eq('id', id);
                    if (context.mounted) Navigator.pop(context);
                  },
                  child: const Text(
                    'FINALIZAR',
                    style: TextStyle(
                      color: Color(0xff3AF500),
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  'VOLVER',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── BOTONES DE ACCIÓN EN CARD ─────────────────────────────────────────────

  Widget _botonCard(
          String label, IconData icon, Color color, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: color.withValues(alpha: 0.5), width: 0.8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 11, color: color),
              const SizedBox(width: 4),
              Text(label,
                  style: TextStyle(
                      fontSize: 10,
                      color: color,
                      fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      );

  List<Widget> _botonesAccion(
      BuildContext context, Map<String, dynamic> servicio, String estado) {
    const finales = {
      'finalizado',
      'finalizado_con_problema',
      'finalizado_por_demora',
      'cancelado',
    };
    final btns = <Widget>[];

    // 💰 PRECIO (solo cotizacion — el tap normal ya lo hace pero aquí queda explícito)
    if (estado == 'cotizacion') {
      btns.add(_botonCard('PRECIO', Icons.attach_money, Colors.orange[700]!,
          () => _cotizarRapido(context, servicio)));
    }

    // 🏍 ASIGNAR
    if (['pendiente', 'cotizacion_aprobada', 'cotizada'].contains(estado)) {
      btns.add(_botonCard('ASIGNAR', Icons.motorcycle, Colors.blue[700]!,
          () => _asignarMotoManual(context, servicio)));
    }

    // 🔄 REASIGNAR
    if (estado == 'programado') {
      btns.add(_botonCard('REASIGNAR', Icons.motorcycle, Colors.blue[600]!,
          () => _asignarMotoManual(context, servicio)));
    }

    // ✅ FINALIZAR
    if (['programado', 'en_ruta_origen', 'en_origen', 'en_ruta_destino']
        .contains(estado)) {
      btns.add(_botonCard('FINALIZAR', Icons.check_circle_outline,
          Colors.green[700]!, () => _finalizarServicio(context, servicio)));
    }

    // ⚠️ PROBLEMA
    if (['en_ruta_origen', 'en_origen', 'en_ruta_destino', 'programado']
        .contains(estado)) {
      btns.add(_botonCard('PROBLEMA', Icons.warning_amber_rounded,
          Colors.orange[800]!, () => _marcarProblema(context, servicio)));
    }

    // 🔄 REACTIVAR
    if (['cancelado', 'caducado', 'problema', 'finalizado_por_demora']
        .contains(estado)) {
      btns.add(_botonCard('REACTIVAR', Icons.refresh, Colors.teal[700]!,
          () => _reactivarServicio(servicio)));
    }

    // 🏁 FINALIZAR CON PROBLEMA
    if (estado == 'problema') {
      btns.add(_botonCard('FIN+PROB', Icons.flag_outlined, Colors.red[700]!,
          () => _finalizarConProblema(context, servicio)));
    }

    // ❌ CANCELAR — todo excepto estados finales y ya cancelado
    if (!finales.contains(estado)) {
      btns.add(_botonCard('CANCELAR', Icons.close, Colors.red[700]!,
          () => _cancelarServicio(context, servicio)));
    }

    return btns;
  }

  // ── Asignar multi-ruta: varios servicios → un solo móvil en secuencia ───────
  Future<void> _asignarMultiRuta(BuildContext context) async {
    if (_multiSeleccion.isEmpty) return;

    final ahora = DateTime.now().toUtc();
    final motos = _movilesCache
        .where((m) => m['en_linea'] == true || (() {
              if (m['ultimo_ping'] == null) return false;
              final mins = ahora
                  .difference(DateTime.parse(m['ultimo_ping'].toString()).toUtc())
                  .inMinutes;
              return mins < 10;
            })())
        .toList()
      ..sort((a, b) {
        int pingMin(Map<String, dynamic> m) {
          if (m['ultimo_ping'] == null) return 9999;
          return ahora
              .difference(DateTime.parse(m['ultimo_ping'].toString()).toUtc())
              .inMinutes;
        }
        return pingMin(a).compareTo(pingMin(b));
      });

    if (!mounted) return;

    final motoElegida = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 36, height: 4,
            margin: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
                color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text(
              'Asignar ${_multiSeleccion.length} servicios a un móvil',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: motos.length,
              itemBuilder: (_, i) {
                final m = motos[i];
                final ping = _pingLabel(m);
                final usr = m['usuario']?.toString() ?? '';
                final num = RegExp(r'\d+').firstMatch(usr)?.group(0) ?? '?';
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.indigo[800],
                    child: Text('#$num',
                        style: const TextStyle(color: Colors.white, fontSize: 11)),
                  ),
                  title: Text(m['nombre']?.toString() ?? '#$num',
                      style: const TextStyle(fontSize: 13)),
                  subtitle: Text('$ping · ${m["rango_movil"] ?? "NOVATO"}',
                      style: TextStyle(
                          fontSize: 10,
                          color: ping.startsWith('●') ? Colors.green[700] : Colors.grey)),
                  onTap: () => Navigator.pop(ctx, m),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );

    if (motoElegida == null || !mounted) return;

    // Generar UUID simple para esta multi-ruta
    final rutaId = DateTime.now().millisecondsSinceEpoch.toString();
    final ids = _multiSeleccion.toList();

    // Actualizar todos los servicios seleccionados en secuencia
    for (int i = 0; i < ids.length; i++) {
      await Supabase.instance.client.from('servicios').update({
        'movil_id': motoElegida['id'],
        'estado': 'programado',
        'multi_ruta_id': rutaId,
        'multi_ruta_orden': i + 1,
      }).eq('id', ids[i]);
    }

    if (mounted) {
      setState(() {
        _modoMulti = false;
        _multiSeleccion.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          '${ids.length} servicios asignados a Móvil '
          '${RegExp(r"\d+").firstMatch(motoElegida["usuario"]?.toString() ?? "")?.group(0) ?? "?"}',
        ),
        backgroundColor: Colors.indigo[800],
        duration: const Duration(seconds: 3),
      ));
    }
  }

  Future<void> _asignarMotoManual(
      BuildContext context, Map<String, dynamic> servicio) async {
    final ahora = DateTime.now().toUtc();
    final motos = List<Map<String, dynamic>>.from(_movilesCache)
      ..sort((a, b) {
        final pa = a['ultimo_ping'] != null
            ? DateTime.parse(a['ultimo_ping']).toUtc()
            : DateTime(2000);
        final pb = b['ultimo_ping'] != null
            ? DateTime.parse(b['ultimo_ping']).toUtc()
            : DateTime(2000);
        return pb.compareTo(pa); // más reciente primero
      });

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(ctx).size.height * 0.6,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 4),
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.motorcycle, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${servicio["origen"] ?? ""} ➔ ${servicio["destino"] ?? ""}',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: motos.isEmpty
                  ? const Center(child: Text('Sin motos registradas'))
                  : ListView.builder(
                      itemCount: motos.length,
                      itemBuilder: (ctx, i) {
                        final moto = motos[i];
                        final ping = moto['ultimo_ping'] != null
                            ? DateTime.parse(moto['ultimo_ping']).toUtc()
                            : null;
                        final mins = ping != null
                            ? ahora.difference(ping).inMinutes
                            : null;
                        final conectado = mins != null && mins < 5;
                        final nombre = _formatearNombreCentral(moto);
                        final rango =
                            moto['rango_movil']?.toString() ?? 'NOVATO';

                        return ListTile(
                          dense: true,
                          leading: CircleAvatar(
                            radius: 16,
                            backgroundColor: conectado
                                ? Colors.green[50]
                                : Colors.grey[100],
                            child: Icon(Icons.motorcycle,
                                size: 16,
                                color: conectado
                                    ? Colors.green[700]
                                    : Colors.grey[400]),
                          ),
                          title: Text(nombre,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13)),
                          subtitle: Text(
                            '$rango${mins != null ? " · hace ${mins}min" : " · sin ping"}',
                            style: const TextStyle(fontSize: 11),
                          ),
                          trailing: Icon(Icons.circle,
                              size: 10,
                              color: conectado
                                  ? Colors.green
                                  : Colors.grey[400]),
                          onTap: () async {
                            Navigator.pop(ctx);
                            final nombreMoto = _formatearNombreCentral(moto);
                            await Supabase.instance.client
                                .from('servicios')
                                .update({
                                  'movil_id': moto['id'],
                                  'estado': 'en_ruta_origen',
                                  'accepted_at': DateTime.now().toUtc().toIso8601String(),
                                  'picked_up_at': null,
                                  'extension_minutes': 0,
                                  'observacion': 'Asignado a \$nombreMoto por Central',
                                })
                                .eq('id', servicio['id']);
                            if (moto['ticket_prioridad'] == true) {
                              await Supabase.instance.client
                                  .from('usuarios')
                                  .update({'ticket_prioridad': false})
                                  .eq('id', moto['id']);
                            }
                            await MotorNotificaciones.dispararMisil(
                              idDestino: moto['id'].toString(),
                              titulo: '🚨 NUEVO SERVICIO ASIGNADO',
                              mensaje: 'La Central te ha asignado un servicio. Revisa tu radar.',
                              sonido: Sonidos.alerta,
                            );
                            _seleccionadoId.value = null;
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _cancelarServicio(
      BuildContext context, Map<String, dynamic> servicio) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Cancelar servicio',
            style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text(
            'Servicio #${servicio["id"]}\n${servicio["origen"]} ➔ ${servicio["destino"]}'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('NO', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style:
                ElevatedButton.styleFrom(backgroundColor: Colors.red[700]),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('SÍ, CANCELAR',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await Supabase.instance.client.from('servicios').update({
        'estado': 'cancelado',
        'observacion': servicio['observacion'] != null
            ? '${servicio["observacion"]} | Cancelado por central'
            : 'Cancelado por central',
      }).eq('id', servicio['id']);
      _seleccionadoId.value = null;
    }
  }

  Future<void> _finalizarServicio(
      BuildContext context, Map<String, dynamic> servicio) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Finalizar servicio',
            style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text('¿Marcar #${servicio["id"]} como finalizado?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('NO', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green[700]),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('FINALIZAR',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await Supabase.instance.client
          .from('servicios')
          .update({'estado': 'finalizado'})
          .eq('id', servicio['id']);
      _seleccionadoId.value = null;
    }
  }

  Future<void> _finalizarConProblema(
      BuildContext context, Map<String, dynamic> servicio) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Finalizar con problema',
            style: TextStyle(fontWeight: FontWeight.bold)),
        content:
            Text('¿Cerrar #${servicio["id"]} como finalizado con problema?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('NO', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style:
                ElevatedButton.styleFrom(backgroundColor: Colors.red[700]),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('CONFIRMAR',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await Supabase.instance.client
          .from('servicios')
          .update({'estado': 'finalizado_con_problema'})
          .eq('id', servicio['id']);
      _seleccionadoId.value = null;
    }
  }

  Future<void> _marcarProblema(
      BuildContext context, Map<String, dynamic> servicio) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Marcar problema',
            style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text('¿Reportar problema en servicio #${servicio["id"]}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('NO', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange[700]),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('CONFIRMAR',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await Supabase.instance.client
          .from('servicios')
          .update({'estado': 'problema'})
          .eq('id', servicio['id']);
      _seleccionadoId.value = null;
    }
  }

  Future<void> _reactivarServicio(Map<String, dynamic> servicio) async {
    await Supabase.instance.client.from('servicios').update({
      'estado': 'pendiente',
      'movil_id': null,
      'onesignal_30s': null,
    }).eq('id', servicio['id']);
    _seleccionadoId.value = null;
  }

  // ── COTIZACIÓN RÁPIDA (bottom sheet) ──────────────────────────────────────

  Future<void> _cotizarRapido(
      BuildContext context, Map<String, dynamic> servicio) async {
    final TextEditingController precioCtrl = TextEditingController();
    bool esVip = servicio['es_vip'] == true;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding:
              EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle visual
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Ruta
                Row(
                  children: [
                    const Icon(Icons.route, size: 16, color: Colors.black54),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${servicio["origen"] ?? "—"} ➔ ${servicio["destino"] ?? "—"}',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                if (servicio['cliente_nombre'] != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    '👤 ${servicio["cliente_nombre"]}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
                const SizedBox(height: 16),

                // Campo precio
                TextField(
                  controller: precioCtrl,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    prefixText: '\$ ',
                    prefixStyle: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.bold),
                    hintText: '0',
                    labelText: 'Precio del servicio',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8)),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide:
                          const BorderSide(color: Colors.black, width: 2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Toggle VIP
                GestureDetector(
                  onTap: () => setSheet(() => esVip = !esVip),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: esVip
                          ? const Color(0xFFFFF8E1)
                          : Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: esVip
                            ? const Color(0xFFFFD700)
                            : Colors.grey[300]!,
                      ),
                    ),
                    child: Row(
                      children: [
                        Text(esVip ? '👑' : '⬜',
                            style: const TextStyle(fontSize: 18)),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text('Servicio VIP  (+\$3.000)',
                              style: TextStyle(fontWeight: FontWeight.w600)),
                        ),
                        Switch(
                          value: esVip,
                          onChanged: (v) => setSheet(() => esVip = v),
                          activeColor: const Color(0xFFB8860B),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Botones
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          side: const BorderSide(color: Colors.black38),
                        ),
                        child: const Text('Cancelar'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: () async {
                          final raw = precioCtrl.text
                              .replaceAll(RegExp(r'[^0-9]'), '');
                          final base = int.tryParse(raw) ?? 0;
                          if (base <= 0) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(
                                  content: Text('Ingresa un precio válido'),
                                  duration: Duration(seconds: 2)),
                            );
                            return;
                          }
                          final tarifaFinal = esVip ? base + 3000 : base;
                          Navigator.pop(ctx);
                          await Supabase.instance.client
                              .from('servicios')
                              .update({
                                'tarifa': tarifaFinal,
                                'es_vip': esVip,
                                'estado': 'cotizada',
                              })
                              .eq('id', servicio['id']);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text(
                          'CONFIRMAR PRECIO',
                          style: TextStyle(
                            color: Color(0xff3AF500),
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    precioCtrl.dispose();
  }

  // ── HELPERS MONITOR ────────────────────────────────────────────────────────

  Widget _kpiChip(String label, int count, Color color,
      {VoidCallback? onTap}) {
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: RichText(
        text: TextSpan(children: [
          TextSpan(
            text: '$count ',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: color,
                height: 1),
          ),
          TextSpan(
            text: label,
            style: TextStyle(fontSize: 8, color: color, height: 1),
          ),
        ]),
      ),
    );
    if (onTap == null) return chip;
    return GestureDetector(onTap: onTap, child: chip);
  }

  void _mostrarResumenDia(
      BuildContext context, List<Map<String, dynamic>> todosHoy) {
    final finalizados = todosHoy
        .where((s) => ['finalizado', 'finalizado_con_problema',
            'finalizado_por_demora'].contains(s['estado']))
        .toList();
    final cancelados =
        todosHoy.where((s) => s['estado'] == 'cancelado').length;
    final caducados =
        todosHoy.where((s) => s['estado'] == 'caducado').length;
    final enCurso = todosHoy
        .where((s) => ['pendiente', 'cotizacion', 'cotizada',
            'cotizacion_aprobada', 'programado', 'en_ruta_origen',
            'en_origen', 'en_ruta_destino'].contains(s['estado']))
        .length;
    final facturacion = finalizados.fold<double>(
        0, (a, s) => a + ((s['tarifa'] as num?)?.toDouble() ?? 0));

    // Moto más activa
    final conteoMovil = <String, int>{};
    for (final s in finalizados) {
      final id = s['movil_id']?.toString();
      if (id != null) conteoMovil[id] = (conteoMovil[id] ?? 0) + 1;
    }
    String? motoMasActivaId =
        conteoMovil.entries.isEmpty
            ? null
            : conteoMovil.entries
                .reduce((a, b) => a.value >= b.value ? a : b)
                .key;
    String motoLabel = '—';
    if (motoMasActivaId != null) {
      final m = _movilesCache.firstWhere(
          (m) => m['id'].toString() == motoMasActivaId,
          orElse: () => {});
      if (m.isNotEmpty) {
        motoLabel =
            '${_formatearNombreCentral(m)} · ${conteoMovil[motoMasActivaId]}';
      }
    }

    // Hora pico (hora con más servicios creados)
    final conteoHora = <int, int>{};
    for (final s in todosHoy) {
      if (s['created_at'] == null) continue;
      final h = DateTime.parse(s['created_at']).toLocal().hour;
      conteoHora[h] = (conteoHora[h] ?? 0) + 1;
    }
    String horaPico = '—';
    if (conteoHora.isNotEmpty) {
      final h =
          conteoHora.entries.reduce((a, b) => a.value >= b.value ? a : b);
      final ini = h.key.toString().padLeft(2, '0');
      final fin = (h.key + 1).toString().padLeft(2, '0');
      horaPico = '$ini:00–$fin:00 (${h.value} servicios)';
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 14),
            Row(children: [
              const Icon(Icons.bar_chart_rounded, size: 18),
              const SizedBox(width: 8),
              Text(
                'Resumen del día — ${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ]),
            const SizedBox(height: 16),
            // Stat grid
            Row(children: [
              _resumenStat('TOTAL', '${todosHoy.length}', Colors.blueGrey[700]!),
              const SizedBox(width: 10),
              _resumenStat('ENTREGADOS', '${finalizados.length}', Colors.green[700]!),
              const SizedBox(width: 10),
              _resumenStat('EN CURSO', '$enCurso', Colors.amber[700]!),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              _resumenStat('CANCELADOS', '$cancelados', Colors.red[700]!),
              const SizedBox(width: 10),
              _resumenStat('CADUCADOS', '$caducados', Colors.grey[600]!),
              const SizedBox(width: 10),
              _resumenStat('FACTURADO',
                  _formatearMonedaCentral(facturacion), Colors.black),
            ]),
            const Divider(height: 24),
            _resumenFila('🏆 Moto más activa', motoLabel),
            const SizedBox(height: 8),
            _resumenFila('⏰ Hora pico', horaPico),
          ],
        ),
      ),
    );
  }

  Widget _resumenStat(String label, String value, Color color) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value,
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: color)),
              Text(label,
                  style:
                      const TextStyle(fontSize: 9, color: Colors.black45)),
            ],
          ),
        ),
      );

  Widget _resumenFila(String label, String value) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.black54)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        ],
      );

  String _tiempoRelativo(DateTime utc) {
    final diff = DateTime.now().toUtc().difference(utc);
    if (diff.inMinutes < 1) return 'ahora';
    if (diff.inMinutes < 60) return 'hace ${diff.inMinutes}min';
    final h = diff.inHours;
    final m = diff.inMinutes % 60;
    return m == 0 ? 'hace ${h}h' : 'hace ${h}h ${m}m';
  }

  Widget _chipEstadoMonitor(String estado, Color colorBase) {
    const labels = <String, String>{
      'pendiente': 'LIBRE',
      'cotizacion': 'COTIZ.',
      'cotizada': 'ENVIADA',
      'cotizacion_aprobada': 'APROB.',
      'programado': 'PROGR.',
      'en_ruta_origen': 'RECOG.',
      'en_origen': 'EN LOCAL',
      'en_ruta_destino': 'ENTREGA',
      'problema': 'PROBL.',
      'finalizado': 'FIN.',
      'finalizado_con_problema': 'FIN.PROB',
      'finalizado_por_demora': 'DEMORA',
      'caducado': 'CADUC.',
      'cancelado': 'CANCEL.',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: colorBase.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: colorBase.withValues(alpha: 0.6), width: 0.8),
      ),
      child: Text(
        labels[estado] ?? estado.toUpperCase(),
        style: TextStyle(
            fontSize: 8,
            fontWeight: FontWeight.bold,
            color: colorBase,
            letterSpacing: 0.3),
      ),
    );
  }

  Widget _construirBloqueServicios(
    BuildContext context,
    String titulo,
    List<Map<String, dynamic>> lista,
    Color colorBase,
    IconData icono, {
    bool visible = true,
  }) {
    final int count = lista.length;

    // Ocultar bloque completo si está filtrado fuera o no hay servicios de este tipo
    if (!visible || count == 0) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          margin: const EdgeInsets.only(top: 10, bottom: 4, left: 6, right: 6),
          decoration: BoxDecoration(
            color: colorBase.withValues(alpha: 0.12),
            border: Border(
              left: BorderSide(color: colorBase, width: 4),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  titulo,
                  style: const TextStyle(
                    color: Colors.black87,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                    letterSpacing: 1,
                  ),
                ),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: Container(
                  key: ValueKey(count),
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: colorBase,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$count',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        ...lista.map((servicio) {
          // Resolver el número real del moto a partir de su campo 'usuario'
          // (ej: movil05 → #5). numero_movil es un contador acumulativo de
          // servicios, no el identificador del moto.
          final movCacheEntry = _movilesCache.firstWhere(
            (m) => m['id'] == servicio['movil_id'],
            orElse: () => <String, dynamic>{},
          );
          final movUsuario = movCacheEntry['usuario']?.toString() ?? '';
          final movNumStr =
              RegExp(r'\d+').firstMatch(movUsuario)?.group(0) ?? '';

          final estado = servicio['estado'];

          // --- MOTOR CENTINELA DE RETRASO ---
          final fechaCreacion = servicio['created_at'] != null
              ? DateTime.parse(servicio['created_at']).toUtc()
              : DateTime.now().toUtc();
          final minutosTranscurridos = DateTime.now()
              .toUtc()
              .difference(fechaCreacion)
              .inMinutes;

          // Alerta primaria: Si lleva más de 15 minutos y sigue buscando móvil, yendo al local, o esperando en el local
          bool alertaRetraso =
              (estado == 'pendiente' ||
                  estado == 'en_curso' ||
                  estado == 'en_ruta_origen' ||
                  estado == 'en_origen') &&
              minutosTranscurridos >= 15;

          // Alerta secundaria: Lógica estricta para cuando ya recogió el pedido y va al destino (30 min efectivos)
          if (estado == 'en_ruta_destino' && servicio['picked_up_at'] != null) {
            final startTime = DateTime.parse(servicio['picked_up_at']).toUtc();
            final elapsed = DateTime.now()
                .toUtc()
                .difference(startTime)
                .inMinutes;
            final extension = servicio['extension_minutes'] as int? ?? 0;
            if ((elapsed - extension) >= 30) alertaRetraso = true;
          }

          // Pintamos la tarjeta de rojo si el centinela se activa
          Color tileBackground = alertaRetraso
              ? const Color(0xfffff0f0)
              : Colors.white;
          Color tileBorder = alertaRetraso ? Colors.red[800]! : colorBase;

          // Si no hay retraso, respetamos los colores originales de tu código
          if (!alertaRetraso) {
            if (estado == 'problema') {
              tileBackground = const Color(0xfffff5f5);
              tileBorder = Colors.red[400]!;
            } else if (estado == 'cancelado') {
              tileBackground = const Color(0xfff7f7f7);
              tileBorder = Colors.grey[400]!;
            } else if (estado == 'finalizado_por_demora') {
              tileBackground = const Color(0xfffaf5ff);
              tileBorder = Colors.deepPurple[300]!;
            } else if (estado == 'caducado') {
              tileBackground = const Color(0xfff4e6fa);
              tileBorder = Colors.purple[800]!;
            } else if (estado == 'cotizacion') {
              tileBackground = const Color(0xfffff9f2);
              tileBorder = Colors.orange[400]!;
            } else if (estado == 'programado') {
              // <--- INYECCIÓN DE COLOR
              tileBackground = const Color(0xffe0f2f1); // Verde agua muy claro
              tileBorder = Colors.teal[600]!;
            }
          }

          bool alarmaCentral =
              servicio['chat_movil_central'] == true ||
              servicio['chat_cliente_central'] == true;

          return FadeSlideIn(
            key: ValueKey('monitor_${servicio['id']}'),
            child: Card(
              margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              elevation: 0,
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
                side: BorderSide(
                  color: alarmaCentral ? Colors.red[700]! : tileBorder,
                  width: alarmaCentral ? 2.5 : 1.2,
                ),
              ),
              color: tileBackground,
              child: InkWell(
                onTap: () {
                  final thisId = servicio['id'] as int;
                  if (_modoMulti) {
                    setState(() {
                      if (_multiSeleccion.contains(thisId)) {
                        _multiSeleccion.remove(thisId);
                      } else {
                        _multiSeleccion.add(thisId);
                      }
                    });
                  } else {
                    _seleccionadoId.value =
                        _seleccionadoId.value == thisId ? null : thisId;
                  }
                },
                onLongPress: () => _abrirMenuGestion(context, servicio),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── FILA 1: chip estado · ruta · alarma/acción ──────────
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          if (_modoMulti)
                            Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: Icon(
                                _multiSeleccion.contains(servicio['id'])
                                    ? Icons.check_circle
                                    : Icons.radio_button_unchecked,
                                size: 16,
                                color: _multiSeleccion.contains(servicio['id'])
                                    ? Colors.indigo[700]
                                    : Colors.grey[400],
                              ),
                            ),
                          _chipEstadoMonitor(estado, colorBase),
                          const SizedBox(width: 5),
                          if (servicio['es_vip'] == true)
                            const Text('👑 ', style: TextStyle(fontSize: 11)),
                          Expanded(
                            child: Text(
                              '${servicio["origen"]} ➔ ${servicio["destino"]}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: alarmaCentral ? Colors.red[800] : Colors.black87,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (alarmaCentral)
                            const Padding(
                              padding: EdgeInsets.only(left: 4),
                              child: Icon(Icons.mark_email_unread, color: Colors.red, size: 15),
                            ),
                          const SizedBox(width: 4),
                          Icon(icono, color: colorBase, size: 14),
                          const SizedBox(width: 2),
                          GestureDetector(
                            onTap: () => _abrirMenuGestion(context, servicio),
                            child: const Icon(Icons.more_vert,
                                size: 16, color: Colors.black38),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      // ── FILA 2: tarifa · moto chip · tiempo relativo ─────────
                      Row(
                        children: [
                          Text(
                            estado == 'cotizacion'
                                ? 'PRECIO PEND.'
                                : _formatearMonedaCentral(servicio['tarifa']),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: (servicio['tarifa'] == null ||
                                      servicio['tarifa'] == 0 ||
                                      servicio['tarifa'] == 0.0)
                                  ? Colors.orange[700]
                                  : Colors.black87,
                            ),
                          ),
                          if (servicio['es_vip'] == true)
                            Text(' +VIP',
                                style: TextStyle(
                                    fontSize: 8,
                                    color: Colors.amber[800],
                                    fontWeight: FontWeight.bold)),
                          if (movNumStr.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: Colors.blueGrey[700],
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text(
                                '🏍 #$movNumStr',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                          ] else if (servicio['numero_cliente'] != null ||
                              servicio['numero_local'] != null) ...[
                            const SizedBox(width: 6),
                            Text(
                              [
                                if (servicio['numero_cliente'] != null)
                                  'C#${servicio["numero_cliente"]}',
                                if (servicio['numero_local'] != null)
                                  'L#${servicio["numero_local"]}',
                              ].join(' '),
                              style: TextStyle(
                                  fontSize: 9, color: Colors.blueGrey[400]),
                            ),
                          ],
                          const Spacer(),
                          Text(
                            _tiempoRelativo(fechaCreacion),
                            style: TextStyle(
                                fontSize: 9,
                                color: alertaRetraso
                                    ? Colors.red[700]
                                    : Colors.grey[500]),
                          ),
                        ],
                      ),
                      // ── FILA 3: sub-estado en curso ──────────────────────────
                      if (['en_ruta_origen', 'en_origen', 'en_ruta_destino']
                          .contains(estado)) ...[
                        const SizedBox(height: 2),
                        Builder(builder: (context) {
                          if (estado == 'en_ruta_origen') {
                            return const Text('🏃 En camino a recogida...',
                                style: TextStyle(
                                    color: Colors.blue,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold));
                          } else if (estado == 'en_origen') {
                            return const Text('🛒 En el local — reloj pausado',
                                style: TextStyle(
                                    color: Colors.orange,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold));
                          } else if (estado == 'en_ruta_destino' &&
                              servicio['picked_up_at'] != null) {
                            final startTime =
                                DateTime.parse(servicio['picked_up_at']).toUtc();
                            final efectivos = DateTime.now()
                                    .toUtc()
                                    .difference(startTime)
                                    .inMinutes -
                                (servicio['extension_minutes'] as int? ?? 0);
                            return Text(
                              efectivos >= 30
                                  ? '⏳ Retrasado en entrega: ${efectivos}min'
                                  : '🛵 En entrega: ${efectivos}min',
                              style: TextStyle(
                                color: efectivos >= 30
                                    ? Colors.orange[900]
                                    : Colors.black54,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            );
                          }
                          return const SizedBox.shrink();
                        }),
                      ],
                      // ── FILA 4: badges opcionales (wrap) ─────────────────────
                      if (alertaRetraso ||
                          (servicio['creador'] != null &&
                              servicio['creador'] != 'Central') ||
                          (estado == 'programado' &&
                              servicio['liberacion_at'] != null) ||
                          servicio['observacion'] != null) ...[
                        const SizedBox(height: 3),
                        Wrap(
                          spacing: 4,
                          runSpacing: 2,
                          children: [
                            if (alertaRetraso)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 5, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.red[900],
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.warning_amber_rounded,
                                          color: Colors.white, size: 10),
                                      const SizedBox(width: 3),
                                      Text(
                                        estado == 'en_ruta_destino'
                                            ? 'RETRASO ENTREGA'
                                            : 'RETRASO ${minutosTranscurridos}MIN',
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 8,
                                            fontWeight: FontWeight.bold),
                                      ),
                                    ]),
                              ),
                            if (servicio['creador'] != null &&
                                servicio['creador'] != 'Central')
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 5, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.yellowAccent[700],
                                  borderRadius: BorderRadius.circular(3),
                                  border:
                                      Border.all(color: Colors.black45, width: 0.5),
                                ),
                                child: Text(
                                  '🏢 ${servicio["creador"].toString().toUpperCase()}',
                                  style: const TextStyle(
                                      color: Colors.black,
                                      fontSize: 8,
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
                            if (estado == 'programado' &&
                                servicio['liberacion_at'] != null)
                              Builder(builder: (context) {
                                final lib = DateTime.parse(
                                        servicio['liberacion_at'])
                                    .toLocal();
                                final diff =
                                    lib.difference(DateTime.now()).inMinutes;
                                return Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 5, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.teal[100],
                                    borderRadius: BorderRadius.circular(3),
                                    border: Border.all(color: Colors.teal[300]!),
                                  ),
                                  child: Text(
                                    diff > 0
                                        ? '⏰ Disparo en ${diff}min'
                                        : '⏰ Liberando...',
                                    style: TextStyle(
                                        color: Colors.teal[900],
                                        fontSize: 8,
                                        fontWeight: FontWeight.bold),
                                  ),
                                );
                              }),
                            if (servicio['observacion'] != null)
                              ConstrainedBox(
                                constraints:
                                    const BoxConstraints(maxWidth: 240),
                                child: Text(
                                  '📝 ${servicio["observacion"]}',
                                  style: TextStyle(
                                      color: Colors.indigo[900],
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                        ),
                      ],

                      // ── FILA 5: acciones rápidas (expandible al seleccionar) ──
                      ValueListenableBuilder<int?>(
                        valueListenable: _seleccionadoId,
                        builder: (context, selId, _) {
                          final seleccionado = selId == servicio['id'];
                          final btns = seleccionado
                              ? _botonesAccion(context, servicio, estado)
                              : <Widget>[];
                          return AnimatedSize(
                            duration: const Duration(milliseconds: 180),
                            curve: Curves.easeInOut,
                            child: seleccionado && btns.isNotEmpty
                                ? Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Wrap(
                                      spacing: 5,
                                      runSpacing: 5,
                                      children: btns,
                                    ),
                                  )
                                : const SizedBox.shrink(),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );  // FadeSlideIn
        }),
      ],
    );
  }

  Future<void> _archivarServiciosTerminados() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text(
          '🧹 LIMPIAR RADAR',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: const Text(
          '¿Archivar todos los servicios finalizados, caducados y cancelados?\n\nDesaparecerán de esta pantalla para limpiar tu visión, pero seguirán contando en tu corte financiero de caja.',
          style: TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCELAR', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.black),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'LIMPIAR TODO',
              style: TextStyle(
                color: Color(0xff3AF500),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmar == true) {
      try {
        // 1. El misil a la base de datos (Exclusivo para terminales)
        await Supabase.instance.client
            .from('servicios')
            .update({'archivado': true})
            .inFilter('estado', [
              'finalizado',
              'cancelado',
              'finalizado_por_demora',
              'finalizado_con_problema',
              'caducado', // El caducado es un cancelado por el sistema
            ])
            .eq('archivado', false);

        if (mounted) {
          // Reinicio del canal — ahora vía el vigilante de conexión, sin
          // parpadeo (antes esto reemplazaba el Stream directo y el
          // StreamBuilder mostraba el loading spinner por un instante).
          _construirStreams();

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Radar limpio. Servicios purgados con éxito.'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error al archivar: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }


}
