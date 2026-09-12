// ignore_for_file: use_build_context_synchronously, invalid_use_of_protected_member
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
    String? paraderoOrigen; // paradero desde el que se despacha (opcional)
    bool procesando = false;
    // Coordenadas del Local elegido por autocompletado — null si
    // todavía no se seleccionó nada de la lista (texto libre).
    double? origenLatCapturada;
    double? origenLngCapturada;

    // Desglose del precio capturado por CampoTarifaInteligente.
    Map<String, dynamic>? detalleActual;

    // Red de direcciones SE del local seleccionado (red_dir_se)
    List<Map<String, dynamic>> dirUsuarioLocal = []; // red_dir_se del local elegido
    List<String> dirUsuarioNombres = []; // nombres para verificar si ya existe
    List<Map<String, dynamic>> sugerenciasDestino = [];
    int? localSeleccionadoId;
    String? destinoBase;
    String? sectorBase;

    // Feature 2: asignación directa a un móvil específico
    String? movilDirectoServimotoId;
    String? movilDirectoServimotoNombre;
    List<Map<String, dynamic>> movilesConectados = [];
    Supabase.instance.client
        .from('usuarios')
        .select('id, nombre, usuario, rango_movil')
        .eq('rol', 'movil')
        .eq('en_linea', true)
        .eq('tiene_se', true)
        .order('usuario', ascending: true)
        .then((data) {
      movilesConectados = List<Map<String, dynamic>>.from(data)
        ..sort((a, b) {
          final na = int.tryParse(RegExp(r'\d+').firstMatch(a['usuario']?.toString() ?? '')?.group(0) ?? '') ?? 9999;
          final nb = int.tryParse(RegExp(r'\d+').firstMatch(b['usuario']?.toString() ?? '')?.group(0) ?? '') ?? 9999;
          return na.compareTo(nb);
        });
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
                  children: ['PAQUETERÍA', 'COMIDA', 'COMPRAS', 'MOTOTAXI', 'RECOGIDA LOCAL'].map(
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
                              // RECOGIDA LOCAL no tiene destino ni tarifa
                              if (tipo == 'RECOGIDA LOCAL') {
                                destinoController.clear();
                                tarifaController.clear();
                              }
                            });
                          }
                        },
                      );
                    },
                  ).toList(),
                ),
                const SizedBox(height: 12),
                const Text(
                  'PARADERO DE ORIGEN (opcional)',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black54),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: ['EXPUENTE', 'MEMOS', 'BOCONO', 'NOCTURNO'].map((p) {
                    final bool sel = paraderoOrigen == p;
                    return ChoiceChip(
                      label: Text(p, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: sel ? Colors.white : Colors.black87)),
                      selected: sel,
                      selectedColor: Colors.blue[800],
                      backgroundColor: Colors.grey[200],
                      onSelected: (v) => setDialogState(() => paraderoOrigen = v ? p : null),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                const Text(
                  'ASIGNAR DIRECTAMENTE A (opcional)',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black54),
                ),
                const SizedBox(height: 6),
                DropdownButtonFormField<String?>(
                  value: movilDirectoServimotoId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    prefixIcon: Icon(Icons.person_pin, size: 18),
                  ),
                  hint: const Text('Seleccionar', style: TextStyle(fontSize: 12, color: Colors.black54)),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Seleccionar', style: TextStyle(fontSize: 12, color: Colors.black54)),
                    ),
                    ...movilesConectados.map((m) => DropdownMenuItem<String?>(
                      value: m['id'].toString(),
                      child: Text(
                        '${_formatearNombreCentral(m)} · ${m['rango_movil'] ?? ''}',
                        style: const TextStyle(fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    )),
                  ],
                  onChanged: (v) => setDialogState(() {
                    movilDirectoServimotoId = v;
                    movilDirectoServimotoNombre = v == null
                        ? null
                        : _formatearNombreCentral(movilesConectados
                            .firstWhere((m) => m['id'].toString() == v, orElse: () => <String, dynamic>{}));
                  }),
                ),
                const SizedBox(height: 12),
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
                    final newLocalId = local['id'] as int?;
                    setDialogState(() {
                      origenLatCapturada = local['lat_fija'] != null
                          ? (local['lat_fija'] as num).toDouble()
                          : null;
                      origenLngCapturada = local['lng_fija'] != null
                          ? (local['lng_fija'] as num).toDouble()
                          : null;
                      localSeleccionadoId = newLocalId;
                      dirUsuarioLocal = [];
                      dirUsuarioNombres = [];
                    });
                    if (newLocalId != null) {
                      Supabase.instance.client
                          .from('red_dir_se')
                          .select('id, nombre, municipio, sector_id, precio')
                          .eq('usuario_id', newLocalId)
                          .eq('activo', true)
                          .order('nombre', ascending: true)
                          .then((du) {
                        dirUsuarioLocal = List<Map<String, dynamic>>.from(du);
                        dirUsuarioNombres = dirUsuarioLocal
                            .map((e) => e['nombre'].toString().toUpperCase())
                            .toList();
                      });
                    }
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
                            : tipoServicio == 'RECOGIDA LOCAL'
                            ? 'Local de Recogida (*)'
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
                              : tipoServicio == 'RECOGIDA LOCAL'
                              ? Icons.store
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

                if (tipoServicio != 'RECOGIDA LOCAL') ...[
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
                    // ── Preservar precio si el usuario añade detalles ──
                    if (destinoBase != null &&
                        texto.toUpperCase().startsWith(destinoBase!)) {
                      setDialogState(() => sugerenciasDestino = []);
                      return;
                    }
                    if (sectorBase != null &&
                        texto.toLowerCase().contains(sectorBase!.toLowerCase())) {
                      setDialogState(() => sugerenciasDestino = []);
                      return;
                    }
                    destinoBase = null;
                    sectorBase  = null;

                    if (texto.length < 2) {
                      setDialogState(() => sugerenciasDestino = []);
                      return;
                    }
                    final t = texto.toLowerCase();
                    final palabras = t.split(RegExp(r'\s+')).where((w) => w.length > 2).toList();

                    final List<Map<String, dynamic>> encontradas = [];
                    for (final d in dirUsuarioLocal) {
                      final nombre = (d['nombre'] ?? '').toString().toLowerCase();
                      final coincide = nombre.contains(t) ||
                          palabras.any((w) => nombre.contains(w));
                      if (!coincide) continue;
                      final int? precio = d['precio'] as int?;
                      encontradas.add({'id': d['id'], 'nombre': d['nombre'].toString().toUpperCase(), 'precio': precio});
                      if (encontradas.length >= 6) break;
                    }
                    setDialogState(() => sugerenciasDestino = encontradas);
                  },
                ),

                // Sugerencias de la red de direcciones (con precio si disponible)
                if (sugerenciasDestino.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6, bottom: 4),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: sugerenciasDestino.map((sug) {
                        final nombre = sug['nombre'].toString();
                        final int? precio = sug['precio'] as int?;
                        String? precioStr;
                        if (precio != null) {
                          String r = ''; int c = 0;
                          final s = precio.toString();
                          for (int i = s.length - 1; i >= 0; i--) {
                            r = s[i] + r; c++;
                            if (c == 3 && i > 0) { r = '.$r'; c = 0; }
                          }
                          precioStr = '\$$r';
                        }
                        return InkWell(
                          onTap: () {
                            destinoBase = nombre;
                            sectorBase  = null;
                            destinoController.text = '$nombre - ';
                            if (precioStr != null)
                              tarifaController.text = precioStr;
                            setDialogState(() => sugerenciasDestino = []);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 7),
                            decoration: BoxDecoration(
                              color: precio != null ? Colors.blue[50] : Colors.grey[100],
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                  color: precio != null ? Colors.blue[200]! : Colors.grey[400]!),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.location_city,
                                    color: precio != null ? Colors.blue[600] : Colors.grey[600],
                                    size: 14),
                                const SizedBox(width: 4),
                                Text(
                                  precioStr != null ? '$nombre ($precioStr)' : nombre,
                                  style: TextStyle(
                                    color: precio != null ? Colors.blue[900] : Colors.grey[800],
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ], // fin if RECOGIDA LOCAL

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

                // MOTOR DE TARIFAS — oculto para RECOGIDA LOCAL (sin tarifa)
                if (tipoServicio != 'RECOGIDA LOCAL')
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
                          (tipoServicio != 'RECOGIDA LOCAL' && destinoController.text.trim().isEmpty)) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('El origen es obligatorio.'),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }

                      // La cotización (precio vacío) existe para que Local
                      // o Cliente le pidan un precio a Central. No tiene
                      // sentido que Central se pida una cotización a sí
                      // misma — siempre debe poner el precio final.
                      // Excepción: RECOGIDA LOCAL no tiene tarifa.
                      final String tarifaSinFormato = tarifaController.text
                          .replaceAll('\$', '')
                          .replaceAll('.', '')
                          .replaceAll(',', '')
                          .trim();
                      final double tarifaValidada =
                          double.tryParse(tarifaSinFormato) ?? 0.0;
                      if (tipoServicio != 'RECOGIDA LOCAL' && tarifaValidada <= 0) {
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
                      } else if (tipoServicio == 'RECOGIDA LOCAL') {
                        observacionFinal = '[ RECOGIDA LOCAL ] - Sin tarifa ni destino';
                        if (telReceptor.isNotEmpty) { observacionFinal += '\n📞 Tel: $telReceptor'; }
                        if (detalles.isNotEmpty) { observacionFinal += '\n$detalles'; }
                        if (movilDirectoServimotoNombre != null) {
                          observacionFinal += '\n📌 Asignado a: $movilDirectoServimotoNombre';
                        }
                      }

                      try {
                        // ---> UNIFICACIÓN: ESCÁNER MULTI-PARADERO DESDE CENTRAL <---
                        String? exclusivoIdCampo;

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

                        // Si hay asignación directa, el exclusivo_id
                        // es solo ese móvil (nadie más lo ve en el radar)
                        if (movilDirectoServimotoId != null) {
                          exclusivoIdCampo = movilDirectoServimotoId;
                        }

                        // INSERCIÓN EN BD CON MULTI-ID DE PARADERO
                        final insertedSvc = await Supabase.instance.client
                            .from('servicios')
                            .insert({
                              'origen': origenController.text
                                  .trim()
                                  .toUpperCase(),
                              if (tipoServicio != 'RECOGIDA LOCAL')
                                'destino': destinoController.text
                                    .trim()
                                    .toUpperCase(),
                              'telefono_receptor': telReceptor.isEmpty
                                  ? null
                                  : telReceptor,
                              if (tipoServicio != 'RECOGIDA LOCAL' && tarifaFinal > 0) ...{
                                'tarifa': tarifaFinal,
                                'tarifa_detalle': detalleActual ??
                                    {'total': tarifaFinal, 'fuente': 'central'},
                              },
                              'observacion': observacionFinal,
                              'estado': 'pendiente',
                              'creador': 'Central',
                              'tipo_servicio': tipoServicio,
                              'metodo_pago': 'Efectivo',
                              'archivado': false,
                              'exclusivo_id': exclusivoIdCampo,
                              if (origenLatCapturada != null)
                                'origen_lat': origenLatCapturada,
                              if (origenLngCapturada != null)
                                'origen_lng': origenLngCapturada,
                              if (paraderoOrigen != null)
                                'paradero_origen': paraderoOrigen,
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
                        if (movilDirectoServimotoId != null) {
                          // ASIGNACIÓN DIRECTA — notificación solo al móvil elegido
                          final String origenSnap = origenController.text.trim();
                          await MotorNotificaciones.dispararMisil(
                            idDestino: movilDirectoServimotoId!,
                            titulo: '📌 SERVICIO ASIGNADO',
                            mensaje: 'Central te asignó un servicio en $origenSnap',
                            urgente: true,
                            sonido: Sonidos.movilParadero,
                          );
                        } else {
                          // ══════════════════════════════════════════════════
                          // CASCADA 4 FASES (no-FN):
                          //  FASE 1 (0–30s)  → Masters ven card con detalles
                          //  FASE 2 (30–60s) → #1 paradero auto-asignado por
                          //                    pg_cron (fn-auto-asignar-fase2)
                          //  FASE 3 (60–90s) → Zona 2km, botón aceptar
                          //  FASE 4 (90s+)   → Todos disponibles
                          // ══════════════════════════════════════════════════

                          // --- Encontrar #1 del paraderoOrigen para pg_cron ---
                          String? paraderoAutoMovilId;
                          if (paraderoOrigen != null) {
                            try {
                              final filaParadero = await Supabase.instance.client
                                  .from('usuarios')
                                  .select('id')
                                  .eq('rol', 'movil')
                                  .eq('en_linea', true)
                                  .eq('activo', true)
                                  .eq('tiene_se', true)
                                  .eq('paradero_actual', paraderoOrigen!)
                                  .not('suspendido', 'is', true)
                                  .order('ingreso_fila', ascending: true);
                              final activosSvc = await Supabase.instance.client
                                  .from('servicios')
                                  .select('movil_id')
                                  .inFilter('estado', [
                                    'en_ruta_origen', 'en_origen',
                                    'en_ruta_destino', 'problema',
                                  ])
                                  .not('movil_id', 'is', null);
                              final idsOcupados = (activosSvc as List)
                                  .map((s) => s['movil_id'].toString())
                                  .toSet();
                              for (final m in filaParadero as List) {
                                final mId = m['id'].toString();
                                if (!idsOcupados.contains(mId)) {
                                  paraderoAutoMovilId = mId;
                                  break;
                                }
                              }
                              if (paraderoAutoMovilId != null) {
                                await Supabase.instance.client
                                    .from('servicios')
                                    .update({'paradero_auto_movil_id': paraderoAutoMovilId})
                                    .eq('id', nuevoServicioId);
                              }
                            } catch (_) {}
                          }

                          // --- FASE 1 (T=0): MASTERS ---
                          // Solo suscripción. Master no tiene tope de servicios activos
                          // — el tope de 10 es de notificaciones simultáneas (anti-saturación),
                          // no de cuántos servicios puede llevar.
                          var idsMasters = <String>[];
                          try {
                            final mastersResp = await Supabase.instance.client
                                .rpc(
                                  'moviles_elegibles_notificacion',
                                  params: {
                                    'p_solo_master': true,
                                    'p_solo_completamente_libres': false,
                                    'p_tiene_se': true,
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
                                sonido: 'master',
                                canalAndroidId: MotorNotificaciones.canalMasterId,
                              );
                            }
                          } catch (_) {}

                          // FASE 2 (T+30s): pg_cron auto-asigna al #1 del paradero.
                          // No se programa notificación aquí — el cron envía el
                          // headsup tras asignar. paradero_auto_movil_id ya fue
                          // guardado arriba.

                          // --- FASE 3 (T+60s) y FASE 4 (T+90s) ---
                          // Ambas fases usan la RPC moviles_elegibles_notificacion
                          // para respetar el cupo por rango (NOVATO/PRO=1, ELITE=2,
                          // LEYENDA=3, MASTER=sin tope) y excluir prediarios/postdia
                          // que son FN exclusivo.
                          {
                            final int svcId = nuevoServicioId;
                            final String msg = tipoServicio == 'RECOGIDA LOCAL'
                                ? 'Recogida Local en ${origenController.text.trim()}'
                                : 'Nuevo servicio disponible en el radar';
                            final List<String> masterSnap = List<String>.from(idsMasters);
                            // Excluir Masters y #1 del paradero (auto-asignado por cron)
                            final List<String> excluidos = [
                              ...masterSnap,
                              if (paraderoAutoMovilId != null) paraderoAutoMovilId,
                            ];

                            final double? oLat = origenLatCapturada;
                            final double? oLng = origenLngCapturada;

                            // FASE 3: zona 2km — solo suscripción, respeta cupo por rango
                            // (Novato/Pro: 0 activos; Elite: <2; Leyenda: <3; Master: <10)
                            List<String> idsZonaC = [];
                            try {
                              final params3 = <String, dynamic>{
                                'p_solo_master': false,
                                'p_solo_completamente_libres': false,
                                'p_radio_metros': 2000.0,
                                'p_tiene_se': true,
                              };
                              if (oLat != null) params3['p_origen_lat'] = oLat;
                              if (oLng != null) params3['p_origen_lng'] = oLng;
                              final resp3 = await Supabase.instance.client
                                  .rpc('moviles_elegibles_notificacion', params: params3);
                              idsZonaC = (resp3 as List)
                                  .map((m) => m['id'].toString())
                                  .where((id) => !excluidos.contains(id))
                                  .toList();
                            } catch (_) {}

                            // FASE 4: todos los conectados — solo suscripción, respeta cupo
                            List<String> idsTodosC = [];
                            try {
                              final resp4 = await Supabase.instance.client.rpc(
                                'moviles_elegibles_notificacion',
                                params: {
                                  'p_solo_master': false,
                                  'p_solo_completamente_libres': false,
                                  'p_tiene_se': true,
                                },
                              );
                              idsTodosC = (resp4 as List)
                                  .map((m) => m['id'].toString())
                                  .where((id) => !masterSnap.contains(id))
                                  .toList();
                            } catch (_) {}

                            String? id60sC;
                            String? id90sC;
                            if (idsZonaC.isNotEmpty) {
                              id60sC = await MotorNotificaciones.programarMisilRetardado(
                                externalIds: idsZonaC,
                                titulo: '📡 SERVICIO CERCA (2km)',
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
                          final bool yaEstaEnRed = dirUsuarioNombres.any((
                            dir,
                          ) {
                            final String nombreDir = dir.contains(' (')
                                ? dir.split(' (')[0].trim().toUpperCase()
                                : dir.trim().toUpperCase();
                            return nombreDir == barrioExtraido;
                          });

                          if (tarifaFinal > 0 &&
                              !yaEstaEnRed &&
                              barrioExtraido.isNotEmpty &&
                              localSeleccionadoId != null) {
                            final barrioCtrl = TextEditingController(
                              text: barrioExtraido,
                            );
                            final sectorCtrl = TextEditingController();
                            String zonaSeleccionada = 'CÚCUTA';
                            bool guardandoRed = false;

                            // Usamos this.context (del State) en lugar del
                            // context del builder del diálogo, que ya se
                            // destruyó con el Navigator.pop de arriba.
                            showDialog(
                              context: this.context,
                              builder: (ctxSave) => StatefulBuilder(
                                builder: (ctxSave, setSaveState) => AlertDialog(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  title: const Text(
                                    '💾 ¿GUARDAR EN LA LISTA SE?',
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
                                        'Esta dirección no está en la lista del local. '
                                        '¿La guardamos en su red de direcciones SE?',
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
                                      const SizedBox(height: 10),
                                      TextField(
                                        controller: sectorCtrl,
                                        textCapitalization:
                                            TextCapitalization.characters,
                                        decoration: const InputDecoration(
                                          labelText:
                                              'Sector (Ej: TRAPICHES, PRADOS DEL ESTE)',
                                          hintText: 'Opcional',
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
                                                    .from('red_dir_se')
                                                    .insert({
                                                      'usuario_id': localSeleccionadoId,
                                                      'nombre': barrioCtrl.text
                                                          .trim()
                                                          .toUpperCase(),
                                                      'municipio':
                                                          zonaSeleccionada,
                                                      'activo': true,
                                                    });
                                                if (ctxSave.mounted) {
                                                  Navigator.pop(ctxSave);
                                                  ScaffoldMessenger.of(
                                                    this.context,
                                                  ).showSnackBar(
                                                    const SnackBar(
                                                      content: Text(
                                                        '✅ Dirección guardada en la lista SE del local.',
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
                                                    this.context,
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
    if (tipo == 'FN') return 'FN${s['numero']} – $nombre';
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

    // ── Estado de lluvia (leído una vez al abrir el form) ─────────────────────
    bool lluviaActiva = false;
    int recargoLluvia = 1000;
    try {
      final cfg = await Supabase.instance.client
          .from('config_sistema')
          .select('lluvia_activa, recargo_lluvia')
          .eq('id', 1)
          .single();
      lluviaActiva = cfg['lluvia_activa'] as bool? ?? false;
      recargoLluvia = (cfg['recargo_lluvia'] as num?)?.toInt() ?? 1000;
    } catch (_) {}

    if (!context.mounted) return;

    // ── Modo de envío FN ──────────────────────────────────────────────────────
    String modoAsignacion = 'radar'; // 'radar' | 'paradero' | 'directa'
    String? movilDirectoId;
    String? movilDirectoNombre;
    bool movilDirectoSobreLimite = false;
    List<Map<String, dynamic>> movilesDirectaCache = [];
    bool cargandoMovilesDirecta = false;
    // Paradero seleccionado en modo 'paradero'
    String? paraderoFN;

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
                    const Text('Destino (opcional):',
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
                      onChanged: (_) => setDialogState(() {}),
                      decoration: InputDecoration(
                        hintText: 'Mínimo \$4.000',
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
                        activeThumbColor: Colors.blue[700],
                        onChanged: procesando
                            ? null
                            : (v) => setDialogState(() => vaConDatafono = v),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // ── Resumen de cobro ─────────────────────────────────────
                    Builder(builder: (_) {
                      final base = double.tryParse(
                              tarifaCtrl.text.replaceAll(',', '.')) ??
                          0;
                      final extraRecogidas =
                          recogidasSel.where((s) => s != null).length - 1;
                      final recDatafono = vaConDatafono ? 2000 : 0;
                      final recLluvia = lluviaActiva ? recargoLluvia : 0;
                      final total = base + recDatafono + recLluvia;
                      final fmt = (double v) {
                        final n = v.toInt();
                        final s = n.toString();
                        final buf = StringBuffer();
                        for (int i = 0; i < s.length; i++) {
                          if (i > 0 &&
                              (s.length - i) % 3 == 0) buf.write('.');
                          buf.write(s[i]);
                        }
                        return '\$${buf.toString()}';
                      };
                      if (base <= 0 && !vaConDatafono && !lluviaActiva) {
                        return const SizedBox.shrink();
                      }
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.indigo[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.indigo[200]!),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Resumen de cobro',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.indigo)),
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Base',
                                    style: TextStyle(fontSize: 12)),
                                Text(fmt(base),
                                    style: const TextStyle(fontSize: 12)),
                              ],
                            ),
                            if (vaConDatafono) ...[
                              const SizedBox(height: 2),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('+ Datáfono',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.blue)),
                                  Text(fmt(2000),
                                      style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.blue)),
                                ],
                              ),
                            ],
                            if (lluviaActiva) ...[
                              const SizedBox(height: 2),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('+ Lluvia 🌧️',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.blue[700])),
                                  Text(fmt(recargoLluvia.toDouble()),
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.blue[700])),
                                ],
                              ),
                            ],
                            if (extraRecogidas > 0) ...[
                              const SizedBox(height: 2),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                      '+ $extraRecogidas recogida${extraRecogidas > 1 ? 's' : ''} extra',
                                      style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.orange)),
                                  const Text('(incluir en base)',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.orange,
                                          fontStyle: FontStyle.italic)),
                                ],
                              ),
                            ],
                            const Divider(height: 10),
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('TOTAL',
                                    style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold)),
                                Text(fmt(total),
                                    style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.indigo)),
                              ],
                            ),
                          ],
                        ),
                      );
                    }),
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
                    const SizedBox(height: 14),

                    // ── Modo de envío FN ─────────────────────────────────────
                    // RADAR: cascada 3 fases (Master→Cercano→Todos)
                    // PARADERO: asigna al #1 del paradero elegido
                    // DIRECTO: la central asigna a un móvil específico
                    const Text('Modo de envío:',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.black54,
                            fontSize: 12)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: procesando
                                ? null
                                : () => setDialogState(
                                    () => modoAsignacion = 'radar'),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 9, horizontal: 4),
                              decoration: BoxDecoration(
                                color: modoAsignacion == 'radar'
                                    ? Colors.indigo[900]
                                    : Colors.grey[100],
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                    color: Colors.indigo[900]!, width: 1.5),
                              ),
                              child: Text(
                                '📡  RADAR',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: modoAsignacion == 'radar'
                                      ? Colors.white
                                      : Colors.indigo[900],
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: GestureDetector(
                            onTap: procesando
                                ? null
                                : () => setDialogState(() {
                                      modoAsignacion = 'paradero';
                                      paraderoFN ??= 'EXPUENTE';
                                    }),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 9, horizontal: 4),
                              decoration: BoxDecoration(
                                color: modoAsignacion == 'paradero'
                                    ? Colors.teal[700]
                                    : Colors.grey[100],
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                    color: Colors.teal[700]!, width: 1.5),
                              ),
                              child: Text(
                                '📍  PARADERO',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: modoAsignacion == 'paradero'
                                      ? Colors.white
                                      : Colors.teal[700],
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: GestureDetector(
                            onTap: procesando
                                ? null
                                : () async {
                                    setDialogState(() {
                                      modoAsignacion = 'directa';
                                      if (movilesDirectaCache.isEmpty)
                                        cargandoMovilesDirecta = true;
                                    });
                                    if (movilesDirectaCache.isEmpty) {
                                      try {
                                        final data = await Supabase
                                            .instance.client
                                            .from('usuarios')
                                            .select('id, nombre, usuario, rango_movil')
                                            .eq('rol', 'movil')
                                            .eq('activo', true)
                                            .eq('en_linea', true)
                                            .not('suspendido', 'is', true)
                                            .eq('tiene_fn', true)
                                            .order('usuario');
                                        final activos = await Supabase
                                            .instance.client
                                            .from('servicios')
                                            .select('movil_id')
                                            .inFilter('estado', [
                                              'en_ruta_origen',
                                              'en_origen',
                                              'en_ruta_destino',
                                              'problema',
                                            ])
                                            .not('movil_id', 'is', null);
                                        final Map<String, int> cnt = {};
                                        for (final sv in activos as List) {
                                          final sid =
                                              sv['movil_id'].toString();
                                          cnt[sid] = (cnt[sid] ?? 0) + 1;
                                        }
                                        int limR(String? r) {
                                          switch (r?.toUpperCase().trim()) {
                                            case 'PRO': return 1;
                                            case 'ELITE': return 2;
                                            case 'LEYENDA': return 3;
                                            case 'MASTER': return 999;
                                            default: return 1;
                                          }
                                        }
                                        final lista = (data as List)
                                            .map<Map<String, dynamic>>((m) {
                                          final sobreLimite =
                                              (cnt[m['id'].toString()] ?? 0) >=
                                                  limR(m['rango_movil']
                                                      ?.toString());
                                          return {
                                            ...Map<String, dynamic>.from(m),
                                            'sobre_limite': sobreLimite,
                                          };
                                        }).toList()
                                          ..sort((a, b) {
                                            final na = int.tryParse(RegExp(r'\d+').firstMatch(a['usuario']?.toString() ?? '')?.group(0) ?? '') ?? 9999;
                                            final nb = int.tryParse(RegExp(r'\d+').firstMatch(b['usuario']?.toString() ?? '')?.group(0) ?? '') ?? 9999;
                                            return na.compareTo(nb);
                                          });
                                        setDialogState(() {
                                          movilesDirectaCache = lista;
                                          cargandoMovilesDirecta = false;
                                        });
                                      } catch (_) {
                                        setDialogState(() =>
                                            cargandoMovilesDirecta = false);
                                      }
                                    }
                                  },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 9, horizontal: 4),
                              decoration: BoxDecoration(
                                color: modoAsignacion == 'directa'
                                    ? Colors.orange[800]
                                    : Colors.grey[100],
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                    color: Colors.orange[800]!, width: 1.5),
                              ),
                              child: Text(
                                '👤  ASIGNAR MÓVIL',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: modoAsignacion == 'directa'
                                      ? Colors.white
                                      : Colors.orange[800],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                    // Selector de paradero — solo en modo paradero
                    if (modoAsignacion == 'paradero') ...[
                      const SizedBox(height: 10),
                      const Text('Paradero destino:',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.black54,
                              fontSize: 12)),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: ['EXPUENTE', 'MEMOS', 'BOCONO', 'NOCTURNO']
                            .map((p) {
                          final bool sel = paraderoFN == p;
                          return ChoiceChip(
                            label: Text(p,
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: sel ? Colors.white : Colors.teal[700])),
                            selected: sel,
                            selectedColor: Colors.teal[700],
                            backgroundColor: Colors.grey[100],
                            side: BorderSide(color: Colors.teal[700]!, width: 1.5),
                            onSelected: procesando
                                ? null
                                : (v) => setDialogState(
                                    () => paraderoFN = v ? p : paraderoFN),
                          );
                        }).toList(),
                      ),
                    ],

                    // Selector de móvil — solo en modo directa
                    if (modoAsignacion == 'directa') ...[
                      const SizedBox(height: 10),
                      if (cargandoMovilesDirecta)
                        const Center(
                            child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2)))
                      else if (movilesDirectaCache.isEmpty)
                        const Text('Sin móviles FN registrados',
                            style: TextStyle(
                                fontSize: 12, color: Colors.black38))
                      else
                        DropdownButtonFormField<String>(
                          value: movilDirectoId,
                          isExpanded: true,
                          hint: const Text('Seleccionar móvil...',
                              style: TextStyle(
                                  fontSize: 13, color: Colors.black38)),
                          decoration: InputDecoration(
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8)),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                          ),
                          items: movilesDirectaCache
                              .map((m) => DropdownMenuItem<String>(
                                    value: m['id'].toString(),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            () {
                                              final usr = m['usuario']?.toString() ?? '';
                                              final num = RegExp(r'\d+').firstMatch(usr)?.group(0);
                                              return num != null ? 'Móvil $num' : (m['nombre']?.toString() ?? '—');
                                            }(),
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 13,
                                              color:
                                                  m['sobre_limite'] == true
                                                      ? Colors.orange[700]
                                                      : Colors.black87,
                                            ),
                                          ),
                                        ),
                                        if (m['sobre_limite'] == true)
                                          const Text(' ⚠️',
                                              style: TextStyle(fontSize: 12)),
                                      ],
                                    ),
                                  ))
                              .toList(),
                          onChanged: procesando
                              ? null
                              : (v) {
                                  final sel = movilesDirectaCache
                                      .firstWhere(
                                          (m) => m['id'].toString() == v,
                                          orElse: () => <String, dynamic>{});
                                  setDialogState(() {
                                    movilDirectoId = v;
                                    final usr = sel['usuario']?.toString() ?? '';
                                    final num = RegExp(r'\d+').firstMatch(usr)?.group(0);
                                    movilDirectoNombre = num != null
                                        ? 'Móvil $num'
                                        : sel['nombre']?.toString();
                                    movilDirectoSobreLimite =
                                        sel['sobre_limite'] == true;
                                  });
                                },
                        ),
                      if (movilDirectoSobreLimite && movilDirectoId != null)
                        Container(
                          margin: const EdgeInsets.only(top: 6),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.orange[50],
                            borderRadius: BorderRadius.circular(6),
                            border:
                                Border.all(color: Colors.orange[300]!),
                          ),
                          child: const Text(
                            '⚠️ Este móvil está en su límite de servicios. La central puede forzar la asignación.',
                            style: TextStyle(
                                fontSize: 11,
                                color: Colors.deepOrange),
                          ),
                        ),
                    ],
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
                        final tarifaBase = double.tryParse(
                                tarifaCtrl.text.replaceAll(',', '.')) ??
                            0;
                        final tarifa = tarifaBase +
                            (vaConDatafono ? 2000 : 0) +
                            (lluviaActiva ? recargoLluvia : 0);
                        if (tarifaBase < 4000) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('La tarifa mínima es \$4.000'),
                              backgroundColor: Colors.red,
                            ),
                          );
                          return;
                        }

                        setDialogState(() => procesando = true);

                        try {
                          final sede = sedeSolicitante!;
                          final zona = sede['zona'] as String;
                          final zonaLabel = _fnLabelZona(zona);
                          final sLat = (sede['lat'] as num?)?.toDouble();
                          final sLng = (sede['lng'] as num?)?.toDouble();
                          final nombreSede = _fnLabelSede(sede);

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

                          // Si la primera recogida tiene coords, usarlas como
                          // referencia de proximidad (Fase 2/3) — el móvil va
                          // primero a la recogida, no a la sede.
                          final primeraRecLat = recogidasList.isNotEmpty
                              ? (recogidasList.first['lat'] as num?)?.toDouble()
                              : null;
                          final primeraRecLng = recogidasList.isNotEmpty
                              ? (recogidasList.first['lng'] as num?)?.toDouble()
                              : null;
                          final refLat = primeraRecLat ?? sLat;
                          final refLng = primeraRecLng ?? sLng;

                          if (modoAsignacion == 'directa') {
                            // ══════════════════════════════════════════════════
                            // ASIGNACIÓN DIRECTA — la central elige el móvil.
                            // El servicio nace ya asignado (en_ruta_origen).
                            // No entra al radar ni dispara la cascada de fases.
                            // ══════════════════════════════════════════════════
                            if (movilDirectoId == null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text(
                                        'Selecciona el móvil a asignar'),
                                    backgroundColor: Colors.orange),
                              );
                              setDialogState(() => procesando = false);
                              return;
                            }

                            // Confirmación si el móvil está sobre su límite
                            if (movilDirectoSobreLimite) {
                              bool confirmo = false;
                              await showDialog(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text('⚠️ MÓVIL EN LÍMITE'),
                                  content: Text(
                                    '${movilDirectoNombre ?? 'Este móvil'} ya está en su límite de servicios simultáneos.\n\n¿Asignar de todas formas?',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx),
                                      child: const Text('Cancelar'),
                                    ),
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                          backgroundColor:
                                              Colors.orange[700]),
                                      onPressed: () {
                                        confirmo = true;
                                        Navigator.pop(ctx);
                                      },
                                      child: const Text(
                                        'FORZAR ASIGNACIÓN',
                                        style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                              if (!confirmo) {
                                setDialogState(() => procesando = false);
                                return;
                              }
                            }

                            final ahora =
                                DateTime.now().toUtc().toIso8601String();

                            await Supabase.instance.client
                                .from('servicios')
                                .insert({
                              'origen': nombreSede,
                              'destino':
                                  destinoCtrl.text.trim().toUpperCase(),
                              'tarifa': tarifa,
                              'estado': 'en_ruta_origen',
                              'creador': 'Central FN',
                              'tipo_servicio': 'FARMANORTE',
                              'tipo_fn': true,
                              'zona_fn': zona,
                              'fn_sede_id': sede['id'],
                              'recogidas': recogidasList,
                              'metodo_pago':
                                  vaConDatafono ? 'Datafono' : 'Efectivo',
                              'archivado': false,
                              'movil_id': int.tryParse(movilDirectoId!),
                              'accepted_at': ahora,
                              'fn_asignacion_tipo': 'directa',
                              'fn_asignado_por': 'Central',
                              if (sede['sector'] != null &&
                                  (sede['sector'] as String).trim().isNotEmpty)
                                'fn_sector_sede': (sede['sector'] as String).trim(),
                              if (sLat != null) 'origen_lat': sLat,
                              if (sLng != null) 'origen_lng': sLng,
                              if (sede['telefono_whatsapp'] != null &&
                                  (sede['telefono_whatsapp'] as String)
                                      .isNotEmpty)
                                'fn_whatsapp':
                                    sede['telefono_whatsapp'] as String,
                              if (instruccionesCtrl.text.trim().isNotEmpty)
                                'instrucciones_especiales':
                                    instruccionesCtrl.text.trim(),
                            });

                            // Notificación diferenciada: no es "turno disponible",
                            // es "la central te asignó" — tono y título distintos
                            await MotorNotificaciones.dispararRafa(
                              idsDestinos: [movilDirectoId!],
                              titulo: '📋 CENTRAL TE ASIGNÓ UN TURNO FN',
                              mensaje:
                                  'Tienes un servicio Farmanorte asignado · $zonaLabel',
                              urgente: true,
                              sonido: Sonidos.movilParadero,
                            );

                            if (context.mounted) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'FN asignado directamente a ${movilDirectoNombre ?? movilDirectoId}',
                                  ),
                                  backgroundColor: Colors.orange[700],
                                ),
                              );
                            }
                          } else if (modoAsignacion == 'paradero') {
                            // ══════════════════════════════════════════════════
                            // CASCADA PARADERO FN — 4 FASES
                            // Igual que Radar, pero Fase 2 auto-asigna al #1
                            // del paradero elegido (no al más cercano por GPS).
                            //
                            // FASE 1 (T=0,   inmediato) → SOLO Masters
                            // FASE 2 (T+30s, pg_cron)  → #1 del paradero
                            // FASE 3 (T+60s, programado) → no-masters 2km
                            // FASE 4 (T+90s, programado) → resto global
                            // ══════════════════════════════════════════════════
                            if (paraderoFN == null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('Selecciona un paradero'),
                                    backgroundColor: Colors.orange),
                              );
                              setDialogState(() => procesando = false);
                              return;
                            }

                            final ahora = DateTime.now().toUtc().toIso8601String();

                            // 1. Cargar todos los móviles FN online
                            final movilesDataP = await Supabase.instance.client
                                .from('usuarios')
                                .select('id, rango_movil, latitud, longitud, tipo_plan_movil, saldo_wallet')
                                .eq('rol', 'movil')
                                .eq('en_linea', true)
                                .eq('activo', true)
                                .eq('tiene_fn', true)
                                .not('suspendido', 'is', true);

                            final movilesAllP = (movilesDataP as List).where((m) {
                              final plan = m['tipo_plan_movil']?.toString() ?? '';
                              if (plan == 'prediario') {
                                return ((m['saldo_wallet'] as num?)?.toDouble() ?? 0.0) > 0;
                              }
                              return true;
                            }).toList();

                            final mastersP = movilesAllP
                                .where((m) => m['rango_movil']?.toString().toUpperCase() == 'MASTER')
                                .toList();
                            final noMastersP = movilesAllP
                                .where((m) => m['rango_movil']?.toString().toUpperCase() != 'MASTER')
                                .toList();
                            final masterIdsP = mastersP.map<String>((m) => m['id'].toString()).toList();
                            final noMasterIdsP = noMastersP.map<String>((m) => m['id'].toString()).toList();

                            // 2. Buscar el #1 del paradero
                            final filaParaderoP = await Supabase.instance.client
                                .from('usuarios')
                                .select('id, usuario, ingreso_fila')
                                .eq('rol', 'movil')
                                .eq('en_linea', true)
                                .eq('activo', true)
                                .eq('tiene_fn', true)
                                .eq('paradero_actual', paraderoFN!)
                                .not('suspendido', 'is', true)
                                .order('ingreso_fila', ascending: true)
                                .limit(1);

                            String? paraderoMovilId;
                            String? paraderoMovilNombre;
                            if ((filaParaderoP as List).isNotEmpty) {
                              final primero = filaParaderoP.first;
                              paraderoMovilId = primero['id'].toString();
                              final usr = primero['usuario']?.toString() ?? '';
                              final numStr = RegExp(r'\d+').firstMatch(usr)?.group(0);
                              paraderoMovilNombre = numStr != null ? 'Móvil $numStr' : usr;
                            }

                            if (paraderoMovilId == null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('No hay móviles FN en el paradero $paraderoFN'),
                                  backgroundColor: Colors.red[700],
                                ),
                              );
                              setDialogState(() => procesando = false);
                              return;
                            }

                            // 3. Fase 3 — no-masters dentro de 2km (excl. #1 paradero)
                            final fase3IdsP = noMastersP.where((m) {
                              final id = m['id'].toString();
                              if (id == paraderoMovilId) return false;
                              if (refLat == null || refLng == null) return false;
                              final uLat = (m['latitud'] as num?)?.toDouble();
                              final uLng = (m['longitud'] as num?)?.toDouble();
                              if (uLat == null || uLng == null) return false;
                              return const Distance().as(
                                    LengthUnit.Meter,
                                    LatLng(uLat, uLng),
                                    LatLng(refLat, refLng),
                                  ) <= 2000;
                            }).map<String>((m) => m['id'].toString()).toList();

                            // 4. Fase 4 — resto global (excl. #1 paradero y fase 3)
                            final fase4IdsP = noMasterIdsP
                                .where((id) => id != paraderoMovilId && !fase3IdsP.contains(id))
                                .toList();

                            // ── FASE 1 (T=0): heads-up exclusivo a MASTERS ──
                            if (masterIdsP.isNotEmpty) {
                              await MotorNotificaciones.dispararRafa(
                                idsDestinos: masterIdsP,
                                titulo: '👑 TURNO FN — MASTER',
                                mensaje: 'Servicio Farmanorte · $zonaLabel',
                                urgente: true,
                                sonido: 'master',
                                canalAndroidId: MotorNotificaciones.canalMasterId,
                              );
                            }

                            // ── Insertar servicio en BD ──────────────────────
                            // Estado 'pendiente' — el pg_cron auto-asigna al #1
                            // del paradero a T+30s via fn_fase2_movil_id.
                            final insertedSvcP = await Supabase.instance.client
                                .from('servicios')
                                .insert({
                                  'origen': nombreSede,
                                  'destino': destinoCtrl.text.trim().toUpperCase(),
                                  'tarifa': tarifa,
                                  'estado': tarifa > 0 ? 'pendiente' : 'cotizacion',
                                  'creador': 'Central FN',
                                  'tipo_servicio': 'FARMANORTE',
                                  'tipo_fn': true,
                                  'zona_fn': zona,
                                  'fn_sede_id': sede['id'],
                                  'recogidas': recogidasList,
                                  'metodo_pago': vaConDatafono ? 'Datafono' : 'Efectivo',
                                  'archivado': false,
                                  'fn_radar_t0': ahora,
                                  'fn_asignacion_tipo': 'paradero',
                                  'fn_fase2_movil_id': paraderoMovilId,
                                  'paradero_origen': paraderoFN,
                                  if (masterIdsP.isNotEmpty)
                                    'fn_notificados_fase1': masterIdsP,
                                  if (sede['sector'] != null &&
                                      (sede['sector'] as String).trim().isNotEmpty)
                                    'fn_sector_sede': (sede['sector'] as String).trim(),
                                  if (refLat != null) 'origen_lat': refLat,
                                  if (refLng != null) 'origen_lng': refLng,
                                  if (sede['telefono_whatsapp'] != null &&
                                      (sede['telefono_whatsapp'] as String).isNotEmpty)
                                    'fn_whatsapp': sede['telefono_whatsapp'] as String,
                                  if (instruccionesCtrl.text.trim().isNotEmpty)
                                    'instrucciones_especiales': instruccionesCtrl.text.trim(),
                                })
                                .select('id')
                                .single();

                            final int nuevoIdP = (insertedSvcP['id'] as num).toInt();

                            // ── FASE 3 (T+60s): zona 2km ─────────────────────
                            String? notifFase3P;
                            if (fase3IdsP.isNotEmpty) {
                              notifFase3P = await MotorNotificaciones.programarMisilRetardado(
                                externalIds: fase3IdsP,
                                titulo: '🔵 TURNO FN CERCA',
                                mensaje: 'Servicio Farmanorte disponible · $zonaLabel',
                                segundosRetardo: 60,
                                sonido: Sonidos.movilParadero,
                              );
                            }

                            // ── FASE 4 (T+90s): global ───────────────────────
                            String? notifFase4P;
                            if (fase4IdsP.isNotEmpty) {
                              notifFase4P = await MotorNotificaciones.programarMisilRetardado(
                                externalIds: fase4IdsP,
                                titulo: '🔵 TURNO FN SIN TOMAR',
                                mensaje: 'Servicio Farmanorte · $zonaLabel',
                                segundosRetardo: 90,
                                sonido: Sonidos.movilParadero,
                              );
                            }

                            // ── FASE 4b (T+90s): re-alerta Masters ───────────
                            String? notifFase4bP;
                            if (masterIdsP.isNotEmpty) {
                              notifFase4bP = await MotorNotificaciones.programarMisilRetardado(
                                externalIds: masterIdsP,
                                titulo: '🚨 FN SIN CUBRIR',
                                mensaje: 'Servicio Farmanorte sin tomar · $zonaLabel',
                                segundosRetardo: 90,
                                sonido: 'master',
                                canalAndroidId: MotorNotificaciones.canalMasterId,
                              );
                            }

                            // Guardar IDs para cancelar si alguien acepta
                            if (notifFase3P != null || notifFase4P != null || notifFase4bP != null) {
                              await Supabase.instance.client
                                  .from('servicios')
                                  .update({
                                if (notifFase3P != null) 'fn_notif_fase3': notifFase3P,
                                if (notifFase4P != null) 'fn_notif_fase4': notifFase4P,
                                if (notifFase4bP != null) 'fn_notif_fase4b': notifFase4bP,
                              }).eq('id', nuevoIdP);
                            }

                            if (context.mounted) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'FN Paradero · Masters avisados, $paraderoMovilNombre se auto-asigna en 30s',
                                  ),
                                  backgroundColor: Colors.teal[700],
                                ),
                              );
                            }
                          } else {
                            // ══════════════════════════════════════════════════
                            // CASCADA RADAR FN — 3 FASES
                            // Completamente separada de Serviexpress normal.
                            // NUNCA toca onesignal_30s / onesignal_2m / onesignal_5m.
                            //
                            // FASE 1 (T=0,  inmediato) → SOLO masters con capacidad
                            // FASE 2 (T+31s, programado) → el más cercano a la sede
                            // FASE 3 (T+61s, programado) → todos los FN restantes
                            //
                            // Los IDs se guardan en fn_notif_fase2/3 para
                            // cancelarlos si alguien acepta el servicio.
                            // ══════════════════════════════════════════════════
                            final ahora =
                                DateTime.now().toUtc().toIso8601String();

                            // 1. Cargar todos los móviles FN online
                            final movilesData = await Supabase.instance
                                .client
                                .from('usuarios')
                                .select('id, rango_movil, latitud, longitud, tipo_plan_movil, saldo_wallet')
                                .eq('rol', 'movil')
                                .eq('en_linea', true)
                                .eq('activo', true)
                                .eq('tiene_fn', true)
                                .not('suspendido', 'is', true);

                            // FN: sin límite de capacidad — todos los móviles
                            // FN habilitados reciben notificaciones.
                            // Prediarios con saldo <= 0 quedan excluidos.
                            final movilesAll = (movilesData as List)
                                .where((m) {
                                  final plan = m['tipo_plan_movil']?.toString() ?? '';
                                  if (plan == 'prediario') {
                                    return ((m['saldo_wallet'] as num?)?.toDouble() ?? 0.0) > 0;
                                  }
                                  return true;
                                }).toList();

                            // Separar masters de no-masters (sin filtro de cupo)
                            final masters = movilesAll
                                .where((m) =>
                                    m['rango_movil']
                                            ?.toString()
                                            .toUpperCase() ==
                                        'MASTER')
                                .toList();
                            final noMasters = movilesAll
                                .where((m) =>
                                    m['rango_movil']
                                            ?.toString()
                                            .toUpperCase() !=
                                        'MASTER')
                                .toList();

                            final masterIds = masters
                                .map<String>((m) => m['id'].toString())
                                .toList();
                            final noMasterIds = noMasters
                                .map<String>((m) => m['id'].toString())
                                .toList();

                            // 3. Calcular el móvil más cercano al punto de
                            // referencia: primera recogida si la hay, sede si no.
                            String? fase2MovilId;
                            if (refLat != null &&
                                refLng != null &&
                                noMasters.isNotEmpty) {
                              double minDist = double.infinity;
                              for (final m in noMasters) {
                                final uLat =
                                    (m['latitud'] as num?)?.toDouble();
                                final uLng =
                                    (m['longitud'] as num?)?.toDouble();
                                if (uLat == null || uLng == null) continue;
                                final dist = const Distance().as(
                                  LengthUnit.Meter,
                                  LatLng(uLat, uLng),
                                  LatLng(refLat, refLng),
                                );
                                if (dist < minDist) {
                                  minDist = dist;
                                  fase2MovilId = m['id'].toString();
                                }
                              }
                            } else if (noMasters.isNotEmpty) {
                              // Sin coordenadas → primer disponible
                              fase2MovilId =
                                  noMasters.first['id'].toString();
                            }

                            // Fase 3 (zona 2km desde el punto de referencia):
                            // no-masters dentro del radio, excluyendo el de fase 2.
                            final fase3Ids = noMasterIds.where((id) {
                              if (id == fase2MovilId) return false;
                              if (refLat == null || refLng == null) return false;
                              final mData = noMasters.firstWhere(
                                (m) => m['id'].toString() == id,
                                orElse: () => <String, dynamic>{},
                              );
                              if (mData.isEmpty) return false;
                              final uLat = (mData['latitud'] as num?)?.toDouble();
                              final uLng = (mData['longitud'] as num?)?.toDouble();
                              if (uLat == null || uLng == null) return false;
                              return const Distance().as(
                                    LengthUnit.Meter,
                                    LatLng(uLat, uLng),
                                    LatLng(refLat, refLng),
                                  ) <= 2000;
                            }).toList();

                            // Fase 4 (global): todos los demás no-masters
                            // que no recibieron notificación en fases 2 ni 3.
                            final fase4Ids = noMasterIds
                                .where((id) =>
                                    id != fase2MovilId &&
                                    !fase3Ids.contains(id))
                                .toList();

                            // ── FASE 1 (T=0): heads-up exclusivo a MASTERS ──
                            if (masterIds.isNotEmpty) {
                              await MotorNotificaciones.dispararRafa(
                                idsDestinos: masterIds,
                                titulo: '👑 TURNO FN — MASTER',
                                mensaje:
                                    'Servicio Farmanorte · $zonaLabel',
                                urgente: true,
                                sonido: 'master',
                                canalAndroidId: MotorNotificaciones.canalMasterId,
                              );
                            }

                            // ── Insertar servicio en BD ──────────────────────
                            final insertedSvc = await Supabase.instance
                                .client
                                .from('servicios')
                                .insert({
                                  'origen': nombreSede,
                                  'destino': destinoCtrl.text
                                      .trim()
                                      .toUpperCase(),
                                  'tarifa': tarifa,
                                  'estado': tarifa > 0
                                      ? 'pendiente'
                                      : 'cotizacion',
                                  'creador': 'Central FN',
                                  'tipo_servicio': 'FARMANORTE',
                                  'tipo_fn': true,
                                  'zona_fn': zona,
                                  'fn_sede_id': sede['id'],
                                  'recogidas': recogidasList,
                                  'metodo_pago':
                                      vaConDatafono ? 'Datafono' : 'Efectivo',
                                  'archivado': false,
                                  'fn_radar_t0': ahora,
                                  'fn_asignacion_tipo': 'radar',
                                  if (fase2MovilId != null)
                                    'fn_fase2_movil_id': fase2MovilId,
                                  if (masterIds.isNotEmpty)
                                    'fn_notificados_fase1': masterIds,
                                  if (sede['sector'] != null &&
                                      (sede['sector'] as String).trim().isNotEmpty)
                                    'fn_sector_sede': (sede['sector'] as String).trim(),
                                  if (refLat != null) 'origen_lat': refLat,
                                  if (refLng != null) 'origen_lng': refLng,
                                  if (sede['telefono_whatsapp'] != null &&
                                      (sede['telefono_whatsapp'] as String)
                                          .isNotEmpty)
                                    'fn_whatsapp':
                                        sede['telefono_whatsapp'] as String,
                                  if (instruccionesCtrl.text
                                      .trim()
                                      .isNotEmpty)
                                    'instrucciones_especiales':
                                        instruccionesCtrl.text.trim(),
                                })
                                .select('id')
                                .single();

                            final int nuevoId =
                                (insertedSvc['id'] as num).toInt();

                            // ── FASE 2 (T+30s): auto-asignación via pg_cron ──
                            // El Edge Function fn-auto-asignar-fase2 (cron cada
                            // minuto) detecta fn_fase2_movil_id + fn_radar_t0 y
                            // asigna directamente sin que el móvil deba aceptar.
                            // No se programa notificación aquí; el cron la envía
                            // tras asignar.

                            // ── FASE 3 (T+60s): zona 2km de la sede ─────────
                            String? notifFase3;
                            if (fase3Ids.isNotEmpty) {
                              notifFase3 = await MotorNotificaciones
                                  .programarMisilRetardado(
                                externalIds: fase3Ids,
                                titulo: '🔵 TURNO FN CERCA',
                                mensaje:
                                    'Servicio Farmanorte disponible · $zonaLabel',
                                segundosRetardo: 60,
                                sonido: Sonidos.movilParadero,
                              );
                            }

                            // ── FASE 4 (T+90s): global — todos los demás ────
                            String? notifFase4;
                            if (fase4Ids.isNotEmpty) {
                              notifFase4 = await MotorNotificaciones
                                  .programarMisilRetardado(
                                externalIds: fase4Ids,
                                titulo: '🔵 TURNO FN SIN TOMAR',
                                mensaje:
                                    'Servicio Farmanorte · $zonaLabel',
                                segundosRetardo: 90,
                                sonido: Sonidos.movilParadero,
                              );
                            }

                            // ── FASE 4b (T+90s): re-alerta Masters ───────────
                            String? notifFase4b;
                            if (masterIds.isNotEmpty) {
                              notifFase4b = await MotorNotificaciones
                                  .programarMisilRetardado(
                                externalIds: masterIds,
                                titulo: '🚨 FN SIN CUBRIR',
                                mensaje: 'Servicio Farmanorte sin tomar · $zonaLabel',
                                segundosRetardo: 90,
                                sonido: 'master',
                                canalAndroidId: MotorNotificaciones.canalMasterId,
                              );
                            }

                            // Guardar IDs de misiles FN para cancelarlos
                            // si alguien acepta (NO son onesignal_30s/2m/5m)
                            if (notifFase3 != null || notifFase4 != null || notifFase4b != null) {
                              await Supabase.instance.client
                                  .from('servicios')
                                  .update({
                                if (notifFase3 != null)
                                  'fn_notif_fase3': notifFase3,
                                if (notifFase4 != null)
                                  'fn_notif_fase4': notifFase4,
                                if (notifFase4b != null)
                                  'fn_notif_fase4b': notifFase4b,
                              }).eq('id', nuevoId);
                            }

                            if (context.mounted) {
                              Navigator.pop(context);
                              final totalNotif = masterIds.length +
                                  (fase2MovilId != null ? 1 : 0);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    totalNotif == 0
                                        ? 'Servicio FN creado (sin móviles FN disponibles)'
                                        : 'Servicio FN al radar — ${masterIds.length} master${masterIds.length != 1 ? 's' : ''} notificados',
                                  ),
                                  backgroundColor: Colors.indigo[700],
                                ),
                              );
                            }
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
                    : Text(
                        modoAsignacion == 'directa'
                            ? 'ASIGNAR MÓVIL'
                            : modoAsignacion == 'paradero'
                                ? 'ASIGNAR A PARADERO'
                                : 'ENVIAR AL RADAR',
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
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
                                // Notificar al móvil del secundario si tenía uno asignado
                                final movilIdSec = svcSecundario['movil_id']?.toString();
                                if (movilIdSec != null && movilIdSec.isNotEmpty && movilIdSec != 'null') {
                                  MotorNotificaciones.dispararMisil(
                                    idDestino: movilIdSec,
                                    titulo: '❌ Servicio cancelado',
                                    mensaje: 'El servicio #${svcSecundario['id']} fue fusionado y cancelado.',
                                    urgente: false,
                                    sonido: 'central_cancelado',
                                    canalAndroidId: MotorNotificaciones.canalCanceladoId,
                                  );
                                }

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
        ScaffoldMessenger.of(context).showSnackBar(
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
      context: context,
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('⚡ Cotización enviada: $textoTarifa'),
            backgroundColor: Colors.green[700],
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cotizar: $e'), backgroundColor: Colors.red),
        );
      }
    }
    return true;
  }

}
