// ignore_for_file: curly_braces_in_flow_control_structures, no_leading_underscores_for_local_identifiers, use_build_context_synchronously, unused_element, unused_element_parameter
part of 'local_screen.dart';

// ══════════════════════════════════════════════════════════════════════════════
// _CardsMixin — tarjetas de servicio, controles operativos y helpers de hub
// ══════════════════════════════════════════════════════════════════════════════
mixin _CardsMixin on State<LocalScreen> {
  // ── Stubs de métodos implementados en otros mixins ────────────────────────
  void _abrirFormularioPedido(
    BuildContext context, {
    bool esPuntoAPunto = false,
    required Map<String, dynamic> perfilEnVivo,
    String? telefonoPrellenado,
    String? movilPreselId,
    String? movilPreselLabel,
  });

  // ── Campos propios ─────────────────────────────────────────────────────────
  // Etiqueta "Móvil 07" de móviles asignados directo (se consulta 1 vez por móvil)
  final Map<String, String> _etiquetasMovilAsignado = {};
  final Set<String> _etiquetasMovilPidiendo = {};

  String? _etiquetaMovilAsignado(String id) {
    final ya = _etiquetasMovilAsignado[id];
    if (ya != null || id.isEmpty || _etiquetasMovilPidiendo.contains(id)) return ya;
    _etiquetasMovilPidiendo.add(id);
    () async {
      try {
        final u = await Supabase.instance.client
            .from('usuarios')
            .select('numero_movil, nombre')
            .eq('id', id)
            .maybeSingle();
        if (u != null) {
          final n = u['numero_movil'];
          _etiquetasMovilAsignado[id] = n != null
              ? 'Móvil ${n.toString().padLeft(2, '0')}'
              : (u['nombre']?.toString() ?? 'Móvil');
          if (mounted) _expansionTick.value++; // redibuja solo la lista
        }
      } catch (_) {
        _etiquetasMovilPidiendo.remove(id); // reintentar en el próximo dibujo
      }
    }();
    return null;
  }

  final Set<int> _tarjetasColapsadasLocal = {};
  final Set<int> _tarjetasExpandidasLocal = {};
  final ValueNotifier<int> _expansionTick = ValueNotifier(0);
  /// IDs de servicios que acaban de pasar a 'cotizada' (highlight animado)
  final Set<int> _cotizadasRecientes = {};

  /// Datos del móvil por id, consultados UNA vez y reutilizados. Antes la
  /// tarjeta los pedía al servidor en cada redibujado (muchas veces por minuto).
  final Map<String, Future<List<Map<String, dynamic>>>> _infoMovilCache = {};
  Future<List<Map<String, dynamic>>> _infoMovil(dynamic movilId) {
    final key = movilId.toString();
    return _infoMovilCache.putIfAbsent(
      key,
      () => Supabase.instance.client
          .from('usuarios')
          .select(
            'id, nombre, usuario, rol, telefono, foto_perfil_url, '
            'pago_nequi, pago_daviplata, pago_bancolombia',
          )
          .eq('id', movilId)
          .then((r) => List<Map<String, dynamic>>.from(r))
          .catchError((_) {
        _infoMovilCache.remove(key); // si falló, reintenta en el próximo dibujo
        return <Map<String, dynamic>>[];
      }),
    );
  }

  @override
  void dispose() {
    _expansionTick.dispose();
    super.dispose();
  }

  // ── Helper: formatea ISO timestamp a "HH:mm" local ───────────────────────
  String _fmtHora(dynamic iso) {
    if (iso == null) return '';
    try {
      final dt = DateTime.parse(iso.toString()).toLocal();
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      return ' · $h:$m';
    } catch (_) {
      return '';
    }
  }

  // ── Helper: tiempo transcurrido "hace Xm" / "hace Xh Ym" ────────────────
  String _fmtElapsed(dynamic iso) {
    if (iso == null) return '';
    try {
      final dt = DateTime.parse(iso.toString()).toLocal();
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 1) return ' · ahora';
      if (diff.inMinutes < 60) return ' · hace ${diff.inMinutes}m';
      final h = diff.inHours;
      final m = diff.inMinutes.remainder(60);
      return m > 0 ? ' · hace ${h}h ${m}m' : ' · hace ${h}h';
    } catch (_) {
      return '';
    }
  }

  // ── Abstract stubs (implementados en otros mixins) ─────────────────────────
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
          .select('onesignal_2m, onesignal_5m, movil_id')
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

      // El aviso al móvil lo manda el SERVIDOR (trg_avisar_servicio_cancelado).
      // Notificar a la Central que el pedido fue cancelado por el local
      MotorNotificaciones.dispararACentral(
        titulo: '❌ PEDIDO CANCELADO',
        mensaje: '${widget.usuario['nombre']} canceló el pedido #$id.',
        urgente: false,
        sonido: 'central_cancelado',
        canalAndroidId: MotorNotificaciones.canalCanceladoId,
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

  // ═══════════════════════════════════════════════════════════════════════════
  // TARJETA DE SERVICIO DEL LOCAL (diseño nuevo, oscuro)
  //   • Franja de color por estado, cabecera con estado/número/tiempo/destino/
  //     precio, línea de avance, bloque del móvil (pagos visibles con copiar),
  //     datos con íconos, precio con desglose y acciones abajo.
  //   • El local NO ve la fase de la cascada: solo "Buscando móvil".
  // ═══════════════════════════════════════════════════════════════════════════
  static const Color _tFondo = Color(0xFF1C1C1E);
  static const Color _tFondo2 = Color(0xFF26262A);
  static const Color _tTexto2 = Color(0xFF9A9AA0);

  Widget _construirTarjetaServicio(
    Map<String, dynamic> servicio, {
    bool esHistorial = false,
    bool esGlobal = false,
    VoidCallback? onOcultar,
    VoidCallback? onEliminar,
    VoidCallback? extraRebuild,
  }) {
    final int svcId = servicio['id'] as int;
    final bool estaExpandida = esHistorial
        ? _tarjetasExpandidasLocal.contains(svcId)
        : !_tarjetasColapsadasLocal.contains(svcId);
    void toggleExpansion() {
      final set = esHistorial ? _tarjetasExpandidasLocal : _tarjetasColapsadasLocal;
      set.contains(svcId) ? set.remove(svcId) : set.add(svcId);
      _expansionTick.value++;
      extraRebuild?.call();
    }

    final String estado = servicio['estado']?.toString() ?? '';
    final bool esPAP = servicio['es_punto_a_punto'] == true;
    final bool terminado = ['finalizado', 'finalizado_por_demora', 'finalizado_con_problema',
        'cancelado', 'caducado'].contains(estado);

    // ── Estado visual ────────────────────────────────────────────────────
    late Color color;
    late String textoEstado;
    late IconData icono;
    final bool asignadoDirecto = estado == 'pendiente' &&
        (servicio['exclusivo_id']?.toString().trim() ?? '').isNotEmpty;
    switch (estado) {
      case 'programado':
        color = Colors.lightBlueAccent;
        icono = Icons.schedule;
        textoEstado = 'PROGRAMADO';
        if (servicio['liberacion_at'] != null) {
          final diff = DateTime.parse(servicio['liberacion_at']).toLocal().difference(DateTime.now()).inMinutes;
          textoEstado = diff > 0 ? 'PROGRAMADO · SALE EN $diff MIN' : 'LIBERANDO…';
        }
        break;
      case 'pendiente':
        if (asignadoDirecto) {
          final et = _etiquetaMovilAsignado(servicio['exclusivo_id'].toString().split(',').first.trim());
          color = Colors.lightBlueAccent;
          icono = Icons.assignment_ind_rounded;
          textoEstado = et != null ? 'ASIGNADO A ${et.toUpperCase()} · ESPERANDO QUE ACEPTE' : 'MÓVIL ASIGNADO · ESPERANDO QUE ACEPTE';
        } else {
          color = Colors.amber;
          icono = Icons.radar;
          textoEstado = 'BUSCANDO MÓVIL';
        }
        break;
      case 'en_curso':
      case 'en_ruta_origen':
        color = const Color(0xff3AF500);
        icono = Icons.two_wheeler;
        textoEstado = 'MÓVIL EN CAMINO AL LOCAL';
        break;
      case 'en_origen':
        color = Colors.orangeAccent;
        icono = Icons.storefront;
        textoEstado = 'MÓVIL EN EL LOCAL';
        break;
      case 'en_ruta_destino':
        color = const Color(0xff3AF500);
        icono = Icons.delivery_dining;
        textoEstado = 'EN RUTA DE ENTREGA';
        break;
      case 'problema':
        color = Colors.redAccent;
        icono = Icons.warning_amber_rounded;
        textoEstado = 'NOVEDAD REPORTADA';
        break;
      case 'cotizacion':
        color = Colors.orangeAccent;
        icono = Icons.hourglass_top_rounded;
        textoEstado = 'ESPERANDO PRECIO';
        break;
      case 'cotizada':
        color = Colors.lightBlueAccent;
        icono = Icons.monetization_on;
        textoEstado = 'COTIZACIÓN RECIBIDA';
        break;
      case 'cotizacion_aprobada':
        color = Colors.tealAccent;
        icono = Icons.check_circle_outline;
        textoEstado = 'APROBADA · EN ESPERA';
        break;
      case 'finalizado':
        color = Colors.greenAccent;
        icono = Icons.check_circle;
        textoEstado = 'ENTREGADO';
        break;
      case 'cancelado':
        color = Colors.grey;
        icono = Icons.block;
        textoEstado = 'CANCELADO';
        break;
      case 'caducado':
        color = Colors.purpleAccent;
        icono = Icons.hourglass_disabled;
        textoEstado = 'NADIE TOMÓ EL SERVICIO';
        break;
      case 'finalizado_por_demora':
      case 'finalizado_con_problema':
        color = Colors.orangeAccent;
        icono = Icons.report_problem;
        textoEstado = 'CERRADO CON NOVEDAD';
        break;
      default:
        color = Colors.grey;
        icono = Icons.help_outline;
        textoEstado = estado.toUpperCase();
    }

    // ── Tiempo del estado (activos: "hace X"; historial: hora) ───────────
    final dynamic tsEstado = switch (estado) {
      'en_ruta_origen' || 'en_curso' => servicio['accepted_at'],
      'en_origen' => servicio['llegada_sede_at'] ?? servicio['updated_at'],
      'en_ruta_destino' => servicio['picked_up_at'],
      'pendiente' || 'cotizacion' => servicio['created_at'],
      _ => servicio['updated_at'] ?? servicio['created_at'],
    };
    final String tiempo = (esHistorial || terminado ? _fmtHora(tsEstado) : _fmtElapsed(tsEstado))
        .replaceFirst(' · ', '');

    final num? tarifa = servicio['tarifa'] as num?;
    final num tarifaNum = tarifa ?? 0;
    final bool hayTarifa = !esPAP && tarifaNum > 0;
    final String tipo = (servicio['tipo_servicio'] ?? '').toString().toUpperCase();
    final IconData iconoTipo = tipo.contains('MOTOTAXI')
        ? Icons.two_wheeler
        : (tipo.contains('COMIDA') || tipo.contains('DOMICILIO'))
            ? Icons.restaurant
            : tipo.contains('COMPRA')
                ? Icons.shopping_bag_outlined
                : Icons.inventory_2_outlined;

    final bool destacada = !esHistorial && _cotizadasRecientes.contains(svcId);

    // ─────────────────────────────────────────────────────────────────────
    Widget cabecera() => InkWell(
          onTap: toggleExpansion,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(icono, size: 14, color: color),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(textoEstado,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.3)),
                      ),
                    ]),
                  ),
                ),
                if (tiempo.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(tiempo, style: const TextStyle(color: _tTexto2, fontSize: 11)),
                ],
                const Spacer(),
                Text('#${servicio['numero_local'] ?? servicio['id']}',
                    style: const TextStyle(color: _tTexto2, fontWeight: FontWeight.bold, fontSize: 12)),
                Icon(estaExpandida ? Icons.expand_less : Icons.expand_more, color: _tTexto2, size: 20),
              ]),
              const SizedBox(height: 8),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(esPAP ? Icons.flash_on : iconoTipo, size: 18, color: Colors.white70),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    esPAP ? 'Punto a punto · ${servicio['origen'] ?? ''}' : (servicio['destino']?.toString() ?? '—'),
                    maxLines: estaExpandida ? 3 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700, height: 1.25),
                  ),
                ),
                if (hayTarifa) ...[
                  const SizedBox(width: 8),
                  Text(fmtPeso(tarifa),
                      style: const TextStyle(color: Color(0xff3AF500), fontSize: 16, fontWeight: FontWeight.bold)),
                ],
              ]),
            ]),
          ),
        );

    // ── Línea de avance (sin fases de cascada) ────────────────────────────
    Widget lineaAvance() {
      final pasos = <(String, dynamic)>[
        ('Pedido', servicio['created_at']),
        ('Móvil', servicio['accepted_at']),
        ('En local', servicio['llegada_sede_at']),
        ('En camino', servicio['picked_up_at']),
        ('Entregado', estado == 'finalizado' ? servicio['updated_at'] : null),
      ];
      final int actual = switch (estado) {
        'en_ruta_origen' || 'en_curso' => 1,
        'en_origen' => 2,
        'en_ruta_destino' => 3,
        'finalizado' => 4,
        'problema' => servicio['picked_up_at'] != null ? 3 : (servicio['llegada_sede_at'] != null ? 2 : 1),
        _ => 0,
      };
      String hora(dynamic iso) => _fmtHora(iso).replaceFirst(' · ', '');
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(children: [
          for (int i = 0; i < pasos.length; i++) ...[
            Expanded(
              child: Column(children: [
                Row(children: [
                  Expanded(
                      child: Container(
                          height: 2,
                          color: i == 0 ? Colors.transparent : (i <= actual ? color : Colors.white12))),
                  Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i < actual ? color : (i == actual ? color.withValues(alpha: 0.25) : _tFondo2),
                      border: Border.all(color: i <= actual ? color : Colors.white24, width: 2),
                    ),
                    child: i < actual ? const Icon(Icons.check, size: 9, color: Colors.black) : null,
                  ),
                  Expanded(
                      child: Container(
                          height: 2,
                          color: i == pasos.length - 1 ? Colors.transparent : (i < actual ? color : Colors.white12))),
                ]),
                const SizedBox(height: 4),
                Text(pasos[i].$1,
                    style: TextStyle(
                        fontSize: 10,
                        color: i <= actual ? Colors.white : _tTexto2,
                        fontWeight: i == actual ? FontWeight.bold : FontWeight.normal)),
                Text(pasos[i].$2 != null && i <= actual ? hora(pasos[i].$2) : ' ',
                    style: const TextStyle(fontSize: 9, color: _tTexto2)),
              ]),
            ),
          ],
        ]),
      );
    }

    // ── Bloque del móvil ──────────────────────────────────────────────────
    Widget bloqueMovil() => FutureBuilder<List<Map<String, dynamic>>>(
          future: _infoMovil(servicio['movil_id']),
          builder: (context, snap) {
            final data = (snap.data != null && snap.data!.isNotEmpty) ? snap.data!.first : null;
            if (data == null) return const SizedBox.shrink();
            final usr = data['usuario']?.toString() ?? '';
            final numMovil = usr.replaceAll(RegExp(r'[^0-9]'), '');
            final esMovil = (data['rol']?.toString() ?? 'movil') == 'movil';
            final nombreFinal = esMovil && numMovil.isNotEmpty
                ? 'Móvil $numMovil'
                : (data['nombre']?.toString() ?? 'Móvil');
            final telefonoReal = data['telefono']?.toString() ?? '';
            final fotoUrl = data['foto_perfil_url']?.toString();
            final tieneFoto = fotoUrl != null && fotoUrl.isNotEmpty;
            final bool chatNuevo = !esHistorial && servicio['chat_cliente'] == true;
            final pagos = <(String, Color, String)>[
              if ((data['pago_nequi']?.toString() ?? '').isNotEmpty)
                ('Nequi', const Color(0xFFE5007D), data['pago_nequi'].toString()),
              if ((data['pago_daviplata']?.toString() ?? '').isNotEmpty)
                ('Daviplata', const Color(0xFFEE2A24), data['pago_daviplata'].toString()),
              if ((data['pago_bancolombia']?.toString() ?? '').isNotEmpty)
                ('Bancolombia', const Color(0xFFFFCC00), data['pago_bancolombia'].toString()),
            ];

            Widget botonIcono(IconData ic, Color c, String tip, VoidCallback onTap, {bool alerta = false}) =>
                Tooltip(
                  message: tip,
                  child: InkWell(
                    onTap: onTap,
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: (alerta ? Colors.red : c).withValues(alpha: alerta ? 0.9 : 0.16),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(ic, size: 19, color: alerta ? Colors.white : c),
                    ),
                  ),
                );

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: _tFondo2, borderRadius: BorderRadius.circular(10)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: Colors.black,
                    backgroundImage: tieneFoto ? NetworkImage(fotoUrl) : null,
                    child: tieneFoto
                        ? null
                        : Text(numMovil.isNotEmpty ? numMovil : '?',
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(nombreFinal,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                      if (esMovil && data['nombre'] != null)
                        Text(data['nombre'].toString().toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: _tTexto2, fontSize: 10)),
                    ]),
                  ),
                  if (telefonoReal.isNotEmpty) ...[
                    botonIcono(Icons.wechat, Colors.greenAccent, 'WhatsApp', () async {
                      final n = telefonoReal.startsWith('57') ? telefonoReal : '57$telefonoReal';
                      final uri = Uri.parse('https://wa.me/$n');
                      if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
                    }),
                    const SizedBox(width: 6),
                  ],
                  botonIcono(
                    chatNuevo ? Icons.mark_email_unread : (esHistorial ? Icons.history : Icons.chat_bubble_outline),
                    Colors.lightBlueAccent,
                    chatNuevo ? 'Mensaje nuevo' : 'Chat',
                    () {
                      if (!esHistorial) {
                        Supabase.instance.client.from('servicios').update({'chat_cliente': false}).eq('id', servicio['id']);
                      }
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ChatScreen(
                            salaId: 'servicio_${servicio['id']}',
                            miId: widget.usuario['id'],
                            miNombre: widget.usuario['nombre'],
                            titulo: 'Chat con $nombreFinal ${esHistorial ? "(Historial)" : ""}',
                            servicioId: servicio['id'],
                            alarmaLocal: 'chat_cliente',
                            alarmaDestino: 'chat_movil',
                            destinatarioId: (servicio['movil_id'] as num?)?.toInt(),
                            tipoFaq: TipoFaqChat.local,
                          ),
                        ),
                      );
                    },
                    alerta: chatNuevo,
                  ),
                  const SizedBox(width: 6),
                  botonIcono(Icons.badge_outlined, Colors.white70, 'Ver perfil', () => _verPerfilMovilLocal(context, data)),
                ]),
                const SizedBox(height: 10),
                // Pagos: siempre visibles, con botón de copiar
                if (pagos.isEmpty)
                  const Text('Sin métodos de pago registrados',
                      style: TextStyle(color: _tTexto2, fontSize: 11, fontStyle: FontStyle.italic))
                else
                  ...pagos.map((p) => Container(
                        margin: const EdgeInsets.only(top: 4),
                        padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(8),
                          border: Border(left: BorderSide(color: p.$2, width: 3)),
                        ),
                        child: Row(children: [
                          SizedBox(
                            width: 84,
                            child: Text(p.$1,
                                style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                          ),
                          Expanded(
                            child: Text(p.$3,
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
                          ),
                          IconButton(
                            tooltip: 'Copiar',
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.copy_rounded, size: 18, color: Colors.white70),
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: p.$3));
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                content: Text('Número de ${p.$1} copiado'),
                                duration: const Duration(seconds: 2),
                                behavior: SnackBarBehavior.floating,
                              ));
                            },
                          ),
                        ]),
                      )),
                if (['en_ruta_origen', 'en_origen', 'en_ruta_destino'].contains(estado) && !esHistorial) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.lightBlueAccent,
                        side: BorderSide(color: Colors.lightBlueAccent.withValues(alpha: 0.5)),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                      onPressed: () => _abrirFormularioPedido(
                        context,
                        perfilEnVivo: widget.usuario,
                        movilPreselId: data['id'].toString(),
                        movilPreselLabel: movilLabel(data),
                      ),
                      icon: const Icon(Icons.add_circle_outline, size: 16),
                      label: Text('NUEVO PEDIDO CON ${movilLabel(data).toUpperCase()}',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ]),
            );
          },
        );

    // ── Fila de dato con ícono ───────────────────────────────────────────
    Widget dato(IconData ic, Widget contenido, {Widget? accion}) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(padding: const EdgeInsets.only(top: 1), child: Icon(ic, size: 16, color: _tTexto2)),
            const SizedBox(width: 10),
            Expanded(child: contenido),
            if (accion != null) accion,
          ]),
        );

    final String telCliente = servicio['telefono_receptor']?.toString().trim() ?? '';
    final String ticket = servicio['ticket_factura']?.toString().trim() ?? '';
    final String nota = servicio['observacion']?.toString().trim() ?? '';
    final String fotoComanda = servicio['foto_comanda_url']?.toString() ?? '';
    final int recargo = (servicio['recargo_total'] as num?)?.toInt() ?? 0;

    Future<void> contactarCliente(BuildContext ctx) async {
      final dig = telCliente.replaceAll(RegExp(r'[^0-9]'), '');
      final wa = dig.startsWith('57') ? dig : '57$dig';
      await showModalBottomSheet(
        context: ctx,
        backgroundColor: _tFondo,
        builder: (bs) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              title: Text('Cliente · $telCliente', style: const TextStyle(color: Colors.white)),
            ),
            ListTile(
              leading: const Icon(Icons.call, color: Colors.lightBlueAccent),
              title: const Text('Llamar', style: TextStyle(color: Colors.white)),
              onTap: () async {
                Navigator.pop(bs);
                await launchUrl(Uri.parse('tel:$dig'));
              },
            ),
            ListTile(
              leading: const Icon(Icons.wechat, color: Colors.greenAccent),
              title: const Text('WhatsApp', style: TextStyle(color: Colors.white)),
              onTap: () async {
                Navigator.pop(bs);
                await launchUrl(Uri.parse('https://wa.me/$wa'), mode: LaunchMode.externalApplication);
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy_rounded, color: Colors.white70),
              title: const Text('Copiar número', style: TextStyle(color: Colors.white)),
              onTap: () {
                Clipboard.setData(ClipboardData(text: telCliente));
                Navigator.pop(bs);
              },
            ),
          ]),
        ),
      );
    }

    Widget botonPrincipal(String texto, IconData? ic, Color c, VoidCallback onTap) => ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: c,
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onPressed: onTap,
          icon: Icon(ic ?? Icons.check, size: 18),
          label: Text(texto, style: const TextStyle(fontWeight: FontWeight.bold)),
        );
    Widget botonSecundario(String texto, Color c, VoidCallback? onTap, {IconData? ic}) => OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: c,
            side: BorderSide(color: c.withValues(alpha: 0.5)),
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onPressed: onTap,
          icon: Icon(ic ?? Icons.close, size: 16),
          label: Text(texto, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
        );

    // ── Cuerpo ────────────────────────────────────────────────────────────
    Widget cuerpo() => Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Divider(color: Colors.white10, height: 1),
            const SizedBox(height: 12),
            if (!esPAP && ['pendiente', 'en_curso', 'en_ruta_origen', 'en_origen', 'en_ruta_destino',
                    'problema', 'finalizado'].contains(estado))
              lineaAvance(),
            if (servicio['movil_id'] != null) bloqueMovil(),

            // Datos del pedido
            if (ticket.isNotEmpty)
              dato(Icons.receipt_long, Text('Ticket / factura #$ticket',
                  style: const TextStyle(color: Colors.lightBlueAccent, fontWeight: FontWeight.bold, fontSize: 13))),
            if (telCliente.isNotEmpty)
              dato(
                Icons.phone,
                InkWell(
                  onTap: () => contactarCliente(context),
                  child: Text('Cliente: $telCliente',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.underline,
                          decorationColor: Colors.white38)),
                ),
                accion: InkWell(
                  onTap: () => contactarCliente(context),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6),
                    child: Icon(Icons.more_horiz, color: _tTexto2, size: 18),
                  ),
                ),
              ),
            if (nota.isNotEmpty)
              dato(Icons.sticky_note_2_outlined,
                  Text(nota, style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.3))),
            if (fotoComanda.isNotEmpty)
              dato(
                Icons.photo_camera_outlined,
                GestureDetector(
                  onTap: () => showDialog(
                    context: context,
                    builder: (dctx) => Dialog(
                      backgroundColor: Colors.black,
                      insetPadding: const EdgeInsets.all(12),
                      child: Stack(children: [
                        InteractiveViewer(child: Image.network(fotoComanda, fit: BoxFit.contain)),
                        Positioned(
                          top: 8,
                          right: 8,
                          child: IconButton(
                              icon: const Icon(Icons.close, color: Colors.white),
                              onPressed: () => Navigator.pop(dctx)),
                        ),
                      ]),
                    ),
                  ),
                  child: Row(children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.network(fotoComanda,
                          width: 56,
                          height: 56,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              const SizedBox(width: 56, height: 56, child: Icon(Icons.broken_image, color: Colors.grey))),
                    ),
                    const SizedBox(width: 10),
                    const Text('Foto de comanda · toca para ver',
                        style: TextStyle(color: _tTexto2, fontSize: 12)),
                  ]),
                ),
              ),

            // Precio
            if (esPAP)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: 2, bottom: 4),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.purple.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text('⚡ PUNTO A PUNTO — Servicio gratuito',
                    style: TextStyle(color: Colors.purpleAccent, fontWeight: FontWeight.bold, fontSize: 13)),
              )
            else
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: 2, bottom: 4),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(color: _tFondo2, borderRadius: BorderRadius.circular(10)),
                child: estado == 'cotizacion'
                    ? const Row(children: [
                        Icon(Icons.hourglass_top_rounded, size: 16, color: Colors.orangeAccent),
                        SizedBox(width: 8),
                        Text('Esperando el precio de la central…',
                            style: TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold, fontSize: 13)),
                      ])
                    : Row(children: [
                        const Text('Tarifa', style: TextStyle(color: _tTexto2, fontSize: 12)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: recargo > 0 && hayTarifa
                              ? Text('base ${fmtPeso(tarifaNum - recargo)} + recargo ${fmtPeso(recargo)}',
                                  style: const TextStyle(color: _tTexto2, fontSize: 11))
                              : const SizedBox.shrink(),
                        ),
                        Text(hayTarifa ? fmtPeso(tarifa) : '—',
                            style: const TextStyle(color: Color(0xff3AF500), fontWeight: FontWeight.bold, fontSize: 18)),
                      ]),
              ),

            // Ubicación del cliente
            if (!esHistorial && !terminado) ...[
              IndicadorUbicacionCliente(servicio, oscuro: true),
            ],

            // ── Acciones ──────────────────────────────────────────────────
            const SizedBox(height: 10),
            if (!esHistorial) ...[
              if (estado == 'cotizada')
                Row(children: [
                  Expanded(child: botonSecundario('RECHAZAR', Colors.redAccent, () => _cancelarPedido(servicio['id']))),
                  const SizedBox(width: 8),
                  Expanded(
                      flex: 2,
                      child: botonPrincipal('APROBAR', Icons.check, Colors.lightBlueAccent,
                          () => _completarDatosYAprobar(context, servicio))),
                ])
              else if (estado == 'cotizacion_aprobada') ...[
                Text('Precio aprobado: ${fmtPeso(tarifa)}. Cuando el pedido esté listo, solicita el móvil.',
                    style: const TextStyle(color: Colors.tealAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: botonSecundario('CANCELAR', Colors.redAccent, () => _cancelarPedido(servicio['id']))),
                  const SizedBox(width: 8),
                  Expanded(
                      flex: 2,
                      child: botonPrincipal('SOLICITAR MÓVIL', Icons.two_wheeler, Colors.tealAccent,
                          () => _solicitarMovilAprobado(context, servicio))),
                ]),
              ],
              if (!terminado)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(children: [
                    Expanded(
                      child: botonSecundario('PEDIR UBICACIÓN', Colors.lightBlueAccent,
                          () => pedirUbicacionCliente(servicio), ic: Icons.my_location),
                    ),
                    if (estado == 'pendiente' || estado == 'cotizacion') ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: botonSecundario(estado == 'cotizacion' ? 'DESCARTAR' : 'CANCELAR', Colors.redAccent,
                            () => _cancelarPedido(servicio['id'])),
                      ),
                    ],
                  ]),
                ),
            ],

            // Historial: calificar / ocultar / eliminar
            if (esHistorial && estado == 'finalizado' && servicio['movil_id'] != null) ...[
              if (servicio['calificacion_local'] == null)
                SizedBox(
                  width: double.infinity,
                  child: botonPrincipal('CALIFICAR MÓVIL', Icons.star_rate_rounded, Colors.amber,
                      () => _mostrarDialogoCalificacion(servicio)),
                )
              else
                Row(children: [
                  const Text('Tu calificación', style: TextStyle(color: _tTexto2, fontSize: 12)),
                  const Spacer(),
                  ...List.generate(
                      5,
                      (i) => Icon(i < (servicio['calificacion_local'] as int) ? Icons.star : Icons.star_border,
                          color: Colors.amber, size: 18)),
                ]),
              const SizedBox(height: 8),
            ],
            if (esHistorial && !esGlobal)
              SizedBox(
                width: double.infinity,
                child: botonSecundario('OCULTAR DEL TABLERO DE HOY', Colors.white54, onOcultar, ic: Icons.archive),
              ),
            if (esGlobal)
              SizedBox(
                width: double.infinity,
                child: botonSecundario('ELIMINAR PERMANENTEMENTE', Colors.redAccent, onEliminar, ic: Icons.delete),
              ),
          ]),
        );

    return AnimatedContainer(
      duration: const Duration(milliseconds: 600),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: _tFondo,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: destacada ? Colors.lightBlueAccent : Colors.white.withValues(alpha: 0.06),
            width: destacada ? 2 : 1),
        boxShadow: [
          if (destacada)
            BoxShadow(color: Colors.lightBlueAccent.withValues(alpha: 0.45), blurRadius: 20, spreadRadius: 2)
          else
            BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 6, offset: const Offset(0, 2)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(children: [
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              cabecera(),
              if (estaExpandida) cuerpo(),
            ]),
          ),
          // Franja de color del estado
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Container(width: 4, color: esHistorial ? color.withValues(alpha: 0.5) : color),
          ),
        ]),
      ),
    );
  }

  // Diseño anterior de la tarjeta (ya no se usa; se conserva temporalmente
  // como referencia y se puede borrar).
  Widget _construirTarjetaServicioAnterior(
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
          // La liberación la hace el SERVIDOR (se_liberar_programados) a la hora
          // exacta, aunque el local tenga la app cerrada: cancela los avisos
          // viejos, pasa a 'pendiente' y arranca F1 (Masters en línea) + F2/F3/F4.
        }
      }
    } else if (estado == 'pendiente' &&
        (servicio['exclusivo_id']?.toString().trim() ?? '').isNotEmpty) {
      // Enrutado / asignado directo: ya tiene móvil, falta que lo acepte
      final idMovil = servicio['exclusivo_id'].toString().split(',').first.trim();
      final etiqueta = _etiquetaMovilAsignado(idMovil);
      bordeColor = Colors.blue[700]!;
      fondoColor = const Color(0xFFE3F2FD);
      textoEstado = etiqueta != null
          ? 'ASIGNADO A ${etiqueta.toUpperCase()} — ESPERANDO QUE ACEPTE'
          : 'MÓVIL ASIGNADO — ESPERANDO QUE ACEPTE';
      iconoEstado = Icons.assignment_ind_rounded;
    } else if (estado == 'pendiente') {
      bordeColor = Colors.amber[700]!;
      fondoColor = const Color(0xFFFFF9C4);
      textoEstado = 'BUSCANDO MÓVIL...';
      iconoEstado = Icons.radar;
    } else if (estado == 'en_origen') {
      bordeColor = Colors.orange[800]!;
      fondoColor = Colors.orange[50]!;
      textoEstado = 'MÓVIL ESPERANDO EN EL LOCAL';
      iconoEstado = Icons.storefront;
    } else if (estado == 'en_curso' || estado == 'en_ruta_origen') {
      bordeColor = const Color(0xff3AF500);
      fondoColor = const Color(0xfff0fff0);
      textoEstado = estado == 'en_ruta_origen' ? 'MÓVIL EN CAMINO AL LOCAL' : 'MÓVIL ASIGNADO';
      iconoEstado = Icons.motorcycle;
    } else if (estado == 'en_ruta_destino') {
      bordeColor = const Color(0xff3AF500);
      fondoColor = const Color(0xFFDCEEFF);
      textoEstado = 'EN RUTA DE ENTREGA';
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

    // ── Timestamps por estado ──────────────────────────────────────────────
    // Activos: muestra tiempo transcurrido ("hace 5m"). Historial: hora fija.
    String ts(dynamic iso) => esHistorial ? _fmtHora(iso) : _fmtElapsed(iso);
    if (estado == 'programado') {
      // ya muestra hora de liberación en el textoEstado
    } else if (estado == 'cotizacion') {
      textoEstado += ts(servicio['created_at']);
    } else if (estado == 'cotizada') {
      textoEstado += ts(servicio['updated_at']);
    } else if (estado == 'cotizacion_aprobada') {
      textoEstado += ts(servicio['updated_at']);
    } else if (estado == 'pendiente') {
      textoEstado += ts(servicio['created_at']);
    } else if (estado == 'en_ruta_origen') {
      textoEstado += ts(servicio['accepted_at']);
    } else if (estado == 'en_origen') {
      textoEstado += ts(servicio['updated_at']);
    } else if (estado == 'en_ruta_destino') {
      textoEstado += ts(servicio['picked_up_at']);
    } else if (estado == 'finalizado') {
      textoEstado += _fmtHora(servicio['updated_at']); // historial: siempre hora exacta
    } else if (estado == 'caducado' || estado == 'finalizado_por_demora' ||
        estado == 'finalizado_con_problema' || estado == 'cancelado') {
      textoEstado += _fmtHora(servicio['updated_at']);
    }

    String? ticketPOS = servicio['ticket_factura']?.toString();
    String? telCliente = servicio['telefono_receptor']?.toString();

    // Tarifa compacta para el header colapsado (no mostrar en PAP)
    final bool _esPAP = servicio['es_punto_a_punto'] == true;
    final _tarifaDisplay = () {
      if (_esPAP) return '';
      final t = servicio['tarifa'];
      if (t != null && (t as num) > 0) return fmtPeso(t);
      return '';
    }();

    final bool _esDestacada = !esHistorial && _cotizadasRecientes.contains(svcId);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 600),
      margin: _esDestacada
          ? const EdgeInsets.only(bottom: 12)
          : EdgeInsets.zero,
      decoration: _esDestacada
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: Colors.blue.withOpacity(0.55),
                  blurRadius: 22,
                  spreadRadius: 4,
                ),
              ],
            )
          : const BoxDecoration(),
      child: Card(
      elevation: esHistorial ? 1 : 3,
      margin: _esDestacada ? EdgeInsets.zero : const EdgeInsets.only(bottom: 12),
      color: fondoColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: bordeColor, width: _esDestacada ? 2.5 : (esHistorial ? 1.0 : 1.5)),
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
                  // Badge de estado (sin animación)
                  Row(
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
                    if (_tarifaDisplay.isNotEmpty) ...[
                      const SizedBox(width: 4),
                      Text(
                        _tarifaDisplay,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.green[700],
                        ),
                      ),
                      const SizedBox(width: 2),
                    ],
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
                future: _infoMovil(servicio['movil_id']),
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
                        if (data != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8, left: 46),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('💳 Métodos de pago:',
                                    style: TextStyle(fontSize: 11, color: Colors.black54, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 4),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  children: [
                                    if (data['pago_nequi']?.toString().isNotEmpty ?? false)
                                      _chipPagoLocal('Nequi', const Color(0xFFE5007D), Colors.white, data['pago_nequi']),
                                    if (data['pago_daviplata']?.toString().isNotEmpty ?? false)
                                      _chipPagoLocal('Daviplata', const Color(0xFFEE2A24), Colors.white, data['pago_daviplata']),
                                    if (data['pago_bancolombia']?.toString().isNotEmpty ?? false)
                                      _chipPagoLocal('Bancolombia', const Color(0xFFFFCC00), Colors.black, data['pago_bancolombia']),
                                    if (!(data['pago_nequi']?.toString().isNotEmpty ?? false) &&
                                        !(data['pago_daviplata']?.toString().isNotEmpty ?? false) &&
                                        !(data['pago_bancolombia']?.toString().isNotEmpty ?? false))
                                      const Text('No registrados',
                                          style: TextStyle(fontSize: 11, color: Colors.black38, fontStyle: FontStyle.italic)),
                                  ],
                                ),
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
                        // NUEVO SERVICIO CON ESTE MÓVIL — abre el formulario
                        // completo con el móvil activo pre-seleccionado.
                        // El pedido se envía directo a él sin cascada.
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
                                  backgroundColor: Colors.blue[50],
                                  side: BorderSide(color: Colors.blue[300]!, width: 1.5),
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                ),
                                onPressed: () => _abrirFormularioPedido(
                                  context,
                                  perfilEnVivo: widget.usuario,
                                  movilPreselId: data['id'].toString(),
                                  movilPreselLabel: movilLabel(data),
                                ),
                                icon: const Icon(Icons.add_circle_outline, size: 14),
                                label: Text(
                                  'NUEVO PEDIDO — ${movilLabel(data).toUpperCase()}',
                                  style: const TextStyle(
                                      fontSize: 10, fontWeight: FontWeight.bold),
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
                                              destinatarioId: (servicio['movil_id'] as num?)?.toInt(),
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
            // PAP: banner morado en lugar de tarifa
            if (_esPAP) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.purple[900],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.flash_on, size: 15, color: Colors.purpleAccent),
                        SizedBox(width: 6),
                        Text(
                          '⚡ PUNTO A PUNTO — Servicio gratuito',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.purpleAccent,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ] else ...[
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
            ],

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

            // ── Foto de comanda ────────────────────────────────────────
            if ((servicio['foto_comanda_url']?.toString() ?? '').isNotEmpty) ...[
              const SizedBox(height: 10),
              Builder(builder: (ctx) {
                final fotoUrl = servicio['foto_comanda_url'].toString();
                return GestureDetector(
                  onTap: () => showDialog(
                    context: ctx,
                    builder: (_) => Dialog(
                      backgroundColor: Colors.black,
                      insetPadding: const EdgeInsets.all(12),
                      child: Stack(children: [
                        InteractiveViewer(
                          child: Image.network(fotoUrl, fit: BoxFit.contain),
                        ),
                        Positioned(
                          top: 8, right: 8,
                          child: IconButton(
                            icon: const Icon(Icons.close, color: Colors.white),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ),
                      ]),
                    ),
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.brown[200]!),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ClipRRect(
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
                          child: Image.network(
                            fotoUrl,
                            height: 140,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const SizedBox(
                              height: 60,
                              child: Center(child: Icon(Icons.broken_image, color: Colors.grey)),
                            ),
                          ),
                        ),
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.brown[50],
                            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(7)),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          child: Row(children: [
                            const Text('📷', style: TextStyle(fontSize: 12)),
                            const SizedBox(width: 6),
                            Text('Foto de comanda · toca para ver grande',
                                style: TextStyle(fontSize: 11, color: Colors.brown[700])),
                          ]),
                        ),
                      ],
                    ),
                  ),
                );
              }),
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
                    onPressed: () => pedirUbicacionCliente(servicio),
                  ),
                ),
                // Estado: esperando / exacta / aproximada / poco precisa
                IndicadorUbicacionCliente(servicio),
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
    ),                  // Card
  );                    // AnimatedContainer + return
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
      color: const Color(0xFF1C1C1C),
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
                color: Colors.black.withValues(alpha: 0.3),
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
                            fontWeight: FontWeight.bold, fontSize: 15,
                            color: Colors.white)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: const TextStyle(
                            fontSize: 12, color: Colors.white54)),
                    if (secondaryAction != null) ...[
                      const SizedBox(height: 10),
                      secondaryAction,
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right, color: Colors.white24, size: 22),
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
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14,
                            color: Colors.white)),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle,
                          style: const TextStyle(
                              fontSize: 12, color: Colors.white54)),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right, size: 22, color: Colors.white24),
            ],
          ),
        ),
      ),
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
  // ENRUTAR ENCARGO AL MÓVIL ACTIVO (LEGACY — reemplazado por botón en la card)
  // Mantenido temporalmente por si algún otro punto del código lo llama.
  // ─────────────────────────────────────────────────────────────
  void _abrirEnrutarAlMoto(
    BuildContext context,
    Map<String, dynamic> servicio,
    Map<String, dynamic> moto,
  ) {
    final destinoCtrl = TextEditingController();
    final telefonoCtrl = TextEditingController();
    final movilNombre = movilLabel(moto).toUpperCase();

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
            const SizedBox(height: 12),
            const Text('💳 Métodos de pago',
                style: TextStyle(fontSize: 11, color: Colors.black54, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 4, children: [
              if (moto['pago_nequi'] != null && moto['pago_nequi'].toString().isNotEmpty)
                _chipPagoLocal('Nequi', const Color(0xFFE5007D), Colors.white, moto['pago_nequi']),
              if (moto['pago_daviplata'] != null && moto['pago_daviplata'].toString().isNotEmpty)
                _chipPagoLocal('Daviplata', const Color(0xFFEE2A24), Colors.white, moto['pago_daviplata']),
              if (moto['pago_bancolombia'] != null && moto['pago_bancolombia'].toString().isNotEmpty)
                _chipPagoLocal('Bancolombia', const Color(0xFFFFCC00), Colors.black, moto['pago_bancolombia']),
              if ((moto['pago_nequi'] == null || moto['pago_nequi'].toString().isEmpty) &&
                  (moto['pago_daviplata'] == null || moto['pago_daviplata'].toString().isEmpty) &&
                  (moto['pago_bancolombia'] == null || moto['pago_bancolombia'].toString().isEmpty))
                const Text('No registrados',
                    style: TextStyle(fontSize: 11, color: Colors.black38, fontStyle: FontStyle.italic)),
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
