// ignore_for_file: curly_braces_in_flow_control_structures, no_leading_underscores_for_local_identifiers, use_build_context_synchronously
import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:serviexpress_app/screens/chat_screen.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter/services.dart';
import 'package:serviexpress_app/utils/widgets_compartidos.dart'; // FIX #10: widgets compartidos sin duplicados
import 'package:serviexpress_app/utils/sonido_manager.dart'; // Motor de audio in-app
import 'package:serviexpress_app/utils/onesignal_api.dart'; // Push a la Central
import 'package:onesignal_flutter/onesignal_flutter.dart'; // Login OneSignal
import 'package:serviexpress_app/utils/permisos_criticos.dart'; // Permisos críticos
import 'package:serviexpress_app/services/ota_updater.dart'; // OTA updates
import 'package:http/http.dart' as http;
import 'package:serviexpress_app/screens/carta_local_screen.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:serviexpress_app/utils/deeplink_service.dart';
import 'package:image_picker/image_picker.dart';

part 'local_screen_dispatch.dart';
part 'local_screen_cards.dart';
part 'local_screen_dialogs.dart';
part 'local_screen_formulario.dart';

class LocalScreen extends StatefulWidget {
  final Map<String, dynamic> usuario;
  const LocalScreen({super.key, required this.usuario});

  @override
  State<LocalScreen> createState() => _LocalScreenState();
}

class _LocalScreenState extends State<LocalScreen>
    with WidgetsBindingObserver, _CardsMixin, _DialogsMixin, _FormularioMixin, _DispatchMixin {
  // Memoria táctica para ocultar servicios del panel de hoy
  final Set<int> _serviciosOcultosLocal = {};

  // ---> INYECCIÓN: Controladores locales para la persistencia del perfil
  final _telLocalController = TextEditingController();
  final _instruccionesController = TextEditingController();
  @override
  String _tipoServicioDefecto = 'COMIDA';
  bool _perfilCargado = false;
  bool _guardandoPerfil = false;
  @override
  final SonidoManager _sonidos = SonidoManager();
  RealtimeChannel? _canalEstados;
  RealtimeChannel? _canalChat;

  // ARQUITECTURA ANTI-PARPADEO — mismo patrón que movil_screen.dart y
  // central_screen.dart. ANTES, los dos streams de esta pantalla se
  // construían DIRECTO dentro de build() — un canal nuevo en cada
  // reconstrucción del widget, lo que causaba parpadeo visible
  // constante (el StreamBuilder volvía a mostrar el spinner de carga
  // cada vez). Ahora viven en controllers estables que nunca cambian
  // de identidad — por debajo se pueden reconectar todas las veces
  // que haga falta sin que la UI lo note.
  final StreamController<List<Map<String, dynamic>>> _ctrlPerfilPropio =
      StreamController<List<Map<String, dynamic>>>.broadcast();
  final StreamController<List<Map<String, dynamic>>> _ctrlServiciosLocal =
      StreamController<List<Map<String, dynamic>>>.broadcast();
  Stream<List<Map<String, dynamic>>> get _streamPerfilPropio =>
      _ctrlPerfilPropio.stream;
  Stream<List<Map<String, dynamic>>> get _streamServiciosLocal =>
      _ctrlServiciosLocal.stream;
  StreamSubscription<List<Map<String, dynamic>>>? _subPerfilPropio;
  StreamSubscription<List<Map<String, dynamic>>>? _subServiciosLocal;
  Timer? _reconexionTimer;

  // Caché anti-parpadeo: evita spinner al reconectar cada 30s
  List<Map<String, dynamic>>? _cachePerfilPropio;
  List<Map<String, dynamic>>? _cacheServiciosLocal;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // ONESIGNAL — registrar identidad del local para recibir push
    // (cotización respondida, servicio asignado, etc.).
    // Debe hacerse en initState para que cuando Central notifique via
    // include_external_user_ids, el dispositivo ya esté enlazado.
    Future.microtask(() {
      OneSignal.login(widget.usuario['id'].toString());
    });

    // VIGILANTE DE CONEXIÓN — detectado en la prueba piloto: una
    // conexión websocket de larga duración puede morir en silencio.
    // El Local necesita ver todo en el momento exacto en que sucede
    // (cotizaciones respondidas, servicios nuevos) — sin esto, la
    // única forma de recuperarse era cerrar y volver a abrir la app.
    _construirStreams();
    _iniciarVigilanteDeConexion();

    // PERMISOS CRÍTICOS (Local) — solo Notificaciones + Batería, no el
    // gate completo de Móvil (Local no necesita GPS "siempre" — su
    // ubicación es fija — ni superposición). Chequeo SILENCIOSO
    // primero: la pantalla solo aparece si de verdad falta algo.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final faltaAlgo = await PermisosCriticosScreen.hayPermisosPendientes(
        permisosRequeridos: kPermisosLocal,
      );
      if (faltaAlgo && mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                const PermisosCriticosScreen(permisosRequeridos: kPermisosLocal),
            fullscreenDialog: true,
          ),
        );
      }
      // OTA: cubre sesión persistente (solo Android/iOS, no web)
      if (!kIsWeb && mounted) await OtaUpdater.verificar(context);
    });

    // Canal: detecta cambios de estado en los servicios de este local
    _canalEstados = Supabase.instance.client
        .channel('local_estados_${widget.usuario['id']}')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'servicios',
          callback: (payload) {
            final String estadoNuevo =
                payload.newRecord['estado']?.toString() ?? '';
            final String estadoAnterior =
                payload.oldRecord['estado']?.toString() ?? '';
            if (estadoNuevo == estadoAnterior || !mounted) return;

            // Central respondió la cotización → alerta fuerte
            if (estadoAnterior == 'cotizacion' && estadoNuevo == 'cotizada') {
              _sonidos.reproducir(Sonidos.localRespuesta);
            } else {
              // Cualquier otro cambio de estado → suave
              _sonidos.reproducirSuave(Sonidos.localEstado);
            }
          },
        )
        .subscribe();

    // Canal: detecta mensajes de chat nuevos
    _canalChat = Supabase.instance.client
        .channel('local_chat_${widget.usuario['id']}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'mensajes',
          callback: (payload) {
            final doc = payload.newRecord;
            if (doc.isEmpty || !mounted) return;
            final emisorId = doc['emisor_id']?.toString();
            final miId = widget.usuario['id']?.toString();
            if (emisorId != null && emisorId != miId) {
              _sonidos.reproducirSuave(Sonidos.localChat);
            }
          },
        )
        .subscribe();
  }

  // Reconstruye ambos streams reenviando hacia los controllers
  // estables — el StreamBuilder nunca se entera, nunca parpadea.
  void _construirStreams() {
    _subPerfilPropio?.cancel();
    _subServiciosLocal?.cancel();

    final crudoPerfil = Supabase.instance.client
        .from('usuarios')
        .stream(primaryKey: ['id'])
        .eq('id', widget.usuario['id']);

    final crudoServicios = Supabase.instance.client
        .from('servicios')
        .stream(primaryKey: ['id'])
        .eq('local_id', widget.usuario['id']) // FIX #4: ID único, no nombre
        // NOTA: stream() solo admite 1 .eq(). No se puede añadir
        // .eq('oculto_local', false) — rompe el SDK. Se filtra abajo.
        .order('id', ascending: false);

    _subPerfilPropio = crudoPerfil.listen(
      (data) {
        _cachePerfilPropio = data;
        if (!_ctrlPerfilPropio.isClosed) _ctrlPerfilPropio.add(data);
      },
      onError: (e) {
        if (!_ctrlPerfilPropio.isClosed) _ctrlPerfilPropio.addError(e);
      },
    );
    _subServiciosLocal = crudoServicios.listen(
      (data) {
        _cacheServiciosLocal = data;
        if (!_ctrlServiciosLocal.isClosed) _ctrlServiciosLocal.add(data);
      },
      onError: (e) {
        if (!_ctrlServiciosLocal.isClosed) _ctrlServiciosLocal.addError(e);
      },
    );
  }

  // Reconstruye cada 30s. No usa setState() — la reconexión es
  // invisible para el árbol de widgets, así que no hace falta forzar
  // ningún rebuild para lograrla.
  void _iniciarVigilanteDeConexion() {
    _reconexionTimer?.cancel();
    _reconexionTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      _construirStreams();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Momento de mayor riesgo: el local minimiza la app (cambia a
    // WhatsApp, etc.) y al volver el canal puede estar muerto.
    // Reconstruimos de inmediato, sin esperar los 30s.
    if (state == AppLifecycleState.resumed && mounted) {
      _construirStreams();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _canalEstados?.unsubscribe();
    _canalChat?.unsubscribe();
    _reconexionTimer?.cancel();
    _subPerfilPropio?.cancel();
    _subServiciosLocal?.cancel();
    _ctrlPerfilPropio.close();
    _ctrlServiciosLocal.close();
    _telLocalController.dispose();
    _instruccionesController.dispose();
    // _expansionTick se dispone en _CardsMixin.dispose() via super chain
    _sonidos.silenciar();
    super.dispose();
  }

  /// Deriva tipo_servicio desde categoria_local (fallback cuando no está guardado)
  String _tipoDesdeCategoria(String cat) {
    final s = cat.toLowerCase();
    if (s.contains('comida') || s.contains('restaurante') ||
        s.contains('panader') || s.contains('pastel')) return 'COMIDA';
    if (s.contains('bebidas') || s.contains('licores')) return 'BEBIDAS';
    if (s.contains('paquete')) return 'PAQUETERÍA';
    return 'COMPRAS';
  }

  bool _localEstaAbierto(Map<String, dynamic> perfil) {
    // Override manual: si activo == false, siempre cerrado
    if (perfil['activo'] == false) return false;
    final rawDias = perfil['dias_semana']?.toString();
    final apertura = perfil['horario_apertura']?.toString();
    final cierre = perfil['horario_cierre']?.toString();
    // Check day (weekday: Mon=1..Sun=7 in Dart)
    if (rawDias != null && rawDias.length == 7) {
      final idx = DateTime.now().weekday - 1; // Mon=0..Sun=6
      if (idx >= 0 && idx < 7 && rawDias[idx] == '0') return false;
    }
    // Check time
    if (apertura == null || cierre == null) return true;
    int toMin(String s) {
      final p = s.split(':');
      return (int.tryParse(p[0]) ?? 0) * 60 + (int.tryParse(p.length > 1 ? p[1] : '0') ?? 0);
    }
    final now = TimeOfDay.now();
    final nowMin = now.hour * 60 + now.minute;
    final aMin = toMin(apertura);
    final cMin = toMin(cierre);
    if (aMin < cMin) return nowMin >= aMin && nowMin < cMin;
    return nowMin >= aMin || nowMin < cMin;
  }

  Future<void> _toggleAbiertoCerrado(Map<String, dynamic> perfil) async {
    final nuevoActivo = !(perfil['activo'] != false);
    try {
      await Supabase.instance.client
          .from('usuarios')
          .update({'activo': nuevoActivo})
          .eq('id', perfil['id']);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(nuevoActivo ? '✅ Local abierto manualmente' : '🔒 Local cerrado manualmente'),
          backgroundColor: nuevoActivo ? Colors.green : Colors.red,
          duration: const Duration(seconds: 2),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    }
  }

  // --- MOTOR TÁCTICO: OBTENER O SELLAR COORDENADAS FIJAS ---
  @override
  Future<Map<String, double>?> _obtenerOSellarGPSLocal({
    bool forzar = false,
  }) async {
    double? lat = widget.usuario['lat_fija']?.toDouble();
    double? lng = widget.usuario['lng_fija']?.toDouble();

    // Si ya están selladas y no estamos forzando, las devuelve al instante sin gastar batería
    if (!forzar && lat != null && lng != null) {
      return {'lat': lat, 'lng': lng};
    }

    // Si no existen, escanea y sella la base
    bool gpsActivo = await Geolocator.isLocationServiceEnabled();
    if (!gpsActivo) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '⚠️ Activa el GPS del dispositivo para anclar la ubicación de tu local.',
            ),
          ),
        );
      }
      return null;
    }

    LocationPermission permiso = await Geolocator.checkPermission();
    if (permiso == LocationPermission.denied) {
      permiso = await Geolocator.requestPermission();
      if (permiso == LocationPermission.denied ||
          permiso == LocationPermission.deniedForever) {
        return null;
      }
    }

    try {
      Position pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      lat = pos.latitude;
      lng = pos.longitude;

      // 1. Sellar en Supabase
      await Supabase.instance.client
          .from('usuarios')
          .update({'lat_fija': lat, 'lng_fija': lng})
          .eq('id', widget.usuario['id']);

      // 2. Guardar en memoria activa para que no vuelva a pedirlo hoy
      setState(() {
        widget.usuario['lat_fija'] = lat;
        widget.usuario['lng_fija'] = lng;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '📍 Base sellada. Coordenadas del local guardadas con éxito.',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }

      return {'lat': lat, 'lng': lng};
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Error de GPS. Asegúrate de estar al aire libre para el primer escaneo.',
            ),
          ),
        );
      }
      return null;
    }
  }

  // --- VERIFICADOR VIP (PUNTO A PUNTO) ---
  bool _puedeUsarPuntoAPunto() {
    final ultimoUsoStr = widget.usuario['ultimo_punto_a_punto']?.toString();
    if (ultimoUsoStr == null || ultimoUsoStr.isEmpty) return true;
    try {
      final ultimoUso = DateTime.parse(ultimoUsoStr).toLocal();
      final hoy = DateTime.now();
      return !(ultimoUso.year == hoy.year &&
          ultimoUso.month == hoy.month &&
          ultimoUso.day == hoy.day);
    } catch (e) {
      return true;
    }
  }

  // ---> INYECCIÓN: NÚCLEO DE LA INTERFAZ CON EL PANEL DE PERFIL <---
  @override
  Widget build(BuildContext context) {
    // DefaultTabController FUERA del StreamBuilder — así el tab activo
    // no se resetea cuando el stream del perfil reconecta cada 30s.
    return DefaultTabController(
      length: 3,
      child: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _streamPerfilPropio,
        initialData: _cachePerfilPropio, // evita spinner al reconectar
        builder: (context, snapshotUsuario) {
          // Leemos el perfil en vivo de la BD para tener la config actualizada
          final perfilEnVivo =
              (snapshotUsuario.hasData && snapshotUsuario.data!.isNotEmpty)
              ? snapshotUsuario.data!.first
              : widget.usuario;

          // Inicializamos los campos del perfil la primera vez
          if (!_perfilCargado && snapshotUsuario.hasData) {
            _telLocalController.text =
                perfilEnVivo['telefono_local']?.toString() ?? '';
            _instruccionesController.text =
                perfilEnVivo['instrucciones_recogida']?.toString() ?? '';
            _tipoServicioDefecto =
                perfilEnVivo['tipo_servicio_defecto']?.toString() ??
                _tipoDesdeCategoria(perfilEnVivo['categoria_local']?.toString() ?? '');
            _perfilCargado = true;
          }

          return Scaffold(
            backgroundColor: const Color(0xFFF5F5F5),
            appBar: AppBar(
              title: Text(
                'Panel | ${perfilEnVivo['nombre']}',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              backgroundColor: Colors.black,
              iconTheme: IconThemeData(color: Colors.white),
              bottom: const TabBar(
                labelColor: Color(0xff3AF500),
                unselectedLabelColor: Colors.white70,
                indicatorColor: Color(0xff3AF500),
                tabs: [
                  Tab(icon: Icon(Icons.motorcycle), text: 'ACTIVOS'),
                  Tab(icon: Icon(Icons.history), text: 'HISTORIAL'),
                  Tab(
                    icon: Icon(Icons.storefront),
                    text: 'MI LOCAL',
                  ), // <--- Nueva pestaña de control
                ],
              ),
              // Borramos las "actions" de aquí porque ahora viven en "MI LOCAL"
            ),
            body: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _streamServiciosLocal,
              initialData: _cacheServiciosLocal, // evita spinner al reconectar
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(color: Colors.black),
                  );
                }

                // FIX #5 (client-side): stream() no soporta 2 .eq() simultáneos.
                // Aceptable: el stream ya está acotado por local_id.
                final todos = (snapshot.data ?? [])
                    .where((s) => s['oculto_local'] != true)
                    .toList();

                todos.sort((a, b) {
                  final fA =
                      a['created_at'] !=
                          null // FIX: era null3 (typo)
                      ? DateTime.parse(a['created_at'])
                      : DateTime.fromMillisecondsSinceEpoch(0);
                  final fB = b['created_at'] != null
                      ? DateTime.parse(b['created_at'])
                      : DateTime.fromMillisecondsSinceEpoch(0);
                  return fB.compareTo(fA);
                });

                final activos = todos
                    .where(
                      (s) => [
                        'programado', // <--- INYECCIÓN: PARA QUE NO SEA INVISIBLE
                        'pendiente',
                        'en_curso',
                        'en_ruta_origen',
                        'en_origen',
                        'en_ruta_destino',
                        'problema',
                        'cotizacion',
                        'cotizada',
                        'cotizacion_aprobada',
                      ].contains(s['estado']),
                    )
                    .toList();

                final hoy = DateTime.now();
                final historial = todos.where((s) {
                  if (![
                    'finalizado',
                    'cancelado',
                    'caducado',
                    'finalizado_por_demora',
                    'finalizado_con_problema',
                  ].contains(s['estado'])) {
                    return false;
                  }
                  if (_serviciosOcultosLocal.contains(s['id'])) return false;

                  if (s['created_at'] != null) {
                    final fechaSvc = DateTime.parse(s['created_at']).toLocal();
                    return fechaSvc.year == hoy.year &&
                        fechaSvc.month == hoy.month &&
                        fechaSvc.day == hoy.day;
                  }
                  return false;
                }).toList();

                // Calculamos el volumen de entregas limpias de hoy
                final countFinalizadosHoy = todos.where((s) {
                  if (s['estado'] != 'finalizado') return false;
                  if (s['created_at'] != null) {
                    final fechaSvc = DateTime.parse(s['created_at']).toLocal();
                    return fechaSvc.year == hoy.year &&
                        fechaSvc.month == hoy.month &&
                        fechaSvc.day == hoy.day;
                  }
                  return false;
                }).length;

                // Stats rápidos para el KPI bar del historial
                final puedeVip = _puedeUsarPuntoAPunto();
                final histFinalizados = historial.where((s) => s['estado'] == 'finalizado').length;
                final histCancelados = historial.where((s) => s['estado'] == 'cancelado').length;

                // Helper chip para KPI bar
                Widget kpiBar(String val, String label, Color color) => Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(val, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color)),
                    Text(label, style: const TextStyle(fontSize: 9, color: Colors.black45)),
                  ]),
                );

                return TabBarView(
                  children: [
                    // --- PESTAÑA 1: ACTIVOS ---
                    Column(
                      children: [
                        // ── PANEL DE ACCIONES 2×2 ─────────────────────────
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                          color: Colors.white,
                          child: Column(
                            children: [
                              // Fila 1: Solicitar + Cotizar
                              Row(children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xff3AF500),
                                      foregroundColor: Colors.black,
                                      padding: const EdgeInsets.symmetric(vertical: 11),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                    onPressed: () => _abrirFormularioPedido(context,
                                        esCotizacion: false, perfilEnVivo: perfilEnVivo),
                                    icon: const Icon(Icons.motorcycle, size: 18),
                                    label: const Text('SOLICITAR MÓVIL',
                                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.orange[800],
                                      side: BorderSide(color: Colors.orange[800]!),
                                      padding: const EdgeInsets.symmetric(vertical: 11),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                    onPressed: () => _abrirFormularioPedido(context,
                                        esCotizacion: true, perfilEnVivo: perfilEnVivo),
                                    icon: const Icon(Icons.request_quote, size: 18),
                                    label: const Text('COTIZAR',
                                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                  ),
                                ),
                              ]),
                              const SizedBox(height: 8),
                              // Fila 2: Punto a Punto + VIP
                              Row(children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: puedeVip ? Colors.purple[800] : Colors.grey[300],
                                      foregroundColor: puedeVip ? Colors.white : Colors.grey[600],
                                      padding: const EdgeInsets.symmetric(vertical: 10),
                                      elevation: puedeVip ? 2 : 0,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                    onPressed: puedeVip
                                        ? () => _abrirFormularioPedido(context,
                                            esPuntoAPunto: true, perfilEnVivo: perfilEnVivo)
                                        : null,
                                    icon: const Icon(Icons.flash_on, size: 17),
                                    label: Text(
                                      puedeVip ? 'PUNTO A PUNTO' : 'P.A.P AGOTADO',
                                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: const Color(0xFFB8860B),
                                      side: const BorderSide(color: Color(0xFFB8860B)),
                                      padding: const EdgeInsets.symmetric(vertical: 10),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                    onPressed: () => _abrirFormularioPedido(context,
                                        esVip: true, perfilEnVivo: perfilEnVivo),
                                    icon: const Text('👑', style: TextStyle(fontSize: 14)),
                                    label: const Text('VIP · +\$3.000',
                                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                                  ),
                                ),
                              ]),
                            ],
                          ),
                        ),
                        const Divider(height: 1, color: Colors.black26),
                        Expanded(
                          child: activos.isEmpty
                              ? const Center(
                                  child: Text(
                                    'No tienes servicios en curso.',
                                    style: TextStyle(
                                      color: Colors.black54,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                )
                              : ValueListenableBuilder<int>(
                                  valueListenable: _expansionTick,
                                  builder: (_, __, ___) => ListView.builder(
                                    padding: const EdgeInsets.all(12),
                                    itemCount: activos.length,
                                    itemBuilder: (c, i) => RepaintBoundary(
                                      child: FadeSlideIn(
                                        key: ValueKey('activo_local_${activos[i]['id']}'),
                                        child: _construirTarjetaServicio(activos[i]),
                                      ),
                                    ),
                                  ),
                                ),
                        ),
                      ],
                    ),

                    // --- PESTAÑA 2: HISTORIAL ---
                    historial.isEmpty
                        ? const Center(
                            child: Text(
                              'Tu historial está limpio.',
                              style: TextStyle(
                                color: Colors.black54,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          )
                        : Column(
                            children: [
                              // ── KPI BAR ─────────────────────────────
                              Container(
                                color: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                                child: Row(
                                  children: [
                                    kpiBar('${historial.length}', 'Total hoy', Colors.black87),
                                    kpiBar('$histFinalizados', 'Entregados', Colors.green[700]!),
                                    kpiBar('$histCancelados', 'Cancelados', Colors.red[700]!),
                                  ],
                                ),
                              ),
                              const Divider(height: 1, color: Colors.black12),
                              // ── LISTA ────────────────────────────────
                              Expanded(
                                child: ValueListenableBuilder<int>(
                                  valueListenable: _expansionTick,
                                  builder: (_, __, ___) => ListView.builder(
                                    padding: const EdgeInsets.all(12),
                                    itemCount: historial.length,
                                    itemBuilder: (c, i) => RepaintBoundary(
                                      child: FadeSlideIn(
                                        key: ValueKey('hist_local_${historial[i]['id']}'),
                                        child: _construirTarjetaServicio(
                                          historial[i],
                                          esHistorial: true,
                                          onOcultar: () => setState(
                                            () => _serviciosOcultosLocal.add(
                                              historial[i]['id'],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),

                    // --- PESTAÑA 3: MI LOCAL (HUB) ---
                    SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(14, 14, 14, 80),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ── HEADER ─────────────────────────────────
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.black,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Row(
                              children: [
                                GestureDetector(
                                  onTap: () async {
                                    final picker = ImagePicker();
                                    final img = await picker.pickImage(
                                        source: ImageSource.gallery, imageQuality: 75);
                                    if (img == null) return;
                                    try {
                                      final bytes = await img.readAsBytes();
                                      final path =
                                          'perfil_local_${perfilEnVivo['id']}_${DateTime.now().millisecondsSinceEpoch}.jpg';
                                      await Supabase.instance.client.storage
                                          .from('avatars')
                                          .uploadBinary(path, bytes,
                                              fileOptions: const FileOptions(
                                                  contentType: 'image/jpeg',
                                                  upsert: true));
                                      final url = Supabase.instance.client.storage
                                          .from('avatars')
                                          .getPublicUrl(path);
                                      await Supabase.instance.client
                                          .from('usuarios')
                                          .update({'foto_perfil_url': url})
                                          .eq('id', perfilEnVivo['id']);
                                      if (mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(
                                                content: Text('✅ Foto actualizada'),
                                                backgroundColor: Colors.green));
                                      }
                                    } catch (e) {
                                      if (mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                                content: Text('Error: $e'),
                                                backgroundColor: Colors.red));
                                      }
                                    }
                                  },
                                  child: () {
                                    final fotoUrl = perfilEnVivo['foto_perfil_url']?.toString();
                                    final tieneFoto = fotoUrl != null && fotoUrl.isNotEmpty;
                                    return Stack(
                                      children: [
                                        CircleAvatar(
                                          radius: 26,
                                          backgroundColor: const Color(0xff3AF500),
                                          backgroundImage: tieneFoto ? NetworkImage(fotoUrl) : null,
                                          onBackgroundImageError: tieneFoto ? (_, __) {} : null,
                                          child: !tieneFoto
                                              ? const Icon(Icons.storefront, color: Colors.black, size: 24)
                                              : null,
                                        ),
                                        Positioned(
                                          bottom: 0,
                                          right: 0,
                                          child: Container(
                                            width: 16,
                                            height: 16,
                                            decoration: const BoxDecoration(
                                              color: Colors.white,
                                              shape: BoxShape.circle,
                                            ),
                                            child: const Icon(Icons.camera_alt, size: 10, color: Colors.black),
                                          ),
                                        ),
                                      ],
                                    );
                                  }(),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        perfilEnVivo['nombre']?.toString() ?? 'Mi Local',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                        ),
                                      ),
                                      Row(
                                        children: [
                                          Text(
                                            '$countFinalizadosHoy servicios hoy',
                                            style: const TextStyle(
                                              color: Color(0xff3AF500),
                                              fontSize: 12,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Builder(builder: (ctx) {
                                            final abierto = _localEstaAbierto(perfilEnVivo);
                                            return GestureDetector(
                                              onTap: () => _toggleAbiertoCerrado(perfilEnVivo),
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                decoration: BoxDecoration(
                                                  color: abierto ? const Color(0xff3AF500) : Colors.red,
                                                  borderRadius: BorderRadius.circular(20),
                                                ),
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Text(
                                                      abierto ? 'ABIERTO' : 'CERRADO',
                                                      style: TextStyle(
                                                        color: abierto ? Colors.black : Colors.white,
                                                        fontSize: 10,
                                                        fontWeight: FontWeight.bold,
                                                        letterSpacing: 0.5,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 4),
                                                    Icon(
                                                      Icons.touch_app,
                                                      size: 10,
                                                      color: abierto ? Colors.black54 : Colors.white70,
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            );
                                          }),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 18),

                          // ── SECCIÓN 1: CARTA ────────────────────────
                          const Padding(
                            padding: EdgeInsets.only(left: 2, bottom: 8),
                            child: Text('MENÚ Y CARTA',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.3,
                                    color: Colors.black45)),
                          ),
                          _hubCard(
                            icon: Icons.restaurant_menu,
                            iconColor: Colors.white,
                            iconBg: Colors.green,
                            title: 'Mi Carta',
                            subtitle: 'Productos, categorías y precios',
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => CartaLocalScreen(
                                  localId: perfilEnVivo['id'] as int,
                                  localNombre: perfilEnVivo['nombre']?.toString() ?? 'Mi Local',
                                  initialTab: 0,
                                ),
                              ),
                            ),
                            secondaryAction: Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.teal,
                                    side: const BorderSide(color: Colors.teal),
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    minimumSize: Size.zero,
                                  ),
                                  icon: const Icon(Icons.qr_code_2, size: 14),
                                  label: const Text('Compartir QR', style: TextStyle(fontSize: 11)),
                                  onPressed: () => _mostrarQrCarta(perfilEnVivo),
                                ),
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.green[700],
                                    side: BorderSide(color: Colors.green[300]!),
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    minimumSize: Size.zero,
                                  ),
                                  icon: const Icon(Icons.menu_book_rounded, size: 14),
                                  label: const Text('Lista precios', style: TextStyle(fontSize: 11)),
                                  onPressed: () => _abrirPanelTarifario(context),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 18),

                          // ── SECCIÓN 2: DOMICILIOS ───────────────────
                          const Padding(
                            padding: EdgeInsets.only(left: 2, bottom: 8),
                            child: Text('DOMICILIOS SERVIEXPRESS',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.3,
                                    color: Colors.black45)),
                          ),
                          _hubCard(
                            icon: Icons.delivery_dining,
                            iconColor: Colors.black,
                            iconBg: const Color(0xff3AF500),
                            title: 'Pedidos Entrantes',
                            subtitle: 'Ver y gestionar pedidos en tiempo real',
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => CartaLocalScreen(
                                  localId: perfilEnVivo['id'] as int,
                                  localNombre: perfilEnVivo['nombre']?.toString() ?? 'Mi Local',
                                  initialTab: 1,
                                ),
                              ),
                            ),
                            secondaryAction: Row(
                              children: [
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.deepPurple,
                                    side: const BorderSide(color: Colors.deepPurple),
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    minimumSize: Size.zero,
                                  ),
                                  icon: const Icon(Icons.tune, size: 14),
                                  label: const Text('Config. domicilios', style: TextStyle(fontSize: 11)),
                                  onPressed: () => _abrirConfigDomicilios(perfilEnVivo),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 18),

                          // ── SECCIÓN 3: PERFIL & CONFIG ──────────────
                          const Padding(
                            padding: EdgeInsets.only(left: 2, bottom: 8),
                            child: Text('PERFIL Y CONFIGURACIÓN',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.3,
                                    color: Colors.black45)),
                          ),
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.05),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Tipo de Servicio por Defecto',
                                    style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black54)),
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  decoration: BoxDecoration(
                                    border: Border.all(color: Colors.grey[300]!),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<String>(
                                      value: _tipoServicioDefecto,
                                      isExpanded: true,
                                      items: ['COMIDA', 'BEBIDAS', 'COMPRAS', 'PAQUETERÍA']
                                          .map((v) => DropdownMenuItem(
                                                value: v,
                                                child: Text(v,
                                                    style: const TextStyle(
                                                        fontWeight: FontWeight.bold,
                                                        fontSize: 13)),
                                              ))
                                          .toList(),
                                      onChanged: (v) {
                                        if (v != null) setState(() => _tipoServicioDefecto = v);
                                      },
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 14),
                                TextField(
                                  controller: _telLocalController,
                                  keyboardType: TextInputType.phone,
                                  decoration: InputDecoration(
                                    labelText: 'WhatsApp del Local',
                                    border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8)),
                                    prefixIcon: const Icon(Icons.phone),
                                    isDense: true,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: _instruccionesController,
                                  maxLines: 2,
                                  decoration: InputDecoration(
                                    labelText: 'Instrucciones de Recogida',
                                    hintText: 'Ej: Quitarse el casco, etc...',
                                    border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8)),
                                    prefixIcon: const Icon(Icons.assignment),
                                  ),
                                ),
                                const SizedBox(height: 14),
                                SizedBox(
                                  width: double.infinity,
                                  height: 46,
                                  child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.black,
                                      shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(10)),
                                    ),
                                    onPressed: _guardandoPerfil
                                        ? null
                                        : () async {
                                            setState(() => _guardandoPerfil = true);
                                            try {
                                              await Supabase.instance.client
                                                  .from('usuarios')
                                                  .update({
                                                    'tipo_servicio_defecto': _tipoServicioDefecto,
                                                    'telefono_local': _telLocalController.text.trim(),
                                                    'instrucciones_recogida': _instruccionesController.text.trim(),
                                                  }).eq('id', perfilEnVivo['id']);
                                              if (context.mounted) {
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  const SnackBar(
                                                      content: Text('✅ Perfil actualizado.'),
                                                      backgroundColor: Colors.green),
                                                );
                                              }
                                            } catch (e) {
                                              if (context.mounted) {
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  SnackBar(
                                                      content: Text('Error: $e'),
                                                      backgroundColor: Colors.red),
                                                );
                                              }
                                            } finally {
                                              setState(() => _guardandoPerfil = false);
                                            }
                                          },
                                    child: _guardandoPerfil
                                        ? const SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                                color: Color(0xff3AF500), strokeWidth: 2))
                                        : const Text('GUARDAR CAMBIOS',
                                            style: TextStyle(
                                                color: Color(0xff3AF500),
                                                fontWeight: FontWeight.bold)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 18),

                          // ── OPCIONES ADICIONALES ────────────────────
                          const Padding(
                            padding: EdgeInsets.only(left: 2, bottom: 8),
                            child: Text('MÁS OPCIONES',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.3,
                                    color: Colors.black45)),
                          ),
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.04),
                                  blurRadius: 4,
                                ),
                              ],
                            ),
                            child: Column(
                              children: [
                                Builder(builder: (ctx) {
                                  final apertura = perfilEnVivo['horario_apertura']?.toString();
                                  final cierre = perfilEnVivo['horario_cierre']?.toString();
                                  final horaStr = (apertura != null && cierre != null)
                                      ? '${apertura.substring(0, 5)} – ${cierre.substring(0, 5)}'
                                      : 'Sin horario configurado';
                                  return _hubListTile(
                                    icon: Icons.schedule,
                                    iconColor: Colors.teal,
                                    title: 'Horario de Atención',
                                    subtitle: horaStr,
                                    onTap: () => _abrirConfigDomicilios(perfilEnVivo),
                                  );
                                }),
                                const Divider(height: 1),
                                _hubListTile(
                                  icon: Icons.folder_shared,
                                  iconColor: Colors.grey,
                                  title: 'Bóveda Historial General',
                                  onTap: () => _mostrarHistorialGlobal(context),
                                ),
                                const Divider(height: 1),
                                _hubListTile(
                                  icon: Icons.people_alt,
                                  iconColor: Colors.purple,
                                  title: 'Directorio de Clientes (CRM)',
                                  subtitle: 'Compras, estadísticas y retargeting',
                                  onTap: () => _abrirCRMLocal(context, perfilEnVivo),
                                ),
                                const Divider(height: 1),
                                _hubListTile(
                                  icon: Icons.add_location_alt,
                                  iconColor: Colors.orangeAccent,
                                  title: 'Configurar Ubicación del Local',
                                  onTap: () => _abrirMenuUbicacion(),
                                ),
                                const Divider(height: 1),
                                Builder(
                                  builder: (ctx) {
                                    final tieneAlarma = perfilEnVivo['chat_central'] == true;
                                    return _hubListTile(
                                      icon: tieneAlarma
                                          ? Icons.mark_email_unread
                                          : Icons.support_agent,
                                      iconColor: tieneAlarma ? Colors.red : Colors.blue[800]!,
                                      title: 'Soporte Central',
                                      onTap: () {
                                        Supabase.instance.client
                                            .from('usuarios')
                                            .update({'chat_central': false})
                                            .eq('id', perfilEnVivo['id']);
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => ChatScreen(
                                              salaId: 'soporte_${perfilEnVivo['id']}',
                                              miId: perfilEnVivo['id'],
                                              miNombre: perfilEnVivo['nombre'],
                                              titulo: 'Soporte Central',
                                              usuarioId: perfilEnVivo['id'],
                                              alarmaLocal: 'chat_central',
                                              alarmaDestino: 'alarma_soporte',
                                              tipoFaq: TipoFaqChat.local,
                                            ),
                                          ),
                                        );
                                      },
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),

                          // ── CUENTA ──────────────────────────────────
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.04),
                                  blurRadius: 4,
                                ),
                              ],
                            ),
                            child: Column(
                              children: [
                                _hubListTile(
                                  icon: Icons.person_remove,
                                  iconColor: Colors.red,
                                  title: 'Eliminar Mi Cuenta',
                                  onTap: () => _eliminarMiCuenta(context),
                                ),
                                const Divider(height: 1),
                                _hubListTile(
                                  icon: Icons.power_settings_new,
                                  iconColor: Colors.redAccent,
                                  title: 'Cerrar Sesión',
                                  onTap: _cerrarSesionSegura,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          );   // Scaffold
        },     // outer StreamBuilder builder
      ),       // outer StreamBuilder (child: de DefaultTabController)
    );         // DefaultTabController
  }
}
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      