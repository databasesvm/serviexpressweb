import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:latlong2/latlong.dart';
import 'package:serviexpress_app/utils/onesignal_api.dart';
import 'package:serviexpress_app/utils/widgets_compartidos.dart';

class GuestTrackingScreen extends StatefulWidget {
  const GuestTrackingScreen({super.key});

  @override
  State<GuestTrackingScreen> createState() => _GuestTrackingScreenState();
}

class _GuestTrackingScreenState extends State<GuestTrackingScreen> {
  int? _idPedido;
  bool _cargandoId = true;
  // Stream guardado como campo para que StreamBuilder no cree una nueva
  // suscripción WebSocket en cada rebuild del widget.
  Stream<List<Map<String, dynamic>>>? _streamServicio;

  @override
  void initState() {
    super.initState();
    _cargarUltimoPedido();
  }

  Future<void> _cargarUltimoPedido() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getInt('ultimo_pedido_invitado');
    setState(() {
      _idPedido = id;
      _cargandoId = false;
      if (id != null) {
        _streamServicio = Supabase.instance.client
            .from('servicios')
            .stream(primaryKey: ['id'])
            .eq('id', id)
            .limit(1);
      }
    });
  }

  Future<void> _procesarRespuestaCotizacion(
    Map<String, dynamic> servicio,
    bool aprobada,
  ) async {
    try {
      String notaAnterior = servicio['observacion'] ?? '';

      await Supabase.instance.client
          .from('servicios')
          .update({
            'estado': aprobada ? 'pendiente' : 'cancelado',
            'observacion': aprobada
                ? '$notaAnterior\n[ ✔️ APROBADA POR INVITADO ]'
                : '$notaAnterior\n[ ❌ RECHAZADA POR INVITADO ]',
          })
          .eq('id', servicio['id']);

      if (aprobada) {
        // --- CASCADA 4 FASES — igual que el resto de la app ---
        final int svcId = servicio['id'] as int;
        final double? origLat = (servicio['origen_lat'] as num?)?.toDouble();
        final double? origLng = (servicio['origen_lng'] as num?)?.toDouble();
        final exclusivoStr = servicio['exclusivo_id']?.toString() ?? '';

        // T=0: Masters
        final mastersData = await Supabase.instance.client
            .from('usuarios')
            .select('id')
            .or('rol.eq.central,rol.eq.master,rango_movil.eq.MASTER')
            .neq('suspendido', true);
        final masterIds = mastersData.map((u) => u['id'].toString()).toList();
        if (masterIds.isNotEmpty) {
          await MotorNotificaciones.dispararRafa(
            idsDestinos: masterIds,
            titulo: '👑 NUEVO SERVICIO',
            mensaje: 'Invitado aprobó cotización — revisa el radar.',
            urgente: true,
          );
        }

        // T=30s: #1 de paradero
        final paraderoIds = exclusivoStr.isEmpty
            ? <String>[]
            : exclusivoStr
                .split(',')
                .map((e) => e.trim())
                .where((e) => e.isNotEmpty && !masterIds.contains(e))
                .toList();
        if (paraderoIds.isNotEmpty) {
          Future.delayed(const Duration(seconds: 30), () async {
            if (!mounted) return;
            final chk = await Supabase.instance.client
                .from('servicios').select('estado').eq('id', svcId).maybeSingle();
            if (chk == null || chk['estado'] != 'pendiente') return;
            await MotorNotificaciones.dispararRafa(
              idsDestinos: paraderoIds,
              titulo: 'TU TURNO DE PARADERO',
              mensaje: 'Servicio de Invitado disponible.',
              urgente: true,
            );
          });
        }

        // T=60s: radio 1km (no Masters, no paradero)
        Future.delayed(const Duration(seconds: 60), () async {
          if (!mounted) return;
          final chk = await Supabase.instance.client
              .from('servicios').select('estado').eq('id', svcId).maybeSingle();
          if (chk == null || chk['estado'] != 'pendiente') return;
          final candidatos = await Supabase.instance.client
              .from('usuarios')
              .select('id, latitud, longitud')
              .eq('rol', 'movil').eq('en_linea', true).neq('suspendido', true)
              .not('rango_movil', 'in', '("MASTER")');
          final idsZ = (candidatos as List).where((u) {
            final id = u['id'].toString();
            if (masterIds.contains(id) || paraderoIds.contains(id)) return false;
            if (origLat == null || origLng == null) return true;
            final uLat = (u['latitud'] as num?)?.toDouble();
            final uLng = (u['longitud'] as num?)?.toDouble();
            if (uLat == null || uLng == null) return false;
            return const Distance().as(
                  LengthUnit.Meter, LatLng(uLat, uLng), LatLng(origLat, origLng)) <= 1000;
          }).map((u) => u['id'].toString()).toList();
          if (idsZ.isNotEmpty) {
            await MotorNotificaciones.dispararRafa(
              idsDestinos: idsZ,
              titulo: '📡 SERVICIO CERCA (1km)',
              mensaje: 'Servicio de Invitado disponible.',
              urgente: true,
            );
          }
        });

        // T=90s: todos los disponibles (ola final)
        Future.delayed(const Duration(seconds: 90), () async {
          if (!mounted) return;
          final chk = await Supabase.instance.client
              .from('servicios').select('estado').eq('id', svcId).maybeSingle();
          if (chk == null || chk['estado'] != 'pendiente') return;
          final todos = await Supabase.instance.client
              .from('usuarios').select('id')
              .eq('rol', 'movil').eq('en_linea', true).neq('suspendido', true);
          final idsT = (todos as List)
              .map((u) => u['id'].toString())
              .where((id) => !masterIds.contains(id))
              .toList();
          if (idsT.isNotEmpty) {
            await MotorNotificaciones.dispararRafa(
              idsDestinos: idsT,
              titulo: '🚨 SERVICIO SIN TOMAR',
              mensaje: 'Servicio de Invitado sin asignar.',
              urgente: true,
            );
          }
        });
      }
    } catch (e) {}
    // ignore: empty_catches
  }

  Future<void> _abrirWhatsApp(String telefono, int idPedido) async {
    String numero = telefono.replaceAll(RegExp(r'[^0-9]'), '');
    if (numero.length == 10) numero = '57$numero';

    final String mensaje =
        'Hola, te envío el comprobante de pago del servicio #$idPedido de ServiExpress.';
    final Uri url = Uri.parse(
      'https://wa.me/$numero?text=${Uri.encodeComponent(mensaje)}',
    );

    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  // Fila de cuenta de pago — nombre fijo de la app + número + botón
  // de copiar, para que el invitado pueda pegarlo directo en su app
  // de pago sin tener que transcribirlo a mano.
  Widget _filaPagoInvitado(
    BuildContext context,
    String app,
    Color colorMarca,
    Color colorTexto,
    dynamic numero,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 90,
            padding: const EdgeInsets.symmetric(vertical: 7),
            decoration: BoxDecoration(
              color: colorMarca,
              borderRadius: BorderRadius.circular(6),
            ),
            alignment: Alignment.center,
            child: Text(
              app,
              style: TextStyle(
                color: colorTexto,
                fontWeight: FontWeight.bold,
                fontSize: 11,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              numero.toString(),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy, size: 16, color: Colors.blue),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
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

  // ── MOTOR DE CALIFICACIÓN INVITADO ─────────────────────────────────────────
  // El invitado no tiene cuenta, por eso calificador_id = null.
  // calificador_nombre se extrae del campo 'creador' ("Invitado: Juan").
  void _mostrarDialogoCalificacionInvitado(Map<String, dynamic> servicio) {
    int estrellas = 5;
    final comentarioCtrl = TextEditingController();
    bool procesando = false;

    // Extraer nombre del invitado del campo creador ("Invitado: Nombre")
    final String nombreInvitado = () {
      final creador = servicio['creador']?.toString() ?? '';
      if (creador.toLowerCase().startsWith('invitado:')) {
        return creador.substring('invitado:'.length).trim();
      }
      return 'Invitado';
    }();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text(
            'CALIFICAR SERVICIO',
            style: TextStyle(fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '¿Cómo estuvo tu servicio?\n¡Tu opinión mejora el servicio!',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black87, fontSize: 13),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (index) {
                  return IconButton(
                    iconSize: 36,
                    padding: EdgeInsets.zero,
                    icon: Icon(
                      index < estrellas ? Icons.star : Icons.star_border,
                      color: Colors.amber[600],
                    ),
                    onPressed: () =>
                        setDialogState(() => estrellas = index + 1),
                  );
                }),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: comentarioCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Comentario (Opcional)',
                  border: OutlineInputBorder(),
                  hintText: 'Ej: Muy rápido y amable',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: procesando ? null : () => Navigator.pop(ctx),
              child: const Text('CERRAR', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.black),
              onPressed: procesando
                  ? null
                  : () async {
                      setDialogState(() => procesando = true);
                      try {
                        await Supabase.instance.client
                            .from('calificaciones')
                            .upsert({
                              'servicio_id': servicio['id'],
                              'movil_id': servicio['movil_id'].toString(),
                              'calificador_tipo': 'invitado',
                              'calificador_id': null,
                              'calificador_nombre': nombreInvitado,
                              'estrellas': estrellas,
                              'comentario':
                                  comentarioCtrl.text.trim().isEmpty
                                  ? null
                                  : comentarioCtrl.text.trim(),
                            }, onConflict: 'servicio_id, calificador_tipo');

                        // Actualizar puntuación del móvil
                        await Supabase.instance.client.rpc(
                          'recalcular_puntuacion_movil',
                          params: {'p_movil_id': servicio['movil_id'].toString()},
                        );

                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('¡Gracias por tu calificación!'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      } catch (e) {
                        setDialogState(() => procesando = false);
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(content: Text('Error: $e')),
                          );
                        }
                      }
                    },
              child: procesando
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        color: Color(0xff3AF500),
                        strokeWidth: 2,
                      ),
                    )
                  : const Text(
                      'ENVIAR VALORACIÓN',
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
  // ── FIN MOTOR CALIFICACIÓN INVITADO ────────────────────────────────────────

  Widget _construirEstadoVisual(String estado, Map<String, dynamic> servicio) {
    Color colorEstado = Colors.grey;
    String titulo = 'Estado Desconocido';
    String descripcion = 'Cargando información del servicio...';
    IconData icono = Icons.help_outline;
    Widget? acciones;

    switch (estado) {
      case 'cotizacion':
        colorEstado = Colors.orange[800]!;
        titulo = 'ESPERANDO PRECIO';
        descripcion =
            'La Central está calculando la tarifa de tu ruta. No cierres esta pantalla.';
        icono = Icons.calculate_outlined;
        break;

      case 'cotizada':
        colorEstado = Colors.blue[800]!;
        titulo = 'COTIZACIÓN RECIBIDA';
        descripcion =
            'La Central asignó una tarifa de ${fmtPeso(servicio['tarifa'])} para tu servicio. ¿Deseas confirmar la solicitud?';
        icono = Icons.monetization_on_outlined;
        acciones = Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                  ),
                  onPressed: () => _procesarRespuestaCotizacion(
                    servicio,
                    false,
                  ), // <-- CAMBIO AQUÍ
                  child: const Text(
                    'RECHAZAR',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xff3AF500),
                    foregroundColor: Colors.black,
                  ),
                  onPressed: () => _procesarRespuestaCotizacion(
                    servicio,
                    true,
                  ), // <-- CAMBIO AQUÍ
                  child: const Text(
                    'APROBAR Y PEDIR',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        );
        break;

      case 'pendiente':
        colorEstado = Colors.black54;
        titulo = 'BUSCANDO MÓVIL';
        descripcion =
            'Tu pedido ya está en el radar de la Central. Buscando el Móvil disponible más cercano...';
        icono = Icons.radar;
        break;

      case 'en_ruta_origen':
        colorEstado = Colors.blue[600]!;
        titulo = 'MÓVIL EN CAMINO';
        descripcion = 'El Móvil va hacia el punto de recogida.';
        icono = Icons.motorcycle; // <-- MOTO EN VEZ DE BICI
        break;

      case 'en_origen':
        colorEstado = Colors.orange[600]!;
        titulo = 'MÓVIL EN EL LOCAL';
        descripcion = 'El Móvil está gestionando el servicio, ten paciencia.';
        icono = Icons.storefront;
        break;

      case 'en_ruta_destino':
        colorEstado = const Color(0xff3AF500);
        titulo = 'MÓVIL EN RUTA A DESTINO';
        descripcion = '¡Todo listo! El Móvil va en camino a la entrega final.';
        icono = Icons.motorcycle;
        break;

      case 'problema':
        colorEstado = Colors.red[800]!;
        titulo = 'NOVEDAD EN RUTA';
        descripcion =
            'Se presentó un retraso o inconveniente con tu entrega. La Central o Móvil se comunicará contigo de inmediato.';
        icono = Icons.warning_amber_rounded;
        break;

      case 'finalizado':
        colorEstado = Colors.green[700]!;
        titulo = 'SERVICIO COMPLETADO';
        descripcion =
            '¡El servicio se ha completado con éxito! Gracias por confiar en ServiExpress.';
        icono = Icons.check_circle_outline;
        break;

      case 'cancelado':
      case 'caducado':
        colorEstado = Colors.grey[700]!;
        titulo = 'SERVICIO CERRADO';
        descripcion = 'Este servicio fue cancelado o expiró por tiempo límite.';
        icono = Icons.block_rounded;
        break;
    }

    if (['en_ruta_origen', 'en_origen', 'en_ruta_destino'].contains(estado)) {
      acciones = FutureBuilder<List<Map<String, dynamic>>>(
        future: Supabase.instance.client
            .from('usuarios')
            .select(
              'nombre, usuario, telefono, pago_nequi, pago_daviplata, '
              'pago_bancolombia',
            )
            .eq('id', servicio['movil_id']),
        builder: (context, snapshot) {
          final movil = (snapshot.data != null && snapshot.data!.isNotEmpty)
              ? snapshot.data!.first
              : null;

          // FIX: un invitado (no registrado) solo debe ver el NÚMERO
          // de operación del móvil, nunca su nombre real — antes esta
          // pantalla mostraba 'Asignado a: Juan Pérez', exponiendo el
          // nombre real a cualquiera que tuviera el link de rastreo.
          String nombreMovil = '...';
          if (movil != null) {
            final usr = movil['usuario']?.toString() ?? '';
            final numStr = usr.replaceAll(RegExp(r'[^0-9]'), '');
            nombreMovil = numStr.isNotEmpty ? 'Móvil $numStr' : 'Móvil';
          }
          final telefono = movil != null ? movil['telefono'] : null;
          final bool tienePagos =
              movil != null &&
              ((movil['pago_nequi']?.toString().trim().isNotEmpty ?? false) ||
                  (movil['pago_daviplata']?.toString().trim().isNotEmpty ??
                      false) ||
                  (movil['pago_bancolombia']?.toString().trim().isNotEmpty ??
                      false));

          return Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.motorcycle, color: Colors.black54),
                    const SizedBox(width: 10),
                    Text(
                      'Asignado a: $nombreMovil',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              if (tienePagos)
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue[200]!),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'MÉTODO DE PAGO DEL MÓVIL',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                          fontSize: 11,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 10),
                      // ---> CORRECCIÓN: Se eliminó el "!" en movil['pago_nequi']
                      if (movil['pago_nequi']?.toString().trim().isNotEmpty ??
                          false)
                        _filaPagoInvitado(
                          context,
                          'Nequi',
                          const Color(0xFFE5007D),
                          Colors.white,
                          movil['pago_nequi'],
                        ),
                      if (movil['pago_daviplata']
                              ?.toString()
                              .trim()
                              .isNotEmpty ??
                          false)
                        _filaPagoInvitado(
                          context,
                          'Daviplata',
                          const Color(0xFFEE2A24),
                          Colors.white,
                          movil['pago_daviplata'],
                        ),
                      if (movil['pago_bancolombia']
                              ?.toString()
                              .trim()
                              .isNotEmpty ??
                          false)
                        _filaPagoInvitado(
                          context,
                          'Bancolombia',
                          const Color(0xFFFFCC00),
                          Colors.black,
                          movil['pago_bancolombia'],
                        ),
                      const SizedBox(height: 4),
                      if (telefono != null &&
                          telefono.toString().trim().isNotEmpty)
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xff25D366),
                              foregroundColor: Colors.white,
                              elevation: 0,
                            ),
                            onPressed: () =>
                                _abrirWhatsApp(telefono.toString(), servicio['id']),
                            icon: const Icon(
                              Icons.camera_alt_outlined,
                              size: 18,
                            ),
                            label: const Text(
                              'ENVIAR COMPROBANTE',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          );
        },
      );
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colorEstado.withValues(alpha: 0.3), width: 2),
          ),
          child: Column(
            children: [
              Icon(icono, size: 60, color: colorEstado),
              const SizedBox(height: 16),
              Text(
                titulo,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: colorEstado,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                descripcion,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.black54,
                  height: 1.4,
                ),
              ),
              if (acciones != null) acciones,
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_cargandoId) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: Color(0xff3AF500))),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: Text(
          'Seguimiento de Servicio',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.black,
        iconTheme: IconThemeData(color: Colors.white),
      ),
      body: _idPedido == null
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24.0),
                child: Text(
                  'No tienes ningún servicio activo registrado como invitado.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.black45,
                  ),
                ),
              ),
            )
          : StreamBuilder<List<Map<String, dynamic>>>(
              stream: _streamServicio,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting)
                  return const Center(
                    child: CircularProgressIndicator(color: Colors.black),
                  );
                if (!snapshot.hasData || snapshot.data!.isEmpty)
                  return const Center(
                    child: Text(
                      'No se encontró el servicio en la base de datos.',
                    ),
                  );

                final servicio = snapshot.data!.first;
                final estado = servicio['estado'];

                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      'Orden #${servicio['id']}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.black38,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '📍 Origen: ${servicio['origen']}',
                      style: const TextStyle(fontSize: 14),
                    ),
                    Text(
                      '🏁 Destino: ${servicio['destino']}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Divider(height: 30),

                    _construirEstadoVisual(estado, servicio),

                    // ── SECCIÓN CALIFICAR (solo invitados, solo finalizado) ──
                    if (estado == 'finalizado' &&
                        servicio['movil_id'] != null) ...[
                      const SizedBox(height: 20),
                      FutureBuilder<List<Map<String, dynamic>>>(
                        future: Supabase.instance.client
                            .from('calificaciones')
                            .select('estrellas')
                            .eq('servicio_id', servicio['id'])
                            .eq('calificador_tipo', 'invitado'),
                        builder: (context, snap) {
                          final yaCalifique = snap.hasData &&
                              snap.data!.isNotEmpty;
                          if (snap.connectionState ==
                              ConnectionState.waiting) {
                            return const SizedBox.shrink();
                          }
                          if (yaCalifique) {
                            final estrellasDadas =
                                snap.data!.first['estrellas'] as int;
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.amber[50],
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.amber[200]!),
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Tu calificación:',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                  Row(
                                    children: List.generate(5, (i) => Icon(
                                      i < estrellasDadas
                                          ? Icons.star
                                          : Icons.star_border,
                                      color: Colors.amber,
                                      size: 18,
                                    )),
                                  ),
                                ],
                              ),
                            );
                          }
                          return SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.amber[100],
                                foregroundColor: Colors.amber[900],
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              onPressed: () =>
                                  _mostrarDialogoCalificacionInvitado(servicio),
                              icon: const Icon(Icons.star_rate_rounded),
                              label: const Text(
                                'CALIFICAR SERVICIO',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                    // ── FIN SECCIÓN CALIFICAR ─────────────────────────
                  ],
                );
              },
            ),
    );
  }
}
