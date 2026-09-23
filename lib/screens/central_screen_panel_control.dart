// ignore_for_file: use_build_context_synchronously, invalid_use_of_protected_member
part of 'central_screen.dart';

extension CentralScreenPanelControl on _CentralScreenState {

  Widget _construirPanelControl() {
    return Container(
      margin: const EdgeInsets.all(8.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
            ),
            child: const Text(
              'CONTROL OPERATIVO',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _streamServiciosMonitor,
              builder: (context, snapServicios) {
                // Servicios activos en campo (para la sección "En Servicio")
                final serviciosEnCurso = (snapServicios.data ?? [])
                    .where(
                      (s) => [
                        'en_ruta_origen',
                        'en_origen',
                        'en_ruta_destino',
                        'problema',
                      ].contains(s['estado']),
                    )
                    .toList();

                return StreamBuilder<List<Map<String, dynamic>>>(
                  stream: _streamUsuariosMoviles,
                  // initialData evita parpadeo: siempre hay datos desde el inicio
                  initialData: _movilesCache,
                  builder: (context, snapshot) {
                    // Interceptor táctico para formatear la vista
                    final moviles = (snapshot.data ?? _movilesCache).map((m) {
                      final map = Map<String, dynamic>.from(m);
                      map['nombre'] = _formatearNombreCentral(map);
                      return map;
                    }).toList();

                    // Moviles con servicio activo
                    final movilesEnServicioIds = serviciosEnCurso
                        .map((s) => s['movil_id'])
                        .toSet();
                    // Helper: orden ascendente por número extraído de 'usuario' (ej: movil05 → 5)
                    int numMovil(Map<String, dynamic> m) =>
                        int.tryParse(RegExp(r'\d+').firstMatch(m['usuario']?.toString() ?? '')?.group(0) ?? '') ?? 9999;
                    int sortAscMovil(Map<String, dynamic> a, Map<String, dynamic> b) =>
                        numMovil(a).compareTo(numMovil(b));

                    final movilesEnServicio = moviles
                        .where(
                          (m) =>
                              movilesEnServicioIds.contains(m['id']) &&
                              m['en_linea'] == true,
                        )
                        .toList()
                      ..sort(sortAscMovil);

                    // --- MOTOR DE ORDENAMIENTO TÁCTICO (VIP > HORA) ---
                    int ordenarPorPrioridadYHora(
                      Map<String, dynamic> a,
                      Map<String, dynamic> b,
                    ) {
                      final ticketA = a['ticket_prioridad'] == true ? 1 : 0;
                      final ticketB = b['ticket_prioridad'] == true ? 1 : 0;
                      if (ticketA != ticketB) {
                        return ticketB.compareTo(ticketA); // El que tiene ticket va primero
                      }

                      final horaA = a['ingreso_fila'] != null
                          ? DateTime.parse(a['ingreso_fila'])
                          : DateTime.fromMillisecondsSinceEpoch(0);
                      final horaB = b['ingreso_fila'] != null
                          ? DateTime.parse(b['ingreso_fila'])
                          : DateTime.fromMillisecondsSinceEpoch(0);
                      final cmp = horaA.compareTo(horaB);
                      if (cmp != 0) return cmp;
                      // Empate: desempate por id para orden siempre estable
                      return ((a['id'] as num?) ?? 0).compareTo((b['id'] as num?) ?? 0);
                    }

                    // ── PARADEROS-C: filas dinámicas desde BD ──────────────
                    List<Map<String, dynamic>> _filaParadero(String nombre) {
                      final fila = moviles.where((m) =>
                        m['en_linea'] == true &&
                        m['paradero_actual'] == nombre &&
                        m['ingreso_fila'] != null &&
                        m['suspendido'] != true,
                      ).toList()..sort(ordenarPorPrioridadYHora);
                      return fila;
                    }

                    final sinFila = moviles
                        .where(
                          (m) =>
                              m['en_linea'] == true &&
                              m['paradero_actual'] == null &&
                              m['suspendido'] != true &&
                              !movilesEnServicioIds.contains(m['id']),
                        )
                        .toList()
                      ..sort(sortAscMovil);
                    // Bloqueados por inactividad
                    final bloqueados = moviles
                        .where((m) =>
                            m['bloqueado_inactividad'] == true &&
                            m['activo'] == true &&
                            m['suspendido'] != true)
                        .toList()
                      ..sort(sortAscMovil);

                    // De descanso: día fijo semanal == hoy
                    // 0=Dom, 1=Lun, 2=Mar, 3=Mié, 4=Jue, 5=Vie, 6=Sáb
                    final hoyDow = DateTime.now().weekday % 7;
                    final enDescanso = moviles
                        .where((m) =>
                            m['activo'] == true &&
                            m['suspendido'] != true &&
                            m['bloqueado_inactividad'] != true &&
                            m['dia_descanso_semanal'] != null &&
                            m['dia_descanso_semanal'] == hoyDow)
                        .toList()
                      ..sort(sortAscMovil);

                    final desconectados = moviles
                        .where(
                          (m) =>
                              m['en_linea'] != true &&
                              m['suspendido'] != true &&
                              m['activo'] == true &&
                              m['bloqueado_inactividad'] != true &&
                              m['dia_descanso_semanal'] != hoyDow,
                        )
                        .toList()
                      ..sort(sortAscMovil);
                    final suspendidos = moviles
                        .where((m) => m['suspendido'] == true)
                        .toList()
                      ..sort(sortAscMovil);

                    // ── MOTOS FN FARMANORTE ─────────────────────────────────
                    // Solo aparecen si están conectados y no suspendidos.
                    // Desconectados/suspendidos se ven en sus grupos normales.
                    final motosFn = moviles
                        .where((m) =>
                            m['tiene_fn'] == true &&
                            m['activo'] == true &&
                            m['en_linea'] == true &&
                            m['suspendido'] != true)
                        .toList()
                      ..sort(sortAscMovil);

                    return ListView(
                      children: [
                        // ── SECCIÓN FARMANORTE ──────────────────────────────
                        GestureDetector(
                          onTap: () => setState(() {
                            if (_seccionesOcultasFlota.contains('fn')) {
                              _seccionesOcultasFlota.remove('fn');
                            } else {
                              _seccionesOcultasFlota.add('fn');
                            }
                          }),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            color: const Color(0xFF002da2),
                            child: Row(
                              children: [
                                const Icon(Icons.local_pharmacy,
                                    color: Colors.white, size: 13),
                                const SizedBox(width: 6),
                                const Expanded(
                                  child: Text(
                                    'FARMANORTE',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                                Container(
                                  margin: const EdgeInsets.only(right: 4),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: motosFn.isNotEmpty
                                        ? Colors.white24
                                        : Colors.white10,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    '${motosFn.length}',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold),
                                  ),
                                ),
                                Icon(
                                  _seccionesOcultasFlota.contains('fn')
                                      ? Icons.expand_more
                                      : Icons.expand_less,
                                  color: Colors.white70,
                                  size: 16,
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (!_seccionesOcultasFlota.contains('fn')) ...[
                          if (motosFn.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(8),
                              child: Text(
                                'Sin motos FN registradas',
                                style: TextStyle(color: Colors.grey, fontSize: 11),
                              ),
                            )
                          else
                            ...motosFn.map((m) => FadeSlideIn(
                                  key: ValueKey('fn_${m['id']}'),
                                  child: ListTile(
                                    dense: true,
                                    leading: Stack(
                                      clipBehavior: Clip.none,
                                      children: [
                                        CircleAvatar(
                                          radius: 12,
                                          backgroundColor: const Color(0xFF002da2),
                                          child: Text(
                                            _extraerNumeroAvatar(m),
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        Positioned(
                                          right: -4,
                                          bottom: -3,
                                          child: Container(
                                            width: 12,
                                            height: 12,
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF002da2),
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                  color: Colors.white, width: 1),
                                            ),
                                            child: const Icon(
                                                Icons.local_pharmacy,
                                                size: 7,
                                                color: Colors.white),
                                          ),
                                        ),
                                      ],
                                    ),
                                    title: Text(
                                      m['nombre'].toString().toUpperCase(),
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                        color: const Color(0xFF002da2),
                                      ),
                                    ),
                                    subtitle: Text(
                                      _estadoMovilFn(m, movilesEnServicioIds),
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: _colorEstadoMovilFn(m, movilesEnServicioIds),
                                      ),
                                    ),
                                    onTap: () =>
                                        _abrirMenuAccionesMovil(context, m),
                                  ),
                                )),
                        ],

                        const Divider(height: 4, color: Colors.transparent),
                        // ── FIN SECCIÓN FN ──────────────────────────────────

                        // ── PARADEROS-C: secciones dinámicas desde BD ────────
                        // Si aún no cargó, muestra fallback silencioso.
                        // Una vez que _paraderosPanel tiene datos, genera una
                        // sección colapsable por cada paradero activo.
                        if (_paraderosPanel.isEmpty)
                          const SizedBox.shrink()
                        else
                          for (final paradero in _paraderosPanel) ...[
                            Builder(builder: (ctx) {
                              final nombre  = paradero['nombre'].toString();
                              final emoji   = paradero['emoji'] as String? ?? '📍';
                              final hexStr  = paradero['color_hex'] as String? ?? '#1565C0';
                              final esNoc   = paradero['es_nocturno'] == true;
                              final color   = _hexToColorPanel(hexStr);
                              final key     = nombre.toLowerCase();
                              final fila    = _filaParadero(nombre);

                              final bgColor  = esNoc ? color : color.withValues(alpha: 0.10);
                              final txtColor = esNoc ? Colors.white : color;
                              final badgeOn  = esNoc ? Colors.white24 : color;
                              final badgeOff = esNoc ? Colors.white10 : color.withValues(alpha: 0.30);
                              final chevronColor = esNoc ? Colors.white54 : color.withValues(alpha: 0.70);

                              return Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  GestureDetector(
                                    onTap: () => setState(() {
                                      if (_seccionesOcultasFlota.contains(key)) {
                                        _seccionesOcultasFlota.remove(key);
                                      } else {
                                        _seccionesOcultasFlota.add(key);
                                      }
                                    }),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      color: bgColor,
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              '$emoji $nombre',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: txtColor,
                                                fontSize: 11,
                                              ),
                                            ),
                                          ),
                                          AnimatedSwitcher(
                                            duration: const Duration(milliseconds: 220),
                                            child: Container(
                                              key: ValueKey('${key}_cnt_${fila.length}'),
                                              margin: const EdgeInsets.only(right: 6),
                                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: fila.isNotEmpty ? badgeOn : badgeOff,
                                                borderRadius: BorderRadius.circular(10),
                                              ),
                                              child: Text(
                                                '${fila.length}',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ),
                                          if (fila.isNotEmpty)
                                            TextButton.icon(
                                              onPressed: () => _vaciarParadero(nombre, fila),
                                              icon: const Icon(Icons.delete_sweep, size: 14, color: Colors.red),
                                              label: const Text('Vaciar', style: TextStyle(fontSize: 10, color: Colors.red)),
                                              style: TextButton.styleFrom(
                                                padding: EdgeInsets.zero,
                                                minimumSize: Size.zero,
                                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                              ),
                                            ),
                                          Icon(
                                            _seccionesOcultasFlota.contains(key)
                                                ? Icons.expand_more
                                                : Icons.expand_less,
                                            size: 16,
                                            color: chevronColor,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  if (!_seccionesOcultasFlota.contains(key))
                                    if (fila.isEmpty)
                                      const Padding(
                                        padding: EdgeInsets.all(8),
                                        child: Text(
                                          'Sin móviles en cola',
                                          style: TextStyle(color: Colors.grey, fontSize: 11),
                                        ),
                                      )
                                    else
                                      ...fila.asMap().entries.map((e) {
                                        final idx = e.key + 1;
                                        final m   = e.value;
                                        return FadeSlideIn(
                                          key: ValueKey('${key}_${m['id']}'),
                                          child: ListTile(
                                            dense: true,
                                            leading: _paraderoMovilLeading(m, color),
                                            title: Text(
                                              '#$idx. ${m['nombre'].toString().toUpperCase()}',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 12,
                                              ),
                                            ),
                                            subtitle: _subtituloMovilFlota(m),
                                            trailing: _movilTrailing(m),
                                            onTap: () => _abrirMenuAccionesMovil(context, m),
                                          ),
                                        );
                                      }),
                                ],
                              );
                            }),
                          ],

                        // =====================================================
                        // SECCIÓN: EN SERVICIO
                        // =====================================================
                        GestureDetector(
                          onTap: () => setState(() {
                            if (_seccionesOcultasFlota.contains('servicio')) {
                              _seccionesOcultasFlota.remove('servicio');
                            } else {
                              _seccionesOcultasFlota.add('servicio');
                            }
                          }),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            color: Colors.orange[800],
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '🚴 EN SERVICIO  (${movilesEnServicio.length})',
                                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 11, letterSpacing: 0.5),
                                  ),
                                ),
                                Icon(
                                  _seccionesOcultasFlota.contains('servicio') ? Icons.expand_more : Icons.expand_less,
                                  size: 16,
                                  color: Colors.orange[200],
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (!_seccionesOcultasFlota.contains('servicio')) ...[
                          if (movilesEnServicio.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              child: Text(
                                'Ningún móvil en campo ahora',
                                style: TextStyle(color: Colors.grey, fontSize: 11),
                              ),
                            )
                          else
                            ...movilesEnServicio.map((movil) {
                            final svcsDelMovil = serviciosEnCurso
                                .where((s) => s['movil_id'] == movil['id'])
                                .toList();
                            return FadeSlideIn(
                              key: ValueKey('svc_${movil['id']}'),
                              child: Material(
                              color: Colors.orange[50],
                              child: InkWell(
                                onTap: () => _abrirMenuAccionesMovil(context, movil),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // Avatar
                                      CircleAvatar(
                                        radius: 13,
                                        backgroundColor: Colors.orange[700],
                                        child: Text(
                                          _extraerNumeroAvatar(movil),
                                          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      // Info principal + servicios
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              movil['nombre'].toString().toUpperCase(),
                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                            ),
                                            const SizedBox(height: 1),
                                            Row(children: [
                                              Text(
                                                '${movil['rango_movil'] ?? 'NOVATO'} · ${_formatCalificacion(movil['puntuacion'])}',
                                                style: const TextStyle(fontSize: 10, color: Colors.black45),
                                              ),
                                              const SizedBox(width: 6),
                                              Builder(builder: (_) {
                                                final p = _pingLabel(movil);
                                                return Text(p, style: TextStyle(fontSize: 9, color: p.startsWith('●') ? Colors.green[700] : Colors.grey[400], fontWeight: FontWeight.w600));
                                              }),
                                            ]),
                                            const SizedBox(height: 4),
                                            // Servicios compactos: uno por fila
                                            ...svcsDelMovil.map((s) {
                                              final String ico;
                                              final String fase;
                                              final Color faseColor;
                                              switch (s['estado']) {
                                                case 'en_ruta_origen':
                                                  ico = '🔵'; fase = 'RUTA ORIGEN'; faseColor = Colors.blue[700]!; break;
                                                case 'en_origen':
                                                  ico = '📍'; fase = 'EN LOCAL'; faseColor = Colors.purple[700]!; break;
                                                case 'en_ruta_destino':
                                                  ico = '🚀'; fase = 'RUTA DESTINO'; faseColor = Colors.green[700]!; break;
                                                case 'problema':
                                                  ico = '🚨'; fase = 'NOVEDAD'; faseColor = Colors.red[700]!; break;
                                                default:
                                                  ico = '●'; fase = s['estado'] ?? ''; faseColor = Colors.grey;
                                              }
                                              final String origen = s['origen'] ?? '—';
                                              final String destino = s['destino'] ?? '';
                                              final String creador = s['creador']?.toString() ?? '';
                                              // Tiempo transcurrido desde accepted_at
                                              String tiempoStr = '';
                                              if (s['accepted_at'] != null) {
                                                final aceptado = DateTime.tryParse(s['accepted_at'].toString())?.toLocal();
                                                if (aceptado != null) {
                                                  final mins = DateTime.now().difference(aceptado).inMinutes;
                                                  tiempoStr = mins < 60 ? '${mins}min' : '${mins ~/ 60}h${mins % 60}m';
                                                }
                                              }
                                              // Tarifa
                                              final tarifa = (s['tarifa'] as num?)?.toInt();
                                              final tarifaStr = tarifa != null && tarifa > 0 ? '\$${_formatearMonedaCentral(tarifa.toDouble())}' : '';
                                              return Container(
                                                margin: const EdgeInsets.only(top: 4),
                                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
                                                decoration: BoxDecoration(
                                                  color: Colors.white,
                                                  borderRadius: BorderRadius.circular(6),
                                                  border: Border.all(color: faseColor.withValues(alpha: 0.4)),
                                                ),
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    // Fila 1: fase + tiempo + tarifa
                                                    Row(
                                                      children: [
                                                        Container(
                                                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                                          decoration: BoxDecoration(
                                                            color: faseColor.withValues(alpha: 0.12),
                                                            borderRadius: BorderRadius.circular(4),
                                                          ),
                                                          child: Text(
                                                            '$ico $fase',
                                                            style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: faseColor),
                                                          ),
                                                        ),
                                                        if (tiempoStr.isNotEmpty) ...[
                                                          const SizedBox(width: 5),
                                                          Text('⏱ $tiempoStr', style: const TextStyle(fontSize: 9, color: Colors.black38)),
                                                        ],
                                                        const Spacer(),
                                                        if (tarifaStr.isNotEmpty)
                                                          Text(tarifaStr, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.green[800])),
                                                      ],
                                                    ),
                                                    const SizedBox(height: 3),
                                                    // Fila 2: #id · creador · origen
                                                    Text(
                                                      '#${s['id']}${creador.isNotEmpty && creador != 'Central' ? ' · $creador' : ''} · $origen',
                                                      style: const TextStyle(fontSize: 10, color: Colors.black54),
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                    if (destino.isNotEmpty)
                                                      Text(
                                                        '→ $destino',
                                                        style: const TextStyle(fontSize: 10, color: Colors.black87, fontWeight: FontWeight.w500),
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                    // Badge foto de comanda
                                                    if ((s['foto_comanda_url']?.toString() ?? '').isNotEmpty)
                                                      GestureDetector(
                                                        onTap: () => showDialog(
                                                          context: context,
                                                          builder: (_) => Dialog(
                                                            backgroundColor: Colors.black,
                                                            insetPadding: const EdgeInsets.all(12),
                                                            child: Stack(children: [
                                                              InteractiveViewer(
                                                                child: Image.network(
                                                                  s['foto_comanda_url'].toString(),
                                                                  fit: BoxFit.contain,
                                                                ),
                                                              ),
                                                              Positioned(
                                                                top: 4, right: 4,
                                                                child: IconButton(
                                                                  icon: const Icon(Icons.close, color: Colors.white),
                                                                  onPressed: () => Navigator.pop(context),
                                                                ),
                                                              ),
                                                            ]),
                                                          ),
                                                        ),
                                                        child: Padding(
                                                          padding: const EdgeInsets.only(top: 3),
                                                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                                                            const Text('📷', style: TextStyle(fontSize: 9)),
                                                            const SizedBox(width: 2),
                                                            Text('foto comanda',
                                                                style: TextStyle(
                                                                    fontSize: 8,
                                                                    color: Colors.brown[600],
                                                                    fontWeight: FontWeight.w600)),
                                                          ]),
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                              );
                                            }),
                                          ],
                                        ),
                                      ),
                                      // Más opciones
                                      const Icon(
                                        Icons.more_vert,
                                        color: Colors.black38,
                                        size: 18,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              ),  // Material
                            );    // FadeSlideIn
                          }),
                        ],  // if !servicio oculto

                        GestureDetector(
                          onTap: () => setState(() {
                            if (_seccionesOcultasFlota.contains('libre')) {
                              _seccionesOcultasFlota.remove('libre');
                            } else {
                              _seccionesOcultasFlota.add('libre');
                            }
                          }),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            color: Colors.green[700],
                            child: Row(
                              children: [
                                const Expanded(
                                  child: Text(
                                    '🏍️ LIBRE / SIN PARADERO',
                                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 11),
                                  ),
                                ),
                                AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 220),
                                  child: Container(
                                    key: ValueKey('libre_cnt_${sinFila.length}'),
                                    margin: const EdgeInsets.only(right: 6),
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: sinFila.isNotEmpty ? Colors.green[900] : Colors.green[600],
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text('${sinFila.length}',
                                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                  ),
                                ),
                                Icon(
                                  _seccionesOcultasFlota.contains('libre') ? Icons.expand_more : Icons.expand_less,
                                  size: 16,
                                  color: Colors.green[200],
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (!_seccionesOcultasFlota.contains('libre')) ...[
                          if (sinFila.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(8),
                              child: Text(
                                'Ninguno rodando libre',
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 11,
                                ),
                              ),
                            )
                          else
                            ...sinFila.map(
                              (m) => ListTile(
                                dense: true,
                                leading: _paraderoMovilLeading(m, Colors.green[600]!),
                                title: Text(
                                  m['nombre'].toString().toUpperCase(),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                subtitle: _subtituloMovilFlota(m),
                                trailing: _movilTrailing(m),
                                onTap: () => _abrirMenuAccionesMovil(context, m),
                              ),
                            ),
                        ],

                        // =====================================================
                        // SUSPENDIDOS — antes que desconectados
                        // =====================================================
                        if (suspendidos.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            color: Colors.red[900],
                            child: Row(
                              children: [
                                const Expanded(
                                  child: Text(
                                    '🛑 SUSPENDIDOS',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.red[700],
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    '${suspendidos.length}',
                                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ...suspendidos.map((movil) {
                          return Material(
                            color: Colors.transparent,
                            child: ListTile(
                              dense: true,
                              leading: _paraderoMovilLeading(movil, Colors.red[800]!),
                              title: Text(
                                movil['nombre'] ?? 'Desconocido',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  color: Colors.red[800],
                                ),
                              ),
                              subtitle: _subtituloMovilFlota(movil),
                              trailing: _movilTrailing(movil),
                              onTap: () =>
                                  _abrirMenuAccionesMovil(context, movil),
                            ),
                          );
                        }),

                        // =====================================================
                        // BLOQUEADOS POR INACTIVIDAD — desplegable
                        // =====================================================
                        if (bloqueados.isNotEmpty || _bloqueadosExpandidos)
                          InkWell(
                            onTap: () => setState(
                              () => _bloqueadosExpandidos = !_bloqueadosExpandidos,
                            ),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              color: const Color(0xFF7C2D12),
                              child: Row(children: [
                                const Icon(Icons.lock_outline, color: Colors.orange, size: 13),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    '🔒 BLOQUEADOS POR INACTIVIDAD (${bloqueados.length})',
                                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange, fontSize: 11),
                                  ),
                                ),
                                Icon(
                                  _bloqueadosExpandidos ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                                  size: 16, color: Colors.orange,
                                ),
                              ]),
                            ),
                          ),
                        if (_bloqueadosExpandidos)
                          if (bloqueados.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(8),
                              child: Text('Sin bloqueados', style: TextStyle(color: Colors.grey, fontSize: 11)),
                            )
                          else
                            ...bloqueados.map((movil) => Material(
                              color: const Color(0xFF1C0A00),
                              child: ListTile(
                                dense: true,
                                leading: _paraderoMovilLeading(movil, Colors.orange[800]!),
                                title: Text(
                                  movil['nombre'] ?? 'Desconocido',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.orange),
                                ),
                                subtitle: Text(
                                  'Inactivo ${movil['dias_inactivos_acumulados'] ?? 0} día(s)',
                                  style: const TextStyle(color: Colors.orange, fontSize: 10),
                                ),
                                trailing: _movilTrailing(movil),
                                onTap: () => _abrirMenuAccionesMovil(context, movil),
                              ),
                            )),

                        // =====================================================
                        // DE DESCANSO HOY — desplegable
                        // =====================================================
                        if (enDescanso.isNotEmpty || _descansoExpandido)
                          InkWell(
                            onTap: () => setState(
                              () => _descansoExpandido = !_descansoExpandido,
                            ),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              color: const Color(0xFF064E3B),
                              child: Row(children: [
                                const Icon(Icons.beach_access, color: Colors.greenAccent, size: 13),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    '🏖️ DE DESCANSO HOY (${enDescanso.length})',
                                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.greenAccent, fontSize: 11),
                                  ),
                                ),
                                Icon(
                                  _descansoExpandido ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                                  size: 16, color: Colors.greenAccent,
                                ),
                              ]),
                            ),
                          ),
                        if (_descansoExpandido)
                          if (enDescanso.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(8),
                              child: Text('Sin móviles de descanso', style: TextStyle(color: Colors.grey, fontSize: 11)),
                            )
                          else
                            ...enDescanso.map((movil) => Material(
                              color: const Color(0xFF022C22),
                              child: ListTile(
                                dense: true,
                                leading: _paraderoMovilLeading(movil, Colors.green[700]!),
                                title: Text(
                                  movil['nombre'] ?? 'Desconocido',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.greenAccent),
                                ),
                                subtitle: const Text('Día de descanso fijo', style: TextStyle(color: Colors.green, fontSize: 10)),
                                trailing: _movilTrailing(movil),
                                onTap: () => _abrirMenuAccionesMovil(context, movil),
                              ),
                            )),

                        // =====================================================
                        // DESCONECTADOS — desplegable
                        // =====================================================
                        InkWell(
                          onTap: () => setState(
                            () => _desconectadosExpandidos = !_desconectadosExpandidos,
                          ),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            color: Colors.grey[200],
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '⚫ DESCONECTADOS (${desconectados.length})',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black54,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                                Icon(
                                  _desconectadosExpandidos
                                      ? Icons.keyboard_arrow_up
                                      : Icons.keyboard_arrow_down,
                                  size: 16,
                                  color: Colors.black38,
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (_desconectadosExpandidos)
                          if (desconectados.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(8),
                              child: Text(
                                'Nadie desconectado',
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 11,
                                ),
                              ),
                            )
                          else
                            ...desconectados.map((movil) {
                            // Solo las últimas 24h — una falla de hace
                            // meses no debería perseguir a un moto para
                            // siempre, sobre todo si ya mejoró desde
                            // entonces. Filtrado server-side: más rápido
                            // que traer todo el historial y descartar
                            // el resto en el cliente.
                            final hace24h = DateTime.now()
                                .toUtc()
                                .subtract(const Duration(hours: 24))
                                .toIso8601String();
                            return FutureBuilder<List<Map<String, dynamic>>>(
                              future: Supabase.instance.client
                                  .from('servicios')
                                  .select(
                                    'id, origen, destino, estado, observacion, created_at',
                                  )
                                  .eq('movil_id', movil['id'])
                                  .not('estado', 'eq', 'pendiente')
                                  .not('estado', 'eq', 'en_curso')
                                  .not('estado', 'eq', 'problema')
                                  .gte('created_at', hace24h),
                              builder: (context, historySnapshot) {
                                final historialReciente =
                                    historySnapshot.data ?? [];
                                final fallasRecientes = historialReciente
                                    .where(
                                      (f) =>
                                          f['estado'] ==
                                              'finalizado_por_demora' ||
                                          f['estado'] ==
                                              'finalizado_con_problema' ||
                                          (f['observacion'] != null &&
                                              f['observacion']
                                                  .toString()
                                                  .contains(
                                                    '[MARCA DE FALLA]',
                                                  )),
                                    )
                                    .length;
                                return Material(
                                  color: Colors.transparent,
                                  child: ListTile(
                                    dense: true,
                                    leading: _paraderoMovilLeading(movil, Colors.grey[500]!),
                                    title: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            movil['nombre'] ?? 'Desconocido',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                              color: Colors.black87,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        if (fallasRecientes > 0)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 4,
                                              vertical: 1,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.red[50],
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                              border: Border.all(
                                                color: Colors.red[300]!,
                                              ),
                                            ),
                                            child: Text(
                                              // Singular si fue 1, cuenta
                                              // solo si pasó más de una
                                              // vez en las últimas 24h.
                                              fallasRecientes == 1
                                                  ? 'FALLA (24h)'
                                                  : '$fallasRecientes FALLAS (24h)',
                                              style: TextStyle(
                                                color: Colors.red[900],
                                                fontSize: 9,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                    subtitle: _subtituloMovilFlota(movil),
                                    trailing: _movilTrailing(movil),
                                    onTap: () => _abrirMenuAccionesMovil(
                                      context,
                                      movil,
                                    ),
                                  ),
                                );
                              },
                            );
                          }),
                      ],
                    );
                  },
                ); // cierre StreamBuilder _streamUsuariosMoviles
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _construirPanelMapa() {
    return Container(
      margin: const EdgeInsets.all(8.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: const BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'RADAR DE MÓVILES',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _radarActivo ? 'ON' : 'OFF',
                      style: TextStyle(
                        color: _radarActivo
                            ? const Color(0xff3AF500)
                            : Colors.redAccent,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                    Transform.scale(
                      scale: 0.8,
                      child: Switch(
                        value: _radarActivo,
                        onChanged: (val) => setState(() => _radarActivo = val),
                        activeThumbColor: const Color(0xff3AF500),
                        activeTrackColor: Colors.green[900],
                        inactiveThumbColor: Colors.redAccent,
                        inactiveTrackColor: Colors.red[900],
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh_rounded, color: Colors.white70, size: 18),
                      tooltip: 'Actualizar radar',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      onPressed: () async {
                        // 1. Fetch + reconexión de streams (datos frescos)
                        await _preCargarDatosIniciales();
                        _construirStreams();

                        // 2. Push silencioso heartbeat a todos los móviles
                        // conectados — les ordena reiniciar el GPS stream y
                        // emitir su posición inmediatamente.
                        try {
                          final movilesOnline = await Supabase.instance.client
                              .from('usuarios')
                              .select('id')
                              .eq('rol', 'movil')
                              .eq('en_linea', true)
                              .neq('suspendido', true);
                          final ids = movilesOnline
                              .map((m) => m['id'].toString())
                              .toList();
                          if (ids.isNotEmpty) {
                            await MotorNotificaciones.dispararSilencioso(
                              idsDestinos: ids,
                              data: {'tipo': 'heartbeat'},
                            );
                          }
                        } catch (_) {}

                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('🔄 Radar actualizado.'),
                              duration: Duration(seconds: 1),
                              backgroundColor: Colors.black87,
                            ),
                          );
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: !_radarActivo
                ? Container(
                    width: double.infinity,
                    decoration: const BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.vertical(
                        bottom: Radius.circular(8),
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.radar, size: 60, color: Colors.grey[800]),
                        const SizedBox(height: 16),
                        const Text(
                          'RADAR DESACTIVADO',
                          style: TextStyle(
                            color: Colors.white54,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 2,
                          ),
                        ),
                      ],
                    ),
                  )
                : StreamBuilder<List<Map<String, dynamic>>>(
                    stream: _streamUsuariosMoviles,
                    builder: (context, snapMoviles) {
                      List<Marker> marcadores = [];

                      // ── Pins de paraderos ──────────────────────────────
                      if (_mapaParaderos) {
                        for (final p in _paraderosPanel) {
                          final lat = (p['latitud'] as num?)?.toDouble();
                          final lng = (p['longitud'] as num?)?.toDouble();
                          if (lat == null || lng == null) continue;
                          final pinColor = _hexToColorPanel(
                              p['color_hex'] as String? ?? '#1565C0');
                          final pinLabel = p['nombre'].toString();
                          final pinEmoji = p['emoji'] as String? ?? '📍';
                          marcadores.add(Marker(
                            point: LatLng(lat, lng),
                            width: 72,
                            height: 56,
                            child: Column(mainAxisSize: MainAxisSize.min, children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                decoration: BoxDecoration(
                                  color: pinColor,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '$pinEmoji $pinLabel',
                                  style: const TextStyle(color: Colors.white,
                                      fontSize: 8, fontWeight: FontWeight.bold),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Icon(Icons.location_on, color: pinColor, size: 28),
                            ]),
                          ));
                        }
                      }

                      // ── Pins de sedes FN (con número) ─────────────────
                      if (_mapaSedesFN) {
                        for (final s in _sedesFN) {
                          final lat = (s['lat'] as num?)?.toDouble();
                          final lng = (s['lng'] as num?)?.toDouble();
                          if (lat == null || lng == null) continue;
                          final label = 'FN${s['numero']}';
                          marcadores.add(Marker(
                            point: LatLng(lat, lng),
                            width: 64,
                            height: 52,
                            child: Column(mainAxisSize: MainAxisSize.min, children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF002DA2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  label,
                                  style: const TextStyle(color: Colors.white,
                                      fontSize: 8, fontWeight: FontWeight.bold),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const Icon(Icons.store_rounded, color: Color(0xFF002DA2), size: 26),
                            ]),
                          ));
                        }
                      }

                      // ── Pins de puntos FN (droguerías, bodega, etc.) ───
                      if (_mapaPuntosFN) {
                        for (final s in _puntosFN) {
                          final lat = (s['lat'] as num?)?.toDouble();
                          final lng = (s['lng'] as num?)?.toDouble();
                          if (lat == null || lng == null) continue;
                          final label = (s['nombre']?.toString() ?? '').toUpperCase();
                          marcadores.add(Marker(
                            point: LatLng(lat, lng),
                            width: 80,
                            height: 52,
                            child: Column(mainAxisSize: MainAxisSize.min, children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF546E7A),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  label,
                                  style: const TextStyle(color: Colors.white,
                                      fontSize: 8, fontWeight: FontWeight.bold),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const Icon(Icons.place_rounded, color: Color(0xFF546E7A), size: 26),
                            ]),
                          ));
                        }
                      }

                      // ── Pins de locales con coordenadas ────────────────
                      if (_mapaLocales) {
                        for (final l in _localesUbicacion) {
                          final lat = (l['lat_fija'] as num?)?.toDouble();
                          final lng = (l['lng_fija'] as num?)?.toDouble();
                          if (lat == null || lng == null) continue;
                          final label = (l['nombre']?.toString() ?? 'LOCAL').toUpperCase();
                          marcadores.add(Marker(
                            point: LatLng(lat, lng),
                            width: 80,
                            height: 52,
                            child: Column(mainAxisSize: MainAxisSize.min, children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFC62828),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  label,
                                  style: const TextStyle(color: Colors.white,
                                      fontSize: 8, fontWeight: FontWeight.bold),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const Icon(Icons.storefront_rounded, color: Color(0xFFC62828), size: 26),
                            ]),
                          ));
                        }
                      }

                      if (snapMoviles.hasData) {
                        for (var m in snapMoviles.data!) {
                          if (_mapaMoviles &&
                              m['en_linea'] == true &&
                              m['latitud'] != null &&
                              m['longitud'] != null &&
                              m['suspendido'] != true) {
                            marcadores.add(
                              Marker(
                                point: LatLng(m['latitud'], m['longitud']),
                                width: 60,
                                height: 60,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: const BoxDecoration(
                                        color: Colors.black87,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Text(
                                        _extraerNumeroAvatar(m),
                                        style: const TextStyle(
                                          color: Color(0xff3AF500),
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    const Icon(
                                      Icons.motorcycle,
                                      color: Colors.green,
                                      size: 24,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }
                        }
                      }
                      return Column(children: [
                        // ── Barra de filtros ───────────────────────────
                        Container(
                          color: Colors.black87,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(children: [
                              _filtroChip('Paraderos', _mapaParaderos, const Color(0xFF1565C0),
                                  () => setState(() => _mapaParaderos = !_mapaParaderos)),
                              const SizedBox(width: 6),
                              _filtroChip('Sedes FN', _mapaSedesFN, const Color(0xFF002DA2),
                                  () => setState(() => _mapaSedesFN = !_mapaSedesFN)),
                              const SizedBox(width: 6),
                              _filtroChip('Puntos FN', _mapaPuntosFN, const Color(0xFF546E7A),
                                  () => setState(() => _mapaPuntosFN = !_mapaPuntosFN)),
                              const SizedBox(width: 6),
                              _filtroChip('Locales', _mapaLocales, const Color(0xFFC62828),
                                  () => setState(() => _mapaLocales = !_mapaLocales)),
                              const SizedBox(width: 6),
                              _filtroChip('Móviles', _mapaMoviles, Colors.green,
                                  () => setState(() => _mapaMoviles = !_mapaMoviles)),
                            ]),
                          ),
                        ),
                        // ── Mapa ───────────────────────────────────────
                        Expanded(
                          child: ClipRRect(
                            borderRadius: const BorderRadius.vertical(
                              bottom: Radius.circular(8),
                            ),
                            child: FlutterMap(
                              options: const MapOptions(
                                initialCenter: LatLng(7.8634, -72.4757),
                                initialZoom: 15.5,
                              ),
                              children: [
                                TileLayer(
                                  urlTemplate:
                                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                  userAgentPackageName: 'com.serviexpress.express',
                                ),
                                MarkerLayer(markers: marcadores),
                              ],
                            ),
                          ),
                        ),
                      ]);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _construirPanelMonitor() {
    return Container(
      margin: const EdgeInsets.all(8.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: const BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'MONITOR DE SERVICIOS',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                    fontSize: 12,
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(Icons.route_rounded, size: 16,
                          color: _modoMulti ? const Color(0xff3AF500) : Colors.white70),
                      tooltip: _modoMulti ? 'Cancelar multi-ruta' : 'Asignar multi-ruta',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      onPressed: () => setState(() {
                        _modoMulti = !_modoMulti;
                        if (!_modoMulti) _multiSeleccion.clear();
                      }),
                    ),
                    IconButton(
                      icon: const Icon(Icons.filter_list, size: 16, color: Colors.white70),
                      tooltip: 'Filtrar Monitor',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      onPressed: () => _abrirMenuFiltroMonitor(context),
                    ),
                    IconButton(
                      icon: const Icon(Icons.history, size: 16, color: Colors.white70),
                      tooltip: 'Historial Completo',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      onPressed: () => _abrirHistorialCompletoCentral(context),
                    ),
                    IconButton(
                      icon: const Icon(Icons.cleaning_services_rounded, size: 16, color: Colors.redAccent),
                      tooltip: 'Limpiar finalizados',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      onPressed: _archivarServiciosTerminados,
                    ),
                  ],
                ),
              ],
            ),
          ),
          // ── BARRA DE BÚSQUEDA ──────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 2),
            child: TextField(
              controller: _busquedaCtrl,
              onChanged: (val) {
                _busquedaTexto = val.toLowerCase().trim();
                _filtroVersion.value++;
              },
              style: const TextStyle(fontSize: 12),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Buscar por ruta, cliente, local, móvil...',
                hintStyle: TextStyle(fontSize: 11, color: Colors.grey[400]),
                prefixIcon: const Icon(Icons.search, size: 16),
                suffixIcon: _busquedaTexto.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close, size: 14),
                        onPressed: () {
                          _busquedaCtrl.clear();
                          _busquedaTexto = '';
                          _filtroVersion.value++;
                        },
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      )
                    : null,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: Colors.black54),
                ),
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _streamServiciosMonitor,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(color: Colors.black),
                  );
                }
                final todos = snapshot.data ?? [];

                // Orden ascendente por ID en todas las listas (#16)
                List<Map<String, dynamic>> _asc(Iterable<Map<String, dynamic>> it) =>
                    it.toList()..sort((a, b) => ((a['id'] as int?) ?? 0).compareTo((b['id'] as int?) ?? 0));

                final problemas = _asc(todos.where((s) => s['estado'] == 'problema'));
                final cotizaciones = _asc(todos.where((s) => s['estado'] == 'cotizacion'));
                final renegociaciones = _asc(todos.where((s) => s['estado'] == 'fn_renegociando'));
                final cotizadas = _asc(todos.where((s) => s['estado'] == 'cotizada'));
                final cotizacionesAprobadas = _asc(todos.where((s) => s['estado'] == 'cotizacion_aprobada'));
                final finalizadosDemora = _asc(todos.where((s) => s['estado'] == 'finalizado_por_demora'));
                // Asignados directo FN (esperando aceptación del móvil asignado)
                final directosFnEsperando = _asc(todos.where((s) =>
                    s['estado'] == 'pendiente' &&
                    s['fn_asignacion_tipo'] == 'directo_presel'));
                // Libres para el radar (pendiente sin asignación directa)
                final libres = _asc(todos.where((s) =>
                    s['estado'] == 'pendiente' &&
                    s['fn_asignacion_tipo'] != 'directo_presel'));
                // ---> INYECCIÓN: EXTRAER LOS PROGRAMADOS <---
                final programados = _asc(todos.where((s) => s['estado'] == 'programado'));
                final enCurso = _asc(todos.where((s) => [
                      'en_ruta_origen',
                      'en_origen',
                      'en_ruta_destino',
                    ].contains(s['estado'])));
                final finalizadosProblema = _asc(todos.where((s) => s['estado'] == 'finalizado_con_problema'));
                final finalizados = _asc(todos.where((s) => s['estado'] == 'finalizado'));
                final cancelados = _asc(todos.where((s) => s['estado'] == 'cancelado'));
                final caducados = _asc(todos.where((s) => s['estado'] == 'caducado'));
                // Contadores para chips toggle
                final kpiFinalizados = finalizados.length +
                    finalizadosProblema.length +
                    finalizadosDemora.length;
                final kpiCancelados = cancelados.length + caducados.length;

                // Sonidos de estado manejados por radar_central_bg channel

                // ValueListenableBuilder reacciona al filtro/búsqueda sin
                // reconstruir el StreamBuilder completo (evita parpadeo).
                return ValueListenableBuilder<int>(
                  valueListenable: _filtroVersion,
                  builder: (context, _, __) {
                    // ── FILTRO POR BÚSQUEDA ────────────────────────────────
                    bool matchBusqueda(Map<String, dynamic> s) {
                      if (_busquedaTexto.isEmpty) return true;
                      final q = _busquedaTexto;
                      if ((s['origen'] ?? '').toString().toLowerCase().contains(q)) return true;
                      if ((s['destino'] ?? '').toString().toLowerCase().contains(q)) return true;
                      if ((s['numero_cliente'] ?? '').toString().contains(q)) return true;
                      if ((s['numero_local'] ?? '').toString().contains(q)) return true;
                      if ((s['numero_movil'] ?? '').toString().contains(q)) return true;
                      if ((s['observacion'] ?? '').toString().toLowerCase().contains(q)) return true;
                      // buscar por #moto (ej: "5" o "#5")
                      final movEntry = _movilesCache.firstWhere(
                        (m) => m['id'] == s['movil_id'], orElse: () => <String, dynamic>{});
                      if (movEntry.isNotEmpty) {
                        final usuario = movEntry['usuario']?.toString() ?? '';
                        if (usuario.toLowerCase().contains(q)) return true;
                      }
                      return false;
                    }

                    // KPIs desde todos (sin filtro de búsqueda)
                    final kpiPendientes = todos.where((s) => s['estado'] == 'pendiente').length;
                    final kpiEnCurso = todos.where((s) => ['en_ruta_origen','en_origen','en_ruta_destino'].contains(s['estado'])).length;
                    final kpiProblemas = todos.where((s) => s['estado'] == 'problema').length;
                    final hoy = DateTime.now();
                    final todosHoy = todos.where((s) {
                      if (s['created_at'] == null) return false;
                      final d = DateTime.parse(s['created_at']).toLocal();
                      return d.year == hoy.year && d.month == hoy.month && d.day == hoy.day;
                    }).toList();
                    final kpiHoy = todosHoy.length;
                    final kpiFact = todosHoy
                        .where((s) => ['finalizado', 'finalizado_con_problema', 'finalizado_por_demora'].contains(s['estado']))
                        .fold<double>(0, (acc, s) => acc + ((s['tarifa'] as num?)?.toDouble() ?? 0));
                    final segsDesde = DateTime.now().difference(_ultimaActualizacion).inSeconds;
                    final actLabel = segsDesde < 5 ? 'ahora' : 'hace ${segsDesde}s';

                    // Listas filtradas por búsqueda
                    List<Map<String, dynamic>> _filtrar(List<Map<String, dynamic>> lista) =>
                        lista.where(matchBusqueda).toList();

                    return Column(
                      children: [
                        // ── KPIs ────────────────────────────────────────────
                        Container(
                          color: const Color(0xFFF5F5F5),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                          child: Row(
                            children: [
                              _kpiChip('LIBRE', kpiPendientes, const Color(0xff3AF500)),
                              const SizedBox(width: 5),
                              _kpiChip('CURSO', kpiEnCurso, Colors.amber[700]!),
                              const SizedBox(width: 5),
                              if (kpiProblemas > 0) ...[
                                _kpiChip('PROB', kpiProblemas, Colors.red[700]!),
                                const SizedBox(width: 5),
                              ],
                              _kpiChip('HOY', kpiHoy, Colors.blueGrey[600]!,
                                  onTap: () => _mostrarResumenDia(context, todosHoy)),
                              const SizedBox(width: 5),
                              // Toggles de finalizados/cancelados recientes
                              if (kpiFinalizados > 0)
                                _kpiChip(
                                  'FIN', kpiFinalizados, Colors.grey[600]!,
                                  active: _mostrarFinalizados,
                                  onTap: () {
                                    _mostrarFinalizados = !_mostrarFinalizados;
                                    _filtroVersion.value++;
                                  },
                                ),
                              if (kpiFinalizados > 0 && kpiCancelados > 0)
                                const SizedBox(width: 5),
                              if (kpiCancelados > 0)
                                _kpiChip(
                                  'CANC', kpiCancelados, Colors.black54,
                                  active: _mostrarCancelados,
                                  onTap: () {
                                    _mostrarCancelados = !_mostrarCancelados;
                                    _filtroVersion.value++;
                                  },
                                ),
                              const Spacer(),
                              if (kpiFact > 0)
                                Text(
                                  _formatearMonedaCentral(kpiFact),
                                  style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black54),
                                ),
                              const SizedBox(width: 6),
                              Text(
                                '● $actLabel',
                                style: TextStyle(
                                    fontSize: 8,
                                    color: segsDesde < 10
                                        ? Colors.green[600]
                                        : Colors.orange[700]),
                              ),
                            ],
                          ),
                        ),
                        // ── LISTA ────────────────────────────────────────────
                        Expanded(
                          child: ListView(
                            padding: const EdgeInsets.only(bottom: 10),
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              _construirBloqueServicios(
                                context,
                                '⚠️ REPORTES DE PROBLEMA',
                                _filtrar(problemas),
                                Colors.red[700]!,
                                Icons.warning_rounded,
                                visible: !_seccionesOcultasMonitor.contains('problemas'),
                              ),
                              _construirBloqueServicios(
                                context,
                                '🔄 RENEGOCIACIONES FN',
                                _filtrar(renegociaciones),
                                Colors.deepOrange[700]!,
                                Icons.sync_rounded,
                                visible: !_seccionesOcultasMonitor.contains('renegociaciones'),
                              ),
                              _construirBloqueServicios(
                                context,
                                '❓ COTIZACIONES PENDIENTES',
                                _filtrar(cotizaciones),
                                Colors.orange[700]!,
                                Icons.calculate_outlined,
                                visible: !_seccionesOcultasMonitor.contains('cotizaciones'),
                              ),
                              _construirBloqueServicios(
                                context,
                                '✉️ COTIZACIONES ENVIADAS',
                                _filtrar(cotizadas),
                                Colors.blue[600]!,
                                Icons.hourglass_top,
                                visible: !_seccionesOcultasMonitor.contains('cotizadas'),
                              ),
                              _construirBloqueServicios(
                                context,
                                '✅ COTIZACIONES APROBADAS · EN ESPERA',
                                _filtrar(cotizacionesAprobadas),
                                Colors.teal[700]!,
                                Icons.check_circle_outline,
                                visible: !_seccionesOcultasMonitor.contains('cotizaciones_aprobadas'),
                              ),
                              _construirBloqueServicios(
                                context,
                                '⏰ SERVICIOS PROGRAMADOS (EN ESPERA)',
                                _filtrar(programados),
                                Colors.teal[700]!,
                                Icons.schedule,
                                visible: !_seccionesOcultasMonitor.contains('programados'),
                              ),
                              if (_mostrarCancelados)
                                _construirBloqueServicios(
                                  context,
                                  '♻️ SERVICIOS CADUCADOS',
                                  _filtrar(caducados),
                                  Colors.purple[800]!,
                                  Icons.hourglass_disabled,
                                  visible: !_seccionesOcultasMonitor.contains('caducados'),
                                ),
                              if (_mostrarFinalizados)
                                _construirBloqueServicios(
                                  context,
                                  '⏱️ SERVICIOS VENCIDOS / DEMORADOS',
                                  _filtrar(finalizadosDemora),
                                  Colors.deepPurple[700]!,
                                  Icons.timer_off,
                                  visible: !_seccionesOcultasMonitor.contains('demorados'),
                                ),
                              _construirBloqueServicios(
                                context,
                                '🎯 FN DIRECTO · ESPERANDO ACEPTACIÓN',
                                _filtrar(directosFnEsperando),
                                Colors.indigo[400]!,
                                Icons.assignment_ind_outlined,
                                visible: !_seccionesOcultasMonitor.contains('fn_directos'),
                              ),
                              _construirBloqueServicios(
                                context,
                                '🟢 RADAR DE DISPONIBLES',
                                _filtrar(libres),
                                const Color(0xff3AF500),
                                Icons.add_task,
                                visible: !_seccionesOcultasMonitor.contains('libres'),
                              ),
                              _construirBloqueServicios(
                                context,
                                '🟡 SERVICIOS EN CURSO',
                                _filtrar(enCurso),
                                Colors.amber[600]!,
                                Icons.motorcycle,
                                visible: !_seccionesOcultasMonitor.contains('en_curso'),
                              ),
                              if (_mostrarFinalizados) ...[
                                _construirBloqueServicios(
                                  context,
                                  '🔴 SERVICIOS FINALIZADOS CON PROBLEMA',
                                  _filtrar(finalizadosProblema),
                                  Colors.red[900]!,
                                  Icons.report_off,
                                  visible: !_seccionesOcultasMonitor.contains('finalizados_problema'),
                                ),
                                _construirBloqueServicios(
                                  context,
                                  '⚪ SERVICIOS FINALIZADOS',
                                  _filtrar(finalizados),
                                  Colors.grey[500]!,
                                  Icons.check_circle_outline,
                                  visible: !_seccionesOcultasMonitor.contains('finalizados'),
                                ),
                              ],
                              if (_mostrarCancelados)
                                _construirBloqueServicios(
                                  context,
                                  '⚫ SERVICIOS CANCELADOS',
                                  _filtrar(cancelados),
                                  Colors.black54,
                                  Icons.block,
                                  visible: !_seccionesOcultasMonitor.contains('cancelados'),
                                ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
          // ── BARRA MULTI-RUTA ───────────────────────────────────────────────
          if (_modoMulti)
            Container(
              color: Colors.indigo[800],
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(children: [
                const Icon(Icons.route_rounded, color: Colors.white70, size: 14),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _multiSeleccion.isEmpty
                        ? 'Toca servicios para seleccionar'
                        : '${_multiSeleccion.length} servicio${_multiSeleccion.length == 1 ? "" : "s"} seleccionado${_multiSeleccion.length == 1 ? "" : "s"}',
                    style: const TextStyle(color: Colors.white, fontSize: 11),
                  ),
                ),
                if (_multiSeleccion.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () => _asignarMultiRuta(context),
                    icon: const Icon(Icons.motorcycle, size: 13),
                    label: const Text('ASIGNAR RUTA',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xff3AF500),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ]),
            ),
        ],
      ),
    );
  }

  // =========================================================================
  // CONFIGURACIÓN DE RECARGOS POR LOCAL
  // =========================================================================
  // recargo_nocturno_especial: NULL = usa el default de config_sistema
  //   ($2.000). Un valor propio (ej: 1000) = convenio especial del local.
  //
  // zona_lluvia: 'general' = recibe recargo si llueve en cualquier zona
  //   monitoreada. 'trapiches' = SOLO si llueve específicamente en
  //   Trapiches (evita cobrar de más a locales que solo despachan ahí).
  // =========================================================================
  // EXPULSIÓN DE PARADERO — individual y general
  // =========================================================================
  // Saca a un moto de la fila sin afectar su cuenta — solo limpia
  // paradero_actual/ingreso_fila. Puede volver a registrarse cuando
  // quiera (sigue en línea, solo pierde su puesto en la fila).
  // =========================================================================
  // MENÚ DE ACCIONES POR MÓVIL — un solo punto de entrada, sin botones
  // apretados que se puedan tocar por error. Se abre al tocar la
  // tarjeta del moto en cualquiera de las filas de paradero.
  // =========================================================================

  // ── PARADEROS-C: carga dinámica desde BD ──────────────────────────────────
  Widget _filtroChip(String label, bool activo, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: activo ? color : Colors.transparent,
          border: Border.all(color: color, width: 1.2),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: activo ? Colors.white : color,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Future<void> _cargarParaderosPanel() async {
    if (!mounted) return;
    try {
      final data = await Supabase.instance.client
          .from('paraderos')
          .select()
          .eq('activo', true)
          .order('orden', ascending: true);
      if (mounted) {
        setState(() => _paraderosPanel = List<Map<String, dynamic>>.from(data));
      }
    } catch (_) {
      // Si falla, el panel muestra los fallbacks hardcoded
    }

    // Sedes FN y puntos FN (droguerías, bodega, etc.)
    try {
      final todasFN = await Supabase.instance.client
          .from('fn_sedes')
          .select('id, numero, nombre, lat, lng')
          .eq('activo', true)
          .not('lat', 'is', null)
          .not('lng', 'is', null);
      if (mounted) {
        final lista = List<Map<String, dynamic>>.from(todasFN);
        setState(() {
          _sedesFN  = lista.where((s) => s['numero'] != null).toList();
          _puntosFN = lista.where((s) => s['numero'] == null).toList();
        });
      }
    } catch (_) {}

    // Locales con coordenadas fijas
    try {
      final locales = await Supabase.instance.client
          .from('usuarios')
          .select('id, nombre, lat_fija, lng_fija')
          .eq('rol', 'local')
          .eq('suspendido', false)
          .not('lat_fija', 'is', null)
          .not('lng_fija', 'is', null);
      if (mounted) {
        setState(() => _localesUbicacion = List<Map<String, dynamic>>.from(locales));
      }
    } catch (_) {}
  }

  /// Alias local de _hexColor (definido en central_screen_gestion.dart).
  Color _hexToColorPanel(String hex) => _hexColor(hex);
}
