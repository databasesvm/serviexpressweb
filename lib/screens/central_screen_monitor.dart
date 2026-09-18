// ignore_for_file: use_build_context_synchronously, invalid_use_of_protected_member
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

    // FN sede: cotización/renegociación usa diálogo especializado
    if (servicio['fn_origen']?.toString() == 'sede' &&
        (estado == 'cotizacion' || estado == 'fn_renegociando')) {
      await _mostrarDialogoCotizacionFn(servicio);
      return;
    }

    if (estado == 'cotizacion') {
      // FAST-PATH: si el motor tiene alta confianza, ofrecemos resolución en 1 tap.
      // Si el usuario elige "Revisar manualmente" (null), caemos al diálogo completo.
      // Si la llamada falla o confianza != 'alta', también caemos al diálogo completo.
      final bool resueltoPorMotor = await _fastPathCotizacion(context, servicio, esVip);
      if (resueltoPorMotor) return;

      if (!mounted) return;
      showDialog(
        context: context,
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
                    '👑 COTIZACIÓN VIP #${_consec(id)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                )
              : Text(
                  'RESOLVER COTIZACIÓN #${_consec(id)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.orange,
                  ),
                ),
          content: SingleChildScrollView(
            child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '🏢 Origen: ${servicio['creador'].toString().toUpperCase()}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Text('🏁 Va para: ${servicio['destino']}'),
              // ── Detalles del servicio ─────────────────────────────────
              if ((servicio['observacion'] ?? '').toString().trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF8E1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFFFFE082)),
                  ),
                  child: Text(
                    servicio['observacion'].toString().trim(),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
              if (servicio['recogidas'] != null &&
                  (servicio['recogidas'] as List).isNotEmpty) ...[
                const SizedBox(height: 4),
                ...((servicio['recogidas'] as List).map((r) => Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    '🔵 Recogida: ${r['nombre'] ?? r['zona'] ?? ''}',
                    style: const TextStyle(fontSize: 12, color: Colors.blue),
                  ),
                ))),
              ],
              if ((servicio['instrucciones_especiales'] ?? '').toString().trim().isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  '📝 ${servicio['instrucciones_especiales']}',
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
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
          )),
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
            'COTIZACIÓN ENVIADA #${_consec(id)}',
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
                // Notificar al móvil si ya tenía uno asignado
                final movilId = servicio['movil_id']?.toString();
                if (movilId != null && movilId.isNotEmpty && movilId != 'null') {
                  MotorNotificaciones.dispararMisil(
                    idDestino: movilId,
                    titulo: '❌ Servicio cancelado',
                    mensaje: 'El servicio #$id fue cancelado.',
                    urgente: false,
                    sonido: 'central_cancelado',
                    canalAndroidId: MotorNotificaciones.canalCanceladoId,
                  );
                }
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

    // ── Variables de la ficha para usar sin conflicto de comillas ─────────
    String fechaCreado = '';
    if (servicio['created_at'] != null) {
      try {
        final dt = DateTime.parse(servicio['created_at'].toString()).toLocal();
        final d = dt.day.toString().padLeft(2, '0');
        final m = dt.month.toString().padLeft(2, '0');
        final h = dt.hour.toString().padLeft(2, '0');
        final min = dt.minute.toString().padLeft(2, '0');
        fechaCreado = '$d/$m $h:$min';
      } catch (_) {
        fechaCreado = servicio['created_at'].toString();
      }
    }
    final String? telReceptor = servicio['telefono_receptor']?.toString();
    final String? numLocal    = servicio['numero_local']?.toString();
    final String? numCliente  = servicio['numero_cliente']?.toString();
    final String tarifaTexto  = tarifaActual == 0.0
        ? 'Sin fijar'
        : _formatearMonedaCentral(tarifaActual);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (_, scrollCtrl) => Container(
          decoration: const BoxDecoration(
            color: Color(0xFF1A1A2E),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Handle
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 10, bottom: 6),
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Header oscuro
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'ORDEN #${_consec(id)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                    _badgeDark((servicio['tipo_servicio'] ?? 'domicilio').toString().toUpperCase(), Colors.white12, Colors.white),
                    const SizedBox(width: 5),
                    _badgeDark(estado.toUpperCase().replaceAll('_', ' '), const Color(0xFF16213E), Colors.cyanAccent),
                    if (servicio['es_vip'] == true) ...[
                      const SizedBox(width: 5),
                      _badgeDark('👑 VIP', const Color(0xFF7B5800), Colors.amber),
                    ],
                    if (servicio['es_punto_a_punto'] == true) ...[
                      const SizedBox(width: 5),
                      _badgeDark('PAP', Colors.purple.shade900, Colors.purpleAccent),
                    ],
                  ],
                ),
              ),
              const Divider(color: Colors.white12, height: 1),
              // Cuerpo scrollable
              Expanded(
                child: ListView(
                  controller: scrollCtrl,
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                  children: [
                    // ── RUTA ──────────────────────────────────────────────
                    _seccion(
                      icon: Icons.route,
                      color: Colors.cyanAccent,
                      titulo: 'RUTA',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            const Icon(Icons.trip_origin, size: 14, color: Colors.greenAccent),
                            const SizedBox(width: 8),
                            Expanded(child: Text(servicio['origen']?.toString() ?? '',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14))),
                          ]),
                          const Padding(
                            padding: EdgeInsets.only(left: 6),
                            child: Text('│', style: TextStyle(color: Colors.white24, fontSize: 12)),
                          ),
                          Row(children: [
                            const Icon(Icons.location_on, size: 14, color: Colors.redAccent),
                            const SizedBox(width: 8),
                            Expanded(child: Text(servicio['destino']?.toString() ?? '',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14))),
                          ]),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // ── DETALLES ───────────────────────────────────────────
                    _seccion(
                      icon: Icons.info_outline,
                      color: Colors.amberAccent,
                      titulo: 'DETALLES',
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          _infoBadge('💵 Tarifa', tarifaTexto,
                              tarifaActual == 0.0 ? Colors.orange.shade900 : const Color(0xFF1B5E20),
                              tarifaActual == 0.0 ? Colors.orangeAccent : Colors.greenAccent),
                          if (fechaCreado.isNotEmpty)
                            _infoBadge('🕐 Creado', fechaCreado, const Color(0xFF0D1B2A), Colors.white70),
                          if (telReceptor != null)
                            _infoBadge('📞 Receptor', telReceptor, const Color(0xFF0D1B4A), Colors.lightBlueAccent),
                          if (numLocal != null)
                            _infoBadge('🏪 Local', '#$numLocal', const Color(0xFF1A0A2E), Colors.purpleAccent),
                          if (numCliente != null)
                            _infoBadge('👤 Cliente', '#$numCliente', const Color(0xFF0A1A0A), Colors.lightGreenAccent),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // ── NOTAS ─────────────────────────────────────────────
                    if ((servicio['instrucciones_especiales']?.toString().isNotEmpty ?? false) ||
                        (servicio['observacion']?.toString().isNotEmpty ?? false) ||
                        (servicio['recogidas'] != null && (servicio['recogidas'] as List).isNotEmpty)) ...[
                      _seccion(
                        icon: Icons.notes,
                        color: Colors.orangeAccent,
                        titulo: 'NOTAS',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (servicio['instrucciones_especiales']?.toString().isNotEmpty ?? false)
                              _notaBadge('📝', servicio['instrucciones_especiales'].toString(),
                                  Colors.amber.shade900.withValues(alpha: 0.3), Colors.amber.shade200),
                            if (servicio['observacion']?.toString().isNotEmpty ?? false) ...[
                              if (servicio['instrucciones_especiales']?.toString().isNotEmpty ?? false)
                                const SizedBox(height: 6),
                              _notaBadge('⚠️', servicio['observacion'].toString(),
                                  Colors.red.shade900.withValues(alpha: 0.2), Colors.red.shade200),
                            ],
                            if (servicio['recogidas'] != null && (servicio['recogidas'] as List).isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade900.withValues(alpha: 0.3),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('🔵 Recogidas:',
                                        style: TextStyle(color: Colors.lightBlueAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 4),
                                    ...((servicio['recogidas'] as List).map((r) => Text(
                                      '• ${r['nombre'] ?? r['zona'] ?? ''}',
                                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                                    ))),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],

                    // ── FIJAR TARIFA ──────────────────────────────────────
                    if (!['finalizado', 'finalizado_por_demora', 'finalizado_con_problema'].contains(estado)) ...[
                      _seccion(
                        icon: Icons.attach_money,
                        color: Colors.greenAccent,
                        titulo: 'FIJAR TARIFA',
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                inputFormatters: [CurrencyInputFormatter()],
                                controller: tarifaController,
                                keyboardType: TextInputType.number,
                                style: const TextStyle(color: Colors.white),
                                decoration: InputDecoration(
                                  hintText: tarifaActual == 0.0 ? 'Ej: \$15.000' : tarifaTexto,
                                  hintStyle: const TextStyle(color: Colors.white38),
                                  filled: true,
                                  fillColor: const Color(0xFF0D2818),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: const BorderSide(color: Colors.green, width: 1),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(color: Colors.green.shade800, width: 1),
                                  ),
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  suffixIcon: IconButton(
                                    icon: const Icon(Icons.clear, size: 16, color: Colors.white38),
                                    onPressed: () => tarifaController.clear(),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green[800],
                                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              onPressed: () async {
                                String tarifaLimpia = tarifaController.text
                                    .replaceAll('\$', '').replaceAll('.', '').replaceAll(',', '').trim();
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
                              child: const Text('FIJAR', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],

                    // ── LÍNEAS DIRECTAS ───────────────────────────────────
                    if (servicio['movil_id'] != null || servicio['cliente_id'] != null)
                      _seccion(
                        icon: Icons.contact_phone,
                        color: Colors.lightBlueAccent,
                        titulo: 'LÍNEAS DIRECTAS',
                        child: Column(
                          children: [
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
                                  return _contactRow(
                                    icono: Icons.motorcycle,
                                    nombre: nom.isNotEmpty ? nom : 'Móvil',
                                    colorIcono: Colors.greenAccent,
                                    wsLabel: 'WS MÓVIL',
                                    wsColor: const Color(0xff25D366),
                                    onWs: () => _abrirWhatsAppCentral(tel, id),
                                    chatLabel: alarmaMovil
                                        ? ((_noLeidos['soporte_movil_$id'] ?? 0) > 0
                                            ? '${_noLeidos['soporte_movil_$id']} SIN LEER'
                                            : 'NUEVO MSG')
                                        : 'CHAT MÓVIL',
                                    chatColor: alarmaMovil ? Colors.red.shade700 : Colors.blueGrey.shade700,
                                    chatIcon: alarmaMovil ? Icons.mark_email_unread : Icons.chat_bubble_outline,
                                    onChat: () {
                                      final salaMovil = 'soporte_movil_$id';
                                      setState(() => _noLeidos.remove(salaMovil));
                                      Supabase.instance.client
                                          .from('servicios')
                                          .update({'chat_movil_central': false})
                                          .eq('id', id);
                                      Navigator.push(context, MaterialPageRoute(
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
                                      ));
                                    },
                                  );
                                },
                              ),
                            if (servicio['movil_id'] != null && servicio['cliente_id'] != null)
                              const SizedBox(height: 8),
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
                                  return _contactRow(
                                    icono: Icons.person,
                                    nombre: nom,
                                    colorIcono: Colors.lightGreenAccent,
                                    wsLabel: 'WS CLIENTE',
                                    wsColor: const Color(0xff128C7E),
                                    onWs: () => _abrirWhatsAppCentral(tel, id),
                                    chatLabel: alarmaCliente
                                        ? ((_noLeidos['soporte_cliente_$id'] ?? 0) > 0
                                            ? '${_noLeidos['soporte_cliente_$id']} SIN LEER'
                                            : 'NUEVO MSG')
                                        : 'CHAT CLIENTE',
                                    chatColor: alarmaCliente ? Colors.red.shade700 : Colors.teal.shade800,
                                    chatIcon: alarmaCliente ? Icons.mark_email_unread : Icons.chat_bubble_outline,
                                    onChat: () {
                                      final salaCliente = 'soporte_cliente_$id';
                                      setState(() => _noLeidos.remove(salaCliente));
                                      Supabase.instance.client
                                          .from('servicios')
                                          .update({'chat_cliente_central': false})
                                          .eq('id', id);
                                      Navigator.push(context, MaterialPageRoute(
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
                                      ));
                                    },
                                  );
                                },
                              ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 12),

                    // ── ACCIONES ──────────────────────────────────────────
                    _seccion(
                      icon: Icons.flash_on,
                      color: Colors.white,
                      titulo: 'ACCIONES',
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (estado == 'pendiente')
                            _accionBtn('FUSIONAR', Colors.purple.shade700, Colors.white,
                                () => _mostrarMenuFusion(context, servicio)),
                          if (!['finalizado', 'finalizado_por_demora', 'finalizado_con_problema', 'cancelado', 'caducado'].contains(estado))
                            _accionBtnIcon(Icons.my_location, 'GPS', Colors.blue.shade700, Colors.white, () async {
                              final link = 'https://oukiofdtargjrclualgm.supabase.co/functions/v1/capturar-ubicacion?id=$id';
                              final mensaje = Uri.encodeComponent(
                                'Hola 👋 Para que el conductor llegue exactamente donde estás, toca este enlace y activa tu GPS (un segundo):\n$link',
                              );
                              final uri = Uri.parse('https://wa.me/?text=$mensaje');
                              if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
                            }),
                          if (['cancelado', 'finalizado_por_demora', 'finalizado_con_problema', 'caducado'].contains(estado))
                            _accionBtn('REACTIVAR', const Color(0xff3AF500), Colors.black, () async {
                              await Supabase.instance.client
                                  .from('servicios')
                                  .update({'estado': 'pendiente', 'movil_id': null, 'observacion': null,
                                           'accepted_at': null, 'picked_up_at': null, 'extension_minutes': 0})
                                  .eq('id', id);
                              if (context.mounted) Navigator.pop(context);
                            }),
                          if (!['finalizado', 'finalizado_por_demora', 'finalizado_con_problema', 'cancelado', 'caducado'].contains(estado))
                            _accionBtn('EDITAR', Colors.orange.shade800, Colors.white, () {
                              Navigator.pop(context);
                              _editarServicio(context, servicio);
                            }),
                          _accionBtn('REASIGNAR', Colors.blue.shade800, Colors.white, () {
                            Navigator.pop(context);
                            _asignarMotoManual(context, servicio);
                          }),
                          if (estado != 'cancelado' && estado != 'finalizado')
                            _accionBtn('CANCELAR', Colors.red.shade800, Colors.white, () async {
                              for (final campo in ['onesignal_30s', 'onesignal_2m', 'onesignal_5m']) {
                                final nId = servicio[campo]?.toString();
                                if (nId != null && nId.isNotEmpty && nId != 'null')
                                  MotorNotificaciones.cancelarMisil(nId).catchError((_) {});
                              }
                              for (final campo in ['fn_notif_fase2', 'fn_notif_fase3', 'fn_notif_fase4', 'fn_notif_fase4b']) {
                                final nId = servicio[campo]?.toString();
                                if (nId != null && nId.isNotEmpty && nId != 'null')
                                  MotorNotificaciones.cancelarMisil(nId).catchError((_) {});
                              }
                              await Supabase.instance.client
                                  .from('servicios')
                                  .update({'estado': 'cancelado', 'onesignal_30s': null, 'onesignal_2m': null, 'onesignal_5m': null,
                                           'fn_notif_fase2': null, 'fn_notif_fase3': null, 'fn_notif_fase4': null, 'fn_notif_fase4b': null})
                                  .eq('id', id);
                              final movilId = servicio['movil_id']?.toString();
                              if (movilId != null && movilId.isNotEmpty && movilId != 'null') {
                                MotorNotificaciones.dispararMisil(
                                  idDestino: movilId,
                                  titulo: '❌ Servicio cancelado',
                                  mensaje: 'El servicio #$id fue cancelado.',
                                  urgente: false,
                                  sonido: 'central_cancelado',
                                  canalAndroidId: MotorNotificaciones.canalCanceladoId,
                                );
                              }
                              if (context.mounted) Navigator.pop(context);
                            }),
                          if (estado != 'finalizado')
                            _accionBtn('FINALIZAR', Colors.black, const Color(0xff3AF500), () async {
                              String obsAnterior = servicio['observacion'] ?? '';
                              String nuevaObs = obsAnterior;
                              if (['cancelado', 'finalizado_por_demora', 'finalizado_con_problema'].contains(estado)) {
                                nuevaObs = '[MARCA DE FALLA] ${obsAnterior.isEmpty ? 'Cerrado forzoso por Central' : obsAnterior}';
                              }
                              for (final campo in ['onesignal_30s', 'onesignal_2m', 'onesignal_5m']) {
                                final nId = servicio[campo]?.toString();
                                if (nId != null && nId.isNotEmpty && nId != 'null')
                                  MotorNotificaciones.cancelarMisil(nId).catchError((_) {});
                              }
                              for (final campo in ['fn_notif_fase2', 'fn_notif_fase3', 'fn_notif_fase4', 'fn_notif_fase4b']) {
                                final nId = servicio[campo]?.toString();
                                if (nId != null && nId.isNotEmpty && nId != 'null')
                                  MotorNotificaciones.cancelarMisil(nId).catchError((_) {});
                              }
                              await Supabase.instance.client
                                  .from('servicios')
                                  .update({
                                    'estado': 'finalizado',
                                    'observacion': nuevaObs.isEmpty ? null : nuevaObs,
                                    'onesignal_30s': null, 'onesignal_2m': null, 'onesignal_5m': null,
                                    'fn_notif_fase2': null, 'fn_notif_fase3': null, 'fn_notif_fase4': null, 'fn_notif_fase4b': null,
                                    'paradero_auto_movil_id': null, 'fn_fase2_movil_id': null,
                                  })
                                  .eq('id', id);
                              if (context.mounted) Navigator.pop(context);
                            }),
                          _accionBtn('VOLVER', const Color(0xFF2A2A3E), Colors.white70,
                              () => Navigator.pop(context)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── EDITAR SERVICIO ──────────────────────────────────────────────────────

  Future<void> _editarServicio(BuildContext context, Map<String, dynamic> servicio) async {
    final int id = servicio['id'];

    final origenCtrl      = TextEditingController(text: servicio['origen']?.toString() ?? '');
    final destinoCtrl     = TextEditingController(text: servicio['destino']?.toString() ?? '');
    final telefonoCtrl    = TextEditingController(text: servicio['telefono_receptor']?.toString() ?? '');
    final instrucCtrl     = TextEditingController(text: servicio['instrucciones']?.toString() ?? '');
    final instrEspCtrl    = TextEditingController(text: servicio['instrucciones_especiales']?.toString() ?? '');
    final obsCtrl         = TextEditingController(text: servicio['observacion']?.toString() ?? '');
    final tiempoCtrl      = TextEditingController(
      text: servicio['tiempo_estimado_minutos'] != null
          ? servicio['tiempo_estimado_minutos'].toString()
          : '',
    );

    String metodoPago  = servicio['metodo_pago']?.toString() ?? 'Efectivo';
    String tipoServicio = servicio['tipo_servicio']?.toString() ?? 'domicilio';

    const metodosPago  = ['Efectivo', 'Datafono', 'Nequi', 'Daviplata', 'Transferencia'];
    const tiposServicio = [
      'domicilio', 'mototaxi', 'PAQUETERÍA', 'COMIDA',
      'FARMACIA', 'BEBIDAS', 'FARMANORTE', 'RECOGIDA LOCAL',
    ];

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: Text(
            '✏️ EDITAR SERVICIO #${_consec(id)}',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.orange),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Origen
                _campoEdicion('Origen 📍', origenCtrl, maxLines: 2),
                const SizedBox(height: 10),
                // Destino
                _campoEdicion('Destino 🏁', destinoCtrl, maxLines: 2),
                const SizedBox(height: 10),
                // Teléfono receptor
                _campoEdicion('Teléfono receptor 📞', telefonoCtrl,
                    tipo: TextInputType.phone),
                const SizedBox(height: 10),
                // Método de pago
                const Text('Método de pago 💳',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black54)),
                const SizedBox(height: 4),
                DropdownButtonFormField<String>(
                  value: metodosPago.contains(metodoPago) ? metodoPago : metodosPago.first,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    filled: true,
                    fillColor: Colors.blue[50],
                  ),
                  items: metodosPago
                      .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                      .toList(),
                  onChanged: (v) => setStateDialog(() => metodoPago = v ?? metodoPago),
                ),
                const SizedBox(height: 10),
                // Tipo de servicio
                const Text('Tipo de servicio 🏷️',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black54)),
                const SizedBox(height: 4),
                DropdownButtonFormField<String>(
                  value: tiposServicio.contains(tipoServicio) ? tipoServicio : null,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    filled: true,
                    fillColor: Colors.purple[50],
                  ),
                  hint: Text(tiposServicio.contains(tipoServicio) ? tipoServicio : tipoServicio),
                  items: tiposServicio
                      .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                      .toList(),
                  onChanged: (v) => setStateDialog(() => tipoServicio = v ?? tipoServicio),
                ),
                const SizedBox(height: 10),
                // Tiempo estimado
                _campoEdicion('Tiempo estimado (min) ⏱️', tiempoCtrl,
                    tipo: TextInputType.number),
                const SizedBox(height: 10),
                // Instrucciones
                _campoEdicion('Instrucciones 📝', instrucCtrl, maxLines: 3),
                const SizedBox(height: 10),
                // Instrucciones especiales
                _campoEdicion('Instrucciones especiales ⚡', instrEspCtrl, maxLines: 2),
                const SizedBox(height: 10),
                // Observación
                _campoEdicion('Observación ⚠️', obsCtrl, maxLines: 2),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('CANCELAR',
                  style: TextStyle(color: Colors.black54, fontWeight: FontWeight.bold, fontSize: 11)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange[800],
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
              ),
              onPressed: () async {
                final Map<String, dynamic> cambios = {};

                final newOrigen  = origenCtrl.text.trim();
                final newDestino = destinoCtrl.text.trim();
                final newTel     = telefonoCtrl.text.trim();
                final newInstruc = instrucCtrl.text.trim();
                final newInstrEsp = instrEspCtrl.text.trim();
                final newObs     = obsCtrl.text.trim();
                final newTiempo  = int.tryParse(tiempoCtrl.text.trim());

                if (newOrigen.isNotEmpty)   cambios['origen']   = newOrigen;
                if (newDestino.isNotEmpty)  cambios['destino']  = newDestino;
                cambios['telefono_receptor']           = newTel.isEmpty ? null : newTel;
                cambios['instrucciones']               = newInstruc.isEmpty ? null : newInstruc;
                cambios['instrucciones_especiales']    = newInstrEsp.isEmpty ? null : newInstrEsp;
                cambios['observacion']                 = newObs.isEmpty ? null : newObs;
                cambios['metodo_pago']                 = metodoPago;
                cambios['tipo_servicio']               = tipoServicio;
                if (newTiempo != null) cambios['tiempo_estimado_minutos'] = newTiempo;

                if (cambios.isNotEmpty) {
                  await Supabase.instance.client
                      .from('servicios')
                      .update(cambios)
                      .eq('id', id);
                }

                if (ctx.mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('✅ Servicio actualizado'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                }
              },
              child: const Text(
                'GUARDAR',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _campoEdicion(
    String label,
    TextEditingController ctrl, {
    int maxLines = 1,
    TextInputType tipo = TextInputType.text,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black54)),
        const SizedBox(height: 4),
        TextField(
          controller: ctrl,
          maxLines: maxLines,
          keyboardType: tipo,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          ),
        ),
      ],
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

    // 💰 PRECIO (cotizacion y renegociación FN)
    if (estado == 'cotizacion' || estado == 'fn_renegociando') {
      final esFnSede = servicio['fn_origen']?.toString() == 'sede';
      btns.add(_botonCard(
          estado == 'fn_renegociando' ? 'RENEGOCIAR' : 'PRECIO',
          Icons.attach_money,
          estado == 'fn_renegociando' ? Colors.deepOrange[700]! : Colors.orange[700]!,
          esFnSede
              ? () => _mostrarDialogoCotizacionFn(servicio)
              : () => _cotizarRapido(context, servicio)));
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
        .where((m) => m['en_linea'] == true) // solo conectados
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
    final motos = _movilesCache
        .where((m) => m['en_linea'] == true) // solo conectados
        .toList()
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
                  ? const Center(child: Text('Sin móviles conectados'))
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
                            // Cancelar cascada SE + FN antes de asignar
                            for (final campo in ['onesignal_30s', 'onesignal_2m', 'onesignal_5m',
                                                 'fn_notif_fase2', 'fn_notif_fase3', 'fn_notif_fase4', 'fn_notif_fase4b']) {
                              final nId = servicio[campo]?.toString();
                              if (nId != null && nId.isNotEmpty && nId != 'null')
                                MotorNotificaciones.cancelarMisil(nId).catchError((_) {});
                            }
                            await Supabase.instance.client
                                .from('servicios')
                                .update({
                                  'movil_id': moto['id'],
                                  'estado': 'en_ruta_origen',
                                  'accepted_at': DateTime.now().toUtc().toIso8601String(),
                                  'picked_up_at': null,
                                  'extension_minutes': 0,
                                  'observacion': 'Asignado a $nombreMoto por Central',
                                  'onesignal_30s': null,
                                  'onesignal_2m': null,
                                  'onesignal_5m': null,
                                  'fn_notif_fase2': null,
                                  'fn_notif_fase3': null,
                                  'fn_notif_fase4': null,
                                  'fn_notif_fase4b': null,
                                })
                                .eq('id', servicio['id']);
                            if (moto['ticket_prioridad'] == true) {
                              await Supabase.instance.client
                                  .from('usuarios')
                                  .update({
                                    'ticket_prioridad': false,
                                    'ingreso_fila': DateTime.now().toUtc().toIso8601String(),
                                  })
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
      final esFn = servicio['fn_origen'] != null ||
          servicio['tipo_fn'] == true;

      // SE: cancelar misiles de cascada
      for (final campo in ['onesignal_30s', 'onesignal_2m', 'onesignal_5m']) {
        final nId = servicio[campo]?.toString();
        if (nId != null && nId.isNotEmpty && nId != 'null')
          MotorNotificaciones.cancelarMisil(nId).catchError((_) {});
      }
      // FN: cancelar misiles de cascada
      if (esFn) {
        for (final campo in ['fn_notif_fase2', 'fn_notif_fase3', 'fn_notif_fase4', 'fn_notif_fase4b']) {
          final nId = servicio[campo]?.toString();
          if (nId != null && nId.isNotEmpty && nId != 'null')
            MotorNotificaciones.cancelarMisil(nId).catchError((_) {});
        }
      }

      await Supabase.instance.client.from('servicios').update({
        'estado': 'cancelado',
        'observacion': servicio['observacion'] != null
            ? '${servicio["observacion"]} | Cancelado por central'
            : 'Cancelado por central',
        'onesignal_30s': null,
        'onesignal_2m': null,
        'onesignal_5m': null,
        if (esFn) 'fn_notif_fase2': null,
        if (esFn) 'fn_notif_fase3': null,
        if (esFn) 'fn_notif_fase4': null,
        if (esFn) 'fn_notif_fase4b': null,
        if (esFn) 'fn_notificados_fase1': <String>[],
      }).eq('id', servicio['id']);
      // Notificar al móvil si ya tenía uno asignado
      final movilId = servicio['movil_id']?.toString();
      if (movilId != null && movilId.isNotEmpty && movilId != 'null') {
        MotorNotificaciones.dispararMisil(
          idDestino: movilId,
          titulo: '❌ Servicio cancelado',
          mensaje: 'El servicio #${servicio['id']} fue cancelado.',
          urgente: false,
          sonido: 'central_cancelado',
          canalAndroidId: MotorNotificaciones.canalCanceladoId,
        );
      }
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
      // Cancelar cascada SE + FN pendiente
      for (final campo in ['onesignal_30s', 'onesignal_2m', 'onesignal_5m']) {
        final nId = servicio[campo]?.toString();
        if (nId != null && nId.isNotEmpty && nId != 'null')
          MotorNotificaciones.cancelarMisil(nId).catchError((_) {});
      }
      for (final campo in ['fn_notif_fase2', 'fn_notif_fase3', 'fn_notif_fase4', 'fn_notif_fase4b']) {
        final nId = servicio[campo]?.toString();
        if (nId != null && nId.isNotEmpty && nId != 'null')
          MotorNotificaciones.cancelarMisil(nId).catchError((_) {});
      }
      await Supabase.instance.client
          .from('servicios')
          .update({
            'estado': 'finalizado',
            'onesignal_30s': null,
            'onesignal_2m': null,
            'onesignal_5m': null,
            'fn_notif_fase2': null,
            'fn_notif_fase3': null,
            'fn_notif_fase4': null,
            'fn_notif_fase4b': null,
            'paradero_auto_movil_id': null,
            'fn_fase2_movil_id': null,
          })
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
      // Cancelar cascada SE + FN pendiente
      for (final campo in ['onesignal_30s', 'onesignal_2m', 'onesignal_5m']) {
        final nId = servicio[campo]?.toString();
        if (nId != null && nId.isNotEmpty && nId != 'null')
          MotorNotificaciones.cancelarMisil(nId).catchError((_) {});
      }
      for (final campo in ['fn_notif_fase2', 'fn_notif_fase3', 'fn_notif_fase4', 'fn_notif_fase4b']) {
        final nId = servicio[campo]?.toString();
        if (nId != null && nId.isNotEmpty && nId != 'null')
          MotorNotificaciones.cancelarMisil(nId).catchError((_) {});
      }
      await Supabase.instance.client
          .from('servicios')
          .update({
            'estado': 'finalizado_con_problema',
            'onesignal_30s': null,
            'onesignal_2m': null,
            'onesignal_5m': null,
            'fn_notif_fase2': null,
            'fn_notif_fase3': null,
            'fn_notif_fase4': null,
            'fn_notif_fase4b': null,
            'paradero_auto_movil_id': null,
            'fn_fase2_movil_id': null,
          })
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
                          activeThumbColor: const Color(0xFFB8860B),
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
      {VoidCallback? onTap, bool active = false}) {
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        // Cuando está activo, fondo sólido; si no, solo tinte suave
        color: active ? color : color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: active ? color : color.withValues(alpha: 0.4),
          width: active ? 1.5 : 1,
        ),
      ),
      child: RichText(
        text: TextSpan(children: [
          TextSpan(
            text: '$count ',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: active ? Colors.white : color,
                height: 1),
          ),
          TextSpan(
            text: label,
            style: TextStyle(
                fontSize: 8,
                color: active ? Colors.white : color,
                height: 1),
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
          orElse: () => <String, dynamic>{});
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
      'fn_renegociando': 'RENEG.',
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

    // Clave de colapso: primera palabra del título en minúsculas
    final collapseKey = titulo.split(' ').first.toLowerCase();
    final colapsado = _categoriasColapsadas.contains(collapseKey);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => setState(() {
            if (colapsado) {
              _categoriasColapsadas.remove(collapseKey);
            } else {
              _categoriasColapsadas.add(collapseKey);
            }
          }),
          child: Container(
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
                const SizedBox(width: 6),
                Icon(
                  colapsado ? Icons.expand_more : Icons.expand_less,
                  size: 16,
                  color: colorBase,
                ),
              ],
            ),
          ),
        ),
        if (!colapsado) ...lista.map((servicio) {
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
            if ((elapsed - extension) >= 60) alertaRetraso = true;
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
            // FN: fondo azul claro + borde azul (sin importar la sección:
            // radar disponibles, en curso, etc.) — sobreescribe amber/verde.
            if (servicio['tipo_fn'] == true) {
              tileBackground = const Color(0xffe8f4fd); // azul muy claro
              tileBorder = Colors.blue[700]!;
            }
          }

          bool alarmaCentral =
              servicio['chat_movil_central'] == true ||
              servicio['chat_cliente_central'] == true;

          return Stack(
            clipBehavior: Clip.none,
            children: [
            FadeSlideIn(
            key: ValueKey('monitor_${servicio['id']}'),
            child: Card(
              margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              elevation: alarmaCentral ? 4 : 0,
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
                side: BorderSide(
                  color: alarmaCentral ? Colors.red[700]! : tileBorder,
                  width: alarmaCentral ? 3.0 : 1.2,
                ),
              ),
              color: alarmaCentral
                  ? Colors.red.withValues(alpha: 0.06)
                  : tileBackground,
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
                            Container(
                              margin: const EdgeInsets.only(left: 5),
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.red[700],
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.chat_bubble_rounded, color: Colors.white, size: 10),
                                  SizedBox(width: 3),
                                  Text('MSG', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                          const SizedBox(width: 4),
                          Icon(icono, color: colorBase, size: 14),
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
                            // Etiqueta de plan del móvil asignado
                            Builder(builder: (_) {
                              final plan = movCacheEntry['tipo_plan']?.toString();
                              if (plan == null) return const SizedBox.shrink();
                              final color = plan == 'prediario' ? Colors.orange[700]! : Colors.green[700]!;
                              final label = plan == 'prediario' ? 'PREDIA' : 'SUSCR';
                              return Container(
                                margin: const EdgeInsets.only(left: 4),
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
                                child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 7, fontWeight: FontWeight.bold)),
                              );
                            }),
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
                              efectivos >= 60
                                  ? '⏳ Retrasado en entrega: ${efectivos}min'
                                  : '🛵 En entrega: ${efectivos}min',
                              style: TextStyle(
                                color: efectivos >= 60
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
                          servicio['tipo_fn'] == true ||
                          (servicio['creador'] != null &&
                              servicio['creador'] != 'Central') ||
                          (estado == 'programado' &&
                              servicio['liberacion_at'] != null) ||
                          servicio['observacion'] != null ||
                          servicio['paradero_origen'] != null ||
                          servicio['tipo_servicio'] == 'RECOGIDA LOCAL' ||
                          servicio['transferencia_a_movil_id'] != null ||
                          servicio['transferido'] == true ||
                          servicio['transferencia_rechazada'] == true) ...[
                        const SizedBox(height: 3),
                        Wrap(
                          spacing: 4,
                          runSpacing: 2,
                          children: [
                            // Badge FN — visible en todas las secciones
                            if (servicio['tipo_fn'] == true)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 5, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.blue[700],
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: const Text(
                                  '🔵 FN',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 8,
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
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
                            if (servicio['paradero_origen'] != null)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.blue[800],
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: Text(
                                  '📍 ${servicio["paradero_origen"].toString().toUpperCase()}',
                                  style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
                                ),
                              ),
                            if (servicio['tipo_servicio'] == 'RECOGIDA LOCAL')
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.deepOrange[700],
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: const Text(
                                  '🏪 RECOGIDA LOCAL',
                                  style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
                                ),
                              ),
                            // Transferencia pendiente — esperando aceptación
                            if (servicio['transferencia_a_movil_id'] != null)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.teal[700],
                                  borderRadius: BorderRadius.circular(3),
                                  border: Border.all(color: Colors.teal[300]!, width: 0.6),
                                ),
                                child: const Text(
                                  '⏳ TRANSFIRIENDO...',
                                  style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
                                ),
                              ),
                            // Servicio ya transferido — queda como soporte/auditoría
                            if (servicio['transferido'] == true)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.deepPurple[600],
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: const Text(
                                  '🔄 TRANSFERIDO',
                                  style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
                                ),
                              ),
                            // Transferencia rechazada — auditoría
                            if (servicio['transferencia_rechazada'] == true)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.red[800],
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: const Text(
                                  '❌ TRANSF. RECHAZADA',
                                  style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
                                ),
                              ),
                          ],
                        ),
                      ],

                      // ── FILA 👁: notificados por fase (FN radar · pendiente) ──
                      if (servicio['tipo_fn'] == true &&
                          servicio['fn_asignacion_tipo'] == 'radar' &&
                          estado == 'pendiente' &&
                          servicio['movil_id'] == null) ...[
                        const SizedBox(height: 3),
                        Builder(builder: (_) {
                          String numeros(dynamic ids) {
                            if (ids == null) return '';
                            final list = (ids as List<dynamic>);
                            if (list.isEmpty) return '';
                            return list.map((id) {
                              final entry = _movilesCache.firstWhere(
                                (m) => m['id'].toString() == id.toString(),
                                orElse: () => <String, dynamic>{},
                              );
                              final u = entry['usuario']?.toString() ?? '';
                              final n = RegExp(r'\d+').firstMatch(u)?.group(0) ?? '?';
                              return '#$n';
                            }).join(' ');
                          }

                          final f1 = numeros(servicio['fn_notificados_fase1']);
                          final f2Raw = servicio['fn_fase2_movil_id']?.toString();
                          String f2 = '';
                          if (f2Raw != null) {
                            final entry = _movilesCache.firstWhere(
                              (m) => m['id'].toString() == f2Raw,
                              orElse: () => <String, dynamic>{},
                            );
                            final u = entry['usuario']?.toString() ?? '';
                            final n = RegExp(r'\d+').firstMatch(u)?.group(0) ?? '?';
                            f2 = '#$n';
                          }
                          final f3 = numeros(servicio['fn_notificados_fase3']);
                          final f4List = (servicio['fn_notificados_fase4'] as List<dynamic>?) ?? [];
                          final f4 = f4List.isEmpty ? '' : (f4List.length > 5
                              ? '${numeros(f4List.take(4).toList())} +${f4List.length - 4}'
                              : numeros(f4List));

                          final partes = <String>[
                            if (f1.isNotEmpty) 'F1: $f1',
                            if (f2.isNotEmpty) 'F2→ $f2',
                            if (f3.isNotEmpty) 'F3: $f3',
                            if (f4.isNotEmpty) 'F4: $f4',
                          ];
                          if (partes.isEmpty) return const SizedBox.shrink();

                          return Text(
                            '👁 ${partes.join('  ·  ')}',
                            style: TextStyle(fontSize: 8, color: Colors.indigo[400]),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 2,
                          );
                        }),
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
                            child: seleccionado
                                ? Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        if (btns.isNotEmpty)
                                          Wrap(
                                            spacing: 5,
                                            runSpacing: 5,
                                            children: btns,
                                          ),
                                        const SizedBox(height: 6),
                                        SizedBox(
                                          width: double.infinity,
                                          child: OutlinedButton.icon(
                                            onPressed: () => _abrirMenuGestion(context, servicio),
                                            icon: const Icon(Icons.open_in_new, size: 14),
                                            label: const Text(
                                              'MÁS DETALLES',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                                letterSpacing: 0.5,
                                              ),
                                            ),
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor: Colors.black87,
                                              side: const BorderSide(color: Colors.black38),
                                              padding: const EdgeInsets.symmetric(vertical: 6),
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(5),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
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
          ),  // FadeSlideIn
          // ── Badge flotante de MENSAJE cuando el móvil/cliente escribió ──
          if (alarmaCentral)
            Positioned(
              top: -2, right: 14,
              child: GestureDetector(
                onTap: () {
                  final svcId = servicio['id'] as int;
                  if (servicio['chat_movil_central'] == true) {
                    Supabase.instance.client.from('servicios')
                        .update({'chat_movil_central': false}).eq('id', svcId);
                    Navigator.push(context, MaterialPageRoute(
                      builder: (_) => ChatScreen(
                        salaId: 'soporte_movil_$svcId',
                        miId: 0,
                        miNombre: 'Central',
                        titulo: 'Chat con Móvil',
                        servicioId: svcId,
                        alarmaLocal: 'chat_movil_central',
                        alarmaDestino: 'chat_central_movil',
                        destinatarioId: (servicio['movil_id'] as num?)?.toInt(),
                        tipoFaq: TipoFaqChat.central,
                      ),
                    ));
                  } else {
                    Supabase.instance.client.from('servicios')
                        .update({'chat_cliente_central': false}).eq('id', svcId);
                    Navigator.push(context, MaterialPageRoute(
                      builder: (_) => ChatScreen(
                        salaId: 'soporte_cliente_$svcId',
                        miId: 0,
                        miNombre: 'Central',
                        titulo: 'Chat con Cliente',
                        servicioId: svcId,
                        alarmaLocal: 'chat_cliente_central',
                        alarmaDestino: 'chat_central_cliente',
                        destinatarioId: (servicio['cliente_id'] as num?)?.toInt(),
                        tipoFaq: TipoFaqChat.central,
                      ),
                    ));
                  }
                },
                child: PulsingPanicoButton(
                  color: Colors.red,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.red[800],
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.red.withValues(alpha: 0.5),
                          blurRadius: 8,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.mark_email_unread_rounded,
                            color: Colors.white, size: 13),
                        SizedBox(width: 5),
                        Text(
                          '💬 MENSAJE',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],  // Stack.children
        );  // Stack
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

  // ── HELPERS PARA _abrirMenuGestion (BottomSheet moderno) ─────────────────

  Widget _badgeDark(String texto, Color bg, Color fg) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(5)),
    child: Text(texto, style: TextStyle(color: fg, fontSize: 9, fontWeight: FontWeight.bold)),
  );

  Widget _seccion({
    required IconData icon,
    required Color color,
    required String titulo,
    required Widget child,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 5),
        Text(titulo, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
      ]),
      const SizedBox(height: 8),
      child,
    ],
  );

  Widget _infoBadge(String label, String value, Color bg, Color fg) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white38, fontSize: 9)),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(color: fg, fontWeight: FontWeight.bold, fontSize: 12)),
      ],
    ),
  );

  Widget _notaBadge(String icono, String texto, Color bg, Color fg) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(icono, style: const TextStyle(fontSize: 13)),
      const SizedBox(width: 8),
      Expanded(child: Text(texto, style: TextStyle(color: fg, fontSize: 12, height: 1.4))),
    ]),
  );

  Widget _contactRow({
    required IconData icono,
    required String nombre,
    required Color colorIcono,
    required String wsLabel,
    required Color wsColor,
    required VoidCallback onWs,
    required String chatLabel,
    required Color chatColor,
    required IconData chatIcon,
    required VoidCallback onChat,
  }) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: const Color(0xFF0D1B2E),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      children: [
        Icon(icono, color: colorIcono, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(nombre,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
            overflow: TextOverflow.ellipsis)),
        const SizedBox(width: 8),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: wsColor,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onPressed: onWs,
          icon: const Icon(Icons.wechat, size: 12, color: Colors.white),
          label: Text(wsLabel, style: const TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(width: 6),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: chatColor,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onPressed: onChat,
          icon: Icon(chatIcon, size: 12, color: Colors.white),
          label: Text(chatLabel, style: const TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.bold)),
        ),
      ],
    ),
  );

  Widget _accionBtn(String label, Color bg, Color fg, VoidCallback onTap) => ElevatedButton(
    style: ElevatedButton.styleFrom(
      backgroundColor: bg,
      foregroundColor: fg,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      minimumSize: Size.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
    onPressed: onTap,
    child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: fg)),
  );

  Widget _accionBtnIcon(IconData icon, String label, Color bg, Color fg, VoidCallback onTap) => ElevatedButton.icon(
    style: ElevatedButton.styleFrom(
      backgroundColor: bg,
      foregroundColor: fg,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      minimumSize: Size.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
    onPressed: onTap,
    icon: Icon(icon, size: 13, color: fg),
    label: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: fg)),
  );

}
