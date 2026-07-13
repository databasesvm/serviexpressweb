// ignore_for_file: use_build_context_synchronously, invalid_use_of_protected_member
part of 'central_screen.dart';

extension CentralScreenPanico on _CentralScreenState {

  Future<void> _ejecutarLimpiezaDeCaducados() async {
    // FIX #8: antes hacía SELECT de todos los pendientes + 1 UPDATE por cada uno
    // (potencialmente 50+ queries cada 30 seg). Ahora son exactamente 2 UPDATEs
    // con filtro server-side — Supabase hace el trabajo, no el dispositivo.
    try {
      final corte60min = DateTime.now()
          .toUtc()
          .subtract(const Duration(minutes: 60))
          .toIso8601String();

      final corte30min = DateTime.now()
          .toUtc()
          .subtract(const Duration(minutes: 30))
          .toIso8601String();

      // 1 query: caducar TODOS los pendientes con más de 60 min de vida
      await Supabase.instance.client
          .from('servicios')
          .update({
            'estado': 'caducado',
            'observacion':
                'SISTEMA: Caducado por 60 min sin atención en el radar.',
          })
          .eq('estado', 'pendiente')
          .lt('created_at', corte60min);

      // 1 query: caducar TODAS las cotizaciones sin respuesta en 30 min
      await Supabase.instance.client
          .from('servicios')
          .update({
            'estado': 'caducado',
            'observacion':
                'SISTEMA: Cotización expirada. El cliente no respondió en 30 minutos.',
          })
          .eq('estado', 'cotizada')
          .lt('created_at', corte30min);
    } catch (e) {
      debugPrint('Error en limpieza de caducados: $e');
    }
  }

  // Detecta servicios activos con +30 min y suena UNA sola vez por servicio.
  // Se llama desde el timer cada 5 minutos.
  Future<void> _detectarDemorasYSonar() async {
    try {
      final corte = DateTime.now()
          .toUtc()
          .subtract(const Duration(minutes: 30))
          .toIso8601String();

      final demorados = await Supabase.instance.client
          .from('servicios')
          .select('id')
          .inFilter('estado', [
            'en_ruta_origen',
            'en_origen',
            'en_ruta_destino',
            'problema',
          ])
          .lt('updated_at', corte);

      bool sonoEnEsteCiclo = false;
      for (var s in demorados) {
        final int id = s['id'] as int;
        if (!_demorasAlertadas.contains(id)) {
          _demorasAlertadas.add(id);
          if (!sonoEnEsteCiclo) {
            // Una sola alarma por ciclo aunque haya varios demorados
            _sonidos.reproducir(Sonidos.centralDemora);
            sonoEnEsteCiclo = true;
          }
        }
      }
    } catch (e) {
      debugPrint('_detectarDemorasYSonar: $e');
    }
  }

  // =========================================================================
  // PÁNICO — Alerta de emergencia global e individual
  // =========================================================================

  void _mostrarPanicoOverlay({
    required String disparadoPor,
    String? usuarioDisparador,
    required String rolDisparador,
    int? eventoId,
    bool tieneUbicacion = false,
  }) {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.transparent,
      builder: (_) => PanicoOverlay(
        disparadoPor: disparadoPor,
        usuarioDisparador: usuarioDisparador,
        rolDisparador: rolDisparador,
        eventoId: eventoId,
        tieneUbicacion: tieneUbicacion,
      ),
    );
  }

  /// Convocatoria global con selector de destinatarios.
  /// [scope] = 'todos' | 'paradero'
  /// [paradero] = nombre del paradero cuando scope == 'paradero'
  /// [incluirDesconectados] = true para enviar también a usuarios desconectados
  Future<void> _dispararPanico({
    String scope = 'todos',
    String? paradero,
    bool incluirDesconectados = false,
  }) async {
    try {
      final yo = widget.usuario;
      if (yo == null) return;

      await Supabase.instance.client.from('eventos_panico').insert({
        'disparado_por_id': yo['id'],
        'disparado_por_nombre': yo['nombre'],
        'rol_disparador': yo['rol'] ?? 'central',
        'tipo': 'global',
      });

      // Construir query según scope
      List<dynamic> resultado;
      if (scope == 'paradero' && paradero != null) {
        // Solo móviles en ese paradero específico
        var q = Supabase.instance.client
            .from('usuarios')
            .select('id')
            .eq('paradero_actual', paradero)
            .neq('suspendido', true);
        if (!incluirDesconectados) q = q.eq('en_linea', true);
        resultado = await q;
      } else {
        // Todos: móviles, centrales y masters
        var q = Supabase.instance.client
            .from('usuarios')
            .select('id')
            .inFilter('rol', ['movil', 'central', 'master'])
            .neq('suspendido', true);
        if (!incluirDesconectados) q = q.eq('en_linea', true);
        resultado = await q;
      }

      final ids = resultado
          .map((u) => u['id'].toString())
          .where((id) => id != yo['id'].toString())
          .toList();

      if (ids.isNotEmpty) {
        final subtitulo = scope == 'paradero' && paradero != null
            ? 'Paradero $paradero — Central requiere tu atención.'
            : 'Central requiere tu atención URGENTE. Abre la app de inmediato.';
        await MotorNotificaciones.dispararRafa(
          idsDestinos: ids,
          titulo: '📢 LA CENTRAL TE SOLICITA',
          mensaje: subtitulo,
          urgente: true,
          sonido: Sonidos.panico,
          canalAndroidId: 'serviexpress_panico_v1',
        );
      }

      // Marcar convocatoria activa para mostrar botón Detener
      if (mounted) setState(() => _convocatoriaGlobalActiva = true);

      // Auto-detención: máximo 2 minutos si nadie lo cierra manualmente
      _timerExpiracionGlobal?.cancel();
      _timerExpiracionGlobal = Timer(const Duration(minutes: 2), () {
        if (mounted) {
          setState(() => _convocatoriaGlobalActiva = false);
          _detenerAlerta(tipo: 'global');
        }
      });

      // Confirmación discreta — solo para quien disparó
      if (mounted) mostrarConfirmacionDiscreta(context);
    } catch (e) {
      debugPrint('_dispararPanico: $e');
    }
  }

  /// Abre el diálogo selector de destinatarios para la convocatoria.
  // ignore: unused_element
  void _mostrarDialogoConvocatoria() {
    String scope = 'todos';
    String? paraderoSel;
    Map<String, dynamic>? movilSel;
    bool incluirDesconectados = false;
    const paraderos = ['EXPUENTE', 'MEMOS', 'NOCTURNO', 'BASE CASA'];

    // Carga lista de móviles una sola vez al abrir el diálogo
    final futureMoviles = Supabase.instance.client
        .from('usuarios')
        .select('id, nombre, usuario, en_linea, paradero_actual')
        .eq('rol', 'movil')
        .neq('suspendido', true)
        .order('nombre');

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          backgroundColor: Colors.grey[900],
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: const Row(
            children: [
              Icon(Icons.campaign_rounded, color: Colors.orange, size: 22),
              SizedBox(width: 8),
              Text(
                'CONVOCATORIA',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Si hay convocatoria activa, mostrar opción de detener primero
                if (_convocatoriaGlobalActiva) ...[
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red[800],
                      minimumSize: const Size(double.infinity, 42),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.stop_circle_rounded,
                        color: Colors.white, size: 18),
                    label: const Text('DETENER CONVOCATORIA ACTIVA',
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold)),
                    onPressed: () {
                      Navigator.pop(ctx);
                      setState(() => _convocatoriaGlobalActiva = false);
                      _detenerAlerta(tipo: 'global');
                    },
                  ),
                  const SizedBox(height: 16),
                  const Divider(color: Colors.white24),
                  const SizedBox(height: 12),
                ],
                // Selector de scope
                const Text('Enviar a:',
                    style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _chipScope(
                      label: 'Todos',
                      icon: Icons.groups_rounded,
                      selected: scope == 'todos',
                      onTap: () => setDlg(() {
                        scope = 'todos';
                        paraderoSel = null;
                        movilSel = null;
                      }),
                    ),
                    _chipScope(
                      label: 'Paradero',
                      icon: Icons.place_rounded,
                      selected: scope == 'paradero',
                      onTap: () => setDlg(() {
                        scope = 'paradero';
                        paraderoSel ??= paraderos.first;
                        movilSel = null;
                      }),
                    ),
                    _chipScope(
                      label: 'Individual',
                      icon: Icons.person_pin_rounded,
                      selected: scope == 'individual',
                      onTap: () => setDlg(() {
                        scope = 'individual';
                        paraderoSel = null;
                      }),
                    ),
                  ],
                ),
                // Sub-selector de paradero
                if (scope == 'paradero') ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: paraderos.map((p) {
                      final sel = paraderoSel == p;
                      return GestureDetector(
                        onTap: () => setDlg(() => paraderoSel = p),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: sel ? Colors.orange : Colors.white10,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: sel ? Colors.orange : Colors.white24),
                          ),
                          child: Text(
                            p,
                            style: TextStyle(
                              color: sel ? Colors.black : Colors.white70,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
                // Sub-selector individual: lista de móviles
                if (scope == 'individual') ...[
                  const SizedBox(height: 12),
                  FutureBuilder<List<dynamic>>(
                    future: futureMoviles,
                    builder: (ctx, snap) {
                      if (!snap.hasData) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(12),
                            child: CircularProgressIndicator(
                              color: Colors.orange,
                              strokeWidth: 2,
                            ),
                          ),
                        );
                      }
                      final lista = List<Map<String, dynamic>>.from(snap.data!);
                      if (lista.isEmpty) {
                        return const Text('Sin móviles disponibles.',
                            style: TextStyle(color: Colors.white54, fontSize: 13));
                      }
                      return ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 200),
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: lista.length,
                          itemBuilder: (c, i) {
                            final m = lista[i];
                            final enLinea = m['en_linea'] == true;
                            final seleccionado =
                                movilSel?['id'] == m['id'];
                            return InkWell(
                              onTap: () => setDlg(() => movilSel = m),
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                margin:
                                    const EdgeInsets.symmetric(vertical: 2),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 7),
                                decoration: BoxDecoration(
                                  color: seleccionado
                                      ? Colors.orange.withValues(alpha: 0.18)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: seleccionado
                                        ? Colors.orange
                                        : Colors.white12,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      enLinea
                                          ? Icons.circle
                                          : Icons.circle_outlined,
                                      size: 8,
                                      color: enLinea
                                          ? Colors.greenAccent
                                          : Colors.white30,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        m['nombre'] ?? '—',
                                        style: TextStyle(
                                          color: seleccionado
                                              ? Colors.orange
                                              : Colors.white70,
                                          fontSize: 13,
                                          fontWeight: seleccionado
                                              ? FontWeight.bold
                                              : FontWeight.normal,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      m['usuario'] ?? '',
                                      style: const TextStyle(
                                          color: Colors.white38, fontSize: 11),
                                    ),
                                    if (seleccionado) ...[
                                      const SizedBox(width: 6),
                                      const Icon(Icons.check_circle_rounded,
                                          color: Colors.orange, size: 16),
                                    ],
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
                ],
                // Toggle desconectados — no aplica para individual
                if (scope != 'individual') ...[
                  const SizedBox(height: 16),
                  GestureDetector(
                    onTap: () => setDlg(
                        () => incluirDesconectados = !incluirDesconectados),
                    child: Row(
                      children: [
                        Icon(
                          incluirDesconectados
                              ? Icons.check_box_rounded
                              : Icons.check_box_outline_blank_rounded,
                          color: incluirDesconectados
                              ? Colors.orange
                              : Colors.white38,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Incluir desconectados',
                          style:
                              TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('CANCELAR',
                  style: TextStyle(color: Colors.white38)),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              icon: const Icon(Icons.campaign_rounded,
                  color: Colors.black, size: 18),
              label: const Text('CONVOCAR',
                  style: TextStyle(
                      color: Colors.black, fontWeight: FontWeight.bold)),
              onPressed: (scope == 'paradero' && paraderoSel == null) ||
                      (scope == 'individual' && movilSel == null)
                  ? null
                  : () {
                      Navigator.pop(ctx);
                      if (scope == 'individual') {
                        _dispararPanicoIndividual(movilSel!);
                      } else {
                        _dispararPanico(
                          scope: scope,
                          paradero: paraderoSel,
                          incluirDesconectados: incluirDesconectados,
                        );
                      }
                    },
            ),
          ],
        ),
      ),
    );
  }

  /// Chip de selección de scope para el diálogo de convocatoria.
  Widget _chipScope({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? Colors.orange : Colors.white10,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: selected ? Colors.orange : Colors.white24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 14,
                color: selected ? Colors.black : Colors.white54),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.black : Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _dispararPanicoIndividual(Map<String, dynamic> movil) async {
    try {
      final yo = widget.usuario;
      if (yo == null) return;

      await Supabase.instance.client.from('eventos_panico').insert({
        'disparado_por_id': yo['id'],
        'disparado_por_nombre': yo['nombre'],
        'rol_disparador': yo['rol'] ?? 'central',
        'tipo': 'individual',
        'destino_id': movil['id'],
        'destino_nombre': movil['nombre'],
      });

      await MotorNotificaciones.dispararMisil(
        idDestino: movil['id'].toString(),
        titulo: '🚨 CENTRAL REQUIERE TU ATENCIÓN',
        mensaje:
            'La Central ha enviado una alerta urgente. Responde de inmediato.',
        urgente: true,
        sonido: Sonidos.panico,
        canalAndroidId: 'serviexpress_panico_v1',
      );

      // Auto-detención: máximo 2 minutos si nadie lo cierra manualmente
      _timerExpiracionIndividual?.cancel();
      _timerExpiracionIndividual = Timer(const Duration(minutes: 2), () {
        if (mounted) _detenerAlerta(tipo: 'individual', movilId: movil['id']);
      });

      // Confirmación discreta — solo para quien disparó
      if (mounted) mostrarConfirmacionDiscreta(context);
    } catch (e) {
      debugPrint('_dispararPanicoIndividual: $e');
    }
  }

  // ── LINK DE PEDIDO POR WHATSAPP ─────────────────────────────────────────
  /// Muestra un diálogo para capturar el número del cliente y abre WhatsApp
  /// con un mensaje que incluye el link de la app web para que el cliente
  /// haga su propio pedido como invitado.
  Future<void> _enviarLinkInvitado(BuildContext ctx) async {
    final telCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: ctx,
      builder: (dlgCtx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.share_rounded, color: Color(0xff25D366), size: 22),
            SizedBox(width: 10),
            Text(
              'Enviar link al cliente',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'El cliente recibirá un link por WhatsApp para hacer su pedido directamente como invitado.',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: telCtrl,
              keyboardType: TextInputType.phone,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Número WhatsApp del cliente',
                labelStyle: const TextStyle(color: Colors.white54),
                prefixText: '+57 ',
                prefixStyle: const TextStyle(color: Colors.white70),
                hintText: '3001234567',
                hintStyle: const TextStyle(color: Colors.white30),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Colors.white24),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xff25D366)),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dlgCtx, false),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xff25D366),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: const Icon(Icons.send_rounded, size: 18),
            label: const Text('Abrir WhatsApp'),
            onPressed: () => Navigator.pop(dlgCtx, true),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    telCtrl.dispose();

    final tel = telCtrl.text.trim().replaceAll(RegExp(r'\D'), '');
    if (tel.isEmpty) return;

    // Número colombiano: prefijo 57 si no empieza con +
    final numero = tel.startsWith('57') ? tel : '57$tel';
    final mensaje = Uri.encodeComponent(
      '¡Hola! 👋 Puedes hacer tu pedido de Serviexpress directamente desde aquí:\n'
      '$_kUrlApp\n\n'
      'Solo abre el link, elige el tipo de servicio y nosotros te atendemos. '
      '¡También puedes registrarte para guardar tus datos! 🛵',
    );
    final waUrl = Uri.parse('https://wa.me/$numero?text=$mensaje');

    if (await canLaunchUrl(waUrl)) {
      await launchUrl(waUrl, mode: LaunchMode.externalApplication);
    }
  }

  /// Detiene una alerta de pánico activa disparada por esta Central.
  /// [tipo] = 'global' o 'individual'. Para individual, [movilId] es el destino.
  Future<void> _detenerAlerta({
    required String tipo,
    dynamic movilId,
  }) async {
    try {
      final yo = widget.usuario;
      if (yo == null) return;

      // Cancelar timer de auto-expiración correspondiente
      if (tipo == 'global') {
        _timerExpiracionGlobal?.cancel();
        _timerExpiracionGlobal = null;
        if (mounted) setState(() => _convocatoriaGlobalActiva = false);
      } else {
        _timerExpiracionIndividual?.cancel();
        _timerExpiracionIndividual = null;
      }

      // Buscamos el evento más reciente activo de esta Central
      List<dynamic> rows;
      if (tipo == 'individual' && movilId != null) {
        rows = await Supabase.instance.client
            .from('eventos_panico')
            .select('id, ubicacion_expira_at')
            .eq('disparado_por_id', yo['id'])
            .eq('tipo', 'individual')
            .eq('destino_id', movilId)
            .order('created_at', ascending: false)
            .limit(5);
      } else {
        rows = await Supabase.instance.client
            .from('eventos_panico')
            .select('id, ubicacion_expira_at')
            .eq('disparado_por_id', yo['id'])
            .eq('tipo', 'global')
            .order('created_at', ascending: false)
            .limit(5);
      }

      // Filtramos: solo eventos aún activos
      // (ubicacion_expira_at nulo = nunca expirado, o aún en el futuro)
      Map<String, dynamic>? evento;
      for (final row in rows) {
        final expiraStr = row['ubicacion_expira_at']?.toString();
        if (expiraStr == null) {
          evento = row as Map<String, dynamic>;
          break;
        }
        final expira = DateTime.tryParse(expiraStr)?.toUtc();
        if (expira != null && DateTime.now().toUtc().isBefore(expira)) {
          evento = row as Map<String, dynamic>;
          break;
        }
      }

      if (evento == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No hay alerta activa para detener.')),
          );
        }
        return;
      }

      // Expirar el evento ahora → PanicoOverlay lo detecta y se cierra en todos
      final ahora = DateTime.now().toUtc().subtract(const Duration(seconds: 5));
      await Supabase.instance.client
          .from('eventos_panico')
          .update({'ubicacion_expira_at': ahora.toIso8601String()})
          .eq('id', evento['id']);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tipo == 'global'
                  ? '✅ Convocatoria general detenida.'
                  : '✅ Llamado individual detenido.',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('_detenerAlerta: $e');
    }
  }

  // FIX #7: antes calculaba su propio ranking consultando el campo `puntuacion`
  // de la tabla `usuarios` — una fuente de verdad distinta a RankingScreen.
  // Ahora navega directamente a RankingScreen, que es la única fuente de verdad.
  // Beneficio: cualquier mejora a la lógica de ranking aplica automáticamente aquí.
  void _mostrarRankingSemanalDialog(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RankingScreen()),
    );
  }

  void _mostrarPerfilHistorialCompleto(
    BuildContext context,
    String nombreMovil,
    List<Map<String, dynamic>> todoHistorial,
  ) {
    final completados = todoHistorial
        .where(
          (f) =>
              f['estado'] == 'finalizado' &&
              !(f['observacion'] ?? '').contains('[MARCA DE FALLA]'),
        )
        .length;
    final cancelados = todoHistorial
        .where((f) => f['estado'] == 'cancelado')
        .length;
    final demorados = todoHistorial
        .where((f) => f['estado'] == 'finalizado_por_demora')
        .length;
    final fallas = todoHistorial
        .where(
          (f) =>
              f['estado'] == 'finalizado_con_problema' ||
              (f['observacion'] ?? '').contains('[MARCA DE FALLA]'),
        )
        .length;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(
          'PERFIL DE OPERACIÓN | $nombreMovil',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  _bloqueMetrico('Completados', completados, Colors.green),
                  _bloqueMetrico('Cancelados', cancelados, Colors.black54),
                  _bloqueMetrico('Demorados', demorados, Colors.deepPurple),
                  _bloqueMetrico('Fallas', fallas, Colors.red[700]!),
                ],
              ),
              const SizedBox(height: 16),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'ÚLTIMOS SERVICIOS ASIGNADOS:',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                    color: Colors.black54,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              todoHistorial.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(20),
                      child: Text(
                        'Historial vacío.',
                        style: TextStyle(color: Colors.black38),
                      ),
                    )
                  : SizedBox(
                      height: 300,
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: todoHistorial.length,
                        itemBuilder: (context, index) {
                          final f = todoHistorial[index];
                          final est = f['estado'];
                          Color c = Colors.green;
                          String txt = 'FINALIZADO';
                          if (est == 'cancelado') {
                            c = Colors.black54;
                            txt = 'CANCELADO';
                          } else if (est == 'finalizado_por_demora') {
                            c = Colors.deepPurple;
                            txt = 'DEMORA';
                          } else if (est == 'finalizado_con_problema' ||
                              (f['observacion'] ?? '').contains(
                                '[MARCA DE FALLA]',
                              )) {
                            c = Colors.red[700]!;
                            txt = 'FALLA';
                          }

                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            elevation: 0.5,
                            child: ListTile(
                              dense: true,
                              title: Text(
                                'Orden #${f['id']} | ${f['origen']} ➔ ${f['destino']}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                              subtitle: Text(
                                f['observacion'] ??
                                    'Operación ordinaria sin notas.',
                                style: const TextStyle(fontSize: 11),
                              ),
                              trailing: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: c,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: Text(
                                  txt,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 8,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'CERRAR',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bloqueMetrico(String t, int v, Color c) {
    return Container(
      width: 100,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Text(
            t,
            style: TextStyle(
              fontSize: 9,
              color: c,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '$v',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: c,
            ),
          ),
        ],
      ),
    );
  }

}
