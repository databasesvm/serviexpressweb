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
                          m['nombre'].toString().toUpperCase(),
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
                    titulo: 'LLAMAR A ${m['nombre']}',
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
          'Suspender a ${usuario['nombre']}',
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
        title: Text('Duración manual — ${usuario['nombre']}',
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
                  ? '🛑 ${usuario['nombre']} suspendido indefinidamente.'
                  : '🛑 ${usuario['nombre']} suspendido por $etiqueta.',
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
            content: Text('✅ ${usuario['nombre']} fue rehabilitado.'),
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
          '¿Sacar a ${movil['nombre']} de la fila?\n\n'
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
            content: Text('${movil['nombre']} fue sacado de la fila.'),
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
      backgroundColor: (esFn && enLinea) ? const Color(0xFF1A237E) : colorBase,
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
    return Row(
      children: [
        if (m['ticket_prioridad'] == true) ...[
          const Icon(Icons.local_activity, color: Colors.amber, size: 12),
          const SizedBox(width: 4),
        ],
        Text(
          '${m['rango_movil'] ?? 'NOVATO'} | ${_formatCalificacion(m['puntuacion'])}',
          style: const TextStyle(
              fontSize: 10, color: Colors.black54, fontWeight: FontWeight.w500),
        ),
        const SizedBox(width: 6),
        Text(
          ping,
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
              color: const Color(0xFF1A237E),
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
          .then((r) => (r as List).length),
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
                      onTap: () => _abrirGestionUsuarios(context),
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
                      icono: Icons.grid_view_rounded,
                      color: Colors.indigo[400]!,
                      titulo: 'Sectores',
                      subtitulo: 'Catálogo de barrios y zonas de cobertura',
                      onTap: () => _abrirGestorSectores(),
                    ),
                    _tarjetaGestion(
                      icono: Icons.map,
                      color: Colors.indigo[700]!,
                      titulo: 'Red de Direcciones',
                      subtitulo: 'Direcciones compartidas con locales',
                      onTap: () => _abrirRedDirecciones(context),
                    ),
                    _tarjetaGestion(
                      icono: Icons.price_change,
                      color: Colors.orange[800]!,
                      titulo: 'Listas de Precios',
                      subtitulo: 'Ver y editar tarifas de cada local por sector',
                      onTap: () => _abrirListasPrecios(context),
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
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Row(
          children: [
            Icon(Icons.storefront, color: Colors.blue),
            SizedBox(width: 8),
            Expanded(
              // <--- AQUÍ ESTÁ LA MAGIA
              child: Text(
                'GESTOR DE LOCALES EXCLUSIVOS',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          height: MediaQuery.of(context).size.height * 0.65,
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: Supabase.instance.client
                .from('usuarios')
                .select(
                  'id, nombre, paradero_exclusivo, recargo_nocturno_especial, zona_lluvia',
                )
                .eq('rol', 'local')
                .order('nombre', ascending: true),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(color: Colors.black),
                );
              }
              final locales = snapshot.data ?? [];
              if (locales.isEmpty) {
                return const Center(
                  child: Text(
                    'No hay locales registrados en el sistema.',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.black54,
                    ),
                  ),
                );
              }

              final localesExpuente = locales
                  .where((l) => l['paradero_exclusivo'] == 'EXPUENTE')
                  .toList();
              final localesMemos = locales
                  .where((l) => l['paradero_exclusivo'] == 'MEMOS')
                  .toList();
              final localesLibres = locales
                  .where(
                    (l) =>
                        l['paradero_exclusivo'] != 'EXPUENTE' &&
                        l['paradero_exclusivo'] != 'MEMOS',
                  )
                  .toList();

              Widget construirListaLocales(
                String titulo,
                List<Map<String, dynamic>> lista,
                Color color,
                String paraderoEtiqueta,
              ) {
                return ExpansionTile(
                  initiallyExpanded: true,
                  collapsedBackgroundColor: color.withValues(alpha: 0.1),
                  backgroundColor: color.withValues(alpha: 0.05),
                  title: Text(
                    '$titulo (${lista.length})',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: color,
                      fontSize: 14,
                    ),
                  ),
                  children: lista.isEmpty
                      ? [
                          const Padding(
                            padding: EdgeInsets.all(12),
                            child: Text(
                              'Sin locales asignados',
                              style: TextStyle(
                                color: Colors.black45,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ]
                      : lista
                            .map(
                              (local) => Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                child: Row(
                                  children: [
                                    Icon(Icons.business, color: color, size: 18),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        local['nombre'].toString().toUpperCase(),
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    // CONFIGURACIÓN DE RECARGOS — nocturno especial + zona lluvia
                                    IconButton(
                                      icon: const Icon(Icons.tune, size: 18, color: Colors.orange),
                                      tooltip: 'Configurar recargos',
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                      onPressed: () => _abrirConfigRecargosLocal(local),
                                    ),
                                    const SizedBox(width: 4),
                                    SizedBox(
                                      width: 120,
                                      child: DropdownButtonFormField<String>(
                                        initialValue: paraderoEtiqueta,
                                        isDense: true,
                                        isExpanded: true,
                                        decoration: const InputDecoration(
                                          contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                                          border: OutlineInputBorder(),
                                          isDense: true,
                                        ),
                                        style: const TextStyle(
                                          fontSize: 10,
                                          color: Colors.black,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        items: const [
                                          DropdownMenuItem(value: 'LIBRE', child: Text('LIBRE 🟢', style: TextStyle(fontSize: 11))),
                                          DropdownMenuItem(value: 'EXPUENTE', child: Text('EXPUENTE 🔵', style: TextStyle(fontSize: 11))),
                                          DropdownMenuItem(value: 'MEMOS', child: Text('MEMOS 🟣', style: TextStyle(fontSize: 11))),
                                        ],
                                        onChanged: (nuevoParadero) async {
                                          if (nuevoParadero != null &&
                                              nuevoParadero != paraderoEtiqueta) {
                                            String? valorFinal =
                                                nuevoParadero == 'LIBRE'
                                                ? null
                                                : nuevoParadero;
                                            await Supabase.instance.client
                                                .from('usuarios')
                                                .update({
                                                  'paradero_exclusivo': valorFinal,
                                                })
                                                .eq('id', local['id']);
                                            if (ctx.mounted) {
                                              Navigator.pop(ctx);
                                              _abrirGestorParaderos();
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                SnackBar(
                                                  content: Text(
                                                    'Local ${local['nombre']} reasignado a $nuevoParadero',
                                                  ),
                                                  backgroundColor: Colors.black,
                                                ),
                                              );
                                            }
                                          }
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                            .toList(),
                );
              }

              return ListView(
                children: [
                  const Text(
                    'Asigna de qué paradero saldrán los móviles para cada local. Si lo dejas libre, el radar buscará al más cercano.',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                  const SizedBox(height: 12),
                  construirListaLocales(
                    '📍 EXCLUSIVOS EXPUENTE',
                    localesExpuente,
                    Colors.blue[800]!,
                    'EXPUENTE',
                  ),
                  const SizedBox(height: 8),
                  construirListaLocales(
                    '📍 EXCLUSIVOS MEMOS',
                    localesMemos,
                    Colors.purple[800]!,
                    'MEMOS',
                  ),
                  const SizedBox(height: 8),
                  construirListaLocales(
                    '🟢 LOCALES LIBRES (Por Cercanía)',
                    localesLibres,
                    Colors.green[800]!,
                    'LIBRE',
                  ),
                ],
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'CERRAR',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // GESTOR DE SECTORES
  // ─────────────────────────────────────────────────────────────
  void _abrirGestorSectores() {
    final nombreCtrl = TextEditingController();
    String filtro = 'Cúcuta';
    String municipioNuevo = 'Cúcuta';

    Future<List<Map<String, dynamic>>> sectorsFuture =
        Supabase.instance.client.from('sectores').select().order('municipio').order('nombre');

    void recargar(StateSetter setSt) {
      sectorsFuture = Supabase.instance.client.from('sectores').select().order('municipio').order('nombre');
      setSt(() {});
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            title: const Row(children: [
              Icon(Icons.grid_view_rounded, color: Colors.indigo),
              SizedBox(width: 8),
              Text('SECTORES / BARRIOS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ]),
            content: SizedBox(
              width: double.maxFinite,
              height: MediaQuery.of(context).size.height * 0.65,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // ── Agregar ──────────────────────────────────────────────
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: nombreCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Nombre del sector / barrio',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  DropdownButton<String>(
                    value: municipioNuevo,
                    isDense: true,
                    items: ['Cúcuta', 'Los Patios', 'V. Rosario']
                        .map((m) => DropdownMenuItem(value: m, child: Text(m, style: const TextStyle(fontSize: 12))))
                        .toList(),
                    onChanged: (v) => setSt(() => municipioNuevo = v ?? 'Cúcuta'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                    onPressed: () async {
                      final n = nombreCtrl.text.trim();
                      if (n.isEmpty) return;
                      try {
                        await Supabase.instance.client.from('sectores')
                            .insert({'nombre': n, 'municipio': municipioNuevo});
                        nombreCtrl.clear();
                        recargar(setSt);
                      } catch (e) {
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red[800]));
                        }
                      }
                    },
                    child: const Icon(Icons.add, color: Color(0xff3AF500), size: 18),
                  ),
                ]),
                const SizedBox(height: 12),
                // ── Filtros por municipio ─────────────────────────────────
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: ['Cúcuta', 'Los Patios', 'V. Rosario'].map((m) {
                    final sel = filtro == m;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(m, style: TextStyle(fontSize: 11, color: sel ? Colors.white : Colors.black87)),
                        selected: sel,
                        selectedColor: Colors.indigo,
                        backgroundColor: Colors.grey[200],
                        onSelected: (_) => setSt(() => filtro = m),
                      ),
                    );
                  }).toList()),
                ),
                const SizedBox(height: 10),
                // ── Lista ────────────────────────────────────────────────
                Expanded(
                  child: FutureBuilder<List<Map<String, dynamic>>>(
                    future: sectorsFuture,
                    builder: (_, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator(color: Colors.indigo));
                      }
                      final lista = (snap.data ?? [])
                          .where((s) => s['municipio'].toString() == filtro)
                          .toList();
                      if (lista.isEmpty) {
                        return Center(child: Text('Sin sectores en $filtro.',
                            style: const TextStyle(color: Colors.black54)));
                      }
                      return ListView.builder(
                        itemCount: lista.length,
                        itemBuilder: (_, i) {
                          final s = lista[i];
                          final activo = s['activo'] as bool? ?? true;
                          return Card(
                            margin: const EdgeInsets.only(bottom: 6),
                            elevation: 0,
                            color: Colors.grey[100],
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            child: ListTile(
                              dense: true,
                              leading: Icon(Icons.location_city,
                                  color: activo ? Colors.indigo : Colors.grey, size: 20),
                              title: Text(s['nombre'].toString(),
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: activo ? Colors.black : Colors.grey)),
                              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                                GestureDetector(
                                  onTap: () async {
                                    await Supabase.instance.client
                                        .from('sectores').update({'activo': !activo}).eq('id', s['id']);
                                    recargar(setSt);
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: activo ? Colors.indigo : Colors.grey[200],
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(activo ? 'ON' : 'OFF',
                                        style: TextStyle(
                                            fontSize: 11, fontWeight: FontWeight.bold,
                                            color: activo ? Colors.white : Colors.grey)),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                IconButton(
                                  icon: const Icon(Icons.delete, color: Colors.red, size: 18),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                  onPressed: () async {
                                    await Supabase.instance.client
                                        .from('sectores').delete().eq('id', s['id']);
                                    recargar(setSt);
                                  },
                                ),
                              ]),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ]),
            ),
            actions: [TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('CERRAR', style: TextStyle(fontWeight: FontWeight.bold)),
            )],
          );
        },
      ),
    );
  }


  // ─────────────────────────────────────────────────────────────
  // GESTOR DE RED DE DIRECCIONES
  // ─────────────────────────────────────────────────────────────
  void _abrirRedDirecciones(BuildContext context) {
    final nombreCtrl = TextEditingController();
    String municipioSel = 'Cúcuta';
    String filtroDir   = 'Cúcuta';
    int? sectorSel;

    // Futures estables — fuera del builder para no resetear en cada setSt
    final sectoresFuture = Supabase.instance.client
        .from('sectores').select().eq('activo', true).order('nombre');

    Future<List<Map<String, dynamic>>> dirsFuture = Supabase.instance.client
        .from('red_direcciones')
        .select('id, nombre, municipio, activo, sector_id, sectores(nombre)')
        .order('municipio').order('nombre');

    void recargar(StateSetter setSt) {
      dirsFuture = Supabase.instance.client
          .from('red_direcciones')
          .select('id, nombre, municipio, activo, sector_id, sectores(nombre)')
          .order('municipio').order('nombre');
      setSt(() {});
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            title: const Row(children: [
              Icon(Icons.map, color: Colors.indigo),
              SizedBox(width: 8),
              Text('RED DE DIRECCIONES', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ]),
            content: SizedBox(
              width: double.maxFinite,
              height: MediaQuery.of(context).size.height * 0.70,
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: sectoresFuture,
                builder: (_, snapS) {
                  final sectores = snapS.data ?? [];
                  return Column(children: [
                    // ── Filtros por municipio ────────────────────────────
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(children: ['Cúcuta', 'Los Patios', 'V. Rosario'].map((m) {
                        final sel = filtroDir == m;
                        return Padding(
                          padding: const EdgeInsets.only(right: 6, bottom: 8),
                          child: ChoiceChip(
                            label: Text(m, style: TextStyle(fontSize: 11, color: sel ? Colors.white : Colors.black87)),
                            selected: sel,
                            selectedColor: Colors.indigo,
                            backgroundColor: Colors.grey[200],
                            onSelected: (_) => setSt(() => filtroDir = m),
                          ),
                        );
                      }).toList()),
                    ),
                    // --- Agregar dirección ---
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(
                          child: TextField(
                            controller: nombreCtrl,
                            textCapitalization: TextCapitalization.words,
                            decoration: const InputDecoration(labelText: 'Nombre del lugar/dirección', isDense: true, border: OutlineInputBorder()),
                          ),
                        ),
                        const SizedBox(width: 8),
                        DropdownButton<String>(
                          value: municipioSel,
                          isDense: true,
                          items: ['Cúcuta', 'Los Patios', 'V. Rosario']
                              .map((m) => DropdownMenuItem(value: m, child: Text(m, style: const TextStyle(fontSize: 12))))
                              .toList(),
                          onChanged: (v) => setSt(() => municipioSel = v ?? 'Cúcuta'),
                        ),
                      ]),
                      const SizedBox(height: 8),
                      Row(children: [
                        const Text('Sector: ', style: TextStyle(fontSize: 12, color: Colors.black54)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: DropdownButton<int?>(
                            value: sectorSel,
                            isDense: true,
                            isExpanded: true,
                            hint: const Text('Sin sector', style: TextStyle(fontSize: 12)),
                            items: [
                              const DropdownMenuItem<int?>(value: null, child: Text('Sin sector', style: TextStyle(fontSize: 12))),
                              ...sectores.map((s) => DropdownMenuItem<int?>(
                                value: s['id'] as int,
                                child: Text('${s['nombre']} (${s['municipio']})', style: const TextStyle(fontSize: 12)),
                              )),
                            ],
                            onChanged: (v) => setSt(() => sectorSel = v),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.black, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12)),
                          onPressed: () async {
                            final n = nombreCtrl.text.trim();
                            if (n.isEmpty) return;
                            try {
                              await Supabase.instance.client.from('red_direcciones').insert({
                                'nombre': n, 'municipio': municipioSel,
                                'zona_lluvia': 'general', 'activo': true,
                                if (sectorSel != null) 'sector_id': sectorSel,
                              });
                              nombreCtrl.clear();
                              recargar(setSt);
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Error al agregar: $e'), backgroundColor: Colors.red),
                                );
                              }
                            }
                          },
                          child: const Icon(Icons.add, color: Color(0xff3AF500), size: 18),
                        ),
                      ]),
                    ]),
                    const Divider(height: 20),
                    Expanded(
                      child: FutureBuilder<List<Map<String, dynamic>>>(
                        future: dirsFuture,
                        builder: (_, snap) {
                          if (snap.connectionState == ConnectionState.waiting) {
                            return const Center(child: CircularProgressIndicator(color: Colors.black));
                          }
                          final todaDir = snap.data ?? [];
                          final dirs = todaDir.where((d) => d['municipio'].toString() == filtroDir).toList();
                          if (dirs.isEmpty) return Center(child: Text('Sin direcciones en $filtroDir.'));
                          return ListView.builder(
                            itemCount: dirs.length,
                            itemBuilder: (_, i) {
                              final d = dirs[i];
                              final activo = d['activo'] as bool? ?? true;
                              final sectorNombre = d['sectores'] != null ? (d['sectores'] as Map)['nombre'] : null;
                              return ListTile(
                                dense: true,
                                leading: Icon(Icons.place, color: activo ? Colors.indigo : Colors.grey, size: 18),
                                title: Text(d['nombre'].toString(), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: activo ? Colors.black : Colors.grey)),
                                subtitle: Text(
                                  '${d['municipio']}${sectorNombre != null ? ' · $sectorNombre' : ''}',
                                  style: const TextStyle(fontSize: 11),
                                ),
                                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                                  GestureDetector(
                                    onTap: () async {
                                      try {
                                        await Supabase.instance.client.from('red_direcciones').update({'activo': !activo}).eq('id', d['id']);
                                        recargar(setSt);
                                      } catch (_) {}
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: activo ? Colors.indigo : Colors.grey[200],
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(activo ? 'ON' : 'OFF',
                                          style: TextStyle(
                                              fontSize: 11, fontWeight: FontWeight.bold,
                                              color: activo ? Colors.white : Colors.grey)),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  IconButton(
                                    icon: const Icon(Icons.delete, color: Colors.red, size: 18),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                    onPressed: () async {
                                      try {
                                        await Supabase.instance.client.from('red_direcciones').delete().eq('id', d['id']);
                                        recargar(setSt);
                                      } catch (_) {}
                                    },
                                  ),
                                ]),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ]);
                },
              ),
            ),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CERRAR', style: TextStyle(fontWeight: FontWeight.bold)))],
          );
        },
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // GESTOR DE LISTAS DE PRECIOS (por local, por sector)
  // ─────────────────────────────────────────────────────────────
  void _abrirListasPrecios(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) {
        String? localSelId;
        String localSelNombre = '';
        final localesFuture = Supabase.instance.client
            .from('usuarios').select('id, nombre').eq('rol', 'local').order('nombre');
        return StatefulBuilder(
        builder: (ctx, setSt) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            title: const Row(children: [
              Icon(Icons.price_change, color: Colors.orange),
              SizedBox(width: 8),
              Text('LISTAS DE PRECIOS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ]),
            content: SizedBox(
              width: double.maxFinite,
              height: MediaQuery.of(context).size.height * 0.70,
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: localesFuture,
                builder: (_, snapL) {
                  final locales = snapL.data ?? [];
                  if (locales.isEmpty) return const Center(child: Text('Sin locales registrados.'));
                  if (localSelId == null) {
                    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Selecciona un local para ver o editar su lista de precios:', style: TextStyle(fontSize: 13, color: Colors.black54)),
                      const SizedBox(height: 12),
                      Expanded(
                        child: ListView.builder(
                          itemCount: locales.length,
                          itemBuilder: (_, i) {
                            final l = locales[i];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: const Icon(Icons.store, color: Colors.orange),
                                title: Text(l['nombre'].toString(), style: const TextStyle(fontWeight: FontWeight.bold)),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => setSt(() { localSelId = l['id'].toString(); localSelNombre = l['nombre'].toString(); }),
                              ),
                            );
                          },
                        ),
                      ),
                    ]);
                  }
                  return _PanelPreciosLocal(localId: localSelId!, localNombre: localSelNombre, onBack: () => setSt(() => localSelId = null));
                },
              ),
            ),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CERRAR', style: TextStyle(fontWeight: FontWeight.bold)))],
          );
        },
      );
      },
    );
  }

  void _abrirBuzonSoporte(
    BuildContext context,
    List<Map<String, dynamic>> usuariosConAlarma,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text(
          '🚨 BUZÓN DE SOPORTE GENERAL',
          style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
        ),
        content: SizedBox(
          width: 400,
          height: 400,
          child: ListView.builder(
            itemCount: usuariosConAlarma.length,
            itemBuilder: (context, index) {
              final u = usuariosConAlarma[index];
              return Card(
                elevation: 2,
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(
                  side: const BorderSide(color: Colors.red, width: 1.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Colors.red,
                    child: Icon(Icons.warning, color: Colors.white, size: 20),
                  ),
                  title: Text(
                    u['nombre'].toString().toUpperCase(),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text('Rol: ${u['rol'].toString().toUpperCase()}'),
                  trailing: const Icon(Icons.chat, color: Colors.blue),
                  onTap: () {
                    setState(() => _noLeidos.remove('soporte_${u['id']}'));
                    Supabase.instance.client
                        .from('usuarios')
                        .update({'alarma_soporte': false})
                        .eq('id', u['id']);
                    Navigator.pop(ctx);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChatScreen(
                          salaId: 'soporte_${u['id']}',
                          miId: 0,
                          miNombre: 'Central',
                          titulo: 'Soporte ➔ ${u['nombre']}',
                          usuarioId: u['id'],
                          alarmaLocal: 'alarma_soporte',
                          alarmaDestino: 'chat_central',
                          destinatarioId: u['id'] as int?,
                          tipoFaq: TipoFaqChat.central,
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'CERRAR',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
            ),
          ),
        ],
      ),
    );
  }

}
