// ignore_for_file: curly_braces_in_flow_control_structures, no_leading_underscores_for_local_identifiers, use_build_context_synchronously, unused_element
part of 'local_screen.dart';

// ══════════════════════════════════════════════════════════════════════════════
// _DispatchMixin — notificaciones, aprobar cotizaciones, radar
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
    String? sonido,
    String? canalAndroidId,
  }) => MotorNotificaciones.dispararRafa(
        idsDestinos: externalIds,
        titulo: titulo,
        mensaje: mensaje,
        urgente: true,
        sonido: sonido ?? 'alerta',
        canalAndroidId: canalAndroidId,
      );

  // (El flujo VIP del local — avisos VIP, espera de 3/5 min y paso a estándar —
  //  se eliminó: la opción VIP ya no existe.)

  // ── SOLICITUD DIRECTA AL RADAR (Temporal) ────────────────────────────────────
  // Crea un servicio RECOGIDA LOCAL sin destino, datos del cliente ni precio y
  // dispara la cascada SE completa (4 fases). Se elimina cuando el sistema
  // tenga el flujo adaptado definitivamente.
  Future<void> _solicitarMovilDirecto(BuildContext ctx) async {
    final confirmar = await showDialog<bool>(
      context: ctx,
      barrierDismissible: true,
      builder: (d) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Row(children: [
          Icon(Icons.motorcycle, color: Colors.black, size: 22),
          SizedBox(width: 8),
          Text('SOLICITAR MÓVIL', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        ]),
        content: Text(
          '¿Enviar solicitud al radar para ${widget.usuario['nombre']}?\n\nSin dirección ni precio — recogida directa en el local.',
          style: const TextStyle(fontSize: 13),
        ),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: const Text('CANCELAR', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.black),
            onPressed: () => Navigator.pop(d, true),
            child: const Text('SOLICITAR',
                style: TextStyle(color: Color(0xff3AF500), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;

    try {
      final double? oLat = (widget.usuario['lat_fija'] as num?)?.toDouble();
      final double? oLng = (widget.usuario['lng_fija'] as num?)?.toDouble();
      final String localNombre = widget.usuario['nombre']?.toString() ?? 'Local';

      // 1. Insertar servicio RECOGIDA LOCAL (sin tarifa, sin destino)
      final insertedSvc = await Supabase.instance.client
          .from('servicios')
          .insert({
            'local_id': widget.usuario['id'],
            'tipo_servicio': 'RECOGIDA LOCAL',
            'origen': localNombre,
            'estado': 'pendiente',
            'tarifa': 0,
            'creador': localNombre,
            'observacion': '[ RECOGIDA LOCAL ] - Solicitud directa desde el local',
            if (oLat != null) 'origen_lat': oLat,
            if (oLng != null) 'origen_lng': oLng,
          })
          .select('id')
          .single();
      final int svcId = (insertedSvc['id'] as num).toInt();

      // 2. F2 la hace el SERVIDOR (se_f2_huecos): a T+30s ofrece al #1 del
      //    paradero objetivo o, si está vacío, al móvil más cercano (con todos
      //    los filtros de fase, rango, billetera y suspensión) y le manda el
      //    push solo si el servicio sigue pendiente. Aquí solo se indica el
      //    paradero objetivo del local.
      final String? paraderoObjetivo =
          await _paraderoObjetivoDeLocal(widget.usuario, oLat, oLng);
      if (paraderoObjetivo != null) {
        await Supabase.instance.client
            .from('servicios')
            .update({'paradero_origen': paraderoObjetivo})
            .eq('id', svcId);
      }

      // Fase 1 (T=0): Masters → la manda el servidor (se_f1_motivo).
      // Fase 2 (T+30s): la hace el servidor (se_f2_huecos).

      // F3/F4 — pg_cron consulta en_linea en tiempo real
      await Supabase.instance.client.from('servicios').update({
        'se_cascade_t0': DateTime.now().toUtc().toIso8601String(),
        'se_f3_enviado': false,
        'se_f4_enviado': false,
        'se_f1_motivo': 'nuevo',
      }).eq('id', svcId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('✅ Solicitud enviada al radar. Masters avisados.'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error al solicitar móvil: $e'),
          backgroundColor: Colors.red,
        ));
      }
    }
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
    final movilUsuario = movilLabel(moto).toUpperCase();
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
      await _dispararMisilInmediato(
        externalIds: [movilId],
        titulo: TextosPush.asignadoTitulo,
        mensaje: TextosPush.asignadoMensaje(
          widget.usuario['nombre']?.toString() ?? 'El local',
          TextosPush.ruta(servicio['origen']?.toString(),
              servicio['destino']?.toString()),
        ),
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

      // F2 la hace el SERVIDOR (se_f2_huecos): #1 del paradero objetivo o, si
      // está vacío, el móvil más cercano, con todos los filtros, y solo si el
      // servicio sigue pendiente a T+30s. Aquí solo se indica el paradero objetivo.
      // Programados: los libera el servidor a su hora (se_liberar_programados)
      // y arranca la cascada completa en ese momento.
      String? paraderoObjetivo;
      if (!esPuntoAPunto) {
        paraderoObjetivo = await _paraderoObjetivoDeLocal(
          widget.usuario,
          (servicio['origen_lat'] as num?)?.toDouble(),
          (servicio['origen_lng'] as num?)?.toDouble(),
        );
      }

      await Supabase.instance.client
          .from('servicios')
          .update({
            'estado': nuevoEstado,
            if (paraderoObjetivo != null) 'paradero_origen': paraderoObjetivo,
            // La cotización pudo crearse hace rato: el reloj de fases (tarjetas
            // y servidor) arranca AHORA. Los programados conservan su hora.
            if (retardoProgramado == 0)
              'liberacion_at': DateTime.now().toUtc().toIso8601String(),
            // F1 (T=0) a Masters lo manda el SERVIDOR, solo si el servicio ya
            // está en el radar. Un programado lo avisa el servidor al liberarlo.
            if (retardoProgramado == 0) 'se_f1_motivo': 'nuevo',
          })
          .eq('id', nuevoServicioId);

      // F3/F4 — pg_cron (edge functions). Programados: los arranca el servidor al liberar.
      if (!esPuntoAPunto && retardoProgramado == 0) {
        await Supabase.instance.client.from('servicios').update({
          'se_cascade_t0': DateTime.now().toUtc().toIso8601String(),
          'se_f3_enviado': false,
          'se_f4_enviado': false,
        }).eq('id', nuevoServicioId);
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
            .from('red_dir_se')
            .select('nombre, precio')
            .eq('usuario_id', widget.usuario['id'])
            .eq('activo', true);

        String destinoMayus = destinoNuevo.toUpperCase();
        String barrioExtraido = destinoMayus.contains('-')
            ? destinoMayus.split('-')[0].trim()
            : destinoMayus;
        final tarifaCobrada = (servicio['tarifa'] as num).toDouble();

        bool yaEstaGuardado = resLista.any((item) {
          final nom = (item['nombre'] ?? '').toString().toUpperCase();
          return barrioExtraido == nom || destinoMayus.startsWith(nom);
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
                              final munNorm = zonaSeleccionada == 'CÚCUTA'
                                  ? 'Cúcuta'
                                  : zonaSeleccionada == 'LOS PATIOS'
                                      ? 'Los Patios'
                                      : 'V. Rosario';
                              await Supabase.instance.client
                                  .from('red_dir_se')
                                  .insert({
                                    'usuario_id': widget.usuario['id'],
                                    'nombre': barrioCtrl.text.trim().toUpperCase(),
                                    'municipio': munNorm,
                                    'sector_id': sectorId,
                                    'precio': tarifaCobrada.toInt(),
                                  });
                              if (ctxSave.mounted) {
                                Navigator.pop(ctxSave);
                                ScaffoldMessenger.of(contextoPrincipal).showSnackBar(
                                  const SnackBar(
                                    content: Text('✅ Dirección guardada en tu Red de Direcciones.'),
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

// ── Paradero objetivo del local para la F2 SE ─────────────────────────────────
// La F2 la resuelve el servidor (se_f2_huecos) usando servicios.paradero_origen:
// #1 de ese paradero o, si está vacío, el móvil más cercano al origen.
// Regla del local: su primer paradero exclusivo; si no tiene, el paradero
// activo más cercano a (lat, lng). Devuelve el nombre en MAYÚSCULAS o null.
Future<String?> _paraderoObjetivoDeLocal(
  Map<String, dynamic> usuarioLocal,
  double? lat,
  double? lng,
) async {
  final String raw = usuarioLocal['paradero_exclusivo']?.toString() ?? '';
  final List<String> exclusivos = raw
      .split(',')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();
  if (exclusivos.isNotEmpty) return exclusivos.first.toUpperCase();
  if (lat == null || lng == null) return null;
  try {
    final paraderos = await Supabase.instance.client
        .from('paraderos')
        .select('nombre, latitud, longitud')
        .eq('activo', true)
        // Solo paraderos de día: de noche el servidor usa NOCTURNO para todos
        .or('es_nocturno.is.null,es_nocturno.eq.false');
    String? mejor;
    double menor = double.infinity;
    for (final p in paraderos) {
      final pLat = (p['latitud'] as num?)?.toDouble();
      final pLng = (p['longitud'] as num?)?.toDouble();
      if (pLat == null || pLng == null) continue;
      final d = const Distance().as(
        LengthUnit.Meter,
        LatLng(lat, lng),
        LatLng(pLat, pLng),
      );
      if (d < menor) {
        menor = d;
        mejor = p['nombre'].toString().trim().toUpperCase();
      }
    }
    return mejor;
  } catch (_) {
    return null;
  }
}
