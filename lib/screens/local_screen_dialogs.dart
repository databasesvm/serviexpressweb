// ignore_for_file: curly_braces_in_flow_control_structures, no_leading_underscores_for_local_identifiers, use_build_context_synchronously, unused_element, unused_element_parameter
part of 'local_screen.dart';

// ══════════════════════════════════════════════════════════════════════════════
// _DialogsMixin — diálogos, paneles, CRM, configuración y acciones de cuenta
// ══════════════════════════════════════════════════════════════════════════════
mixin _DialogsMixin on State<LocalScreen> {
  // ── Abstract stubs (implementados en otros mixins / core) ──────────────────
  Widget _construirTarjetaServicio(
    Map<String, dynamic> servicio, {
    bool esHistorial = false,
    bool esGlobal = false,
    VoidCallback? onOcultar,
    VoidCallback? onEliminar,
    VoidCallback? extraRebuild,
  });
  void _abrirFormularioPedido(
    BuildContext ctx, {
    bool esPuntoAPunto = false,
    bool esCotizacion = false,
    bool esVip = false,
    required Map<String, dynamic> perfilEnVivo,
    String? telefonoPrellenado,
  });
  Future<Map<String, double>?> _obtenerOSellarGPSLocal({bool forzar = false});
  String get _tipoServicioDefecto;
  set _tipoServicioDefecto(String v);

  // =========================================================================
  // HISTORIAL GLOBAL DEL LOCAL
  // =========================================================================
  void _mostrarHistorialGlobal(BuildContext context) {
    // Future cacheado ANTES del builder para que setModalState no lo recree.
    final futureHistorial = Supabase.instance.client
        .from('servicios')
        .select()
        .eq('local_id', widget.usuario['id'])
        .inFilter('estado', [
          'finalizado',
          'cancelado',
          'caducado',
          'finalizado_por_demora',
          'finalizado_con_problema',
        ])
        .or('oculto_local.is.null,oculto_local.eq.false')
        .order('created_at', ascending: false)
        .limit(100);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0D0D0D),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => DraggableScrollableSheet(
          initialChildSize: 0.75,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) => Column(
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 10),
                width: 40,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const Text(
                'HISTORIAL COMPLETO',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: futureHistorial,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      );
                    }

                    // FIX #5: el filtro ya viaja en la query, no se necesita .where() aquí
                    final historialGlobal = snapshot.data ?? [];

                    if (historialGlobal.isEmpty) {
                      return const Center(
                        child: Text(
                          'No hay registros en tu auditoría.',
                          style: TextStyle(
                            color: Colors.white54,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      );
                    }

                    return ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.all(16),
                      itemCount: historialGlobal.length,
                      itemBuilder: (context, index) {
                        return _construirTarjetaServicio(
                          historialGlobal[index],
                          esHistorial: true,
                          esGlobal: true,
                          extraRebuild: () => setModalState(() {}),
                          onEliminar: () async {
                            final confirmar = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text(
                                  '⚠️ ELIMINAR REGISTRO',
                                  style: TextStyle(
                                    color: Colors.red,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                content: const Text(
                                  '¿Estás seguro de que quieres borrar este pedido? Desaparecerá de tu historial para siempre.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: const Text(
                                      'CANCELAR',
                                      style: TextStyle(color: Colors.grey),
                                    ),
                                  ),
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.red[900],
                                    ),
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: Text(
                                      'SÍ, BORRAR',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );

                            if (confirmar == true) {
                              // Disparamos el borrado fantasma a la base de datos
                              await Supabase.instance.client
                                  .from('servicios')
                                  .update({'oculto_local': true})
                                  .eq('id', historialGlobal[index]['id']);

                              // Recargamos el panel en vivo
                              setModalState(() {});
                            }
                          },
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
    );
  }

  // =========================================================================
  // BÚSQUEDA DE DIRECCIONES POR TELÉFONO — reutilizable
  // =========================================================================
  Future<List<Map<String, dynamic>>> _buscarDireccionesPorTelefono(
    String telefono,
  ) async {
    try {
      final res = await Supabase.instance.client
          .from('servicios')
          .select('destino, tarifa')
          .eq('telefono_receptor', telefono)
          .eq('local_id', widget.usuario['id'])
          .not('destino', 'is', null)
          .order('id', ascending: false)
          .limit(20);

      if (res.isEmpty) return [];

      // Filtro anti-duplicados — normaliza a mayúsculas
      final mapUnicos = <String, Map<String, dynamic>>{};
      for (var r in res) {
        String destinoNormalizado = r['destino'].toString().trim().toUpperCase();
        if (!mapUnicos.containsKey(destinoNormalizado)) {
          mapUnicos[destinoNormalizado] = r;
        }
      }
      // Corte táctico a las 3 más recientes
      return mapUnicos.values.take(3).toList();
    } catch (_) {
      return [];
    }
  }

  // =========================================================================
  // MÓDULO CRM: DIRECTORIO INTELIGENTE DE CLIENTES (VERSIÓN VOLUMEN)
  // =========================================================================
  void _abrirCRMLocal(
    BuildContext contextoPrincipal,
    Map<String, dynamic> perfilEnVivo,
  ) {
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
          initialChildSize: 0.85,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) => Column(
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 10),
                width: 40,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const Text(
                '👥 DIRECTORIO DE CLIENTES (CRM)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
              ),
              const Text(
                'Fidelización y volumen de envíos por WhatsApp',
                style: TextStyle(fontSize: 12, color: Colors.white54),
              ),

              Padding(
                padding: const EdgeInsets.all(16.0),
                child: TextField(
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Buscar por celular',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.search),
                    isDense: true,
                  ),
                  onChanged: (val) =>
                      setModalState(() => filtroActual = val.trim()),
                ),
              ),

              Expanded(
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: Supabase.instance.client
                      .from('servicios')
                      .select(
                        'id, destino, estado, created_at, telefono_receptor',
                      )
                      .eq('local_id', widget.usuario['id'])
                      .not('telefono_receptor', 'is', null),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      );
                    }

                    final servicios = snapshot.data ?? [];
                    if (servicios.isEmpty) {
                      return const Center(
                        child: Text(
                          'Aún no hay clientes registrados.',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.white54,
                          ),
                        ),
                      );
                    }

                    // --- MOTOR DE PROCESAMIENTO ---
                    Map<String, Map<String, dynamic>> directorio = {};

                    for (var servicio in servicios) {
                      String tel = servicio['telefono_receptor'].toString().trim();
                      if (tel.isEmpty || tel == 'null') continue;

                      if (!directorio.containsKey(tel)) {
                        directorio[tel] = {
                          'telefono': tel,
                          'total_pedidos': 0,
                          'completados': 0,
                          'cancelados': 0,
                          'ultima_fecha': null,
                          'direcciones': <String, int>{},
                          'historial': <Map<String, dynamic>>[],
                        };
                      }

                      directorio[tel]!['total_pedidos']++;
                      directorio[tel]!['historial'].add(servicio);

                      if (servicio['estado'] == 'finalizado') {
                        directorio[tel]!['completados']++;
                      } else if (servicio['estado'] == 'cancelado') {
                        directorio[tel]!['cancelados']++;
                      }

                      String dir =
                          servicio['destino']?.toString().toUpperCase() ?? '';
                      if (dir.isNotEmpty) {
                        Map<String, int> dirs = directorio[tel]!['direcciones'];
                        dirs[dir] = (dirs[dir] ?? 0) + 1;
                      }

                      if (servicio['created_at'] != null) {
                        DateTime fecha = DateTime.parse(servicio['created_at']);
                        DateTime? ultima = directorio[tel]!['ultima_fecha'];
                        if (ultima == null || fecha.isAfter(ultima)) {
                          directorio[tel]!['ultima_fecha'] = fecha;
                        }
                      }
                    }

                    List<Map<String, dynamic>> listaClientes = directorio.values
                        .toList();
                    if (filtroActual.isNotEmpty) {
                      listaClientes = listaClientes
                          .where(
                            (c) =>
                                c['telefono'].toString().contains(filtroActual),
                          )
                          .toList();
                    }

                    // Orden: Por cantidad de envíos exitosos
                    listaClientes.sort((a, b) {
                      int cmp = (b['completados'] as int).compareTo(
                        a['completados'] as int,
                      );
                      if (cmp == 0)
                        return (b['total_pedidos'] as int).compareTo(
                          a['total_pedidos'] as int,
                        );
                      return cmp;
                    });

                    return ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      itemCount: listaClientes.length,
                      itemBuilder: (ctx, i) {
                        final cliente = listaClientes[i];

                        Map<String, int> dirs = cliente['direcciones'];
                        String dirFavorita = 'Sin registrar';
                        if (dirs.isNotEmpty) {
                          var entradaMayor = dirs.entries.reduce(
                            (a, b) => a.value > b.value ? a : b,
                          );
                          dirFavorita = entradaMayor.key;
                        }

                        int completados = cliente['completados'];
                        Color badgeColor = Colors.grey;
                        String badgeText = 'NUEVO';
                        if (completados >= 10) {
                          badgeColor = Colors.purple;
                          badgeText = 'VIP';
                        } else if (completados >= 5) {
                          badgeColor = Colors.blue;
                          badgeText = 'FRECUENTE';
                        } else if (completados >= 2) {
                          badgeColor = Colors.green;
                          badgeText = 'CONOCIDO';
                        }

                        final DateTime? ultimaFecha = cliente['ultima_fecha'];
                        final String fechaStr = ultimaFecha != null
                            ? "${ultimaFecha.day}/${ultimaFecha.month}"
                            : "-";

                        return Card(
                          elevation: 1,
                          margin: const EdgeInsets.only(bottom: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: BorderSide(color: Colors.grey[300]!),
                          ),
                          child: InkWell(
                            onTap: () => _mostrarDetalleCliente(
                              contextoPrincipal,
                              cliente,
                              dirFavorita,
                              perfilEnVivo,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 22,
                                    backgroundColor: badgeColor.withValues(alpha: 0.1),
                                    child: Icon(
                                      Icons.person,
                                      color: badgeColor,
                                      size: 24,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Text(
                                              cliente['telefono'],
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 2,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: badgeColor,
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                badgeText,
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '📍 $dirFavorita',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Colors.black87,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            const Icon(
                                              Icons.motorcycle,
                                              size: 12,
                                              color: Colors.black54,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              '${cliente['completados']} envíos',
                                              style: const TextStyle(
                                                fontSize: 11,
                                                color: Colors.black54,
                                              ),
                                            ),
                                            if (cliente['cancelados'] > 0) ...[
                                              const SizedBox(width: 8),
                                              const Icon(
                                                Icons.cancel,
                                                size: 12,
                                                color: Colors.redAccent,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                '${cliente['cancelados']}',
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.redAccent,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Text(
                                        'Último',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.black54,
                                        ),
                                      ),
                                      Text(
                                        fechaStr,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                          color: Colors.black,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      const Icon(
                                        Icons.chevron_right,
                                        color: Colors.black38,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
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
    );
  }

  // SUB-PANTALLA: DETALLE EXACTO DEL CLIENTE
  void _mostrarDetalleCliente(
    BuildContext context,
    Map<String, dynamic> cliente,
    String dirFavorita,
    Map<String, dynamic> perfilEnVivo,
  ) {
    final DateTime? ultimaFecha = cliente['ultima_fecha'];
    final String fechaStr = ultimaFecha != null
        ? "${ultimaFecha.day}/${ultimaFecha.month}/${ultimaFecha.year}"
        : "Desconocida";
    final List historial = cliente['historial'];
    historial.sort(
      (a, b) => DateTime.parse(
        b['created_at'],
      ).compareTo(DateTime.parse(a['created_at'])),
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(
          children: [
            const Icon(Icons.contact_phone, color: Colors.blue),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'CLIENTE: ${cliente['telefono']}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 400,
          height: 450,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // PANEL DE MÉTRICAS (Simplificado)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue[200]!),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Column(
                      children: [
                        const Text(
                          'Exitosos',
                          style: TextStyle(fontSize: 10, color: Colors.black54),
                        ),
                        Text(
                          '${cliente['completados']}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: Colors.blue[800],
                          ),
                        ),
                      ],
                    ),
                    Container(width: 1, height: 32, color: Colors.grey[300]),
                    Column(
                      children: [
                        const Text(
                          'Cancelados',
                          style: TextStyle(fontSize: 10, color: Colors.black54),
                        ),
                        Text(
                          '${cliente['cancelados']}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: Colors.red,
                          ),
                        ),
                      ],
                    ),
                    Container(width: 1, height: 32, color: Colors.grey[300]),
                    Column(
                      children: [
                        const Text(
                          'Último',
                          style: TextStyle(fontSize: 10, color: Colors.black54),
                        ),
                        Text(
                          fechaStr,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: Colors.black,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '📍 Destino principal: $dirFavorita',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),

              const Text(
                'HISTORIAL DE DIRECCIONES:',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.black54,
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  itemCount: historial.length,
                  itemBuilder: (c, i) {
                    final servicio = historial[i];
                    final bool finalizado = servicio['estado'] == 'finalizado';
                    final dt = DateTime.parse(servicio['created_at']).toLocal();
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        finalizado ? Icons.check_circle : Icons.cancel,
                        color: finalizado ? Colors.green : Colors.red,
                        size: 20,
                      ),
                      title: Text(
                        '${servicio['destino']}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${dt.day}/${dt.month}/${dt.year} - ${servicio['estado'].toString().toUpperCase()}',
                        style: const TextStyle(fontSize: 10),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          // Fila 1: botones de acción
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xff3AF500),
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        icon: const Icon(Icons.motorcycle, size: 16),
                        label: const Text(
                          'NUEVO PEDIDO',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                        ),
                        onPressed: () {
                          Navigator.pop(ctx);
                          Navigator.pop(context);
                          _abrirFormularioPedido(
                            context,
                            esCotizacion: false,
                            perfilEnVivo: perfilEnVivo,
                            telefonoPrellenado: cliente['telefono'].toString(),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xff25D366),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        icon: const Icon(Icons.wechat, color: Colors.white, size: 16),
                        label: const Text(
                          'PROMO',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                        ),
                        onPressed: () async {
                          String numero = cliente['telefono'].toString().replaceAll(
                            RegExp(r'[^0-9]'), '');
                          if (numero.length == 10) numero = '57$numero';
                          final uri = Uri.parse(
                            'https://wa.me/$numero?text=${Uri.encodeComponent('¡Hola! Tenemos promociones especiales para ti hoy en ${widget.usuario['nombre']} 🍔🎁')}',
                          );
                          if (await canLaunchUrl(uri)) {
                            await launchUrl(uri, mode: LaunchMode.externalApplication);
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('CERRAR', style: TextStyle(color: Colors.black54)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // SELECTOR DE MAPA — PIN DE UBICACIÓN DEL LOCAL
  // =========================================================================
  void _abrirSelectorMapa() {
    LatLng centerPos = widget.usuario['lat_fija'] != null
        ? LatLng(
            widget.usuario['lat_fija'].toDouble(),
            widget.usuario['lng_fija'].toDouble(),
          )
        : const LatLng(7.8833, -72.5053); // Default Cúcuta

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        contentPadding: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text(
          'UBICA TU LOCAL',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
        content: SizedBox(
          width: 400,
          height: 450,
          child: Stack(
            children: [
              FlutterMap(
                options: MapOptions(
                  initialCenter: centerPos,
                  initialZoom: 16.0,
                  onPositionChanged: (pos, hasGesture) {
                    centerPos = pos.center;
                  },
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.serviexpress.express',
                  ),
                ],
              ),
              const Center(
                child: Padding(
                  padding: EdgeInsets.only(bottom: 40),
                  child: Icon(Icons.location_on, color: Colors.red, size: 40),
                ),
              ),
              Positioned(
                bottom: 16,
                left: 16,
                right: 16,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () async {
                    await Supabase.instance.client
                        .from('usuarios')
                        .update({
                          'lat_fija': centerPos.latitude,
                          'lng_fija': centerPos.longitude,
                        })
                        .eq('id', widget.usuario['id']);

                    setState(() {
                      widget.usuario['lat_fija'] = centerPos.latitude;
                      widget.usuario['lng_fija'] = centerPos.longitude;
                    });

                    if (ctx.mounted) {
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            '✅ Ubicación fijada.',
                            style: TextStyle(color: Colors.white),
                          ),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.save, color: Color(0xff3AF500)),
                  label: const Text(
                    'GUARDAR AQUÍ',
                    style: TextStyle(
                      color: Color(0xff3AF500),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // =========================================================================
  // QR DE LA CARTA DEL LOCAL
  // =========================================================================
  void _mostrarQrCarta(Map<String, dynamic> perfil) {
    final localId = perfil['id'] as int;
    final nombre = perfil['nombre']?.toString() ?? 'Mi Local';
    const webUrl = 'https://databasesvm.github.io/serviexpressweb/';
    final link = webUrl; // QR apunta a la web para clientes sin la app
    final texto = DeeplinkService.textoCompartible(nombre, localId);

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Compartir carta',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Comparte este QR para que tus clientes abran tu menú directamente',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
              const SizedBox(height: 16),
              Center(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: QrImageView(
                    data: link,
                    version: QrVersions.auto,
                    size: 200,
                    backgroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                link,
                style: const TextStyle(fontSize: 10, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Copiar link'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: link));
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Link copiado al portapapeles'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black,
              foregroundColor: const Color(0xff3AF500),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            icon: const Icon(Icons.share, size: 16),
            label: const Text('Compartir'),
            onPressed: () {
              Navigator.pop(context);
              Share.share(texto, subject: 'Pide en $nombre por ServiExpress');
            },
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // CONFIGURACIÓN DE DOMICILIOS
  // =========================================================================
  Future<void> _abrirConfigDomicilios(Map<String, dynamic> perfil) async {
    final db = Supabase.instance.client;
    final categorias = [
      'Restaurante / Comida', 'Bebidas y Licores', 'Panadería / Pastelería',
      'Mercado / Supermercado', 'Farmacia / Droguería',
      'Ferretería', 'Papelería', 'Tecnología / Electrónica',
      'Ropa / Accesorios', 'Miscelánea', 'Mascotas', 'Otro',
    ];
    String categoria = perfil['categoria_local']?.toString() ?? 'Comida';
    final tiempoCtrl = TextEditingController(text: (perfil['tiempo_entrega'] ?? 35).toString());
    final minimoCtrl = TextEditingController(text: (perfil['pedido_minimo'] ?? 0).toString());
    TimeOfDay? apertura = _parseTime(perfil['horario_apertura']?.toString());
    TimeOfDay? cierre   = _parseTime(perfil['horario_cierre']?.toString());
    // dias_semana: string "1111111" Mon=0..Sun=6
    final rawDias = perfil['dias_semana']?.toString();
    List<bool> diasAbierto = rawDias != null && rawDias.length == 7
        ? rawDias.split('').map((c) => c == '1').toList()
        : List<bool>.filled(7, true);

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setDlg) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Config. Domicilios',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Categoría', style: TextStyle(fontSize: 12, color: Colors.black54)),
                const SizedBox(height: 4),
                DropdownButtonFormField<String>(
                  initialValue: categorias.contains(categoria) ? categoria : 'Comida',
                  items: categorias.map((cat) => DropdownMenuItem(
                      value: cat, child: Text(cat, style: const TextStyle(fontSize: 13)))).toList(),
                  onChanged: (v) {
                  if (v == null) return;
                  setDlg(() {
                    categoria = v;
                    // Reflect auto-tipo in parent state (will be overridden if user changed it manually)
                    final s = v.toLowerCase();
                    if (s.contains('comida') || s.contains('restaurante') ||
                        s.contains('panader') || s.contains('pastel')) {
                      setState(() => _tipoServicioDefecto = 'COMIDA');
                    } else if (s.contains('bebidas') || s.contains('licores')) {
                      setState(() => _tipoServicioDefecto = 'BEBIDAS');
                    } else if (s.contains('paquete')) {
                      setState(() => _tipoServicioDefecto = 'PAQUETERÍA');
                    } else {
                      setState(() => _tipoServicioDefecto = 'COMPRAS');
                    }
                  });
                },
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(height: 12),
                const Text('Tiempo estimado de entrega', style: TextStyle(fontSize: 12, color: Colors.black54)),
                const SizedBox(height: 4),
                TextField(
                  controller: tiempoCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    suffixText: 'min',
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 12),
                const Text('Pedido mínimo (COP)', style: TextStyle(fontSize: 12, color: Colors.black54)),
                const SizedBox(height: 4),
                TextField(
                  controller: minimoCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    prefixText: '\$ ',
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 12),
                const Text('Horario de atención', style: TextStyle(fontSize: 12, color: Colors.black54)),
                const SizedBox(height: 4),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.access_time, size: 14),
                      label: Text(
                        apertura != null
                            ? '${apertura!.hour.toString().padLeft(2, "0")}:${apertura!.minute.toString().padLeft(2, "0")}'
                            : 'Apertura',
                        style: const TextStyle(fontSize: 12),
                      ),
                      onPressed: () async {
                        final t = await showTimePicker(
                            context: ctx2,
                            initialTime: apertura ?? const TimeOfDay(hour: 8, minute: 0));
                        if (t != null) setDlg(() => apertura = t);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.access_time, size: 14),
                      label: Text(
                        cierre != null
                            ? '${cierre!.hour.toString().padLeft(2, "0")}:${cierre!.minute.toString().padLeft(2, "0")}'
                            : 'Cierre',
                        style: const TextStyle(fontSize: 12),
                      ),
                      onPressed: () async {
                        final t = await showTimePicker(
                            context: ctx2,
                            initialTime: cierre ?? const TimeOfDay(hour: 22, minute: 0));
                        if (t != null) setDlg(() => cierre = t);
                      },
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                const Text('Días de atención', style: TextStyle(fontSize: 12, color: Colors.black54)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  children: List.generate(7, (i) {
                    const labels = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];
                    const fullNames = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
                    final activo = diasAbierto[i];
                    return FilterChip(
                      label: Text(labels[i],
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: activo ? Colors.white : Colors.black54)),
                      tooltip: fullNames[i],
                      selected: activo,
                      onSelected: (v) => setDlg(() => diasAbierto[i] = v),
                      selectedColor: Colors.black,
                      backgroundColor: const Color(0xFF0D0D0D),
                      checkmarkColor: const Color(0xff3AF500),
                      showCheckmark: false,
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                      visualDensity: VisualDensity.compact,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    );
                  }),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: const Color(0xff3AF500),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () async {
                final tiempo = int.tryParse(tiempoCtrl.text.trim()) ?? 35;
                final minimo = int.tryParse(minimoCtrl.text.trim()) ?? 0;
                final data = <String, dynamic>{
                  'categoria_local': categoria,
                  'tiempo_entrega': tiempo,
                  'pedido_minimo': minimo,
                  if (apertura != null)
                    'horario_apertura':
                        '${apertura!.hour.toString().padLeft(2, "0")}:${apertura!.minute.toString().padLeft(2, "0")}:00',
                  if (cierre != null)
                    'horario_cierre':
                        '${cierre!.hour.toString().padLeft(2, "0")}:${cierre!.minute.toString().padLeft(2, "0")}:00',
                  'dias_semana': diasAbierto.map((v) => v ? '1' : '0').join(),
                };
                try {
                  await db.from('usuarios').update(data).eq('id', perfil['id']);
                  if (ctx.mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                        content: Text('Configuración guardada'), backgroundColor: Colors.green));
                  }
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
                  }
                }
              },
              child: const Text('Guardar', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // HELPERS DE TIEMPO Y UBICACIÓN
  // =========================================================================
  TimeOfDay? _parseTime(String? s) {
    if (s == null || s.isEmpty) return null;
    final parts = s.split(':');
    if (parts.length < 2) return null;
    return TimeOfDay(hour: int.tryParse(parts[0]) ?? 0, minute: int.tryParse(parts[1]) ?? 0);
  }

  void _abrirMenuUbicacion() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          '📍 UBICACIÓN DEL LOCAL',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'Configura tu ubicación para que la Central te vea en el radar y te mande la flota más cercana.',
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue[800],
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.gps_fixed),
            label: const Text('USAR MI UBICACIÓN ACTUAL'),
            onPressed: () async {
              Navigator.pop(ctx);
              await _obtenerOSellarGPSLocal(forzar: true);
            },
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.purple[800],
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.map),
            label: const Text('UBICAR PIN EN EL MAPA'),
            onPressed: () {
              Navigator.pop(ctx);
              _abrirSelectorMapa();
            },
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // SESIÓN Y CUENTA
  // =========================================================================
  Future<void> _cerrarSesionSegura() async {
    final bool? confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Cerrar sesión', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text('¿Seguro que quieres cerrar sesión?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar', style: TextStyle(color: Colors.black54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.black),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('CERRAR SESIÓN',
                style: TextStyle(color: Color(0xff3AF500), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('saved_phone');
    await prefs.remove('saved_password');
    await prefs.setBool('auto_login', false);
    await prefs.remove('sesion_usuario_json');
    if (mounted) Navigator.pushReplacementNamed(context, '/');
  }

  // =========================================================================
  // RECARGO OBLIGATORIO — Confirma nocturno/lluvia antes de despachar.
  // =========================================================================
  Future<double?> _confirmarRecargoObligatorio(double precioBase) async {
    Map<String, dynamic>? recargo;
    try {
      final resultado = await Supabase.instance.client.rpc(
        'calcular_recargo_local',
        params: {'p_local_id': widget.usuario['id']},
      );
      if (resultado != null && (resultado as List).isNotEmpty) {
        recargo = resultado[0] as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('_confirmarRecargoObligatorio: $e');
    }

    // Sin recargo activo (o error de red) → seguimos con el precio tal cual
    final bool aplica = recargo?['aplica_recargo'] == true;
    if (!aplica) return precioBase;

    final int recargoTotal = (recargo!['recargo_total'] as num).toInt();
    final String desglose = recargo['desglose']?.toString() ?? '';
    final double precioFinal = precioBase + recargoTotal;

    if (!mounted) return null;

    final bool? confirmado = await showDialog<bool>(
      context: context,
      barrierDismissible: false, // No se puede ignorar tocando fuera
      builder: (ctxRecargo) => PopScope(
        canPop: false, // El botón atrás tampoco lo evade — debe elegir una opción
        child: AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: Colors.orange[700]!, width: 2),
          ),
          title: Row(
            children: [
              Icon(Icons.nights_stay, color: Colors.orange[800]),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'RECARGO ACTIVO',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Es horario nocturno o está lloviendo en tu zona. '
                'El recargo es obligatorio para continuar con este precio.',
                style: TextStyle(fontSize: 13, color: Colors.grey[700]),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tu precio: \$${_formatPesoSimple(precioBase)}',
                      style: const TextStyle(fontSize: 13),
                    ),
                    Text(
                      '+ $desglose',
                      style: TextStyle(fontSize: 13, color: Colors.orange[800]),
                    ),
                    const Divider(height: 16),
                    Text(
                      'Total: \$${_formatPesoSimple(precioFinal)}',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Si no estás de acuerdo, puedes cancelar y resolver el '
                'pedido por tu cuenta.',
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctxRecargo, false),
              child: Text(
                'CANCELAR DESPACHO',
                style: TextStyle(
                  color: Colors.grey[700],
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                minimumSize: const Size(double.infinity, 44),
              ),
              onPressed: () => Navigator.pop(ctxRecargo, true),
              child: Text(
                'CONFIRMAR \$${_formatPesoSimple(precioFinal)}',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (confirmado != true) return null;
    return precioFinal;
  }

  String _formatPesoSimple(double valor) {
    final s = valor.toInt().toString();
    final buffer = StringBuffer();
    final inicio = s.length % 3;
    if (inicio > 0) buffer.write(s.substring(0, inicio));
    for (int i = inicio; i < s.length; i += 3) {
      if (i > 0) buffer.write('.');
      buffer.write(s.substring(i, i + 3));
    }
    return buffer.toString();
  }

  // =========================================================================
  // ELIMINAR CUENTA
  // =========================================================================
  Future<void> _eliminarMiCuenta(BuildContext context) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Colors.red, width: 2),
        ),
        title: const Text(
          '⚠️ ELIMINAR CUENTA',
          style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          '¿Estás absolutamente seguro? Perderás todo tu historial, configuraciones y acceso al sistema. Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCELAR', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red[900]),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'SÍ, ELIMINAR',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmar == true) {
      try {
        await Supabase.instance.client
            .from('usuarios')
            .update({
              'suspendido': true,
              'en_linea': false,
              'observacion': 'CUENTA ELIMINADA POR EL USUARIO',
            })
            .eq('id', widget.usuario['id']);

        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('saved_phone');
        await prefs.remove('saved_password');
        await prefs.remove('sesion_usuario_json'); // evita auto-login con cuenta eliminada
        await prefs.setBool('auto_login', false);

        try {
          await Supabase.instance.client.auth.signOut();
        } catch (_) {}

        if (context.mounted) {
          Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
        }
      } catch (e) {
        if (context.mounted)
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }
}
