// ignore_for_file: use_build_context_synchronously
part of 'central_screen.dart';

extension CentralScreenPerfil on _CentralScreenState {

  // Abre estadísticas de cualquier móvil consultando Supabase en el momento
  // Vista completa del perfil del moto, para Central — todos los
  // datos: identidad, contacto, fecha de nacimiento, rango y las 3
  // cuentas de pago. El mapa 'movil' ya trae todas las columnas (el
  // stream que alimenta Flota no usa .select() limitado), así que no
  // hace falta ninguna consulta extra.
  void _verPerfilCompletoMovil(BuildContext ctx, Map<String, dynamic> movil) {
    final String rango =
        movil['rango_movil']?.toString().toUpperCase() ?? 'NOVATO';
    final Color colorRango = rango == 'MASTER'
        ? const Color(0xFFE040FB)
        : rango == 'LEYENDA'
            ? const Color(0xFFFF9800)
            : rango == 'ELITE'
                ? const Color(0xFF2196F3)
                : rango == 'PRO'
                    ? const Color(0xFF4CAF50)
                    : Colors.grey;

    // Fecha de nacimiento y edad
    String fechaNacTexto = 'No registrada';
    int? edadMovil;
    if (movil['fecha_nacimiento'] != null) {
      try {
        final f = DateTime.parse(movil['fecha_nacimiento'].toString());
        fechaNacTexto =
            '${f.day.toString().padLeft(2, '0')}/${f.month.toString().padLeft(2, '0')}/${f.year}';
        final hoy = DateTime.now();
        edadMovil = hoy.year - f.year;
        if (hoy.month < f.month ||
            (hoy.month == f.month && hoy.day < f.day)) { edadMovil--; }
      } catch (_) {}
    }

    // Fecha de registro
    String fechaRegistroTexto = 'No disponible';
    if (movil['created_at'] != null) {
      try {
        final r = DateTime.parse(movil['created_at'].toString()).toLocal();
        fechaRegistroTexto =
            '${r.day.toString().padLeft(2, '0')}/${r.month.toString().padLeft(2, '0')}/${r.year}';
      } catch (_) {}
    }

    // Suspensión
    final bool suspendido = movil['suspendido'] == true;
    String? suspendidoHastaTexto;
    if (suspendido && movil['suspendido_hasta'] != null) {
      try {
        final h = DateTime.parse(movil['suspendido_hasta'].toString()).toLocal();
        suspendidoHastaTexto =
            '${h.day.toString().padLeft(2, '0')}/${h.month.toString().padLeft(2, '0')}/${h.year} ${h.hour.toString().padLeft(2, '0')}:${h.minute.toString().padLeft(2, '0')}';
      } catch (_) {}
    }

    // Estado actual
    final bool enLinea = movil['en_linea'] == true;
    final String? paraderoActual = movil['paradero_actual']?.toString();
    Color estadoColor;
    String estadoLabel;
    IconData estadoIcon;
    if (suspendido) {
      estadoColor = Colors.red[800]!;
      estadoLabel = 'SUSPENDIDO';
      estadoIcon = Icons.block_rounded;
    } else if (!enLinea) {
      estadoColor = Colors.grey[600]!;
      estadoLabel = 'DESCONECTADO';
      estadoIcon = Icons.gps_off_rounded;
    } else if (paraderoActual != null && paraderoActual.isNotEmpty) {
      estadoColor = Colors.blue[700]!;
      estadoLabel = 'EN PARADERO · $paraderoActual';
      estadoIcon = Icons.location_on_rounded;
    } else {
      estadoColor = const Color(0xFF2E7D32);
      estadoLabel = 'EN LÍNEA';
      estadoIcon = Icons.gps_fixed_rounded;
    }

    final String? fotoUrl = movil['foto_perfil_url']?.toString();
    final bool tieneFoto = fotoUrl != null && fotoUrl.isNotEmpty;
    final bool silenciaRadar = movil['silenciar_radar'] == true;
    final bool tieneTicket = movil['ticket_prioridad'] == true;
    final String? exclusivo = movil['paradero_exclusivo']?.toString();
    final String? dirCasa = movil['dir_casa']?.toString();

    // Sección header de sección
    Widget seccionHeader(String titulo) => Padding(
          padding: const EdgeInsets.fromLTRB(0, 16, 0, 6),
          child: Row(children: [
            Text(titulo,
                style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.black45,
                    letterSpacing: 0.8)),
            const SizedBox(width: 8),
            const Expanded(child: Divider(height: 1)),
          ]),
        );

    showDialog(
      context: ctx,
      builder: (dctx) {
        final double screenW = MediaQuery.of(dctx).size.width;
        return Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          insetPadding: EdgeInsets.symmetric(
            horizontal: screenW > 500 ? (screenW - 480) / 2 : 16,
            vertical: 24,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 480,
                maxHeight: MediaQuery.of(dctx).size.height * 0.88,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── CABECERA NEGRA ──────────────────────────────
                  Container(
                    width: double.infinity,
                    color: Colors.black,
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
                    child: Column(
                      children: [
                        // Foto / avatar
                        CircleAvatar(
                          radius: 36,
                          backgroundColor: colorRango,
                          backgroundImage:
                              tieneFoto ? NetworkImage(fotoUrl) : null,
                          child: !tieneFoto
                              ? Text(_extraerNumeroAvatar(movil),
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold))
                              : null,
                        ),
                        const SizedBox(height: 10),
                        // Nombre
                        Text(
                          (movil['nombre'] ?? 'Sin nombre')
                              .toString()
                              .toUpperCase(),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xff3AF500),
                            fontWeight: FontWeight.bold,
                            fontSize: 17,
                          ),
                        ),
                        // Usuario MOVIL##
                        Text(
                          _formatearNombreCentral(movil).toUpperCase(),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: Colors.white60, fontSize: 12),
                        ),
                        const SizedBox(height: 10),
                        // Rango + puntuación
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: colorRango.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: colorRango),
                              ),
                              child: Text(
                                '🏆 $rango — ${_formatCalificacion(movil['puntuacion'])}',
                                style: TextStyle(
                                    color: colorRango,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11),
                              ),
                            ),
                            if (tieneTicket)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.amber.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(20),
                                  border:
                                      Border.all(color: Colors.amber[600]!),
                                ),
                                child: const Text('⭐ TICKET PRIORIDAD',
                                    style: TextStyle(
                                        color: Colors.amber,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold)),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // ── BARRA DE ESTADO ─────────────────────────────
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    color: estadoColor,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(estadoIcon, color: Colors.white, size: 14),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(estadoLabel,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5),
                              overflow: TextOverflow.ellipsis),
                        ),
                        if (suspendido && suspendidoHastaTexto != null) ...[
                          const SizedBox(width: 8),
                          Text('hasta $suspendidoHastaTexto',
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 10)),
                        ],
                      ],
                    ),
                  ),

                  // ── CUERPO SCROLLABLE ───────────────────────────
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // —— CONTACTO ——————————————————————————
                          seccionHeader('CONTACTO'),
                          _filaPerfilCentral(
                              Icons.phone, 'Teléfono', movil['telefono']),
                          if (movil['telefono'] != null &&
                              movil['telefono']
                                  .toString()
                                  .trim()
                                  .isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2, bottom: 6),
                              child: SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.green[700],
                                    side: BorderSide(
                                        color: Colors.green[700]!),
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 6),
                                  ),
                                  onPressed: () async {
                                    final tel =
                                        movil['telefono'].toString();
                                    final wa = tel.startsWith('57')
                                        ? tel
                                        : '57$tel';
                                    final uri =
                                        Uri.parse('https://wa.me/$wa');
                                    if (await canLaunchUrl(uri)) {
                                      await launchUrl(uri,
                                          mode: LaunchMode
                                              .externalApplication);
                                    }
                                  },
                                  icon:
                                      const Icon(Icons.wechat, size: 15),
                                  label: const Text('Abrir WhatsApp',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 11)),
                                ),
                              ),
                            ),
                          _filaPerfilCentral(Icons.email_outlined, 'Correo',
                              movil['correo']),
                          if (dirCasa != null && dirCasa.isNotEmpty)
                            _filaPerfilCentral(Icons.home_outlined,
                                'Dirección', dirCasa),

                          // —— DATOS PERSONALES ——————————————————
                          seccionHeader('DATOS PERSONALES'),
                          _filaPerfilCentral(
                              Icons.cake_outlined, 'Nacimiento', fechaNacTexto),
                          if (edadMovil != null)
                            _filaPerfilCentral(Icons.hourglass_bottom_outlined,
                                'Edad', '$edadMovil años'),
                          _filaPerfilCentral(Icons.calendar_today_outlined,
                              'Registro', fechaRegistroTexto),

                          // —— OPERACIONAL ———————————————————————
                          seccionHeader('OPERACIONAL'),
                          if (exclusivo != null && exclusivo.isNotEmpty)
                            _filaPerfilCentral(Icons.place_rounded,
                                'Exclusivo', exclusivo),
                          _filaPerfilCentralBool(
                            Icons.volume_off_rounded,
                            'Silenciar radar',
                            silenciaRadar,
                            colorTrue: Colors.orange,
                          ),
                          _filaPerfilCentralBool(
                            Icons.local_activity_rounded,
                            'Ticket prioridad',
                            tieneTicket,
                            colorTrue: Colors.amber[700]!,
                          ),

                          // —— CUENTAS DE PAGO ———————————————————
                          seccionHeader('CUENTAS DE PAGO'),
                          _filaPagoCentral('Nequi',
                              const Color(0xFFE5007D), Colors.white,
                              movil['pago_nequi']),
                          _filaPagoCentral('Daviplata',
                              const Color(0xFFEE2A24), Colors.white,
                              movil['pago_daviplata']),
                          _filaPagoCentral('Bancolombia',
                              const Color(0xFFFFCC00), Colors.black,
                              movil['pago_bancolombia']),

                          // —— CALIFICACIONES (con nombre real del calificador) ——
                          seccionHeader('CALIFICACIONES RECIBIDAS'),
                          FutureBuilder<List<Map<String, dynamic>>>(
                            future: Supabase.instance.client
                                .from('calificaciones')
                                .select(
                                    'estrellas, comentario, calificador_tipo, '
                                    'calificador_nombre, created_at')
                                .eq('movil_id', movil['id'].toString())
                                .order('created_at', ascending: false)
                                .limit(20),
                            builder: (context, snap) {
                              if (snap.connectionState ==
                                  ConnectionState.waiting) {
                                return const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 8),
                                  child: Center(
                                    child: SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    ),
                                  ),
                                );
                              }
                              final califs = snap.data ?? [];
                              if (califs.isEmpty) {
                                return const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 8),
                                  child: Text(
                                    'Sin calificaciones aún.',
                                    style: TextStyle(
                                        color: Colors.black45, fontSize: 12),
                                  ),
                                );
                              }
                              // Promedio
                              final double prom = califs
                                      .map((c) =>
                                          (c['estrellas'] as num).toDouble())
                                      .reduce((a, b) => a + b) /
                                  califs.length;
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Resumen
                                  Padding(
                                    padding:
                                        const EdgeInsets.only(bottom: 8),
                                    child: Row(
                                      children: [
                                        Text(
                                          prom.toStringAsFixed(1),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 22,
                                            color: Colors.amber,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: List.generate(
                                                  5,
                                                  (i) => Icon(
                                                        i < prom.round()
                                                            ? Icons.star
                                                            : Icons.star_border,
                                                        size: 14,
                                                        color: Colors.amber,
                                                      )),
                                            ),
                                            Text(
                                              '${califs.length} valoración${califs.length != 1 ? 'es' : ''}',
                                              style: const TextStyle(
                                                  fontSize: 10,
                                                  color: Colors.black45),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Lista de calificaciones
                                  ...califs.map((c) {
                                    final tipo =
                                        c['calificador_tipo']?.toString() ??
                                            '';
                                    final nombre =
                                        c['calificador_nombre']?.toString() ??
                                            (tipo == 'invitado'
                                                ? 'Invitado'
                                                : 'Desconocido');
                                    final int stars =
                                        (c['estrellas'] as num).toInt();
                                    final String? com =
                                        c['comentario']?.toString();
                                    String fechaStr = '';
                                    try {
                                      final dt = DateTime.parse(
                                              c['created_at'].toString())
                                          .toLocal();
                                      fechaStr =
                                          '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
                                    } catch (_) {}
                                    return Container(
                                      margin:
                                          const EdgeInsets.only(bottom: 8),
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: Colors.grey[50],
                                        borderRadius:
                                            BorderRadius.circular(8),
                                        border: Border.all(
                                            color: Colors.grey[200]!),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment
                                                    .spaceBetween,
                                            children: [
                                              Flexible(
                                                child: Text(
                                                  nombre,
                                                  style: const TextStyle(
                                                    fontWeight:
                                                        FontWeight.bold,
                                                    fontSize: 12,
                                                  ),
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                              Row(
                                                children: [
                                                  ...List.generate(
                                                    5,
                                                    (i) => Icon(
                                                      i < stars
                                                          ? Icons.star
                                                          : Icons.star_border,
                                                      size: 12,
                                                      color: Colors.amber,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    fechaStr,
                                                    style: const TextStyle(
                                                        fontSize: 9,
                                                        color: Colors.black38),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                          if (com != null &&
                                              com.isNotEmpty) ...[
                                            const SizedBox(height: 4),
                                            Text(
                                              '"$com"',
                                              style: const TextStyle(
                                                fontSize: 11,
                                                fontStyle: FontStyle.italic,
                                                color: Colors.black87,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    );
                                  }),
                                ],
                              );
                            },
                          ),

                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                  ),

                  // ── PIE ─────────────────────────────────────────
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(dctx),
                          child: const Text('CERRAR',
                              style: TextStyle(
                                  color: Colors.black54,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _filaPerfilCentral(IconData icono, String etiqueta, dynamic valor) {
    final String texto = (valor == null || valor.toString().trim().isEmpty)
        ? 'No registrado'
        : valor.toString();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(icono, size: 16, color: Colors.grey[500]),
          const SizedBox(width: 10),
          SizedBox(
            width: 90,
            child: Text(etiqueta, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          ),
          Expanded(
            child: Text(
              texto,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filaPerfilCentralBool(
    IconData icono,
    String etiqueta,
    bool valor, {
    Color colorTrue = Colors.green,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(icono, size: 16, color: Colors.grey[500]),
          const SizedBox(width: 10),
          Text(etiqueta,
              style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          const Spacer(),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: valor
                  ? colorTrue.withValues(alpha: 0.12)
                  : Colors.grey[100],
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              valor ? 'SÍ' : 'NO',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: valor ? colorTrue : Colors.grey[400],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filaPagoCentral(String app, Color color, Color colorTexto, dynamic numero) {
    final bool tiene = numero != null && numero.toString().trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Container(
            width: 84,
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
            alignment: Alignment.center,
            child: Text(app, style: TextStyle(color: colorTexto, fontWeight: FontWeight.bold, fontSize: 10)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              tiene ? numero.toString() : 'No registrada',
              style: TextStyle(
                fontSize: 12,
                color: tiene ? Colors.black87 : Colors.grey[400],
                fontWeight: tiene ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
          if (tiene)
            IconButton(
              icon: const Icon(Icons.copy_rounded, size: 18, color: Colors.blue),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              tooltip: 'Copiar número',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: numero.toString()));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('$app copiado: $numero'),
                    backgroundColor: Colors.black,
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Future<void> _abrirEstadisticasMovil(
    BuildContext ctx,
    Map<String, dynamic> movil,
  ) async {
    final historial = await Supabase.instance.client
        .from('servicios')
        .select('id, origen, destino, estado, observacion')
        .eq('movil_id', movil['id'])
        .not('estado', 'eq', 'pendiente')
        .not('estado', 'eq', 'en_curso')
        .not('estado', 'eq', 'problema');
    if (ctx.mounted) {
      _mostrarPerfilHistorialCompleto(
        ctx,
        (movil['usuario'] ?? movil['nombre'] ?? 'Conductor').toString().toUpperCase(),
        historial,
      );
    }
  }

  void _abrirChatDirectoMovil(Map<String, dynamic> movil) {
    // 1. Apagamos la alerta visual en la central al entrar y resetear contador
    final salaDirecta = 'soporte_${movil['id']}';
    setState(() => _noLeidos.remove(salaDirecta));
    Supabase.instance.client
        .from('usuarios')
        .update({'alarma_soporte': false})
        .eq('id', movil['id']);

    // 2. Entramos al chat cruzando las alarmas tácticas
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          salaId: 'soporte_${movil['id']}',
          miId: 0,
          miNombre: 'Central',
          titulo: 'Central ➔ ${movil['nombre']}',
          usuarioId: movil['id'],
          alarmaLocal: 'alarma_soporte', // Apaga en Central al leer
          alarmaDestino: 'chat_central', // Enciende en Móvil al enviar
          destinatarioId: movil['id'] as int?,
          tipoFaq: TipoFaqChat.central,
        ),
      ),
    );
  }

}
