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
  }) {
    return FutureBuilder<int>(
      future: Supabase.instance.client
          .from('usuarios')
          .select('id')
          .eq('rol', 'local')
          .eq('estado_local', 'pendiente')
          .then((r) => r.length),
      builder: (ctx, snap) {
        final count = snap.data ?? 0;
        return Stack(
          children: [
            _tarjetaGestion(
              icono: icono,
              color: color,
              titulo: titulo,
              subtitulo: subtitulo,
              onTap: onTap,
            ),
            if (count > 0)
              Positioned(
                top: 8, right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.red[600],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$count',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ),
          ],
        );
      },
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
                    _tarjetaGestionConBadge(
                      icono: Icons.manage_accounts_rounded,
                      color: Colors.blue[600]!,
                      titulo: 'Gestión de Usuarios',
                      subtitulo: 'Solicitudes, activaciones, ascensos y registros',
                      // Si hay pendientes de activación → abrir directo en "Por Activar"
                      onTap: () => _abrirGestionUsuarios(
                        context,
                        tabInicial: _usuariosPendientes > 0 ? 1 : 0,
                      ),
                    ),
                    _tarjetaGestion(
                      icono: Icons.storefront,
                      color: Colors.teal[700]!,
                      titulo: 'Gestor de Paraderos',
                      subtitulo: 'Zonas, horarios y filas',
                      onTap: _abrirGestorParaderos,
                    ),
                    _tarjetaGestion(
                      icono: Icons.emoji_events,
                      color: Colors.amber[800]!,
                      titulo: 'Ranking Semanal',
                      subtitulo: 'Desempeño de la flota',
                      onTap: () => _mostrarRankingSemanalDialog(context),
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
                      icono: Icons.map_outlined,
                      color: Colors.indigo[600]!,
                      titulo: 'Red & Sectores',
                      subtitulo: 'Direcciones, barrios y precios globales',
                      onTap: () => _abrirGestorRedYSectores(context),
                    ),
                    _tarjetaGestion(
                      icono: Icons.delivery_dining,
                      color: const Color(0xff3AF500),
                      titulo: 'Monitor Domicilios',
                      subtitulo:
                          'Pedidos activos, estados y domicilios por local',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => MonitorPedidosScreen(usuario: widget.usuario!),
                        ),
                      ),
                    ),
                    _tarjetaGestion(
                      icono: Icons.local_pharmacy,
                      color: Colors.indigo[900]!,
                      titulo: 'Farmanorte FN',
                      subtitulo: 'Sedes, motos FN e ignorados del día',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const FnPanelScreen(),
                        ),
                      ),
                    ),
                    _tarjetaGestion(
                      icono: Icons.history_rounded,
                      color: Colors.indigo[600]!,
                      titulo: 'Historial de Servicios',
                      subtitulo: 'Búsqueda y consulta de servicios pasados',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const HistorialServiciosScreen(),
                        ),
                      ),
                    ),
                    _tarjetaGestion(
                      icono: Icons.flag_outlined,
                      color: Colors.orange[700]!,
                      titulo: 'Reportes y Quejas',
                      subtitulo: _reportesSinLeer > 0
                          ? '$_reportesSinLeer sin leer — quejas de clientes y sedes'
                          : 'Quejas de clientes y sedes activas',
                      onTap: () => _abrirPanelReportes(context),
                    ),

                    // ── Toggle: bloqueo automático por inactividad ──────────
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

                  ]),
                ),
              ),
            ],
          ),
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


}

// ══════════════════════════════════════════════════════════════════════════════
// GESTOR DE PARADEROS — pantalla completa
// ══════════════════════════════════════════════════════════════════════════════

class _PanelGestorParaderos extends StatefulWidget {
  final Function(Map<String, dynamic>) onConfigRecargos;
  const _PanelGestorParaderos({required this.onConfigRecargos});

  @override
  State<_PanelGestorParaderos> createState() => _PanelGestorParaderosState();
}

class _PanelGestorParaderosState extends State<_PanelGestorParaderos> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _cargar();
  }

  Future<List<Map<String, dynamic>>> _cargar() =>
      Supabase.instance.client
          .from('usuarios')
          .select('id, nombre, paradero_exclusivo, recargo_nocturno_especial, zona_lluvia')
          .eq('rol', 'local')
          .order('nombre', ascending: true);

  void _recargar() => setState(() { _future = _cargar(); });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 1,
        title: const Row(children: [
          Icon(Icons.storefront, color: Colors.blue),
          SizedBox(width: 8),
          Expanded(child: Text('GESTOR DE LOCALES EXCLUSIVOS',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
        ]),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Colors.black));
          }
          final locales = snapshot.data ?? [];
          if (locales.isEmpty) {
            return const Center(child: Text('No hay locales registrados en el sistema.',
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black54)));
          }

          final localesExpuente = locales.where((l) => l['paradero_exclusivo'] == 'EXPUENTE').toList();
          final localesMemos    = locales.where((l) => l['paradero_exclusivo'] == 'MEMOS').toList();
          final localesLibres   = locales.where((l) =>
              l['paradero_exclusivo'] != 'EXPUENTE' && l['paradero_exclusivo'] != 'MEMOS').toList();

          Widget construirLista(String titulo, List<Map<String, dynamic>> lista, Color color, String etiqueta) {
            return ExpansionTile(
              initiallyExpanded: true,
              collapsedBackgroundColor: color.withValues(alpha: 0.1),
              backgroundColor: color.withValues(alpha: 0.05),
              title: Text('$titulo (${lista.length})',
                  style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 14)),
              children: lista.isEmpty
                  ? [const Padding(padding: EdgeInsets.all(12),
                      child: Text('Sin locales asignados',
                          style: TextStyle(color: Colors.black45, fontSize: 12)))]
                  : lista.map((local) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      child: Row(children: [
                        Icon(Icons.business, color: color, size: 18),
                        const SizedBox(width: 10),
                        Expanded(child: Text(local['nombre'].toString().toUpperCase(),
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                            maxLines: 2, overflow: TextOverflow.ellipsis)),
                        IconButton(
                          icon: const Icon(Icons.tune, size: 18, color: Colors.orange),
                          tooltip: 'Configurar recargos',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                          onPressed: () => widget.onConfigRecargos(local),
                        ),
                        const SizedBox(width: 4),
                        SizedBox(width: 120, child: DropdownButtonFormField<String>(
                          initialValue: etiqueta,
                          isDense: true, isExpanded: true,
                          decoration: const InputDecoration(
                            contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                            border: OutlineInputBorder(), isDense: true,
                          ),
                          style: const TextStyle(fontSize: 10, color: Colors.black, fontWeight: FontWeight.bold),
                          items: const [
                            DropdownMenuItem(value: 'LIBRE',    child: Text('LIBRE 🟢',    style: TextStyle(fontSize: 11))),
                            DropdownMenuItem(value: 'EXPUENTE', child: Text('EXPUENTE 🔵', style: TextStyle(fontSize: 11))),
                            DropdownMenuItem(value: 'MEMOS',    child: Text('MEMOS 🟣',    style: TextStyle(fontSize: 11))),
                          ],
                          onChanged: (nuevo) async {
                            if (nuevo == null || nuevo == etiqueta) return;
                            final valor = nuevo == 'LIBRE' ? null : nuevo;
                            await Supabase.instance.client.from('usuarios')
                                .update({'paradero_exclusivo': valor}).eq('id', local['id']);
                            if (mounted) {
                              _recargar();
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                content: Text('Local ${local['nombre']} reasignado a $nuevo'),
                                backgroundColor: Colors.black,
                              ));
                            }
                          },
                        )),
                      ]),
                    )).toList(),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Asigna de qué paradero saldrán los móviles para cada local. Si lo dejas libre, el radar buscará al más cercano.',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
              const SizedBox(height: 12),
              construirLista('📍 EXCLUSIVOS EXPUENTE', localesExpuente, Colors.blue[800]!,   'EXPUENTE'),
              const SizedBox(height: 8),
              construirLista('📍 EXCLUSIVOS MEMOS',    localesMemos,    Colors.purple[800]!, 'MEMOS'),
              const SizedBox(height: 8),
              construirLista('🟢 LOCALES LIBRES (Por Cercanía)', localesLibres, Colors.green[800]!, 'LIBRE'),
            ],
          );
        },
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
  String _dirFiltroMun = 'Cúcuta';
  int? _dirFiltroSector;

  static const _municipios = ['Cúcuta', 'Los Patios', 'V. Rosario'];

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _tab.addListener(() => setState(() {}));
    _cargarInicial();
  }

  @override
  void dispose() {
    _tab.dispose();
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
                  final precio = int.tryParse(precioCtrl.text.trim());
                  if (precio != null && precio > 0) {
                    await _db.from('se_precios_dir').delete()
                        .eq('usuario_id', userId).eq('dir_id', newDirId);
                    await _db.from('se_precios_dir').insert({
                      'usuario_id': userId, 'dir_id': newDirId, 'precio': precio,
                    });
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
          ? FloatingActionButton.extended(
              backgroundColor: const Color(0xff3AF500),
              onPressed: _abrirFormSector,
              icon: const Icon(Icons.add, color: Colors.black),
              label: const Text('Nuevo sector',
                  style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            )
          : _userSel != null
              ? FloatingActionButton.extended(
                  backgroundColor: const Color(0xff3AF500),
                  onPressed: () => _formDir(),
                  icon: const Icon(Icons.add_location_alt, color: Colors.black),
                  label: const Text('Nueva dirección',
                      style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
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
    final filtrados = <Map<String, dynamic>>[];
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
    if (_dirFiltroSector != null) {
      filtradas = filtradas
          .where((d) => d['sector_id'] == _dirFiltroSector)
          .toList();
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
              onTap: () => setState(() { _dirFiltroMun = m; _dirFiltroSector = null; }),
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
            .where((s) => s['municipio'] == _dirFiltroMun)
            .toList()
          ..sort((a, b) => (a['nombre'] ?? '').toString()
              .compareTo((b['nombre'] ?? '').toString()));
        if (subSecs.isEmpty) return const SizedBox.shrink();
        return Container(
          color: const Color(0xFF0D0D0D),
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
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
              const DropdownMenuItem<int?>(value: null, child: Text('Todos los sectores', style: TextStyle(color: Colors.white54))),
              ...subSecs.map((s) => DropdownMenuItem<int?>(
                value: s['id'] as int?,
                child: Text(s['nombre']?.toString() ?? '', style: const TextStyle(color: Colors.white)),
              )),
            ],
            onChanged: (v) => setState(() => _dirFiltroSector = v),
          ),
        );
      }),
      const Divider(height: 1, color: Colors.white12),
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

  Widget _noUserPlaceholder(String msg) => Center(
    child: Text(msg, textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white38, fontSize: 14)),
  );
}
