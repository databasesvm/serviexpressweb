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
                    final movilesEnServicio = moviles
                        .where(
                          (m) =>
                              movilesEnServicioIds.contains(m['id']) &&
                              m['en_linea'] == true,
                        )
                        .toList();

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
                      return horaA.compareTo(horaB);
                    }

                    final filaExpuente = moviles
                        .where(
                          (m) =>
                              m['en_linea'] == true &&
                              m['paradero_actual'] == 'EXPUENTE' &&
                              m['ingreso_fila'] != null &&
                              m['suspendido'] != true,
                        )
                        .toList();
                    filaExpuente.sort(ordenarPorPrioridadYHora);

                    final filaMemos = moviles
                        .where(
                          (m) =>
                              m['en_linea'] == true &&
                              m['paradero_actual'] == 'MEMOS' &&
                              m['ingreso_fila'] != null &&
                              m['suspendido'] != true,
                        )
                        .toList();
                    filaMemos.sort(ordenarPorPrioridadYHora);

                    final filaNocturno = moviles
                        .where(
                          (m) =>
                              m['en_linea'] == true &&
                              m['paradero_actual'] == 'NOCTURNO' &&
                              m['ingreso_fila'] != null &&
                              m['suspendido'] != true,
                        )
                        .toList();
                    filaNocturno.sort(ordenarPorPrioridadYHora);

                    final sinFila = moviles
                        .where(
                          (m) =>
                              m['en_linea'] == true &&
                              m['paradero_actual'] == null &&
                              m['suspendido'] != true &&
                              !movilesEnServicioIds.contains(m['id']),
                        )
                        .toList();
                    final desconectados = moviles
                        .where(
                          (m) =>
                              m['en_linea'] != true &&
                              m['suspendido'] != true &&
                              m['activo'] == true,
                        )
                        .toList();
                    final suspendidos = moviles
                        .where((m) => m['suspendido'] == true)
                        .toList();

                    // ── MOTOS FN FARMANORTE ─────────────────────────────────
                    final motosFn = moviles
                        .where(
                          (m) =>
                              m['tiene_fn'] == true &&
                              m['en_linea'] == true &&
                              m['suspendido'] != true,
                        )
                        .toList();

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
                            color: Colors.indigo[900],
                            child: Row(
                              children: [
                                const Icon(Icons.local_pharmacy,
                                    color: Colors.white, size: 13),
                                const SizedBox(width: 6),
                                const Expanded(
                                  child: Text(
                                    'CONTROL OPERATIVO FARMANORTE',
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
                                'Sin motos FN en línea',
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
                                          backgroundColor: Colors.indigo[900],
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
                                              color: Colors.indigo[700],
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
                                        color: Colors.indigo[900],
                                      ),
                                    ),
                                    subtitle: Text(
                                      '${m['rango_movil'] ?? 'NOVATO'} · ${m['fn_ignorados_hoy'] ?? 0} ign. hoy',
                                      style: const TextStyle(
                                          fontSize: 10, color: Colors.black54),
                                    ),
                                    onTap: () =>
                                        _abrirMenuAccionesMovil(context, m),
                                  ),
                                )),
                        ],

                        const Divider(height: 4, color: Colors.transparent),
                        // ── FIN SECCIÓN FN ──────────────────────────────────

                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          color: Colors.blue[50],
                          child: Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  '📍 PARADERO 1 (Expuente)',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 220),
                                child: Container(
                                  key: ValueKey('exp_cnt_${filaExpuente.length}'),
                                  margin: const EdgeInsets.only(right: 6),
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: filaExpuente.isNotEmpty ? Colors.blue[800] : Colors.blue[200],
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    '${filaExpuente.length}',
                                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ),
                              if (filaExpuente.isNotEmpty)
                                TextButton.icon(
                                  onPressed: () => _vaciarParadero(
                                    'Expuente',
                                    filaExpuente,
                                  ),
                                  icon: const Icon(
                                    Icons.delete_sweep,
                                    size: 14,
                                    color: Colors.red,
                                  ),
                                  label: const Text(
                                    'Vaciar',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.red,
                                    ),
                                  ),
                                  style: TextButton.styleFrom(
                                    padding: EdgeInsets.zero,
                                    minimumSize: const Size(40, 24),
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                ),
                              IconButton(
                                onPressed: () => setState(() {
                                  if (_seccionesOcultasFlota.contains('expuente')) {
                                    _seccionesOcultasFlota.remove('expuente');
                                  } else {
                                    _seccionesOcultasFlota.add('expuente');
                                  }
                                }),
                                icon: Icon(
                                  _seccionesOcultasFlota.contains('expuente')
                                      ? Icons.expand_more
                                      : Icons.expand_less,
                                  size: 16,
                                  color: Colors.blue[400],
                                ),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                visualDensity: VisualDensity.compact,
                              ),
                            ],
                          ),
                        ),
                        if (!_seccionesOcultasFlota.contains('expuente')) ...[
                          if (filaExpuente.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(8),
                              child: Text(
                                'Sin móviles en cola',
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 11,
                                ),
                              ),
                            )
                          else
                            ...filaExpuente.asMap().entries.map((e) {
                              int idx = e.key + 1;
                              var m = e.value;
                              return FadeSlideIn(
                                key: ValueKey('exp_${m['id']}'),
                                child: ListTile(
                                  dense: true,
                                  leading: _paraderoMovilLeading(m, Colors.blue[800]!),
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

                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          color: Colors.purple[50],
                          child: Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  '📍 PARADERO 2 (Memos)',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.purple,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 220),
                                child: Container(
                                  key: ValueKey('mem_cnt_${filaMemos.length}'),
                                  margin: const EdgeInsets.only(right: 6),
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: filaMemos.isNotEmpty ? Colors.purple[800] : Colors.purple[200],
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    '${filaMemos.length}',
                                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ),
                              if (filaMemos.isNotEmpty)
                                TextButton.icon(
                                  onPressed: () =>
                                      _vaciarParadero('Memos', filaMemos),
                                  icon: const Icon(
                                    Icons.delete_sweep,
                                    size: 14,
                                    color: Colors.red,
                                  ),
                                  label: const Text(
                                    'Vaciar',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.red,
                                    ),
                                  ),
                                  style: TextButton.styleFrom(
                                    padding: EdgeInsets.zero,
                                    minimumSize: const Size(40, 24),
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                ),
                              IconButton(
                                onPressed: () => setState(() {
                                  if (_seccionesOcultasFlota.contains('memos')) {
                                    _seccionesOcultasFlota.remove('memos');
                                  } else {
                                    _seccionesOcultasFlota.add('memos');
                                  }
                                }),
                                icon: Icon(
                                  _seccionesOcultasFlota.contains('memos')
                                      ? Icons.expand_more
                                      : Icons.expand_less,
                                  size: 16,
                                  color: Colors.purple[300],
                                ),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                visualDensity: VisualDensity.compact,
                              ),
                            ],
                          ),
                        ),
                        if (!_seccionesOcultasFlota.contains('memos')) ...[
                          if (filaMemos.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(8),
                              child: Text(
                                'Sin móviles en cola',
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 11,
                                ),
                              ),
                            )
                          else
                            ...filaMemos.asMap().entries.map((e) {
                              int idx = e.key + 1;
                              var m = e.value;
                              return FadeSlideIn(
                                key: ValueKey('memos_${m['id']}'),
                                child: ListTile(
                                  dense: true,
                                  leading: _paraderoMovilLeading(m, Colors.purple[800]!),
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

                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          color: Colors.indigo[900],
                          child: Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  '🌙 PARADERO NOCTURNO',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 220),
                                child: Container(
                                  key: ValueKey('noc_cnt_${filaNocturno.length}'),
                                  margin: const EdgeInsets.only(right: 6),
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: filaNocturno.isNotEmpty ? Colors.indigo[300] : Colors.indigo[700],
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    '${filaNocturno.length}',
                                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ),
                              if (filaNocturno.isNotEmpty)
                                TextButton.icon(
                                  onPressed: () => _vaciarParadero(
                                    'Nocturno',
                                    filaNocturno,
                                  ),
                                  icon: const Icon(
                                    Icons.delete_sweep,
                                    size: 14,
                                    color: Colors.orangeAccent,
                                  ),
                                  label: const Text(
                                    'Vaciar',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.orangeAccent,
                                    ),
                                  ),
                                  style: TextButton.styleFrom(
                                    padding: EdgeInsets.zero,
                                    minimumSize: const Size(40, 24),
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                ),
                              IconButton(
                                onPressed: () => setState(() {
                                  if (_seccionesOcultasFlota.contains('nocturno')) {
                                    _seccionesOcultasFlota.remove('nocturno');
                                  } else {
                                    _seccionesOcultasFlota.add('nocturno');
                                  }
                                }),
                                icon: Icon(
                                  _seccionesOcultasFlota.contains('nocturno')
                                      ? Icons.expand_more
                                      : Icons.expand_less,
                                  size: 16,
                                  color: Colors.indigo[200],
                                ),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                visualDensity: VisualDensity.compact,
                              ),
                            ],
                          ),
                        ),
                        if (!_seccionesOcultasFlota.contains('nocturno')) ...[
                          if (filaNocturno.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(8),
                              child: Text(
                                'Sin móviles en cola',
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 11,
                                ),
                              ),
                            )
                          else
                            ...filaNocturno.asMap().entries.map((e) {
                              int idx = e.key + 1;
                              var m = e.value;
                              return FadeSlideIn(
                                key: ValueKey('noc_${m['id']}'),
                                child: ListTile(
                                  dense: true,
                                  leading: _paraderoMovilLeading(m, Colors.indigo[400]!),
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
                                ),  // ListTile
                              );    // FadeSlideIn
                            }),
                        ],

                        // =====================================================
                        // SECCIÓN: EN SERVICIO
                        // =====================================================
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                          color: Colors.orange[800],
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '🚴 EN SERVICIO  (${movilesEnServicio.length})',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    fontSize: 11,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                              IconButton(
                                onPressed: () => setState(() {
                                  if (_seccionesOcultasFlota.contains('servicio')) {
                                    _seccionesOcultasFlota.remove('servicio');
                                  } else {
                                    _seccionesOcultasFlota.add('servicio');
                                  }
                                }),
                                icon: Icon(
                                  _seccionesOcultasFlota.contains('servicio')
                                      ? Icons.expand_more
                                      : Icons.expand_less,
                                  size: 16,
                                  color: Colors.orange[200],
                                ),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                visualDensity: VisualDensity.compact,
                              ),
                            ],
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
                                              switch (s['estado']) {
                                                case 'en_ruta_origen':  ico = '🔵'; fase = 'Ruta origen'; break;
                                                case 'en_origen':       ico = '📍'; fase = 'En origen'; break;
                                                case 'en_ruta_destino': ico = '🚀'; fase = 'Ruta destino'; break;
                                                case 'problema':        ico = '🚨'; fase = 'Problema'; break;
                                                default: ico = '●'; fase = s['estado'] ?? '';
                                              }
                                              final String origen = s['origen'] ?? '—';
                                              final String destino = s['destino'] ?? '';
                                              return Container(
                                                margin: const EdgeInsets.only(top: 3),
                                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                                decoration: BoxDecoration(
                                                  color: Colors.white,
                                                  borderRadius: BorderRadius.circular(5),
                                                  border: Border.all(color: Colors.orange[200]!),
                                                ),
                                                child: Row(
                                                  children: [
                                                    Text('$ico ', style: const TextStyle(fontSize: 11)),
                                                    Expanded(
                                                      child: Text(
                                                        '#${s['id']} $fase · $origen${destino.isNotEmpty ? ' → $destino' : ''}',
                                                        style: const TextStyle(fontSize: 10, color: Colors.black87),
                                                        overflow: TextOverflow.ellipsis,
                                                        maxLines: 1,
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

                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                          color: Colors.green[700],
                          child: Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  '🏍️ LIBRE / SIN PARADERO',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 220),
                                child: Container(
                                  key: ValueKey('libre_cnt_${sinFila.length}'),
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: sinFila.isNotEmpty ? Colors.green[900] : Colors.green[600],
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    '${sinFila.length}',
                                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ),
                              IconButton(
                                onPressed: () => setState(() {
                                  if (_seccionesOcultasFlota.contains('libre')) {
                                    _seccionesOcultasFlota.remove('libre');
                                  } else {
                                    _seccionesOcultasFlota.add('libre');
                                  }
                                }),
                                icon: Icon(
                                  _seccionesOcultasFlota.contains('libre')
                                      ? Icons.expand_more
                                      : Icons.expand_less,
                                  size: 16,
                                  color: Colors.green[200],
                                ),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                visualDensity: VisualDensity.compact,
                              ),
                            ],
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
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
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
                        // DESCONECTADOS — desplegable
                        // =====================================================
                        InkWell(
                          onTap: () => setState(
                            () => _desconectadosExpandidos = !_desconectadosExpandidos,
                          ),
                          child: Container(
                            padding: const EdgeInsets.all(8),
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
                    Switch(
                      value: _radarActivo,
                      onChanged: (val) => setState(() => _radarActivo = val),
                      activeThumbColor: const Color(0xff3AF500),
                      activeTrackColor: Colors.green[900],
                      inactiveThumbColor: Colors.redAccent,
                      inactiveTrackColor: Colors.red[900],
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh_rounded, color: Colors.white70, size: 18),
                      tooltip: 'Actualizar radar',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                      onPressed: () async {
                        await _preCargarDatosIniciales();
                        _construirStreams();
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
                      marcadores.add(
                        Marker(
                          point: const LatLng(7.863439, -72.475760),
                          width: 40,
                          height: 40,
                          child: const Icon(
                            Icons.location_on,
                            color: Colors.blue,
                            size: 40,
                          ),
                        ),
                      );
                      marcadores.add(
                        Marker(
                          point: const LatLng(7.863283, -72.476152),
                          width: 40,
                          height: 40,
                          child: const Icon(
                            Icons.location_on,
                            color: Colors.indigo,
                            size: 40,
                          ),
                        ),
                      );
                      marcadores.add(
                        Marker(
                          point: const LatLng(7.863976, -72.479256),
                          width: 40,
                          height: 40,
                          child: const Icon(
                            Icons.location_on,
                            color: Colors.purple,
                            size: 40,
                          ),
                        ),
                      );

                      if (snapMoviles.hasData) {
                        for (var m in snapMoviles.data!) {
                          if (m['en_linea'] == true &&
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
                      return ClipRRect(
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
                      );
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

                final problemas = todos
                    .where((s) => s['estado'] == 'problema')
                    .toList();
                final cotizaciones = todos
                    .where((s) => s['estado'] == 'cotizacion')
                    .toList();
                final cotizadas = todos
                    .where((s) => s['estado'] == 'cotizada')
                    .toList();
                final cotizacionesAprobadas = todos
                    .where((s) => s['estado'] == 'cotizacion_aprobada')
                    .toList();
                final finalizadosDemora = todos
                    .where((s) => s['estado'] == 'finalizado_por_demora')
                    .toList();
                final libres = todos
                    .where((s) => s['estado'] == 'pendiente')
                    .toList();
                // ---> INYECCIÓN: EXTRAER LOS PROGRAMADOS <---
                final programados = todos
                    .where((s) => s['estado'] == 'programado')
                    .toList();
                final enCurso = todos
                    .where(
                      (s) => [
                        'en_ruta_origen',
                        'en_origen',
                        'en_ruta_destino',
                      ].contains(s['estado']),
                    )
                    .toList();
                final finalizadosProblema = todos
                    .where((s) => s['estado'] == 'finalizado_con_problema')
                    .toList();
                final finalizados = todos
                    .where((s) => s['estado'] == 'finalizado')
                    .toList();
                final cancelados = todos
                    .where((s) => s['estado'] == 'cancelado')
                    .toList();
                final caducados = todos
                    .where((s) => s['estado'] == 'caducado')
                    .toList();

                // Sonidos de estado manejados por radar_central_bg channel

                // ValueListenableBuilder reacciona al filtro/búsqueda sin
                // reconstruir el StreamBuilder completo (evita parpadeo).
                return ValueListenableBuilder<int>(
                  valueListenable: _filtroVersion,
                  builder: (context, _, __) {
                    // ── FILTRO POR BÚSQUEDA ────────────────────────────────
                    bool _matchBusqueda(Map<String, dynamic> s) {
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
                        (m) => m['id'] == s['movil_id'], orElse: () => {});
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
                        lista.where(_matchBusqueda).toList();

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
                              _construirBloqueServicios(
                                context,
                                '♻️ SERVICIOS CADUCADOS',
                                _filtrar(caducados),
                                Colors.purple[800]!,
                                Icons.hourglass_disabled,
                                visible: !_seccionesOcultasMonitor.contains('caducados'),
                              ),
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
}
