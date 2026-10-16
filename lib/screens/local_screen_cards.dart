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
                          ).showSnackBar(SnackBar(content: Text(textoError(e))));
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
  //   • Diseño oficial (tema_serviexpress): tarjeta blanca, franja del color
  //     del servicio, botones de 48 px con texto.

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
      // Colores fuertes: se leen bien sobre la tarjeta blanca (diseño oficial)
      case 'programado':
        color = const Color(0xFF1565C0);
        icono = Icons.schedule;
        // La hora y la cuenta regresiva en vivo van debajo (CuentaRegresivaRadar)
        textoEstado = 'PROGRAMADO';
        break;
      case 'pendiente':
        if (asignadoDirecto) {
          final et = _etiquetaMovilAsignado(servicio['exclusivo_id'].toString().split(',').first.trim());
          color = const Color(0xFF1565C0);
          icono = Icons.assignment_ind_rounded;
          textoEstado = et != null ? 'ASIGNADO A ${et.toUpperCase()} · ESPERANDO QUE ACEPTE' : 'MÓVIL ASIGNADO · ESPERANDO QUE ACEPTE';
        } else {
          color = const Color(0xFFB26A00);
          icono = Icons.radar;
          textoEstado = 'BUSCANDO MÓVIL';
        }
        break;
      case 'en_curso':
      case 'en_ruta_origen':
        color = kVerdeOscuroSE;
        icono = Icons.two_wheeler;
        textoEstado = 'MÓVIL EN CAMINO AL LOCAL';
        break;
      case 'en_origen':
        color = const Color(0xFFE65100);
        icono = Icons.storefront;
        textoEstado = 'MÓVIL EN EL LOCAL';
        break;
      case 'en_ruta_destino':
        color = kVerdeOscuroSE;
        icono = Icons.delivery_dining;
        textoEstado = 'EN RUTA DE ENTREGA';
        break;
      case 'problema':
        color = const Color(0xFFC62828);
        icono = Icons.warning_amber_rounded;
        textoEstado = 'NOVEDAD REPORTADA';
        break;
      case 'cotizacion':
        color = const Color(0xFFE65100);
        icono = Icons.hourglass_top_rounded;
        textoEstado = 'ESPERANDO PRECIO';
        break;
      case 'cotizada':
        color = const Color(0xFF1565C0);
        icono = Icons.monetization_on;
        textoEstado = 'COTIZACIÓN RECIBIDA';
        break;
      case 'cotizacion_aprobada':
        color = const Color(0xFF00796B);
        icono = Icons.check_circle_outline;
        textoEstado = 'APROBADA · EN ESPERA';
        break;
      case 'finalizado':
        color = const Color(0xFF2E7D32);
        icono = Icons.check_circle;
        textoEstado = 'ENTREGADO';
        break;
      case 'cancelado':
        color = const Color(0xFF616161);
        icono = Icons.block;
        textoEstado = 'CANCELADO';
        break;
      case 'caducado':
        color = const Color(0xFF7B1FA2);
        icono = Icons.hourglass_disabled;
        textoEstado = 'NADIE TOMÓ EL SERVICIO';
        break;
      case 'finalizado_por_demora':
      case 'finalizado_con_problema':
        color = const Color(0xFFE65100);
        icono = Icons.report_problem;
        textoEstado = 'CERRADO CON NOVEDAD';
        break;
      default:
        color = const Color(0xFF616161);
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
    // Color del tipo de servicio (franja de la tarjeta, diseño oficial)
    final EstiloServicio estiloTipo = EstiloServicio.deTipo(servicio['tipo_servicio']?.toString());
    // El tipo solo se muestra si es distinto al que el local tiene en su perfil
    // (ej. un local de comida que pide un mototaxi).
    final String tipoPerfil = (widget.usuario['tipo_servicio_defecto'] ?? 'COMIDA').toString(); // mismo valor por defecto del formulario
    final bool tipoDistinto = !esPAP &&
        (servicio['tipo_servicio'] ?? '').toString().trim().isNotEmpty &&
        EstiloServicio.deTipo(servicio['tipo_servicio']?.toString()) != EstiloServicio.deTipo(tipoPerfil);
    final bool esRecogidaLocal = (servicio['tipo_servicio'] ?? '').toString().toUpperCase() == 'RECOGIDA LOCAL';
    final String destinoTexto = servicio['destino']?.toString().trim() ?? '';

    final bool destacada = !esHistorial && _cotizadasRecientes.contains(svcId);

    // ─────────────────────────────────────────────────────────────────────
    Widget cabecera() => InkWell(
          onTap: toggleExpansion,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(icono, size: 15, color: color),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(textoEstado,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.3)),
                      ),
                    ]),
                  ),
                ),
                if (tiempo.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(tiempo, style: const TextStyle(color: Colors.black54, fontSize: 12)),
                ],
                const Spacer(),
                Text('#${servicio['numero_local'] ?? servicio['id']}',
                    style: const TextStyle(color: Colors.black54, fontWeight: FontWeight.bold, fontSize: 13)),
                Icon(estaExpandida ? Icons.expand_less : Icons.expand_more, color: Colors.black54, size: 24),
              ]),
              const SizedBox(height: 10),
              // Dirección de entrega: con título y sin cortarse
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(esPAP ? Icons.flash_on : Icons.location_on_rounded,
                      size: 22, color: estiloTipo.colorIcono),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      esPAP ? 'Punto a punto' : (esRecogidaLocal ? 'Pedido' : 'Entregar en'),
                      style: const TextStyle(color: Colors.black54, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      esPAP ? (servicio['origen']?.toString() ?? '') : (destinoTexto.isEmpty ? '—' : destinoTexto),
                      maxLines: estaExpandida ? null : 2,
                      overflow: estaExpandida ? TextOverflow.visible : TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.black87, fontSize: 16, fontWeight: FontWeight.w800, height: 1.25),
                    ),
                  ]),
                ),
                if (hayTarifa) ...[
                  const SizedBox(width: 8),
                  Text(fmtPeso(tarifa),
                      style: const TextStyle(color: kVerdeOscuroSE, fontSize: 18, fontWeight: FontWeight.w800)),
                ],
              ]),
              if (tipoDistinto) ...[
                const SizedBox(height: 8),
                EtiquetaSE(estiloTipo.nombreCorto, estiloTipo.color),
              ],
              // Programado: cuenta regresiva en vivo hasta salir al radar
              if (!esHistorial &&
                  servicio['liberacion_at'] != null &&
                  (estado == 'programado' ||
                      (estado == 'cotizacion_aprobada' &&
                          (DateTime.tryParse(servicio['liberacion_at'].toString())
                                  ?.isAfter(DateTime.now()) ??
                              false)))) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    CuentaRegresivaRadar(
                      liberacionAt: servicio['liberacion_at'],
                      color: const Color(0xFF1565C0),
                      tamano: 15,
                    ),
                    if (estado == 'programado')
                      SizedBox(
                        height: 48,
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.send_rounded, size: 18),
                          label: const Text('Enviar ya',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF1565C0),
                            side: const BorderSide(color: Color(0xFF1565C0)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadioCampoSE)),
                          ),
                          onPressed: () => enviarProgramadoYa(
                              context, servicio['id'],
                              localId: widget.usuario['id']),
                        ),
                      ),
                  ],
                ),
              ],
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
                          color: i == 0 ? Colors.transparent : (i <= actual ? color : Colors.black12))),
                  Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i < actual ? color : (i == actual ? color.withValues(alpha: 0.2) : kCampoSE),
                      border: Border.all(color: i <= actual ? color : Colors.black26, width: 2),
                    ),
                    child: i < actual ? const Icon(Icons.check, size: 10, color: Colors.white) : null,
                  ),
                  Expanded(
                      child: Container(
                          height: 2,
                          color: i == pasos.length - 1 ? Colors.transparent : (i < actual ? color : Colors.black12))),
                ]),
                const SizedBox(height: 4),
                Text(pasos[i].$1,
                    style: TextStyle(
                        fontSize: 11,
                        color: i <= actual ? Colors.black87 : Colors.black45,
                        fontWeight: i == actual ? FontWeight.w800 : FontWeight.normal)),
                Text(pasos[i].$2 != null && i <= actual ? hora(pasos[i].$2) : ' ',
                    style: const TextStyle(fontSize: 10, color: Colors.black54)),
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

            // Botón con ícono + texto (mín. 48 px, nada escondido solo en ícono)
            Widget botonIcono(IconData ic, Color c, String tip, VoidCallback onTap, {bool alerta = false}) =>
                InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 64, minHeight: 52),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                    decoration: BoxDecoration(
                      color: (alerta ? Colors.red : c).withValues(alpha: alerta ? 0.9 : 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(ic, size: 20, color: alerta ? Colors.white : c),
                      const SizedBox(height: 2),
                      Text(tip,
                          style: TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w700, color: alerta ? Colors.white : c)),
                    ]),
                  ),
                );

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: kCampoSE, borderRadius: BorderRadius.circular(kRadioCampoSE)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  CircleAvatar(
                    radius: 22,
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
                          style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w800, fontSize: 15)),
                      if (esMovil && data['nombre'] != null)
                        Text(data['nombre'].toString().toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.black54, fontSize: 12)),
                    ]),
                  ),
                ]),
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  if (telefonoReal.isNotEmpty)
                    botonIcono(iconoWhatsApp, const Color(0xFF128C7E), 'WhatsApp', () async {
                      // En computador: WhatsApp Web en la pestaña de ServiExpress
                      await abrirChatWhatsApp(telefonoReal);
                    }),
                  botonIcono(
                    chatNuevo ? Icons.mark_email_unread : (esHistorial ? Icons.history : Icons.chat_bubble_outline),
                    const Color(0xFF1565C0),
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
                  botonIcono(Icons.badge_outlined, Colors.black87, 'Ver perfil', () => _verPerfilMovilLocal(context, data)),
                ]),
                const SizedBox(height: 10),
                // Pagos: siempre visibles, con botón de copiar
                if (pagos.isEmpty)
                  const Text('Sin métodos de pago registrados',
                      style: TextStyle(color: Colors.black54, fontSize: 12, fontStyle: FontStyle.italic))
                else
                  ...pagos.map((p) => Container(
                        margin: const EdgeInsets.only(top: 6),
                        padding: const EdgeInsets.fromLTRB(10, 2, 2, 2),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border(left: BorderSide(color: p.$2, width: 4)),
                        ),
                        child: Row(children: [
                          SizedBox(
                            width: 90,
                            child: Text(p.$1,
                                style: const TextStyle(color: Colors.black54, fontSize: 13, fontWeight: FontWeight.bold)),
                          ),
                          Expanded(
                            child: Text(p.$3,
                                style: const TextStyle(
                                    color: Colors.black87, fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                          ),
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFF1565C0),
                              minimumSize: const Size(48, 48),
                            ),
                            icon: const Icon(Icons.copy_rounded, size: 18),
                            label: const Text('Copiar', style: TextStyle(fontWeight: FontWeight.w700)),
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
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF1565C0),
                        side: const BorderSide(color: Color(0xFF1565C0)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadioCampoSE)),
                      ),
                      onPressed: () => _abrirFormularioPedido(
                        context,
                        perfilEnVivo: widget.usuario,
                        movilPreselId: data['id'].toString(),
                        movilPreselLabel: movilLabel(data),
                      ),
                      icon: const Icon(Icons.add_circle_outline, size: 18),
                      label: Text('Nuevo pedido con ${movilLabel(data)}',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ]),
            );
          },
        );

    // ── Fila de dato con ícono ───────────────────────────────────────────
    Widget dato(IconData ic, Widget contenido, {Widget? accion}) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(padding: const EdgeInsets.only(top: 1), child: Icon(ic, size: 20, color: Colors.black54)),
            const SizedBox(width: 10),
            Expanded(child: contenido),
            if (accion != null) accion,
          ]),
        );
    // Título pequeño + valor (ej. "Ticket" / "#40")
    Widget tituloValor(String titulo, String valor, {Color? colorValor}) =>
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(titulo, style: const TextStyle(color: Colors.black54, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(valor,
              style: TextStyle(
                  color: colorValor ?? Colors.black87, fontSize: 15, fontWeight: FontWeight.w700, height: 1.3)),
        ]);
    // Botón chico con ícono + texto (48 px de alto)
    Widget botonDato(String texto, IconData ic, Color c, VoidCallback onTap) => SizedBox(
          height: 48,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: c,
              side: BorderSide(color: c.withValues(alpha: 0.5)),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadioCampoSE)),
            ),
            onPressed: onTap,
            icon: Icon(ic, size: 18),
            label: Text(texto, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          ),
        );

    final String telCliente = servicio['telefono_receptor']?.toString().trim() ?? '';
    final String ticket = servicio['ticket_factura']?.toString().trim() ?? '';
    // Nota: solo lo que escribió el local. Sin etiquetas internas
    // ([ COMIDA ], [ TICKET: #… ], [⏰ PROGRAMADO: …]) ni las instrucciones
    // de recogida del perfil del local.
    final String nota = (servicio['observacion']?.toString() ?? '')
        .replaceAll(RegExp(r'\n?\s*•\s*Recogida:[^\n]*'), '')
        .replaceAll(RegExp(r'\[\s*TICKET:[^\]]*\]'), '')
        .replaceAll(RegExp(r'\[\s*⏰[^\]]*\]'), '')
        .replaceAll(RegExp(r'\[\s*[A-ZÁÉÍÓÚÑ ]+\s*\]'), '')
        .replaceAll(RegExp(r'^[\s·—-]+'), '')
        .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
        .trim();
    final String fotoComanda = servicio['foto_comanda_url']?.toString() ?? '';
    final int recargo = (servicio['recargo_total'] as num?)?.toInt() ?? 0;

    // Contacto del cliente: botones visibles (número o @usuario de WhatsApp;
    // con @usuario no se puede llamar).
    final Uri? uriTelCliente = uriLlamada(telCliente);
    final Uri? uriWaCliente = uriWhatsApp(telCliente);
    final bool esUsuarioWa = esUsuarioWhatsApp(telCliente);
    void copiar(String texto, String aviso) {
      Clipboard.setData(ClipboardData(text: texto));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(aviso),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ));
    }

    final double? destLat = (servicio['destino_lat'] as num?)?.toDouble();
    final double? destLng = (servicio['destino_lng'] as num?)?.toDouble();

    Widget botonPrincipal(String texto, IconData? ic, Color c, VoidCallback onTap) => SizedBox(
          height: 54,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: c,
              foregroundColor: sobreColorSE(c),
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: onTap,
            icon: Icon(ic ?? Icons.check, size: 20),
            label: Text(texto, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          ),
        );
    Widget botonSecundario(String texto, Color c, VoidCallback? onTap, {IconData? ic}) => SizedBox(
          height: 48,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: c,
              side: BorderSide(color: c.withValues(alpha: 0.6)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadioCampoSE)),
            ),
            onPressed: onTap,
            icon: Icon(ic ?? Icons.close, size: 18),
            label: Text(texto, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          ),
        );

    // ── Cuerpo ────────────────────────────────────────────────────────────
    Widget cuerpo() => Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Divider(color: Colors.black12, height: 1),
            const SizedBox(height: 14),
            if (!esPAP && ['pendiente', 'en_curso', 'en_ruta_origen', 'en_origen', 'en_ruta_destino',
                    'problema', 'finalizado'].contains(estado))
              lineaAvance(),
            if (servicio['movil_id'] != null) bloqueMovil(),

            // ── Datos del pedido ──────────────────────────────────────────
            // Dirección de entrega: copiar / ver en mapa
            if (!esPAP && !esRecogidaLocal && destinoTexto.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Wrap(spacing: 8, runSpacing: 8, children: [
                  botonDato('Copiar dirección', Icons.copy_rounded, Colors.black87,
                      () => copiar(destinoTexto, 'Dirección copiada')),
                  if (destLat != null && destLng != null)
                    botonDato('Ver en mapa', Icons.map_outlined, const Color(0xFF1565C0), () {
                      launchUrl(
                        Uri.parse('https://www.google.com/maps/search/?api=1&query=$destLat,$destLng'),
                        mode: LaunchMode.externalApplication,
                      );
                    }),
                ]),
              ),
            if (ticket.isNotEmpty)
              dato(Icons.receipt_long, tituloValor('Ticket / factura', '#$ticket')),
            if (telCliente.isNotEmpty)
              dato(
                Icons.person_outline,
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  tituloValor('Cliente', telCliente),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    if (uriWaCliente != null)
                      botonDato('WhatsApp', iconoWhatsApp, const Color(0xFF128C7E),
                          () => abrirChatWhatsApp(telCliente)),
                    if (uriTelCliente != null)
                      botonDato('Llamar', Icons.call, const Color(0xFF1565C0), () => launchUrl(uriTelCliente)),
                    botonDato(esUsuarioWa ? 'Copiar usuario' : 'Copiar número', Icons.copy_rounded,
                        Colors.black87, () => copiar(telCliente, esUsuarioWa ? 'Usuario copiado' : 'Número copiado')),
                  ]),
                ]),
              ),
            if (nota.isNotEmpty)
              dato(Icons.sticky_note_2_outlined, tituloValor('Nota', nota)),
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
                        style: TextStyle(color: Colors.black54, fontSize: 13)),
                  ]),
                ),
              ),

            // Precio
            if (esPAP)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: 2, bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3E5F5),
                  borderRadius: BorderRadius.circular(kRadioCampoSE),
                ),
                child: const Text('⚡ PUNTO A PUNTO — Servicio gratuito',
                    style: TextStyle(color: Color(0xFF7B1FA2), fontWeight: FontWeight.w800, fontSize: 14)),
              )
            else
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: 2, bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  color: estado == 'cotizacion' ? kAvisoSE : kCampoSE,
                  borderRadius: BorderRadius.circular(kRadioCampoSE),
                ),
                child: estado == 'cotizacion'
                    ? const Row(children: [
                        Icon(Icons.hourglass_top_rounded, size: 18, color: Color(0xFFE65100)),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text('Esperando el precio de la Central…',
                              style: TextStyle(color: Color(0xFFE65100), fontWeight: FontWeight.w800, fontSize: 14)),
                        ),
                      ])
                    : Row(children: [
                        const Text('Tarifa', style: TextStyle(color: Colors.black54, fontSize: 13, fontWeight: FontWeight.w600)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: recargo > 0 && hayTarifa
                              ? Text('base ${fmtPeso(tarifaNum - recargo)} + recargo ${fmtPeso(recargo)}',
                                  style: const TextStyle(color: Colors.black54, fontSize: 12))
                              : const SizedBox.shrink(),
                        ),
                        Text(hayTarifa ? fmtPeso(tarifa) : '—',
                            style: const TextStyle(color: kVerdeOscuroSE, fontWeight: FontWeight.w800, fontSize: 20)),
                      ]),
              ),

            // Ubicación del cliente
            if (!esHistorial && !terminado) ...[
              IndicadorUbicacionCliente(servicio),
            ],

            // ── Acciones ──────────────────────────────────────────────────
            const SizedBox(height: 10),
            if (!esHistorial) ...[
              if (estado == 'cotizada')
                Row(children: [
                  Expanded(
                      child: botonSecundario('Rechazar', const Color(0xFFC62828), () => _cancelarPedido(servicio['id']))),
                  const SizedBox(width: 8),
                  Expanded(
                      flex: 2,
                      child: botonPrincipal('Aprobar precio', Icons.check, const Color(0xFF1565C0),
                          () => _completarDatosYAprobar(context, servicio))),
                ])
              else if (estado == 'cotizacion_aprobada') ...[
                Text('Precio aprobado: ${fmtPeso(tarifa)}. Cuando el pedido esté listo, solicita el Móvil.',
                    style: const TextStyle(color: Color(0xFF00796B), fontSize: 14, fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                      child: botonSecundario('Cancelar', const Color(0xFFC62828), () => _cancelarPedido(servicio['id']))),
                  const SizedBox(width: 8),
                  Expanded(
                      flex: 2,
                      child: botonPrincipal('Solicitar Móvil', Icons.two_wheeler, const Color(0xFF00796B),
                          () => _solicitarMovilAprobado(context, servicio))),
                ]),
              ],
              if (!terminado) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: botonSecundario('Pedir ubicación al cliente', const Color(0xFF1565C0),
                      () => pedirUbicacionCliente(servicio), ic: Icons.my_location),
                ),
                if (estado == 'pendiente' || estado == 'cotizacion') ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: botonSecundario(estado == 'cotizacion' ? 'Descartar pedido' : 'Cancelar pedido',
                        const Color(0xFFC62828), () => _cancelarPedido(servicio['id'])),
                  ),
                ],
              ],
            ],

            // Historial: calificar / ocultar / eliminar
            if (esHistorial && estado == 'finalizado' && servicio['movil_id'] != null) ...[
              if (servicio['calificacion_local'] == null)
                SizedBox(
                  width: double.infinity,
                  child: botonPrincipal('Calificar Móvil', Icons.star_rate_rounded, Colors.amber,
                      () => _mostrarDialogoCalificacion(servicio)),
                )
              else
                Row(children: [
                  const Text('Tu calificación', style: TextStyle(color: Colors.black54, fontSize: 13)),
                  const Spacer(),
                  ...List.generate(
                      5,
                      (i) => Icon(i < (servicio['calificacion_local'] as int) ? Icons.star : Icons.star_border,
                          color: Colors.amber[700], size: 20)),
                ]),
              const SizedBox(height: 8),
            ],
            if (esHistorial && !esGlobal)
              SizedBox(
                width: double.infinity,
                child: botonSecundario('Ocultar del tablero de hoy', Colors.black54, onOcultar, ic: Icons.archive),
              ),
            if (esGlobal)
              SizedBox(
                width: double.infinity,
                child: botonSecundario('Eliminar para siempre', const Color(0xFFC62828), onEliminar, ic: Icons.delete),
              ),
          ]),
        );

    // Tarjeta clara del diseño oficial: blanca, radio 18, franja del color del
    // servicio y sombra suave. Una cotización recién respondida se resalta.
    final Color acento = estiloTipo.color;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 600),
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(kRadioTarjetaSE),
        border: destacada ? Border.all(color: const Color(0xFF1565C0), width: 2.5) : null,
        boxShadow: [
          if (destacada)
            BoxShadow(color: const Color(0xFF2F80ED).withValues(alpha: 0.55), blurRadius: 22, spreadRadius: 2)
          else
            BoxShadow(color: acento.withValues(alpha: 0.18), blurRadius: 18, offset: const Offset(0, 6)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(kRadioTarjetaSE),
        child: Stack(children: [
          Padding(
            padding: const EdgeInsets.only(left: 5),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              cabecera(),
              if (estaExpandida) cuerpo(),
            ]),
          ),
          // Franja del color del servicio
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Container(width: 5, color: esHistorial ? acento.withValues(alpha: 0.5) : acento),
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

        if (diff > 60) {
          // Programado a una hora: se muestra la hora exacta
          textoEstado = 'PROGRAMADO · ${textoProgramado(lib).toUpperCase()}';
        } else if (diff > 0) {
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
                                    icon: const Icon(iconoWhatsApp, size: 16),
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
                                      // En computador: WhatsApp Web en la
                                      // pestaña de ServiExpress
                                      await abrirChatWhatsApp(telefonoReal);
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
                // El cliente ya mandó su ubicación por WhatsApp: pegar el enlace
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.teal[700],
                      side: BorderSide(color: Colors.teal[300]!),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    icon: const Icon(Icons.add_location_alt, size: 16),
                    label: const Text(
                      'PEGAR UBICACIÓN QUE MANDÓ EL CLIENTE',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 11),
                    ),
                    onPressed: () => pegarUbicacionEnServicio(context, servicio),
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
              keyboardType: TextInputType.text,
              autocorrect: false,
              enableSuggestions: false,
              inputFormatters: formatoWhatsApp,
              decoration: const InputDecoration(
                labelText: 'WhatsApp receptor (opcional)',
                helperText: 'Número o @usuario de WhatsApp',
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
                    'telefono_receptor': normalizarWhatsApp(telefonoCtrl.text),
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
