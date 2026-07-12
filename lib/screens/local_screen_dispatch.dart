// ignore_for_file: curly_braces_in_flow_control_structures, no_leading_underscores_for_local_identifiers, use_build_context_synchronously, unused_element
part of 'local_screen.dart';

// ══════════════════════════════════════════════════════════════════════════════
// _DispatchMixin — notificaciones, VIP fallback, aprobar cotizaciones, radar
// ══════════════════════════════════════════════════════════════════════════════
mixin _DispatchMixin on State<LocalScreen> {
  // ── Abstract stubs (implementados en otros mixins) ─────────────────────────
  Future<int> _buscarOCrearSector(String nombre, String municipio);

  // ── Cañones OneSignal ──────────────────────────────────────────────────────
  Future<String?> _programarMisilRetardado({
    required List<String> externalIds,
    required String titulo,
    required String mensaje,
    int minutosRetardo = 0,
    int segundosRetardo = 0,
  }) => MotorNotificaciones.programarMisilRetardado(
        externalIds: externalIds,
        titulo: titulo,
        mensaje: mensaje,
        minutosRetardo: minutosRetardo,
        segundosRetardo: segundosRetardo,
      );

  Future<void> _dispararMisilInmediato({
    required List<String> externalIds,
    required String titulo,
    required String mensaje,
  }) => MotorNotificaciones.dispararRafa(
        idsDestinos: externalIds,
        titulo: titulo,
        mensaje: mensaje,
        urgente: true,
      );

  // ─── VIP: verificación periódica + diálogo de fallback ───────────────────
  //
  // Flujo:
  //   Envío VIP → notifica Masters (0s) + Leyenda #1 (30s)
  //               → espera 3 min → _verificarFallbackVip()
  //   _verificarFallbackVip:
  //     • Si el servicio ya fue tomado → no hace nada
  //     • Si hay nuevos VIP disponibles → les notifica + reinicia timer 3 min
  //     • Si no hay nadie → llama _mostrarDialogoFallbackVip()
  //   _mostrarDialogoFallbackVip:
  //     ESPERAR  → espera 5 min → vuelve a _verificarFallbackVip()
  //     ESTÁNDAR → resta $3.000, enruta como servicio normal

  Future<void> _verificarFallbackVip({
    required int servicioId,
    required String destino,
    required List<String> pilotosParadero,
    required bool esPuntoAPunto,
    required Map<String, dynamic>? coords,
    required double tarifaConVip,
  }) async {
    if (!mounted) return;
    try {
      final check = await Supabase.instance.client
          .from('servicios')
          .select('estado, es_vip, movil_id')
          .eq('id', servicioId)
          .single();
      // Ya fue tomado o degradado — nada que hacer
      if (check['estado'] != 'pendiente' ||
          check['es_vip'] != true ||
          check['movil_id'] != null) return;
    } catch (_) {
      return;
    }
    if (!mounted) return;

    // ¿Hay nuevos VIP disponibles ahora?
    final masters = await Supabase.instance.client
        .from('usuarios')
        .select('id')
        .eq('rol', 'movil')
        .eq('en_linea', true)
        .inFilter('rango_movil', ['MASTER']);
    final leyendas = await Supabase.instance.client
        .from('usuarios')
        .select('id, ingreso_fila')
        .eq('rol', 'movil')
        .eq('en_linea', true)
        .eq('rango_movil', 'LEYENDA')
        .not('paradero_actual', 'is', null)
        .order('ingreso_fila', ascending: true);

    final List<String> masterIds =
        masters.map((u) => u['id'].toString()).toList();
    final List<String> leyendaIds =
        leyendas.isNotEmpty ? [leyendas.first['id'].toString()] : [];

    if (masterIds.isNotEmpty || leyendaIds.isNotEmpty) {
      // Nuevos VIP conectados → notificar y reiniciar timer 3 min
      const String msg = 'Hay un servicio VIP esperando — revisa el radar';
      if (masterIds.isNotEmpty) {
        await _dispararMisilInmediato(
          externalIds: masterIds,
          titulo: '👑 SERVICIO VIP',
          mensaje: msg,
        );
      }
      if (leyendaIds.isNotEmpty) {
        // Misil server-side T+30s para Leyenda VIP — sobrevive en segundo plano
        final id30sVipV = await _programarMisilRetardado(
          externalIds: leyendaIds,
          titulo: '👑 SERVICIO VIP',
          mensaje: msg,
          segundosRetardo: 30,
        );
        if (id30sVipV != null) {
          await Supabase.instance.client
              .from('servicios')
              .update({'onesignal_30s': id30sVipV})
              .eq('id', servicioId);
        }
      }
      Future.delayed(const Duration(minutes: 3), () {
        _verificarFallbackVip(
          servicioId: servicioId,
          destino: destino,
          pilotosParadero: pilotosParadero,
          esPuntoAPunto: esPuntoAPunto,
          coords: coords,
          tarifaConVip: tarifaConVip,
        );
      });
    } else {
      // Aún sin VIP → mostrar diálogo al local
      if (mounted) {
        _mostrarDialogoFallbackVip(
          servicioId: servicioId,
          destino: destino,
          pilotosParadero: pilotosParadero,
          esPuntoAPunto: esPuntoAPunto,
          coords: coords,
          tarifaConVip: tarifaConVip,
        );
      }
    }
  }

  Future<void> _mostrarDialogoFallbackVip({
    required int servicioId,
    required String destino,
    required List<String> pilotosParadero,
    required bool esPuntoAPunto,
    required Map<String, dynamic>? coords,
    required double tarifaConVip,
  }) async {
    if (!mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctxVip) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [Color(0xFFB8860B), Color(0xFFFFD700), Color(0xFFB8860B)],
          ).createShader(bounds),
          child: Text(
            '👑 SIN MÓVILES VIP',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
          ),
        ),
        content: const Text(
          'Parece que no hay móviles capacitados disponibles para tu servicio VIP en este momento.\n\n¿Deseas esperar a que haya uno disponible, o prefieres pedirlo como servicio estándar?',
          style: TextStyle(fontSize: 14),
        ),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actions: [
          // ESPERAR: re-verifica en 5 minutos
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFB8860B),
              side: const BorderSide(color: Color(0xFFFFD700)),
            ),
            onPressed: () {
              Navigator.pop(ctxVip);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    '⏳ VIP en espera. Te avisamos en 5 min si hay un Leyenda o Master disponible.',
                  ),
                  backgroundColor: Color(0xFF7A5500),
                  duration: Duration(seconds: 5),
                ),
              );
              Future.delayed(const Duration(minutes: 5), () {
                _verificarFallbackVip(
                  servicioId: servicioId,
                  destino: destino,
                  pilotosParadero: pilotosParadero,
                  esPuntoAPunto: esPuntoAPunto,
                  coords: coords,
                  tarifaConVip: tarifaConVip,
                );
              });
            },
            icon: const Icon(Icons.hourglass_top, size: 16),
            label: const Text('ESPERAR'),
          ),
          // SERVICIO ESTÁNDAR: restar $3.000 y enrutar normal
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xff3AF500),
              foregroundColor: Colors.black,
            ),
            onPressed: () async {
              Navigator.pop(ctxVip);
              final double tarifaEstandar =
                  (tarifaConVip - 3000).clamp(0.0, double.infinity);
              await Supabase.instance.client
                  .from('servicios')
                  .update({
                    'es_vip': false,
                    'tarifa': tarifaEstandar,
                    'tarifa_detalle': {
                      'total': tarifaEstandar,
                      'fuente': 'local_quitar_vip',
                    },
                  })
                  .eq('id', servicioId);

              const String msgStd = 'Nuevo servicio disponible — revisa el radar';
              final mastersStd = await Supabase.instance.client
                  .from('usuarios')
                  .select('id')
                  .or('rol.eq.central,rol.eq.master,rango_movil.eq.MASTER')
                  .neq('suspendido', true);
              final List<String> masterStdIds =
                  mastersStd.map((u) => u['id'].toString()).toList();

              if (masterStdIds.isNotEmpty) {
                await _dispararMisilInmediato(
                  externalIds: masterStdIds,
                  titulo: '👑 NUEVO SERVICIO',
                  mensaje: msgStd,
                );
              }

              // T=+30s: paradero — misil server-side
              if (pilotosParadero.isNotEmpty) {
                final List<String> targetStd = pilotosParadero
                    .where((id) => !masterStdIds.contains(id))
                    .toList();
                if (targetStd.isNotEmpty) {
                  final id30sStd = await _programarMisilRetardado(
                    externalIds: targetStd,
                    titulo: 'TU TURNO DE PARADERO',
                    mensaje: msgStd,
                    segundosRetardo: 30,
                  );
                  if (id30sStd != null) {
                    await Supabase.instance.client
                        .from('servicios')
                        .update({'onesignal_30s': id30sStd})
                        .eq('id', servicioId);
                  }
                }
              }
              // T=+60s y T=+90s — misiles server-side (pre-fetch al despachar)
              {
                final double? _oLat = (coords?['lat'] as num?)?.toDouble();
                final double? _oLng = (coords?['lng'] as num?)?.toDouble();
                final movilesStd = await Supabase.instance.client
                    .from('usuarios').select('id, latitud, longitud')
                    .eq('rol', 'movil').eq('en_linea', true).neq('suspendido', true)
                    .not('rango_movil', 'in', '("MASTER")');
                final idsZonaStd = movilesStd.where((u) {
                  final id = u['id'].toString();
                  if (masterStdIds.contains(id) || pilotosParadero.contains(id)) return false;
                  if (_oLat == null || _oLng == null) return true;
                  final uLat = (u['latitud'] as num?)?.toDouble();
                  final uLng = (u['longitud'] as num?)?.toDouble();
                  if (uLat == null || uLng == null) return false;
                  return const Distance().as(
                        LengthUnit.Meter, LatLng(uLat, uLng), LatLng(_oLat, _oLng),
                      ) <= 1000;
                }).map((u) => u['id'].toString()).toList();
                final idsTodosStd = movilesStd
                    .map((u) => u['id'].toString())
                    .where((id) => !masterStdIds.contains(id))
                    .toList();
                String? id60sStd;
                String? id90sStd;
                if (idsZonaStd.isNotEmpty)
                  id60sStd = await _programarMisilRetardado(
                    externalIds: idsZonaStd,
                    titulo: '📡 SERVICIO CERCA (1km)',
                    mensaje: msgStd,
                    segundosRetardo: 60,
                  );
                if (idsTodosStd.isNotEmpty)
                  id90sStd = await _programarMisilRetardado(
                    externalIds: idsTodosStd,
                    titulo: '🚨 SERVICIO SIN TOMAR',
                    mensaje: msgStd,
                    segundosRetardo: 90,
                  );
                if (id60sStd != null || id90sStd != null) {
                  await Supabase.instance.client.from('servicios').update({
                    if (id60sStd != null) 'onesignal_2m': id60sStd,
                    if (id90sStd != null) 'onesignal_5m': id90sStd,
                  }).eq('id', servicioId);
                }
              }

              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('✅ Pedido enviado como servicio estándar.'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
            icon: const Icon(Icons.motorcycle, size: 16),
            label: const Text('SERVICIO ESTÁNDAR'),
          ),
        ],
      ),
    );
  }

  // --- MÓDULO: COMPLETAR DATOS AL APROBAR COTIZACIÓN (MULTI-PARADERO + TEMPORIZADOR) ---
  void _completarDatosYAprobar(
    BuildContext contextoPrincipal,
    Map<String, dynamic> servicio,
  ) {
    final telefonoCtrl = TextEditingController(
      text: servicio['telefono_receptor']?.toString() ?? '',
    );
    final ticketCtrl = TextEditingController(
      text: servicio['ticket_factura']?.toString() ?? '',
    );
    final notasCtrl = TextEditingController();
    bool procesando = false;

    showDialog(
      context: contextoPrincipal,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          title: const Text(
            '📝 APROBAR COTIZACIÓN',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cotización aprobada por: ${fmtPeso(servicio['tarifa'])}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Completa los datos finales para enviarlo al radar:',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
                const SizedBox(height: 16),

                TextField(
                  controller: ticketCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Ticket / Factura # (Opcional)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.receipt_long, size: 18),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),

                TextField(
                  controller: telefonoCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'WhatsApp de Contacto (*)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.phone, size: 18),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),

                TextField(
                  controller: notasCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Notas finales de entrega / Pedido',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.notes, size: 18),
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: procesando ? null : () => Navigator.pop(context),
              child: const Text(
                'CANCELAR',
                style: TextStyle(color: Colors.red),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.black),
              onPressed: procesando
                  ? null
                  : () async {
                      if (telefonoCtrl.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('El WhatsApp es obligatorio.'),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }

                      setDialogState(() => procesando = true);

                      String obsAnterior = servicio['observacion'] ?? '';
                      String ticketStr = ticketCtrl.text.trim().isNotEmpty
                          ? '[ TICKET: #${ticketCtrl.text.trim()} ] '
                          : '';
                      String notasNuevas = notasCtrl.text.trim().isNotEmpty
                          ? '\n📝 NOTAS EXTRA: ${notasCtrl.text.trim()}'
                          : '';
                      String nuevaObs = '$ticketStr$obsAnterior$notasNuevas';

                      try {
                        // Solo guardamos los datos y marcamos como aprobada.
                        // El scan de paraderos y las notificaciones se hacen
                        // cuando el local pulse "SOLICITAR MÓVIL".
                        await Supabase.instance.client
                            .from('servicios')
                            .update({
                              'estado': 'cotizacion_aprobada',
                              'observacion': nuevaObs,
                              'telefono_receptor': telefonoCtrl.text.trim(),
                              'ticket_factura': ticketCtrl.text.trim().isEmpty
                                  ? null
                                  : ticketCtrl.text.trim(),
                            })
                            .eq('id', servicio['id']);

                        if (context.mounted) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(contextoPrincipal).showSnackBar(
                            const SnackBar(
                              content: Text(
                                '✅ Cotización aprobada. Pulsa "SOLICITAR MÓVIL" cuando el pedido esté listo.',
                              ),
                              backgroundColor: Colors.teal,
                              duration: Duration(seconds: 4),
                            ),
                          );
                        }
                      } catch (e) {
                        setDialogState(() => procesando = false);
                        if (context.mounted)
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Error: $e'),
                              backgroundColor: Colors.red,
                            ),
                          );
                      }
                    },
              child: procesando
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xff3AF500),
                      ),
                    )
                  : const Text(
                      'APROBAR',
                      style: TextStyle(
                        color: Color(0xff3AF500),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // --- MÓDULO: SOLICITAR MÓVIL DESPUÉS DE APROBAR COTIZACIÓN ---
  Future<void> _solicitarMovilAprobado(
    BuildContext contextoPrincipal,
    Map<String, dynamic> servicio,
  ) async {
    // Busca móviles que ya tienen servicios ACTIVOS de este local.
    // Si hay alguno, ofrece ENRUTAR directamente antes de ir al radar.
    List<Map<String, dynamic>> movilesActivos = [];
    try {
      final serviciosActivos = await Supabase.instance.client
          .from('servicios')
          .select('movil_id')
          .eq('local_id', widget.usuario['id'])
          .inFilter('estado', ['en_ruta_origen', 'en_origen', 'en_ruta_destino'])
          .not('movil_id', 'is', null);

      final Set<String> movilIds = serviciosActivos
          .map((s) => s['movil_id'].toString())
          .toSet();

      if (movilIds.isNotEmpty) {
        final perfiles = await Supabase.instance.client
            .from('usuarios')
            .select('id, usuario, nombre, rango_movil')
            .inFilter('id', movilIds.toList());
        movilesActivos = List<Map<String, dynamic>>.from(perfiles);
      }
    } catch (_) {}

    if (!contextoPrincipal.mounted) return;

    showDialog(
      context: contextoPrincipal,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text(
          '🏍️ SOLICITAR MÓVIL',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.teal),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Orden #${servicio['id']} → ${servicio['destino']} · ${fmtPeso(servicio['tarifa'])}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            // Si hay móviles activos, muestra opciones de ENRUTAR primero
            if (movilesActivos.isNotEmpty) ...[
              const Divider(),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  'Ya tienes móvil(es) en camino. ¿Enrutar con uno de ellos?',
                  style: TextStyle(fontSize: 12, color: Colors.blue[700]),
                ),
              ),
              ...movilesActivos.map((moto) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.blue[700],
                      side: BorderSide(color: Colors.blue[300]!),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    onPressed: () async {
                      Navigator.pop(ctx);
                      // Envía el servicio DIRECTAMENTE al móvil seleccionado
                      // (no al radar general) — como exclusivo_id para que
                      // solo él lo vea, con notificación inmediata solo a él.
                      await _enviarAprobadaAlMovilExclusivo(
                        contextoPrincipal, servicio, moto);
                    },
                    icon: const Icon(Icons.alt_route, size: 16),
                    label: Text(
                      'ENRUTAR a ${(moto['usuario'] ?? moto['nombre'] ?? '').toString().toUpperCase()}',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              )),
              const Divider(),
            ],
            const Text(
              '¿El pedido ya está listo para enviarlo al radar?',
              style: TextStyle(fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('AÚN NO', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal[700]),
            onPressed: () async {
              Navigator.pop(ctx);
              await _enviarAprobadaAlRadar(contextoPrincipal, servicio);
            },
            child: Text(
              'ENVIAR AL RADAR',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  // --- MÓDULO: ENRUTAR COTIZACIÓN APROBADA DIRECTAMENTE A UN MÓVIL ---
  // Envía el servicio cotizacion_aprobada directamente a un móvil específico
  // como exclusivo_id, sin pasar por el radar general. Solo ese móvil
  // recibe la notificación inmediata.
  Future<void> _enviarAprobadaAlMovilExclusivo(
    BuildContext contextoPrincipal,
    Map<String, dynamic> servicio,
    Map<String, dynamic> moto,
  ) async {
    final movilUsuario = (moto['usuario'] ?? moto['nombre'] ?? '').toString().toUpperCase();
    final String movilId = moto['id'].toString();

    try {
      await Supabase.instance.client
          .from('servicios')
          .update({
            'estado': 'pendiente',
            'exclusivo_id': movilId,
          })
          .eq('id', servicio['id']);

      // Notificación inmediata solo al móvil elegido
      const String mensajeNotif = 'Tienes un servicio asignado directamente';
      await _dispararMisilInmediato(
        externalIds: [movilId],
        titulo: '🔗 SERVICIO ENRUTADO A TI',
        mensaje: mensajeNotif,
      );

      if (contextoPrincipal.mounted) {
        ScaffoldMessenger.of(contextoPrincipal).showSnackBar(
          SnackBar(
            content: Text('✅ Orden #${servicio['id']} enviada directamente a $movilUsuario.'),
            backgroundColor: Colors.blue[700],
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (contextoPrincipal.mounted) {
        ScaffoldMessenger.of(contextoPrincipal).showSnackBar(
          SnackBar(
            content: Text('Error al enrutar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _enviarAprobadaAlRadar(
    BuildContext contextoPrincipal,
    Map<String, dynamic> servicio,
  ) async {
    try {
      int retardoProgramado = 0;
      if (servicio['liberacion_at'] != null) {
        final lib = DateTime.parse(servicio['liberacion_at']).toLocal();
        final ahora = DateTime.now();
        if (lib.isAfter(ahora)) {
          retardoProgramado = lib.difference(ahora).inMinutes;
        }
      }

      String destinoNuevo = servicio['destino'] ?? '';
      bool esPuntoAPunto = servicio['es_punto_a_punto'] == true;
      int nuevoServicioId = servicio['id'];
      String nuevoEstado = retardoProgramado > 0 ? 'programado' : 'pendiente';

      String? exclusivoIdCampo;
      List<String> pilotosSeleccionadosIds = [];

      if (!esPuntoAPunto) {
        final serviciosPendientes = await Supabase.instance.client
            .from('servicios')
            .select('exclusivo_id')
            .eq('estado', 'pendiente')
            .not('exclusivo_id', 'is', null);
        List<String> ocupados = [];
        for (var s in serviciosPendientes) {
          ocupados.addAll(
            s['exclusivo_id'].toString().split(',').map((e) => e.trim()),
          );
        }

        final movilesLibres = await Supabase.instance.client
            .from('usuarios')
            .select('id, paradero_actual, ingreso_fila')
            .eq('rol', 'movil')
            .eq('en_linea', true)
            .not('paradero_actual', 'is', null);

        Map<String, List<Map<String, dynamic>>> gruposParaderos = {};
        for (var m in movilesLibres) {
          String pName = m['paradero_actual'].toString().trim().toLowerCase();
          gruposParaderos.putIfAbsent(pName, () => []).add(m);
        }

        Map<String, String> numeroUnosPorParadero = {};
        gruposParaderos.forEach((pName, listaFila) {
          listaFila.sort(
            (a, b) => DateTime.parse(
              a['ingreso_fila'] ?? DateTime.now().toIso8601String(),
            ).compareTo(
              DateTime.parse(b['ingreso_fila'] ?? DateTime.now().toIso8601String()),
            ),
          );
          for (var candidato in listaFila) {
            String candId = candidato['id'].toString();
            if (!ocupados.contains(candId)) {
              numeroUnosPorParadero[pName] = candId;
              break;
            }
          }
        });

        String paraderosLocalRaw =
            widget.usuario['paradero_exclusivo']?.toString() ?? '';
        List<String> paraderosDelLocal = paraderosLocalRaw
            .split(',')
            .map((e) => e.trim().toLowerCase())
            .where((e) => e.isNotEmpty)
            .toList();

        if (paraderosDelLocal.isEmpty) {
          numeroUnosPorParadero.forEach((pName, driverId) {
            pilotosSeleccionadosIds.add(driverId);
          });
        } else {
          for (var pLocal in paraderosDelLocal) {
            if (numeroUnosPorParadero.containsKey(pLocal)) {
              pilotosSeleccionadosIds.add(numeroUnosPorParadero[pLocal]!);
            }
          }
        }

        if (pilotosSeleccionadosIds.isNotEmpty) {
          exclusivoIdCampo = pilotosSeleccionadosIds.join(',');
        }
      }

      await Supabase.instance.client
          .from('servicios')
          .update({
            'estado': nuevoEstado,
            'exclusivo_id': exclusivoIdCampo,
          })
          .eq('id', nuevoServicioId);

      String mensajeAlarma =
          '📍 ${widget.usuario['nombre']} solicitó un móvil para $destinoNuevo.';
      final mastersData = await Supabase.instance.client
          .from('usuarios')
          .select('id')
          .or('rol.eq.master,rango_movil.eq.MASTER')
          .neq('suspendido', true);
      List<String> masterIds =
          mastersData.map((u) => u['id'].toString()).toList();

      if (masterIds.isNotEmpty) {
        await _dispararMisilInmediato(
          externalIds: masterIds,
          titulo: retardoProgramado > 0 ? '👑 SERVICIO PROGRAMADO' : '👑 NUEVO SERVICIO',
          mensaje: mensajeAlarma,
        );
      }

      if (pilotosSeleccionadosIds.isNotEmpty) {
        List<String> targetPilotos =
            pilotosSeleccionadosIds.where((id) => !masterIds.contains(id)).toList();
        if (targetPilotos.isNotEmpty) {
          // Paradero: misil retardado con ID guardado — cancela si alguien acepta antes
          String? id30s;
          if (retardoProgramado > 0) {
            id30s = await _programarMisilRetardado(
              externalIds: targetPilotos,
              titulo: 'TU TURNO DE PARADERO',
              mensaje: mensajeAlarma,
              minutosRetardo: retardoProgramado,
            );
          } else {
            id30s = await _programarMisilRetardado(
              externalIds: targetPilotos,
              titulo: 'TU TURNO DE PARADERO',
              mensaje: mensajeAlarma,
              segundosRetardo: 30,
            );
          }
          if (id30s != null) {
            await Supabase.instance.client
                .from('servicios')
                .update({'onesignal_30s': id30s})
                .eq('id', nuevoServicioId);
          }
        }
      }

      // T=+60s (zonal 1km) y T=+90s (todos) — nuevas olas del embudo de 2 min
      if (!esPuntoAPunto) {
        final int _svcId3 = nuevoServicioId;
        final String _msg3 = mensajeAlarma;
        final List<String> _mSnap3 = List<String>.from(masterIds);
        final List<String> _pSnap3 = List<String>.from(pilotosSeleccionadosIds);

        if (retardoProgramado > 0) {
          // Misiles programados para servicios con retardo
          List<String> zona1kmIds = [];
          List<String> todosIds = [];
          final movilesActivos = await Supabase.instance.client
              .from('usuarios').select('id, latitud, longitud')
              .eq('rol', 'movil').eq('en_linea', true);
          for (var m in movilesActivos) {
            final idStr = m['id'].toString();
            todosIds.add(idStr);
            double dist = 999999;
            if (m['latitud'] != null && m['longitud'] != null &&
                servicio['origen_lat'] != null && servicio['origen_lng'] != null) {
              dist = const Distance().as(
                LengthUnit.Meter,
                LatLng((m['latitud'] as num).toDouble(), (m['longitud'] as num).toDouble()),
                LatLng((servicio['origen_lat'] as num).toDouble(), (servicio['origen_lng'] as num).toDouble()),
              );
            }
            if (dist <= 1000) zona1kmIds.add(idStr);
          }
          String? id1m;
          String? id2m;
          if (zona1kmIds.isNotEmpty)
            id1m = await _programarMisilRetardado(
              externalIds: zona1kmIds,
              titulo: '📡 SERVICIO CERCA',
              mensaje: 'Servicio a menos de 1km — revisa el radar.',
              minutosRetardo: retardoProgramado + 1,
            );
          if (todosIds.isNotEmpty)
            id2m = await _programarMisilRetardado(
              externalIds: todosIds,
              titulo: '🚨 SERVICIO SIN TOMAR',
              mensaje: '¡Revisa el Radar!',
              minutosRetardo: retardoProgramado + 2,
            );
          if (id1m != null || id2m != null) {
            await Supabase.instance.client.from('servicios').update({
              if (id1m != null) 'onesignal_2m': id1m,
              if (id2m != null) 'onesignal_5m': id2m,
            }).eq('id', _svcId3);
          }
        } else {
          // Servicio inmediato: T=+60s y T=+90s — misiles server-side
          // Pre-fetch al momento de aprobación; se cancelan si alguien acepta
          final double? _oLat3 = (servicio['origen_lat'] as num?)?.toDouble();
          final double? _oLng3 = (servicio['origen_lng'] as num?)?.toDouble();
          final movilesInm3 = await Supabase.instance.client
              .from('usuarios').select('id, latitud, longitud')
              .eq('rol', 'movil').eq('en_linea', true).neq('suspendido', true)
              .not('rango_movil', 'in', '("MASTER")');
          final idsZona3 = movilesInm3.where((u) {
            final id = u['id'].toString();
            if (_mSnap3.contains(id) || _pSnap3.contains(id)) return false;
            if (_oLat3 == null || _oLng3 == null) return true;
            final uLat = (u['latitud'] as num?)?.toDouble();
            final uLng = (u['longitud'] as num?)?.toDouble();
            if (uLat == null || uLng == null) return false;
            return const Distance().as(
                  LengthUnit.Meter,
                  LatLng(uLat, uLng),
                  LatLng(_oLat3, _oLng3),
                ) <= 1000;
          }).map((u) => u['id'].toString()).toList();
          final idsTodos3 = movilesInm3
              .map((u) => u['id'].toString())
              .where((id) => !_mSnap3.contains(id))
              .toList();
          String? id60s3;
          String? id90s3;
          if (idsZona3.isNotEmpty)
            id60s3 = await _programarMisilRetardado(
              externalIds: idsZona3,
              titulo: '📡 SERVICIO CERCA (1km)',
              mensaje: _msg3,
              segundosRetardo: 60,
            );
          if (idsTodos3.isNotEmpty)
            id90s3 = await _programarMisilRetardado(
              externalIds: idsTodos3,
              titulo: '🚨 SERVICIO SIN TOMAR',
              mensaje: _msg3,
              segundosRetardo: 90,
            );
          if (id60s3 != null || id90s3 != null) {
            await Supabase.instance.client.from('servicios').update({
              if (id60s3 != null) 'onesignal_2m': id60s3,
              if (id90s3 != null) 'onesignal_5m': id90s3,
            }).eq('id', _svcId3);
          }
        }
      }

      if (contextoPrincipal.mounted) {
        ScaffoldMessenger.of(contextoPrincipal).showSnackBar(
          const SnackBar(
            content: Text('✅ Móvil solicitado con éxito. Orden en el radar.'),
            backgroundColor: Colors.green,
          ),
        );
      }

      // --- DIÁLOGO RÁPIDO PARA GUARDAR EN LA LISTA DE PRECIOS ---
      if (contextoPrincipal.mounted) {
        final resLista = await Supabase.instance.client
            .from('tarifas_locales')
            .select('sector_id, sectores(nombre, municipio), tarifa')
            .eq('local_id', widget.usuario['id']);

        String destinoMayus = destinoNuevo.toUpperCase();
        String barrioExtraido = destinoMayus.contains('-')
            ? destinoMayus.split('-')[0].trim()
            : destinoMayus;
        final tarifaCobrada = (servicio['tarifa'] as num).toDouble();

        bool yaEstaGuardado = resLista.any((item) {
          final s = item['sectores'] as Map<String, dynamic>?;
          if (s == null) return false;
          final clave = '${s['nombre']} (${s['municipio']})'.toUpperCase();
          return barrioExtraido == clave ||
              (destinoMayus.startsWith(clave) &&
                  (item['tarifa'] as num).toDouble() == tarifaCobrada);
        });

        if (!yaEstaGuardado) {
          final barrioCtrl = TextEditingController(text: barrioExtraido);
          String zonaSeleccionada = 'CÚCUTA';
          bool guardandoLista = false;

          showDialog(
            context: contextoPrincipal,
            builder: (ctxSave) => StatefulBuilder(
              builder: (ctxSave, setSaveState) => AlertDialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                title: const Text(
                  '💾 GUARDAR EN LISTA',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Se cobró ${fmtPeso(servicio['tarifa'])}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: barrioCtrl,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        labelText: 'Barrio / Lugar (Ej: PRADOS)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '¿A qué municipio pertenece?',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    Wrap(
                      spacing: 6,
                      runSpacing: 0,
                      children: ['CÚCUTA', 'LOS PATIOS', 'V. ROSARIO']
                          .map((z) => ChoiceChip(
                                label: Text(
                                  z,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                selected: zonaSeleccionada == z,
                                selectedColor: Colors.blue[100],
                                onSelected: (bool selected) {
                                  if (selected)
                                    setSaveState(() => zonaSeleccionada = z);
                                },
                              ))
                          .toList(),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctxSave),
                    child: const Text('NO GUARDAR', style: TextStyle(color: Colors.grey)),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.black),
                    onPressed: guardandoLista
                        ? null
                        : () async {
                            if (barrioCtrl.text.trim().isEmpty) return;
                            setSaveState(() => guardandoLista = true);
                            try {
                              final sectorId = await _buscarOCrearSector(
                                barrioCtrl.text.trim().toUpperCase(),
                                zonaSeleccionada,
                              );
                              await Supabase.instance.client
                                  .from('tarifas_locales')
                                  .upsert(
                                    {
                                      'local_id': widget.usuario['id'],
                                      'local_nombre': widget.usuario['nombre'],
                                      'sector_id': sectorId,
                                      'tarifa': tarifaCobrada,
                                    },
                                    onConflict: 'local_id, sector_id',
                                  );
                              if (ctxSave.mounted) {
                                Navigator.pop(ctxSave);
                                ScaffoldMessenger.of(contextoPrincipal).showSnackBar(
                                  const SnackBar(
                                    content: Text('✅ Dirección guardada en tu Tarifario.'),
                                    backgroundColor: Colors.green,
                                  ),
                                );
                              }
                            } catch (e) {
                              setSaveState(() => guardandoLista = false);
                              if (ctxSave.mounted)
                                ScaffoldMessenger.of(contextoPrincipal).showSnackBar(
                                  SnackBar(
                                    content: Text('Error BD: $e'),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                            }
                          },
                    child: guardandoLista
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              color: Color(0xff3AF500),
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            'GUARDAR DIRECCIÓN',
                            style: TextStyle(
                              color: Color(0xff3AF500),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ],
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (contextoPrincipal.mounted)
        ScaffoldMessenger.of(contextoPrincipal).showSnackBar(
          SnackBar(
            content: Text('Error al solicitar móvil: $e'),
            backgroundColor: Colors.red,
          ),
        );
    }
  }
}
