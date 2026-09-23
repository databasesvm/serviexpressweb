// ignore_for_file: use_build_context_synchronously, invalid_use_of_protected_member
part of 'central_screen.dart';

extension CentralScreenGestion on _CentralScreenState {

  void _abrirMenuAccionesMovil(BuildContext context, Map<String, dynamic> m) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        padding: const EdgeInsets.only(top: 12, bottom: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Manija visual de "deslizar para cerrar"
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 18),

            // CABECERA — identifica de un vistazo a quién le vas a actuar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: Colors.blue[800],
                    child: Text(
                      _extraerNumeroAvatar(m),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _formatearNombreCentral(m).toUpperCase(),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            if (m['ticket_prioridad'] == true) ...[
                              const Icon(
                                Icons.local_activity,
                                color: Colors.amber,
                                size: 13,
                              ),
                              const SizedBox(width: 4),
                            ],
                            Text(
                              '${m['rango_movil'] ?? 'NOVATO'} · ${_formatCalificacion(m['puntuacion'])}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Divider(height: 1),
            ),

            // OPCIONES REGULARES
            _opcionMenuAccion(
              icono: Icons.chat_bubble_rounded,
              color: Colors.blue,
              titulo: 'Chat directo',
              subtitulo: 'Enviar un mensaje privado a este móvil',
              onTap: () {
                Navigator.pop(ctx);
                _abrirChatDirectoMovil(m);
              },
            ),
            _opcionMenuAccion(
              icono: Icons.campaign_rounded,
              color: Colors.orange[800]!,
              titulo: 'Llamar urgente',
              subtitulo: 'Convocatoria individual — mantener presionado',
              onTap: () {
                Navigator.pop(ctx);
                showDialog(
                  context: context,
                  builder: (_) => PanicoConfirmDialog(
                    segundos: 1.5,
                    icono: Icons.campaign_rounded,
                    colorAcento: Colors.orange,
                    titulo: 'LLAMAR A ${_formatearNombreCentral(m)}',
                    descripcion:
                        'Se enviará una alerta urgente a este móvil. Úsalo '
                        'cuando necesites su atención de inmediato.',
                    onActivado: () => _dispararPanicoIndividual(m),
                  ),
                );
              },
            ),
            _opcionMenuAccion(
              icono: Icons.notifications_off_rounded,
              color: Colors.red[700]!,
              titulo: 'Detener llamado urgente',
              subtitulo: 'Cancela la alerta individual activa a este móvil',
              onTap: () {
                Navigator.pop(ctx);
                _detenerAlerta(tipo: 'individual', movilId: m['id']);
              },
            ),
            _opcionMenuAccion(
              icono: Icons.badge_rounded,
              color: Colors.teal,
              titulo: 'Ver perfil completo',
              subtitulo: 'Datos personales, contacto y pago',
              onTap: () {
                Navigator.pop(ctx);
                _verPerfilCompletoMovil(context, m);
              },
            ),
            _opcionMenuAccion(
              icono: Icons.bar_chart_rounded,
              color: Colors.indigo,
              titulo: 'Ver estadísticas',
              subtitulo: 'Historial y rendimiento completo',
              onTap: () {
                Navigator.pop(ctx);
                _abrirEstadisticasMovil(context, m);
              },
            ),

            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Divider(height: 1),
            ),

            // SUSPENDER / QUITAR SUSPENSIÓN — condicional según estado
            if (m['suspendido'] == true)
              _opcionMenuAccion(
                icono: Icons.restore_rounded,
                color: Colors.green[700]!,
                titulo: 'Quitar suspensión',
                subtitulo: 'Rehabilita el acceso de inmediato',
                onTap: () {
                  Navigator.pop(ctx);
                  _quitarSuspension(context, m, () {});
                },
              )
            else
              _opcionMenuAccion(
                icono: Icons.block_rounded,
                color: Colors.deepOrange,
                titulo: 'Suspender',
                subtitulo: 'Elegir por cuánto tiempo',
                onTap: () {
                  Navigator.pop(ctx);
                  _mostrarSelectorSuspension(context, m, () {});
                },
              ),

            // ACCIÓN DESTRUCTIVA — separada visualmente de las demás.
            // Solo aplica si el moto realmente está en una fila — no
            // tiene sentido mostrarlo para alguien En Servicio, Libre,
            // Suspendido o Desconectado que no está en ningún paradero.
            if (m['paradero_actual'] != null)
              _opcionMenuAccion(
                icono: Icons.person_remove_rounded,
                color: Colors.red[700]!,
                titulo: 'Expulsar de la fila',
                subtitulo: 'Sale del paradero — puede volver a registrarse',
                onTap: () {
                  Navigator.pop(ctx);
                  _expulsarDelParadero(m);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // Tile reutilizable para cada opción del menú — ícono en cápsula de
  // color, título + descripción corta, chevron indicando que es tocable.
  Widget _opcionMenuAccion({
    required IconData icono,
    required Color color,
    required String titulo,
    required String subtitulo,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icono, color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titulo,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitulo,
                    style: TextStyle(fontSize: 11.5, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // SUSPENSIÓN CON DURACIÓN — compartida entre el menú de Flota y el
  // de "CONTROL DE ACCESOS Y BAJAS". Un solo lugar, un solo comportamiento.
  // =========================================================================

  // Abre el selector de duración. alTerminar() se llama después de
  // ejecutar la suspensión, para que cada pantalla refresque a su modo
  // (el menú de Flota vive de un stream y se refresca solo; el otro
  // usa setStateDialog y necesita que se lo pidamos explícito).
  void _mostrarSelectorSuspension(
    BuildContext context,
    Map<String, dynamic> usuario,
    VoidCallback alTerminar,
  ) {
    showDialog(
      context: context,
      builder: (ctxDialog) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(
          'Suspender a ${_formatearNombreCentral(usuario)}',
          style: const TextStyle(fontSize: 16),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '¿Por cuánto tiempo? Se desconecta y sale de cualquier '
              'fila de inmediato.',
              style: TextStyle(fontSize: 13, color: Colors.black54),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _chipDuracionSuspension(ctxDialog, usuario, alTerminar,
                    '15 min', const Duration(minutes: 15)),
                _chipDuracionSuspension(ctxDialog, usuario, alTerminar,
                    '30 min', const Duration(minutes: 30)),
                _chipDuracionSuspension(ctxDialog, usuario, alTerminar,
                    '1 hora', const Duration(hours: 1)),
                _chipDuracionSuspension(ctxDialog, usuario, alTerminar,
                    '2 horas', const Duration(hours: 2)),
                _chipDuracionSuspension(ctxDialog, usuario, alTerminar,
                    '6 horas', const Duration(hours: 6)),
                _chipDuracionSuspension(ctxDialog, usuario, alTerminar,
                    '12 horas', const Duration(hours: 12)),
                _chipDuracionSuspension(ctxDialog, usuario, alTerminar,
                    '1 día', const Duration(days: 1)),
                _chipDuracionSuspension(ctxDialog, usuario, alTerminar,
                    '2 días', const Duration(days: 2)),
                _chipDuracionSuspension(ctxDialog, usuario, alTerminar,
                    '3 días', const Duration(days: 3)),
                _chipDuracionSuspension(ctxDialog, usuario, alTerminar,
                    '1 semana', const Duration(days: 7)),
                _chipDuracionSuspension(ctxDialog, usuario, alTerminar,
                    '2 semanas', const Duration(days: 14)),
                _chipDuracionSuspension(ctxDialog, usuario, alTerminar,
                    'Indefinido', null),
                // Chip para duración manual
                ActionChip(
                  label: const Text('Manual…',
                      style: TextStyle(fontSize: 12)),
                  backgroundColor: Colors.blue[50],
                  labelStyle: TextStyle(
                    color: Colors.blue[800],
                    fontWeight: FontWeight.bold,
                  ),
                  onPressed: () {
                    Navigator.pop(ctxDialog);
                    _mostrarSuspensionManual(context, usuario, alTerminar);
                  },
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctxDialog),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
  }

  // --- SUSPENSIÓN MANUAL: el operador escribe horas y minutos libres ---
  void _mostrarSuspensionManual(
    BuildContext context,
    Map<String, dynamic> usuario,
    VoidCallback alTerminar,
  ) {
    final horasCtrl = TextEditingController(text: '0');
    final minutosCtrl = TextEditingController(text: '30');

    showDialog(
      context: context,
      builder: (ctxM) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text('Duración manual — ${_formatearNombreCentral(usuario)}',
            style: const TextStyle(fontSize: 15)),
        content: Row(
          children: [
            Expanded(
              child: TextField(
                controller: horasCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Horas',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: minutosCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Minutos',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctxM),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange[700]),
            onPressed: () {
              final int horas = int.tryParse(horasCtrl.text) ?? 0;
              final int minutos = int.tryParse(minutosCtrl.text) ?? 0;
              final total = horas * 60 + minutos;
              if (total <= 0) return;
              Navigator.pop(ctxM);
              _ejecutarSuspension(
                context,
                usuario,
                Duration(minutes: total),
                'Manual ${horas}h ${minutos}min',
                alTerminar,
              );
            },
            child: const Text('Suspender',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _chipDuracionSuspension(
    BuildContext ctxDialog,
    Map<String, dynamic> usuario,
    VoidCallback alTerminar,
    String etiqueta,
    Duration? duracion,
  ) {
    final bool esIndefinido = duracion == null;
    return ActionChip(
      label: Text(etiqueta, style: const TextStyle(fontSize: 12)),
      backgroundColor: esIndefinido ? Colors.red[50] : Colors.orange[50],
      labelStyle: TextStyle(
        color: esIndefinido ? Colors.red[800] : Colors.orange[800],
        fontWeight: FontWeight.bold,
      ),
      side: BorderSide(
        color: esIndefinido ? Colors.red[200]! : Colors.orange[200]!,
      ),
      onPressed: () => _ejecutarSuspension(
        ctxDialog,
        usuario,
        duracion,
        etiqueta,
        alTerminar,
      ),
    );
  }

  Future<void> _ejecutarSuspension(
    BuildContext ctxDialog,
    Map<String, dynamic> usuario,
    Duration? duracion,
    String etiqueta,
    VoidCallback alTerminar,
  ) async {
    final DateTime? hasta = duracion == null
        ? null
        : DateTime.now().toUtc().add(duracion);

    try {
      await Supabase.instance.client
          .from('usuarios')
          .update({
            'suspendido': true,
            'suspendido_hasta': hasta?.toIso8601String(),
            'en_linea': false,
            'paradero_actual': null,
            'ingreso_fila': null,
          })
          .eq('id', usuario['id']);

      if (ctxDialog.mounted) Navigator.pop(ctxDialog);
      alTerminar();

      // Push al suspendido — llega aunque la app esté en segundo plano
      final msgSuspension = duracion == null
          ? '🛑 Tu acceso fue suspendido indefinidamente por la Central. Comunícate con ellos para más información.'
          : '🛑 Tu acceso fue suspendido por $etiqueta. Espera que la Central lo reactive.';
      await MotorNotificaciones.dispararMisil(
        idDestino: usuario['id'].toString(),
        titulo: '🛑 ACCESO SUSPENDIDO',
        mensaje: msgSuspension,
        urgente: true,
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              duracion == null
                  ? '🛑 ${_formatearNombreCentral(usuario)} suspendido indefinidamente.'
                  : '🛑 ${_formatearNombreCentral(usuario)} suspendido por $etiqueta.',
            ),
            backgroundColor: Colors.orange[800],
          ),
        );
      }
    } catch (e) {
      if (ctxDialog.mounted) {
        ScaffoldMessenger.of(ctxDialog).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // Quita la suspensión — visible inline en ambos menús cuando el
  // usuario ya está suspendido, sin tener que ir a otra pantalla.
  Future<void> _quitarSuspension(
    BuildContext context,
    Map<String, dynamic> usuario,
    VoidCallback alTerminar,
  ) async {
    try {
      await Supabase.instance.client
          .from('usuarios')
          .update({'suspendido': false, 'suspendido_hasta': null})
          .eq('id', usuario['id']);

      alTerminar();

      // Push al rehabilitado — llega aunque la app esté en segundo plano
      await MotorNotificaciones.dispararMisil(
        idDestino: usuario['id'].toString(),
        titulo: '✅ SUSPENSIÓN LEVANTADA',
        mensaje: 'La Central restauró tu acceso. Ya puedes conectarte y volver a recibir servicios con normalidad.',
        urgente: true,
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ ${_formatearNombreCentral(usuario)} fue rehabilitado.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _expulsarDelParadero(Map<String, dynamic> movil) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Expulsar del paradero'),
        content: Text(
          '¿Sacar a ${_formatearNombreCentral(movil)} de la fila?\n\n'
          'Sigue en línea — puede volver a registrarse cuando quiera.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red[800]),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'EXPULSAR',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    try {
      await Supabase.instance.client
          .from('usuarios')
          .update({'paradero_actual': null, 'ingreso_fila': null})
          .eq('id', movil['id']);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${_formatearNombreCentral(movil)} fue sacado de la fila.'),
            backgroundColor: Colors.black,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // Vacía TODA la fila de un paradero de un golpe — útil al cerrar
  // turno, reorganizar, o limpiar fantasmas acumulados.
  Future<void> _vaciarParadero(
    String nombreParadero,
    List<Map<String, dynamic>> fila,
  ) async {
    if (fila.isEmpty) return;

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text('Vaciar $nombreParadero'),
        content: Text(
          '¿Sacar a los ${fila.length} móviles de esta fila?\n\n'
          'Todos siguen en línea — pueden volver a registrarse cuando quieran.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red[800]),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'VACIAR FILA',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    try {
      final ids = fila.map((m) => m['id']).toList();
      await Supabase.instance.client
          .from('usuarios')
          .update({'paradero_actual': null, 'ingreso_fila': null})
          .inFilter('id', ids);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '$nombreParadero vaciado — ${fila.length} móviles fuera de la fila.',
            ),
            backgroundColor: Colors.black,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _abrirConfigRecargosLocal(Map<String, dynamic> local) {
    final TextEditingController recargoController = TextEditingController(
      text: local['recargo_nocturno_especial'] != null
          ? local['recargo_nocturno_especial'].toString()
          : '',
    );
    String zonaSeleccionada =
        local['zona_lluvia']?.toString() ?? 'general';
    bool usaDefault = local['recargo_nocturno_especial'] == null;

    showDialog(
      context: context,
      builder: (ctxDialog) => StatefulBuilder(
        builder: (ctxDialog, setDialogState) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.tune, color: Colors.orange),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  local['nombre'].toString().toUpperCase(),
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // --- RECARGO NOCTURNO ESPECIAL ---
                const Text(
                  'Recargo nocturno',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 4),
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: usaDefault,
                  title: const Text(
                    'Usar el default del sistema (\$2.000)',
                    style: TextStyle(fontSize: 12),
                  ),
                  onChanged: (val) {
                    setDialogState(() {
                      usaDefault = val ?? true;
                      if (usaDefault) recargoController.clear();
                    });
                  },
                ),
                if (!usaDefault)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 8),
                    child: TextField(
                      controller: recargoController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Recargo especial (\$)',
                        hintText: 'Ej: 1000',
                        border: OutlineInputBorder(),
                        isDense: true,
                        prefixIcon: Icon(Icons.attach_money, size: 18),
                      ),
                    ),
                  ),

                const SizedBox(height: 16),

                // --- ZONA DE LLUVIA ---
                const Text(
                  'Zona de lluvia',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 4),
                Text(
                  'Define qué zona debe estar lloviendo para que este local reciba el recargo.',
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  initialValue: zonaSeleccionada,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'general',
                      child: Text('General (Cúcuta y alrededores)', style: TextStyle(fontSize: 12)),
                    ),
                    DropdownMenuItem(
                      value: 'trapiches',
                      child: Text('Solo Trapiches', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setDialogState(() => zonaSeleccionada = val);
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctxDialog),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.black),
              onPressed: () async {
                final int? recargoFinal = usaDefault
                    ? null
                    : int.tryParse(recargoController.text.trim());

                try {
                  await Supabase.instance.client
                      .from('usuarios')
                      .update({
                        'recargo_nocturno_especial': recargoFinal,
                        'zona_lluvia': zonaSeleccionada,
                      })
                      .eq('id', local['id']);

                  if (ctxDialog.mounted) {
                    Navigator.pop(ctxDialog);
                    Navigator.pop(context);
                    _abrirGestorParaderos(); // recarga con los nuevos datos
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Recargos de ${local['nombre']} actualizados',
                        ),
                        backgroundColor: Colors.black,
                      ),
                    );
                  }
                } catch (e) {
                  if (ctxDialog.mounted) {
                    ScaffoldMessenger.of(ctxDialog).showSnackBar(
                      SnackBar(
                        content: Text('Error: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              child: const Text(
                'Guardar',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // MENÚ DE FILTRO DEL MONITOR — qué secciones se muestran
  // =========================================================================
  // =========================================================================
  // PANEL DE GESTIÓN — Onboarding, Ascensos, Paraderos, Ranking y Corte
  // Financiero, agrupados en una sola pantalla aparte. Antes vivían
  // sueltos en el AppBar (10 acciones distintas ahí) — ahora el AppBar
  // solo tiene lo que debe estar siempre a mano sin importar la
  // pestaña, y esto se abre como su propia pantalla.
  // =========================================================================
  Future<void> _abrirGestionUsuarios(BuildContext context, {int tabInicial = 0}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => _PanelGestionUsuarios(tabInicial: tabInicial)),
    );
  }

  // ── Avatar de moto en paradero — color índigo identifica FN conectado ────────
  Widget _paraderoMovilLeading(Map<String, dynamic> m, Color colorBase) {
    final esFn = m['tiene_fn'] == true;
    final enLinea = m['en_linea'] == true;
    return CircleAvatar(
      radius: 12,
      backgroundColor: (esFn && enLinea) ? const Color(0xFF002DA2) : colorBase,
      child: Text(
        _extraerNumeroAvatar(m),
        style: const TextStyle(
            color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }

  // ── Ping helper — estado de conexión real basado en ultimo_ping ────────────
  String _pingLabel(Map<String, dynamic> m) {
    if (m['ultimo_ping'] == null) return '○ sin ping';
    final mins = DateTime.now()
        .toUtc()
        .difference(DateTime.parse(m['ultimo_ping'].toString()).toUtc())
        .inMinutes;
    if (mins < 2) return '● ahora';
    if (mins < 5) return '● hace ${mins}min';
    if (mins < 60) return '○ hace ${mins}min';
    return '○ offline';
  }

  Widget _subtituloMovilFlota(Map<String, dynamic> m) {
    final ping = _pingLabel(m);
    final online = ping.startsWith('●');
    final mins = _minutosHoyMoviles[m['id'] as int? ?? -1] ?? 0;
    final h = mins ~/ 60;
    final min = mins % 60;
    final horasSuffix = mins == 0
        ? ''
        : ' · ${h > 0 ? '${h}h ${min.toString().padLeft(2, '0')}m' : '${min}m'}';

    // Etiqueta de plan
    final plan = m['tipo_plan']?.toString();
    Widget? planChip;
    if (plan == 'prediario') {
      planChip = Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(color: Colors.orange[700], borderRadius: BorderRadius.circular(3)),
        child: const Text('PREDIA', style: TextStyle(color: Colors.white, fontSize: 7, fontWeight: FontWeight.bold)),
      );
    } else if (plan == 'suscripcion') {
      planChip = Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(color: Colors.green[700], borderRadius: BorderRadius.circular(3)),
        child: const Text('SUSCR', style: TextStyle(color: Colors.white, fontSize: 7, fontWeight: FontWeight.bold)),
      );
    }

    return Row(
      children: [
        if (m['ticket_prioridad'] == true) ...[
          const Icon(Icons.local_activity, color: Colors.amber, size: 12),
          const SizedBox(width: 4),
        ],
        if (planChip != null) ...[planChip, const SizedBox(width: 5)],
        Text(
          '${m['rango_movil'] ?? 'NOVATO'} | ${_formatCalificacion(m['puntuacion'])}',
          style: const TextStyle(
              fontSize: 10, color: Colors.black54, fontWeight: FontWeight.w500),
        ),
        const SizedBox(width: 6),
        Text(
          '$ping$horasSuffix',
          style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: online ? Colors.green[700] : Colors.grey[400]),
        ),
      ],
    );
  }

  // ── Trailing estándar — muestra badge FN pill + ícono de menú ────────────
  Widget _movilTrailing(Map<String, dynamic> m) {
    final esFn = m['tiene_fn'] == true;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (esFn)
          Container(
            margin: const EdgeInsets.only(right: 6),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFF002DA2),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.local_pharmacy, size: 8, color: Colors.white),
                SizedBox(width: 3),
                Text(
                  'FN',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
          ),
        const Icon(Icons.more_vert, color: Colors.black38),
      ],
    );
  }

  Widget _tarjetaGestionConBadge({
    required IconData icono,
    required Color color,
    required String titulo,
    required String subtitulo,
    required VoidCallback onTap,
    int badge = 0,
  }) {
    return Stack(
      children: [
        _tarjetaGestion(
          icono: icono,
          color: color,
          titulo: titulo,
          subtitulo: subtitulo,
          onTap: onTap,
        ),
        if (badge > 0)
          Positioned(
            top: 8, right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.red[600],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '$badge',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold),
              ),
            ),
          ),
      ],
    );
  }

  void _abrirPanelGestion(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          backgroundColor: const Color(0xFF0A0A0A),
          body: CustomScrollView(
            slivers: [
              SliverAppBar(
                backgroundColor: Colors.black,
                iconTheme: const IconThemeData(color: Colors.white),
                pinned: true,
                expandedHeight: 130,
                flexibleSpace: const FlexibleSpaceBar(
                  title: Text(
                    'Gestión',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  centerTitle: false,
                  titlePadding: EdgeInsets.only(left: 56, bottom: 16),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([

                    // ── USUARIOS ────────────────────────────────────────────
                    _seccionGestion('USUARIOS'),
                    _tarjetaGestionConBadge(
                      icono: Icons.manage_accounts_rounded,
                      color: Colors.blue[600]!,
                      titulo: 'Gestión de Usuarios',
                      subtitulo: 'Solicitudes, activaciones, ascensos y registros',
                      badge: _usuariosPendientes,
                      onTap: () => _abrirGestionUsuarios(
                        context,
                        tabInicial: _usuariosPendientes > 0 ? 1 : 0,
                      ),
                    ),
                    _tarjetaGestion(
                      icono: Icons.emoji_events,
                      color: Colors.amber[800]!,
                      titulo: 'Ranking Semanal',
                      subtitulo: 'Desempeño de la flota',
                      onTap: () => _mostrarRankingSemanalDialog(context),
                    ),

                    // ── OPERACIONES ─────────────────────────────────────────
                    _seccionGestion('OPERACIONES'),
                    _tarjetaGestion(
                      icono: Icons.storefront,
                      color: Colors.teal[700]!,
                      titulo: 'Gestor de Paraderos',
                      subtitulo: 'Zonas, horarios y filas',
                      onTap: _abrirGestorParaderos,
                    ),
                    _tarjetaGestion(
                      icono: Icons.delivery_dining,
                      color: const Color(0xff3AF500),
                      titulo: 'Monitor Domicilios',
                      subtitulo: 'Pedidos activos, estados y domicilios por local',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => MonitorPedidosScreen(usuario: widget.usuario!),
                        ),
                      ),
                    ),
                    _tarjetaGestion(
                      icono: Icons.history_rounded,
                      color: Colors.blueGrey[600]!,
                      titulo: 'Historial de Servicios',
                      subtitulo: 'Búsqueda y consulta de servicios pasados',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const HistorialServiciosScreen(),
                        ),
                      ),
                    ),
                    _tarjetaGestionConBadge(
                      icono: Icons.flag_outlined,
                      color: Colors.orange[700]!,
                      titulo: 'Reportes y Quejas',
                      subtitulo: _reportesSinLeer > 0
                          ? '$_reportesSinLeer sin leer — quejas de clientes y sedes'
                          : 'Quejas de clientes y sedes activas',
                      badge: _reportesSinLeer,
                      onTap: () => _abrirPanelReportes(context),
                    ),

                    // ── ADMINISTRACIÓN ──────────────────────────────────────
                    _seccionGestion('ADMINISTRACIÓN'),
                    _tarjetaGestion(
                      icono: Icons.map_outlined,
                      color: Colors.indigo[600]!,
                      titulo: 'Red & Sectores',
                      subtitulo: 'Direcciones, barrios y precios globales',
                      onTap: () => _abrirGestorRedYSectores(context),
                    ),
                    _tarjetaGestion(
                      icono: Icons.bar_chart_rounded,
                      color: Colors.green[700]!,
                      titulo: 'Corte Financiero',
                      subtitulo: 'Reporte de ingresos y comisiones',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const ReporteFinancieroScreen(),
                        ),
                      ),
                    ),
                    _tarjetaGestion(
                      icono: Icons.local_pharmacy,
                      color: const Color(0xFF002da2),
                      titulo: 'Farmanorte FN',
                      subtitulo: 'Sedes, motos FN e ignorados del día',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const FnPanelScreen(),
                        ),
                      ),
                    ),

                    // ── CONFIGURACIÓN ───────────────────────────────────────
                    _seccionGestion('CONFIGURACIÓN'),
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF141414),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: _bloqueoInactividadActivo
                              ? Colors.orange.withValues(alpha: 0.5)
                              : Colors.white12,
                        ),
                      ),
                      child: SwitchListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        secondary: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: (_bloqueoInactividadActivo ? Colors.orange : Colors.white24).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.lock_clock,
                            color: _bloqueoInactividadActivo ? Colors.orange : Colors.white38,
                            size: 22,
                          ),
                        ),
                        title: const Text(
                          'Bloqueo automático por inactividad',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        subtitle: Text(
                          _bloqueoInactividadActivo
                              ? '🔴 Activo — el cron bloqueará y eliminará móviles inactivos'
                              : '⚪ Desactivado — el cron corre pero no toma acciones',
                          style: TextStyle(
                            color: _bloqueoInactividadActivo ? Colors.orange[300] : Colors.white38,
                            fontSize: 11,
                          ),
                        ),
                        value: _bloqueoInactividadActivo,
                        activeColor: Colors.orange,
                        onChanged: (val) async {
                          final confirmado = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              backgroundColor: const Color(0xFF1A1A1A),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              title: Text(
                                val ? '⚠️ Activar bloqueo automático' : '⚪ Desactivar bloqueo automático',
                                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                              ),
                              content: Text(
                                val
                                    ? 'El cron diario comenzará a bloquear móviles con 3+ días sin actividad y a eliminar cuentas según el plan. ¿Confirmar?'
                                    : 'El cron seguirá corriendo pero no tomará acciones sobre móviles inactivos. ¿Confirmar?',
                                style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
                              ),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCELAR', style: TextStyle(color: Colors.white38))),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: val ? Colors.orange[800] : Colors.grey[700],
                                    foregroundColor: Colors.white,
                                  ),
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: Text(val ? 'ACTIVAR' : 'DESACTIVAR', style: const TextStyle(fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                          );
                          if (confirmado == true) _toggleBloqueoInactividad(val);
                        },
                      ),
                    ),

                    // ── CONFIG-CASCADA-D: tiempos de cascada ────────────────
                    _tarjetaGestion(
                      icono: Icons.timer_outlined,
                      color: const Color(0xFF1565C0),
                      titulo: '⏱️ Cascada de Notificaciones',
                      subtitulo:
                          'SE: F2 ${_cascadaSeF2Seg}s · F3 ${_cascadaSeF3Seg}s · F4 ${_cascadaSeF4Seg}s'
                          '  |  FN: F2 ${_cascadaFnF2Seg}s (⏰${_cascadaFnF2TimeoutSeg}s) · F3 ${_cascadaFnF3Seg}s · F4 ${_cascadaFnF4Seg}s',
                      onTap: () => _abrirDialogoCascada(context),
                    ),

                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _seccionGestion(String label) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8, left: 4),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white38,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.4,
        ),
      ),
    );
  }

  Widget _tarjetaGestion({
    required IconData icono,
    required Color color,
    required String titulo,
    required String subtitulo,
    required VoidCallback onTap,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey[200]!),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icono, color: color, size: 22),
        ),
        title: Text(
          titulo,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        subtitle: Text(
          subtitulo,
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
        trailing: const Icon(Icons.chevron_right, color: Colors.black26),
        onTap: onTap,
      ),
    );
  }

  void _abrirMenuFiltroMonitor(BuildContext context) {
    final opciones = {
      'problemas': '⚠️ Reportes de problema',
      'renegociaciones': '🔄 Renegociaciones FN',
      'cotizaciones': '❓ Cotizaciones pendientes',
      'cotizadas': '✉️ Cotizaciones enviadas',
      'programados': '⏰ Servicios programados',
      'caducados': '♻️ Servicios caducados',
      'demorados': '⏱️ Vencidos / demorados',
      'libres': '🟢 Radar de disponibles',
      'en_curso': '🟡 Servicios en curso',
      'finalizados_problema': '🔴 Finalizados con problema',
      'finalizados': '⚪ Finalizados',
      'cancelados': '⚫ Cancelados',
    };

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: const Text('Qué mostrar en el monitor'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: opciones.entries.map((e) {
                final oculta = _seccionesOcultasMonitor.contains(e.key);
                return CheckboxListTile(
                  value: !oculta,
                  dense: true,
                  activeColor: Colors.black,
                  title: Text(e.value, style: const TextStyle(fontSize: 13)),
                  onChanged: (val) {
                    setDialogState(() {
                      if (val == true) {
                        _seccionesOcultasMonitor.remove(e.key);
                      } else {
                        _seccionesOcultasMonitor.add(e.key);
                      }
                    });
                    // Notifica solo al monitor — sin reconstruir todo el Scaffold
                    _filtroVersion.value++;
                  },
                );
              }).toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('CERRAR'),
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // HISTORIAL COMPLETO — servicios ya archivados, filtrables por fecha
  // =========================================================================
  void _abrirHistorialCompletoCentral(BuildContext context) {
    DateTimeRange? rangoSeleccionado;

    showModalBottomSheet(
      context: context,
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
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Historial completo',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                      ),
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.calendar_month, size: 16),
                      label: Text(
                        rangoSeleccionado == null
                            ? 'Filtrar fecha'
                            : '${DateFormat('dd/MM').format(rangoSeleccionado!.start)} - ${DateFormat('dd/MM').format(rangoSeleccionado!.end)}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      onPressed: () async {
                        final ahora = DateTime.now();
                        final rango = await showDateRangePicker(
                          context: context,
                          firstDate: DateTime(ahora.year - 1),
                          lastDate: ahora,
                          initialDateRange: rangoSeleccionado,
                        );
                        if (rango != null) {
                          setModalState(() => rangoSeleccionado = rango);
                        }
                      },
                    ),
                    if (rangoSeleccionado != null)
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () =>
                            setModalState(() => rangoSeleccionado = null),
                      ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: () async {
                    var query = Supabase.instance.client
                        .from('servicios')
                        .select()
                        .eq('archivado', true);
                    if (rangoSeleccionado != null) {
                      query = query
                          .gte(
                            'created_at',
                            rangoSeleccionado!.start.toIso8601String(),
                          )
                          .lt(
                            'created_at',
                            rangoSeleccionado!.end
                                .add(const Duration(days: 1))
                                .toIso8601String(),
                          );
                    }
                    return await query.order('id', ascending: false).limit(200);
                  }(),
                  builder: (context, snap) {
                    if (!snap.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final servicios = snap.data!;
                    if (servicios.isEmpty) {
                      return const Center(
                        child: Text('Sin servicios archivados en este rango.'),
                      );
                    }
                    return ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.all(12),
                      itemCount: servicios.length,
                      itemBuilder: (context, i) {
                        final s = servicios[i];
                        String fechaTexto = '';
                        try {
                          final f = DateTime.parse(s['created_at']).toLocal();
                          fechaTexto = DateFormat('dd/MM/yyyy · hh:mm a').format(f);
                        } catch (_) {}
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            dense: true,
                            title: Text(
                              '#${s['id']} — ${s['origen'] ?? ''} ➔ ${s['destino'] ?? ''}',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Text(
                              '$fechaTexto · ${s['estado'] ?? ''}',
                              style: const TextStyle(fontSize: 11),
                            ),
                            trailing: Text(
                              fmtPeso(s['tarifa'], mostrarCero: true),
                              style: const TextStyle(fontSize: 12),
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

  void _abrirGestorParaderos() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _PanelGestorParaderos(
          onConfigRecargos: (local) => _abrirConfigRecargosLocal(local),
        ),
      ),
    );
  }


  // ─────────────────────────────────────────────────────────────
  // RED DE DIRECCIONES SE — navega a pantalla completa
  // GESTOR DE SECTORES
  // ─────────────────────────────────────────────────────────────
  // ─────────────────────────────────────────────────────────────
  // GESTOR UNIFICADO: RED DE DIRECCIONES + SECTORES
  // ─────────────────────────────────────────────────────────────
  void _abrirGestorRedYSectores(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const _PanelRedYSectores()),
    );
  }

  // ── Utilidad de color compartida en _CentralScreenState ─────────────────
  Color _hexColor(String hex) {
    try {
      final h = hex.replaceAll('#', '');
      return Color(int.parse('FF$h', radix: 16));
    } catch (_) { return Colors.blue; }
  }

  // ── CONFIG-CASCADA-D: Dialog de tiempos de cascada ──────────────────────

  Future<void> _abrirDialogoCascada(BuildContext ctx) async {
    final seF2c  = TextEditingController(text: _cascadaSeF2Seg.toString());
    final seF3c  = TextEditingController(text: _cascadaSeF3Seg.toString());
    final seF4c  = TextEditingController(text: _cascadaSeF4Seg.toString());
    final fnF2c  = TextEditingController(text: _cascadaFnF2Seg.toString());
    final fnToc  = TextEditingController(text: _cascadaFnF2TimeoutSeg.toString());
    final fnF3c  = TextEditingController(text: _cascadaFnF3Seg.toString());
    final fnF4c  = TextEditingController(text: _cascadaFnF4Seg.toString());

    bool guardando = false;
    String? errorGuardando;

    await showDialog<void>(
      context: ctx,
      builder: (dlgCtx) => StatefulBuilder(
        builder: (_, setDlg) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Row(children: [
            Icon(Icons.timer_outlined, color: Color(0xFF42A5F5), size: 20),
            SizedBox(width: 8),
            Text('Cascada de Notificaciones',
                style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
          ]),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Todos los valores son segundos desde T=0 (creación del servicio).',
                  style: TextStyle(color: Colors.white38, fontSize: 11, height: 1.4),
                ),
                const SizedBox(height: 16),

                // ── SERVIEXPRESS ─────────────────────────────────────────
                _cascadaSeccionLabel('🟢 ServiExpress'),
                _cascadaCampo(
                  label: 'Fase 2 — Auto-asigna #1 del paradero',
                  hint: 'aplica de inmediato a servicios en vuelo',
                  ctrl: seF2c,
                ),
                _cascadaCampo(
                  label: 'Fase 3 — Push radio 1km del punto de recogida',
                  hint: 'aplica a servicios creados después de guardar',
                  ctrl: seF3c,
                ),
                _cascadaCampo(
                  label: 'Fase 4 — Push todos los disponibles',
                  hint: 'aplica a servicios creados después de guardar',
                  ctrl: seF4c,
                ),

                const SizedBox(height: 16),

                // ── FN LA CASCADA ─────────────────────────────────────────
                _cascadaSeccionLabel('🔵 FN La Cascada'),
                _cascadaCampo(
                  label: 'Fase 2 — Ofrece al móvil más cercano a la sede',
                  hint: 'aplica de inmediato a servicios en vuelo',
                  ctrl: fnF2c,
                ),
                _cascadaCampo(
                  label: '⏰ Tiempo para aceptar antes de liberar a F3',
                  hint: 'aplica de inmediato a servicios en vuelo',
                  ctrl: fnToc,
                  accentColor: Colors.orange,
                ),
                _cascadaCampo(
                  label: 'Fase 3 — Push no-Masters dentro de 2km de la sede',
                  hint: 'aplica a servicios creados después de guardar',
                  ctrl: fnF3c,
                ),
                _cascadaCampo(
                  label: 'Fase 4 — Push global a todos los disponibles',
                  hint: 'aplica a servicios creados después de guardar',
                  ctrl: fnF4c,
                ),

                if (errorGuardando != null) ...[
                  const SizedBox(height: 10),
                  Text(errorGuardando!, style: const TextStyle(color: Colors.redAccent, fontSize: 11)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: guardando ? null : () => Navigator.pop(dlgCtx),
              child: const Text('CANCELAR', style: TextStyle(color: Colors.white38)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1565C0),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: guardando ? null : () async {
                setDlg(() { guardando = true; errorGuardando = null; });
                try {
                  await Supabase.instance.client
                      .from('config_sistema')
                      .update({
                        'cascada_se_f2_seg':         int.tryParse(seF2c.text) ?? 30,
                        'cascada_se_f3_seg':         int.tryParse(seF3c.text) ?? 60,
                        'cascada_se_f4_seg':         int.tryParse(seF4c.text) ?? 90,
                        'cascada_fn_f2_seg':         int.tryParse(fnF2c.text) ?? 30,
                        'cascada_fn_f2_timeout_seg': int.tryParse(fnToc.text) ?? 30,
                        'cascada_fn_f3_seg':         int.tryParse(fnF3c.text) ?? 60,
                        'cascada_fn_f4_seg':         int.tryParse(fnF4c.text) ?? 90,
                      })
                      .eq('id', 1);
                  await _cargarBloqueoInactividad(); // recarga todos los campos de config
                  if (dlgCtx.mounted) Navigator.pop(dlgCtx);
                } catch (e) {
                  setDlg(() { guardando = false; errorGuardando = 'Error al guardar: $e'; });
                }
              },
              child: guardando
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('GUARDAR', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );

    seF2c.dispose(); seF3c.dispose(); seF4c.dispose();
    fnF2c.dispose(); fnToc.dispose(); fnF3c.dispose(); fnF4c.dispose();
  }

  Widget _cascadaSeccionLabel(String label) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      label,
      style: const TextStyle(
        color: Colors.white70,
        fontSize: 12,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.5,
      ),
    ),
  );

  Widget _cascadaCampo({
    required String label,
    required String hint,
    required TextEditingController ctrl,
    Color accentColor = const Color(0xFF42A5F5),
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(color: Colors.white, fontSize: 11, height: 1.3)),
                  Text(hint,
                      style: const TextStyle(color: Colors.white38, fontSize: 10, height: 1.3)),
                ],
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 58,
              height: 36,
              child: TextField(
                controller: ctrl,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: accentColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
                decoration: InputDecoration(
                  contentPadding: const EdgeInsets.symmetric(vertical: 6),
                  suffix: Text('s',
                      style: TextStyle(color: accentColor.withValues(alpha: 0.7), fontSize: 11)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: accentColor.withValues(alpha: 0.3)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: accentColor),
                  ),
                  filled: true,
                  fillColor: accentColor.withValues(alpha: 0.08),
                ),
              ),
            ),
          ],
        ),
      );

}

// ══════════════════════════════════════════════════════════════════════════════
// GESTOR DE PARADEROS — pantalla completa (mobile-friendly)
// ══════════════════════════════════════════════════════════════════════════════

class _PanelGestorParaderos extends StatefulWidget {
  final Function(Map<String, dynamic>) onConfigRecargos;
  const _PanelGestorParaderos({required this.onConfigRecargos});

  @override
  State<_PanelGestorParaderos> createState() => _PanelGestorParaderosState();
}

class _PanelGestorParaderosState extends State<_PanelGestorParaderos>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  late Future<List<Map<String, dynamic>>> _future;

  // Paraderos de día disponibles (valor → label, color, emoji)
  // PARADEROS-C ✅ (panel_control): Panel usa BD dinámicamente.
  // PENDIENTE PARADEROS-D: reemplazar esta lista por carga dinámica en formularios.
  static const _paraderosDia = [
    ('LIBRE',    'Libre (por cercanía)', Color(0xFF2E7D32), '🟢'),
    ('EXPUENTE', 'Expuente',             Color(0xFF2E7D32), '🟢'),
    ('BOCONO',   'Boconó',               Color(0xFF4E342E), '🟤'),
    ('MEMOS',    'Memos',                Color(0xFFC62828), '🔴'),
  ];

  // ── Tab 3: lista de paraderos de BD ─────────────────────────────────────────
  List<Map<String, dynamic>> _paraderosBD = [];
  bool _cargandoParaderosBD = false;

  // Colores predefinidos para el selector de color
  static const _coloresPreset = [
    ('#1565C0', '🔵 Azul'),
    ('#6A1B9A', '🟣 Morado'),
    ('#4E342E', '🟤 Café'),
    ('#1A237E', '🌙 Azul noche'),
    ('#1B5E20', '🟢 Verde'),
    ('#E65100', '🟠 Naranja'),
    ('#B71C1C', '🔴 Rojo'),
    ('#37474F', '⚫ Gris oscuro'),
  ];

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    _future = _cargar();
    _cargarParaderosBD();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _cargar() =>
      Supabase.instance.client
          .from('usuarios')
          .select('id, nombre, paradero_exclusivo, paradero_nocturno, recargo_nocturno_especial, zona_lluvia')
          .eq('rol', 'local')
          .order('nombre', ascending: true);

  void _recargar() => setState(() => _future = _cargar());

  /// Cambia el paradero de día de un local
  Future<void> _cambiarParadero(Map<String, dynamic> local, String? nuevo) async {
    await Supabase.instance.client
        .from('usuarios')
        .update({'paradero_exclusivo': nuevo})
        .eq('id', local['id']);
    _recargar();
  }

  /// Activa/desactiva el paradero nocturno de un local
  Future<void> _toggleNocturno(Map<String, dynamic> local, bool valor) async {
    await Supabase.instance.client
        .from('usuarios')
        .update({'paradero_nocturno': valor})
        .eq('id', local['id']);
    _recargar();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Gestor de Paraderos',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        bottom: TabBar(
          controller: _tab,
          labelColor: const Color(0xFF3AF500),
          unselectedLabelColor: Colors.white60,
          indicatorColor: const Color(0xFF3AF500),
          tabs: const [
            Tab(icon: Icon(Icons.wb_sunny_outlined, size: 18), text: 'DÍA'),
            Tab(icon: Icon(Icons.nights_stay_outlined, size: 18), text: 'NOCTURNO'),
            Tab(icon: Icon(Icons.place_rounded, size: 18), text: 'PARADEROS'),
          ],
        ),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Colors.black));
          }
          final locales = snapshot.data ?? [];
          if (locales.isEmpty) {
            return const Center(
              child: Text('No hay locales registrados.',
                  style: TextStyle(color: Colors.black54, fontSize: 14)));
          }
          return TabBarView(
            controller: _tab,
            children: [
              _buildTabDia(locales),
              _buildTabNocturno(locales),
              _buildTabParaderos(),
            ],
          );
        },
      ),
    );
  }

  // ── TAB 1: PARADEROS DE DÍA ────────────────────────────────────────────────
  Widget _buildTabDia(List<Map<String, dynamic>> locales) {
    // Agrupar por paradero
    final grupos = <String, List<Map<String, dynamic>>>{};
    for (final l in locales) {
      final p = l['paradero_exclusivo']?.toString() ?? 'LIBRE';
      grupos.putIfAbsent(p, () => []).add(l);
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _bannerInfo(
          '☀️ Asigna de qué paradero saldrán los móviles para cada local durante el día. '
          'Memos cierra después de medianoche.',
        ),
        const SizedBox(height: 12),
        for (final entry in _paraderosDia) ...[
          _seccionParadero(
            emoji: entry.$4,
            titulo: entry.$2.toUpperCase(),
            color: entry.$3,
            locales: grupos[entry.$1] ?? [],
            todos: locales,
            valorSeccion: entry.$1,
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  // ── TAB 2: NOCTURNO ────────────────────────────────────────────────────────
  Widget _buildTabNocturno(List<Map<String, dynamic>> locales) {
    // Solo aplica a Expuente y Boconó (Memos cierra, Libre no tiene zona nocturna)
    final aplicables = locales.where((l) {
      final p = l['paradero_exclusivo']?.toString() ?? 'LIBRE';
      return p == 'EXPUENTE' || p == 'BOCONO';
    }).toList();

    final nocturnos  = aplicables.where((l) => l['paradero_nocturno'] == true).toList();
    final diurnos    = aplicables.where((l) => l['paradero_nocturno'] != true).toList();

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _bannerInfo(
          '🌙 Los locales marcados como NOCTURNO seguirán siendo atendidos después de medianoche '
          'desde el paradero NOCTURNO. Aplica solo a Expuente y Boconó.',
        ),
        const SizedBox(height: 12),
        // Sección: con nocturno activo
        _headerSeccion('🌙 TRABAJAN DE NOCHE (${nocturnos.length})', const Color(0xFF283593)),
        if (nocturnos.isEmpty)
          _emptyCard('Sin locales nocturnos aún')
        else
          ...nocturnos.map((l) => _cardLocalNocturno(l, true)),
        const SizedBox(height: 12),
        // Sección: sin nocturno
        _headerSeccion('☀️ SOLO HORARIO DIURNO (${diurnos.length})', Colors.grey[700]!),
        if (diurnos.isEmpty)
          _emptyCard('Todos los locales trabajan de noche')
        else
          ...diurnos.map((l) => _cardLocalNocturno(l, false)),
        const SizedBox(height: 12),
        // Locales que no aplican
        _headerSeccion('⚫ NO APLICAN (Memos / Libres)', Colors.grey[500]!),
        _bannerInfo('Memos cierra después de medianoche. Los locales libres no tienen zona nocturna asignada.'),
      ],
    );
  }

  // ── WIDGETS COMPARTIDOS ────────────────────────────────────────────────────

  Widget _bannerInfo(String texto) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: Colors.blue[50],
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: Colors.blue[100]!),
    ),
    child: Text(texto, style: TextStyle(fontSize: 12, color: Colors.blue[900])),
  );

  Widget _headerSeccion(String titulo, Color color) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(titulo,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold,
            color: color, letterSpacing: 0.6)),
  );

  Widget _emptyCard(String msg) => Card(
    elevation: 0,
    margin: const EdgeInsets.only(bottom: 8),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Text(msg, style: const TextStyle(color: Colors.black38, fontSize: 12)),
    ),
  );

  Widget _seccionParadero({
    required String emoji,
    required String titulo,
    required Color color,
    required List<Map<String, dynamic>> locales,
    required List<Map<String, dynamic>> todos,
    required String valorSeccion,
  }) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: color.withValues(alpha: 0.3)),
      ),
      child: ExpansionTile(
        initiallyExpanded: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        collapsedShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        title: Row(children: [
          Text(emoji, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
          Text(titulo,
              style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 13)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text('${locales.length}',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color)),
          ),
        ]),
        children: [
          if (locales.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Text('Sin locales asignados',
                  style: TextStyle(color: Colors.black38, fontSize: 12)),
            )
          else
            ...locales.map((local) => _cardLocalDia(local, todos, valorSeccion, color)),
        ],
      ),
    );
  }

  /// Tarjeta de local en la pestaña de DÍA
  Widget _cardLocalDia(
    Map<String, dynamic> local,
    List<Map<String, dynamic>> todos,
    String paraderoActual,
    Color colorSeccion,
  ) {
    final esNocturno = local['paradero_nocturno'] == true;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorSeccion.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Nombre + badge nocturno
          Row(children: [
            const Icon(Icons.storefront, size: 16, color: Colors.black45),
            const SizedBox(width: 8),
            Expanded(
              child: Text(local['nombre'].toString(),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
            if (esNocturno)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF283593).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text('🌙 nocturno',
                    style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold,
                        color: Color(0xFF283593))),
              ),
          ]),
          const SizedBox(height: 10),
          // Dropdown paradero de día (ocupa todo el ancho — más fácil en celular)
          DropdownButtonFormField<String>(
            value: paraderoActual,
            isExpanded: true,
            isDense: true,
            decoration: InputDecoration(
              labelText: 'Paradero de día',
              labelStyle: const TextStyle(fontSize: 11),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: colorSeccion.withValues(alpha: 0.4)),
              ),
            ),
            style: const TextStyle(fontSize: 13, color: Colors.black, fontWeight: FontWeight.w600),
            items: _paraderosDia.map((p) => DropdownMenuItem(
              value: p.$1,
              child: Text('${p.$4} ${p.$2}', style: const TextStyle(fontSize: 13)),
            )).toList(),
            onChanged: (nuevo) async {
              if (nuevo == null || nuevo == paraderoActual) return;
              final valor = nuevo == 'LIBRE' ? null : nuevo;
              await _cambiarParadero(local, valor);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('${local['nombre']} → $nuevo'),
                  backgroundColor: Colors.black,
                  duration: const Duration(seconds: 2),
                ));
              }
            },
          ),
          const SizedBox(height: 6),
          // Botón de recargos
          GestureDetector(
            onTap: () => widget.onConfigRecargos(local),
            child: Row(children: [
              Icon(Icons.tune, size: 13, color: Colors.orange[700]),
              const SizedBox(width: 4),
              Text('Configurar recargos',
                  style: TextStyle(fontSize: 11, color: Colors.orange[700],
                      fontWeight: FontWeight.w600)),
            ]),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TAB 3: GESTIÓN DE PARADEROS (CRUD sobre tabla paraderos)
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> _cargarParaderosBD() async {
    if (!mounted) return;
    setState(() => _cargandoParaderosBD = true);
    final data = await Supabase.instance.client
        .from('paraderos')
        .select('id, nombre, latitud, longitud, activo, es_nocturno, color_hex, emoji, orden, radio_metros')
        .order('orden', ascending: true);
    if (!mounted) return;
    setState(() { _paraderosBD = List<Map<String, dynamic>>.from(data); _cargandoParaderosBD = false; });
  }

  Widget _buildTabParaderos() {
    if (_cargandoParaderosBD) {
      return const Center(child: CircularProgressIndicator(color: Colors.black));
    }
    return Stack(children: [
      ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
        children: [
          _bannerInfo('📍 Gestiona los paraderos de la flota. Los cambios se reflejan en toda la app al próximo reinicio de sesión.'),
          const SizedBox(height: 12),
          if (_paraderosBD.isEmpty)
            _emptyCard('Sin paraderos registrados')
          else
            ..._paraderosBD.map((p) => _cardParadero(p)),
        ],
      ),
      // FAB crear nuevo paradero
      Positioned(
        bottom: 16, right: 16,
        child: FloatingActionButton.extended(
          heroTag: 'fab_paradero',
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          icon: const Icon(Icons.add_location_alt_rounded),
          label: const Text('Nuevo paradero', style: TextStyle(fontWeight: FontWeight.bold)),
          onPressed: () => _dialogParadero(null),
        ),
      ),
    ]);
  }

  Widget _cardParadero(Map<String, dynamic> p) {
    final color = _hexColor(p['color_hex'] ?? '#1565C0');
    final activo = p['activo'] == true;
    final esNocturno = p['es_nocturno'] == true;

    return Card(
      elevation: activo ? 1 : 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: activo ? color.withValues(alpha: 0.35) : Colors.grey[300]!),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(children: [
          // Emoji + color swatch
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(
              color: activo ? color.withValues(alpha: 0.12) : Colors.grey[100],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: activo ? color.withValues(alpha: 0.4) : Colors.grey[300]!),
            ),
            child: Center(child: Text(p['emoji'] ?? '📍', style: const TextStyle(fontSize: 20))),
          ),
          const SizedBox(width: 12),
          // Info
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(p['nombre'] ?? '', style: TextStyle(
                fontWeight: FontWeight.bold, fontSize: 14,
                color: activo ? Colors.black87 : Colors.black38,
              )),
              const SizedBox(width: 6),
              if (esNocturno)
                _badgeChip('🌙 nocturno', const Color(0xFF1A237E)),
              if (!activo)
                _badgeChip('INACTIVO', Colors.grey),
            ]),
            const SizedBox(height: 3),
            Text(
              'Orden ${p['orden'] ?? '—'} · ${p['color_hex'] ?? ''} · radio ${p['radio_metros'] ?? 150}m',
              style: const TextStyle(fontSize: 10, color: Colors.black38),
            ),
            if (p['latitud'] != null)
              Text(
                '${(p['latitud'] as double).toStringAsFixed(5)}, ${(p['longitud'] as double).toStringAsFixed(5)}',
                style: const TextStyle(fontSize: 10, color: Colors.black38),
              ),
          ])),
          // Acciones
          Column(mainAxisSize: MainAxisSize.min, children: [
            IconButton(
              icon: const Icon(Icons.edit_rounded, size: 18),
              color: Colors.black54,
              tooltip: 'Editar',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
              onPressed: () => _dialogParadero(p),
            ),
            IconButton(
              icon: Icon(activo ? Icons.toggle_on_rounded : Icons.toggle_off_rounded,
                  size: 22, color: activo ? Colors.green[700] : Colors.grey),
              tooltip: activo ? 'Desactivar' : 'Activar',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
              onPressed: () => _toggleActivoParadero(p),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _badgeChip(String label, Color color) => Container(
    margin: const EdgeInsets.only(left: 4),
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: color.withValues(alpha: 0.4)),
    ),
    child: Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: color)),
  );

  Color _hexColor(String hex) {
    try {
      final h = hex.replaceAll('#', '');
      return Color(int.parse('FF$h', radix: 16));
    } catch (_) { return Colors.blue; }
  }

  Future<void> _toggleActivoParadero(Map<String, dynamic> p) async {
    final nuevo = !(p['activo'] == true);
    await Supabase.instance.client
        .from('paraderos')
        .update({'activo': nuevo})
        .eq('id', p['id']);
    await _cargarParaderosBD();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(nuevo ? '✅ ${p['nombre']} activado' : '⏸ ${p['nombre']} desactivado'),
      backgroundColor: Colors.black87,
      duration: const Duration(seconds: 2),
    ));
  }

  Future<void> _dialogParadero(Map<String, dynamic>? existing) async {
    final isEdit = existing != null;
    final nombreCtrl  = TextEditingController(text: existing?['nombre'] ?? '');
    final emojiCtrl   = TextEditingController(text: existing?['emoji']  ?? '📍');
    final colorCtrl   = TextEditingController(text: existing?['color_hex'] ?? '#1565C0');
    final ordenCtrl   = TextEditingController(text: (existing?['orden'] ?? '').toString());
    final latCtrl     = TextEditingController(text: (existing?['latitud']  ?? '').toString());
    final lngCtrl     = TextEditingController(text: (existing?['longitud'] ?? '').toString());
    final radioCtrl   = TextEditingController(text: (existing?['radio_metros'] ?? 150).toString());
    bool esNocturno   = existing?['es_nocturno'] == true;
    String colorSel   = existing?['color_hex'] ?? '#1565C0';

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(children: [
            Icon(isEdit ? Icons.edit_location_rounded : Icons.add_location_alt_rounded,
                color: Colors.white70, size: 20),
            const SizedBox(width: 8),
            Text(isEdit ? 'Editar paradero' : 'Nuevo paradero',
                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
          ]),
          content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            // Nombre
            _inputField(nombreCtrl, 'Nombre (ej: EXPUENTE)', TextInputType.text),
            const SizedBox(height: 10),
            // Emoji + Orden en fila
            Row(children: [
              Expanded(child: _inputField(emojiCtrl, 'Emoji', TextInputType.text)),
              const SizedBox(width: 8),
              Expanded(child: _inputField(ordenCtrl, 'Orden (#)', TextInputType.number)),
            ]),
            const SizedBox(height: 10),
            // Color hex + preview
            Row(children: [
              Expanded(child: _inputField(colorCtrl, 'Color hex (#1565C0)',
                TextInputType.text, onChange: (v) => setSt(() => colorSel = v))),
              const SizedBox(width: 8),
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: _hexColor(colorSel),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            // Colores preset
            Wrap(spacing: 6, runSpacing: 6, children: _coloresPreset.map((c) {
              final sel = colorSel == c.$1;
              return GestureDetector(
                onTap: () => setSt(() { colorSel = c.$1; colorCtrl.text = c.$1; }),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: sel ? _hexColor(c.$1).withValues(alpha: 0.2) : Colors.white10,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: sel ? _hexColor(c.$1) : Colors.white24, width: sel ? 1.5 : 1),
                  ),
                  child: Text(c.$2, style: TextStyle(fontSize: 10,
                      color: sel ? Colors.white : Colors.white54,
                      fontWeight: sel ? FontWeight.bold : FontWeight.normal)),
                ),
              );
            }).toList()),
            const SizedBox(height: 10),
            // Coordenadas
            Row(children: [
              Expanded(child: _inputField(latCtrl, 'Latitud', const TextInputType.numberWithOptions(decimal: true, signed: true))),
              const SizedBox(width: 8),
              Expanded(child: _inputField(lngCtrl, 'Longitud', const TextInputType.numberWithOptions(decimal: true, signed: true))),
            ]),
            const SizedBox(height: 10),
            // Radio geocerca
            _inputField(radioCtrl, 'Radio geocerca (metros)', TextInputType.number),
            const SizedBox(height: 4),
            const Text('Distancia máxima para permanecer en la fila (+ 50m de margen automático).',
                style: TextStyle(fontSize: 10, color: Colors.white38)),
            const SizedBox(height: 10),
            // Es nocturno
            Row(children: [
              const Icon(Icons.nights_stay_outlined, color: Colors.white54, size: 18),
              const SizedBox(width: 8),
              const Expanded(child: Text('Paradero nocturno',
                  style: TextStyle(color: Colors.white70, fontSize: 12))),
              Switch(
                value: esNocturno,
                onChanged: (v) => setSt(() => esNocturno = v),
                activeColor: const Color(0xFF1A237E),
              ),
            ]),
          ])),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('CANCELAR', style: TextStyle(color: Colors.white38)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3AF500), foregroundColor: Colors.black),
              onPressed: () async {
                final nombre = nombreCtrl.text.trim().toUpperCase();
                if (nombre.isEmpty) return;
                final payload = {
                  'nombre':       nombre,
                  'emoji':        emojiCtrl.text.trim().isEmpty ? '📍' : emojiCtrl.text.trim(),
                  'color_hex':    colorCtrl.text.trim().isEmpty ? '#1565C0' : colorCtrl.text.trim(),
                  'es_nocturno':  esNocturno,
                  'orden':        int.tryParse(ordenCtrl.text.trim()) ?? 99,
                  'latitud':      double.tryParse(latCtrl.text.trim()),
                  'longitud':     double.tryParse(lngCtrl.text.trim()),
                  'radio_metros': int.tryParse(radioCtrl.text.trim()) ?? 150,
                  'activo':       true,
                };
                if (isEdit) {
                  await Supabase.instance.client
                      .from('paraderos').update(payload).eq('id', existing['id']);
                } else {
                  await Supabase.instance.client.from('paraderos').insert(payload);
                }
                if (ctx.mounted) Navigator.pop(ctx);
                await _cargarParaderosBD();
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(isEdit ? '✅ Paradero actualizado' : '✅ Paradero creado'),
                  backgroundColor: Colors.black87,
                  duration: const Duration(seconds: 2),
                ));
              },
              child: const Text('GUARDAR', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
    nombreCtrl.dispose(); emojiCtrl.dispose(); colorCtrl.dispose();
    ordenCtrl.dispose(); latCtrl.dispose(); lngCtrl.dispose(); radioCtrl.dispose();
  }

  Widget _inputField(TextEditingController ctrl, String hint, TextInputType tipo,
      {void Function(String)? onChange}) =>
    TextField(
      controller: ctrl,
      keyboardType: tipo,
      onChanged: onChange,
      style: const TextStyle(color: Colors.white, fontSize: 13),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white30, fontSize: 11),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        filled: true,
        fillColor: Colors.white10,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Colors.white24)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Colors.white24)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF3AF500))),
      ),
    );

  // ══════════════════════════════════════════════════════════════════════════
  // FIN TAB 3
  // ══════════════════════════════════════════════════════════════════════════

  /// Tarjeta de local en la pestaña NOCTURNO
  Widget _cardLocalNocturno(Map<String, dynamic> local, bool esNocturno) {
    final paradero = local['paradero_exclusivo']?.toString() ?? 'LIBRE';
    final (_, labelP, colorP, emojiP) = _paraderosDia.firstWhere(
      (p) => p.$1 == paradero, orElse: () => _paraderosDia[0]);

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: esNocturno ? const Color(0xFF283593).withValues(alpha: 0.5) : Colors.grey[300]!,
          width: esNocturno ? 1.5 : 1,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: CircleAvatar(
          radius: 20,
          backgroundColor: esNocturno
              ? const Color(0xFF283593).withValues(alpha: 0.12)
              : Colors.grey[100],
          child: Text(esNocturno ? '🌙' : '☀️', style: const TextStyle(fontSize: 16)),
        ),
        title: Text(local['nombre'].toString(),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        subtitle: Row(children: [
          Text(emojiP, style: const TextStyle(fontSize: 11)),
          const SizedBox(width: 4),
          Text(labelP, style: TextStyle(fontSize: 11, color: colorP, fontWeight: FontWeight.w600)),
          Text(' de día', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
        ]),
        trailing: Switch(
          value: esNocturno,
          activeTrackColor: const Color(0xFF283593).withValues(alpha: 0.3),
          activeThumbColor: const Color(0xFF283593),
          onChanged: (val) async {
            await _toggleNocturno(local, val);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(val
                    ? '🌙 ${local['nombre']} — nocturno activado'
                    : '☀️ ${local['nombre']} — solo diurno'),
                backgroundColor: Colors.black,
                duration: const Duration(seconds: 2),
              ));
            }
          },
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// RED & SECTORES — pantalla completa
// ══════════════════════════════════════════════════════════════════════════════

class _PanelRedYSectores extends StatefulWidget {
  const _PanelRedYSectores();
  @override
  State<_PanelRedYSectores> createState() => _PanelRedYSectoresState();
}

class _PanelRedYSectoresState extends State<_PanelRedYSectores>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  final _db = Supabase.instance.client;

  // ── Datos globales ──────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _usuarios = [];
  List<Map<String, dynamic>> _sectoresActivos = []; // catálogo global
  bool _cargandoInicial = true;

  // ── Usuario seleccionado ────────────────────────────────────────────────────
  Map<String, dynamic>? _userSel;
  List<Map<String, dynamic>> _dirs = []; // red_dir_catalogo
  Map<int, int> _preciosDir = {}; // dir_id → precio (se_precios_dir)
  Map<int, int> _tarifaMap = {}; // sector_id → precio (tarifas_usuario_sector)
  bool _cargandoUser = false;

  // ── Filtros ─────────────────────────────────────────────────────────────────
  String _secFiltroMun = 'Cúcuta';
  int? _secFiltroSector;
  String? _secFiltroIncompleto; // #108: null | 'sinPrecio' | 'inactivo'
  final _secBusquedaCtrl = TextEditingController(); // #99
  String _secBusqueda = ''; // #99
  String _dirFiltroMun = 'Cúcuta';
  int? _dirFiltroSector;
  int? _dirFiltroBarrio; // #101
  String? _dirFiltroIncompleto; // #108: null | 'sinPrecio' | 'sinGps' | 'inactivo'
  final _dirBusquedaCtrl = TextEditingController(); // #99
  String _dirBusqueda = ''; // #99

  static const _municipios = ['Cúcuta', 'Los Patios', 'V. Rosario'];

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _tab.addListener(() => setState(() {}));
    _secBusquedaCtrl.addListener(() =>
        setState(() => _secBusqueda = _secBusquedaCtrl.text.trim().toLowerCase()));
    _dirBusquedaCtrl.addListener(() =>
        setState(() => _dirBusqueda = _dirBusquedaCtrl.text.trim().toLowerCase()));
    _cargarInicial();
  }

  @override
  void dispose() {
    _tab.dispose();
    _secBusquedaCtrl.dispose();
    _dirBusquedaCtrl.dispose();
    super.dispose();
  }

  // ── Carga inicial ───────────────────────────────────────────────────────────
  Future<void> _cargarInicial() async {
    setState(() => _cargandoInicial = true);
    try {
      final usuarios = await _db
          .from('usuarios')
          .select('id, nombre, rol, usuario')
          .inFilter('rol', ['local', 'cliente'])
          .eq('activo', true)
          .order('nombre');
      final sectores = await _db
          .from('sectores')
          .select('id, nombre, municipio, activo, parent_id')
          .order('municipio')
          .order('nombre');
      if (mounted) setState(() {
        _usuarios = List<Map<String, dynamic>>.from(usuarios);
        _sectoresActivos = List<Map<String, dynamic>>.from(sectores);
        _cargandoInicial = false;
      });
    } catch (_) {
      if (mounted) setState(() => _cargandoInicial = false);
    }
  }

  Future<void> _cargarUser(int userId) async {
    setState(() => _cargandoUser = true);
    try {
      final dirs = await _db
          .from('red_dir_catalogo')
          .select('id, nombre, alias, direccion, municipio, sector_id, activo, lat, lng')
          .order('municipio')
          .order('nombre');
      final precios = await _db
          .from('se_precios_dir')
          .select('dir_id, precio')
          .eq('usuario_id', userId);
      final tarifas = await _db
          .from('tarifas_usuario_sector')
          .select('sector_id, precio')
          .eq('usuario_id', userId);
      if (mounted) {
        final pm = <int, int>{};
        for (final p in List<Map<String, dynamic>>.from(precios)) {
          pm[p['dir_id'] as int] = (p['precio'] as num).toInt();
        }
        final tm = <int, int>{};
        for (final t in List<Map<String, dynamic>>.from(tarifas)) {
          tm[t['sector_id'] as int] = (t['precio'] as num).toInt();
        }
        setState(() {
          _dirs = List<Map<String, dynamic>>.from(dirs);
          _preciosDir = pm;
          _tarifaMap = tm;
          _cargandoUser = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _cargandoUser = false);
    }
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  String _etiqueta(Map<String, dynamic> u) {
    final rol = u['rol'] as String? ?? '';
    final nom = u['nombre']?.toString() ?? '';
    return '${rol == 'local' ? '🏪' : '👤'} $nom';
  }

  String _fmt(int v) {
    final s = v.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  // ── CRUD Sectores globales ──────────────────────────────────────────────────
  Future<void> _abrirFormSector({Map<String, dynamic>? sector}) async {
    final ctrl = TextEditingController(text: sector?['nombre']?.toString() ?? '');
    bool activo = sector?['activo'] != false;
    String? municipio = sector?['municipio']?.toString() ?? _secFiltroMun;
    final sId = sector?['id'] as int?;
    int? parentId = sector?['parent_id'] as int?;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          backgroundColor: const Color(0xFF1A1A1A),
          title: Text(
            sector == null ? '➕ Nuevo sector/barrio' : '✏️ Editar sector/barrio',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
          ),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String?>(
              value: municipio,
              dropdownColor: const Color(0xFF1A1A1A),
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Municipio', labelStyle: TextStyle(color: Colors.white54),
                border: OutlineInputBorder(), isDense: true,
              ),
              items: [
                const DropdownMenuItem<String?>(value: null,
                    child: Text('Sin definir', style: TextStyle(color: Colors.white54))),
                ..._municipios.map((m) => DropdownMenuItem<String?>(
                      value: m, child: Text(m, style: const TextStyle(color: Colors.white)))),
              ],
              onChanged: (v) => setD(() { municipio = v; parentId = null; }),
            ),
            const SizedBox(height: 12),
            // Dropdown padre (barrio de...)
            Builder(builder: (ctx2) {
              final padres = _sectoresActivos
                  .where((s) =>
                      s['municipio'] == municipio &&
                      s['parent_id'] == null &&
                      (sId == null || s['id'] != sId))
                  .toList()
                ..sort((a, b) => (a['nombre'] ?? '').toString()
                    .compareTo((b['nombre'] ?? '').toString()));
              final validParent = padres.any((p) => p['id'] == parentId) ? parentId : null;
              return DropdownButtonFormField<int?>(
                value: validParent,
                dropdownColor: const Color(0xFF1A1A1A),
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: '¿Barrio de...?', labelStyle: TextStyle(color: Colors.white54),
                  border: OutlineInputBorder(), isDense: true,
                ),
                items: [
                  const DropdownMenuItem<int?>(
                      value: null,
                      child: Text('— Es un sector raíz —',
                          style: TextStyle(color: Colors.white54, fontSize: 13))),
                  ...padres.map((p) => DropdownMenuItem<int?>(
                      value: p['id'] as int,
                      child: Text(p['nombre']?.toString() ?? '',
                          style: const TextStyle(color: Colors.white)))),
                ],
                onChanged: (v) => setD(() => parentId = v),
              );
            }),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: 'Nombre',
                labelStyle: const TextStyle(color: Colors.white54),
                hintText: parentId != null ? 'Ej: Norte, Centro, Alto' : 'Ej: Bocono, Aeropuerto',
                hintStyle: const TextStyle(color: Colors.white24),
                border: const OutlineInputBorder(), isDense: true,
              ),
            ),
            if (sector != null) ...[
              const SizedBox(height: 12),
              SwitchListTile(
                value: activo,
                onChanged: (v) => setD(() => activo = v),
                title: const Text('Activo', style: TextStyle(color: Colors.white, fontSize: 13)),
                dense: true, contentPadding: EdgeInsets.zero,
              ),
            ],
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false),
                child: const Text('CANCELAR', style: TextStyle(color: Colors.white54))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xff3AF500)),
              onPressed: () async {
                final nombre = ctrl.text.trim();
                if (nombre.isEmpty) return;
                // #109 — detectar duplicado
                final duplicado = _sectoresActivos.any((s) =>
                    (s['nombre'] ?? '').toString().toLowerCase() ==
                        nombre.toLowerCase() &&
                    s['municipio'] == municipio &&
                    (sId == null || s['id'] != sId));
                if (duplicado) {
                  ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                    content: Text(
                        '⚠️ Ya existe un sector/barrio con ese nombre en este municipio'),
                    backgroundColor: Colors.orange,
                  ));
                  return;
                }
                final nav = Navigator.of(ctx);
                try {
                  if (sector == null) {
                    await _db.from('sectores').insert({
                      'nombre': nombre, 'activo': true,
                      if (municipio != null) 'municipio': municipio,
                      if (parentId != null) 'parent_id': parentId,
                    });
                  } else {
                    await _db.from('sectores').update({
                      'nombre': nombre, 'activo': activo, 'municipio': municipio,
                      'parent_id': parentId,
                    }).eq('id', sector['id']);
                  }
                  nav.pop(true);
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text('Error al guardar: $e'),
                      backgroundColor: Colors.red,
                    ));
                  }
                }
              },
              child: const Text('GUARDAR',
                  style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
    if (ok == true) await _cargarInicial();
  }

  Future<void> _eliminarSector(Map<String, dynamic> s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('¿Eliminar sector?', style: TextStyle(color: Colors.white)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(s['nombre'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('Se eliminará del catálogo global (todas las sedes y usuarios).',
              style: TextStyle(color: Colors.orange, fontSize: 12)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('NO', style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ELIMINAR', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok == true) {
      try {
        await _db.from('sectores').delete().eq('id', s['id']);
        await _cargarInicial();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Error al eliminar: $e'),
            backgroundColor: Colors.red,
          ));
        }
      }
    }
  }

  String _miles(int v) {
    if (v >= 1000) {
      final s = v.toString();
      return '${s.substring(0, s.length - 3)}.${s.substring(s.length - 3)}';
    }
    return v.toString();
  }

  void _editarTarifaDialog(int sId, int? tarifaActual) {
    final ctrl = TextEditingController(text: tarifaActual?.toString() ?? '');
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Tarifa del sector', style: TextStyle(color: Colors.white, fontSize: 15)),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            prefixText: '\$ ',
            prefixStyle: TextStyle(color: Colors.white54),
            hintText: '0',
            hintStyle: TextStyle(color: Colors.white38),
          ),
        ),
        actions: [
          if (tarifaActual != null)
            TextButton(
              onPressed: () { _eliminarTarifa(sId); Navigator.pop(context); },
              child: const Text('Quitar', style: TextStyle(color: Colors.red)),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () { _upsertTarifa(sId, ctrl.text); Navigator.pop(context); },
            child: const Text('Guardar', style: TextStyle(color: Color(0xff3AF500))),
          ),
        ],
      ),
    );
  }

  // ── CRUD Tarifas por usuario ────────────────────────────────────────────────
  Future<void> _upsertTarifa(int sectorId, String val) async {
    final precio = int.tryParse(val.trim());
    if (precio == null || precio <= 0) return;
    final userId = _userSel!['id'] as int;
    await _db.from('tarifas_usuario_sector').upsert(
      {'usuario_id': userId, 'sector_id': sectorId, 'precio': precio},
      onConflict: 'usuario_id, sector_id',
    );
    await _cargarUser(userId);
  }

  Future<void> _eliminarTarifa(int sectorId) async {
    final userId = _userSel!['id'] as int;
    await _db.from('tarifas_usuario_sector')
        .delete().eq('usuario_id', userId).eq('sector_id', sectorId);
    await _cargarUser(userId);
  }

  // ── CRUD Direcciones ────────────────────────────────────────────────────────
  static (double?, double?) _parseGps(String url) {
    var m = RegExp(r'@(-?\d{1,3}\.\d+),(-?\d{1,3}\.\d+)').firstMatch(url);
    if (m != null) return (double.tryParse(m.group(1)!), double.tryParse(m.group(2)!));
    m = RegExp(r'[?&]q=(-?\d{1,3}\.\d+),(-?\d{1,3}\.\d+)').firstMatch(url);
    if (m != null) return (double.tryParse(m.group(1)!), double.tryParse(m.group(2)!));
    m = RegExp(r'll=(-?\d{1,3}\.\d+),(-?\d{1,3}\.\d+)').firstMatch(url);
    if (m != null) return (double.tryParse(m.group(1)!), double.tryParse(m.group(2)!));
    m = RegExp(r'(-?\d{1,3}\.\d{4,}),(-?\d{1,3}\.\d{4,})').firstMatch(url);
    if (m != null) return (double.tryParse(m.group(1)!), double.tryParse(m.group(2)!));
    return (null, null);
  }

  Future<void> _formDir({Map<String, dynamic>? existing}) async {
    final nombreCtrl = TextEditingController(text: existing?['nombre']?.toString() ?? '');
    final aliasCtrl = TextEditingController(text: existing?['alias']?.toString() ?? '');
    final direccionCtrl = TextEditingController(text: existing?['direccion']?.toString() ?? '');
    final dId = existing?['id'] as int?;
    final precioCtrl = TextEditingController(
      text: dId != null && _preciosDir.containsKey(dId) ? _preciosDir[dId].toString() : '',
    );
    final gpsCtrl = TextEditingController();
    String? municipio = existing?['municipio']?.toString() ?? _dirFiltroMun;
    int? sectorId = existing?['sector_id'] as int?;
    bool activo = existing?['activo'] != false;
    double? gpsLat = (existing?['lat'] as num?)?.toDouble();
    double? gpsLng = (existing?['lng'] as num?)?.toDouble();

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          final sectoresFilt = municipio == null
              ? _sectoresActivos
              : _sectoresActivos.where((s) => s['municipio'] == municipio).toList();
          final sectorValido = sectoresFilt.any((s) => s['id'] == sectorId);
          return AlertDialog(
            backgroundColor: const Color(0xFF1A1A1A),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            title: Text(
              existing != null ? '✏️ Editar dirección' : '➕ Nueva dirección',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
            ),
            content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                // 1. Nombre/alias
                TextField(
                  controller: nombreCtrl,
                  style: const TextStyle(color: Colors.white),
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Nombre / alias', labelStyle: TextStyle(color: Colors.white54),
                    hintText: 'Ej: Clínica Norte', hintStyle: TextStyle(color: Colors.white24),
                    isDense: true, border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                // 2. Municipio
                DropdownButtonFormField<String?>(
                  value: municipio,
                  dropdownColor: const Color(0xFF1A1A1A),
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Municipio', labelStyle: TextStyle(color: Colors.white54),
                    isDense: true, border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(value: null,
                        child: Text('Sin definir', style: TextStyle(color: Colors.white54))),
                    ..._municipios.map((m) => DropdownMenuItem<String?>(
                          value: m, child: Text(m, style: const TextStyle(color: Colors.white)))),
                  ],
                  onChanged: (v) => setD(() { municipio = v; sectorId = null; }),
                ),
                const SizedBox(height: 10),
                // 3. Sector (opcional)
                DropdownButtonFormField<int?>(
                  value: sectorValido ? sectorId : null,
                  dropdownColor: const Color(0xFF1A1A1A),
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Sector (opcional)', labelStyle: const TextStyle(color: Colors.white54),
                    isDense: true, border: const OutlineInputBorder(),
                    hintText: sectoresFilt.isEmpty ? 'Sin sectores' : null,
                    hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                  items: [
                    const DropdownMenuItem<int?>(value: null,
                        child: Text('Sin sector', style: TextStyle(color: Colors.white54))),
                    ...sectoresFilt.map((s) => DropdownMenuItem<int?>(
                          value: s['id'] as int,
                          child: Text(s['nombre'].toString(), style: const TextStyle(color: Colors.white)))),
                  ],
                  onChanged: (v) => setD(() => sectorId = v),
                ),
                const SizedBox(height: 10),
                // 4. Dirección completa
                TextField(
                  controller: direccionCtrl,
                  style: const TextStyle(color: Colors.white),
                  maxLines: 2,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Dirección completa', labelStyle: TextStyle(color: Colors.white54),
                    hintText: 'Ej: Calle 10 # 5-20', hintStyle: TextStyle(color: Colors.white24),
                    isDense: true, border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                // 5. Precio para este usuario
                TextField(
                  controller: precioCtrl,
                  style: const TextStyle(color: Colors.white),
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Precio sugerido para este usuario (\$)',
                    labelStyle: TextStyle(color: Colors.white54),
                    hintText: 'Sin precio → no aparece en autocomplete',
                    hintStyle: TextStyle(color: Colors.white24, fontSize: 11),
                    isDense: true, border: OutlineInputBorder(),
                    prefixText: '\$ ', prefixStyle: TextStyle(color: Colors.white70),
                  ),
                ),
                const SizedBox(height: 10),
                // 6. GPS (opcional)
                TextField(
                  controller: gpsCtrl,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    labelText: 'Link GPS (opcional)',
                    labelStyle: const TextStyle(color: Colors.white54, fontSize: 13),
                    hintText: 'Pega un link de Google Maps',
                    hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
                    isDense: true, border: const OutlineInputBorder(),
                    suffixIcon: gpsLat != null
                        ? const Icon(Icons.gps_fixed, color: Color(0xff3AF500), size: 18)
                        : const Icon(Icons.gps_not_fixed, color: Colors.white38, size: 18),
                  ),
                  onChanged: (v) {
                    if (v.trim().isEmpty) { setD(() { gpsLat = null; gpsLng = null; }); return; }
                    final p = _parseGps(v.trim());
                    setD(() { gpsLat = p.$1; gpsLng = p.$2; });
                  },
                ),
                if (gpsLat != null)
                  Padding(padding: const EdgeInsets.only(top: 4), child: Row(children: [
                    const Icon(Icons.check_circle, color: Color(0xff3AF500), size: 13),
                    const SizedBox(width: 4),
                    Text('GPS: ${gpsLat!.toStringAsFixed(5)}, ${gpsLng!.toStringAsFixed(5)}',
                        style: const TextStyle(color: Color(0xff3AF500), fontSize: 11)),
                  ])),
                if (existing != null) ...[
                  const SizedBox(height: 10),
                  SwitchListTile(
                    value: activo,
                    onChanged: (v) => setD(() => activo = v),
                    title: const Text('Activa', style: TextStyle(color: Colors.white, fontSize: 13)),
                    dense: true, contentPadding: EdgeInsets.zero,
                  ),
                ],
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx),
                  child: const Text('CANCELAR', style: TextStyle(color: Colors.white54))),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xff3AF500)),
                onPressed: () async {
                  final nombre = nombreCtrl.text.trim();
                  final direccion = direccionCtrl.text.trim();
                  if (nombre.isEmpty || direccion.isEmpty) {
                    ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                        content: Text('Nombre y dirección son obligatorios')));
                    return;
                  }
                  // #109 — detectar duplicado
                  final dup = _dirs.any((d) =>
                      (d['nombre'] ?? '').toString().toLowerCase() ==
                          nombre.toLowerCase() &&
                      d['municipio'] == municipio &&
                      (existing == null || d['id'] != existing['id']));
                  if (dup) {
                    ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                      content: Text(
                          '⚠️ Ya existe una dirección con ese nombre en este municipio'),
                      backgroundColor: Colors.orange,
                    ));
                    return;
                  }
                  final userId = _userSel!['id'] as int;
                  int newDirId;
                  if (existing == null) {
                    final res = await _db.from('red_dir_catalogo').insert({
                      'nombre': nombre,
                      if (aliasCtrl.text.trim().isNotEmpty) 'alias': aliasCtrl.text.trim(),
                      'direccion': direccion.toUpperCase(),
                      if (municipio != null) 'municipio': municipio,
                      'sector_id': sectorId, 'activo': true,
                      if (gpsLat != null) 'lat': gpsLat,
                      if (gpsLng != null) 'lng': gpsLng,
                    }).select('id').single();
                    newDirId = res['id'] as int;
                  } else {
                    await _db.from('red_dir_catalogo').update({
                      'nombre': nombre,
                      'alias': aliasCtrl.text.trim().isEmpty ? null : aliasCtrl.text.trim(),
                      'direccion': direccion.toUpperCase(),
                      'municipio': municipio, 'sector_id': sectorId, 'activo': activo,
                      'lat': gpsLat, 'lng': gpsLng,
                    }).eq('id', existing['id']);
                    newDirId = existing['id'] as int;
                  }
                  final precioTexto = precioCtrl.text.trim();
                  final precio = int.tryParse(precioTexto);
                  if (precio != null && precio > 0) {
                    await _db.from('se_precios_dir').delete()
                        .eq('usuario_id', userId).eq('dir_id', newDirId);
                    await _db.from('se_precios_dir').insert({
                      'usuario_id': userId, 'dir_id': newDirId, 'precio': precio,
                    });
                  } else if (precioTexto.isEmpty) {
                    // #102 — vacío → eliminar precio existente
                    await _db.from('se_precios_dir').delete()
                        .eq('usuario_id', userId).eq('dir_id', newDirId);
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                  await _cargarUser(userId);
                },
                child: Text(existing != null ? 'GUARDAR' : 'AGREGAR',
                    style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
    nombreCtrl.dispose(); aliasCtrl.dispose(); direccionCtrl.dispose();
    precioCtrl.dispose(); gpsCtrl.dispose();
  }

  Future<void> _eliminarDir(Map<String, dynamic> dir) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('¿Eliminar dirección?',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(dir['nombre'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(dir['direccion']?.toString() ?? '',
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 8),
          const Text('Se eliminará del catálogo global y de todos los usuarios.',
              style: TextStyle(color: Colors.orange, fontSize: 12)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('CANCELAR', style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ELIMINAR', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _db.from('red_dir_catalogo').delete().eq('id', dir['id']);
    await _cargarUser(_userSel!['id'] as int);
  }

  // ── BUILD ───────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Red de Direcciones SE',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.list_alt_outlined, color: Colors.white70),
            tooltip: 'Listas plantilla',
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const _PanelListasPrecios())),
          ),
        ],
        bottom: TabBar(
          controller: _tab,
          labelColor: const Color(0xff3AF500),
          unselectedLabelColor: Colors.white54,
          indicatorColor: const Color(0xff3AF500),
          tabs: const [
            Tab(icon: Icon(Icons.grid_view_rounded, size: 16), text: 'Sectores/Barrios'),
            Tab(icon: Icon(Icons.place_outlined, size: 16), text: 'Direcciones'),
          ],
        ),
      ),
      body: _cargandoInicial
          ? const Center(child: CircularProgressIndicator(color: Color(0xff3AF500)))
          : Column(children: [
              _buildUserSelector(),
              Expanded(child: TabBarView(
                controller: _tab,
                children: [_tabSectores(), _tabDirecciones()],
              )),
            ]),
      floatingActionButton: _tab.index == 0
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_userSel != null) ...[
                  FloatingActionButton(
                    mini: true,
                    heroTag: 'sec_menu',
                    backgroundColor: Colors.white12,
                    onPressed: () => _mostrarMenuMasivo(isSector: true),
                    child: const Icon(Icons.more_vert, color: Colors.white70, size: 20),
                  ),
                  const SizedBox(width: 8),
                ],
                FloatingActionButton.extended(
                  heroTag: 'sec_add',
                  backgroundColor: const Color(0xff3AF500),
                  onPressed: _abrirFormSector,
                  icon: const Icon(Icons.add, color: Colors.black),
                  label: const Text('Nuevo sector',
                      style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                ),
              ],
            )
          : _userSel != null
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FloatingActionButton(
                      mini: true,
                      heroTag: 'dir_menu',
                      backgroundColor: Colors.white12,
                      onPressed: () => _mostrarMenuMasivo(isSector: false),
                      child: const Icon(Icons.more_vert, color: Colors.white70, size: 20),
                    ),
                    const SizedBox(width: 8),
                    FloatingActionButton.extended(
                      heroTag: 'dir_add',
                      backgroundColor: const Color(0xff3AF500),
                      onPressed: () => _formDir(),
                      icon: const Icon(Icons.add_location_alt, color: Colors.black),
                      label: const Text('Nueva dirección',
                          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                    ),
                  ],
                )
              : null,
    );
  }

  Widget _buildUserSelector() {
    return Container(
      color: const Color(0xFF111111),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: DropdownButtonFormField<int>(
        value: _userSel?['id'] as int?,
        dropdownColor: const Color(0xFF1A1A1A),
        style: const TextStyle(color: Colors.white, fontSize: 13),
        decoration: InputDecoration(
          labelText: 'Usuario (local / cliente)',
          labelStyle: const TextStyle(color: Colors.white54, fontSize: 12),
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Colors.white24),
          ),
          prefixIcon: const Icon(Icons.person_search, color: Colors.white38, size: 18),
        ),
        items: _usuarios.map((u) => DropdownMenuItem<int>(
          value: u['id'] as int,
          child: Text(_etiqueta(u), style: const TextStyle(color: Colors.white, fontSize: 13)),
        )).toList(),
        onChanged: (id) {
          final u = _usuarios.firstWhere((u) => u['id'] == id);
          setState(() { _userSel = u; _dirs = []; _preciosDir = {}; _tarifaMap = {}; });
          _cargarUser(id!);
        },
        hint: const Text('Selecciona un usuario…', style: TextStyle(color: Colors.white38, fontSize: 13)),
      ),
    );
  }

  // ── Tab 0: Sectores + tarifas por usuario ───────────────────────────────────
  Widget _tabSectores() {
    var raices = _sectoresActivos
        .where((s) =>
            s['municipio']?.toString() == _secFiltroMun &&
            s['parent_id'] == null)
        .toList();
    if (_secFiltroSector != null) {
      raices = raices.where((s) => s['id'] == _secFiltroSector).toList();
    }
    raices.sort((a, b) =>
        (a['nombre'] ?? '').toString().compareTo((b['nombre'] ?? '').toString()));
    // Expandir: sector raíz + sus barrios ordenados
    var filtrados = <Map<String, dynamic>>[];
    for (final s in raices) {
      filtrados.add({...s, '_tipo': 'sector'});
      final barrios = _sectoresActivos
          .where((b) => b['parent_id'] == s['id'])
          .toList()
        ..sort((a, b) => (a['nombre'] ?? '').toString()
            .compareTo((b['nombre'] ?? '').toString()));
      for (final b in barrios) {
        filtrados.add({...b, '_tipo': 'barrio'});
      }
    }
    // #99 — búsqueda
    if (_secBusqueda.isNotEmpty) {
      filtrados = filtrados.where((s) =>
          (s['nombre'] ?? '').toString().toLowerCase().contains(_secBusqueda)).toList();
    }
    // #108 — filtro incompleto
    if (_secFiltroIncompleto == 'sinPrecio') {
      filtrados = filtrados.where((s) =>
          _userSel == null || !_tarifaMap.containsKey(s['id'] as int)).toList();
    } else if (_secFiltroIncompleto == 'inactivo') {
      filtrados = filtrados.where((s) => s['activo'] == false).toList();
    }

    return Column(children: [
      // Chips municipio centrados
      Container(
        color: const Color(0xFF111111),
        height: 42,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: _municipios.map((m) {
            final sel = _secFiltroMun == m;
            return GestureDetector(
              onTap: () => setState(() { _secFiltroMun = m; _secFiltroSector = null; }),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: sel ? const Color(0xff3AF500) : const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: sel ? const Color(0xff3AF500) : Colors.white24),
                ),
                child: Text(m, style: TextStyle(
                  color: sel ? Colors.black : Colors.white54,
                  fontSize: 12, fontWeight: sel ? FontWeight.bold : FontWeight.normal,
                )),
              ),
            );
          }).toList(),
        ),
      ),
      // Dropdown sector
      Builder(builder: (ctx) {
        final subSecs = _sectoresActivos
            .where((s) => s['municipio'] == _secFiltroMun && s['parent_id'] == null)
            .toList()
          ..sort((a, b) => (a['nombre'] ?? '').toString()
              .compareTo((b['nombre'] ?? '').toString()));
        if (subSecs.isEmpty) return const SizedBox.shrink();
        return Container(
          color: const Color(0xFF0D0D0D),
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
          child: DropdownButtonFormField<int?>(
            value: _secFiltroSector,
            dropdownColor: const Color(0xFF1A1A1A),
            style: const TextStyle(color: Colors.white, fontSize: 12),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Colors.white24),
              ),
              prefixIcon: const Icon(Icons.map_outlined, color: Colors.white38, size: 16),
            ),
            items: [
              const DropdownMenuItem<int?>(value: null, child: Text('Todos los sectores', style: TextStyle(color: Colors.white54))),
              ...subSecs.map((s) => DropdownMenuItem<int?>(
                value: s['id'] as int?,
                child: Text(s['nombre']?.toString() ?? '', style: const TextStyle(color: Colors.white)),
              )),
            ],
            onChanged: (v) => setState(() => _secFiltroSector = v),
          ),
        );
      }),
      const Divider(height: 1, color: Colors.white12),
      // #99 — barra de búsqueda
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: TextField(
          controller: _secBusquedaCtrl,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: InputDecoration(
            hintText: 'Buscar sector o barrio…',
            hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
            prefixIcon: const Icon(Icons.search, color: Colors.white38, size: 18),
            suffixIcon: _secBusqueda.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, color: Colors.white38, size: 16),
                    onPressed: () => _secBusquedaCtrl.clear(),
                  )
                : null,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
            filled: true, fillColor: const Color(0xFF1A1A1A),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
          ),
        ),
      ),
      // chips filtro incompleto — siempre visibles
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
        child: Row(children: [
          _chipFiltro('Todos', null, _secFiltroIncompleto,
              (v) => setState(() => _secFiltroIncompleto = v)),
          _chipFiltro('Sin precio', 'sinPrecio', _secFiltroIncompleto,
              (v) => setState(() => _secFiltroIncompleto = v)),
          _chipFiltro('Inactivos', 'inactivo', _secFiltroIncompleto,
              (v) => setState(() => _secFiltroIncompleto = v)),
        ]),
      ),
      Expanded(
        child: filtrados.isEmpty
            ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.map_outlined, color: Colors.white24, size: 48),
                const SizedBox(height: 12),
                Text('Sin sectores en $_secFiltroMun',
                    style: const TextStyle(color: Colors.white38)),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: _abrirFormSector,
                  icon: const Icon(Icons.add, color: Color(0xff3AF500)),
                  label: const Text('Crear primer sector',
                      style: TextStyle(color: Color(0xff3AF500))),
                ),
              ]))
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 100),
                itemCount: filtrados.length,
                itemBuilder: (_, i) {
                  final s = filtrados[i];
                  final esBarrio = s['_tipo'] == 'barrio';
                  final sId = s['id'] as int;
                  final activo = s['activo'] as bool? ?? true;
                  final tarifa = _tarifaMap[sId];
                  return Padding(
                    padding: EdgeInsets.only(left: esBarrio ? 20 : 0, bottom: 6),
                    child: Container(
                      decoration: BoxDecoration(
                        color: activo ? const Color(0xFF1A1A1A) : const Color(0xFF111111),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: activo
                              ? const Color(0xff3AF500).withValues(alpha: 0.3)
                              : Colors.white12,
                        ),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                        leading: CircleAvatar(
                          radius: esBarrio ? 14 : 18,
                          backgroundColor: activo
                              ? (esBarrio
                                  ? const Color(0xff3AF500).withValues(alpha: 0.12)
                                  : const Color(0xff3AF500).withValues(alpha: 0.22))
                              : Colors.grey[800],
                          child: Icon(
                            esBarrio ? Icons.location_city : Icons.map,
                            color: activo ? const Color(0xff3AF500) : Colors.white38,
                            size: esBarrio ? 14 : 18,
                          ),
                        ),
                        title: Text(
                          s['nombre']?.toString() ?? '',
                          style: TextStyle(
                            color: activo ? Colors.white : Colors.white38,
                            fontWeight: esBarrio ? FontWeight.normal : FontWeight.bold,
                            fontSize: esBarrio ? 12 : 13,
                          ),
                        ),
                        subtitle: Row(
                          children: [
                            GestureDetector(
                              onTap: () async {
                                await _db.from('sectores').update({'activo': !activo}).eq('id', sId);
                                await _cargarInicial();
                              },
                              child: Text(
                                activo ? 'Activo' : 'Inactivo',
                                style: TextStyle(
                                  color: activo ? const Color(0xff3AF500) : Colors.red,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                            if (_userSel != null) ...[
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: () => _editarTarifaDialog(sId, tarifa),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: tarifa != null
                                        ? Colors.green.withValues(alpha: 0.2)
                                        : Colors.orange.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: tarifa != null
                                          ? Colors.green.withValues(alpha: 0.6)
                                          : Colors.orange.withValues(alpha: 0.5),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        tarifa != null ? Icons.attach_money : Icons.add,
                                        size: 11,
                                        color: tarifa != null ? Colors.greenAccent : Colors.orange,
                                      ),
                                      Text(
                                        tarifa != null ? '\$${_miles(tarifa)}' : 'Asignar tarifa',
                                        style: TextStyle(
                                          color: tarifa != null ? Colors.greenAccent : Colors.orange,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, color: Color(0xff3AF500), size: 20),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                              onPressed: () => _abrirFormSector(sector: s),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                              onPressed: () => _eliminarSector(s),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
      ),
    ]);
  }

  // ── Tab 1: Direcciones ──────────────────────────────────────────────────────
  Widget _tabDirecciones() {
    if (_cargandoUser) return const Center(child: CircularProgressIndicator(color: Color(0xff3AF500)));

    var filtradas = _dirs
        .where((d) => d['municipio']?.toString() == _dirFiltroMun)
        .toList();
    // #101 — jerarquía sector > barrio
    if (_dirFiltroSector != null) {
      if (_dirFiltroBarrio != null) {
        filtradas = filtradas.where((d) => d['sector_id'] == _dirFiltroBarrio).toList();
      } else {
        final secIds = _sectoresActivos
            .where((s) => s['id'] == _dirFiltroSector || s['parent_id'] == _dirFiltroSector)
            .map<int>((s) => s['id'] as int).toList();
        filtradas = filtradas.where((d) => secIds.contains(d['sector_id'] as int?)).toList();
      }
    }
    // #99 — búsqueda
    if (_dirBusqueda.isNotEmpty) {
      filtradas = filtradas.where((d) {
        final n = (d['nombre'] ?? '').toString().toLowerCase();
        final a = (d['alias'] ?? '').toString().toLowerCase();
        final dir = (d['direccion'] ?? '').toString().toLowerCase();
        return n.contains(_dirBusqueda) || a.contains(_dirBusqueda) || dir.contains(_dirBusqueda);
      }).toList();
    }
    // #108 — filtro incompleto
    if (_dirFiltroIncompleto == 'sinPrecio') {
      filtradas = filtradas
          .where((d) => !_preciosDir.containsKey(d['id'] as int)).toList();
    } else if (_dirFiltroIncompleto == 'sinGps') {
      filtradas = filtradas
          .where((d) => d['lat'] == null || d['lng'] == null).toList();
    } else if (_dirFiltroIncompleto == 'inactivo') {
      filtradas = filtradas.where((d) => d['activo'] == false).toList();
    }
    filtradas.sort((a, b) =>
        (a['nombre'] ?? '').toString().compareTo((b['nombre'] ?? '').toString()));

    return Column(children: [
      // Chips municipio centrados
      Container(
        color: const Color(0xFF111111),
        height: 42,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: _municipios.map((m) {
            final sel = _dirFiltroMun == m;
            return GestureDetector(
              onTap: () => setState(() {
                _dirFiltroMun = m;
                _dirFiltroSector = null;
                _dirFiltroBarrio = null; // #101
              }),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: sel ? const Color(0xff3AF500) : const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: sel ? const Color(0xff3AF500) : Colors.white24),
                ),
                child: Text(m, style: TextStyle(
                  color: sel ? Colors.black : Colors.white54,
                  fontSize: 12, fontWeight: sel ? FontWeight.bold : FontWeight.normal,
                )),
              ),
            );
          }).toList(),
        ),
      ),
      // #101 — Dropdown sector (solo raíces) + barrio sub-dropdown
      Builder(builder: (ctx) {
        final raices = _sectoresActivos
            .where((s) => s['municipio'] == _dirFiltroMun && s['parent_id'] == null)
            .toList()
          ..sort((a, b) => (a['nombre'] ?? '').toString()
              .compareTo((b['nombre'] ?? '').toString()));
        if (raices.isEmpty) return const SizedBox.shrink();
        final barrios = _dirFiltroSector != null
            ? (_sectoresActivos
                .where((s) => s['parent_id'] == _dirFiltroSector)
                .toList()
              ..sort((a, b) => (a['nombre'] ?? '').toString()
                  .compareTo((b['nombre'] ?? '').toString())))
            : <Map<String, dynamic>>[];
        return Column(children: [
          Container(
            color: const Color(0xFF0D0D0D),
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
            child: DropdownButtonFormField<int?>(
              value: _dirFiltroSector,
              dropdownColor: const Color(0xFF1A1A1A),
              style: const TextStyle(color: Colors.white, fontSize: 12),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Colors.white24),
                ),
                prefixIcon: const Icon(Icons.map_outlined, color: Colors.white38, size: 16),
              ),
              items: [
                const DropdownMenuItem<int?>(value: null,
                    child: Text('Todos los sectores', style: TextStyle(color: Colors.white54))),
                ...raices.map((s) => DropdownMenuItem<int?>(
                      value: s['id'] as int?,
                      child: Text(s['nombre']?.toString() ?? '',
                          style: const TextStyle(color: Colors.white)),
                    )),
              ],
              onChanged: (v) => setState(() {
                _dirFiltroSector = v;
                _dirFiltroBarrio = null;
              }),
            ),
          ),
          if (barrios.isNotEmpty)
            Container(
              color: const Color(0xFF0A0A0A),
              padding: const EdgeInsets.fromLTRB(24, 0, 12, 4),
              child: DropdownButtonFormField<int?>(
                value: _dirFiltroBarrio,
                dropdownColor: const Color(0xFF1A1A1A),
                style: const TextStyle(color: Colors.white, fontSize: 12),
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Colors.white12),
                  ),
                  prefixIcon: const Icon(Icons.location_city, color: Colors.white24, size: 15),
                ),
                items: [
                  const DropdownMenuItem<int?>(value: null,
                      child: Text('Todos los barrios', style: TextStyle(color: Colors.white38))),
                  ...barrios.map((b) => DropdownMenuItem<int?>(
                        value: b['id'] as int?,
                        child: Text(b['nombre']?.toString() ?? '',
                            style: const TextStyle(color: Colors.white)),
                      )),
                ],
                onChanged: (v) => setState(() => _dirFiltroBarrio = v),
              ),
            ),
        ]);
      }),
      const Divider(height: 1, color: Colors.white12),
      // #99 — barra de búsqueda
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: TextField(
          controller: _dirBusquedaCtrl,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: InputDecoration(
            hintText: 'Buscar por nombre, alias o dirección…',
            hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
            prefixIcon: const Icon(Icons.search, color: Colors.white38, size: 18),
            suffixIcon: _dirBusqueda.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, color: Colors.white38, size: 16),
                    onPressed: () => _dirBusquedaCtrl.clear(),
                  )
                : null,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
            filled: true, fillColor: const Color(0xFF1A1A1A),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
          ),
        ),
      ),
      // chips filtro incompleto — siempre visibles
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
        child: Row(children: [
          _chipFiltro('Todos', null, _dirFiltroIncompleto,
              (v) => setState(() => _dirFiltroIncompleto = v)),
          _chipFiltro('Sin precio', 'sinPrecio', _dirFiltroIncompleto,
              (v) => setState(() => _dirFiltroIncompleto = v)),
          _chipFiltro('Sin GPS', 'sinGps', _dirFiltroIncompleto,
              (v) => setState(() => _dirFiltroIncompleto = v)),
          _chipFiltro('Inactivas', 'inactivo', _dirFiltroIncompleto,
              (v) => setState(() => _dirFiltroIncompleto = v)),
        ]),
      ),
      Expanded(
        child: _dirs.isEmpty && _userSel == null
            ? _noUserPlaceholder('Selecciona un usuario para ver\nsus direcciones')
            : filtradas.isEmpty
                ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.add_location_alt, color: Colors.white24, size: 48),
                    const SizedBox(height: 12),
                    Text('Sin direcciones en $_dirFiltroMun',
                        style: const TextStyle(color: Colors.white38)),
                    const SizedBox(height: 8),
                    if (_userSel != null)
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xff3AF500)),
                        onPressed: () => _formDir(),
                        icon: const Icon(Icons.add, color: Colors.black, size: 16),
                        label: const Text('Agregar',
                            style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                      ),
                  ]))
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 100),
                    itemCount: filtradas.length,
                    itemBuilder: (_, i) {
                      final d = filtradas[i];
                      final dId = d['id'] as int;
                      final activo = d['activo'] != false;
                      final precio = _preciosDir[dId];
                      final sectorNombre = d['sector_id'] != null
                          ? _sectoresActivos
                              .where((s) => s['id'] == d['sector_id'])
                              .map((s) => s['nombre']?.toString())
                              .firstOrNull
                          : null;
                      return Card(
                        color: const Color(0xFF1A1A1A),
                        margin: const EdgeInsets.only(bottom: 6),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                          leading: CircleAvatar(
                            backgroundColor: activo
                                ? const Color(0xff3AF500).withValues(alpha: 0.15)
                                : Colors.white10,
                            child: Icon(Icons.place,
                                color: activo ? const Color(0xff3AF500) : Colors.white24, size: 18),
                          ),
                          title: Row(children: [
                            Expanded(child: Text(d['nombre']?.toString() ?? '',
                                style: TextStyle(
                                  color: activo ? Colors.white : Colors.white38,
                                  fontWeight: FontWeight.w600, fontSize: 13,
                                ))),
                            if (sectorNombre != null)
                              Container(
                                margin: const EdgeInsets.only(left: 6),
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xff3AF500).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: const Color(0xff3AF500).withValues(alpha: 0.4)),
                                ),
                                child: Text(sectorNombre,
                                    style: const TextStyle(color: Color(0xff3AF500), fontSize: 10)),
                              ),
                          ]),
                          subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            if ((d['direccion']?.toString() ?? '').isNotEmpty)
                              Text(d['direccion'].toString(),
                                  style: TextStyle(
                                    color: activo ? Colors.white54 : Colors.white24, fontSize: 11)),
                            Row(children: [
                              Icon(
                                precio != null ? Icons.attach_money : Icons.money_off,
                                size: 13,
                                color: precio != null ? Colors.greenAccent : Colors.orange,
                              ),
                              Text(
                                precio != null ? '\$${_fmt(precio)}' : 'Sin precio',
                                style: TextStyle(
                                  color: precio != null ? Colors.greenAccent : Colors.orange,
                                  fontWeight: FontWeight.bold, fontSize: 12,
                                ),
                              ),
                            ]),
                          ]),
                          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                            IconButton(
                              icon: const Icon(Icons.edit, color: Color(0xff3AF500), size: 18),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                              onPressed: () => _formDir(existing: d),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.red, size: 18),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                              onPressed: () => _eliminarDir(d),
                            ),
                          ]),
                        ),
                      );
                    },
                  ),
      ),
    ]);
  }

  // ── Chip filtro helper (#108) ────────────────────────────────────────────────
  Widget _chipFiltro(String label, String? valor, String? actual, void Function(String?) onTap) {
    final sel = actual == valor;
    return GestureDetector(
      onTap: () => onTap(sel ? null : valor),
      child: Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: sel ? const Color(0xff3AF500).withValues(alpha: 0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: sel ? const Color(0xff3AF500) : Colors.white24,
          ),
        ),
        child: Text(label, style: TextStyle(
          color: sel ? const Color(0xff3AF500) : Colors.white54,
          fontSize: 11, fontWeight: sel ? FontWeight.bold : FontWeight.normal,
        )),
      ),
    );
  }

  // ── Menú masivo / copiar (#105, #106) ────────────────────────────────────────
  void _mostrarMenuMasivo({required bool isSector}) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          Container(width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.price_change_outlined, color: Color(0xff3AF500)),
            title: Text(
              isSector ? 'Actualizar precios de sectores' : 'Actualizar precios de direcciones',
              style: const TextStyle(color: Colors.white),
            ),
            subtitle: const Text('Sumar o restar \$X a todos los precios del usuario',
                style: TextStyle(color: Colors.white54, fontSize: 12)),
            onTap: () {
              Navigator.pop(context);
              isSector ? _actualizarMasivoSectores() : _actualizarMasivoDirs();
            },
          ),
          ListTile(
            leading: const Icon(Icons.copy_outlined, color: Color(0xff3AF500)),
            title: Text(
              isSector ? 'Copiar tarifas de otro usuario' : 'Copiar precios de otro usuario',
              style: const TextStyle(color: Colors.white),
            ),
            subtitle: const Text('Reemplaza los precios actuales con los del usuario elegido',
                style: TextStyle(color: Colors.white54, fontSize: 12)),
            onTap: () {
              Navigator.pop(context);
              _copiarDeUsuario(isSector: isSector);
            },
          ),
          ListTile(
            leading: const Icon(Icons.list_alt_outlined, color: Color(0xff3AF500)),
            title: Text(
              isSector ? 'Copiar desde lista plantilla' : 'Copiar desde lista plantilla',
              style: const TextStyle(color: Colors.white),
            ),
            subtitle: const Text('Aplica una lista de precios estandarizada',
                style: TextStyle(color: Colors.white54, fontSize: 12)),
            onTap: () {
              Navigator.pop(context);
              _copiarDeLista(isSector: isSector);
            },
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  // #105 — Actualización masiva sectores
  Future<void> _actualizarMasivoSectores() async {
    if (_userSel == null) return;
    final deltaCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Actualizar precios de sectores',
            style: TextStyle(color: Colors.white, fontSize: 15)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Se sumará o restará este valor a todos los sectores con precio asignado.',
              style: TextStyle(color: Colors.white54, fontSize: 12)),
          const SizedBox(height: 12),
          TextField(
            controller: deltaCtrl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(signed: true),
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'Ajuste (\$ positivo o negativo)',
              labelStyle: TextStyle(color: Colors.white54),
              prefixText: '\$ ', prefixStyle: TextStyle(color: Colors.white70),
              hintText: 'Ej: 500 o -500', hintStyle: TextStyle(color: Colors.white24),
              isDense: true, border: OutlineInputBorder(),
            ),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('CANCELAR', style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xff3AF500)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('APLICAR', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final delta = int.tryParse(deltaCtrl.text.trim());
    if (delta == null || delta == 0) return;
    final userId = _userSel!['id'] as int;
    final List<Map<String, dynamic>> nuevas = [];
    for (final entry in _tarifaMap.entries) {
      final nuevoPrecio = (entry.value + delta).clamp(0, 9999999);
      if (nuevoPrecio > 0) {
        nuevas.add({'usuario_id': userId, 'sector_id': entry.key, 'precio': nuevoPrecio});
      }
    }
    if (nuevas.isNotEmpty) {
      await _db.from('tarifas_usuario_sector').upsert(nuevas, onConflict: 'usuario_id, sector_id');
    }
    await _cargarUser(userId);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${nuevas.length} sector(es) actualizados'),
        backgroundColor: Colors.green,
      ));
    }
  }

  // #105 — Actualización masiva dirs
  Future<void> _actualizarMasivoDirs() async {
    if (_userSel == null) return;
    final deltaCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Actualizar precios de direcciones',
            style: TextStyle(color: Colors.white, fontSize: 15)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Se sumará o restará este valor a todas las direcciones con precio asignado.',
              style: TextStyle(color: Colors.white54, fontSize: 12)),
          const SizedBox(height: 12),
          TextField(
            controller: deltaCtrl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(signed: true),
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'Ajuste (\$ positivo o negativo)',
              labelStyle: TextStyle(color: Colors.white54),
              prefixText: '\$ ', prefixStyle: TextStyle(color: Colors.white70),
              hintText: 'Ej: 500 o -500', hintStyle: TextStyle(color: Colors.white24),
              isDense: true, border: OutlineInputBorder(),
            ),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('CANCELAR', style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xff3AF500)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('APLICAR', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final delta = int.tryParse(deltaCtrl.text.trim());
    if (delta == null || delta == 0) return;
    final userId = _userSel!['id'] as int;
    final List<Map<String, dynamic>> nuevos = [];
    for (final entry in _preciosDir.entries) {
      final nuevoPrecio = (entry.value + delta).clamp(0, 9999999);
      if (nuevoPrecio > 0) {
        nuevos.add({'usuario_id': userId, 'dir_id': entry.key, 'precio': nuevoPrecio});
      }
    }
    if (nuevos.isNotEmpty) {
      await _db.from('se_precios_dir').upsert(nuevos, onConflict: 'usuario_id, dir_id');
    }
    await _cargarUser(userId);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${nuevos.length} dirección(es) actualizadas'),
        backgroundColor: Colors.green,
      ));
    }
  }

  // #106 — Copiar precios de otro usuario
  Future<void> _copiarDeUsuario({required bool isSector}) async {
    if (_userSel == null) return;
    final currentId = _userSel!['id'] as int;
    final otros = _usuarios.where((u) => u['id'] != currentId).toList();
    if (otros.isEmpty) return;
    int? fuenteId;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: Text(
            isSector ? 'Copiar tarifas de sectores' : 'Copiar precios de direcciones',
            style: const TextStyle(color: Colors.white, fontSize: 15),
          ),
          content: DropdownButtonFormField<int>(
            value: fuenteId,
            dropdownColor: const Color(0xFF1A1A1A),
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'Copiar desde...', labelStyle: TextStyle(color: Colors.white54),
              isDense: true, border: OutlineInputBorder(),
            ),
            items: otros.map((u) => DropdownMenuItem<int>(
              value: u['id'] as int,
              child: Text(_etiqueta(u), style: const TextStyle(color: Colors.white, fontSize: 13)),
            )).toList(),
            onChanged: (v) => setD(() => fuenteId = v),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false),
                child: const Text('CANCELAR', style: TextStyle(color: Colors.white54))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xff3AF500)),
              onPressed: fuenteId == null ? null : () => Navigator.pop(ctx, true),
              child: const Text('COPIAR', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
    if (ok != true || fuenteId == null) return;
    if (isSector) {
      final fuente = await _db.from('tarifas_usuario_sector')
          .select('sector_id, precio').eq('usuario_id', fuenteId!);
      final rows = (fuente as List).map((r) => {
        'usuario_id': currentId,
        'sector_id': r['sector_id'],
        'precio': r['precio'],
      }).toList();
      if (rows.isNotEmpty) {
        await _db.from('tarifas_usuario_sector').upsert(rows, onConflict: 'usuario_id, sector_id');
      }
    } else {
      final fuente = await _db.from('se_precios_dir')
          .select('dir_id, precio').eq('usuario_id', fuenteId!);
      final rows = (fuente as List).map((r) => {
        'usuario_id': currentId,
        'dir_id': r['dir_id'],
        'precio': r['precio'],
      }).toList();
      if (rows.isNotEmpty) {
        await _db.from('se_precios_dir').upsert(rows, onConflict: 'usuario_id, dir_id');
      }
    }
    await _cargarUser(currentId);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('✅ Precios copiados correctamente'),
        backgroundColor: Colors.green,
      ));
    }
  }

  // #106b — Copiar desde lista plantilla
  Future<void> _copiarDeLista({required bool isSector}) async {
    if (_userSel == null) return;
    final listas = await _db.from('listas_precios').select().order('nombre');
    final listasList = List<Map<String, dynamic>>.from(listas);
    if (listasList.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No hay listas plantilla creadas. Créalas con el botón ☰ arriba.'),
          backgroundColor: Colors.orange,
        ));
      }
      return;
    }
    int? listaId;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: Text(
            isSector ? 'Aplicar lista: sectores' : 'Aplicar lista: direcciones',
            style: const TextStyle(color: Colors.white, fontSize: 15),
          ),
          content: DropdownButtonFormField<int>(
            value: listaId,
            dropdownColor: const Color(0xFF1A1A1A),
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'Lista plantilla',
              labelStyle: TextStyle(color: Colors.white54),
              isDense: true, border: OutlineInputBorder(),
            ),
            items: listasList.map((l) => DropdownMenuItem<int>(
              value: l['id'] as int,
              child: Text(l['nombre']?.toString() ?? '',
                  style: const TextStyle(color: Colors.white, fontSize: 13)),
            )).toList(),
            onChanged: (v) => setD(() => listaId = v),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false),
                child: const Text('CANCELAR', style: TextStyle(color: Colors.white54))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xff3AF500)),
              onPressed: listaId == null ? null : () => Navigator.pop(ctx, true),
              child: const Text('APLICAR',
                  style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
    if (ok != true || listaId == null) return;
    final currentId = _userSel!['id'] as int;
    if (isSector) {
      final rows = await _db.from('lista_precios_sectores')
          .select('sector_id, precio').eq('lista_id', listaId!);
      final upsert = (rows as List).map((r) => {
        'usuario_id': currentId, 'sector_id': r['sector_id'], 'precio': r['precio'],
      }).toList();
      if (upsert.isNotEmpty) {
        await _db.from('tarifas_usuario_sector')
            .upsert(upsert, onConflict: 'usuario_id, sector_id');
      }
    } else {
      final rows = await _db.from('lista_precios_dirs')
          .select('dir_id, precio').eq('lista_id', listaId!);
      final upsert = (rows as List).map((r) => {
        'usuario_id': currentId, 'dir_id': r['dir_id'], 'precio': r['precio'],
      }).toList();
      if (upsert.isNotEmpty) {
        await _db.from('se_precios_dir')
            .upsert(upsert, onConflict: 'usuario_id, dir_id');
      }
    }
    await _cargarUser(currentId);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('✅ Lista aplicada correctamente'),
        backgroundColor: Colors.green,
      ));
    }
  }

  Widget _noUserPlaceholder(String msg) => Center(
    child: Text(msg, textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white38, fontSize: 14)),
  );
}

// ════════════════════════════════════════════════════════════
//  PANEL: Listas de Precios Plantilla
// ════════════════════════════════════════════════════════════

class _PanelListasPrecios extends StatefulWidget {
  const _PanelListasPrecios();
  @override
  State<_PanelListasPrecios> createState() => _PanelListasPreciosState();
}

class _PanelListasPreciosState extends State<_PanelListasPrecios> {
  final _db = Supabase.instance.client;
  List<Map<String, dynamic>> _listas = [];
  bool _cargando = true;

  @override
  void initState() { super.initState(); _cargar(); }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final data = await _db.from('listas_precios').select().order('nombre');
    if (mounted) setState(() {
      _listas = List<Map<String, dynamic>>.from(data);
      _cargando = false;
    });
  }

  Future<void> _crearLista() async {
    final nombreCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Nueva lista de precios',
            style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: nombreCtrl, autofocus: true,
            style: const TextStyle(color: Colors.white),
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Nombre', labelStyle: TextStyle(color: Colors.white54),
              hintText: 'Ej: Lista Boconó, Estándar Centro',
              hintStyle: TextStyle(color: Colors.white24),
              isDense: true, border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: descCtrl,
            style: const TextStyle(color: Colors.white), maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Descripción (opcional)',
              labelStyle: TextStyle(color: Colors.white54),
              isDense: true, border: OutlineInputBorder(),
            ),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('CANCELAR', style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xff3AF500)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('CREAR',
                style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final nombre = nombreCtrl.text.trim();
    if (nombre.isEmpty) return;
    await _db.from('listas_precios').insert({
      'nombre': nombre,
      if (descCtrl.text.trim().isNotEmpty) 'descripcion': descCtrl.text.trim(),
    });
    await _cargar();
  }

  Future<void> _eliminarLista(Map<String, dynamic> lista) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('¿Eliminar lista?',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text('Se eliminará "${lista['nombre']}" y todos sus precios.',
            style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('NO', style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ELIMINAR', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _db.from('listas_precios').delete().eq('id', lista['id']);
    await _cargar();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Listas de precios plantilla',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xff3AF500),
        onPressed: _crearLista,
        icon: const Icon(Icons.add, color: Colors.black),
        label: const Text('Nueva lista',
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: Color(0xff3AF500)))
          : _listas.isEmpty
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.list_alt, color: Colors.white24, size: 56),
                  const SizedBox(height: 12),
                  const Text('Sin listas creadas',
                      style: TextStyle(color: Colors.white38, fontSize: 15)),
                  const SizedBox(height: 6),
                  const Text('Crea una lista de precios plantilla\npara aplicarla a cualquier usuario o sede',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white24, fontSize: 12)),
                ]))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
                  itemCount: _listas.length,
                  itemBuilder: (_, i) {
                    final l = _listas[i];
                    return Card(
                      color: const Color(0xFF1A1A1A),
                      margin: const EdgeInsets.only(bottom: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        contentPadding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                        leading: CircleAvatar(
                          backgroundColor: const Color(0xff3AF500).withValues(alpha: 0.15),
                          child: const Icon(Icons.price_change_outlined,
                              color: Color(0xff3AF500), size: 20),
                        ),
                        title: Text(l['nombre']?.toString() ?? '',
                            style: const TextStyle(
                                color: Colors.white, fontWeight: FontWeight.bold)),
                        subtitle: l['descripcion'] != null
                            ? Text(l['descripcion'].toString(),
                                style: const TextStyle(color: Colors.white54, fontSize: 12))
                            : null,
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(
                            icon: const Icon(Icons.edit_outlined,
                                color: Color(0xff3AF500), size: 20),
                            onPressed: () async {
                              await Navigator.push(context, MaterialPageRoute(
                                  builder: (_) => _PanelDetalleLista(lista: l)));
                              _cargar();
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                            onPressed: () => _eliminarLista(l),
                          ),
                        ]),
                        onTap: () async {
                          await Navigator.push(context, MaterialPageRoute(
                              builder: (_) => _PanelDetalleLista(lista: l)));
                          _cargar();
                        },
                      ),
                    );
                  },
                ),
    );
  }
}

// ════════════════════════════════════════════════════════════
//  PANEL: Detalle de una Lista de Precios
// ════════════════════════════════════════════════════════════

class _PanelDetalleLista extends StatefulWidget {
  final Map<String, dynamic> lista;
  const _PanelDetalleLista({required this.lista});
  @override
  State<_PanelDetalleLista> createState() => _PanelDetalleListaState();
}

class _PanelDetalleListaState extends State<_PanelDetalleLista>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  final _db = Supabase.instance.client;

  List<Map<String, dynamic>> _sectores = [];
  Map<int, int> _tarifasSec = {};
  List<Map<String, dynamic>> _dirs = [];
  Map<int, int> _preciosDir = {};
  bool _cargando = true;

  String _secFiltroMun = 'Cúcuta';
  String _dirFiltroMun = 'Cúcuta';
  int? _dirFiltroSector;

  static const _municipios = ['Cúcuta', 'Los Patios', 'V. Rosario'];

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _tab.addListener(() => setState(() {}));
    _cargar();
  }

  @override
  void dispose() { _tab.dispose(); super.dispose(); }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final listaId = widget.lista['id'] as int;
    final secs = await _db.from('sectores')
        .select('id, nombre, municipio, parent_id, activo').order('municipio').order('nombre');
    final tarifas = await _db.from('lista_precios_sectores')
        .select('sector_id, precio').eq('lista_id', listaId);
    final dirs = await _db.from('red_dir_catalogo')
        .select('id, nombre, alias, direccion, municipio, sector_id, activo').order('municipio').order('nombre');
    final precios = await _db.from('lista_precios_dirs')
        .select('dir_id, precio').eq('lista_id', listaId);
    if (mounted) {
      final tm = <int, int>{};
      for (final t in List<Map<String, dynamic>>.from(tarifas)) {
        tm[t['sector_id'] as int] = (t['precio'] as num).toInt();
      }
      final pm = <int, int>{};
      for (final p in List<Map<String, dynamic>>.from(precios)) {
        pm[p['dir_id'] as int] = (p['precio'] as num).toInt();
      }
      setState(() {
        _sectores = List<Map<String, dynamic>>.from(secs);
        _tarifasSec = tm;
        _dirs = List<Map<String, dynamic>>.from(dirs);
        _preciosDir = pm;
        _cargando = false;
      });
    }
  }

  String _miles(int v) {
    final s = v.toString();
    if (s.length <= 3) return s;
    return '${s.substring(0, s.length - 3)}.${s.substring(s.length - 3)}';
  }

  Future<void> _editarTarifaSector(int sectorId, int? actual) async {
    final ctrl = TextEditingController(text: actual?.toString() ?? '');
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Precio en lista', style: TextStyle(color: Colors.white, fontSize: 15)),
        content: TextField(
          controller: ctrl, keyboardType: TextInputType.number, autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            prefixText: '\$ ', prefixStyle: TextStyle(color: Colors.white54),
            hintText: '0', hintStyle: TextStyle(color: Colors.white38),
            border: OutlineInputBorder(), isDense: true,
          ),
        ),
        actions: [
          if (actual != null)
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                await _db.from('lista_precios_sectores').delete()
                    .eq('lista_id', widget.lista['id']).eq('sector_id', sectorId);
                await _cargar();
              },
              child: const Text('Quitar', style: TextStyle(color: Colors.red)),
            ),
          TextButton(onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar', style: TextStyle(color: Colors.white54))),
          TextButton(
            onPressed: () async {
              final precio = int.tryParse(ctrl.text.trim());
              if (precio != null && precio > 0) {
                Navigator.pop(context);
                await _db.from('lista_precios_sectores').upsert({
                  'lista_id': widget.lista['id'], 'sector_id': sectorId, 'precio': precio,
                }, onConflict: 'lista_id, sector_id');
                await _cargar();
              }
            },
            child: const Text('Guardar', style: TextStyle(color: Color(0xff3AF500))),
          ),
        ],
      ),
    );
  }

  Future<void> _editarPrecioDir(int dirId, int? actual) async {
    final ctrl = TextEditingController(text: actual?.toString() ?? '');
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Precio en lista', style: TextStyle(color: Colors.white, fontSize: 15)),
        content: TextField(
          controller: ctrl, keyboardType: TextInputType.number, autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            prefixText: '\$ ', prefixStyle: TextStyle(color: Colors.white54),
            hintText: '0', hintStyle: TextStyle(color: Colors.white38),
            border: OutlineInputBorder(), isDense: true,
          ),
        ),
        actions: [
          if (actual != null)
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                await _db.from('lista_precios_dirs').delete()
                    .eq('lista_id', widget.lista['id']).eq('dir_id', dirId);
                await _cargar();
              },
              child: const Text('Quitar', style: TextStyle(color: Colors.red)),
            ),
          TextButton(onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar', style: TextStyle(color: Colors.white54))),
          TextButton(
            onPressed: () async {
              final precio = int.tryParse(ctrl.text.trim());
              if (precio != null && precio > 0) {
                Navigator.pop(context);
                await _db.from('lista_precios_dirs').upsert({
                  'lista_id': widget.lista['id'], 'dir_id': dirId, 'precio': precio,
                }, onConflict: 'lista_id, dir_id');
                await _cargar();
              }
            },
            child: const Text('Guardar', style: TextStyle(color: Color(0xff3AF500))),
          ),
        ],
      ),
    );
  }

  Widget _chipMun(String m, String actual, void Function(String) onTap) {
    final sel = actual == m;
    return GestureDetector(
      onTap: () => onTap(m),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: sel ? const Color(0xff3AF500) : const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: sel ? const Color(0xff3AF500) : Colors.white24),
        ),
        child: Text(m, style: TextStyle(
          color: sel ? Colors.black : Colors.white54,
          fontSize: 12, fontWeight: sel ? FontWeight.bold : FontWeight.normal,
        )),
      ),
    );
  }

  Widget _precioBadge(int? precio, void Function() onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: precio != null
              ? Colors.green.withValues(alpha: 0.15)
              : Colors.orange.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: precio != null
                ? Colors.green.withValues(alpha: 0.5)
                : Colors.orange.withValues(alpha: 0.4),
          ),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(precio != null ? Icons.attach_money : Icons.add, size: 13,
              color: precio != null ? Colors.greenAccent : Colors.orange),
          Text(
            precio != null ? '\$${_miles(precio)}' : 'Asignar',
            style: TextStyle(
              color: precio != null ? Colors.greenAccent : Colors.orange,
              fontSize: 11, fontWeight: FontWeight.bold,
            ),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.lista['nombre']?.toString() ?? '',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
          if ((widget.lista['descripcion']?.toString() ?? '').isNotEmpty)
            Text(widget.lista['descripcion'].toString(),
                style: const TextStyle(color: Colors.white54, fontSize: 11)),
        ]),
        bottom: TabBar(
          controller: _tab,
          labelColor: const Color(0xff3AF500),
          unselectedLabelColor: Colors.white54,
          indicatorColor: const Color(0xff3AF500),
          tabs: const [
            Tab(icon: Icon(Icons.grid_view_rounded, size: 16), text: 'Sectores'),
            Tab(icon: Icon(Icons.place_outlined, size: 16), text: 'Direcciones'),
          ],
        ),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: Color(0xff3AF500)))
          : TabBarView(controller: _tab, children: [_tabSectores(), _tabDirs()]),
    );
  }

  Widget _tabSectores() {
    var raices = _sectores
        .where((s) => s['municipio']?.toString() == _secFiltroMun && s['parent_id'] == null)
        .toList()
      ..sort((a, b) => (a['nombre'] ?? '').toString().compareTo((b['nombre'] ?? '').toString()));
    final items = <Map<String, dynamic>>[];
    for (final s in raices) {
      items.add({...s, '_tipo': 'sector'});
      final barrios = _sectores
          .where((b) => b['parent_id'] == s['id'])
          .toList()
        ..sort((a, b) =>
            (a['nombre'] ?? '').toString().compareTo((b['nombre'] ?? '').toString()));
      for (final b in barrios) items.add({...b, '_tipo': 'barrio'});
    }
    return Column(children: [
      Container(
        color: const Color(0xFF111111), height: 42,
        child: Row(mainAxisAlignment: MainAxisAlignment.center,
            children: _municipios
                .map((m) => _chipMun(m, _secFiltroMun,
                    (v) => setState(() => _secFiltroMun = v)))
                .toList()),
      ),
      const Divider(height: 1, color: Colors.white12),
      Expanded(
        child: items.isEmpty
            ? const Center(
                child: Text('Sin sectores', style: TextStyle(color: Colors.white38)))
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 80),
                itemCount: items.length,
                itemBuilder: (_, i) {
                  final s = items[i];
                  final esBarrio = s['_tipo'] == 'barrio';
                  final sId = s['id'] as int;
                  return Padding(
                    padding: EdgeInsets.only(left: esBarrio ? 20 : 0, bottom: 6),
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1A1A),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xff3AF500).withValues(alpha: 0.2)),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                        leading: Icon(
                          esBarrio ? Icons.location_city : Icons.map,
                          color: const Color(0xff3AF500), size: esBarrio ? 16 : 20,
                        ),
                        title: Text(s['nombre']?.toString() ?? '',
                            style: TextStyle(
                              color: Colors.white, fontSize: esBarrio ? 12 : 13,
                              fontWeight: esBarrio ? FontWeight.normal : FontWeight.bold,
                            )),
                        trailing: _precioBadge(_tarifasSec[sId],
                            () => _editarTarifaSector(sId, _tarifasSec[sId])),
                      ),
                    ),
                  );
                },
              ),
      ),
    ]);
  }

  Widget _tabDirs() {
    final secsFilt = _sectores
        .where((s) => s['municipio'] == _dirFiltroMun && s['parent_id'] == null)
        .toList()
      ..sort((a, b) =>
          (a['nombre'] ?? '').toString().compareTo((b['nombre'] ?? '').toString()));
    var filtradas = _dirs.where((d) => d['municipio']?.toString() == _dirFiltroMun).toList();
    if (_dirFiltroSector != null) {
      final secIds = _sectores
          .where((s) => s['id'] == _dirFiltroSector || s['parent_id'] == _dirFiltroSector)
          .map<int>((s) => s['id'] as int).toList();
      filtradas =
          filtradas.where((d) => secIds.contains(d['sector_id'] as int?)).toList();
    }
    filtradas.sort(
        (a, b) => (a['nombre'] ?? '').toString().compareTo((b['nombre'] ?? '').toString()));
    return Column(children: [
      Container(
        color: const Color(0xFF111111), height: 42,
        child: Row(mainAxisAlignment: MainAxisAlignment.center,
            children: _municipios
                .map((m) => _chipMun(m, _dirFiltroMun, (v) => setState(() {
                      _dirFiltroMun = v;
                      _dirFiltroSector = null;
                    })))
                .toList()),
      ),
      if (secsFilt.isNotEmpty)
        Container(
          color: const Color(0xFF0D0D0D),
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
          child: DropdownButtonFormField<int?>(
            value: _dirFiltroSector,
            dropdownColor: const Color(0xFF1A1A1A),
            style: const TextStyle(color: Colors.white, fontSize: 12),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Colors.white24),
              ),
              prefixIcon: const Icon(Icons.map_outlined, color: Colors.white38, size: 16),
            ),
            items: [
              const DropdownMenuItem<int?>(
                  value: null,
                  child: Text('Todos los sectores', style: TextStyle(color: Colors.white54))),
              ...secsFilt.map((s) => DropdownMenuItem<int?>(
                    value: s['id'] as int?,
                    child: Text(s['nombre']?.toString() ?? '',
                        style: const TextStyle(color: Colors.white)),
                  )),
            ],
            onChanged: (v) => setState(() => _dirFiltroSector = v),
          ),
        ),
      const Divider(height: 1, color: Colors.white12),
      Expanded(
        child: filtradas.isEmpty
            ? const Center(
                child: Text('Sin direcciones', style: TextStyle(color: Colors.white38)))
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 80),
                itemCount: filtradas.length,
                itemBuilder: (_, i) {
                  final d = filtradas[i];
                  final dId = d['id'] as int;
                  final sectorNombre = d['sector_id'] != null
                      ? _sectores
                          .where((s) => s['id'] == d['sector_id'])
                          .map((s) => s['nombre']?.toString())
                          .firstOrNull
                      : null;
                  return Card(
                    color: const Color(0xFF1A1A1A),
                    margin: const EdgeInsets.only(bottom: 6),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    child: ListTile(
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                      leading: const Icon(Icons.place, color: Color(0xff3AF500), size: 20),
                      title: Row(children: [
                        Expanded(
                            child: Text(d['nombre']?.toString() ?? '',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13))),
                        if (sectorNombre != null)
                          Container(
                            margin: const EdgeInsets.only(left: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xff3AF500).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(sectorNombre,
                                style: const TextStyle(
                                    color: Color(0xff3AF500), fontSize: 10)),
                          ),
                      ]),
                      subtitle: (d['direccion']?.toString() ?? '').isNotEmpty
                          ? Text(d['direccion'].toString(),
                              style: const TextStyle(color: Colors.white54, fontSize: 11))
                          : null,
                      trailing: _precioBadge(
                          _preciosDir[dId], () => _editarPrecioDir(dId, _preciosDir[dId])),
                    ),
                  );
                },
              ),
      ),
    ]);
  }
}
