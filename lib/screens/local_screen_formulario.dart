// ignore_for_file: curly_braces_in_flow_control_structures, no_leading_underscores_for_local_identifiers, use_build_context_synchronously, unused_element_parameter
part of 'local_screen.dart';

// ══════════════════════════════════════════════════════════════════════════════
// _FormularioMixin — sector, tarifario y formulario de pedido
// ══════════════════════════════════════════════════════════════════════════════
mixin _FormularioMixin on State<LocalScreen> {
  // ── Abstract stubs (implementados en otros mixins / core) ──────────────────
  Future<List<Map<String, dynamic>>> _buscarDireccionesPorTelefono(String telefono);
  Future<double?> _confirmarRecargoObligatorio(double precioBase);
  Future<Map<String, double>?> _obtenerOSellarGPSLocal({bool forzar = false});
  SonidoManager get _sonidos;
  Future<void> _dispararMisilInmediato({
    required List<String> externalIds,
    required String titulo,
    required String mensaje,
    String? sonido,
    String? canalAndroidId,
  });

  // ── FORMULARIO DE PEDIDO ────────────────────────────────────────────────────
  void _abrirFormularioPedido(
    BuildContext context, {
    bool esPuntoAPunto = false,
    required Map<String, dynamic> perfilEnVivo,
    String? telefonoPrellenado, // Viene del botón "NUEVO PEDIDO" en el CRM
    String? movilPreselId,      // ID del móvil activo — abre formulario completo directo a él
    String? movilPreselLabel,   // Etiqueta legible: "MOVIL 03"
  }) async {
    // --- CONSULTA ESPEJO CON "MI LOCAL" ---
    List<Map<String, dynamic>> listaPrecios = [];

    // Carga red SE del local (red_dir_catalogo + se_precios_dir)
    if (!esPuntoAPunto) {
      try {
        final data = await Supabase.instance.client
            .from('se_precios_dir')
            .select('precio, red_dir_catalogo!inner(id, nombre, municipio, sector_id, activo, sectores(nombre))')
            .eq('usuario_id', widget.usuario['id'])
            .eq('red_dir_catalogo.activo', true);
        listaPrecios = List<Map<String, dynamic>>.from(data).map<Map<String, dynamic>>((row) {
          final dir = Map<String, dynamic>.from(row['red_dir_catalogo'] as Map? ?? {});
          return {
            'id': dir['id'],
            'nombre': dir['nombre'],
            'municipio': dir['municipio'],
            'sector_id': dir['sector_id'],
            'precio': row['precio'],
            'activo': dir['activo'],
            'sectores': dir['sectores'],
          };
        }).toList()
          ..sort((a, b) => (a['nombre'] ?? '').toString()
              .compareTo((b['nombre'] ?? '').toString()));
      } catch (_) {}
    }

    if (!context.mounted) return;

    // --- PRECARGA DEL HISTORIAL (si viene de "NUEVO PEDIDO" en el CRM) ---
    List<Map<String, dynamic>> direccionesHistoricasCliente = [];
    if (telefonoPrellenado != null && telefonoPrellenado.length >= 10) {
      direccionesHistoricasCliente = await _buscarDireccionesPorTelefono(
        telefonoPrellenado,
      );
      if (!context.mounted) return;
    }

    // Recargos activos (lluvia / nocturno) que activó la central
    Map<String, dynamic>? recargoActivo;
    try {
      final r = await Supabase.instance.client
          .rpc('calcular_recargo_local', params: {'p_local_id': widget.usuario['id']});
      if (r is List && r.isNotEmpty && r[0]['aplica_recargo'] == true) {
        recargoActivo = Map<String, dynamic>.from(r[0] as Map);
      }
    } catch (_) {}
    if (!context.mounted) return;

    final destinoController = TextEditingController();
    final tarifaController = TextEditingController();
    final notasController = TextEditingController();
    final telefonoController = TextEditingController(
      text: telefonoPrellenado ?? '',
    );
    final ticketController = TextEditingController();

    bool procesando = false;
    bool buscandoCliente = false;
    String tiempoPreparacion = 'Inmediato';
    // Hora exacta elegida con "A una hora…" (sale a los móviles a esa hora)
    DateTime? horaProgramada;

    List<Map<String, dynamic>> sugerenciasListaPrecios = [];
    String? destinoBase; // dirección exacta seleccionada (preserva precio al escribir detalles)
    String? sectorBase;  // sector seleccionado (preserva precio al escribir detalles)

    // Tipo de servicio: desde perfil del local, override mototaxi por pedido
    final String _tipoDefecto =
        widget.usuario['tipo_servicio_defecto']?.toString() ?? 'PAQUETERÍA';
    bool _esMototaxi = false;

    // Modo dinámico: cotización si tarifa vacía, solicitar si tiene precio.
    // PAP = servicio DIRECTO: nunca es cotización (no lleva tarifa).
    bool _esCot = !esPuntoAPunto;
    void Function(VoidCallback)? _setDS;

    // PRECIO AUTOMÁTICO (cotización automática): solo aparece si la central
    // la activó para este local y la ruta ya es confiable. Si no, el pedido
    // va a cotización como siempre (el local no fija precios).
    Timer? debounceSugRuta;
    int pedidoSugRuta = 0;
    Map<String, dynamic>? sugRuta;
    String pesosLocal(num v) {
      final s = v.round().toString();
      final b = StringBuffer();
      for (int i = 0; i < s.length; i++) {
        if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
        b.write(s[i]);
      }
      return '\$$b';
    }
    void buscarSugerenciaRuta(String texto) {
      debounceSugRuta?.cancel();
      final t = texto.trim();
      if (t.length < 4) {
        _setDS?.call(() => sugRuta = null);
        return;
      }
      debounceSugRuta = Timer(const Duration(milliseconds: 700), () async {
        final miPedido = ++pedidoSugRuta;
        try {
          final res = await Supabase.instance.client.rpc('fn_precio_cotizacion', params: {
            'p_local_id': widget.usuario['id'],
            'p_destino': t,
            'p_tipo': _esMototaxi ? 'mototaxi' : _tipoDefecto,
            'p_telefono': telefonoController.text.trim().isEmpty ? null : telefonoController.text.trim(),
          });
          if (miPedido != pedidoSugRuta) return; // llegó una respuesta vieja
          // Solo se muestra cuando el automático aplica (ruta confiable + activado)
          _setDS?.call(() => sugRuta = (res is Map && res['auto'] == true && res['precio'] != null)
              ? Map<String, dynamic>.from(res)
              : null);
        } catch (_) {
          if (miPedido == pedidoSugRuta) _setDS?.call(() => sugRuta = null);
        }
      });
    }
    tarifaController.addListener(() {
      _setDS?.call(() {
        _esCot = !esPuntoAPunto && tarifaController.text.trim().isEmpty;
      });
    });

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          _setDS = setDialogState;
          // Diseño oficial: color del tipo de servicio (PAP morado)
          final EstiloServicio estiloForm =
              EstiloServicio.deTipo(_esMototaxi ? 'mototaxi' : _tipoDefecto);
          final Color colorForm =
              esPuntoAPunto ? const Color(0xFF9B51E0) : estiloForm.color;
          int pasoNum = 0;
          Widget paso(String t) => PasoSE(++pasoNum, t, color: colorForm);
          return Theme(
            data: temaDialogoSE(context, colorForm),
            child: AlertDialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 24,
          ),
          titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
          contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
          actionsPadding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          title: TituloVentanaSE(
            icono: esPuntoAPunto
                ? Icons.card_giftcard
                : (_esMototaxi ? Icons.two_wheeler : estiloForm.icono),
            color: colorForm,
            titulo: _esCot
                ? 'Pedir precio a la Central'
                : (esPuntoAPunto ? 'Punto a Punto' : 'Pedir Móvil'),
            subtitulo: _esCot
                ? 'Sin precio: la Central te lo dice primero'
                : (esPuntoAPunto
                    ? 'Servicio sin cobro'
                    : 'Con precio: sale de una vez a los Móviles'),
          ),
          content: SizedBox(
            width: kAnchoMaxSE,
            child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!esPuntoAPunto) const BannerAltaDemanda(),
                if (_esCot)
                  const AvisoCotizacionSE()
                else
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: esPuntoAPunto ? const Color(0xFFF3E5F5) : kCampoSE,
                      borderRadius: BorderRadius.circular(kRadioCampoSE),
                    ),
                    child: Text(
                      esPuntoAPunto
                          ? '🏁 Llega a: ${widget.usuario['nombre']}'
                          : '📍 Sale de: ${widget.usuario['nombre']}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: esPuntoAPunto ? const Color(0xFF7B1FA2) : Colors.black87,
                      ),
                    ),
                  ),

                // Banner de móvil preseleccionado (viene de "Nuevo servicio con Móvil X")
                if (movilPreselId != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1565C0),
                      borderRadius: BorderRadius.circular(kRadioCampoSE),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.alt_route, color: Colors.white, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '🎯 DIRECTO A ${movilPreselLabel?.toUpperCase() ?? movilPreselId}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),

                // 1. TICKET (no aplica al PAP: es un servicio directo)
                if (!esPuntoAPunto) ...[
                  paso('Cliente'),
                  TextField(
                    controller: ticketController,
                    keyboardType: TextInputType.text,
                    decoration: const InputDecoration(
                      labelText: 'Ticket / Factura # (Opcional)',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.receipt_long),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // 2. WHATSAPP (MINI-CRM CLIENTES)
                if (!esPuntoAPunto) ...[
                  TextField(
                    controller: telefonoController,
                    keyboardType: TextInputType.text,
                    autocorrect: false,
                    enableSuggestions: false,
                    inputFormatters: formatoWhatsApp,
                    decoration: InputDecoration(
                      labelText: 'WhatsApp del cliente (*)',
                      helperText: 'Número o @usuario de WhatsApp',
                      border: const OutlineInputBorder(),
                      prefixIcon: buscandoCliente
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : const Icon(Icons.phone_android),
                    ),
                    onChanged: (val) async {
                      if (whatsAppListoParaBuscar(val)) {
                        setDialogState(() => buscandoCliente = true);
                        final resultado = await _buscarDireccionesPorTelefono(
                          normalizarWhatsApp(val),
                        );
                        setDialogState(() {
                          direccionesHistoricasCliente = resultado;
                          buscandoCliente = false;
                        });
                      } else {
                        setDialogState(() => direccionesHistoricasCliente = []);
                      }
                    },
                  ),

                  // PÍLDORAS DEL HISTORIAL DE DIRECCIONES
                  if (direccionesHistoricasCliente.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: direccionesHistoricasCliente.map((dir) {
                          String numStr = (dir['tarifa'] as num)
                              .toInt()
                              .toString();
                          String result = '';
                          int count = 0;
                          for (int i = numStr.length - 1; i >= 0; i--) {
                            result = numStr[i] + result;
                            count++;
                            if (count == 3 && i > 0) {
                              result = '.$result';
                              count = 0;
                            }
                          }
                          String tarifaStr = '\$$result';

                          return InkWell(
                            onTap: () {
                              destinoController.text = dir['destino'];
                              tarifaController.text = tarifaStr;
                              setDialogState(
                                () => direccionesHistoricasCliente = [],
                              );
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.blue[50],
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.blue[300]!),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.history,
                                    color: Colors.blue,
                                    size: 14,
                                  ),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      '${dir['destino']} ($tarifaStr)',
                                      style: TextStyle(
                                        color: Colors.blue[900],
                                        fontWeight: FontWeight.bold,
                                        fontSize: 11,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  const SizedBox(height: 12),
                ],

                // 3. DESTINO
                paso(esPuntoAPunto ? '¿Dónde recogen?' : '¿A dónde va?'),
                TextField(
                  controller: destinoController,
                  decoration: InputDecoration(
                    labelText: esPuntoAPunto
                        ? '¿Dónde compran / recogen?'
                        : 'Dirección de Entrega',
                    border: const OutlineInputBorder(),
                    prefixIcon: Icon(
                      esPuntoAPunto ? Icons.storefront : Icons.flag,
                    ),
                    // ---> LIBERADO: Muestra el botón de agenda en Cotizar <---
                    suffixIcon: (!esPuntoAPunto && listaPrecios.isNotEmpty)
                        ? IconButton(
                            icon: const Icon(
                              Icons.list_alt,
                              color: Colors.blue,
                            ),
                            tooltip: 'Ver precios de ServiExpress',
                            onPressed: () {
                              showDialog(
                                context: context,
                                builder: (ctxLista) => AlertDialog(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  title: const Text(
                                    '📖 PRECIOS DE SERVIEXPRESS',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
                                  ),
                                  content: SizedBox(
                                    width: double.maxFinite,
                                    height: 350,
                                    child: ListView.builder(
                                      shrinkWrap: true,
                                      itemCount: listaPrecios.length,
                                      itemBuilder: (ctx, i) {
                                        final item = listaPrecios[i];
                                        final precio = item['precio'] as int?;
                                        String tarifaStr = '';
                                        if (precio != null) {
                                          String numStr = precio.toString();
                                          String result = '';
                                          int count = 0;
                                          for (int j = numStr.length - 1; j >= 0; j--) {
                                            result = numStr[j] + result;
                                            count++;
                                            if (count == 3 && j > 0) { result = '.$result'; count = 0; }
                                          }
                                          tarifaStr = '\$$result';
                                        }
                                        return Card(
                                          elevation: 0.5,
                                          margin: const EdgeInsets.only(
                                            bottom: 6,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          child: ListTile(
                                            dense: true,
                                            tileColor: Colors.blue[50],
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            title: Text(
                                              (item['nombre'] ?? '').toString().toUpperCase(),
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13,
                                              ),
                                            ),
                                            subtitle: Text(
                                              item['municipio']?.toString() ?? '',
                                              style: const TextStyle(fontSize: 11),
                                            ),
                                            trailing: Text(
                                              tarifaStr,
                                              style: TextStyle(
                                                color: Colors.blue[900],
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14,
                                              ),
                                            ),
                                            onTap: () {
                                              final lbl = (item['nombre'] ?? '').toString().toUpperCase();
                                              destinoController.text = '$lbl - ';
                                              if (tarifaStr.isNotEmpty)
                                                tarifaController.text = tarifaStr;

                                              setDialogState(
                                                () => sugerenciasListaPrecios =
                                                    [],
                                              );
                                              Navigator.pop(ctxLista);
                                            },
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctxLista),
                                      child: const Text(
                                        'CERRAR',
                                        style: TextStyle(
                                          color: Colors.black,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          )
                        : null,
                  ),
                  onChanged: (texto) {
                    if (esPuntoAPunto) return;
                    buscarSugerenciaRuta(texto); // precio de servicios ya hechos

                    // ── Preservar precio si el usuario solo añade detalles ──
                    if (destinoBase != null &&
                        texto.toUpperCase().startsWith(destinoBase!)) {
                      setDialogState(() { sugerenciasListaPrecios = []; });
                      return;
                    }
                    if (sectorBase != null &&
                        texto.toLowerCase().contains(sectorBase!.toLowerCase())) {
                      setDialogState(() { sugerenciasListaPrecios = []; });
                      return;
                    }
                    // Cambio real → resetear base
                    destinoBase = null;
                    sectorBase  = null;

                    String textoLimpio = texto.toLowerCase();
                    if (textoLimpio.length < 2) {
                      setDialogState(() { sugerenciasListaPrecios = []; });
                      return;
                    }

                    List<String> palabrasDigitadas = textoLimpio
                        .split(RegExp(r'\s+'))
                        .where((w) => w.length > 2)
                        .toList();

                    // --- Sugerencias de Red SE (red_dir_catalogo + se_precios_dir, en verde) ---
                    List<Map<String, dynamic>> encontradas = [];
                    for (var d in listaPrecios) {
                      final nombre = (d['nombre'] ?? '').toString();
                      final nomLower = nombre.toLowerCase();
                      final mun = (d['municipio'] ?? '').toString();
                      final sec = (d['sectores'] as Map?)?.cast<String, dynamic>();
                      bool hay = nomLower.contains(textoLimpio) ||
                          textoLimpio.contains(nomLower) ||
                          palabrasDigitadas.any((w) => nomLower.contains(w));
                      if (!hay) continue;
                      final precio = d['precio'] as int?;
                      String tarifaStr = '';
                      if (precio != null) {
                        String numStr = precio.toString();
                        String result = '';
                        int count = 0;
                        for (int i = numStr.length - 1; i >= 0; i--) {
                          result = numStr[i] + result;
                          count++;
                          if (count == 3 && i > 0) { result = '.$result'; count = 0; }
                        }
                        tarifaStr = '\$$result';
                      }
                      encontradas.add({
                        'palabra': nombre.toUpperCase(),
                        'tarifaStr': tarifaStr,
                        'precio': precio,
                        'municipio': mun,
                        'sectorName': (sec?['nombre'] ?? '').toString().toLowerCase(),
                      });
                    }

                    setDialogState(() {
                      sugerenciasListaPrecios = encontradas.take(5).toList();
                    });
                  },
                ),

                if (sugerenciasListaPrecios.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // --- SUGERENCIAS PROPIAS (con precio, verde) ---
                        if (sugerenciasListaPrecios.isNotEmpty) ...[
                          const Text(
                            '💡 Precio de ServiExpress:',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: sugerenciasListaPrecios.map((sug) =>
                              InkWell(
                                onTap: () {
                                  final palabra = sug['palabra'].toString();
                                  tarifaController.text = sug['tarifaStr'];
                                  if (destinoController.text.length <= palabra.length)
                                    destinoController.text = '$palabra - ';
                                  destinoBase = null;
                                  sectorBase  = sug['sectorName']?.toString();
                                  setDialogState(() {
                                    sugerenciasListaPrecios = [];
                                  });
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: Colors.green[50],
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: Colors.green[400]!),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.add_location_alt, color: Colors.green, size: 14),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${sug['palabra']} (${sug['tarifaStr']})',
                                        style: TextStyle(color: Colors.green[900], fontWeight: FontWeight.bold, fontSize: 11),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ).toList(),
                          ),
                        ],

                      ],
                    ),
                  ),
                // --- Precio automático (ruta confiable + automático activo) ---
                if (!esPuntoAPunto && sugRuta != null)
                  Builder(builder: (_) {
                    final s = sugRuta!;
                    final precio = (s['precio'] as num).toInt();
                    final yaPuesto = tarifaController.text.replaceAll(RegExp(r'[^0-9]'), '') ==
                        precio.toString();
                    return Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
                      decoration: BoxDecoration(
                        color: Colors.green[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green[600]!),
                      ),
                      child: Row(children: [
                        const Text('🤖', style: TextStyle(fontSize: 16)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Precio ${pesosLocal(precio)}\nPuedes pedir el móvil directo, sin esperar cotización.',
                            style: TextStyle(color: Colors.green[900], fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ),
                        if (!yaPuesto)
                          TextButton(
                            onPressed: () {
                              tarifaController.text = pesosLocal(precio);
                              setDialogState(() {});
                            },
                            child: const Text('USAR', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                      ]),
                    );
                  }),
                const SizedBox(height: 12),

                // 4. TARIFA Y RELOJ
                if (!esPuntoAPunto) ...[
                  paso('Precio y hora'),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: tarifaController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [CurrencyInputFormatter()],
                          decoration: InputDecoration(
                            labelText: _esCot
                                ? 'Precio (vacío = la Central te lo dice)'
                                : 'Precio (\$)',
                            enabled: true,
                            border: const OutlineInputBorder(),
                            prefixIcon: const Icon(Icons.attach_money),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Text('¿Cuándo lo necesitas?',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: kCampoSE,
                      borderRadius: BorderRadius.circular(kRadioCampoSE),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: tiempoPreparacion,
                        icon: const Icon(Icons.timer, color: Colors.blue),
                        items: [
                          'Inmediato',
                          'En 15 min',
                          'En 30 min',
                          'En 45 min',
                          'A una hora…',
                        ]
                            .map(
                              (String v) => DropdownMenuItem(
                                value: v,
                                child: Text(
                                  v == 'Inmediato'
                                      ? '⚡ Ya, lo antes posible'
                                      : v == 'A una hora…'
                                          ? (horaProgramada != null
                                              ? '📅 A una hora exacta: ${textoProgramado(horaProgramada!)}'
                                              : '📅 A una hora exacta…')
                                          : '⏱ $v',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (val) async {
                          if (val == null) return;
                          if (val == 'A una hora…') {
                            // Hoy / Mañana + hora exacta
                            final h = await elegirHoraProgramada(context,
                                inicial: horaProgramada);
                            if (h == null) return; // canceló: queda como estaba
                            setDialogState(() {
                              horaProgramada = h;
                              tiempoPreparacion = val;
                            });
                            return;
                          }
                          setDialogState(() => tiempoPreparacion = val);
                        },
                      ),
                    ),
                  ),
                  if (tiempoPreparacion != 'Inmediato')
                    Padding(
                      padding: const EdgeInsets.only(top: 6, left: 2),
                      child: Text(
                        tiempoPreparacion == 'A una hora…' &&
                                horaProgramada != null
                            ? 'Se envía al radar ${textoProgramado(horaProgramada!)}.'
                            : _esCot
                                ? 'Se envía al radar ${tiempoPreparacion.replaceFirst('En ', '')} después de que apruebes el precio.'
                                : 'Se envía al radar ${tiempoPreparacion.toLowerCase()} '
                                    '(${textoProgramado(DateTime.now().add(Duration(minutes: int.tryParse(tiempoPreparacion.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)))}).',
                        style: const TextStyle(
                            fontSize: 13, color: Colors.black54),
                      ),
                    ),
                  const SizedBox(height: 10),
                  // Chips de servicio: Mototaxi y Lluvia en la misma fila
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      FilterChip(
                        label: const Text('🏍 Mototaxi'),
                        selected: _esMototaxi,
                        selectedColor: Colors.orange[100],
                        checkmarkColor: Colors.orange[800],
                        labelStyle: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: _esMototaxi ? Colors.orange[800] : Colors.black54,
                        ),
                        onSelected: (v) => _setDS?.call(() => _esMototaxi = v),
                      ),
                    ],
                  ),
                  // Recargos activos: los activa SOLO la central (lluvia a mano
                  // o por clima; nocturno por horario o a mano). Se suman
                  // solos al pedir; el local solo ve el aviso.
                  if (recargoActivo != null) ...[
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.indigo[50],
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.indigo[200]!),
                      ),
                      child: Text(
                        '${recargoActivo['lluvia_activa'] == true ? '🌧 ' : ''}'
                        '${recargoActivo['nocturno_activo'] == true ? '🌙 ' : ''}'
                        'Recargo activo +\$${recargoActivo['recargo_total']} '
                        '(${recargoActivo['desglose'] ?? ''}). Se suma solo al pedir.',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.indigo[800]),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                ],

                // 5. NOTAS
                paso('Detalles'),
                TextField(
                  controller: notasController,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: esPuntoAPunto
                        ? '¿Qué van a traer? (Detalles)'
                        : 'Notas para el Móvil (opcional)',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.notes),
                  ),
                ),
              ],
            ),
          ),
          ),
          actions: [
            TextButton(
              onPressed: procesando ? null : () => Navigator.pop(context),
              child: const Text(
                'Cancelar',
                style: TextStyle(color: Color(0xFFC62828)),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: colorForm,
                foregroundColor: sobreColorSE(colorForm),
                minimumSize: const Size(160, 54),
                padding: const EdgeInsets.symmetric(horizontal: 22),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: procesando
                  ? null
                  : () async {
                      if (destinoController.text.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(esPuntoAPunto
                                ? 'Escribe dónde compran o recogen.'
                                : 'Escribe la dirección de entrega.'),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }

                      // (Sin bloqueo por lista de precios: el local puede poner
                      // el precio que acordó con el cliente, ej. por WhatsApp.)

                      // ---> REGLA DE DISCIPLINA: FILTRO ANTICIEGOS (NOMENCLATURA) <---
                      String destinoFinal = destinoController.text
                          .trim()
                          .toUpperCase();
                      bool esSoloElBarrio = listaPrecios.any((item) {
                        final s = (item['sectores'] as Map?)?.cast<String, dynamic>();
                        if (s == null) return false;
                        return '${s['nombre']} (${s['municipio']})'.toUpperCase() == destinoFinal;
                      });

                      if (!esPuntoAPunto &&
                          !_esCot &&
                          (esSoloElBarrio || destinoFinal.length <= 8)) {
                        showDialog(
                          context: context,
                          builder: (ctxAlert) => AlertDialog(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: const BorderSide(
                                color: Colors.orange,
                                width: 2,
                              ),
                            ),
                            title: const Row(
                              children: [
                                Icon(
                                  Icons.warning_amber_rounded,
                                  color: Colors.orange,
                                  size: 28,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'DIRECCIÓN CORTA',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.orange,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                            content: const Text(
                              'Parece que solo escribiste el nombre del barrio.\n\nPor favor, agrega la Calle, Avenida, o número de casa/apartamento para que el móvil llegue exacto.',
                              style: TextStyle(fontSize: 14),
                            ),
                            actions: [
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.black,
                                ),
                                onPressed: () => Navigator.pop(
                                  ctxAlert,
                                ),
                                child: Text(
                                  'ACEPTAR Y CORREGIR',
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

                      if (!esPuntoAPunto &&
                          telefonoController.text.trim().isEmpty &&
                          !_esCot) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Falta WhatsApp.'),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }
                      if (!esPuntoAPunto && !_esCot) {
                        final errWa = validarWhatsApp(telefonoController.text);
                        if (errWa != null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(errWa), backgroundColor: Colors.red),
                          );
                          return;
                        }
                      }

                      setDialogState(() => procesando = true);
                      _sonidos.reproducirSuave(
                        Sonidos.localAccion,
                      );
                      final coords = await _obtenerOSellarGPSLocal();
                      if (coords == null) {
                        setDialogState(() => procesando = false);
                        return;
                      }

                      try {
                        String notaManual = notasController.text.trim();
                        String ticketNum = ticketController.text.trim();

                        int retardoProgramado = 0;
                        if (tiempoPreparacion == 'En 15 min')
                          retardoProgramado = 15;
                        else if (tiempoPreparacion == 'En 30 min')
                          retardoProgramado = 30;
                        else if (tiempoPreparacion == 'En 45 min')
                          retardoProgramado = 45;

                        String liberacionCalculada = DateTime.now()
                            .toUtc()
                            .add(Duration(minutes: retardoProgramado))
                            .toIso8601String();

                        // "A una hora…": sale a los móviles a la hora EXACTA
                        // elegida. Si ya pasó al enviar, sale de inmediato.
                        if (tiempoPreparacion == 'A una hora…' &&
                            horaProgramada != null &&
                            horaProgramada!.isAfter(DateTime.now())) {
                          retardoProgramado = 1; // > 0 → 'programado'
                          liberacionCalculada =
                              horaProgramada!.toUtc().toIso8601String();
                        }
                        String estadoFinal = _esCot
                            ? 'cotizacion'
                            : (retardoProgramado > 0
                                  ? 'programado'
                                  : 'pendiente');

                        String tipoDefecto =
                            perfilEnVivo['tipo_servicio_defecto'] ?? 'COMIDA';
                        String instruccionesFijas =
                            perfilEnVivo['instrucciones_recogida'] ?? '';
                        final tipoUp = tipoDefecto.toUpperCase();
                        String tagServicio = '[ $tipoUp ]';

                        String bloqueTicket = ticketNum.isNotEmpty
                            ? '[ TICKET: #$ticketNum ] '
                            : '';

                        // PAP: sin etiqueta — el móvil no debe saberlo antes de aceptar
                        if (!esPuntoAPunto && tiempoPreparacion != 'Inmediato') {
                          final etiquetaProg = tiempoPreparacion == 'A una hora…' &&
                                  horaProgramada != null
                              ? textoProgramado(horaProgramada!)
                              : tiempoPreparacion;
                          notaManual =
                              '[⏰ PROGRAMADO: $etiquetaProg] $notaManual';
                        }

                        String bloqueInstrucciones =
                            instruccionesFijas.isNotEmpty
                            ? '\n• Recogida: $instruccionesFijas'
                            : '';
                        String observacionFinal =
                            '$tagServicio $bloqueTicket$notaManual$bloqueInstrucciones';

                        String tarifaLimpia = tarifaController.text
                            .replaceAll('\$', '')
                            .replaceAll('.', '')
                            .replaceAll(',', '')
                            .trim();
                        double tarifaNueva = (esPuntoAPunto || _esCot)
                            ? 0.0
                            : (double.tryParse(tarifaLimpia) ?? 0.0);
                        // Precio base (sin recargos): sirve para comparar con
                        // el precio calculado y para que las rutas aprendan
                        // el valor real, no el inflado por lluvia/noche.
                        final double tarifaBaseSinRecargo = tarifaNueva;
                        // Lluvia y nocturno los suma _confirmarRecargoObligatorio
                        // (los activa la central); el local ya no los agrega a mano.
                        final destinoNuevo = destinoController.text.trim();

                        // --- INTERCEPTOR DE RECARGO OBLIGATORIO ---
                        if (tarifaNueva > 0) {
                          final double? tarifaConfirmada =
                              await _confirmarRecargoObligatorio(tarifaNueva);
                          if (tarifaConfirmada == null) {
                            setDialogState(() => procesando = false);
                            return;
                          }
                          tarifaNueva = tarifaConfirmada;
                        }

                        // --- ENRUTAR (antes "Doble Enganche") ---
                        String? rutaGrupoIdParaNuevo;
                        if (!esPuntoAPunto &&
                            !_esCot &&
                            retardoProgramado == 0) {
                          final pendientes = await Supabase.instance.client
                              .from('servicios')
                              // Solo lo que se usa (antes: todas las columnas)
                              .select('id, ruta_grupo_id, destino')
                              .eq('local_id', widget.usuario['id'])
                              .eq('estado', 'pendiente')
                              .eq('es_punto_a_punto', false)
                              .order('id', ascending: true)
                              .limit(1);
                          if (pendientes.isNotEmpty) {
                            final pedidoBase = pendientes.first;
                            bool enrutar = false;
                            bool decisionTomada = false;
                            await showDialog(
                              context: context,
                              barrierDismissible: false,
                              builder: (ctxConfirm) => AlertDialog(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                title: const Row(
                                  children: [
                                    Icon(Icons.link, color: Colors.blue),
                                    SizedBox(width: 8),
                                    Text(
                                      'ENRUTAR',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.blue,
                                      ),
                                    ),
                                  ],
                                ),
                                content: Text(
                                  'Tienes la Orden #${pedidoBase['id']} pendiente de asignar móvil.\n\n¿Quieres ENRUTAR este nuevo pedido para que el mismo moto se lleve los dos? Cada uno mantiene su propio destino y tarifa — solo viajan juntos.',
                                  style: const TextStyle(fontSize: 14),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () {
                                      decisionTomada = true;
                                      enrutar = false;
                                      Navigator.pop(ctxConfirm);
                                    },
                                    child: const Text(
                                      'SEPARADOS',
                                      style: TextStyle(
                                        color: Colors.grey,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.blue,
                                    ),
                                    onPressed: () {
                                      decisionTomada = true;
                                      enrutar = true;
                                      Navigator.pop(ctxConfirm);
                                    },
                                    child: Text(
                                      'ENRUTAR (1 Moto)',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );

                            if (decisionTomada && enrutar) {
                              final grupoId = pedidoBase['id'].toString();
                              rutaGrupoIdParaNuevo = grupoId;
                              if (pedidoBase['ruta_grupo_id'] == null) {
                                await Supabase.instance.client
                                    .from('servicios')
                                    .update({'ruta_grupo_id': pedidoBase['id']})
                                    .eq('id', pedidoBase['id']);
                              }
                            }
                          }
                        }

                        String? exclusivoIdCampo;
                        List<String> pilotosSeleccionadosIds = [];

                        // --- PRESEL DIRECTO: saltar ENRUTAR automático y paradero ---
                        if (movilPreselId != null && !_esCot) {
                          exclusivoIdCampo = movilPreselId;
                          pilotosSeleccionadosIds = [movilPreselId];
                        }
                        // --- ENRUTAR CON MÓVIL ACTIVO (solo si NO hay presel) ---
                        else if (!_esCot &&
                            !esPuntoAPunto &&
                            retardoProgramado == 0 &&
                            rutaGrupoIdParaNuevo == null) {
                          final svcActivos = await Supabase.instance.client
                              .from('servicios')
                              .select('id, movil_id')
                              .eq('local_id', widget.usuario['id'])
                              .inFilter('estado', ['en_ruta_origen', 'en_origen', 'en_ruta_destino'])
                              .not('movil_id', 'is', null)
                              .limit(5);

                          if (svcActivos.isNotEmpty) {
                            final Set<String> activoIds = svcActivos
                                .map((s) => s['movil_id'].toString())
                                .toSet();
                            final perfilesActivos = await Supabase.instance.client
                                .from('usuarios')
                                .select('id, usuario, nombre')
                                .inFilter('id', activoIds.toList());

                            if (perfilesActivos.isNotEmpty && context.mounted) {
                              Map<String, dynamic>? motoElegido;
                              bool decidioEnrutar = false;
                              await showDialog(
                                context: context,
                                barrierDismissible: false,
                                builder: (ctxE) => AlertDialog(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                                  title: const Row(
                                    children: [
                                      Icon(Icons.alt_route, color: Colors.blue),
                                      SizedBox(width: 8),
                                      Text('ENRUTAR',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.blue)),
                                    ],
                                  ),
                                  content: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Tienes móvil(es) en camino. ¿Enrutar este nuevo pedido?',
                                        style: TextStyle(fontSize: 13),
                                      ),
                                      const SizedBox(height: 10),
                                      ...perfilesActivos.map((m) => Padding(
                                        padding: const EdgeInsets.only(bottom: 6),
                                        child: SizedBox(
                                          width: double.infinity,
                                          child: ElevatedButton.icon(
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.blue[700],
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 12, vertical: 8)),
                                            onPressed: () {
                                              motoElegido = m;
                                              decidioEnrutar = true;
                                              Navigator.pop(ctxE);
                                            },
                                            icon: Icon(Icons.motorcycle,
                                              size: 16, color: Colors.white),
                                            label: Text(
                                              'ENRUTAR a ${(m['usuario'] ?? m['nombre'] ?? '').toString().toUpperCase()}',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold)),
                                          ),
                                        ),
                                      )),
                                    ],
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctxE),
                                      child: const Text('NO, AL RADAR',
                                        style: TextStyle(color: Colors.grey)),
                                    ),
                                  ],
                                ),
                              );

                              if (decidioEnrutar && motoElegido != null) {
                                final svcDelMoto = svcActivos.firstWhere(
                                  (s) => s['movil_id'].toString() == motoElegido!['id'].toString(),
                                  orElse: () => svcActivos.first,
                                );
                                rutaGrupoIdParaNuevo = svcDelMoto['id'].toString();
                                exclusivoIdCampo = motoElegido!['id'].toString();
                                pilotosSeleccionadosIds = [motoElegido!['id'].toString()];
                              }
                            }
                          }
                        }

                        // --- F2 SE: la resuelve el SERVIDOR (se_f2_huecos) ---
                        // A T+30s ofrece al #1 de este paradero o, si está vacío,
                        // al móvil más cercano (con todos los filtros) y solo si el
                        // servicio sigue pendiente. Aquí solo se indica el paradero
                        // objetivo del local. Programados: los libera el servidor.
                        String? paraderoObjetivoF2;
                        if (!_esCot && !esPuntoAPunto && exclusivoIdCampo == null) {
                          paraderoObjetivoF2 = await _paraderoObjetivoDeLocal(
                            widget.usuario,
                            (coords['lat'] as num?)?.toDouble(),
                            (coords['lng'] as num?)?.toDouble(),
                          );
                        }

                        // REGISTRO EN BD
                        final respuestaServicio = await Supabase.instance.client
                            .from('servicios')
                            .insert({
                              'origen': esPuntoAPunto
                                  ? (widget.usuario['paradero_exclusivo'] ??
                                        'LOCAL')
                                  : widget.usuario['nombre'],
                              'origen_lat': esPuntoAPunto
                                  ? null
                                  : coords['lat'],
                              'origen_lng': esPuntoAPunto
                                  ? null
                                  : coords['lng'],
                              'destino': esPuntoAPunto
                                  ? widget.usuario['nombre']
                                  : destinoNuevo,
                              'destino_lat': esPuntoAPunto
                                  ? coords['lat']
                                  : null,
                              'destino_lng': esPuntoAPunto
                                  ? coords['lng']
                                  : null,
                              'telefono_receptor': esPuntoAPunto
                                  ? null
                                  : normalizarWhatsApp(telefonoController.text),
                              'tarifa': tarifaNueva,
                              'recargo_total': (tarifaNueva - tarifaBaseSinRecargo).round(),
                              'tarifa_detalle': {
                                'total': tarifaNueva,
                                'base': tarifaBaseSinRecargo,
                                'recargo': tarifaNueva - tarifaBaseSinRecargo,
                                'fuente': 'local',
                              },
                              'observacion': observacionFinal,
                              'estado': estadoFinal,
                              'creador': widget.usuario['nombre'],
                              'tipo_servicio': _esMototaxi ? 'mototaxi' : _tipoDefecto,
                              if (rutaGrupoIdParaNuevo != null)
                                'ruta_grupo_id': int.tryParse(
                                  rutaGrupoIdParaNuevo,
                                ),
                              'local_id': widget.usuario['id'],
                              'es_punto_a_punto': esPuntoAPunto,
                              'es_vip': false,
                              'exclusivo_id': exclusivoIdCampo,
                              if (paraderoObjetivoF2 != null)
                                'paradero_origen': paraderoObjetivoF2,
                              'ticket_factura': ticketNum.isEmpty
                                  ? null
                                  : ticketNum,
                              'liberacion_at': liberacionCalculada,
                              // Cotización "En X min": los minutos cuentan desde
                              // que el local aprueba el precio (lo hace el servidor).
                              if (_esCot &&
                                  tiempoPreparacion != 'A una hora…' &&
                                  retardoProgramado > 0)
                                'programado_min': retardoProgramado,
                            })
                            .select()
                            .single();

                        final int nuevoServicioId =
                            respuestaServicio['id'] as int;

                        // P.A.P: el límite de 1 por día, el paradero (o EXPUENTE)
                        // y la cascada SE (F1→F4) los aplica el SERVIDOR
                        // (trigger trg_pap_preparar) al crear el servicio.

                        // Sonido de confirmación según tipo de servicio
                        if (_esCot) {
                          _sonidos.reproducirSuave(Sonidos.localCotizacion);
                        } else {
                          _sonidos.reproducirSuave(Sonidos.localAccion);
                        }

                        // DISPAROS ONESIGNAL
                        if (_esCot) {
                          await MotorNotificaciones.dispararACentral(
                            titulo: '❓ NUEVA COTIZACIÓN',
                            mensaje: 'Un local solicita cotización de tarifa',
                            urgente: true,
                          );
                        } else if (movilPreselId != null) {
                          // Directo: un solo misil al móvil preseleccionado
                          // (el service ya tiene exclusivo_id — no se dispara cascada)
                          await _dispararMisilInmediato(
                            externalIds: [movilPreselId],
                            titulo: TextosPush.asignadoTitulo,
                            mensaje: TextosPush.asignadoMensaje(
                              widget.usuario['nombre']?.toString() ?? 'El local',
                              TextosPush.ruta(
                                  widget.usuario['nombre']?.toString(), destinoNuevo),
                            ),
                          );
                        } else if (esPuntoAPunto) {
                          // P.A.P: cascada SE completa desde el SERVIDOR
                          // (F1 Masters → F2 #1 del paradero del local con
                          // sanción → F3 → F4). Sin push "Punto a Punto":
                          // el móvil lo sabe solo al aceptarlo.
                        } else {
                          final String rutaPush = TextosPush.ruta(
                              widget.usuario['nombre']?.toString(), destinoNuevo);
                          final mastersData = await Supabase.instance.client
                              .from('usuarios')
                              .select('id')
                              .eq('rango_movil', 'MASTER')
                              .eq('tiene_se', true)
                              .eq('en_linea', true)
                              .neq('suspendido', true)
                              .or('wallet_bloqueado.is.null,wallet_bloqueado.eq.false');
                          List<String> masterIds = mastersData
                              .map((u) => u['id'].toString())
                              .toList();

                          // Programado: todavía no está en el radar. El servidor
                          // (se_liberar_programados) lo libera a su hora y en ese
                          // momento envía F1 y arranca F2/F3/F4.
                          if (retardoProgramado == 0) {
                            // F1 (T=0): Masters → lo manda el SERVIDOR
                            // (se_f1_motivo en el update de más abajo). La lista
                            // de Masters solo se usa para no avisar doble.

                            // Enrutado a un móvil que ya viene en camino (exclusivo):
                            // aviso solo a ese móvil.
                            final List<String> targetPilotos = pilotosSeleccionadosIds
                                .where((id) => !masterIds.contains(id))
                                .toList();
                            if (targetPilotos.isNotEmpty) {
                              await _dispararMisilInmediato(
                                externalIds: targetPilotos,
                                titulo: TextosPush.asignadoTitulo,
                                mensaje: TextosPush.asignadoMensaje(
                                  widget.usuario['nombre']?.toString() ?? 'El local',
                                  rutaPush,
                                ),
                              );
                            }

                            // F2 la hace el servidor (se_f2_huecos).
                            // F3/F4 — pg_cron consulta en_linea en tiempo real
                            await Supabase.instance.client
                                .from('servicios')
                                .update({
                                  if (!esPuntoAPunto)
                                    'se_cascade_t0': DateTime.now().toUtc().toIso8601String(),
                                  if (!esPuntoAPunto) 'se_f3_enviado': false,
                                  if (!esPuntoAPunto) 'se_f4_enviado': false,
                                  'se_f1_motivo': 'nuevo',
                                })
                                .eq('id', nuevoServicioId);
                          }
                        }

                        // Cierra el formulario (los locales no manejan lista de precios)
                        if (context.mounted) {
                          Navigator.pop(context);
                        }
                      } catch (e) {
                        setDialogState(() => procesando = false);
                        if (context.mounted)
                          ScaffoldMessenger.of(
                            context,
                          ).showSnackBar(SnackBar(content: Text('Error: $e')));
                      }
                    },
              child: procesando
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: sobreColorSE(colorForm),
                        strokeWidth: 2,
                      ),
                    )
                  : Text(
                      _esCot
                          ? 'Pedir precio'
                          : (esPuntoAPunto ? 'Enviar Punto a Punto' : 'Pedir Móvil'),
                      style: TextStyle(
                        color: sobreColorSE(colorForm),
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
            ),
          ],
        ));
      },
      ),
    );
  }
}
