// ignore_for_file: use_build_context_synchronously
part of 'central_screen.dart';

extension CentralScreenFormularios on _CentralScreenState {

  void _abrirFormularioDespacho(BuildContext context) {
    final origenController = TextEditingController();
    final destinoController = TextEditingController();
    final tarifaController = TextEditingController();
    final telReceptorController = TextEditingController();
    final telEmisorController = TextEditingController();
    final detallesController = TextEditingController();

    String tipoServicio = 'PAQUETERÍA';
    bool procesando = false;
    // Coordenadas del Local elegido por autocompletado — null si
    // todavía no se seleccionó nada de la lista (texto libre).
    double? origenLatCapturada;
    double? origenLngCapturada;

    // Desglose del precio capturado por CampoTarifaInteligente.
    Map<String, dynamic>? detalleActual;

    // Red de direcciones — se carga una vez al abrir el formulario
    List<String> redDireccionesCentral = [];
    List<String> sugerenciasDestino = [];
    Supabase.instance.client
        .from('red_direcciones')
        .select('nombre, municipio')
        .eq('activo', true)
        .order('nombre', ascending: true)
        .then((data) {
      redDireccionesCentral = List<Map<String, dynamic>>.from(data)
          .map((e) => '${e['nombre']} (${e['municipio']})')
          .toList();
    });

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          // FIX: el insetPadding por defecto de AlertDialog (40px a
          // cada lado) se come buena parte del ancho en un celular
          // angosto — por eso se sentía apretado y el texto se
          // cortaba. Lo reducimos y forzamos el contenido a usar
          // todo el ancho disponible en vez de encogerse solo.
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 24,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          title: const Text(
            'NUEVO SERVICIO MANUAL',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'TIPO DE SERVICIO',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.black54,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: ['PAQUETERÍA', 'COMIDA', 'COMPRAS', 'MOTOTAXI'].map(
                    (tipo) {
                      final bool seleccionado = tipoServicio == tipo;
                      return ChoiceChip(
                        label: Text(
                          tipo,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: seleccionado ? Colors.white : Colors.black87,
                          ),
                        ),
                        selected: seleccionado,
                        selectedColor: Colors.black,
                        backgroundColor: Colors.grey[200],
                        onSelected: (val) {
                          if (val) {
                            setDialogState(() {
                              tipoServicio = tipo;
                              if (tipo != 'PAQUETERÍA') {
                                telEmisorController.clear();
                              }
                            });
                          }
                        },
                      );
                    },
                  ).toList(),
                ),
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 16),

                Autocomplete<Map<String, dynamic>>(
                  displayStringForOption: (local) =>
                      (local['nombre'] ?? '').toString(),
                  optionsBuilder: (TextEditingValue valorTexto) async {
                    final texto = valorTexto.text.trim();
                    if (texto.length < 2) {
                      return const Iterable<Map<String, dynamic>>.empty();
                    }
                    try {
                      final resultados = await Supabase.instance.client
                          .from('usuarios')
                          .select('id, nombre, lat_fija, lng_fija')
                          .eq('rol', 'local')
                          .ilike('nombre', '%$texto%')
                          .limit(5);
                      return (resultados as List)
                          .cast<Map<String, dynamic>>();
                    } catch (_) {
                      return const Iterable<Map<String, dynamic>>.empty();
                    }
                  },
                  onSelected: (local) {
                    origenController.text = (local['nombre'] ?? '').toString();
                    setDialogState(() {
                      origenLatCapturada = local['lat_fija'] != null
                          ? (local['lat_fija'] as num).toDouble()
                          : null;
                      origenLngCapturada = local['lng_fija'] != null
                          ? (local['lng_fija'] as num).toDouble()
                          : null;
                    });
                  },
                  fieldViewBuilder:
                      (context, fieldController, focusNode, onFieldSubmitted) {
                    // Mantiene sincronizado el controller externo
                    // (origenController, usado por el resto del
                    // formulario) con el campo de autocompletado.
                    return TextField(
                      controller: fieldController,
                      focusNode: focusNode,
                      textInputAction: TextInputAction.next,
                      onChanged: (val) => origenController.text = val,
                      onSubmitted: (_) => onFieldSubmitted(),
                      decoration: InputDecoration(
                        labelText: tipoServicio == 'COMIDA'
                            ? 'Restaurante (*)'
                            : tipoServicio == 'COMPRAS'
                            ? 'Lugar de compra (*)'
                            : 'Punto de Recogida (*)',
                        helperText: origenLatCapturada != null
                            ? '📍 Ubicación guardada de este local'
                            : 'Escribe 2+ letras para ver locales registrados',
                        helperStyle: TextStyle(
                          fontSize: 10,
                          color: origenLatCapturada != null
                              ? Colors.green[700]
                              : Colors.grey[500],
                        ),
                        border: const OutlineInputBorder(),
                        isDense: true,
                        prefixIcon: Icon(
                          tipoServicio == 'COMIDA'
                              ? Icons.restaurant
                              : tipoServicio == 'COMPRAS'
                              ? Icons.shopping_cart
                              : Icons.storefront,
                          size: 18,
                        ),
                      ),
                    );
                  },
                  optionsViewBuilder: (context, onSelected, options) {
                    return Align(
                      alignment: Alignment.topLeft,
                      child: Material(
                        elevation: 4,
                        borderRadius: BorderRadius.circular(8),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 200),
                          child: ListView.builder(
                            padding: EdgeInsets.zero,
                            shrinkWrap: true,
                            itemCount: options.length,
                            itemBuilder: (context, index) {
                              final local = options.elementAt(index);
                              final bool tieneUbicacion =
                                  local['lat_fija'] != null;
                              return ListTile(
                                dense: true,
                                leading: Icon(
                                  Icons.storefront,
                                  size: 18,
                                  color: tieneUbicacion
                                      ? Colors.green[700]
                                      : Colors.grey[400],
                                ),
                                title: Text(
                                  (local['nombre'] ?? '').toString(),
                                  style: const TextStyle(fontSize: 13),
                                ),
                                trailing: tieneUbicacion
                                    ? const Icon(
                                        Icons.check_circle,
                                        size: 14,
                                        color: Colors.green,
                                      )
                                    : null,
                                onTap: () => onSelected(local),
                              );
                            },
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),

                if (tipoServicio == 'PAQUETERÍA') ...[
                  TextField(
                    controller: telEmisorController,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Teléfono de quien envía (Opcional)',
                      border: OutlineInputBorder(),
                      isDense: true,
                      prefixIcon: Icon(Icons.phone, size: 18),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                TextField(
                  controller: destinoController,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: tipoServicio == 'MOTOTAXI'
                        ? 'Punto de Destino (*)'
                        : 'Dirección de Entrega (*)',
                    border: const OutlineInputBorder(),
                    isDense: true,
                    prefixIcon: const Icon(Icons.flag, size: 18),
                  ),
                  onChanged: (texto) {
                    if (texto.length < 2) {
                      setDialogState(() => sugerenciasDestino = []);
                      return;
                    }
                    final t = texto.toLowerCase();
                    setDialogState(() {
                      sugerenciasDestino = redDireccionesCentral
                          .where((d) => d.toLowerCase().contains(t))
                          .take(5)
                          .toList();
                    });
                  },
                ),

                // Sugerencias de la red de direcciones
                if (sugerenciasDestino.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6, bottom: 4),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: sugerenciasDestino.map((zona) => InkWell(
                        onTap: () {
                          destinoController.text = '$zona - ';
                          setDialogState(() => sugerenciasDestino = []);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 7),
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.grey[400]!),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.location_city,
                                  color: Colors.grey[600], size: 14),
                              const SizedBox(width: 4),
                              Text(zona,
                                  style: TextStyle(
                                    color: Colors.grey[800],
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  )),
                            ],
                          ),
                        ),
                      )).toList(),
                    ),
                  ),

                const SizedBox(height: 12),

                TextField(
                  controller: telReceptorController,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: tipoServicio == 'MOTOTAXI'
                        ? 'Teléfono del Pasajero'
                        : tipoServicio == 'PAQUETERÍA'
                        ? 'Teléfono de quien recibe'
                        : 'Teléfono de Contacto',
                    border: const OutlineInputBorder(),
                    isDense: true,
                    prefixIcon: const Icon(Icons.phone_android, size: 18),
                  ),
                ),
                const SizedBox(height: 12),

                TextField(
                  controller: detallesController,
                  maxLines:
                      (tipoServicio == 'COMIDA' || tipoServicio == 'COMPRAS')
                      ? 3
                      : 2,
                  decoration: InputDecoration(
                    labelText: tipoServicio == 'COMIDA'
                        ? '¿Qué vas a pedir?'
                        : tipoServicio == 'COMPRAS'
                        ? 'Lista de productos'
                        : 'Detalles / Notas (Opcional)',
                    border: const OutlineInputBorder(),
                    isDense: true,
                    prefixIcon: const Icon(Icons.notes, size: 18),
                  ),
                ),
                const SizedBox(height: 12),

                // MOTOR DE TARIFAS — sugiere precio basado en historial,
                // incluye panel de recargos (lluvia/nocturno/sobrecarga).
                CampoTarifaInteligente(
                  origenController: origenController,
                  destinoController: destinoController,
                  tarifaController: tarifaController,
                  tipoServicio: tipoServicio,
                  onDetalleChanged: (d) => detalleActual = d,
                ),
              ],
            ),
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
                      if (origenController.text.trim().isEmpty ||
                          destinoController.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Origen y Destino son obligatorios.'),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }

                      // La cotización (precio vacío) existe para que Local
                      // o Cliente le pidan un precio a Central. No tiene
                      // sentido que Central se pida una cotización a sí
                      // misma — siempre debe poner el precio final.
                      final String tarifaSinFormato = tarifaController.text
                          .replaceAll('\$', '')
                          .replaceAll('.', '')
                          .replaceAll(',', '')
                          .trim();
                      final double tarifaValidada =
                          double.tryParse(tarifaSinFormato) ?? 0.0;
                      if (tarifaValidada <= 0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'La tarifa es obligatoria. Central no puede '
                              'dejarla vacía para cotización.',
                            ),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }

                      setDialogState(() => procesando = true);

                      String tarifaLimpia = tarifaController.text
                          .replaceAll('\$', '')
                          .replaceAll('.', '')
                          .replaceAll(',', '')
                          .trim();
                      double tarifaFinal = double.tryParse(tarifaLimpia) ?? 0.0;

                      String telReceptor = telReceptorController.text.trim();
                      String telEmisor = telEmisorController.text.trim();
                      String detalles = detallesController.text.trim();
                      String observacionFinal = '';

                      if (tipoServicio == 'PAQUETERÍA') {
                        observacionFinal = '[ PAQUETERÍA ]';
                        if (telEmisor.isNotEmpty) { observacionFinal += ' - 📞 Envía: $telEmisor'; }
                        if (telReceptor.isNotEmpty) { observacionFinal += ' | 📞 Recibe: $telReceptor'; }
                        if (detalles.isNotEmpty) { observacionFinal += '\n$detalles'; }
                      } else if (tipoServicio == 'COMIDA') {
                        observacionFinal = '[ COMIDA ] - 🍔 PEDIDO:\n$detalles';
                        if (telReceptor.isNotEmpty) { observacionFinal += '\n---\n📞 Tel: $telReceptor'; }
                      } else if (tipoServicio == 'COMPRAS') {
                        observacionFinal = '[ COMPRAS ] - 🛒 LISTA:\n$detalles';
                        if (telReceptor.isNotEmpty) { observacionFinal += '\n---\n📞 Tel: $telReceptor'; }
                      } else if (tipoServicio == 'MOTOTAXI') {
                        observacionFinal = '[ MOTOTAXI ]';
                        if (telReceptor.isNotEmpty) { observacionFinal += ' - 📱 Pasajero: $telReceptor'; }
                        if (detalles.isNotEmpty) { observacionFinal += '\n$detalles'; }
                      }

                      try {
                        // ---> UNIFICACIÓN: ESCÁNER MULTI-PARADERO DESDE CENTRAL <---
                        String? exclusivoIdCampo;
                        List<String> pilotosSeleccionadosIds = [];

                        // Regla de capacidad por rango (igual que dentro de
                        // la app): NOVATO/PRO no reciben nada si ya tienen
                        // un servicio activo; ELITE/LEYENDA/MASTER mientras
                        // les quede cupo. Se resuelve en SQL para no
                        // repetir esta lógica en cada ola por separado.
                        Set<String> idsElegiblesPorCapacidad = {};
                        try {
                          final elegibles = await Supabase.instance.client
                              .rpc(
                                'moviles_elegibles_notificacion',
                                params: {
                                  'p_solo_master': false,
                                  // T=0: el #1 de paradero debe estar
                                  // completamente libre — el cupo de 2/3
                                  // pedidos no aplica al turno inicial,
                                  // solo a partir de +2min/+5min.
                                  'p_solo_completamente_libres': true,
                                },
                              );
                          idsElegiblesPorCapacidad = (elegibles as List)
                              .map((e) => e['id'].toString())
                              .toSet();
                        } catch (_) {
                          // Si la función no existe todavía (falta correr
                          // el SQL), no bloqueamos el despacho — solo no
                          // filtramos por capacidad esta vez.
                        }

                        if (tarifaFinal > 0) {
                          final serviciosPendientes = await Supabase
                              .instance
                              .client
                              .from('servicios')
                              .select('exclusivo_id')
                              .eq('estado', 'pendiente')
                              .not('exclusivo_id', 'is', null);

                          List<String> ocupados = [];
                          for (var s in serviciosPendientes) {
                            ocupados.addAll(
                              s['exclusivo_id']
                                  .toString()
                                  .split(',')
                                  .map((e) => e.trim()),
                            );
                          }

                          final movilesLibres = await Supabase.instance.client
                              .from('usuarios')
                              .select('id, paradero_actual, ingreso_fila')
                              .eq('rol', 'movil')
                              .eq('en_linea', true)
                              .not('paradero_actual', 'is', null);

                          Map<String, List<Map<String, dynamic>>>
                          gruposParaderos = {};
                          for (var m in movilesLibres) {
                            String pName = m['paradero_actual']
                                .toString()
                                .trim()
                                .toLowerCase();
                            gruposParaderos.putIfAbsent(pName, () => []).add(m);
                          }

                          // Extraemos el #1 de cada paradero disponible que
                          // no esté ocupado NI bloqueado por capacidad de
                          // su rango — si el #1 es Novato/Pro y está
                          // ocupado, pasamos al siguiente de la fila.
                          gruposParaderos.forEach((pName, listaFila) {
                            listaFila.sort(
                              (a, b) =>
                                  DateTime.parse(
                                    a['ingreso_fila'] ??
                                        DateTime.now().toIso8601String(),
                                  ).compareTo(
                                    DateTime.parse(
                                      b['ingreso_fila'] ??
                                          DateTime.now().toIso8601String(),
                                    ),
                                  ),
                            );

                            for (var candidato in listaFila) {
                              String candId = candidato['id'].toString();
                              final bool elegible =
                                  idsElegiblesPorCapacidad.isEmpty ||
                                  idsElegiblesPorCapacidad.contains(candId);
                              if (!ocupados.contains(candId) && elegible) {
                                pilotosSeleccionadosIds.add(candId);
                                break;
                              }
                            }
                          });

                          if (pilotosSeleccionadosIds.isNotEmpty) {
                            exclusivoIdCampo = pilotosSeleccionadosIds.join(
                              ',',
                            );
                          }
                        }

                        // FALLBACK DE UBICACIÓN — si el autocompletado no
                        // encontró un local con base sellada, usamos las
                        // coordenadas del paradero MEMOS como punto de
                        // partida. Sin esto, un servicio sin ubicación
                        // reconocida nunca podría medir el radio de 1km
                        // en la ola zonal de +2min.
                        if (origenLatCapturada == null ||
                            origenLngCapturada == null) {
                          origenLatCapturada = 7.863976;
                          origenLngCapturada = -72.479256;
                        }

                        // INSERCIÓN EN BD CON MULTI-ID DE PARADERO
                        final insertedSvc = await Supabase.instance.client
                            .from('servicios')
                            .insert({
                              'origen': origenController.text
                                  .trim()
                                  .toUpperCase(),
                              'destino': destinoController.text
                                  .trim()
                                  .toUpperCase(),
                              'telefono_receptor': telReceptor.isEmpty
                                  ? null
                                  : telReceptor,
                              'tarifa': tarifaFinal,
                              'tarifa_detalle': detalleActual ??
                                  {'total': tarifaFinal, 'fuente': 'central'},
                              'observacion': observacionFinal,
                              'estado': tarifaFinal > 0
                                  ? 'pendiente'
                                  : 'cotizacion',
                              'creador': 'Central',
                              // FIX: el tipo seleccionado en los chips
                              // (PAQUETERÍA/COMIDA/COMPRAS/MOTOTAXI) se
                              // capturaba pero nunca se guardaba — el
                              // servicio quedaba con el valor por
                              // defecto 'Normal' sin importar qué se
                              // eligiera. Por eso la tarjeta del moto
                              // nunca pudo hablar distinto para un
                              // mototaxi vs. una entrega.
                              'tipo_servicio': tipoServicio,
                              'metodo_pago': 'Efectivo',
                              'archivado': false,
                              'exclusivo_id': exclusivoIdCampo,
                              if (origenLatCapturada != null)
                                'origen_lat': origenLatCapturada,
                              if (origenLngCapturada != null)
                                'origen_lng': origenLngCapturada,
                            }).select('id').single();
                        final int nuevoServicioId =
                            (insertedSvc['id'] as num).toInt();

                        // DISPARO DE NOTIFICACIONES — 3 olas, espejando
                        // exactamente las fases del embudo táctico dentro
                        // de la app:
                        //
                        //   T=0    → Masters en línea (mensaje propio) +
                        //            #1 de cada paradero (mensaje propio)
                        //   +2min  → ZONAL: si nadie lo tomó, se abre a
                        //            quien esté a máx. 1km del origen.
                        //            NOTA: Central todavía no captura
                        //            coordenadas del origen al despachar
                        //            manualmente — sin eso, esta ola no
                        //            puede filtrar por distancia todavía
                        //            y se comporta como la global. Para
                        //            que el radio de 1km funcione de
                        //            verdad aquí, hace falta agregar un
                        //            selector de ubicación al formulario
                        //            de despacho (igual al de los
                        //            formularios de invitado).
                        //   +5min  → GLOBAL: todos los conectados.
                        //
                        // Las 3 olas respetan la regla de capacidad por
                        // rango (NOVATO/PRO bloqueados si están ocupados;
                        // ELITE/LEYENDA/MASTER según su cupo libre) vía
                        // moviles_elegibles_notificacion() en SQL.
                        if (tarifaFinal > 0) {
                          // --- T=0: MASTERS (mensaje propio) ---
                          var idsMasters = <String>[];
                          try {
                            final mastersResp = await Supabase.instance.client
                                .rpc(
                                  'moviles_elegibles_notificacion',
                                  params: {
                                    'p_solo_master': true,
                                    // Mismo turno único — un Master con
                                    // un servicio activo no debe ver
                                    // ofertas nuevas a T=0, solo cuando
                                    // el servicio se libera más adelante.
                                    'p_solo_completamente_libres': true,
                                  },
                                );
                            idsMasters = (mastersResp as List)
                                .map((m) => m['id'].toString())
                                .toList();
                            if (idsMasters.isNotEmpty) {
                              await MotorNotificaciones.dispararRafa(
                                idsDestinos: idsMasters,
                                titulo: '⚡ TURNO DE MASTER',
                                mensaje: 'Nuevo servicio disponible en el radar',
                                urgente: true,
                                sonido: Sonidos.movilParadero,
                              );
                            }
                          } catch (_) {
                            // Si la función SQL no existe todavía, no
                            // bloqueamos el despacho — solo se omite
                            // esta ola hasta que se corra el script.
                          }

                          // --- T=+30s: #1 DE CADA PARADERO (mensaje propio) ---
                          // Se retrasa 30s para que coincida con el contador
                          // de cuenta regresiva que muestra movil_screen al
                          // #1 de la fila antes de abrir el servicio.
                          // Capturamos los valores antes del delay — los
                          // controllers del diálogo pueden disponerse antes.
                          // T=+30s: misil programado al #1 de cada paradero.
                          // Misil retardado (no Future.delayed) — sobrevive si
                          // Central navega fuera de pantalla, y su ID se guarda
                          // para cancelarlo si alguien acepta antes de los 30s.
                          if (pilotosSeleccionadosIds.isNotEmpty) {
                            final idsSnap =
                                List<String>.from(pilotosSeleccionadosIds);
                            final id30s = await MotorNotificaciones
                                .programarMisilRetardado(
                              externalIds: idsSnap,
                              titulo: '📍 TU TURNO EN EL PARADERO',
                              mensaje: 'Un servicio está esperando por ti',
                              segundosRetardo: 30,
                              sonido: Sonidos.movilParadero,
                            );
                            if (id30s != null) {
                              await Supabase.instance.client
                                  .from('servicios')
                                  .update({'onesignal_30s': id30s})
                                  .eq('id', nuevoServicioId);
                            }
                          }

                          // --- T=+60s ZONAL y T=+90s GLOBAL ---
                          // Capturo el servicioId antes del delay para
                          // que no dependa del estado del diálogo.
                          {
                            final int svcId = nuevoServicioId;
                            final String msg =
                                'Nuevo servicio disponible en el radar';
                            final List<String> masterSnap =
                                List<String>.from(idsMasters);
                            final List<String> paraderoSnap =
                                List<String>.from(pilotosSeleccionadosIds);

                            // T=+60s y T=+90s — misiles server-side (pre-fetch al despacho)
                            final double? oLat = origenLatCapturada;
                            final double? oLng = origenLngCapturada;
                            final movilesC = await Supabase.instance.client
                                .from('usuarios').select('id, latitud, longitud')
                                .eq('rol', 'movil').eq('en_linea', true)
                                .neq('suspendido', true)
                                .not('rango_movil', 'in', '("MASTER")');
                            final idsZonaC = movilesC.where((u) {
                              final id = u['id'].toString();
                              if (masterSnap.contains(id) || paraderoSnap.contains(id)) return false;
                              if (oLat == null || oLng == null) return true;
                              final uLat = (u['latitud'] as num?)?.toDouble();
                              final uLng = (u['longitud'] as num?)?.toDouble();
                              if (uLat == null || uLng == null) return false;
                              return const Distance().as(
                                    LengthUnit.Meter,
                                    LatLng(uLat, uLng),
                                    LatLng(oLat, oLng),
                                  ) <= 1000;
                            }).map((u) => u['id'].toString()).toList();
                            final idsTodosC = movilesC
                                .map((u) => u['id'].toString())
                                .where((id) => !masterSnap.contains(id))
                                .toList();
                            String? id60sC;
                            String? id90sC;
                            if (idsZonaC.isNotEmpty) {
                              id60sC = await MotorNotificaciones.programarMisilRetardado(
                                externalIds: idsZonaC,
                                titulo: '📡 SERVICIO CERCA (1km)',
                                mensaje: msg,
                                segundosRetardo: 60,
                                sonido: Sonidos.movilParadero,
                              );
                            }
                            if (idsTodosC.isNotEmpty) {
                              id90sC = await MotorNotificaciones.programarMisilRetardado(
                                externalIds: idsTodosC,
                                titulo: '🚨 SERVICIO SIN TOMAR',
                                mensaje: msg,
                                segundosRetardo: 90,
                                sonido: Sonidos.movilParadero,
                              );
                            }
                            if (id60sC != null || id90sC != null) {
                              await Supabase.instance.client.from('servicios').update({
                                if (id60sC != null) 'onesignal_2m': id60sC,
                                if (id90sC != null) 'onesignal_5m': id90sC,
                              }).eq('id', svcId);
                            }
                          }
                        }

                        if (context.mounted) {
                          // ---> CIERRE Y OFERTA DE GUARDAR EN LA RED DE DIRECCIONES <---
                          // Capturamos antes del pop porque los controllers se
                          // pueden disponer en cuanto el diálogo se destruye.
                          final String destinoCapturado =
                              destinoController.text.trim();
                          Navigator.pop(context);

                          final String destinoMayus =
                              destinoCapturado.toUpperCase();
                          // Extraemos el barrio base (la parte antes del " - "
                          // si el destino viene de un chip de sugerencia, que
                          // rellena con "ZONA - "; si es texto libre, usamos
                          // el texto completo).
                          final String barrioExtraido =
                              destinoMayus.contains(' - ')
                              ? destinoMayus.split(' - ')[0].trim()
                              : destinoMayus;

                          // Revisamos si ya existe en la red cargada al abrir
                          // el formulario — comparación nombre vs. nombre.
                          final bool yaEstaEnRed = redDireccionesCentral.any((
                            dir,
                          ) {
                            final String nombreDir = dir.contains(' (')
                                ? dir.split(' (')[0].trim().toUpperCase()
                                : dir.trim().toUpperCase();
                            return nombreDir == barrioExtraido;
                          });

                          if (tarifaFinal > 0 &&
                              !yaEstaEnRed &&
                              barrioExtraido.isNotEmpty) {
                            final barrioCtrl = TextEditingController(
                              text: barrioExtraido,
                            );
                            String zonaSeleccionada = 'CÚCUTA';
                            bool guardandoRed = false;

                            // Usamos this.context (del State) en lugar del
                            // context del builder del diálogo, que ya se
                            // destruyó con el Navigator.pop de arriba.
                            showDialog(
                              context: this.context, // ignore: use_build_context_synchronously
                              builder: (ctxSave) => StatefulBuilder(
                                builder: (ctxSave, setSaveState) => AlertDialog(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  title: const Text(
                                    '💾 ¿GUARDAR EN LA RED?',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  content: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Esta dirección no está en la red de zonas. '
                                        '¿La agregamos para que todos los locales '
                                        'la vean como sugerencia?',
                                        style: TextStyle(fontSize: 13),
                                      ),
                                      const SizedBox(height: 12),
                                      TextField(
                                        controller: barrioCtrl,
                                        textCapitalization:
                                            TextCapitalization.characters,
                                        decoration: const InputDecoration(
                                          labelText:
                                              'Barrio / Zona (Ej: COCONUCO)',
                                          border: OutlineInputBorder(),
                                          isDense: true,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      const Text(
                                        '¿A qué municipio pertenece?',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Wrap(
                                        spacing: 6,
                                        runSpacing: 0,
                                        children: [
                                          'CÚCUTA',
                                          'LOS PATIOS',
                                          'V. ROSARIO',
                                        ].map((z) {
                                          return ChoiceChip(
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
                                              if (selected) {
                                                setSaveState(
                                                  () => zonaSeleccionada = z,
                                                );
                                              }
                                            },
                                          );
                                        }).toList(),
                                      ),
                                    ],
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctxSave),
                                      child: const Text(
                                        'NO GUARDAR',
                                        style: TextStyle(color: Colors.grey),
                                      ),
                                    ),
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.black,
                                      ),
                                      onPressed: guardandoRed
                                          ? null
                                          : () async {
                                              if (barrioCtrl.text
                                                  .trim()
                                                  .isEmpty) {
                                                return;
                                              }
                                              setSaveState(
                                                () => guardandoRed = true,
                                              );
                                              try {
                                                await Supabase.instance.client
                                                    .from('red_direcciones')
                                                    .insert({
                                                      'nombre': barrioCtrl.text
                                                          .trim()
                                                          .toUpperCase(),
                                                      'municipio':
                                                          zonaSeleccionada,
                                                      'zona_lluvia': 'general',
                                                      'activo': true,
                                                    });
                                                if (ctxSave.mounted) {
                                                  Navigator.pop(ctxSave);
                                                  ScaffoldMessenger.of(
                                                    this.context, // ignore: use_build_context_synchronously
                                                  ).showSnackBar(
                                                    const SnackBar(
                                                      content: Text(
                                                        '✅ Dirección agregada a la red. '
                                                        'Todos los locales la verán.',
                                                      ),
                                                      backgroundColor:
                                                          Colors.green,
                                                    ),
                                                  );
                                                }
                                              } catch (e) {
                                                setSaveState(
                                                  () => guardandoRed = false,
                                                );
                                                if (ctxSave.mounted) {
                                                  ScaffoldMessenger.of(
                                                    this.context, // ignore: use_build_context_synchronously
                                                  ).showSnackBar(
                                                    SnackBar(
                                                      content: Text(
                                                        'Error BD: $e',
                                                      ),
                                                      backgroundColor:
                                                          Colors.red,
                                                    ),
                                                  );
                                                }
                                              }
                                            },
                                      child: guardandoRed
                                          ? const SizedBox(
                                              width: 16,
                                              height: 16,
                                              child: CircularProgressIndicator(
                                                color: Color(0xff3AF500),
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : const Text(
                                              'GUARDAR EN LA RED',
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
                        setDialogState(() => procesando = false);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Error al despachar: $e'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
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
                      'ENVIAR AL RADAR',
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

  // ─── HELPERS FN ────────────────────────────────────────────────────────────

  String _fnLabelZona(String z) {
    switch (z) {
      case 'CUCUTA':
        return 'Cúcuta';
      case 'LOS_PATIOS':
        return 'Los Patios';
      case 'V_ROSARIO':
        return 'Villa del Rosario';
      default:
        return z;
    }
  }

  String _fnLabelSede(Map<String, dynamic> s) {
    final tipo = s['tipo'] as String;
    final nombre = s['nombre'] as String;
    if (tipo == 'FN') return 'FN #${s['numero']} – $nombre';
    return '$tipo – $nombre';
  }

  // ─── FORMULARIO FN ─────────────────────────────────────────────────────────
  // Crea un servicio FARMANORTE con cascada FN de 2 olas:
  //   T=0   → FN motos dentro de 2km de la sede (si vacío → todos)
  //   T+31s → Todos los FN motos (solo si T=0 fue subconjunto)

  void _abrirFormularioFN(BuildContext context) async {
    // ── Cargar sedes activas ──────────────────────────────────────────────────
    List<Map<String, dynamic>> sedes = [];
    try {
      sedes = List<Map<String, dynamic>>.from(
        await Supabase.instance.client
            .from('fn_sedes')
            .select()
            .eq('activo', true)
            .order('tipo')
            .order('numero', nullsFirst: false)
            .order('nombre'),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error cargando sedes FN: $e')));
      }
      return;
    }

    if (!context.mounted) return;

    if (sedes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay sedes FN activas. Créalas en Gestión → Farmanorte FN.')),
      );
      return;
    }

    // ── Ordenar sedes: numéricamente ascendente (menor a mayor) ──────────────
    final sedesOrdenadas = List<Map<String, dynamic>>.from(sedes)
      ..sort((a, b) {
        final na = int.tryParse(a['numero']?.toString() ?? '') ?? -1;
        final nb = int.tryParse(b['numero']?.toString() ?? '') ?? -1;
        return na.compareTo(nb);
      });

    // ── Estado del diálogo ────────────────────────────────────────────────────
    Map<String, dynamic>? sedeSolicitante;
    final List<Map<String, dynamic>?> recogidasSel = [null];
    final destinoCtrl = TextEditingController();
    final tarifaCtrl = TextEditingController();
    final instruccionesCtrl = TextEditingController();
    bool vaConDatafono = false;
    bool procesando = false;

    // Helper: dropdown de sedes ordenadas
    Widget dropdownSede({
      Map<String, dynamic>? value,
      void Function(Map<String, dynamic>?)? onChanged,
      String? label,
    }) =>
        DropdownButtonFormField<Map<String, dynamic>>(
          initialValue: value,
          isExpanded: true,
          hint: const Text('Seleccionar sede...',
              style: TextStyle(fontSize: 13, color: Colors.black38)),
          decoration: InputDecoration(
            labelText: label,
            labelStyle: TextStyle(fontSize: 11, color: Colors.indigo[700]),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          items: sedesOrdenadas
              .map((s) => DropdownMenuItem(
                    value: s,
                    child: Text(
                      _fnLabelSede(s),
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ))
              .toList(),
          onChanged: onChanged,
        );

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {

          return AlertDialog(
            insetPadding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 24),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            backgroundColor: Colors.white,
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.indigo[900],
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('FN',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          letterSpacing: 1.5)),
                ),
                const SizedBox(width: 10),
                const Text(
                  'SERVICIO FARMANORTE',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [

                    // ── Sede FN Solicitante ─────────────────────────────────
                    const Text('Sede FN solicitante:',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.black54,
                            fontSize: 12)),
                    const SizedBox(height: 4),
                    dropdownSede(
                      value: sedeSolicitante,
                      onChanged: procesando
                          ? null
                          : (v) => setDialogState(
                              () => sedeSolicitante = v),
                    ),
                    const SizedBox(height: 6),
                    // Zona chip — solo si hay sede seleccionada
                    if (sedeSolicitante != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.indigo[50],
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.location_on_outlined,
                                size: 13, color: Colors.indigo[700]),
                            const SizedBox(width: 4),
                            Text(
                              _fnLabelZona(
                                  sedeSolicitante!['zona'] as String),
                              style: TextStyle(
                                  color: Colors.indigo[800],
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),

                    const SizedBox(height: 14),

                    // ── Recogidas (lista dinámica de dropdowns) ─────────────
                    Row(
                      children: [
                        const Text('Recogidas:',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.black54,
                                fontSize: 12)),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: procesando
                              ? null
                              : () => setDialogState(() =>
                                  recogidasSel.add(null)),
                          icon: const Icon(Icons.add_circle_outline, size: 16),
                          label: const Text('Agregar',
                              style: TextStyle(fontSize: 12)),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.indigo[700],
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 0),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ...List.generate(recogidasSel.length, (i) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: dropdownSede(
                              value: recogidasSel[i],
                              label: 'Recogida ${i + 1}',
                              onChanged: procesando
                                  ? null
                                  : (v) => setDialogState(
                                      () => recogidasSel[i] = v),
                            ),
                          ),
                          if (recogidasSel.length > 1) ...[
                            const SizedBox(width: 4),
                            IconButton(
                              icon: const Icon(Icons.remove_circle,
                                  color: Colors.red, size: 20),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              tooltip: 'Quitar',
                              onPressed: procesando
                                  ? null
                                  : () => setDialogState(
                                      () => recogidasSel.removeAt(i)),
                            ),
                          ],
                        ],
                      ),
                    )),

                    const SizedBox(height: 8),

                    // ── Destino ─────────────────────────────────────────────
                    const Text('Destino:',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.black54,
                            fontSize: 12)),
                    const SizedBox(height: 4),
                    TextField(
                      controller: destinoCtrl,
                      textCapitalization: TextCapitalization.characters,
                      decoration: InputDecoration(
                        hintText: 'Dirección o barrio de entrega',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // ── Tarifa ──────────────────────────────────────────────
                    const Text('Tarifa:',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.black54,
                            fontSize: 12)),
                    const SizedBox(height: 4),
                    TextField(
                      controller: tarifaCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        hintText: '\$0',
                        prefixIcon: const Icon(Icons.attach_money),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // ── Datafono toggle ──────────────────────────────────────
                    Container(
                      decoration: BoxDecoration(
                        color: vaConDatafono ? Colors.blue[50] : Colors.grey[100],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: vaConDatafono ? Colors.blue[300]! : Colors.grey[300]!,
                        ),
                      ),
                      child: SwitchListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                        secondary: Icon(
                          Icons.credit_card,
                          color: vaConDatafono ? Colors.blue[700] : Colors.grey[500],
                          size: 20,
                        ),
                        title: Text(
                          'Va con datafono',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: vaConDatafono ? Colors.blue[800] : Colors.black54,
                          ),
                        ),
                        subtitle: Text(
                          vaConDatafono ? 'Pago con tarjeta' : 'Pago en efectivo',
                          style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                        ),
                        value: vaConDatafono,
                        activeColor: Colors.blue[700],
                        onChanged: procesando
                            ? null
                            : (v) => setDialogState(() => vaConDatafono = v),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // ── Instrucciones especiales ─────────────────────────────
                    const Text('Instrucciones especiales:',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.black54,
                            fontSize: 12)),
                    const SizedBox(height: 4),
                    TextField(
                      controller: instruccionesCtrl,
                      textCapitalization: TextCapitalization.sentences,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: 'Indicaciones adicionales para el repartidor (opcional)…',
                        hintStyle: const TextStyle(fontSize: 12, color: Colors.black38),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed:
                    procesando ? null : () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: procesando
                    ? null
                    : () async {
                        if (sedeSolicitante == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Selecciona la sede solicitante')),
                          );
                          return;
                        }
                        if (destinoCtrl.text.trim().isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Ingresa el destino')),
                          );
                          return;
                        }
                        final tarifa = double.tryParse(
                                tarifaCtrl.text.replaceAll(',', '.')) ??
                            0;

                        setDialogState(() => procesando = true);

                        try {
                          final sede = sedeSolicitante!;
                          final zona = sede['zona'] as String;
                          final zonaLabel = _fnLabelZona(zona);
                          final sLat = (sede['lat'] as num?)?.toDouble();
                          final sLng = (sede['lng'] as num?)?.toDouble();
                          final nombreSede = _fnLabelSede(sede);

                          // Recogidas seleccionadas (solo las no nulas)
                          final recogidasList = recogidasSel
                              .whereType<Map<String, dynamic>>()
                              .map((s) => {
                                    'id': s['id'],
                                    'tipo': s['tipo'],
                                    'nombre': s['nombre'],
                                    'numero': s['numero'],
                                    'zona': s['zona'],
                                    'lat': s['lat'],
                                    'lng': s['lng'],
                                  })
                              .toList();

                          // ── Cargar FN motos online ─────────────────────────
                          // Filtros explícitos para garantizar que desconectados
                          // y suspendidos nunca reciban heads-up FN:
                          //   • en_linea = true    → excluye desconectados
                          //   • activo   = true    → excluye cuentas desactivadas
                          //   • suspendido IS NOT TRUE → excluye suspendidos;
                          //     "IS NOT TRUE" incluye NULLs (a diferencia de ≠ true)
                          final movilesConFn = await Supabase
                              .instance.client
                              .from('usuarios')
                              .select('id, latitud, longitud')
                              .eq('rol', 'movil')
                              .eq('en_linea', true)
                              .eq('activo', true)
                              .eq('tiene_fn', true)
                              .not('suspendido', 'is', true);

                          final idsTodos = (movilesConFn as List)
                              .map<String>((m) => m['id'].toString())
                              .toList();

                          // ── Calcular ola 1: 2km desde la sede ─────────────
                          List<String> ids2km = [];
                          if (sLat != null && sLng != null) {
                            ids2km = movilesConFn.where((u) {
                              final uLat =
                                  (u['latitud'] as num?)?.toDouble();
                              final uLng =
                                  (u['longitud'] as num?)?.toDouble();
                              if (uLat == null || uLng == null) return false;
                              return const Distance().as(
                                    LengthUnit.Meter,
                                    LatLng(uLat, uLng),
                                    LatLng(sLat, sLng),
                                  ) <=
                                  2000;
                            }).map<String>((u) => u['id'].toString()).toList();
                          }

                          final wave1Ids =
                              ids2km.isNotEmpty ? ids2km : idsTodos;
                          // Ola 2 solo si ola 1 fue subconjunto
                          final wave2Needed = ids2km.isNotEmpty &&
                              ids2km.length < idsTodos.length;

                          // ── T=0: Disparo ola 1 ─────────────────────────────
                          if (wave1Ids.isNotEmpty) {
                            await MotorNotificaciones.dispararRafa(
                              idsDestinos: wave1Ids,
                              titulo: '🔵 TURNO FARMANORTE',
                              mensaje: 'Servicio FN · $zonaLabel',
                              urgente: true,
                              sonido: Sonidos.movilParadero,
                            );
                          }

                          // ── Insertar servicio ──────────────────────────────
                          final insertedSvc = await Supabase
                              .instance.client
                              .from('servicios')
                              .insert({
                                'origen': nombreSede,
                                'destino': destinoCtrl.text
                                    .trim()
                                    .toUpperCase(),
                                'tarifa': tarifa,
                                'estado':
                                    tarifa > 0 ? 'pendiente' : 'cotizacion',
                                'creador': 'Central FN',
                                'tipo_servicio': 'FARMANORTE',
                                'tipo_fn': true,
                                'zona_fn': zona,
                                'fn_sede_id': sede['id'],
                                'recogidas': recogidasList,
                                'fn_primera_ola': wave1Ids,
                                'metodo_pago': vaConDatafono ? 'Datafono' : 'Efectivo',
                                'archivado': false,
                                if (sLat != null) 'origen_lat': sLat,
                                if (sLng != null) 'origen_lng': sLng,
                                if (instruccionesCtrl.text.trim().isNotEmpty)
                                  'instrucciones_especiales': instruccionesCtrl.text.trim(),
                              })
                              .select('id')
                              .single();

                          final int nuevoId =
                              (insertedSvc['id'] as num).toInt();

                          // ── T+31s: Disparo ola 2 (todos FN) ───────────────
                          if (wave2Needed && idsTodos.isNotEmpty) {
                            final id31s = await MotorNotificaciones
                                .programarMisilRetardado(
                              externalIds: idsTodos,
                              titulo: '🔵 TURNO FARMANORTE',
                              mensaje:
                                  'Servicio FN sin tomar · $zonaLabel',
                              segundosRetardo: 31,
                              sonido: Sonidos.movilParadero,
                            );
                            if (id31s != null) {
                              await Supabase.instance.client
                                  .from('servicios')
                                  .update({'onesignal_30s': id31s})
                                  .eq('id', nuevoId);
                            }
                          }

                          if (context.mounted) {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  wave1Ids.isEmpty
                                      ? 'Servicio FN creado (sin motos FN en línea)'
                                      : 'Servicio FN enviado a ${wave1Ids.length} moto${wave1Ids.length == 1 ? '' : 's'}',
                                ),
                                backgroundColor: Colors.indigo[700],
                              ),
                            );
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Error: $e'),
                                backgroundColor: Colors.red[700],
                              ),
                            );
                            setDialogState(() => procesando = false);
                          }
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo[900],
                ),
                child: procesando
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('ENVIAR AL RADAR',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  void _mostrarMenuAsignacion(BuildContext contextoPrincipal, int servicioId) {
    showDialog(
      context: contextoPrincipal,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text(
          'ASIGNAR / REASIGNAR MÓVIL',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue),
        ),
        content: SizedBox(
          width: 400,
          height: 450,
          child: FutureBuilder<List<dynamic>>(
            // Cruce de tablas: Usuarios online + Servicios en curso
            future: Future.wait([
              Supabase.instance.client
                  .from('usuarios')
                  .select()
                  .eq('rol', 'movil')
                  .eq('en_linea', true),
              Supabase.instance.client
                  .from('servicios')
                  .select('movil_id')
                  .inFilter('estado', [
                    'en_ruta_origen',
                    'en_origen',
                    'en_ruta_destino',
                  ]),
            ]),
            builder: (ctx, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(color: Colors.black),
                );
              }

              final moviles =
                  List<Map<String, dynamic>>.from(snapshot.data?[0] ?? []).map((
                    m,
                  ) {
                    final map = Map<String, dynamic>.from(m);
                    map['nombre'] = _formatearNombreCentral(map);
                    return map;
                  }).toList();
              final activos = List<Map<String, dynamic>>.from(
                snapshot.data?[1] ?? [],
              );

              if (moviles.isEmpty) {
                return const Center(
                  child: Text(
                    'No hay móviles en línea.',
                    style: TextStyle(
                      color: Colors.grey,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                );
              }

              // Motor de Carga
              for (var m in moviles) {
                m['carga'] = activos
                    .where((s) => s['movil_id'] == m['id'])
                    .length;
              }

              // Ordenamiento táctico: Primero libres, luego por nombre
              moviles.sort((a, b) {
                int cmp = (a['carga'] as int).compareTo(b['carga'] as int);
                if (cmp == 0) {
                  return a['nombre'].toString().compareTo(
                    b['nombre'].toString(),
                  );
                }
                return cmp;
              });

              return ListView.builder(
                itemCount: moviles.length,
                itemBuilder: (ctx, index) {
                  final movil = moviles[index];
                  final int carga = movil['carga'];

                  Color colorCarga = const Color(0xff3AF500);
                  String txtCarga = 'LIBRE';
                  if (carga == 1) {
                    colorCarga = Colors.blue;
                    txtCarga = '1 VIAJE';
                  } else if (carga >= 2) {
                    colorCarga = Colors.red;
                    txtCarga = '$carga VIAJES';
                  }

                  return Card(
                    elevation: 1,
                    shape: RoundedRectangleBorder(
                      side: BorderSide(
                        color: carga >= 2
                            ? Colors.red[200]!
                            : Colors.transparent,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ListTile(
                      leading: CircleAvatar(
                        radius: 14,
                        backgroundColor: colorCarga,
                        child: Text(
                          _extraerNumeroAvatar(movil),
                          style: const TextStyle(
                            color: Colors.black,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      title: Text(
                        movil['nombre'],
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        'Rango: ${movil['rango_movil'] ?? 'NOVATO'}',
                        style: const TextStyle(fontSize: 11),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: colorCarga.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              txtCarga,
                              style: TextStyle(
                                color: colorCarga == const Color(0xff3AF500)
                                    ? Colors.green[900]
                                    : colorCarga,
                                fontWeight: FontWeight.bold,
                                fontSize: 10,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(Icons.send, color: Colors.blue, size: 18),
                        ],
                      ),
                      onTap: () async {
                        // 1. Asignamos el servicio
                        await Supabase.instance.client
                            .from('servicios')
                            .update({
                              'estado': 'en_ruta_origen',
                              'movil_id': movil['id'],
                              'accepted_at': DateTime.now()
                                  .toUtc()
                                  .toIso8601String(),
                              'picked_up_at': null,
                              'extension_minutes': 0,
                              'observacion':
                                  'Asignado a ${movil['nombre']} por Central',
                            })
                            .eq('id', servicioId);

                        // 2. QUEMAMOS EL TICKET VIP (Cobro del favor)
                        if (movil['ticket_prioridad'] == true) {
                          await Supabase.instance.client
                              .from('usuarios')
                              .update({'ticket_prioridad': false})
                              .eq('id', movil['id']);
                        }

                        // 3. Disparamos la notificación
                        await MotorNotificaciones.dispararMisil(
                          idDestino: movil['id'].toString(),
                          titulo: '🚨 NUEVO SERVICIO ASIGNADO',
                          mensaje:
                              'La Central te ha asignado un servicio manual. Revisa tu radar.',
                          sonido: Sonidos.alerta,
                        );

                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                          Navigator.pop(contextoPrincipal);
                        }
                      },
                    ),
                  );
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CANCELAR', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _mostrarMenuFusion(
    BuildContext contextoPrincipal,
    Map<String, dynamic> svcPrincipal,
  ) {
    showDialog(
      context: contextoPrincipal,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(
          'FUSIONAR ORDEN #${svcPrincipal['id']}',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.purple,
          ),
        ),
        content: SizedBox(
          width: 400,
          height: 400,
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: Supabase.instance.client
                .from('servicios')
                .select()
                .eq('estado', 'pendiente')
                .neq('id', svcPrincipal['id']),
            builder: (ctx, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(color: Colors.black),
                );
              }

              final pendientes = snapshot.data ?? [];
              if (pendientes.isEmpty) {
                return const Center(
                  child: Text(
                    'No hay otras órdenes pendientes en el radar para fusionar.',
                    style: TextStyle(
                      color: Colors.grey,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                    textAlign: TextAlign.center,
                  ),
                );
              }

              return Column(
                children: [
                  const Text(
                    'Selecciona la orden secundaria para amarrarla a esta. Se sumarán las tarifas y se unirán las rutas en un solo bloque.',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: ListView.builder(
                      itemCount: pendientes.length,
                      itemBuilder: (ctx, index) {
                        final svcSecundario = pendientes[index];
                        return Card(
                          elevation: 1,
                          child: ListTile(
                            title: Text(
                              'Orden #${svcSecundario['id']} | ${fmtPeso(svcSecundario['tarifa'])}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            subtitle: Text(
                              '${svcSecundario['origen']} ➔ ${svcSecundario['destino']}',
                              style: const TextStyle(fontSize: 11),
                            ),
                            trailing: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.purple[800],
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                              ),
                              onPressed: () async {
                                final double tarifa1 =
                                    (svcPrincipal['tarifa'] as num?)
                                        ?.toDouble() ??
                                    0.0;
                                final double tarifa2 =
                                    (svcSecundario['tarifa'] as num?)
                                        ?.toDouble() ??
                                    0.0;

                                final String obs1 =
                                    svcPrincipal['observacion'] ?? 'Sin notas';
                                final String obs2 =
                                    svcSecundario['observacion'] ?? 'Sin notas';
                                final String nuevaObs =
                                    '[FUSIÓN CON #${svcSecundario['id']}]\n1: $obs1\n2: $obs2';

                                final String nuevoDestino =
                                    '${svcPrincipal['destino']} Y ${svcSecundario['destino']}';
                                final String nuevoOrigen =
                                    '${svcPrincipal['origen']} Y ${svcSecundario['origen']}';

                                await Supabase.instance.client
                                    .from('servicios')
                                    .update({
                                      'origen': nuevoOrigen,
                                      'destino': nuevoDestino,
                                      'tarifa': tarifa1 + tarifa2,
                                      'tarifa_detalle': {
                                        'base': tarifa1 + tarifa2,
                                        'total': tarifa1 + tarifa2,
                                        'fuente': 'fusion',
                                        'ajuste_manual': 0,
                                      },
                                      'observacion': nuevaObs,
                                    })
                                    .eq('id', svcPrincipal['id']);

                                await Supabase.instance.client
                                    .from('servicios')
                                    .update({
                                      'estado': 'cancelado',
                                      'observacion':
                                          'SISTEMA: Fusionado dentro del bloque #${svcPrincipal['id']}',
                                    })
                                    .eq('id', svcSecundario['id']);

                                if (ctx.mounted) {
                                  Navigator.pop(ctx);
                                  Navigator.pop(contextoPrincipal);
                                  ScaffoldMessenger.of(
                                    contextoPrincipal,
                                  ).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        '¡Órdenes amarradas con éxito!',
                                      ),
                                      backgroundColor: Colors.purple,
                                    ),
                                  );
                                }
                              },
                              child: const Text(
                                'UNIR',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
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
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CANCELAR'),
          ),
        ],
      ),
    );
  }

  Future<void> _abrirWhatsAppCentral(String telefono, int idPedido) async {
    if (telefono.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Sin número registrado.')));
      }
      return;
    }
    String numero = telefono.replaceAll(RegExp(r'[^0-9]'), '');
    if (numero.length == 10) numero = '57$numero';
    final Uri url = Uri.parse(
      'https://wa.me/$numero?text=${Uri.encodeComponent('Central ServiExpress 📡 | Sobre la Orden #$idPedido: ')}',
    );
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar( // ignore: use_build_context_synchronously
          const SnackBar(content: Text('No se pudo abrir WhatsApp.')),
        );
      }
    }
  }

  /// Fast-path para cotizaciones: llama a sugerir_tarifa y, si hay alta
  /// confianza, ofrece resolver con un solo tap sin abrir el formulario
  /// completo. Devuelve `true` si el asunto quedó resuelto (o cancelado
  /// por el usuario), `false` si debe abrirse el diálogo completo.
  Future<bool> _fastPathCotizacion(
    BuildContext context,
    Map<String, dynamic> servicio,
    bool esVip,
  ) async {
    if (!mounted) return false;

    final String origen  = servicio['creador']?.toString() ?? '';
    final String destino = servicio['destino']?.toString()  ?? '';
    final String? tipo   = servicio['tipo_servicio']?.toString();

    // Llamada rápida al motor
    Map<String, dynamic>? row;
    try {
      final params = <String, dynamic>{
        'p_origen':  origen,
        'p_destino': destino,
        if (servicio['destino_lat'] != null) 'p_destino_lat': (servicio['destino_lat'] as num).toDouble(),
        if (servicio['destino_lng'] != null) 'p_destino_lng': (servicio['destino_lng'] as num).toDouble(),
        if (tipo != null)               'p_tipo_servicio': tipo,
      };
      final res = await Supabase.instance.client.rpc('sugerir_tarifa', params: params);
      if (res != null && (res as List).isNotEmpty) row = res[0] as Map<String, dynamic>;
    } catch (_) {
      return false; // cualquier error → caer al diálogo completo
    }

    if (row == null) return false;
    final String confianza = row['confianza']?.toString() ?? 'sin_historial';
    if (confianza != 'alta') return false; // solo fast-path con alta confianza

    final int precioSugerido = (row['precio_sugerido'] as num?)?.toInt() ?? 0;
    if (precioSugerido <= 0) return false;

    final double tarifaFinal = esVip ? (precioSugerido + 3000).toDouble() : precioSugerido.toDouble();
    final String textoTarifa = _formatearMonedaCentral(tarifaFinal);

    if (!mounted) return false;

    final bool? confirmar = await showDialog<bool>(
      context: context, // ignore: use_build_context_synchronously
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Row(
          children: [
            const Text('⚡', style: TextStyle(fontSize: 20)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Cotización Rápida #${servicio['id']}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${servicio['creador']?.toString() ?? ''} → $destino',
              style: const TextStyle(fontSize: 13, color: Colors.black54),
            ),
            if (tipo != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(tipo, style: const TextStyle(fontSize: 12, color: Colors.black38)),
              ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.green[300]!),
              ),
              child: Column(
                children: [
                  Text(
                    textoTarifa,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.green[800],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.auto_graph, size: 13, color: Colors.green[700]),
                      const SizedBox(width: 4),
                      Text(
                        '● Alta confianza · ${row?['num_precedentes'] ?? 0} servicios similares',
                        style: TextStyle(fontSize: 11, color: Colors.green[700]),
                      ),
                    ],
                  ),
                  if (esVip) ...[
                    const SizedBox(height: 4),
                    Text(
                      '(+\$3.000 VIP incluido)',
                      style: TextStyle(fontSize: 11, color: Colors.amber[800]),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null), // null → abrir diálogo completo
            child: const Text('Revisar manualmente', style: TextStyle(color: Colors.black45)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green[700],
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'COTIZAR A $textoTarifa',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirmar != true) {
      // null = "Revisar manualmente" → caer al diálogo completo
      return confirmar == false; // false = usuario cerró el dialog (cancelar)
    }

    // Confirmar → aplicar directamente en BD
    try {
      await Supabase.instance.client.from('servicios').update({
        'tarifa': tarifaFinal,
        'tarifa_detalle': {
          'total': tarifaFinal,
          'base': precioSugerido,
          'fuente': 'motor_alta_fast',
          if (esVip) 'vip': 3000,
        },
        'estado': 'cotizada',
      }).eq('id', servicio['id']);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar( // ignore: use_build_context_synchronously
          SnackBar(
            content: Text('⚡ Cotización enviada: $textoTarifa'),
            backgroundColor: Colors.green[700],
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar( // ignore: use_build_context_synchronously
          SnackBar(content: Text('Error al cotizar: $e'), backgroundColor: Colors.red),
        );
      }
    }
    return true;
  }

}
