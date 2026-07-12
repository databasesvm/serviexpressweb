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
  Future<void> _verificarFallbackVip({
    required int servicioId,
    required String destino,
    required List<String> pilotosParadero,
    required bool esPuntoAPunto,
    required Map<String, dynamic>? coords,
    required double tarifaConVip,
  });
  Future<void> _mostrarDialogoFallbackVip({
    required int servicioId,
    required String destino,
    required List<String> pilotosParadero,
    required bool esPuntoAPunto,
    required Map<String, dynamic>? coords,
    required double tarifaConVip,
  });

  // ── HELPER: busca o crea un sector por nombre+municipio ───────────────────
  Future<int> _buscarOCrearSector(String nombre, String municipio) async {
    final res = await Supabase.instance.client
        .from('sectores')
        .select('id')
        .eq('nombre', nombre)
        .eq('municipio', municipio)
        .maybeSingle();
    if (res != null) return res['id'] as int;
    final nuevo = await Supabase.instance.client
        .from('sectores')
        .insert({'nombre': nombre, 'municipio': municipio})
        .select('id')
        .single();
    return nuevo['id'] as int;
  }

  // ── MÓDULO TÁCTICO: GESTOR DE TARIFAS DEL LOCAL ────────────────────────────
  void _abrirPanelTarifario(BuildContext contextoPrincipal) {
    String filtroActual = '';

    showModalBottomSheet(
      context: contextoPrincipal,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0D0D0D),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => DraggableScrollableSheet(
          initialChildSize: 0.8,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) => Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Container(
                  width: 40,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  '📚 MI LISTA DE PRECIOS',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                ),
                const Text(
                  'El sistema autocompletará la tarifa al detectar el Barrio/Sector/Cond./Conj..',
                  style: TextStyle(fontSize: 12, color: Colors.white54),
                ),
                const SizedBox(height: 16),

                // BARRA DE BÚSQUEDA
                TextField(
                  decoration: const InputDecoration(
                    labelText:
                        'Buscar Barrio / Sector / Cond. / Conj. o Palabra Clave',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.search),
                    isDense: true,
                  ),
                  onChanged: (val) =>
                      setModalState(() => filtroActual = val.toLowerCase()),
                ),
                const SizedBox(height: 12),

                // BOTÓN DE AGREGAR NUEVO
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      foregroundColor: const Color(0xff3AF500),
                    ),
                    icon: const Icon(Icons.add),
                    label: const Text(
                      'NUEVA TARIFA',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    onPressed: () {
                      final palabraCtrl = TextEditingController();
                      final tarifaCtrl = TextEditingController();
                      String zonaSeleccionada =
                          'CÚCUTA'; // <--- INYECCIÓN: ZONA POR DEFECTO

                      showDialog(
                        context: context,
                        builder: (ctxAdd) => StatefulBuilder(
                          builder: (ctxAdd, setAddState) => AlertDialog(
                            title: const Text(
                              'AGREGAR AL TARIFARIO',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            content: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                TextField(
                                  controller: palabraCtrl,
                                  textCapitalization:
                                      TextCapitalization.characters,
                                  decoration: const InputDecoration(
                                    labelText: 'Barrio / Sector / Cond.',
                                    isDense: true,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                // ---> SELECTOR TÁCTICO DE ZONA <---
                                const Text(
                                  'Municipio / Zona:',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black54,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 0,
                                  children:
                                      [
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
                                            if (selected)
                                              setAddState(
                                                () => zonaSeleccionada = z,
                                              );
                                          },
                                        );
                                      }).toList(),
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: tarifaCtrl,
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [CurrencyInputFormatter()],
                                  decoration: InputDecoration(
                                    labelText: 'Tarifa \$',
                                    isDense: true,
                                    suffixIcon: IconButton(
                                      icon: const Icon(Icons.clear, size: 18),
                                      tooltip: 'Borrar',
                                      onPressed: () => tarifaCtrl.clear(),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctxAdd),
                                child: const Text(
                                  'CANCELAR',
                                  style: TextStyle(color: Colors.red),
                                ),
                              ),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.black,
                                ),
                                onPressed: () async {
                                  if (palabraCtrl.text.isEmpty ||
                                      tarifaCtrl.text.isEmpty)
                                    return;
                                  String tarLimpia = tarifaCtrl.text
                                      .replaceAll('\$', '')
                                      .replaceAll('.', '')
                                      .replaceAll(',', '')
                                      .trim();

                                  final sectorId = await _buscarOCrearSector(
                                    palabraCtrl.text.trim().toUpperCase(),
                                    zonaSeleccionada,
                                  );

                                  await Supabase.instance.client
                                      .from('tarifas_locales')
                                      .upsert(
                                        {
                                          'local_id': widget.usuario['id'],
                                          'local_nombre': widget.usuario['nombre'],
                                          'sector_id': sectorId,
                                          'tarifa':
                                              double.tryParse(tarLimpia) ?? 0.0,
                                        },
                                        onConflict: 'local_id, sector_id',
                                      );

                                  if (ctxAdd.mounted) {
                                    Navigator.pop(ctxAdd);
                                    setModalState(() {});
                                  }
                                },
                                child: const Text(
                                  'GUARDAR',
                                  style: TextStyle(color: Color(0xff3AF500)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const Divider(height: 24),

                // LISTADO DE TARIFAS
                Expanded(
                  child: FutureBuilder<List<Map<String, dynamic>>>(
                    future: Supabase.instance.client
                        .from('tarifas_locales')
                        .select('id, sector_id, sectores(nombre, municipio), tarifa')
                        .eq('local_id', widget.usuario['id'])
                        .order('tarifa', ascending: true),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting)
                        return const Center(
                          child: CircularProgressIndicator(color: Colors.black),
                        );

                      final datos = snapshot.data ?? [];
                      final filtrados = datos.where((d) {
                        final s = d['sectores'] as Map<String, dynamic>?;
                        if (s == null) return false;
                        final label = '${s['nombre']} (${s['municipio']})'.toLowerCase();
                        return label.contains(filtroActual);
                      }).toList();

                      if (filtrados.isEmpty)
                        return const Center(
                          child: Text('No hay tarifas registradas.'),
                        );

                      return ListView.builder(
                        controller: scrollController,
                        itemCount: filtrados.length,
                        itemBuilder: (c, i) {
                          final item = filtrados[i];
                          final s = item['sectores'] as Map<String, dynamic>? ?? {};
                          final label = '${s['nombre'] ?? ''} (${s['municipio'] ?? ''})';
                          return Card(
                            elevation: 1,
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: const Icon(
                                Icons.location_city,
                                color: Colors.blue,
                              ),
                              title: Text(
                                label,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              subtitle: Text('Tarifa: ${fmtPeso(item['tarifa'])}'),
                              trailing: IconButton(
                                icon: const Icon(
                                  Icons.delete,
                                  color: Colors.red,
                                ),
                                onPressed: () async {
                                  await Supabase.instance.client
                                      .from('tarifas_locales')
                                      .delete()
                                      .eq('id', item['id']);
                                  setModalState(() {});
                                },
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
          ),
        ),
      ),
    );
  }

  // ── FORMULARIO DE PEDIDO ────────────────────────────────────────────────────
  void _abrirFormularioPedido(
    BuildContext context, {
    bool esPuntoAPunto = false,
    bool esCotizacion = false,
    bool esVip = false,
    required Map<String, dynamic> perfilEnVivo,
    String? telefonoPrellenado, // Viene del botón "NUEVO PEDIDO" en el CRM
  }) async {
    // --- CONSULTA ESPEJO CON "MI LOCAL" ---
    List<Map<String, dynamic>> listaPrecios = [];
    List<String> redDirecciones = []; // zonas de la red central (sin precio)

    // ---> LIBERADO: Ahora descarga la lista también cuando es Cotización <---
    // Las dos queries corren en PARALELO para reducir la espera a la mitad
    if (!esPuntoAPunto) {
      try {
        final results = await Future.wait([
          Supabase.instance.client
              .from('tarifas_locales')
              .select('sector_id, sectores(nombre, municipio), tarifa')
              .eq('local_id', widget.usuario['id'])
              .order('tarifa', ascending: true),
          Supabase.instance.client
              .from('red_direcciones')
              .select('nombre, municipio')
              .eq('activo', true)
              .order('nombre', ascending: true),
        ]);

        listaPrecios = List<Map<String, dynamic>>.from(results[0]);

        // Excluir las que ya están en la lista propia (no duplicar)
        final propias = listaPrecios.map((e) {
          final s = e['sectores'] as Map<String, dynamic>?;
          if (s == null) return '';
          return '${s['nombre']} (${s['municipio']})'.toUpperCase();
        }).toSet();
        redDirecciones = List<Map<String, dynamic>>.from(results[1])
            .map((e) => '${e['nombre']} (${e['municipio']})')
            .where((nombre) => !propias.contains(nombre.toUpperCase()))
            .toList();
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

    List<Map<String, dynamic>> sugerenciasListaPrecios = [];
    List<String> sugerenciasRed = []; // sugerencias de la red (sin precio)

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 24,
          ),
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
                    '👑 SERVICIO VIP',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 1,
                    ),
                  ),
                )
              : Text(
                  esCotizacion
                      ? 'COTIZAR SERVICIO'
                      : (esPuntoAPunto ? 'PUNTO A PUNTO' : 'SOLICITAR MÓVIL'),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: esCotizacion
                        ? Colors.orange[800]
                        : (esPuntoAPunto ? Colors.purple : Colors.black),
                  ),
                ),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (esVip)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFF3D2B00),
                          Color(0xFF7A5500),
                          Color(0xFF3D2B00),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(6),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFFD700).withValues(alpha: 0.35),
                          blurRadius: 8,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: const Row(
                      children: [
                        Text('👑', style: TextStyle(fontSize: 16)),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Solo llega a Leyendas y Masters · +\$3.000 automático',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFFFD700),
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: esCotizacion
                          ? Colors.orange[50]
                          : (esPuntoAPunto
                                ? Colors.purple[50]
                                : Colors.grey[200]),
                      borderRadius: BorderRadius.circular(6),
                      border: esCotizacion
                          ? Border.all(color: Colors.orange[300]!)
                          : (esPuntoAPunto
                                ? Border.all(color: Colors.purple[200]!)
                                : null),
                    ),
                    child: Text(
                      esCotizacion
                          ? 'Central fijará la tarifa para esta ruta.'
                          : (esPuntoAPunto
                                ? '🏁 Destino final: ${widget.usuario['nombre']}'
                                : '📍 Local: ${widget.usuario['nombre']}'),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: esCotizacion
                            ? Colors.orange[900]
                            : (esPuntoAPunto
                                  ? Colors.purple[800]
                                  : Colors.black54),
                      ),
                    ),
                  ),
                const SizedBox(height: 16),

                // 1. TICKET
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

                // 2. WHATSAPP (MINI-CRM CLIENTES)
                if (!esPuntoAPunto) ...[
                  TextField(
                    controller: telefonoController,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: 'WhatsApp del cliente (*)',
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
                      if (val.length >= 10) {
                        setDialogState(() => buscandoCliente = true);
                        final resultado = await _buscarDireccionesPorTelefono(
                          val,
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
                            tooltip: 'Ver mi lista de precios',
                            onPressed: () {
                              showDialog(
                                context: context,
                                builder: (ctxLista) => AlertDialog(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  title: const Text(
                                    '📖 MI LISTA DE PRECIOS',
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
                                        String numStr = (item['tarifa'] as num)
                                            .toInt()
                                            .toString();
                                        String result = '';
                                        int count = 0;
                                        for (
                                          int j = numStr.length - 1;
                                          j >= 0;
                                          j--
                                        ) {
                                          result = numStr[j] + result;
                                          count++;
                                          if (count == 3 && j > 0) {
                                            result = '.$result';
                                            count = 0;
                                          }
                                        }
                                        String tarifaStr = '\$$result';

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
                                              () {
                                                final s = item['sectores'] as Map<String, dynamic>?;
                                                if (s == null) return '';
                                                return '${s['nombre']} (${s['municipio']})'.toUpperCase();
                                              }(),
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13,
                                              ),
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
                                              final s = item['sectores'] as Map<String, dynamic>?;
                                              final lbl = s != null ? '${s['nombre']} (${s['municipio']})'.toUpperCase() : '';
                                              destinoController.text = '$lbl - ';
                                              // Solo pega el precio si no es cotización
                                              if (!esCotizacion)
                                                tarifaController.text =
                                                    tarifaStr;

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

                    String textoLimpio = texto.toLowerCase();
                    if (textoLimpio.length < 2) {
                      setDialogState(() {
                        sugerenciasListaPrecios = [];
                        sugerenciasRed = [];
                      });
                      return;
                    }

                    List<String> palabrasDigitadas = textoLimpio
                        .split(RegExp(r'\s+'))
                        .where((w) => w.length > 2)
                        .toList();

                    // --- Sugerencias de lista propia (con precio, en verde) ---
                    List<Map<String, dynamic>> encontradas = [];
                    for (var t in listaPrecios) {
                      final sec = t['sectores'] as Map<String, dynamic>?;
                      if (sec == null) continue;
                      String palabraClave = '${sec['nombre']} (${sec['municipio']})'.toLowerCase();
                      bool hay = textoLimpio.contains(palabraClave) ||
                          palabrasDigitadas.any((w) => palabraClave.contains(w));
                      if (hay) {
                        String numStr = (t['tarifa'] as num).toInt().toString();
                        String result = '';
                        int count = 0;
                        for (int i = numStr.length - 1; i >= 0; i--) {
                          result = numStr[i] + result;
                          count++;
                          if (count == 3 && i > 0) { result = '.$result'; count = 0; }
                        }
                        encontradas.add({
                          'palabra': '${sec['nombre']} (${sec['municipio']})'.toUpperCase(),
                          'tarifaStr': '\$$result',
                        });
                      }
                    }

                    // --- Sugerencias de red (sin precio, en gris) ---
                    List<String> redEncontradas = redDirecciones
                        .where((nombre) {
                          String n = nombre.toLowerCase();
                          return n.contains(textoLimpio) ||
                              palabrasDigitadas.any((w) => n.contains(w));
                        })
                        .take(3)
                        .toList();

                    setDialogState(() {
                      sugerenciasListaPrecios = encontradas.take(3).toList();
                      sugerenciasRed = redEncontradas;
                    });
                  },
                ),

                if (sugerenciasListaPrecios.isNotEmpty || sugerenciasRed.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // --- SUGERENCIAS PROPIAS (con precio, verde) ---
                        if (sugerenciasListaPrecios.isNotEmpty) ...[
                          const Text(
                            '💡 Mi lista de precios:',
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
                                  if (!esCotizacion)
                                    tarifaController.text = sug['tarifaStr'];
                                  if (destinoController.text.length <= sug['palabra'].toString().length)
                                    destinoController.text = '${sug['palabra']} - ';
                                  setDialogState(() {
                                    sugerenciasListaPrecios = [];
                                    sugerenciasRed = [];
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

                        // --- SUGERENCIAS DE LA RED (sin precio, gris) ---
                        if (sugerenciasRed.isNotEmpty) ...[
                          if (sugerenciasListaPrecios.isNotEmpty) const SizedBox(height: 8),
                          const Text(
                            '🌐 Zona de la red:',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.black45,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: sugerenciasRed.map((nombre) =>
                              InkWell(
                                onTap: () {
                                  if (destinoController.text.length <= nombre.length)
                                    destinoController.text = '$nombre - ';
                                  setDialogState(() {
                                    sugerenciasListaPrecios = [];
                                    sugerenciasRed = [];
                                  });
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: Colors.grey[100],
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: Colors.grey[400]!),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.location_city, color: Colors.grey[600], size: 14),
                                      const SizedBox(width: 4),
                                      Text(
                                        nombre,
                                        style: TextStyle(color: Colors.grey[700], fontWeight: FontWeight.w600, fontSize: 11),
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
                const SizedBox(height: 12),

                // 4. TARIFA Y RELOJ
                if (!esPuntoAPunto) ...[
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: tarifaController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [CurrencyInputFormatter()],
                          decoration: InputDecoration(
                            labelText: esCotizacion
                                ? 'Tarifa (Se calculará)'
                                : 'Tarifa (\$)',
                            enabled: !esCotizacion,
                            border: const OutlineInputBorder(),
                            prefixIcon: const Icon(Icons.attach_money),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: tiempoPreparacion,
                        icon: const Icon(Icons.timer, color: Colors.blue),
                        items:
                            ['Inmediato', 'En 15 min', 'En 30 min', 'En 45 min']
                                .map(
                                  (String v) => DropdownMenuItem(
                                    value: v,
                                    child: Text(
                                      'Enviar móvil: $v',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                        onChanged: (val) {
                          if (val != null)
                            setDialogState(() => tiempoPreparacion = val);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // 5. NOTAS
                TextField(
                  controller: notasController,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: esPuntoAPunto
                        ? '¿Qué van a traer? (Detalles)'
                        : 'Notas de la orden',
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
                'CANCELAR',
                style: TextStyle(color: Colors.red),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: esCotizacion
                    ? Colors.orange[800]
                    : (esPuntoAPunto ? Colors.purple[800] : Colors.black),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
              ),
              onPressed: procesando
                  ? null
                  : () async {
                      if (destinoController.text.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Falta la dirección.'),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }

                      // ---> REGLA DE DISCIPLINA: FILTRO ANTICIEGOS (NOMENCLATURA) <---
                      String destinoFinal = destinoController.text
                          .trim()
                          .toUpperCase();
                      bool esSoloElBarrio = listaPrecios.any((item) {
                        final s = item['sectores'] as Map<String, dynamic>?;
                        if (s == null) return false;
                        return '${s['nombre']} (${s['municipio']})'.toUpperCase() == destinoFinal;
                      });

                      if (!esPuntoAPunto &&
                          !esCotizacion &&
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
                          !esCotizacion) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Falta WhatsApp.'),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
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
                        String estadoFinal = esCotizacion
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

                        if (esPuntoAPunto) {
                          notaManual = '[PUNTO A PIN] $notaManual';
                        } else if (tiempoPreparacion != 'Inmediato') {
                          notaManual =
                              '[⏰ PROGRAMADO: $tiempoPreparacion] $notaManual';
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
                        double tarifaNueva = (esPuntoAPunto || esCotizacion)
                            ? 0.0
                            : (double.tryParse(tarifaLimpia) ?? 0.0);
                        if (esVip && !esCotizacion && tarifaNueva > 0) {
                          tarifaNueva += 3000;
                        }
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
                            !esCotizacion &&
                            retardoProgramado == 0) {
                          final pendientes = await Supabase.instance.client
                              .from('servicios')
                              .select()
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

                        // --- ENRUTAR CON MÓVIL ACTIVO ---
                        if (!esCotizacion &&
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

                        // --- MOTOR MULTI-PARADERO ---
                        if (!esCotizacion && !esPuntoAPunto && exclusivoIdCampo == null) {
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

                          Map<String, String> numeroUnosPorParadero = {};
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
                              if (!ocupados.contains(candId)) {
                                numeroUnosPorParadero[pName] = candId;
                                break;
                              }
                            }
                          });

                          String paraderosLocalRaw =
                              widget.usuario['paradero_exclusivo']
                                  ?.toString() ??
                              '';
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
                                pilotosSeleccionadosIds.add(
                                  numeroUnosPorParadero[pLocal]!,
                                );
                              }
                            }
                          }

                          if (pilotosSeleccionadosIds.isNotEmpty) {
                            exclusivoIdCampo = pilotosSeleccionadosIds.join(
                              ',',
                            );
                          }
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
                                  : telefonoController.text.trim(),
                              'tarifa': tarifaNueva,
                              'tarifa_detalle': {
                                'total': tarifaNueva,
                                'base': tarifaNueva,
                                'fuente': 'local',
                              },
                              'observacion': observacionFinal,
                              'estado': estadoFinal,
                              'creador': widget.usuario['nombre'],
                              'tipo_servicio': 'PAQUETERÍA',
                              if (rutaGrupoIdParaNuevo != null)
                                'ruta_grupo_id': int.tryParse(
                                  rutaGrupoIdParaNuevo,
                                ),
                              'local_id': widget.usuario['id'],
                              'es_punto_a_punto': esPuntoAPunto,
                              'es_vip': esVip,
                              'exclusivo_id': exclusivoIdCampo,
                              'ticket_factura': ticketNum.isEmpty
                                  ? null
                                  : ticketNum,
                              'liberacion_at': liberacionCalculada,
                            })
                            .select()
                            .single();

                        final int nuevoServicioId =
                            respuestaServicio['id'] as int;

                        // Sonido de confirmación según tipo de servicio
                        if (esCotizacion) {
                          _sonidos.reproducirSuave(Sonidos.localCotizacion);
                        } else {
                          _sonidos.reproducirSuave(Sonidos.localAccion);
                        }

                        // DISPAROS ONESIGNAL
                        if (esCotizacion) {
                          await MotorNotificaciones.dispararACentral(
                            titulo: esVip ? '👑 COTIZACIÓN VIP' : '❓ NUEVA COTIZACIÓN',
                            mensaje: esVip
                                ? 'Cotización VIP pendiente de respuesta'
                                : 'Un local solicita cotización de tarifa',
                            urgente: true,
                          );
                        } else if (esVip) {
                          const String mensajeVip =
                              'Servicio VIP disponible — revisa el radar';

                          final mastersVip = await Supabase.instance.client
                              .from('usuarios')
                              .select('id')
                              .eq('rol', 'movil')
                              .eq('en_linea', true)
                              .inFilter('rango_movil', ['MASTER']);
                          final List<String> masterVipIds = mastersVip
                              .map((u) => u['id'].toString())
                              .toList();

                          final leyendasVip = await Supabase.instance.client
                              .from('usuarios')
                              .select('id, paradero_actual, ingreso_fila')
                              .eq('rol', 'movil')
                              .eq('en_linea', true)
                              .eq('rango_movil', 'LEYENDA')
                              .not('paradero_actual', 'is', null)
                              .order('ingreso_fila', ascending: true);

                          final List<String> leyendaVipIds =
                              leyendasVip.isNotEmpty
                              ? [leyendasVip.first['id'].toString()]
                              : [];

                          if (masterVipIds.isEmpty && leyendaVipIds.isEmpty) {
                            _mostrarDialogoFallbackVip(
                              servicioId: nuevoServicioId,
                              destino: destinoNuevo,
                              pilotosParadero: pilotosSeleccionadosIds,
                              esPuntoAPunto: esPuntoAPunto,
                              coords: coords,
                              tarifaConVip: (respuestaServicio['tarifa'] as num?)?.toDouble() ?? 0.0,
                            );
                          } else {
                            if (masterVipIds.isNotEmpty) {
                              await _dispararMisilInmediato(
                                externalIds: masterVipIds,
                                titulo: '👑 SERVICIO VIP',
                                mensaje: mensajeVip,
                              );
                            }
                            if (leyendaVipIds.isNotEmpty) {
                              final id30sVip = await _programarMisilRetardado(
                                externalIds: leyendaVipIds,
                                titulo: '👑 SERVICIO VIP',
                                mensaje: mensajeVip,
                                segundosRetardo: 30,
                              );
                              if (id30sVip != null) {
                                await Supabase.instance.client
                                    .from('servicios')
                                    .update({'onesignal_30s': id30sVip})
                                    .eq('id', nuevoServicioId);
                              }
                            }
                            Future.delayed(const Duration(minutes: 3), () {
                              _verificarFallbackVip(
                                servicioId: nuevoServicioId,
                                destino: destinoNuevo,
                                pilotosParadero: pilotosSeleccionadosIds,
                                esPuntoAPunto: esPuntoAPunto,
                                coords: coords,
                                tarifaConVip: (respuestaServicio['tarifa'] as num?)?.toDouble() ?? 0.0,
                              );
                            });
                          }
                        } else {
                          const String mensajeAlarma =
                              'Nuevo servicio disponible — revisa el radar';
                          final mastersData = await Supabase.instance.client
                              .from('usuarios')
                              .select('id')
                              .or('rol.eq.central,rol.eq.master,rango_movil.eq.MASTER')
                              .neq('suspendido', true);
                          List<String> masterIds = mastersData
                              .map((u) => u['id'].toString())
                              .toList();

                          if (masterIds.isNotEmpty) {
                            await _dispararMisilInmediato(
                              externalIds: masterIds,
                              titulo: retardoProgramado > 0
                                  ? '👑 SERVICIO PROGRAMADO'
                                  : '👑 NUEVO SERVICIO',
                              mensaje: mensajeAlarma,
                            );
                          }

                          if (pilotosSeleccionadosIds.isNotEmpty) {
                            List<String> targetPilotos = pilotosSeleccionadosIds
                                .where((id) => !masterIds.contains(id))
                                .toList();
                            if (targetPilotos.isNotEmpty) {
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

                          // Olas T=+60s y T=+90s
                          if (!esPuntoAPunto) {
                            final int _svcId2 = nuevoServicioId;
                            final String _msg2 = mensajeAlarma;
                            final List<String> _mSnap = List<String>.from(masterIds);
                            final List<String> _pSnap = List<String>.from(
                                pilotosSeleccionadosIds);

                            if (retardoProgramado > 0) {
                              List<String> zona1kmIds = [];
                              List<String> todosIds = [];
                              final medidor = const Distance();
                              final movilesActivos = await Supabase
                                  .instance.client.from('usuarios')
                                  .select('id, latitud, longitud')
                                  .eq('rol', 'movil').eq('en_linea', true);
                              for (var m in movilesActivos) {
                                final idStr = m['id'].toString();
                                todosIds.add(idStr);
                                double dist = 999999;
                                if (m['latitud'] != null && m['longitud'] != null &&
                                    coords['lat'] != null && coords['lng'] != null) {
                                  dist = medidor.as(
                                    LengthUnit.Meter,
                                    LatLng((m['latitud'] as num).toDouble(),
                                           (m['longitud'] as num).toDouble()),
                                    LatLng((coords['lat'] as num).toDouble(),
                                           (coords['lng'] as num).toDouble()),
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
                                await Supabase.instance.client
                                    .from('servicios').update({
                                      if (id1m != null) 'onesignal_2m': id1m,
                                      if (id2m != null) 'onesignal_5m': id2m,
                                    }).eq('id', _svcId2);
                              }
                            } else {
                              final double? _oLat2 = (coords['lat'] as num?)?.toDouble();
                              final double? _oLng2 = (coords['lng'] as num?)?.toDouble();
                              final movilesInm = await Supabase.instance.client
                                  .from('usuarios').select('id, latitud, longitud')
                                  .eq('rol', 'movil').eq('en_linea', true)
                                  .neq('suspendido', true)
                                  .not('rango_movil', 'in', '("MASTER")');
                              final idsZona60 = movilesInm.where((u) {
                                final id = u['id'].toString();
                                if (_mSnap.contains(id) || _pSnap.contains(id)) return false;
                                if (_oLat2 == null || _oLng2 == null) return true;
                                final uLat = (u['latitud'] as num?)?.toDouble();
                                final uLng = (u['longitud'] as num?)?.toDouble();
                                if (uLat == null || uLng == null) return false;
                                return const Distance().as(
                                      LengthUnit.Meter,
                                      LatLng(uLat, uLng),
                                      LatLng(_oLat2, _oLng2),
                                    ) <= 1000;
                              }).map((u) => u['id'].toString()).toList();
                              final idsTodos90 = movilesInm
                                  .map((u) => u['id'].toString())
                                  .where((id) => !_mSnap.contains(id))
                                  .toList();
                              String? id60s;
                              String? id90s;
                              if (idsZona60.isNotEmpty)
                                id60s = await _programarMisilRetardado(
                                  externalIds: idsZona60,
                                  titulo: '📡 SERVICIO CERCA (1km)',
                                  mensaje: _msg2,
                                  segundosRetardo: 60,
                                );
                              if (idsTodos90.isNotEmpty)
                                id90s = await _programarMisilRetardado(
                                  externalIds: idsTodos90,
                                  titulo: '🚨 SERVICIO SIN TOMAR',
                                  mensaje: _msg2,
                                  segundosRetardo: 90,
                                );
                              if (id60s != null || id90s != null) {
                                await Supabase.instance.client.from('servicios').update({
                                  if (id60s != null) 'onesignal_2m': id60s,
                                  if (id90s != null) 'onesignal_5m': id90s,
                                }).eq('id', _svcId2);
                              }
                            }
                          }
                        }

                        // ---> CIERRE Y APERTURA DE POPUP PARA GUARDAR NUEVOS PRECIOS <---
                        if (context.mounted) {
                          Navigator.pop(context);

                          String destinoMayus = destinoNuevo.toUpperCase();
                          String barrioExtraido = destinoMayus.contains('-')
                              ? destinoMayus.split('-')[0].trim()
                              : destinoMayus;

                          bool yaEstaGuardado = listaPrecios.any((item) {
                            final s = item['sectores'] as Map<String, dynamic>?;
                            if (s == null) return false;
                            final clave = '${s['nombre']} (${s['municipio']})'.toUpperCase();
                            return barrioExtraido == clave ||
                                (destinoMayus.startsWith(clave) &&
                                    (item['tarifa'] as num).toDouble() ==
                                        tarifaNueva);
                          });

                          if (!esPuntoAPunto &&
                              !esCotizacion &&
                              !yaEstaGuardado) {
                            final barrioCtrl = TextEditingController(
                              text: barrioExtraido,
                            );
                            String zonaSeleccionada = 'CÚCUTA';
                            bool guardandoLista = false;

                            showDialog(
                              context: context,
                              builder: (ctxSave) => StatefulBuilder(
                                builder: (ctxSave, setSaveState) => AlertDialog(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  title: const Text(
                                    '💾 ¿GUARDAR EN TU LISTA?',
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
                                      Text(
                                        'Tarifa cobrada: ${tarifaController.text}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.blue,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      TextField(
                                        controller: barrioCtrl,
                                        textCapitalization:
                                            TextCapitalization.characters,
                                        decoration: const InputDecoration(
                                          labelText:
                                              'Barrio / Lugar (Ej: COCONUCO)',
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
                                        children:
                                            [
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
                                                  if (selected)
                                                    setSaveState(
                                                      () =>
                                                          zonaSeleccionada = z,
                                                    );
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
                                      onPressed: guardandoLista
                                          ? null
                                          : () async {
                                              if (barrioCtrl.text
                                                  .trim()
                                                  .isEmpty)
                                                return;
                                              setSaveState(
                                                () => guardandoLista = true,
                                              );
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
                                                        'tarifa': tarifaNueva,
                                                      },
                                                      onConflict: 'local_id, sector_id',
                                                    );

                                                if (ctxSave.mounted) {
                                                  Navigator.pop(ctxSave);
                                                  ScaffoldMessenger.of(
                                                    context,
                                                  ).showSnackBar(
                                                    const SnackBar(
                                                      content: Text(
                                                        '✅ Dirección guardada en tu lista de precios.',
                                                      ),
                                                      backgroundColor:
                                                          Colors.green,
                                                    ),
                                                  );
                                                }
                                              } catch (e) {
                                                setSaveState(
                                                  () => guardandoLista = false,
                                                );
                                                if (ctxSave.mounted)
                                                  ScaffoldMessenger.of(
                                                    context,
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
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Text(
                      esCotizacion ? 'ENVIAR A CENTRAL' : 'ENVIAR PEDIDO',
                      style: const TextStyle(
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
