import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'dart:async';
import 'package:url_launcher/url_launcher.dart';
import 'package:serviexpress_app/screens/reporte_financiero_screen.dart';
import 'package:serviexpress_app/utils/onesignal_api.dart';
import 'package:serviexpress_app/screens/chat_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:serviexpress_app/screens/ranking_screen.dart'; // FIX #7: fuente única de verdad para el ranking
import 'package:serviexpress_app/screens/monitor_pedidos_screen.dart';
import 'package:serviexpress_app/utils/widgets_compartidos.dart'; // FIX #10: widgets compartidos sin duplicados
import 'package:serviexpress_app/utils/sonido_manager.dart'; // SONIDOS: motor de audio in-app
import 'package:serviexpress_app/utils/panico_widgets.dart'; // Botón de pánico
import 'package:serviexpress_app/utils/campo_tarifa_inteligente.dart'; // Motor de tarifas
import 'package:serviexpress_app/services/ota_updater.dart'; // OTA updates
import 'package:serviexpress_app/screens/fn_panel_screen.dart'; // Panel FN Farmanorte
import 'package:serviexpress_app/utils/auth_helper.dart'; // hashContrasena
import 'package:serviexpress_app/screens/historial_servicios_screen.dart'; // Historial de servicios
part 'central_panel_precios.dart';
part 'central_corte_financiero.dart';
part 'central_gestion_usuarios.dart';

part 'central_screen_perfil.dart';
part 'central_screen_panico.dart';
part 'central_screen_formularios.dart';
part 'central_screen_monitor.dart';
part 'central_screen_panel_control.dart';
part 'central_screen_gestion.dart';
part 'central_screen_fn.dart';
part 'central_screen_reportes.dart';

class CentralScreen extends StatefulWidget {
  final Map<String, dynamic>? usuario;
  const CentralScreen({super.key, this.usuario});

  @override
  State<CentralScreen> createState() => _CentralScreenState();
}

class _CentralScreenState extends State<CentralScreen>
    with WidgetsBindingObserver {
  // ── URL WEB (Netlify) para el link que se comparte por WhatsApp ──────────
  // Actualiza este valor con tu URL de Netlify cuando la tengas.
  static const String _kUrlApp = 'https://databasesvm.github.io/serviexpressweb/form/';

  Timer? _reloj;
  final SonidoManager _sonidos = SonidoManager(); // Motor de audio in-app
  RealtimeChannel? _canalRadarCentral;
  RealtimeChannel? _canalChatCentral;
  RealtimeChannel? _canalPanico;
  RealtimeChannel? _canalUbicacionesMoviles; // Canal dedicado: refresca mapa al cambiar lat/lng
  RealtimeChannel? _canalActivaciones;
  RealtimeChannel? _canalFn; // Solicitudes FN desde sedes

  // Mapa userId → androidNotificationId para poder eliminar del tray
  // la notificación de "por activar" cuando el usuario es activado.
  final Map<String, int> _activacionNotifIds = {};
  // Listener de OneSignal guardado para poder removerlo en dispose().
  void Function(OSNotificationWillDisplayEvent)? _listenerActivacion;

  // Timers de expiración automática para alertas de pánico (2 min)
  Timer? _timerExpiracionGlobal;
  Timer? _timerExpiracionIndividual;

  // Estado de convocatoria global activa — controla botón "Detener"
  bool _convocatoriaGlobalActiva = false;

  // Sección desconectados — colapsable
  bool _desconectadosExpandidos = false;

  final Set<int> _demorasAlertadas =
      {}; // IDs ya alertados por demora (no repetir)

  int _panelActivoMobile = 1;
  bool _radarActivo = false;

  // REPORTES DE SERVICIO — badge de no leídos
  int _reportesSinLeer = 0;

  // MENÚ DE FILTRO DEL MONITOR — qué secciones se muestran. Vacío =
  // todas visibles (comportamiento de siempre). Las claves coinciden
  // con las usadas en _construirBloqueServicios.
  final Set<String> _seccionesOcultasMonitor = {};
  // Secciones colapsadas en el panel de flota (Control Operativo).
  // Claves: 'fn', 'expuente', 'memos', 'nocturno', 'servicio', 'libre'
  final Set<String> _seccionesOcultasFlota = {};
  // Categorías colapsadas en el monitor de servicios (tap en el header).
  final Set<String> _categoriasColapsadas = {};
  // Notifier para que el monitor se actualice solo cuando cambia el filtro,
  // sin reconstruir todo el Scaffold.
  final ValueNotifier<int> _filtroVersion = ValueNotifier(0);

  // Card seleccionado en el monitor (muestra botones de acción)
  final ValueNotifier<int?> _seleccionadoId = ValueNotifier(null);

  // Multi-pedido: modo de selección múltiple para asignar ruta a un móvil
  bool _modoMulti = false;
  Set<int> _multiSeleccion = {};

  // Búsqueda en tiempo real dentro del monitor
  final TextEditingController _busquedaCtrl = TextEditingController();
  String _busquedaTexto = '';

  // Timestamp de última actualización del stream de servicios
  DateTime _ultimaActualizacion = DateTime.now();

  /// Contadores de mensajes no leídos por sala (sala_id → cantidad).
  /// Se incrementa cuando llega un mensaje ajeno en el canal Realtime.
  /// Se resetea al abrir el chat de esa sala.
  final Map<String, int> _noLeidos = {};

  // ARQUITECTURA ANTI-PARPADEO — mismo patrón que movil_screen.dart.
  // El StreamBuilder consume estos controllers, que NUNCA cambian de
  // identidad durante toda la vida de la pantalla. Por debajo,
  // _construirStreams() puede reconectar el canal real de Supabase
  // cuantas veces haga falta — el StreamBuilder nunca se entera, nunca
  // resetea su snapshot, nunca muestra el loading spinner. El dato
  // anterior se queda visible hasta que llega el dato nuevo.
  final StreamController<List<Map<String, dynamic>>> _ctrlUsuariosMoviles =
      StreamController<List<Map<String, dynamic>>>.broadcast();
  final StreamController<List<Map<String, dynamic>>> _ctrlServiciosMonitor =
      StreamController<List<Map<String, dynamic>>>.broadcast();
  Stream<List<Map<String, dynamic>>> get _streamUsuariosMoviles =>
      _ctrlUsuariosMoviles.stream;
  Stream<List<Map<String, dynamic>>> get _streamServiciosMonitor =>
      _ctrlServiciosMonitor.stream;
  StreamSubscription<List<Map<String, dynamic>>>? _subUsuariosMoviles;
  StreamSubscription<List<Map<String, dynamic>>>? _subServiciosMonitor;
  Timer? _reconexionTimer;
  Timer? _debounceUbicaciones; // Limita el REST fetch de ubicaciones a 1 por segundo

  // Caché de motos — se actualiza en el listener de _subUsuariosMoviles
  // para que _construirBloqueServicios pueda resolver movil_id → #numero real.
  List<Map<String, dynamic>> _movilesCache = [];

  // Usuarios pendientes de activación (activo=false)
  int _usuariosPendientes = 0;

  @override
  void initState() {
    super.initState();

    // --- INYECCIÓN TÁCTICA 1: IDENTIDAD Y PERMISOS PUSH (SOLO MÓVIL) ---
    // OneSignal no tiene soporte web — guard kIsWeb obligatorio.
    if (!kIsWeb) {
      Future.microtask(() async {
        if (widget.usuario != null) {
          OneSignal.login(widget.usuario!['id'].toString());
        } else {
          // Respaldo táctico: Si no llega desde el login, buscamos el ID de la Central en la base de datos
          final centralBackup = await Supabase.instance.client
              .from('usuarios')
              .select('id')
              .eq('rol', 'central')
              .limit(1)
              .maybeSingle();
          if (centralBackup != null) {
            OneSignal.login(centralBackup['id'].toString());
          }
        }
        // Tag para que dispararACentral pueda encontrar este dispositivo
        // sin depender de segmentos configurados en el dashboard de OneSignal.
        OneSignal.User.addTagWithKey('rol', 'central');
        await OneSignal.Notifications.requestPermission(true);

        // Listener para capturar el androidNotificationId de las notif de
        // activación mientras la app está en primer plano, y poder eliminarlas
        // del tray cuando el usuario sea activado.
        _listenerActivacion = (OSNotificationWillDisplayEvent event) {
          final extra = event.notification.additionalData;
          if (extra != null && extra['tipo'] == 'activacion_pendiente') {
            final uid = extra['usuario_id']?.toString();
            final nid = event.notification.androidNotificationId;
            if (uid != null && nid != null) {
              _activacionNotifIds[uid] = nid;
            }
          }
          event.notification.display();
        };
        OneSignal.Notifications.addForegroundWillDisplayListener(
            _listenerActivacion!);
      });
    }

    WidgetsBinding.instance.addObserver(this);

    // VIGILANTE DE CONEXIÓN — mismo problema detectado en la prueba
    // piloto con los móviles: una conexión websocket de larga duración
    // (Central suele quedarse abierta turnos enteros, a veces en
    // tablet) puede morir en silencio. _construirStreams() reenvía
    // hacia los controllers estables de arriba — sin parpadeo — y
    // _iniciarVigilanteDeConexion() la reconstruye cada 30s + al volver
    // de segundo plano, para que nunca haga falta cerrar la app.
    _preCargarDatosIniciales(); // Carga REST inmediata — paradero visible sin esperar WebSocket
    _construirStreams();
    _iniciarVigilanteDeConexion();
    _construirCanalFn(); // Canal Realtime para solicitudes FN desde sedes
    Future.delayed(const Duration(milliseconds: 700), _cargarReportesSinLeer);

    // OTA: cubre sesión persistente (solo Android/iOS, no web)
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!kIsWeb && mounted) await OtaUpdater.verificar(context);
    });

    // --- RADAR CENTRAL: CANAL POSTGRES PARA SONIDOS Y ALERTAS ---
    // Detecta eventos de la tabla servicios en tiempo real.
    // Cada tipo de evento dispara el sonido correcto.
    _canalRadarCentral = Supabase.instance.client
        .channel('radar_central_bg')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'servicios',
          callback: (payload) {
            if (payload.newRecord.isEmpty) return;
            final String estadoNuevo =
                payload.newRecord['estado']?.toString().toLowerCase() ?? '';
            final String estadoAnterior =
                payload.oldRecord['estado']?.toString().toLowerCase() ?? '';

            // INSERT: servicio nuevo
            if (payload.eventType == PostgresChangeEvent.insert) {
              if (estadoNuevo == 'cotizacion') {
                _sonidos.reproducir(Sonidos.centralCotizacion);
              } else if (estadoNuevo == 'pendiente' ||
                  estadoNuevo == 'programado') {
                _sonidos.reproducir(Sonidos.centralRadar);
              }
            }
            // UPDATE: cambio de estado
            else if (payload.eventType == PostgresChangeEvent.update &&
                estadoNuevo != estadoAnterior) {
              switch (estadoNuevo) {
                case 'pendiente':
                  _sonidos.reproducir(Sonidos.centralRadar);
                  break;
                case 'cotizacion':
                  _sonidos.reproducir(Sonidos.centralCotizacion);
                  break;
                case 'cancelado':
                  _sonidos.reproducirSuave(Sonidos.centralCancelado);
                  break;
                case 'caducado':
                  _sonidos.reproducir(Sonidos.centralCaducado);
                  break;
                case 'finalizado_con_problema':
                case 'finalizado_por_demora':
                  _sonidos.reproducir(Sonidos.centralProblema);
                  break;
              }
            }
          },
        )
        .subscribe();

    // --- CANAL UBICACIONES: refresca el mapa al instante cuando un móvil
    // actualiza su lat/lng. El .stream() de usuarios puede tener lag de
    // varios segundos; este canal Postgres dispara un REST fetch inmediato
    // en cuanto detecta cualquier UPDATE en la tabla usuarios (en_linea,
    // latitud, longitud, etc.) — así el mapa siempre muestra posiciones frescas.
    _canalUbicacionesMoviles?.unsubscribe();
    _canalUbicacionesMoviles = Supabase.instance.client
        .channel('central_ubicaciones_moviles')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'usuarios',
          callback: (_) {
            // Debounce: si hay 10 motos actualizando lat/lng al mismo tiempo,
            // agrupa los eventos y hace UN solo fetch 800ms después del último.
            _debounceUbicaciones?.cancel();
            _debounceUbicaciones = Timer(const Duration(milliseconds: 800), () {
              if (!mounted) return;
              Supabase.instance.client
                  .from('usuarios')
                  .select()
                  .eq('rol', 'movil')
                  .then((data) {
                    _movilesCache = List.from(data);
                    if (!_ctrlUsuariosMoviles.isClosed) {
                      _ctrlUsuariosMoviles.add(_movilesCache);
                    }
                  })
                  .catchError((_) {});
            });
          },
        )
        .subscribe();

    // --- CANAL CHAT: SUENA CUANDO LLEGA UN MENSAJE A CUALQUIER SALA ---
    _canalChatCentral = Supabase.instance.client
        .channel('chat_central_bg')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'mensajes',
          callback: (payload) {
            final doc = payload.newRecord;
            if (doc.isEmpty) return;
            // Solo contar y sonar si el mensaje NO lo envió la Central misma
            final emisorId = doc['emisor_id']?.toString();
            final miId = widget.usuario?['id']?.toString();
            if (emisorId != null && emisorId != miId) {
              _sonidos.reproducirSuave(Sonidos.centralChat);
              // Incrementar contador de no leídos para esa sala
              final salaId = doc['sala_id']?.toString();
              if (salaId != null && mounted) {
                setState(() {
                  _noLeidos[salaId] = (_noLeidos[salaId] ?? 0) + 1;
                });
              }
            }
          },
        )
        .subscribe();

    // --- CANAL PÁNICO: escucha eventos de emergencia en tiempo real ---
    _canalPanico = Supabase.instance.client
        .channel('panico_global')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'eventos_panico',
          callback: (payload) {
            final doc = payload.newRecord;
            if (doc.isEmpty || !mounted) return;
            final tipo = doc['tipo']?.toString() ?? 'global';
            final destinoId = doc['destino_id'];
            final disparadorId = doc['disparado_por_id'];
            final miId = widget.usuario?['id'];

            // SILENCIO PARA EL DISPARADOR: por seguridad, quien activa el
            // pánico no recibe su propia alerta (overlay ni sonido).
            if (disparadorId != null &&
                disparadorId.toString() == miId?.toString()) {
              return;
            }

            // Para alertas individuales: solo mostramos si somos el destino
            if (tipo == 'individual' &&
                destinoId?.toString() != miId?.toString()) {
              return;
            }

            // Ubicación en vivo: solo si rolDisparador == 'movil' y la
            // ventana de 24h sigue vigente
            bool tieneUbicacion = false;
            if ((doc['rol_disparador']?.toString() ?? '') == 'movil' &&
                doc['ultima_lat'] != null &&
                doc['ubicacion_expira_at'] != null) {
              final expira = DateTime.tryParse(
                doc['ubicacion_expira_at'].toString(),
              )?.toUtc();
              tieneUbicacion =
                  expira != null && DateTime.now().toUtc().isBefore(expira);
            }

            _mostrarPanicoOverlay(
              disparadoPor: doc['disparado_por_nombre'] ?? 'Sistema',
              usuarioDisparador: doc['disparado_por_usuario']?.toString(),
              rolDisparador: doc['rol_disparador'] ?? '',
              eventoId: doc['id'] as int?,
              tieneUbicacion: tieneUbicacion,
            );
          },
        )
        .subscribe();
    // --- CANAL USUARIOS PENDIENTES: detecta nuevos registros por activar ---
    Supabase.instance.client
        .channel('usuarios_pendientes_central')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'usuarios',
          callback: (payload) async {
            final doc = payload.newRecord;
            if (doc.isEmpty || doc['activo'] == true) return;
            final pendientes = await Supabase.instance.client
                .from('usuarios')
                .select('id')
                .eq('activo', false)
                .not('rol', 'in', '("cliente")');
            final rol = doc['rol']?.toString() ?? '';
            final userId = doc['id']?.toString() ?? '';
            // Identificador visible: MOVIL##, nunca el nombre real
            final usuarioField = doc['usuario']?.toString() ?? '';
            final numStr = usuarioField.replaceAll(RegExp(r'[^0-9]'), '');
            final identificador = numStr.isNotEmpty
                ? 'MOVIL$numStr'
                : (rol == 'local' ? 'LOCAL' : 'MOVIL');

            // ── Push a todos los centrales (incluye segundo plano) ────────
            try {
              final centrales = await Supabase.instance.client
                  .from('usuarios')
                  .select('id')
                  .eq('rol', 'central');
              final ids = (centrales as List)
                  .map((u) => u['id'].toString())
                  .toList();
              if (ids.isNotEmpty) {
                await MotorNotificaciones.dispararRafa(
                  idsDestinos: ids,
                  titulo: '👤 Nuevo registro por activar',
                  mensaje: '$identificador — ve a Gestión → Activaciones',
                  urgente: false,
                  collapseId: 'activacion_$userId',
                  data: {'tipo': 'activacion_pendiente', 'usuario_id': userId},
                );
              }
            } catch (_) {}

            if (mounted) {
              setState(() => _usuariosPendientes = (pendientes as List).length);
              _sonidos.reproducir(Sonidos.centralRadar);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('👤 $identificador por activar'),
                backgroundColor: Colors.orange[800],
                duration: const Duration(seconds: 6),
                action: SnackBarAction(
                  label: 'GESTIÓN',
                  textColor: Colors.white,
                  onPressed: () => _abrirPanelGestion(context),
                ),
              ));
            }
          },
        )
        .subscribe();

    // --- CANAL ACTIVACIONES: detecta cuando un usuario pasa a activo=true ---
    // Decrementa el contador Y elimina la notificación del tray (si se tiene
    // el androidNotificationId guardado por el foreground listener).
    _canalActivaciones = Supabase.instance.client
        .channel('activaciones_completadas_central')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'usuarios',
          callback: (payload) {
            final oldDoc = payload.oldRecord;
            final newDoc = payload.newRecord;
            // Solo nos interesa la transición false → true
            if (oldDoc['activo'] != false || newDoc['activo'] != true) return;
            final userId = newDoc['id']?.toString();
            if (userId != null && !kIsWeb) {
              final nid = _activacionNotifIds.remove(userId);
              if (nid != null) {
                OneSignal.Notifications.removeNotification(nid);
              }
            }
            if (mounted) {
              setState(() =>
                  _usuariosPendientes = (_usuariosPendientes - 1).clamp(0, 9999));
            }
          },
        )
        .subscribe();

    // Cargar conteo inicial de pendientes
    Future.microtask(() async {
      try {
        final pendientes = await Supabase.instance.client
            .from('usuarios')
            .select('id')
            .eq('activo', false)
            .not('rol', 'in', '("cliente")');
        if (mounted) setState(() => _usuariosPendientes = (pendientes as List).length);
      } catch (_) {}
    });

    // pg_cron en Supabase es ahora el responsable principal de caducar
    // servicios. Este timer es solo un respaldo por si el servidor falla
    // o pg_cron no está configurado (plan Free de Supabase).
    _reloj = Timer.periodic(const Duration(minutes: 5), (timer) {
      // Sin setState — limpieza y detección no necesitan reconstruir el árbol
      _ejecutarLimpiezaDeCaducados();
      _detectarDemorasYSonar(); // Suena si hay servicios activos con +30 min
    });
  }

  // =========================================================================
  // VIGILANTE DE CONEXIÓN — mismo patrón que movil_screen.dart
  // =========================================================================

  /// Carga inmediata vía REST para que el paradero aparezca sin esperar
  /// que el WebSocket emita su primer evento (puede tardar 1–3s).
  // ── REPORTES DE SERVICIO ────────────────────────────────────────────────────

  Future<void> _cargarReportesSinLeer() async {
    try {
      final rows = await Supabase.instance.client
          .from('reportes_servicio')
          .select('id')
          .eq('leido', false);
      if (mounted) setState(() => _reportesSinLeer = (rows as List).length);
    } catch (_) {}
  }

  Future<void> _abrirPanelReportes(BuildContext context) async {
    // Marcar todos como leídos
    await Supabase.instance.client
        .from('reportes_servicio')
        .update({'leido': true})
        .eq('leido', false);
    if (mounted) setState(() => _reportesSinLeer = 0);

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _PanelReportesBottomSheet(),
    );
  }

  Future<void> _preCargarDatosIniciales() async {
    try {
      final moviles = await Supabase.instance.client
          .from('usuarios')
          .select()
          .eq('rol', 'movil');
      if (!_ctrlUsuariosMoviles.isClosed) {
        _ctrlUsuariosMoviles.add(List<Map<String, dynamic>>.from(moviles));
      }
      final servicios = await Supabase.instance.client
          .from('servicios')
          .select()
          .eq('archivado', false)
          .order('id', ascending: false);
      if (!_ctrlServiciosMonitor.isClosed) {
        _ctrlServiciosMonitor.add(List<Map<String, dynamic>>.from(servicios));
      }
    } catch (_) {
      // Si falla, el stream WebSocket llegará en breve de todas formas
    }
  }

  void _construirStreams() {
    _subUsuariosMoviles?.cancel();
    _subServiciosMonitor?.cancel();

    final crudoUsuarios = Supabase.instance.client
        .from('usuarios')
        .stream(primaryKey: ['id'])
        .eq('rol', 'movil');

    final crudoServicios = Supabase.instance.client
        .from('servicios')
        .stream(primaryKey: ['id'])
        .eq('archivado', false)
        .order('id', ascending: false);

    _subUsuariosMoviles = crudoUsuarios.listen(
      (data) {
        _movilesCache = List.from(data); // Cache para resolver movil_id → #numero
        if (!_ctrlUsuariosMoviles.isClosed) _ctrlUsuariosMoviles.add(data);
      },
      onError: (e) {
        if (!_ctrlUsuariosMoviles.isClosed) _ctrlUsuariosMoviles.addError(e);
      },
    );
    _subServiciosMonitor = crudoServicios.listen(
      (data) {
        _ultimaActualizacion = DateTime.now();
        if (!_ctrlServiciosMonitor.isClosed) _ctrlServiciosMonitor.add(data);
      },
      onError: (e) {
        if (!_ctrlServiciosMonitor.isClosed) {
          _ctrlServiciosMonitor.addError(e);
        }
      },
    );
  }

  // Reconstruye los streams cada 30s. No usa setState() — la
  // reconexión es invisible para el árbol de widgets.
  void _iniciarVigilanteDeConexion() {
    _reconexionTimer?.cancel();
    _reconexionTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      _construirStreams();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Momento de mayor riesgo: Central en tablet, minimizada un rato
    // (cambio de turno, revisar otra app) y al volver el canal puede
    // estar muerto. Reconstruimos de inmediato, sin esperar los 30s.
    if (state == AppLifecycleState.resumed && mounted) {
      _construirStreams();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Apagamos el canal satelital al salir para evitar fugas de memoria
    _canalRadarCentral?.unsubscribe();
    _canalChatCentral?.unsubscribe();
    _canalPanico?.unsubscribe();
    _canalUbicacionesMoviles?.unsubscribe();
    _debounceUbicaciones?.cancel();
    _canalActivaciones?.unsubscribe();
    _canalFn?.unsubscribe();
    if (_listenerActivacion != null && !kIsWeb) {
      OneSignal.Notifications.removeForegroundWillDisplayListener(
          _listenerActivacion!);
    }
    _reloj?.cancel();
    _reconexionTimer?.cancel();
    _timerExpiracionGlobal?.cancel();
    _timerExpiracionIndividual?.cancel();
    _subUsuariosMoviles?.cancel();
    _subServiciosMonitor?.cancel();
    _ctrlUsuariosMoviles.close();
    _ctrlServiciosMonitor.close();
    _busquedaCtrl.dispose();
    _filtroVersion.dispose();
    _seleccionadoId.dispose();
    _sonidos.silenciar();
    super.dispose();
  }

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
    await prefs.remove('sesion_usuario_json');
    await prefs.setBool('auto_login', false);

    // 2. Cierre forzoso en Supabase
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {}

    // 3. Redirección absoluta
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
    }
  }

  // ---> TRADUCTOR DE MONEDA PARA EL MONITOR <---
  String _formatearMonedaCentral(dynamic monto) {
    if (monto == null || monto == 0 || monto == 0.0) return 'SIN TARIFA';
    String texto = (monto as num).toInt().toString();
    String resultado = '';
    int contador = 0;
    for (int i = texto.length - 1; i >= 0; i--) {
      resultado = texto[i] + resultado;
      contador++;
      if (contador == 3 && i > 0) {
        resultado = '.$resultado';
        contador = 0;
      }
    }
    return '\$$resultado';
  }

  // ---> NUEVO MOTOR DE FORMATO VISUAL (CENTRAL) <---
  String _formatearNombreCentral(Map<String, dynamic>? data) {
    if (data == null || data.isEmpty) return 'Desconocido';
    final rol = data['rol']?.toString() ?? 'movil';
    if (rol == 'movil') {
      final usr = data['usuario']?.toString() ?? '';
      final numStr = usr.replaceAll(RegExp(r'[^0-9]'), '');
      if (numStr.isNotEmpty) return 'Móvil $numStr';
    }
    return data['nombre']?.toString().toUpperCase() ?? 'DESCONOCIDO';
  }

  // -------------------------------------------------
  // REDISEÑO: antes recibía solo el string de 'nombre' y le sacaba
  // dígitos con regex — si el nombre real de la persona no tenía
  // números (la mayoría no los tiene), el resultado era solo una
  // inicial en vez del número del móvil. Encontrado en el mapa en
  // vivo de Central, que no pasaba por _formatearNombreCentral antes
  // de llegar aquí.
  //
  // Ahora recibe el MAPA completo y prioriza la fuente más confiable:
  // el campo 'usuario' (ej: "movil12") siempre tiene el número real
  // de login, sin importar cómo se llame la persona. Funciona sin
  // importar qué pantalla o qué stream lo esté alimentando.
  String _extraerNumeroAvatar(dynamic origen) {
    // Compatibilidad: si alguna llamada vieja todavía pasa un String
    // suelto en vez del mapa, lo tratamos como 'nombre'.
    final Map<String, dynamic> data = origen is Map<String, dynamic>
        ? origen
        : {'nombre': origen?.toString() ?? ''};

    // Prioridad 1: el campo 'usuario' — la fuente más confiable,
    // siempre tiene el número real (movil12 → 12).
    final usr = data['usuario']?.toString() ?? '';
    final numUsr = RegExp(r'\d+').firstMatch(usr)?.group(0);
    if (numUsr != null) return numUsr;

    // Prioridad 2: si 'nombre' ya viene formateado como "Móvil 12"
    // (vía _formatearNombreCentral), también sirve.
    final nombre = data['nombre']?.toString() ?? '';
    final numNombre = RegExp(r'\d+').firstMatch(nombre)?.group(0);
    if (numNombre != null) return numNombre;

    // Último recurso: inicial del nombre — solo si de verdad no hay
    // ningún número disponible en ningún lado.
    if (nombre.trim().isNotEmpty) {
      return nombre.trim().substring(0, 1).toUpperCase();
    }
    return '?';
  }

  /// Estado textual de un movil FN para mostrar en el grupo FARMANORTE.
  /// Prioridad: suspendido > desconectado > en servicio > paradero > libre.
  String _estadoMovilFn(Map<String, dynamic> m, Set<dynamic> enServicioIds) {
    final rango = m['rango_movil'] ?? 'NOVATO';
    final sufijo = rango;
    if (m['suspendido'] == true) return '⛔ SUSPENDIDO · $sufijo';
    if (m['en_linea'] != true) return '🔴 DESCONECTADO · $sufijo';
    if (enServicioIds.contains(m['id'])) return '🚴 EN SERVICIO · $sufijo';
    final paradero = m['paradero_actual'];
    if (paradero != null) return '📍 FILA $paradero · $sufijo';
    return '🟢 LIBRE · $sufijo';
  }

  Color _colorEstadoMovilFn(Map<String, dynamic> m, Set<dynamic> enServicioIds) {
    if (m['suspendido'] == true) return Colors.red[700]!;
    if (m['en_linea'] != true) return Colors.grey[500]!;
    if (enServicioIds.contains(m['id'])) return Colors.orange[800]!;
    if (m['paradero_actual'] != null) return Colors.blue[700]!;
    return Colors.green[700]!;
  }

  // Formatea la calificación 1-5 para mostrar en UI
  String _formatCalificacion(dynamic val) {
    if (val == null) return 'Sin calificar';
    final double v = (val as num).toDouble();
    return '★ ${v.toStringAsFixed(1)}';
  }

  @override
  Widget build(BuildContext context) {
    final esPantallaGrande = MediaQuery.of(context).size.width > 850;

    return Scaffold(
      backgroundColor: Colors.grey[300],
      appBar: AppBar(
        title: Text(
          esPantallaGrande
              ? 'ServiExpress | Comando Central'
              : 'Comando Central',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        backgroundColor: Colors.black,
        elevation: 0,
        actions: esPantallaGrande
            ? [
                // Botón Reportes
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.flag_outlined, color: Colors.orange),
                      tooltip: 'Reportes de clientes y sedes',
                      onPressed: () => _abrirPanelReportes(context),
                    ),
                    if (_reportesSinLeer > 0)
                      Positioned(
                        top: 6, right: 6,
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                          child: Text('$_reportesSinLeer', style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
                        ),
                      ),
                  ],
                ),
                // Botón FN Farmanorte
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo[900],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 0),
                  ),
                  onPressed: () => _abrirFormularioFN(context),
                  child: const Text(
                    'FN',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        letterSpacing: 2),
                  ),
                ),
                const SizedBox(width: 6),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xff3AF500),
                    foregroundColor: Colors.black,
                  ),
                  onPressed: () => _abrirFormularioDespacho(context),
                  icon: const Icon(Icons.add_box),
                  label: const Text(
                    'NUEVO SERVICIO',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton(
                  icon: const Icon(Icons.share_rounded, color: Color(0xff25D366)),
                  tooltip: 'Enviar link de pedido al cliente',
                  onPressed: () => _enviarLinkInvitado(context),
                ),
                const SizedBox(width: 6),
                BotonPanicoTrigger(
                  segundos: 2,
                  icono: Icons.campaign_rounded,
                  colorAcento: Colors.orange,
                  titulo: 'CONVOCATORIA GENERAL',
                  descripcion:
                      'Se notificará a TODO el personal en línea (móviles y central) que necesitas su atención urgente.',
                  onActivado: _dispararPanico,
                  onDetener: () => _detenerAlerta(tipo: 'global'),
                ),
                const SizedBox(width: 6),
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey[850],
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () => _abrirPanelGestion(context),
                      icon: const Icon(Icons.admin_panel_settings_rounded, size: 18),
                      label: const Text(
                        'GESTIÓN',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    if (_usuariosPendientes > 0)
                      Positioned(
                        top: -4,
                        right: -4,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Colors.orange,
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            '$_usuariosPendientes',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 6),
                IconButton(
                  icon: const Icon(
                    Icons.power_settings_new,
                    color: Colors.redAccent,
                  ),
                  onPressed: _cerrarSesionSegura,
                ),
                const SizedBox(width: 8),
              ]
            : [
                // Botón FN compacto
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: InkWell(
                    onTap: () => _abrirFormularioFN(context),
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.indigo[900],
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'FN',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            letterSpacing: 1.5),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add_box, color: Color(0xff3AF500)),
                  onPressed: () => _abrirFormularioDespacho(context),
                ),
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.flag_outlined, color: Colors.orange),
                      onPressed: () => _abrirPanelReportes(context),
                    ),
                    if (_reportesSinLeer > 0)
                      Positioned(
                        top: 6, right: 6,
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                          child: Text('$_reportesSinLeer', style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
                        ),
                      ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.share_rounded, color: Color(0xff25D366)),
                  tooltip: 'Enviar link al cliente',
                  onPressed: () => _enviarLinkInvitado(context),
                ),
                BotonPanicoTrigger(
                  esCompacto: true,
                  segundos: 2,
                  icono: Icons.campaign_rounded,
                  colorAcento: Colors.orange,
                  titulo: 'CONVOCATORIA GENERAL',
                  descripcion:
                      'Se notificará a TODO el personal en línea (móviles y central) que necesitas su atención urgente.',
                  onActivado: _dispararPanico,
                  onDetener: () => _detenerAlerta(tipo: 'global'),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.power_settings_new,
                    color: Colors.redAccent,
                  ),
                  onPressed: _cerrarSesionSegura,
                ),
              ],
      ),

      // ---> BOTÓN FLOTANTE DE SOPORTE <---
      floatingActionButton: StreamBuilder<List<Map<String, dynamic>>>(
        stream: Supabase.instance.client
            .from('usuarios')
            .stream(primaryKey: ['id']).eq('alarma_soporte', true),
        builder: (context, snap) {
          final lista = snap.data ?? [];
          if (lista.isEmpty) return const SizedBox.shrink();
          return PulsingPanicoButton(
            color: Colors.red,
            child: FloatingActionButton(
              backgroundColor: Colors.red,
              onPressed: () => _abrirBuzonSoporte(context, lista),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  const Icon(Icons.support_agent, color: Colors.white),
                  Positioned(
                    right: -6,
                    top: -6,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${lista.length}',
                        style: const TextStyle(
                          color: Colors.red,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),

      body: esPantallaGrande
          ? Row(
              children: [
                SizedBox(width: 340, child: _construirPanelControl()),
                Expanded(child: _construirPanelMapa()),
                SizedBox(width: 340, child: _construirPanelMonitor()),
              ],
            )
          : IndexedStack(
              index: _panelActivoMobile,
              children: [
                RepaintBoundary(child: _construirPanelControl()),
                RepaintBoundary(child: _construirPanelMapa()),
                RepaintBoundary(child: _construirPanelMonitor()),
              ],
            ),

      bottomNavigationBar: esPantallaGrande
          ? null
          : BottomNavigationBar(
              backgroundColor: Colors.black,
              selectedItemColor: const Color(0xff3AF500),
              unselectedItemColor: Colors.white54,
              type: BottomNavigationBarType.fixed,
              currentIndex: _panelActivoMobile,
              onTap: (index) {
                if (index == 3) {
                  _abrirPanelGestion(context);
                } else {
                  setState(() => _panelActivoMobile = index);
                }
              },
              items: const [
                BottomNavigationBarItem(
                  icon: Icon(Icons.people_alt),
                  label: 'Flota',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.radar),
                  label: 'Radar',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.monitor),
                  label: 'Servicios',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.admin_panel_settings_rounded),
                  label: 'Gestión',
                ),
              ],
            ),
    );
  }
}

// ============================================================
// PANEL DE PRECIOS POR LOCAL — sectores + tarifas
// ============================================================