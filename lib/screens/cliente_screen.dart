import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:latlong2/latlong.dart';
import 'package:serviexpress_app/utils/widgets_compartidos.dart';
import 'package:serviexpress_app/utils/onesignal_api.dart';
import 'package:serviexpress_app/utils/permisos_criticos.dart';
import 'package:serviexpress_app/screens/cliente_mototaxi_form.dart';
import 'package:serviexpress_app/screens/cliente_delivery_form.dart';
import 'package:serviexpress_app/screens/cliente_shopping_form.dart';
import 'package:serviexpress_app/screens/cliente_food_form.dart';
import 'package:serviexpress_app/screens/chat_screen.dart';
import 'package:serviexpress_app/screens/pedidos_cliente_screen.dart';
import 'package:serviexpress_app/screens/cliente_perfil_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ClienteScreen extends StatefulWidget {
  final Map<String, dynamic> usuario;
  const ClienteScreen({super.key, required this.usuario});

  @override
  State<ClienteScreen> createState() => _ClienteScreenState();
}

class _ClienteScreenState extends State<ClienteScreen>
    with WidgetsBindingObserver {
  // ARQUITECTURA ANTI-PARPADEO + RECONEXIÓN — mismo patrón que Móvil,
  // Central y Local. Cliente era la única de las 4 pantallas
  // principales que todavía no lo tenía: sus streams se asignaban una
  // sola vez en initState y nunca se recuperaban solos si el canal de
  // Supabase se moría en silencio (cambio de red, app en segundo
  // plano un rato largo, etc.) — la única forma de recuperarse era
  // cerrar y volver a abrir la app.
  final StreamController<List<Map<String, dynamic>>> _ctrlServiciosActivos =
      StreamController<List<Map<String, dynamic>>>.broadcast();
  final StreamController<List<Map<String, dynamic>>> _ctrlMiPerfil =
      StreamController<List<Map<String, dynamic>>>.broadcast();
  Stream<List<Map<String, dynamic>>> get _streamServiciosActivos =>
      _ctrlServiciosActivos.stream;
  Stream<List<Map<String, dynamic>>> get _streamMiPerfil =>
      _ctrlMiPerfil.stream;
  StreamSubscription<List<Map<String, dynamic>>>? _subServiciosActivos;
  StreamSubscription<List<Map<String, dynamic>>>? _subMiPerfil;
  Timer? _reconexionTimer;

  final Set<int> _dialogosDeCalificacionMostrados = {};
  int _tabActual = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _construirStreams();
    _iniciarVigilanteDeConexion();

    // Aviso suave de notificaciones — corre en segundo plano, solo
    // interrumpe si detecta que están desactivadas. Nunca bloquea.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      verificarNotificacionesSuave(context);
    });
  }

  void _construirStreams() {
    _subServiciosActivos?.cancel();
    _subMiPerfil?.cancel();

    final crudoServicios = Supabase.instance.client
        .from('servicios')
        .stream(primaryKey: ['id'])
        .eq('cliente_id', widget.usuario['id'])
        .order('id', ascending: false)
        .limit(50);

    final crudoPerfil = Supabase.instance.client
        .from('usuarios')
        .stream(primaryKey: ['id'])
        .eq('id', widget.usuario['id']);

    _subServiciosActivos = crudoServicios.listen(
      (data) {
        if (!_ctrlServiciosActivos.isClosed) _ctrlServiciosActivos.add(data);
      },
      onError: (e) {
        if (!_ctrlServiciosActivos.isClosed) _ctrlServiciosActivos.addError(e);
      },
    );
    _subMiPerfil = crudoPerfil.listen(
      (data) {
        if (!_ctrlMiPerfil.isClosed) _ctrlMiPerfil.add(data);
      },
      onError: (e) {
        if (!_ctrlMiPerfil.isClosed) _ctrlMiPerfil.addError(e);
      },
    );
  }

  // Reconstruye cada 30s. No usa setState() — la reconexión es
  // invisible para el árbol de widgets.
  void _iniciarVigilanteDeConexion() {
    _reconexionTimer?.cancel();
    _reconexionTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      _construirStreams();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Momento de mayor riesgo: el cliente minimiza la app y al volver
    // el canal puede estar muerto. Reconstruimos de inmediato, sin
    // esperar los 30s.
    if (state == AppLifecycleState.resumed && mounted) {
      _construirStreams();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _reconexionTimer?.cancel();
    _subServiciosActivos?.cancel();
    _subMiPerfil?.cancel();
    _ctrlServiciosActivos.close();
    _ctrlMiPerfil.close();
    super.dispose();
  }

  // ---> PONLA AQUÍ, JUSTO DEBAJO DEL INITSTATE <---
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

  Future<void> _cancelarPedido(int id) async {
    // ... tu código sigue igual
    try {
      await Supabase.instance.client
          .from('servicios')
          .update({'estado': 'cancelado'})
          .eq('id', id);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cancelar: $e'),
            backgroundColor: Colors.red,
          ),
        );
    }
  }

  Future<void> _responderCotizacion(
    Map<String, dynamic> servicio,
    bool aprobada,
  ) async {
    final int id = servicio['id'] as int;
    try {
      await Supabase.instance.client
          .from('servicios')
          .update({
            'estado': aprobada ? 'pendiente' : 'cancelado',
            'observacion': aprobada
                ? 'Cotización aprobada por cliente.'
                : 'Cotización rechazada por cliente.',
          })
          .eq('id', id);

      if (!aprobada) return;

      // CASCADA A MÓVILES — misma lógica que local/central/invitado
      final String destino = servicio['destino']?.toString() ?? 'destino';
      final String msgAlerta = '🛵 Servicio cliente — $destino';
      final exclusivoStr = servicio['exclusivo_id']?.toString() ?? '';

      // T=0: Masters + Central
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
          mensaje: msgAlerta,
          urgente: true,
        );
      }

      // T+30s: paradero — misil con ID guardado
      final paraderoIds = exclusivoStr.isEmpty
          ? <String>[]
          : exclusivoStr
              .split(',')
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty && !masterIds.contains(e))
              .toList();
      if (paraderoIds.isNotEmpty) {
        final id30s = await MotorNotificaciones.programarMisilRetardado(
          externalIds: paraderoIds,
          titulo: 'TU TURNO DE PARADERO',
          mensaje: msgAlerta,
          segundosRetardo: 30,
        );
        if (id30s != null) {
          await Supabase.instance.client
              .from('servicios')
              .update({'onesignal_30s': id30s})
              .eq('id', id);
        }
      }

      // T+60s y T+90s sin mounted check (sobreviven si el widget navega)
      final double? origLat = (servicio['origen_lat'] as num?)?.toDouble();
      final double? origLng = (servicio['origen_lng'] as num?)?.toDouble();
      final List<String> mSnap = List<String>.from(masterIds);
      final List<String> pSnap = List<String>.from(paraderoIds);

      Future.delayed(const Duration(seconds: 60), () async {
        final chk = await Supabase.instance.client
            .from('servicios').select('estado').eq('id', id).maybeSingle();
        if (chk == null || chk['estado'] != 'pendiente') return;
        final candidatos = await Supabase.instance.client
            .from('usuarios').select('id, latitud, longitud')
            .eq('rol', 'movil').eq('en_linea', true).neq('suspendido', true)
            .not('rango_movil', 'in', '("MASTER")');
        final idsZ = (candidatos as List).where((u) {
          final uid = u['id'].toString();
          if (mSnap.contains(uid) || pSnap.contains(uid)) return false;
          if (origLat == null || origLng == null) return true;
          final uLat = (u['latitud'] as num?)?.toDouble();
          final uLng = (u['longitud'] as num?)?.toDouble();
          if (uLat == null || uLng == null) return false;
          return const Distance().as(LengthUnit.Meter,
              LatLng(uLat, uLng), LatLng(origLat, origLng)) <= 1000;
        }).map((u) => u['id'].toString()).toList();
        if (idsZ.isNotEmpty) {
          await MotorNotificaciones.dispararRafa(
              idsDestinos: idsZ, titulo: '📡 SERVICIO CERCA (1km)', mensaje: msgAlerta);
        }
      });

      Future.delayed(const Duration(seconds: 90), () async {
        final chk = await Supabase.instance.client
            .from('servicios').select('estado').eq('id', id).maybeSingle();
        if (chk == null || chk['estado'] != 'pendiente') return;
        final todos = await Supabase.instance.client
            .from('usuarios').select('id')
            .eq('rol', 'movil').eq('en_linea', true).neq('suspendido', true);
        final idsT = (todos as List)
            .map((u) => u['id'].toString())
            .where((uid) => !mSnap.contains(uid))
            .toList();
        if (idsT.isNotEmpty) {
          await MotorNotificaciones.dispararRafa(
              idsDestinos: idsT, titulo: '🚨 SERVICIO SIN TOMAR', mensaje: msgAlerta);
        }
      });
    } catch (e) {
      debugPrint('Error responderCotizacion: $e');
    }
  }

  Future<void> _abrirWhatsApp(String telefono, int idPedido) async {
    String numero = telefono.replaceAll(RegExp(r'[^0-9]'), '');
    if (numero.length == 10) numero = '57$numero';
    final Uri url = Uri.parse(
      'https://wa.me/$numero?text=${Uri.encodeComponent('Hola, soy el cliente del servicio #$idPedido de ServiExpress. Te escribo para coordinar.')}',
    );
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  Future<void> _enviarCalificacion(
    int servicioId,
    dynamic movilId,
    int estrellas,
    String comentario,
  ) async {
    try {
      // 1. Sellamos la calificación en el campo rápido de servicios (para
      //    el historial del cliente y el RPC de puntuación).
      await Supabase.instance.client
          .from('servicios')
          .update({
            'calificacion': estrellas,
            'comentario_cliente': comentario.isEmpty ? null : comentario,
          })
          .eq('id', servicioId);

      // 2. INSERT en calificaciones (fuente de verdad para móvil/central).
      //    UNIQUE(servicio_id) — ignoramos si ya existe (upsert).
      await Supabase.instance.client.from('calificaciones').upsert({
        'servicio_id': servicioId,
        'movil_id': movilId.toString(),
        'calificador_tipo': 'cliente',
        'calificador_id': widget.usuario['id'].toString(),
        'calificador_nombre': widget.usuario['nombre'].toString(),
        'estrellas': estrellas,
        'comentario': comentario.isEmpty ? null : comentario,
      }, onConflict: 'servicio_id, calificador_tipo');

      // 3. Recalculamos la puntuación del móvil — misma función SQL
      // centralizada que usa Local (recalcular_puntuacion_movil). Antes
      // este archivo SUMABA puntos sin límite (+5/-5 acumulado sobre lo
      // que ya hubiera), lo cual podía superar 5.0 con solo unas pocas
      // calificaciones de 5 estrellas seguidas — exactamente el "100pts"
      // detectado en la pestaña Flota de Central. Ahora es un promedio
      // real, siempre acotado entre 1.0 y 5.0.
      await Supabase.instance.client.rpc(
        'recalcular_puntuacion_movil',
        params: {'p_movil_id': movilId.toString()},
      );

      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('¡Gracias por valorar el servicio!'),
            backgroundColor: Colors.green,
          ),
        );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error al calificar: $e')));
    }
  }

  void _mostrarMenuCalificacion(Map<String, dynamic> servicio) {
    int estrellasSeleccionadas = 5;
    final comentarioCtrl = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
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
                '¡Tu servicio ha finalizado!\n¿Qué tal estuvo tu conductor?',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black87),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (index) {
                  return IconButton(
                    iconSize: 36,
                    padding: EdgeInsets.zero,
                    icon: Icon(
                      index < estrellasSeleccionadas
                          ? Icons.star
                          : Icons.star_border,
                      color: Colors.amber[600],
                    ),
                    onPressed: () => setDialogState(
                      () => estrellasSeleccionadas = index + 1,
                    ),
                  );
                }),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: comentarioCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Comentario (Opcional)',
                  border: OutlineInputBorder(),
                  hintText: 'Ej: Muy amable y rápido',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CERRAR', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.black),
              onPressed: () {
                Navigator.pop(context);
                _enviarCalificacion(
                  servicio['id'],
                  servicio['movil_id'],
                  estrellasSeleccionadas,
                  comentarioCtrl.text.trim(),
                );
              },
              child: const Text(
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

  Widget _construirEstadoVisual(String estado, Map<String, dynamic> servicio) {
    Color colorEstado = Colors.grey;
    String titulo = 'Estado Desconocido';
    String descripcion = 'Cargando...';
    IconData icono = Icons.help_outline;
    Widget? acciones;

    if (['en_ruta_origen', 'en_origen', 'en_ruta_destino'].contains(estado)) {
      if (estado == 'en_ruta_origen') {
        colorEstado = Colors.blue[600]!;
        titulo = 'MÓVIL EN CAMINO';
        descripcion = 'El conductor va hacia el punto de recogida.';
        icono = Icons.motorcycle;
      } else if (estado == 'en_origen') {
        colorEstado = Colors.orange[600]!;
        titulo = 'MÓVIL EN EL LOCAL';
        descripcion =
            'El conductor está gestionando tu encargo o esperando al pasajero.';
        icono = Icons.storefront;
      } else {
        colorEstado = const Color(0xff3AF500);
        titulo = 'MÓVIL EN RUTA A DESTINO';
        descripcion =
            '¡Todo listo! El conductor va en camino a la entrega final.';
        icono = Icons.motorcycle;
      }

      if (servicio['movil_id'] != null) {
        acciones = FutureBuilder<Map<String, dynamic>?>(
          future: Supabase.instance.client
              .from('usuarios')
              .select(
                'nombre, telefono, usuario, rol, foto_perfil_url, '
                'pago_nequi, pago_daviplata, pago_bancolombia',
              )
              .eq('id', servicio['movil_id'])
              .maybeSingle(),
          builder: (context, snapshot) {
            final movil = snapshot.data;
            String nombreMovil = '...';
            if (movil != null) {
              final rol = movil['rol']?.toString() ?? 'movil';
              if (rol == 'movil') {
                final usr = movil['usuario']?.toString() ?? '';
                final numStr = usr.replaceAll(RegExp(r'[^0-9]'), '');
                nombreMovil = numStr.isNotEmpty
                    ? 'Móvil $numStr'
                    : (movil['nombre']?.toString().toUpperCase() ?? 'Móvil');
              } else {
                nombreMovil = movil['nombre']?.toString() ?? 'Móvil';
              }
            }
            final telefono = movil != null ? movil['telefono'] : null;

            bool tieneMensajeNuevo = servicio['chat_cliente'] == true;

            Widget btnChatInterno = SizedBox(
              height: 40,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: tieneMensajeNuevo
                      ? Colors.red[700]
                      : Colors.black,
                  foregroundColor: tieneMensajeNuevo
                      ? Colors.white
                      : const Color(0xff3AF500),
                  elevation: 2,
                ),
                onPressed: () {
                  Supabase.instance.client
                      .from('servicios')
                      .update({'chat_cliente': false})
                      .eq('id', servicio['id']);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ChatScreen(
                        salaId: 'servicio_${servicio['id']}',
                        miId: widget.usuario['id'],
                        miNombre: widget.usuario['nombre'],
                        titulo: 'Chat con Móvil',
                        servicioId: servicio['id'],
                        alarmaLocal: 'chat_cliente',
                        alarmaDestino: 'chat_movil',
                        tipoFaq: TipoFaqChat.cliente,
                      ),
                    ),
                  );
                },
                icon: Icon(
                  tieneMensajeNuevo ? Icons.mark_email_unread : Icons.chat,
                  size: 18,
                ),
                label: Text(
                  tieneMensajeNuevo ? 'NUEVO MENSAJE' : 'CHAT INTERNO',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ),
            );

            return Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green[200]!),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Builder(
                        builder: (_) {
                          final String? fotoUrl =
                              movil?['foto_perfil_url']?.toString();
                          final bool tieneFoto =
                              fotoUrl != null && fotoUrl.isNotEmpty;
                          return CircleAvatar(
                            radius: 16,
                            backgroundColor: Colors.green[700],
                            backgroundImage:
                                tieneFoto ? NetworkImage(fotoUrl) : null,
                            child: !tieneFoto
                                ? Icon(
                                    Icons.person,
                                    color: Colors.white,
                                    size: 18,
                                  )
                                : null,
                          );
                        },
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Móvil: $nombreMovil',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                  if (movil != null &&
                      ((movil['pago_nequi']?.toString().isNotEmpty ?? false) ||
                          (movil['pago_daviplata']?.toString().isNotEmpty ?? false) ||
                          (movil['pago_bancolombia']?.toString().isNotEmpty ?? false)))
                    Padding(
                      padding: const EdgeInsets.only(top: 8, left: 42),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          if (movil['pago_nequi']?.toString().isNotEmpty ?? false)
                            _chipPagoCliente('Nequi', const Color(0xFFE5007D), Colors.white, movil['pago_nequi']),
                          if (movil['pago_daviplata']?.toString().isNotEmpty ?? false)
                            _chipPagoCliente('Daviplata', const Color(0xFFEE2A24), Colors.white, movil['pago_daviplata']),
                          if (movil['pago_bancolombia']?.toString().isNotEmpty ?? false)
                            _chipPagoCliente('Bancolombia', const Color(0xFFFFCC00), Colors.black, movil['pago_bancolombia']),
                        ],
                      ),
                    ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: tieneMensajeNuevo
                            ? PulsingWidget(child: btnChatInterno)
                            : btnChatInterno,
                      ),
                      if (telefono != null &&
                          telefono.toString().trim().isNotEmpty) ...[
                        const SizedBox(width: 8),
                        SizedBox(
                          height: 40,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xff25D366),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.all(0),
                            ),
                            onPressed: () =>
                                _abrirWhatsApp(telefono.toString(), servicio['id']),
                            child: const Icon(Icons.wechat, size: 22),
                          ),
                        ),
                      ],
                    ],
                  ),
                  // ENRUTAR — el cliente también puede sumarle otro
                  // encargo al mismo moto mientras sigue en camino,
                  // siempre visible mientras el servicio está activo.
                  if (movil != null &&
                      ['en_ruta_origen', 'en_origen', 'en_ruta_destino']
                          .contains(estado))
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.blue[700],
                            side: BorderSide(color: Colors.blue[300]!),
                            padding: const EdgeInsets.symmetric(vertical: 6),
                          ),
                          onPressed: () => _abrirEnrutarAlMoto(context, servicio, movil),
                          icon: const Icon(Icons.alt_route, size: 14),
                          label: const Text(
                            'ENRUTAR (sumar otro encargo)',
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ),

                  Builder(
                    builder: (context) {
                      bool tieneMensajeCentral =
                          servicio['chat_central_cliente'] == true;
                      bool mostrarChatCentral =
                          estado == 'problema' || tieneMensajeCentral;

                      if (!mostrarChatCentral) return const SizedBox.shrink();

                      Widget btnSoporte = SizedBox(
                        width: double.infinity,
                        height: 40,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: tieneMensajeCentral
                                ? Colors.red[700]
                                : Colors.grey[800],
                            foregroundColor: tieneMensajeCentral
                                ? Colors.white
                                : Colors.amberAccent,
                            elevation: 2,
                          ),
                          onPressed: () {
                            Supabase.instance.client
                                .from('servicios')
                                .update({'chat_central_cliente': false})
                                .eq('id', servicio['id']);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => ChatScreen(
                                  salaId: 'soporte_cliente_${servicio['id']}',
                                  miId: widget.usuario['id'],
                                  miNombre: widget.usuario['nombre'],
                                  titulo: 'Soporte Central',
                                  servicioId: servicio['id'],
                                  alarmaLocal: 'chat_central_cliente',
                                  alarmaDestino: 'chat_cliente_central',
                                  tipoFaq: TipoFaqChat.cliente,
                                ),
                              ),
                            );
                          },
                          icon: Icon(
                            tieneMensajeCentral
                                ? Icons.mark_email_unread
                                : Icons.support_agent,
                            size: 18,
                          ),
                          label: Text(
                            tieneMensajeCentral
                                ? 'MENSAJE DE CENTRAL'
                                : 'SOPORTE CENTRAL',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      );

                      return Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: tieneMensajeCentral
                            ? PulsingWidget(child: btnSoporte)
                            : btnSoporte,
                      );
                    },
                  ),
                ],
              ),
            );
          },
        );
      }
    } else {
      switch (estado) {
        case 'cotizacion':
          colorEstado = Colors.orange[800]!;
          titulo = 'ESPERANDO PRECIO';
          descripcion =
              'La Central está calculando la tarifa. No cierres la app.';
          icono = Icons.calculate_outlined;
          acciones = Padding(
            padding: const EdgeInsets.only(top: 16),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                ),
                onPressed: () => _cancelarPedido(servicio['id']),
                child: const Text(
                  'CANCELAR SOLICITUD',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          );
          break;
        case 'cotizada':
          colorEstado = Colors.blue[800]!;
          titulo = 'COTIZACIÓN RECIBIDA';
          descripcion =
              'La Central asignó tarifa de ${fmtPeso(servicio['tarifa'])}. ¿Confirmas?';
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
                    onPressed: () => _responderCotizacion(servicio, false),
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
                    onPressed: () => _responderCotizacion(servicio, true),
                    child: const Text(
                      'PEDIR MÓVIL',
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
          descripcion = 'Pedido en el radar. Buscando el Móvil más cercano...';
          icono = Icons.radar;
          acciones = Padding(
            padding: const EdgeInsets.only(top: 16),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                ),
                onPressed: () => _cancelarPedido(servicio['id']),
                child: const Text(
                  'CANCELAR BÚSQUEDA',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          );
          break;
        case 'problema':
          colorEstado = Colors.red[800]!;
          titulo = 'NOVEDAD EN RUTA';
          descripcion =
              'Retraso o novedad con tu entrega. Central te contactará.';
          icono = Icons.warning_amber_rounded;
          break;
      }
    }

    return Container(
      width: double.infinity,
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
    );
  }

  Widget _construirBotonServicio(
    BuildContext context, {
    required String titulo,
    required String descripcion,
    required Color colorBase,
    Color textColor = Colors.white,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Material(
        color: colorBase,
        borderRadius: BorderRadius.circular(12),
        elevation: 3,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        titulo,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: textColor,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        descripcion,
                        style: TextStyle(
                          fontSize: 13,
                          color: textColor.withValues(alpha: 0.85),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: textColor.withValues(alpha: 0.5),
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }


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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: Text(
          'ServiExpress | ${widget.usuario['nombre'].toString().split(' ')[0]}',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
        ),
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          // Solo el indicador de soporte permanece en AppBar (tiene alarma en tiempo real)
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: _streamMiPerfil,
            builder: (context, snap) {
              final tieneAlarma = snap.hasData && snap.data!.isNotEmpty && snap.data!.first['chat_central'] == true;
              Widget btn = IconButton(
                icon: Icon(
                  tieneAlarma ? Icons.mark_email_unread : Icons.support_agent,
                  color: tieneAlarma ? Colors.redAccent : const Color(0xff3AF500),
                ),
                tooltip: 'Soporte Central',
                onPressed: () {
                  Supabase.instance.client.from('usuarios').update({'chat_central': false}).eq('id', widget.usuario['id']);
                  Navigator.push(context, MaterialPageRoute(
                    builder: (_) => ChatScreen(
                      salaId: 'soporte_${widget.usuario['id']}',
                      miId: widget.usuario['id'],
                      miNombre: widget.usuario['nombre'],
                      titulo: 'Soporte Central',
                      usuarioId: widget.usuario['id'],
                      alarmaLocal: 'chat_central',
                      alarmaDestino: 'alarma_soporte',
                      tipoFaq: TipoFaqChat.cliente,
                    ),
                  ));
                },
              );
              return tieneAlarma ? PulsingWidget(child: btn) : btn;
            },
          ),
        ],
      ),
      body: _buildBodyTab(),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _tabActual,
        onTap: (i) => setState(() => _tabActual = i),
        backgroundColor: Colors.black,
        selectedItemColor: const Color(0xff3AF500),
        unselectedItemColor: Colors.white54,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_outlined), activeIcon: Icon(Icons.home_rounded), label: 'Inicio'),
          BottomNavigationBarItem(icon: Icon(Icons.history_rounded), label: 'Historial'),
          BottomNavigationBarItem(icon: Icon(Icons.person_outline_rounded), activeIcon: Icon(Icons.person_rounded), label: 'Mi Cuenta'),
        ],
      ),
    );
  }

  Widget _buildBodyTab() {
    switch (_tabActual) {
      case 1: return _buildTabHistorial();
      case 2: return _buildTabCuenta();
      default: return _buildTabInicio();
    }
  }

  Widget _buildTabInicio() {
    return StreamBuilder<List<Map<String, dynamic>>>(
        stream: _streamServiciosActivos,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.black),
            );
          }

          final todos = snapshot.data ?? [];
          final activos = todos
              .where(
                (s) => [
                  'cotizacion',
                  'cotizada',
                  'pendiente',
                  'en_ruta_origen',
                  'en_origen',
                  'en_ruta_destino',
                  'problema',
                ].contains(s['estado']),
              )
              .toList();

          final sinCalificar = todos
              .where(
                (s) =>
                    s['estado'] == 'finalizado' &&
                    s['calificacion'] == null &&
                    s['movil_id'] != null,
              )
              .toList();

          if (sinCalificar.isNotEmpty) {
            for (var svcACalificar in sinCalificar) {
              if (!_dialogosDeCalificacionMostrados.contains(
                svcACalificar['id'],
              )) {
                _dialogosDeCalificacionMostrados.add(svcACalificar['id']);
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) _mostrarMenuCalificacion(svcACalificar);
                });
                break;
              }
            }
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (activos.isNotEmpty) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.red[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red[300]!),
                    ),
                    child: const Text(
                      '⚠️ TIENES SERVICIOS EN CURSO\nEspera a que finalicen para pedir algo nuevo.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  ...activos.map((servicio) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.black,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Orden #${servicio['numero_cliente'] ?? servicio['id']}',
                                  style: const TextStyle(
                                    color: Colors.white54,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  'Tarifa: ${(servicio['tarifa'] == 0.0 || servicio['tarifa'] == null) ? 'Por Definir' : fmtPeso(servicio['tarifa'])}',
                                  style: const TextStyle(
                                    color: Color(0xff3AF500),
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          _construirEstadoVisual(servicio['estado'], servicio),
                        ],
                      ),
                    );
                  }),
                ] else ...[
                  Text(
                    'Hola, ${widget.usuario['nombre'].toString().split(' ')[0]} 👋',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '¿Qué quieres pedir hoy?',
                    style: TextStyle(fontSize: 14, color: Colors.black54),
                  ),
                  const SizedBox(height: 20),

                  // ── HÉROE: PEDIR A DOMICILIO ──────────────────────────
                  GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PedidosClienteScreen(usuario: widget.usuario),
                      ),
                    ),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF1B1B2F), Color(0xFF2D2D44)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(20),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: const Color(0xff3AF500),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Text('NUEVO',
                                          style: TextStyle(
                                              fontSize: 9,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.black,
                                              letterSpacing: 1)),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  '🛵 Pide a Domicilio',
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  'Restaurantes, tiendas y locales\nregistrados en ServiExpress.\nVer menú, elegir y listo.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.white70,
                                    height: 1.4,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: const Color(0xff3AF500),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Text(
                                    'Ver locales disponibles →',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                      color: Colors.black,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Text('🏪', style: TextStyle(fontSize: 56)),
                        ],
                      ),
                    ),
                  ),

                  // ── SECCIÓN: MÁS SERVICIOS ───────────────────────────
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text(
                      'MÁS SERVICIOS',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.3,
                        color: Colors.black45,
                      ),
                    ),
                  ),
                  _construirBotonServicio(
                    context,
                    titulo: '🏍️ Mototaxi',
                    descripcion:
                        'Transporte rápido y seguro para ti o un conocido.',
                    colorBase: const Color(0xff3AF500),
                    textColor: Colors.black,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            ClienteMototaxiForm(usuario: widget.usuario),
                      ),
                    ),
                  ),
                  _construirBotonServicio(
                    context,
                    titulo: '📦 Envío / Recogida',
                    descripcion:
                        'Llevar o traer un paquete, llave o documento.',
                    colorBase: Colors.blue[700]!,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            ClienteDeliveryForm(usuario: widget.usuario),
                      ),
                    ),
                  ),
                  _construirBotonServicio(
                    context,
                    titulo: '🍔 Comida (sin app)',
                    descripcion:
                        'Pedido en cualquier restaurante que no esté en la app.',
                    colorBase: Colors.red[600]!,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            ClienteFoodForm(usuario: widget.usuario),
                      ),
                    ),
                  ),
                  _construirBotonServicio(
                    context,
                    titulo: '🛒 Compras y Encargos',
                    descripcion:
                        'Danos tu lista de súper o farmacia, hacemos la fila por ti.',
                    colorBase: Colors.orange[800]!,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            ClienteShoppingForm(usuario: widget.usuario),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      );
  }

  // Chip de cuenta de pago — nombre fijo de la app + número. Mismo
  // patrón visual que Local, para que un cliente registrado sepa de
  // un vistazo cómo pagarle al moto si así lo acuerdan. Tocarlo copia
  // el número al portapapeles.
  // =========================================================================
  // ENRUTAR — el cliente le suma un encargo nuevo al mismo moto que
  // YA está en camino con su pedido activo. Asignación directa, sin
  // pasar por el radar, pero respetando el cupo real del rango del
  // moto — mismo mecanismo que en Local.
  // =========================================================================
  void _abrirEnrutarAlMoto(
    BuildContext context,
    Map<String, dynamic> servicio,
    Map<String, dynamic> moto,
  ) {
    final destinoCtrl = TextEditingController();
    final tarifaCtrl = TextEditingController();
    final notasCtrl = TextEditingController();
    bool procesando = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: const Row(
            children: [
              Icon(Icons.alt_route, color: Colors.blue),
              SizedBox(width: 8),
              Text('ENRUTAR', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Súmale otro encargo a este mismo moto, sin esperar a que termine el actual.',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: destinoCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Nuevo destino (*)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: tarifaCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Tarifa de este encargo',
                      border: OutlineInputBorder(),
                      isDense: true,
                      prefixText: '\$ ',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: notasCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Notas (opcional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: procesando ? null : () => Navigator.pop(ctx),
              child: const Text('CANCELAR'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
              onPressed: procesando
                  ? null
                  : () async {
                      if (destinoCtrl.text.trim().isEmpty) return;
                      setDialogState(() => procesando = true);
                      try {
                        final rango = (moto['rango_movil'] ?? 'NOVATO')
                            .toString()
                            .toUpperCase();
                        final limite = rango == 'MASTER'
                            ? 999
                            : rango == 'LEYENDA'
                                ? 3
                                : rango == 'ELITE'
                                    ? 2
                                    : 1;
                        final activos = await Supabase.instance.client
                            .from('servicios')
                            .select('id')
                            .eq('movil_id', moto['id'])
                            .inFilter('estado', [
                              'en_ruta_origen',
                              'en_origen',
                              'en_ruta_destino',
                              'problema',
                            ]);

                        if (activos.length >= limite) {
                          setDialogState(() => procesando = false);
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Ese móvil ya no tiene cupo disponible según su rango.',
                                ),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                          return;
                        }

                        int grupoId;
                        if (servicio['ruta_grupo_id'] != null) {
                          grupoId = servicio['ruta_grupo_id'] as int;
                        } else {
                          grupoId = servicio['id'] as int;
                          await Supabase.instance.client
                              .from('servicios')
                              .update({'ruta_grupo_id': grupoId})
                              .eq('id', servicio['id']);
                        }

                        await Supabase.instance.client.from('servicios').insert({
                          'origen': servicio['origen'],
                          'destino': destinoCtrl.text.trim().toUpperCase(),
                          'tarifa': double.tryParse(tarifaCtrl.text.trim()) ?? 0.0,
                          'observacion': notasCtrl.text.trim().isEmpty
                              ? null
                              : notasCtrl.text.trim(),
                          'estado': 'en_ruta_origen',
                          'movil_id': moto['id'],
                          'creador': widget.usuario['nombre'],
                          'cliente_id': widget.usuario['id'],
                          'metodo_pago': 'Efectivo',
                          'archivado': false,
                          'tipo_servicio': servicio['tipo_servicio'] ?? 'PAQUETERÍA',
                          'ruta_grupo_id': grupoId,
                          'accepted_at': DateTime.now().toUtc().toIso8601String(),
                        });

                        try {
                          await MotorNotificaciones.dispararMisil(
                            idDestino: moto['id'].toString(),
                            titulo: '🔗 NUEVO ENCARGO ENRUTADO',
                            mensaje:
                                '${widget.usuario['nombre']} te sumó otro encargo: ${destinoCtrl.text.trim().toUpperCase()}',
                            urgente: true,
                          );
                        } catch (_) {}

                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('✅ Encargo enrutado al mismo moto.'),
                              backgroundColor: Colors.blue,
                            ),
                          );
                        }
                      } catch (e) {
                        setDialogState(() => procesando = false);
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
                          );
                        }
                      }
                    },
              child: procesando
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : Text('ENRUTAR', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chipPagoCliente(
    String app,
    Color colorMarca,
    Color colorTexto,
    dynamic numero,
  ) {
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () {
        Clipboard.setData(ClipboardData(text: numero.toString()));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$app copiado: $numero'),
            backgroundColor: Colors.black,
            duration: const Duration(seconds: 2),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: colorMarca,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$app: $numero',
              style: TextStyle(
                color: colorTexto,
                fontWeight: FontWeight.bold,
                fontSize: 10,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.copy, size: 10, color: colorTexto.withValues(alpha: 0.8)),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // PESTAÑAS DE NAVEGACIÓN
  // =========================================================================

  Widget _buildTabHistorial() {
    return Container(
      color: const Color(0xFF0D0D0D),
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 20, 16, 8),
            child: Text('MIS PEDIDOS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white, letterSpacing: 1)),
          ),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: Supabase.instance.client
                  .from('servicios')
                  .select()
                  .eq('cliente_id', widget.usuario['id'])
                  .inFilter('estado', ['finalizado', 'cancelado', 'caducado', 'finalizado_por_demora', 'finalizado_con_problema'])
                  .order('id', ascending: false)
                  .limit(50),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: Colors.white));
                }
                final historial = snapshot.data ?? [];
                if (historial.isEmpty) {
                  return const Center(child: Text('No tienes pedidos en tu historial aún.', style: TextStyle(color: Colors.white54)));
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: historial.length,
                  itemBuilder: (context, index) {
                    final servicio = historial[index];
                    final estado = servicio['estado'];
                    Color colorTag = Colors.green;
                    String label = 'FINALIZADO';
                    if (estado == 'cancelado') { colorTag = Colors.black54; label = 'CANCELADO'; }
                    else if (estado == 'finalizado_por_demora') { colorTag = Colors.deepPurple; label = 'DEMORA'; }
                    else if (estado == 'caducado') { colorTag = Colors.purple[800]!; label = 'CADUCADO'; }
                    else if (estado == 'finalizado_con_problema' || (servicio['observacion'] ?? '').contains('[MARCA DE FALLA]')) {
                      colorTag = Colors.red[700]!; label = 'NOVEDAD';
                    }
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ListTile(
                            dense: true,
                            title: Text(
                              'Orden #${servicio['numero_cliente'] ?? servicio['id']} | ${servicio['origen']} ➔ ${servicio['destino']}',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Text(servicio['observacion'] ?? 'Sin notas.'),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  (servicio['tarifa'] == null || servicio['tarifa'] == 0) ? '' : fmtPeso(servicio['tarifa']),
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                ),
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(color: colorTag, borderRadius: BorderRadius.circular(4)),
                                  child: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 8)),
                                ),
                              ],
                            ),
                          ),
                          if (estado == 'finalizado' && servicio['movil_id'] != null)
                            Padding(
                              padding: const EdgeInsets.only(left: 16, bottom: 12, right: 16),
                              child: servicio['calificacion'] == null
                                  ? InkWell(
                                      onTap: () => _mostrarMenuCalificacion(servicio),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: Colors.amber[50],
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: Colors.amber[400]!),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.star, size: 14, color: Colors.orange),
                                            SizedBox(width: 4),
                                            Text('CALIFICAR SERVICIO', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.orange)),
                                          ],
                                        ),
                                      ),
                                    )
                                  : Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: List.generate(servicio['calificacion'] as int, (i) => const Icon(Icons.star, size: 14, color: Colors.amber)),
                                    ),
                            ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabCuenta() {
    final nombre = widget.usuario['nombre']?.toString() ?? '';
    final correo = widget.usuario['correo']?.toString() ?? '';
    final iniciales = nombre.trim().isNotEmpty
        ? nombre.trim().split(' ').map((p) => p.isNotEmpty ? p[0] : '').take(2).join().toUpperCase()
        : '?';

    return SingleChildScrollView(
      child: Column(
        children: [
          // Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
            decoration: const BoxDecoration(color: Colors.black),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 36,
                  backgroundColor: const Color(0xff3AF500),
                  child: Text(iniciales, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black)),
                ),
                const SizedBox(height: 12),
                Text(nombre, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                if (correo.isNotEmpty)
                  Text(correo, style: const TextStyle(color: Colors.white54, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Opciones principales
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.manage_accounts_outlined),
                  title: const Text('Mi Perfil', style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text('Nombre, dirección, cédula, facturación'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    final updated = await Navigator.push<Map<String, dynamic>>(
                      context,
                      MaterialPageRoute(builder: (_) => ClientePerfilScreen(usuario: widget.usuario)),
                    );
                    if (updated != null) _construirStreams();
                  },
                ),
                const Divider(height: 1),
                StreamBuilder<List<Map<String, dynamic>>>(
                  stream: _streamMiPerfil,
                  builder: (context, snap) {
                    final tieneAlarma = snap.hasData && snap.data!.isNotEmpty && snap.data!.first['chat_central'] == true;
                    return ListTile(
                      leading: Icon(
                        tieneAlarma ? Icons.mark_email_unread : Icons.support_agent,
                        color: tieneAlarma ? Colors.red : Colors.black,
                      ),
                      title: Text(
                        tieneAlarma ? 'Soporte — MENSAJE NUEVO' : 'Soporte Central',
                        style: TextStyle(fontWeight: FontWeight.bold, color: tieneAlarma ? Colors.red : Colors.black),
                      ),
                      subtitle: const Text('Habla con un operador'),
                      trailing: tieneAlarma
                          ? Container(width: 10, height: 10, decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle))
                          : const Icon(Icons.chevron_right),
                      onTap: () {
                        Supabase.instance.client.from('usuarios').update({'chat_central': false}).eq('id', widget.usuario['id']);
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => ChatScreen(
                            salaId: 'soporte_${widget.usuario['id']}',
                            miId: widget.usuario['id'],
                            miNombre: widget.usuario['nombre'],
                            titulo: 'Soporte Central',
                            usuarioId: widget.usuario['id'],
                            alarmaLocal: 'chat_central',
                            alarmaDestino: 'alarma_soporte',
                            tipoFaq: TipoFaqChat.cliente,
                          ),
                        ));
                      },
                    );
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('ZONA DE PELIGRO', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.red[400], letterSpacing: 1.2)),
            ),
          ),
          const SizedBox(height: 4),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.person_remove, color: Colors.red),
                  title: const Text('Eliminar mi cuenta', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                  subtitle: const Text('Esta acción no se puede deshacer'),
                  onTap: () => _eliminarMiCuenta(context),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.power_settings_new, color: Colors.red),
                  title: const Text('Cerrar sesión', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                  onTap: _cerrarSesionSegura,
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
