// ignore_for_file: curly_braces_in_flow_control_structures, no_leading_underscores_for_local_identifiers, use_build_context_synchronously, unused_element, unused_element_parameter
part of 'local_screen.dart';

// ══════════════════════════════════════════════════════════════════════════════
// _CardsMixin — tarjetas de servicio, controles operativos y helpers de hub
// ══════════════════════════════════════════════════════════════════════════════
mixin _CardsMixin on State<LocalScreen> {
  // ── Campos propios ─────────────────────────────────────────────────────────
  final Set<int> _tarjetasColapsadasLocal = {};
  final Set<int> _tarjetasExpandidasLocal = {};
  final ValueNotifier<int> _expansionTick = ValueNotifier(0);
  final Set<int> _liberandoEnProceso = {};

  @override
  void dispose() {
    _expansionTick.dispose();
    super.dispose();
  }

  // ── Abstract stubs (implementados en otros mixins) ─────────────────────────
  Future<String?> _programarMisilRetardado({
    required List<String> externalIds,
    required String titulo,
    required String mensaje,
    int minutosRetardo = 0,
    int segundosRetardo = 0,
  });
  Future<void> _dispararMisilInmediato({
    required List<String> externalIds,
    required String titulo,
    required String mensaje,
  });
  void _completarDatosYAprobar(BuildContext ctx, Map<String, dynamic> svc);
  Future<void> _solicitarMovilAprobado(BuildContext ctx, Map<String, dynamic> svc);

  // ── CONTROLES OPERATIVOS ───────────────────────────────────────────────────
  Future<void> _cancelarPedido(int id) async {
    try {
      // 1. Cambiamos el estado en Supabase primero (Garantiza que la orden se cancele sí o sí)
      final res = await Supabase.instance.client
          .from('servicios')
          .update({'estado': 'cancelado'})
          .eq('id', id)
          .select('onesignal_2m, onesignal_5m')
          .maybeSingle();

      // 2. Intentamos bajar las notificaciones programadas de forma silenciosa
      if (res != null) {
        // Mismo App ID que MotorNotificaciones (207d1d0a) — donde se programaron
        const String appId = '207d1d0a-0218-46e0-9f35-7d8d88f6765a';
        const String restApiKey =
            'os_v2_app_eb6r2cqcdbdobhzvpwgyr5twlinl2pbrrxzeyrmltx2iwaupqy7uibm7gyzzc6ne4shl7lcmas2mobfum347m5ljvzlahf5pkj2yuvi';

        // Motor táctico interno para no repetir código y silenciar errores
        Future<void> anularMisil(dynamic onesignalId) async {
          if (onesignalId == null) return;
          String mId = onesignalId.toString().trim();

          // El candado que te faltaba: Si está vacío o dice "null", aborta el disparo
          if (mId.isEmpty || mId == 'null') return;

          try {
            await http.delete(
              Uri.parse(
                'https://onesignal.com/api/v1/notifications/$mId?app_id=$appId',
              ),
              headers: {'Authorization': 'Basic $restApiKey'},
            );
          } catch (e) {
            // Si OneSignal falla (por Web/CORS o red), lo silenciamos. La orden ya está cancelada.
            debugPrint('Falla ignorada en OneSignal: $e');
          }
        }

        // Disparamos la anulación sin que afecte la interfaz del local
        await anularMisil(res['onesignal_2m']);
        await anularMisil(res['onesignal_5m']);
      }

      // Notificar a la Central que el pedido fue cancelado por el local
      MotorNotificaciones.dispararACentral(
        titulo: '❌ PEDIDO CANCELADO',
        mensaje: '${widget.usuario['nombre']} canceló el pedido #$id.',
        urgente: false,
        sonido: 'central_cancelado',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cancelar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // --- MOTOR DE CALIFICACIÓN 5.0 ---
  void _mostrarDialogoCalificacion(Map<String, dynamic> servicio) {
    int estrellas = 5;
    final comentarioController = TextEditingController();
    bool procesando = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          title: const Text(
            'CALIFICAR MÓVIL',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '¿Cómo estuvo el servicio de este móvil?',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (index) {
                  return IconButton(
                    icon: Icon(
                      index < estrellas ? Icons.star : Icons.star_border,
                      color: Colors.amber,
                      size: 32,
                    ),
                    onPressed: () =>
                        setDialogState(() => estrellas = index + 1),
                  );
                }),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: comentarioController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Comentario (Opcional)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: procesando ? null : () => Navigator.pop(context),
              child: const Text(
                'CANCELAR',
                style: TextStyle(color: Colors.grey),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.black),
              onPressed: procesando
                  ? null
                  : () async {
                      setDialogState(() => procesando = true);
                      try {
                        final servicioId = servicio['id'];
                        final movilId = servicio['movil_id'];
                        final comentarioFinal =
                            comentarioController.text.trim().isEmpty
                            ? null
                            : comentarioController.text.trim();

                        // 1. Sellamos la nota del local en servicios
                        await Supabase.instance.client
                            .from('servicios')
                            .update({
                              'calificacion_local': estrellas,
                              'comentario_local': comentarioFinal,
                            })
                            .eq('id', servicioId);

                        // 2. INSERT en calificaciones (fuente de verdad
                        //    para el perfil del móvil y Central).
                        await Supabase.instance.client
                            .from('calificaciones')
                            .upsert({
                              'servicio_id': servicioId,
                              'movil_id': movilId.toString(),
                              'calificador_tipo': 'local',
                              'calificador_id':
                                  widget.usuario['id'].toString(),
                              'calificador_nombre':
                                  widget.usuario['nombre'].toString(),
                              'estrellas': estrellas,
                              'comentario': comentarioFinal,
                            }, onConflict: 'servicio_id, calificador_tipo');

                        // 3. Recalculamos la puntuación del móvil — ahora
                        // vive en una sola función SQL (recalcular_
                        // puntuacion_movil) en vez de repetir esta lógica
                        // en Dart. Evita que Local y Cliente diverjan al
                        // calcular el mismo promedio cada uno por su lado.
                        await Supabase.instance.client.rpc(
                          'recalcular_puntuacion_movil',
                          params: {'p_movil_id': movilId},
                        );

                        if (context.mounted) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Calificación enviada. ¡Gracias!'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      } catch (e) {
                        setDialogState(() => procesando = false);
                        if (context.mounted) {
                          ScaffoldMessenger.of(
                            context,
                          ).showSnackBar(SnackBar(content: Text('Error: $e')));
                        }
                      }
                    },
              child: procesando
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        color: Colors.amber,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text(
                      'ENVIAR NOTA',
                      style: TextStyle(
                        color: Colors.amber,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _construirTarjetaServicio(
    Map<String, dynamic> servicio, {
    bool esHistorial = false,
    bool esGlobal = false,
    VoidCallback? onOcultar,
    VoidCallback? onEliminar,
    VoidCallback? extraRebuild,
  }) {
    final int svcId = servicio['id'] as int;
    // Activos: expandidos por defecto (colapsar los agrega al set)
    // Historial: colapsados por defecto (expandir los agrega al set)
    final bool estaExpandida = esHistorial
        ? _tarjetasExpandidasLocal.contains(svcId)
        : !_tarjetasColapsadasLocal.contains(svcId);
    void toggleExpansion() {
      if (esHistorial) {
        if (_tarjetasExpandidasLocal.contains(svcId)) {
          _tarjetasExpandidasLocal.remove(svcId);
        } else {
          _tarjetasExpandidasLocal.add(svcId);
        }
      } else {
        if (_tarjetasColapsadasLocal.contains(svcId)) {
          _tarjetasColapsadasLocal.remove(svcId);
        } else {
          _tarjetasColapsadasLocal.add(svcId);
        }
      }
      _expansionTick.value++; // rebuild solo la lista, no toda la pantalla
      extraRebuild?.call();
    }
    final estado = servicio['estado'];

    late Color bordeColor;
    late Color fondoColor;
    late String textoEstado;
    late IconData iconoEstado;

    // --- NUEVO SISTEMA DE ESTADOS VISUALES ---
    if (estado == 'programado') {
      bordeColor = Colors.blue[700]!;
      fondoColor = Colors.blue[50]!;
      textoEstado = 'PROGRAMADO';
      iconoEstado = Icons.schedule;

      if (servicio['liberacion_at'] != null) {
        final lib = DateTime.parse(servicio['liberacion_at']).toLocal();
        final ahora = DateTime.now();
        final diff = lib.difference(ahora).inMinutes;

        if (diff > 0) {
          textoEstado = 'PROGRAMADO (EN $diff MIN)';
        } else {
          textoEstado = 'LIBERANDO AL RADAR...';

          // ---> GATILLO AUTOMÁTICO: Libera el servicio + reinicia cascada con pilotos actuales <---
          // Guard: se ejecuta una sola vez aunque el widget se reconstruya varias veces
          if (!_liberandoEnProceso.contains(svcId)) {
            _liberandoEnProceso.add(svcId);
            Future.microtask(() async {
              try {
                final db = Supabase.instance.client;

                // 1. Cancelar misiles viejos del snapshot de creación
                final svcOld = await db.from('servicios')
                    .select('onesignal_30s, onesignal_2m, onesignal_5m')
                    .eq('id', svcId).maybeSingle();
                if (svcOld != null) {
                  if (svcOld['onesignal_30s'] != null)
                    await MotorNotificaciones.cancelarMisil(svcOld['onesignal_30s'].toString());
                  if (svcOld['onesignal_2m'] != null)
                    await MotorNotificaciones.cancelarMisil(svcOld['onesignal_2m'].toString());
                  if (svcOld['onesignal_5m'] != null)
                    await MotorNotificaciones.cancelarMisil(svcOld['onesignal_5m'].toString());
                }

                // 2. Liberar al radar
                await db.from('servicios').update({'estado': 'pendiente'}).eq('id', svcId);

                // 3. Cascada fresca con pilotos disponibles AHORA
                final localNombre = widget.usuario['nombre']?.toString() ?? 'Un local';
                final destino = servicio['destino']?.toString() ?? 'destino';
                final msgAlarma = '📍 $localNombre solicitó un móvil para $destino.';

                // T=0: Masters
                final mastersData = await db.from('usuarios').select('id')
                    .or('rol.eq.central,rol.eq.master,rango_movil.eq.MASTER')
                    .neq('suspendido', true);
                final masterIds = mastersData.map((u) => u['id'].toString()).toList();
                if (masterIds.isNotEmpty) {
                  await _dispararMisilInmediato(
                    externalIds: masterIds,
                    titulo: '👑 SERVICIO ACTIVO',
                    mensaje: msgAlarma,
                  );
                }

                // T+30s: Paradero #1 actual del local
                final movilesLibres = await db.from('usuarios')
                    .select('id, paradero_actual, ingreso_fila')
                    .eq('rol', 'movil').eq('en_linea', true).neq('suspendido', true)
                    .not('paradero_actual', 'is', null);
                final Map<String, List<Map<String, dynamic>>> grupos = {};
                for (var m in movilesLibres) {
                  final p = m['paradero_actual'].toString().trim().toLowerCase();
                  grupos.putIfAbsent(p, () => []).add(m);
                }
                final Map<String, String> numero1s = {};
                grupos.forEach((p, fila) {
                  fila.sort((a, b) =>
                      DateTime.parse(a['ingreso_fila'] ?? DateTime.now().toIso8601String())
                          .compareTo(DateTime.parse(b['ingreso_fila'] ?? DateTime.now().toIso8601String())));
                  for (var c in fila) {
                    final cId = c['id'].toString();
                    if (!masterIds.contains(cId)) { numero1s[p] = cId; break; }
                  }
                });
                final paraderosRaw = widget.usuario['paradero_exclusivo']?.toString() ?? '';
                final paraderosLocal = paraderosRaw
                    .split(',').map((e) => e.trim().toLowerCase()).where((e) => e.isNotEmpty).toList();
                List<String> pilotosParadero = paraderosLocal.isEmpty
                    ? numero1s.values.toList()
                    : paraderosLocal.where((p) => numero1s.containsKey(p)).map((p) => numero1s[p]!).toList();

                String? id30s;
                if (pilotosParadero.isNotEmpty) {
                  id30s = await _programarMisilRetardado(
                    externalIds: pilotosParadero,
                    titulo: 'TU TURNO DE PARADERO',
                    mensaje: msgAlarma,
                    segundosRetardo: 30,
                  );
                }

                // T+60s: zona 1km  |  T+90s: todos
                final oLat = (servicio['origen_lat'] as num?)?.toDouble();
                final oLng = (servicio['origen_lng'] as num?)?.toDouble();
                final movilesStd = await db.from('usuarios').select('id, latitud, longitud')
                    .eq('rol', 'movil').eq('en_linea', true).neq('suspendido', true)
                    .not('rango_movil', 'in', '("MASTER")');
                final idsZona = movilesStd.where((u) {
                  final id = u['id'].toString();
                  if (masterIds.contains(id) || pilotosParadero.contains(id)) return false;
                  if (oLat == null || oLng == null) return true;
                  final uLat = (u['latitud'] as num?)?.toDouble();
                  final uLng = (u['longitud'] as num?)?.toDouble();
                  if (uLat == null || uLng == null) return false;
                  return const Distance().as(LengthUnit.Meter, LatLng(uLat, uLng), LatLng(oLat, oLng)) <= 1000;
                }).map((u) => u['id'].toString()).toList();
                final idsTodos = movilesStd
                    .map((u) => u['id'].toString())
                    .where((id) => !masterIds.contains(id) && !pilotosParadero.contains(id))
                    .toList();
                String? id60s;
                String? id90s;
                if (idsZona.isNotEmpty) {
                  id60s = await _programarMisilRetardado(
                    externalIds: idsZona, titulo: '📡 SERVICIO CERCA (1km)',
                    mensaje: msgAlarma, segundosRetardo: 60,
                  );
                }
                if (idsTodos.isNotEmpty) {
                  id90s = await _programarMisilRetardado(
                    externalIds: idsTodos, titulo: '🚨 SERVICIO SIN TOMAR',
                    mensaje: msgAlarma, segundosRetardo: 90,
                  );
                }

                // 4. Guardar IDs de nuevos misiles
                await db.from('servicios').update({
                  'onesignal_30s': id30s,
                  'onesignal_2m': id60s,
                  'onesignal_5m': id90s,
                }).eq('id', svcId);

              } catch (_) {}
              _liberandoEnProceso.remove(svcId);
            });
          }
        }
      }
    } else if (estado == 'pendiente') {
      bordeColor = Colors.black54;
      fondoColor = Colors.grey[100]!;
      textoEstado = 'BUSCANDO MÓVIL...';
      iconoEstado = Icons.radar;
    } else if (estado == 'en_origen') {
      bordeColor = Colors.orange[800]!;
      fondoColor = Colors.orange[50]!;
      textoEstado = 'MÓVIL ESPERANDO EN EL LOCAL';
      iconoEstado = Icons.storefront;
    } else if (estado == 'en_curso' ||
        estado == 'en_ruta_origen' ||
        estado == 'en_ruta_destino') {
      bordeColor = const Color(0xff3AF500);
      fondoColor = const Color(0xfff0fff0);

      if (estado == 'en_ruta_origen') {
        textoEstado = 'MÓVIL EN CAMINO AL LOCAL';
      } else if (estado == 'en_ruta_destino') {
        textoEstado = 'EN RUTA DE ENTREGA';
      } else {
        textoEstado = 'MÓVIL ASIGNADO';
      }
      iconoEstado = Icons.motorcycle;
    } else if (estado == 'problema') {
      bordeColor = Colors.red;
      fondoColor = const Color(0xfffff0f0);
      textoEstado = 'NOVEDAD REPORTADA';
      iconoEstado = Icons.warning_amber_rounded;
    } else if (estado == 'caducado') {
      bordeColor = Colors.purple;
      fondoColor = const Color(0xfff8f0ff);
      textoEstado = 'NADIE TOMÓ EL SERVICIO';
      iconoEstado = Icons.hourglass_disabled;
    } else if (estado == 'cotizacion') {
      bordeColor = Colors.orange[700]!;
      fondoColor = Colors.orange[50]!;
      textoEstado = 'ESPERANDO PRECIO...';
      iconoEstado = Icons.access_time_filled;
    } else if (estado == 'cotizada') {
      bordeColor = Colors.blue[700]!;
      fondoColor = Colors.blue[50]!;
      textoEstado = 'COTIZACIÓN RECIBIDA';
      iconoEstado = Icons.monetization_on;
    } else if (estado == 'cotizacion_aprobada') {
      bordeColor = Colors.teal[700]!;
      fondoColor = Colors.teal[50]!;
      textoEstado = 'APROBADA · EN ESPERA';
      iconoEstado = Icons.check_circle_outline;
    } else if (estado == 'finalizado') {
      bordeColor = Colors.green;
      fondoColor = Colors.white;
      textoEstado = 'COMPLETADO';
      iconoEstado = Icons.check_circle;
    } else if (estado == 'cancelado') {
      bordeColor = Colors.grey;
      fondoColor = const Color(0xfff9f9f9);
      textoEstado = 'CANCELADO';
      iconoEstado = Icons.block;
    } else if (estado == 'finalizado_por_demora' ||
        estado == 'finalizado_con_problema') {
      bordeColor = Colors.orange[800]!;
      fondoColor = Colors.orange[50]!;
      textoEstado = 'CERRADO CON NOVEDAD';
      iconoEstado = Icons.report_problem;
    } else {
      bordeColor = Colors.grey;
      fondoColor = Colors.white;
      textoEstado = 'ESTADO DESCONOCIDO';
      iconoEstado = Icons.help_outline;
    }

    String? ticketPOS = servicio['ticket_factura']?.toString();
    String? telCliente = servicio['telefono_receptor']?.toString();

    return AnimatedSize(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeInOut,
      alignment: Alignment.topCenter,
      child: Card(
      elevation: esHistorial ? 1 : 3,
      margin: const EdgeInsets.only(bottom: 12),
      color: fondoColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: bordeColor, width: esHistorial ? 1.0 : 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── HEADER SIEMPRE VISIBLE ──────────────────────────────────
          InkWell(
            onTap: toggleExpansion,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  // Badge de estado (anima con AnimatedSwitcher cuando cambia)
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 280),
                    child: Row(
                      key: ValueKey('estado_$svcId$textoEstado'),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(iconoEstado, color: bordeColor, size: 18),
                        const SizedBox(width: 6),
                        Text(
                          textoEstado,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: bordeColor,
                            fontSize: 12,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Destino truncado (solo si está colapsado)
                  if (!estaExpandida) ...[
                    const Text('·', style: TextStyle(color: Colors.black38)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        servicio['destino']?.toString() ?? '',
                        style: const TextStyle(fontSize: 12, color: Colors.black54),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ] else
                    const Spacer(),
                  Text(
                    '#${servicio['numero_local'] ?? servicio['id']}',
                    style: const TextStyle(color: Colors.black38, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    estaExpandida ? Icons.expand_less : Icons.expand_more,
                    color: Colors.black38,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
          // ── CUERPO EXPANDIBLE ───────────────────────────────────────
          if (estaExpandida) Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            const Divider(height: 16),

            if (ticketPOS != null && ticketPOS.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '🧾 Factura / Ticket: #$ticketPOS',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.blueAccent,
                  ),
                ),
              ),

            Text(
              '🏁 Destino: ${servicio['destino']}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),

            if (servicio['movil_id'] != null)
              FutureBuilder<List<Map<String, dynamic>>>(
                future: Supabase.instance.client
                    .from('usuarios')
                    .select(
                      'id, nombre, usuario, rol, telefono, foto_perfil_url, '
                      'pago_nequi, pago_daviplata, pago_bancolombia',
                    )
                    .eq('id', servicio['movil_id']),
                builder: (context, snapshot) {
                  final data =
                      (snapshot.data != null && snapshot.data!.isNotEmpty)
                      ? snapshot.data!.first
                      : null;

                  String nombreFinal = 'Desconocido';
                  // FIX: 'telMovil' es el NÚMERO DE OPERACIÓN del moto
                  // (ej: "12", sacado de "movil12") — solo sirve para
                  // mostrar/identificar, NUNCA para WhatsApp. El número
                  // real de WhatsApp vive en 'telefonoReal', el campo
                  // 'telefono' de verdad. Antes el botón de WhatsApp
                  // usaba telMovil por error — apuntaba a un número que
                  // no existe (wa.me/5712 en vez del teléfono real).
                  String telMovil = '';
                  String telefonoReal = '';
                  String numeroAvatar = '?';
                  final String? fotoUrl = data?['foto_perfil_url']?.toString();
                  final bool tieneFoto = fotoUrl != null && fotoUrl.isNotEmpty;

                  if (data != null) {
                    final rol = data['rol']?.toString() ?? 'movil';
                    final usr = data['usuario']?.toString() ?? '';
                    telMovil = usr.replaceAll(RegExp(r'[^0-9]'), '');
                    telefonoReal = data['telefono']?.toString() ?? '';
                    numeroAvatar = telMovil.isNotEmpty ? telMovil : '?';

                    if (rol == 'movil') {
                      nombreFinal = telMovil.isNotEmpty
                          ? 'Móvil $telMovil'
                          : (data['nombre']?.toString().toUpperCase() ??
                                'Móvil');
                    } else {
                      nombreFinal = data['nombre']?.toString() ?? 'Móvil';
                    }
                  }

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // --- INFO OBLIGATORIA: nombre, número, foto, pago ---
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 18,
                              backgroundColor: Colors.black87,
                              backgroundImage:
                                  tieneFoto ? NetworkImage(fotoUrl) : null,
                              child: !tieneFoto
                                  ? Text(
                                      numeroAvatar,
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    )
                                  : null,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    nombreFinal,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black87,
                                      fontSize: 13,
                                    ),
                                  ),
                                  if (data != null &&
                                      data['nombre'] != null &&
                                      data['rol'] == 'movil')
                                    Text(
                                      data['nombre'].toString().toUpperCase(),
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.grey[500],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (data != null &&
                            ((data['pago_nequi']?.toString().isNotEmpty ?? false) ||
                                (data['pago_daviplata']?.toString().isNotEmpty ?? false) ||
                                (data['pago_bancolombia']?.toString().isNotEmpty ?? false)))
                          Padding(
                            padding: const EdgeInsets.only(top: 6, left: 46),
                            child: Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                if (data['pago_nequi']?.toString().isNotEmpty ?? false)
                                  _chipPagoLocal('Nequi', const Color(0xFFE5007D), Colors.white, data['pago_nequi']),
                                if (data['pago_daviplata']?.toString().isNotEmpty ?? false)
                                  _chipPagoLocal('Daviplata', const Color(0xFFEE2A24), Colors.white, data['pago_daviplata']),
                                if (data['pago_bancolombia']?.toString().isNotEmpty ?? false)
                                  _chipPagoLocal('Bancolombia', const Color(0xFFFFCC00), Colors.black, data['pago_bancolombia']),
                              ],
                            ),
                          ),
                        if (data != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.black54,
                                  side: BorderSide(color: Colors.grey[400]!),
                                  padding: const EdgeInsets.symmetric(vertical: 6),
                                ),
                                onPressed: () => _verPerfilMovilLocal(context, data),
                                icon: const Icon(Icons.badge_outlined, size: 14),
                                label: const Text(
                                  'VER PERFIL',
                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                          ),
                        // ENRUTAR — siempre visible mientras el servicio
                        // sigue activo, no solo cuando el sistema
                        // detecta similitud o cercanía. Súmale otro
                        // encargo al mismo moto sin esperar a que
                        // termine el actual (sujeto a su cupo de rango).
                        if (data != null &&
                            ['en_ruta_origen', 'en_origen', 'en_ruta_destino']
                                .contains(estado))
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.blue[700],
                                  side: BorderSide(color: Colors.blue[300]!),
                                  padding: const EdgeInsets.symmetric(vertical: 6),
                                ),
                                onPressed: () => _abrirEnrutarAlMoto(context, servicio, data),
                                icon: const Icon(Icons.alt_route, size: 14),
                                label: const Text(
                                  'ENRUTAR (sumar otro encargo)',
                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                          ),

                        // --- CENTRO DE COMUNICACIÓN EN VIVO Y AUDITORÍA ---
                        if (data != null) ...[
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              // 1. BOTÓN DE WHATSAPP (SIEMPRE ACTIVO)
                              // FIX: antes usaba telMovil (el "12" de
                              // movil12) — apuntaba a un número que no
                              // existe. Ahora usa telefonoReal.
                              if (telefonoReal.isNotEmpty)
                                Expanded(
                                  child: OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.green[700],
                                      side: BorderSide(
                                        color: Colors.green[700]!,
                                      ),
                                      // ---> INYECCIÓN: Quitamos el margen lateral que apachurra el texto
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 8,
                                        horizontal: 2,
                                      ),
                                    ),
                                    icon: const Icon(Icons.wechat, size: 16),
                                    // ---> INYECCIÓN: FittedBox encoge la letra si la pantalla es muy pequeña
                                    label: const FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        'WhatsApp',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                    onPressed: () async {
                                      final numero = telefonoReal.startsWith('57')
                                          ? telefonoReal
                                          : '57$telefonoReal';
                                      final uri = Uri.parse(
                                        'https://wa.me/$numero',
                                      );
                                      if (await canLaunchUrl(uri)) {
                                        await launchUrl(
                                          uri,
                                          mode: LaunchMode.externalApplication,
                                        );
                                      }
                                    },
                                  ),
                                ),

                              if (telefonoReal.isNotEmpty) const SizedBox(width: 8),

                              // 2. BOTÓN DE CHAT INTERNO (MUTA ENTRE CHAT ACTIVO Y BITÁCORA DE HISTORIAL)
                              Expanded(
                                child: Builder(
                                  builder: (context) {
                                    // La alarma de parpadeo solo se activa si el pedido sigue vivo
                                    bool tieneMensajeNuevo =
                                        !esHistorial &&
                                        servicio['chat_cliente'] == true;

                                    return ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: tieneMensajeNuevo
                                            ? Colors.red[700]
                                            : (esHistorial
                                                  ? Colors.grey[800]
                                                  : Colors.blue[800]),
                                        foregroundColor: Colors.white,
                                        // ---> INYECCIÓN: Igualamos los márgenes
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 8,
                                          horizontal: 2,
                                        ),
                                      ),
                                      icon: Icon(
                                        tieneMensajeNuevo
                                            ? Icons.mark_email_unread
                                            : (esHistorial
                                                  ? Icons.history_toggle_off
                                                  : Icons.chat),
                                        size: 16,
                                      ),
                                      // ---> INYECCIÓN: FittedBox para evitar que "NUEVO MENSAJE" se parta
                                      label: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text(
                                          tieneMensajeNuevo
                                              ? 'NUEVO MENSAJE'
                                              : (esHistorial
                                                    ? 'Ver Chat'
                                                    : 'Chat'),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                      onPressed: () {
                                        // Solo limpiamos la alarma si el pedido está activo
                                        if (!esHistorial) {
                                          Supabase.instance.client
                                              .from('servicios')
                                              .update({'chat_cliente': false})
                                              .eq('id', servicio['id']);
                                        }

                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => ChatScreen(
                                              salaId: 'servicio_${servicio['id']}',
                                              miId: widget.usuario['id'],
                                              miNombre:
                                                  widget.usuario['nombre'],
                                              titulo:
                                                  'Chat con $nombreFinal ${esHistorial ? "(Historial)" : ""}',
                                              servicioId: servicio['id'],
                                              alarmaLocal: 'chat_cliente',
                                              alarmaDestino: 'chat_movil',
                                              tipoFaq: TipoFaqChat.local,
                                            ),
                                          ),
                                        );
                                      },
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),

            // ---> INYECCIÓN: WHATSAPP CLIENTE REUBICADO CON MARGEN UNIFORME <---
            if (telCliente != null && telCliente.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 12),
                child: Text(
                  '📞 Cliente: $telCliente',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              )
            else
              const SizedBox(height: 12),

            // -------------------------------------------------------------------
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  estado == 'cotizacion'
                      ? 'Tarifa: Calculando...'
                      : 'Tarifa: ${fmtPeso(servicio['tarifa'])}',
                  style: TextStyle(
                    color: estado == 'cotizacion'
                        ? Colors.orange[800]
                        : Colors.green,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),

            if (servicio['observacion'] != null) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: Text(
                  '📝 ${servicio['observacion']}',
                  style: TextStyle(color: Colors.grey[800], fontSize: 13),
                ),
              ),
            ],

            if (esHistorial && !esGlobal) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.grey[700],
                    backgroundColor: const Color(0xFF0D0D0D),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  onPressed: onOcultar,
                  icon: const Icon(Icons.archive, size: 18),
                  label: const Text(
                    'OCULTAR DEL TABLERO DE HOY',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
              ),
            ],

            if (esGlobal) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red[800],
                    side: BorderSide(color: Colors.red[800]!),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  onPressed: onEliminar,
                  icon: const Icon(Icons.delete, size: 18),
                  label: const Text(
                    'ELIMINAR PERMANENTEMENTE',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
              ),
            ],

            if (esHistorial &&
                estado == 'finalizado' &&
                servicio['movil_id'] != null) ...[
              const SizedBox(height: 12),
              if (servicio['calificacion_local'] == null)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber[100],
                      foregroundColor: Colors.amber[900],
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    onPressed: () => _mostrarDialogoCalificacion(servicio),
                    icon: const Icon(Icons.star_rate_rounded),
                    label: const Text(
                      'CALIFICAR MÓVIL',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.amber[50],
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.amber[200]!),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Tu calificación:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: Colors.black87,
                        ),
                      ),
                      Row(
                        children: List.generate(5, (index) {
                          return Icon(
                            index < (servicio['calificacion_local'] as int)
                                ? Icons.star
                                : Icons.star_border,
                            color: Colors.amber,
                            size: 16,
                          );
                        }),
                      ),
                    ],
                  ),
                ),
            ],

            if (!esHistorial) ...[
              // ── BOTÓN GPS — pedir ubicación exacta al cliente vía WhatsApp ──
              if (!['finalizado', 'finalizado_por_demora',
                    'finalizado_con_problema', 'cancelado', 'caducado']
                  .contains(estado)) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.blue[700],
                      side: BorderSide(color: Colors.blue[300]!),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    icon: const Icon(Icons.my_location, size: 16),
                    label: const Text(
                      'PEDIR UBICACIÓN POR WHATSAPP',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 11),
                    ),
                    onPressed: () async {
                      final link =
                          'https://oukiofdtargjrclualgm.supabase.co'
                          '/functions/v1/capturar-ubicacion?id=${servicio['id']}';
                      final mensaje = Uri.encodeComponent(
                        'Hola 👋 Para que el conductor llegue exactamente '
                        'donde estás, por favor toca este enlace y activa '
                        'tu GPS (solo tarda un segundo):\n$link',
                      );
                      final uri = Uri.parse('https://wa.me/?text=$mensaje');
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri,
                            mode: LaunchMode.externalApplication);
                      }
                    },
                  ),
                ),
              ],
              // ── FIN BOTÓN GPS ────────────────────────────────────────────────
              if (estado == 'pendiente' || estado == 'cotizacion') ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                    ),
                    onPressed: () => _cancelarPedido(servicio['id']),
                    child: Text(
                      estado == 'cotizacion'
                          ? 'DESCARTAR COTIZACIÓN'
                          : 'CANCELAR SERVICIO',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ] else if (estado == 'cotizada') ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: Colors.red),
                        ),
                        onPressed: () => _cancelarPedido(servicio['id']),
                        child: const Text(
                          'RECHAZAR',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue[800],
                        ),
                        onPressed: () => _completarDatosYAprobar(context, servicio),
                        child: Text(
                          'APROBAR',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ] else if (estado == 'cotizacion_aprobada') ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.teal[50],
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.teal[300]!),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, size: 14, color: Colors.teal[700]),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Precio aprobado: ${fmtPeso(servicio['tarifa'])}. Cuando el pedido esté listo, solicita el móvil.',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.teal[900],
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: Colors.red),
                        ),
                        onPressed: () => _cancelarPedido(servicio['id']),
                        child: const Text(
                          'CANCELAR',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal[700],
                        ),
                        icon: Icon(Icons.motorcycle, color: Colors.white, size: 18),
                        onPressed: () => _solicitarMovilAprobado(context, servicio),
                        label: Text(
                          'SOLICITAR MÓVIL',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],        // body Column.children
            ],          // extra nesting from original
          ],            // body Column.children list
        ),              // body Column
      ),                // if (estaExpandida) Padding
      ],                // outer Card.Column.children
    ),                  // outer Card.Column
  ),                    // Card
);                      // AnimatedSize + return
  }

  // -----------------------------------------------------------------------
  // HUB HELPERS — usados en la pestaña MI LOCAL
  // -----------------------------------------------------------------------
  Widget _hubCard({
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Widget? secondaryAction,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey[600])),
                    if (secondaryAction != null) ...[
                      const SizedBox(height: 10),
                      secondaryAction,
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right, color: Colors.black26, size: 22),
            ],
          ),
        ),
      ),
    );
  }

  Widget _hubListTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: iconColor, size: 22),
      title: Text(title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
      subtitle: subtitle != null
          ? Text(subtitle,
              style:
                  const TextStyle(fontSize: 10, color: Colors.black54))
          : null,
      trailing: const Icon(Icons.chevron_right, size: 18),
      onTap: onTap,
      dense: true,
    );
  }

  // Chip de cuenta de pago — nombre fijo de la app + número, usado
  // inline en la tarjeta de servicio (info obligatoria, no opcional).
  // Tocarlo copia el número al portapapeles, listo para pegar en la
  // app de pago correspondiente.
  Widget _chipPagoLocal(
    String app,
    Color colorMarca,
    Color colorTexto,
    dynamic numero,
  ) {
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () {
        Clipboard.setData(ClipboardData(text: numero.toString()));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$app copiado: $numero'),
            backgroundColor: Colors.black,
            duration: const Duration(seconds: 2),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: colorMarca,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              app,
              style: TextStyle(
                color: colorTexto,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              numero.toString(),
              style: TextStyle(
                color: colorTexto,
                fontSize: 10,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.copy, size: 10, color: colorTexto.withAlpha(180)),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // ENRUTAR ENCARGO AL MÓVIL ACTIVO
  // Abre un diálogo para crear un nuevo servicio asignado
  // directamente al mismo móvil que ya está haciendo una entrega.
  // ─────────────────────────────────────────────────────────────
  void _abrirEnrutarAlMoto(
    BuildContext context,
    Map<String, dynamic> servicio,
    Map<String, dynamic> moto,
  ) {
    final destinoCtrl = TextEditingController();
    final telefonoCtrl = TextEditingController();
    final movilNombre = (moto['usuario'] ?? moto['nombre'] ?? '').toString().toUpperCase();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(children: [
          const Icon(Icons.alt_route, color: Colors.blue),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              'ENRUTAR A $movilNombre',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.blue),
            ),
          ),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Crea un nuevo encargo para $movilNombre sin esperar a que termine el actual.',
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: destinoCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Destino del nuevo encargo',
                border: OutlineInputBorder(),
                isDense: true,
                prefixIcon: Icon(Icons.flag_outlined),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: telefonoCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Teléfono receptor (opcional)',
                border: OutlineInputBorder(),
                isDense: true,
                prefixIcon: Icon(Icons.phone_outlined),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CANCELAR', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue[700],
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.send, size: 16),
            label: const Text('ENVIAR', style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: () async {
              final destino = destinoCtrl.text.trim();
              if (destino.isEmpty) return;
              Navigator.pop(ctx);
              try {
                await Supabase.instance.client.from('servicios').insert({
                  'local_id': widget.usuario['id'],
                  'creador': widget.usuario['nombre'],
                  'origen': (widget.usuario['nombre'] ?? '').toString().toUpperCase(),
                  'destino': destino.toUpperCase(),
                  'tarifa': 0.0,
                  'tarifa_detalle': {'total': 0.0, 'base': 0.0, 'fuente': 'local_enrutado'},
                  'observacion': '[ ENRUTADO ] ↪ Encargo adicional para $movilNombre',
                  'estado': 'pendiente',
                  'tipo_servicio': 'PAQUETERÍA',
                  'exclusivo_id': moto['id'].toString(),
                  'ruta_grupo_id': servicio['id'],
                  if (telefonoCtrl.text.trim().isNotEmpty)
                    'telefono_receptor': telefonoCtrl.text.trim(),
                });
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('✅ Encargo enrutado a $movilNombre.'),
                      backgroundColor: Colors.blue[700],
                      duration: const Duration(seconds: 3),
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error al enrutar: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
          ),
        ],
      ),
    );
  }

  // Perfil rápido del moto visto desde el local.
  void _verPerfilMovilLocal(BuildContext ctx, Map<String, dynamic> moto) {
    final nombre = moto['nombre']?.toString() ?? '—';
    final usuario = moto['usuario_movil']?.toString() ?? '';
    final tel = moto['telefono']?.toString() ?? '—';
    final foto = moto['foto_url']?.toString();
    showDialog(
      context: ctx,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 32,
              backgroundImage:
                  foto != null && foto.isNotEmpty ? NetworkImage(foto) : null,
              backgroundColor: const Color(0xFF0D0D0D),
              child: foto == null || foto.isEmpty
                  ? const Icon(Icons.person, size: 32, color: Colors.grey)
                  : null,
            ),
            const SizedBox(height: 10),
            Text(nombre,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            if (usuario.isNotEmpty)
              Text(usuario,
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.phone, size: 14, color: Colors.grey),
              const SizedBox(width: 4),
              Text(tel, style: const TextStyle(fontSize: 13)),
            ]),
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 4, children: [
              if (moto['pago_nequi'] != null && moto['pago_nequi'].toString().isNotEmpty)
                _chipPagoLocal('Nequi', const Color(0xFFE5007D), Colors.white, moto['pago_nequi']),
              if (moto['pago_daviplata'] != null && moto['pago_daviplata'].toString().isNotEmpty)
                _chipPagoLocal('Daviplata', const Color(0xFFEE2A24), Colors.white, moto['pago_daviplata']),
              if (moto['pago_bancolombia'] != null && moto['pago_bancolombia'].toString().isNotEmpty)
                _chipPagoLocal('Bancolombia', const Color(0xFFFFCC00), Colors.black, moto['pago_bancolombia']),
            ]),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('CERRAR')),
        ],
      ),
    );
  }
}
