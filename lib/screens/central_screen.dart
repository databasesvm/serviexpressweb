import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'dart:async';
import 'package:url_launcher/url_launcher.dart';
import 'package:serviexpress_app/screens/reporte_financiero_screen.dart';
import 'package:serviexpress_app/utils/onesignal_api.dart';
import 'package:serviexpress_app/utils/textos_push.dart'; // Textos únicos de push SE
import 'package:serviexpress_app/utils/hora_servidor.dart'; // Reloj alineado con el servidor
import 'package:serviexpress_app/utils/cascada_config.dart'; // Tiempos de la cascada SE
import 'package:serviexpress_app/screens/chat_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:serviexpress_app/screens/ranking_screen.dart'; // FIX #7: fuente única de verdad para el ranking
import 'package:serviexpress_app/screens/monitor_pedidos_screen.dart';
import 'package:serviexpress_app/utils/widgets_compartidos.dart'; // FIX #10: widgets compartidos sin duplicados
import 'package:serviexpress_app/utils/sonido_manager.dart'; // SONIDOS: motor de audio in-app
import 'package:serviexpress_app/utils/campo_tarifa_inteligente.dart'; // Motor de tarifas
import 'package:serviexpress_app/services/ota_updater.dart'; // OTA updates
import 'package:serviexpress_app/screens/fn_panel_screen.dart'; // Panel FN Farmanorte
import 'package:serviexpress_app/screens/fn_facturacion_screen.dart'; // Facturación FN
import 'package:serviexpress_app/screens/fn_red_direcciones_screen.dart'; // Red de direcciones FN
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
part 'central_billetera.dart';

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
  RealtimeChannel? _canalUbicacionesMoviles; // Canal dedicado: refresca mapa al cambiar lat/lng
  RealtimeChannel? _canalFn; // Solicitudes FN desde sedes

  // Mapa userId → androidNotificationId para poder eliminar del tray
  // la notificación de "por activar" cuando el usuario es activado.
  final Map<String, int> _activacionNotifIds = {};
  // Listener de OneSignal guardado para poder removerlo en dispose().
  void Function(OSNotificationWillDisplayEvent)? _listenerActivacion;

  // Sección desconectados — colapsable
  bool _desconectadosExpandidos = false;
  // Secciones nuevas — colapsables
  bool _bloqueadosExpandidos  = false;
  bool _descansoExpandido     = false;

  // Toggle bloqueo automático por inactividad (config_sistema)
  bool _bloqueoInactividadActivo = false;

  // Offset para mostrar el consecutivo de servicios desde 1 tras un reset
  int _serviciosConsecutivoOffset = 0;

  // ── CONFIG-CASCADA: tiempos de cascada configurables desde la UI ─────────
  // SE offsets desde T=0
  int _cascadaSeF2Seg = 30; // auto-asigna #1 paradero (edge fn)
  int _cascadaSeF3Seg = 60; // push radio 1km (misil OneSignal)
  int _cascadaSeF4Seg = 90; // push todos disponibles (misil OneSignal)
  // FN offsets desde T=0
  int _cascadaFnF2Seg          = 30; // ofrece al más cercano (edge fn)
  int _cascadaFnF2TimeoutSeg   = 30; // tiempo para aceptar antes de liberar (edge fn)
  int _cascadaFnF3Seg          = 60; // push no-Masters 2km (misil OneSignal)
  int _cascadaFnF4Seg          = 90; // push global (misil OneSignal)

  final Set<int> _demorasAlertadas =
      {}; // IDs ya alertados por demora (no repetir)

  int _panelActivoMobile = 1;
  bool _radarActivo = false;

  // Toggles del monitor — muestran finalizados/cancelados al presionar el chip
  bool _mostrarFinalizados = false;
  bool _mostrarCancelados  = false;
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  // REPORTES DE SERVICIO — badge de no leídos
  int _reportesSinLeer = 0;

  // HORAS ACTIVAS HOY — mapa movil_id → minutos acumulados
  Map<int, int> _minutosHoyMoviles = {};

  // MENÚ DE FILTRO DEL MONITOR — qué secciones se muestran. Vacío =
  // todas visibles (comportamiento de siempre). Las claves coinciden
  // con las usadas en _construirBloqueServicios.
  final Set<String> _seccionesOcultasMonitor = {};
  // Secciones colapsadas en el panel de flota (Control Operativo).
  // Claves fijas: 'fn', 'servicio', 'libre', 'bloqueados', 'descanso', 'desconectados', 'suspendidos'
  // Claves dinámicas (PARADEROS-C): nombre.toLowerCase() de cada paradero activo en BD
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
  // FAB de soporte general: stream creado una sola vez (E5)
  late final Stream<List<Map<String, dynamic>>> _streamAlarmaSoporte =
      Supabase.instance.client
          .from('usuarios')
          .stream(primaryKey: ['id'])
          .eq('alarma_soporte', true)
          .asBroadcastStream();
  // Vigilante de conexión (E4)
  bool _streamCentralConError = false;
  DateTime _ultimaReconstruccionCentral = DateTime.now();

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
  Timer? _debounceUbicaciones;   // Agrupa avisos de ubicación en un solo refresco del mapa

  // Caché de motos — se actualiza en el listener de _subUsuariosMoviles
  // para que _construirBloqueServicios pueda resolver movil_id → #numero real.
  List<Map<String, dynamic>> _movilesCache = [];
  // Ids de usuarios por activar (activo=false, rol != cliente)
  final Set<String> _pendientesIds = {};
  // Cache 2 min del historial 24 h por móvil (panel → Desconectados)
  final Map<dynamic, (DateTime, Future<List<Map<String, dynamic>>>)>
      _cacheHist24h = {};
  // Cache del cliente (teléfono/nombre) para "Líneas directas"
  final Map<dynamic, Future<Map<String, dynamic>?>> _cacheContactoCliente = {};

  // Caché de servicios para FAB de chats pendientes
  List<Map<String, dynamic>> _cacheSvcMonitor = [];
  final ValueNotifier<int> _chatServicioTotal = ValueNotifier(0);

  // Usuarios pendientes de activación (activo=false)
  int _usuariosPendientes = 0;

  // Billetera: solicitudes pendientes de comprobación
  int _billeteraPendientes = 0;
  RealtimeChannel? _canalBilletera;

  // ── PARADEROS-C: lista dinámica desde BD (panel de control) ─────────────
  // Se carga una sola vez al iniciar. Los cambios en BD se reflejan
  // automáticamente al próximo initState (reinicio de sesión).
  List<Map<String, dynamic>> _paraderosPanel = [];
  List<Map<String, dynamic>> _sedesFN = [];
  List<Map<String, dynamic>> _puntosFN = [];
  List<Map<String, dynamic>> _localesUbicacion = [];

  // Filtros del mapa — solo móviles activos por defecto
  bool _mapaParaderos = false;
  bool _mapaSedesFN   = false;
  bool _mapaPuntosFN  = false;
  bool _mapaLocales   = false;
  bool _mapaMoviles   = true;

  @override
  void initState() {
    super.initState();
    // Monitor: las fases de la cascada se cuentan con la hora del servidor.
    HoraServidor.sincronizar(forzar: true);

    // --- INYECCIÓN TÁCTICA 1: IDENTIDAD Y PERMISOS PUSH (SOLO MÓVIL) ---
    // OneSignal no tiene soporte web — guard kIsWeb obligatorio.
    if (!kIsWeb) {
      Future.microtask(() async {
        // Se ESPERA el login antes de poner la etiqueta: si no, la etiqueta
        // podía quedar en la cuenta anterior del teléfono (p. ej. un móvil).
        bool puedeSerCentral = false;
        try {
          if (widget.usuario != null) {
            await OneSignal.login(widget.usuario!['id'].toString());
            final rol = widget.usuario!['rol']?.toString();
            puedeSerCentral = rol == 'central' ||
                rol == 'master' ||
                widget.usuario!['es_dual'] == true;
          } else {
            // Respaldo táctico: Si no llega desde el login, buscamos el ID de la Central en la base de datos
            final centralBackup = await Supabase.instance.client
                .from('usuarios')
                .select('id')
                .eq('rol', 'central')
                .limit(1)
                .maybeSingle();
            if (centralBackup != null) {
              await OneSignal.login(centralBackup['id'].toString());
              puedeSerCentral = true;
            }
          }
        } catch (_) {}
        // Tag para que dispararACentral pueda encontrar este dispositivo
        // sin depender de segmentos configurados en el dashboard de OneSignal.
        // Solo cuentas de Central, Master o móviles DUAL.
        if (puedeSerCentral) {
          OneSignal.User.addTagWithKey('rol', 'central');
        }
        await OneSignal.Notifications.requestPermission(true);

        // Listener para capturar el androidNotificationId de las notif de
        // activación mientras la app está en primer plano, y poder eliminarlas
        // del tray cuando el usuario sea activado.
        _listenerActivacion = (OSNotificationWillDisplayEvent event) {
          final extra = event.notification.additionalData;
          if (extra != null && extra['tipo'] == 'activacion_pendiente') {
            // En foreground: el canal Realtime ya dispara sonido + snackbar.
            // Suprimimos el display del OS para evitar doble sonido.
            // (La notif en bandeja es innecesaria si la app está abierta.)
            event.preventDefault();
          }
          // Las demás notificaciones las muestra OneSignal por defecto.
          // NO llamar display() explícitamente — el SDK ya lo hace,
          // y llamarlo dos veces genera doble sonido + doble banner.
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
    _construirStreams(); // Carga REST de móviles y servicios (los canales los mantienen en vivo)
    _iniciarVigilanteDeConexion();
    _construirCanalFn(); // Canal Realtime para solicitudes FN desde sedes
    Future.delayed(const Duration(milliseconds: 700), _cargarReportesSinLeer);
    Future.delayed(const Duration(milliseconds: 900), _cargarMinutosHoyMoviles);
    Future.delayed(const Duration(milliseconds: 1100), _cargarBloqueoInactividad);
    Future.delayed(const Duration(milliseconds: 1300), _cargarParaderosPanel);

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
              // Agregar al cache — los inserts nunca llegan con archivado=true
              // Verificar duplicado: el .stream() puede haber añadido el mismo
              // servicio antes que este canal → no prepend si ya existe.
              if (!_ctrlServiciosMonitor.isClosed) {
                final newId = payload.newRecord['id'];
                if (_cacheSvcMonitor.every((s) => s['id'] != newId)) {
                  _cacheSvcMonitor = [payload.newRecord, ..._cacheSvcMonitor];
                }
                _chatServicioTotal.value = _cacheSvcMonitor
                    .where((s) =>
                        s['chat_movil_central'] == true ||
                        s['chat_cliente_central'] == true)
                    .length;
                _ultimaActualizacion = DateTime.now();
                _ctrlServiciosMonitor.add(List.from(_cacheSvcMonitor));
              }
            }
            // UPDATE: cambio de estado o de cualquier campo
            else if (payload.eventType == PostgresChangeEvent.update) {
              // Sonidos solo cuando cambia el estado
              // estadoAnterior vacío = replica identity DEFAULT (oldRecord sin estado) → ignorar
              if (estadoAnterior.isNotEmpty && estadoNuevo != estadoAnterior) {
                switch (estadoNuevo) {
                  case 'pendiente':
                    _sonidos.reproducir(Sonidos.centralRadar);
                    break;
                  case 'cotizacion':
                  case 'fn_renegociando':
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

              // ACTUALIZACIÓN DEL CACHE EN TIEMPO REAL
              // Resuelve el problema de cards que no actualizaban sin refrescar
              // (por ejemplo cotizacion → cotizada). El canal Postgres recibe
              // TODO sin excepción. El flag archivado=true es la única razón
              // para sacar un servicio del cache (pg_cron lo pone a las 4h).
              if (!mounted || _ctrlServiciosMonitor.isClosed) return;
              final isArchivado = payload.newRecord['archivado'] == true;
              final updId = payload.newRecord['id'];
              final idx = _cacheSvcMonitor.indexWhere((s) => s['id'] == updId);
              if (isArchivado) {
                // pg_cron archivó este servicio — sacarlo del cache
                if (idx >= 0) {
                  final nuevo = List<Map<String, dynamic>>.from(_cacheSvcMonitor);
                  nuevo.removeAt(idx);
                  _cacheSvcMonitor = nuevo;
                }
              } else {
                // Actualizar o insertar en cache
                if (idx >= 0) {
                  final updated = Map<String, dynamic>.from(_cacheSvcMonitor[idx])
                    ..addAll(payload.newRecord);
                  final nuevo = List<Map<String, dynamic>>.from(_cacheSvcMonitor);
                  nuevo[idx] = updated;
                  _cacheSvcMonitor = nuevo;
                } else {
                  _cacheSvcMonitor = [payload.newRecord, ..._cacheSvcMonitor];
                }
              }
              _chatServicioTotal.value = _cacheSvcMonitor
                  .where((s) =>
                      s['chat_movil_central'] == true ||
                      s['chat_cliente_central'] == true)
                  .length;
              _ultimaActualizacion = DateTime.now();
              _ctrlServiciosMonitor.add(List.from(_cacheSvcMonitor));
            }
          },
        )
        .subscribe((status, _) {
          // Si el canal da error o se cierra, el vigilante recarga.
          if (status != RealtimeSubscribeStatus.subscribed) {
            _streamCentralConError = true;
          }
        });

    // --- CANAL MÓVILES (F): única fuente en vivo de la lista de móviles de
    // la central (mapa, panel, fila). Toma la fila completa que trae el
    // aviso y la aplica al instante, sin consultar la BD. Ignora clientes,
    // locales y sedes. Agrega móviles nuevos y quita los eliminados.
    _canalUbicacionesMoviles?.unsubscribe();
    _canalUbicacionesMoviles = Supabase.instance.client
        .channel('central_ubicaciones_moviles')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'usuarios',
          callback: (payload) {
            _procesarPendientes(payload); // "por activar" (antes 2 canales extra)
            final upd = payload.newRecord;
            if (payload.eventType == PostgresChangeEvent.delete || upd.isEmpty) {
              final idBorrado = payload.oldRecord['id'];
              if (idBorrado == null) return;
              final antes = _movilesCache.length;
              _movilesCache =
                  _movilesCache.where((m) => m['id'] != idBorrado).toList();
              if (_movilesCache.length == antes) return;
            } else {
              final esMovil = upd['rol'] == 'movil' || upd['es_dual'] == true;
              final idx =
                  _movilesCache.indexWhere((m) => m['id'] == upd['id']);
              if (!esMovil) {
                // Dejó de ser móvil/dual → sacarlo; si nunca lo fue, ignorar.
                if (idx < 0) return;
                _movilesCache = List<Map<String, dynamic>>.from(_movilesCache)
                  ..removeAt(idx);
              } else if (idx < 0) {
                _movilesCache = [..._movilesCache, Map<String, dynamic>.from(upd)];
              } else {
                _movilesCache[idx] = {..._movilesCache[idx], ...upd};
              }
            }
            // Agrupa avisos seguidos en un solo refresco del mapa.
            _debounceUbicaciones?.cancel();
            _debounceUbicaciones = Timer(const Duration(milliseconds: 300), () {
              if (!mounted) return;
              if (!_ctrlUsuariosMoviles.isClosed) {
                _ctrlUsuariosMoviles
                    .add(List<Map<String, dynamic>>.from(_movilesCache));
              }
            });
          },
        )
        .subscribe((status, _) {
          // Si el canal da error o se cierra, el vigilante recarga.
          if (status != RealtimeSubscribeStatus.subscribed) {
            _streamCentralConError = true;
          }
        });

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
            // Solo contar y sonar si el mensaje va DIRIGIDO a la Central
            // (salas soporte_*) y NO lo envió la Central. La Central escribe
            // con emisor_id = 0 (ChatScreen miId: 0); antes se oía a sí misma
            // y sonaba también con los chats móvil ↔ cliente/local (servicio_*).
            final emisorId = doc['emisor_id']?.toString();
            final miId = widget.usuario?['id']?.toString();
            final salaChat = doc['sala_id']?.toString() ?? '';
            // -1 = respuestas automáticas del asistente (bot): no suenan
            final esDeCentral = emisorId == null ||
                emisorId == '0' ||
                emisorId == '-1' ||
                emisorId == miId;
            final paraCentral = salaChat.startsWith('soporte_');
            if (!esDeCentral && paraCentral) {
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

    // --- USUARIOS POR ACTIVAR ---
    // Antes había 2 canales extra sobre `usuarios` (nuevos registros y
    // activaciones) que recibían TODOS los GPS de los móviles. Ahora lo
    // procesa el canal de móviles (_procesarPendientes). Aquí solo la carga
    // inicial de los ids pendientes (activo=false, rol != cliente).
    Future.microtask(() async {
      try {
        final pendientes = await Supabase.instance.client
            .from('usuarios')
            .select('id')
            .eq('activo', false)
            .not('rol', 'in', '("cliente")');
        _pendientesIds
          ..clear()
          ..addAll(pendientes.map((p) => p['id'].toString()));
        if (mounted) setState(() => _usuariosPendientes = _pendientesIds.length);
      } catch (_) {}
    });

    // ── CANAL BILLETERA: solicitudes de recarga pendientes ────────────────
    _canalBilletera = Supabase.instance.client
        .channel('billetera_solicitudes_central')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'solicitudes_recarga_wallet',
          callback: (_) async {
            try {
              final rows = await Supabase.instance.client
                  .from('solicitudes_recarga_wallet')
                  .select('id')
                  .eq('estado', 'pendiente');
              if (mounted) setState(() => _billeteraPendientes = rows.length);
            } catch (_) {}
          },
        )
        .subscribe();

    // Carga inicial del contador de billetera
    Future.microtask(() async {
      try {
        final rows = await Supabase.instance.client
            .from('solicitudes_recarga_wallet')
            .select('id')
            .eq('estado', 'pendiente');
        if (mounted) setState(() => _billeteraPendientes = rows.length);
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

  Future<void> _cargarMinutosHoyMoviles() async {
    try {
      final hoy = DateTime.now();
      final fechaHoy =
          '${hoy.year}-${hoy.month.toString().padLeft(2, '0')}-${hoy.day.toString().padLeft(2, '0')}';
      final rows = await Supabase.instance.client
          .from('sesiones_movil')
          .select('movil_id, duracion_minutos')
          .eq('fecha', fechaHoy)
          .not('duracion_minutos', 'is', null);
      final Map<int, int> mapa = {};
      for (final r in rows) {
        final mid = r['movil_id'] as int?;
        if (mid == null) continue;
        mapa[mid] = (mapa[mid] ?? 0) + ((r['duracion_minutos'] as num?)?.toInt() ?? 0);
      }
      if (mounted) setState(() => _minutosHoyMoviles = mapa);
    } catch (_) {}
  }

  Future<void> _cargarReportesSinLeer() async {
    try {
      final rows = await Supabase.instance.client
          .from('reportes_servicio')
          .select('id')
          .eq('leido', false);
      if (mounted) setState(() => _reportesSinLeer = rows.length);
    } catch (_) {}
  }

  Future<void> _cargarBloqueoInactividad() async {
    try {
      final row = await Supabase.instance.client
          .from('config_sistema')
          .select(
            'bloqueo_inactividad_activo, servicios_consecutivo_offset, '
            'cascada_se_f2_seg, cascada_se_f3_seg, cascada_se_f4_seg, '
            'cascada_fn_f2_seg, cascada_fn_f2_timeout_seg, '
            'cascada_fn_f3_seg, cascada_fn_f4_seg',
          )
          .eq('id', 1)
          .single();
      if (mounted) setState(() {
        _bloqueoInactividadActivo    = row['bloqueo_inactividad_activo'] as bool? ?? false;
        _serviciosConsecutivoOffset  = (row['servicios_consecutivo_offset'] as int?) ?? 0;
        _cascadaSeF2Seg              = (row['cascada_se_f2_seg']          as int?) ?? 30;
        _cascadaSeF3Seg              = (row['cascada_se_f3_seg']          as int?) ?? 60;
        _cascadaSeF4Seg              = (row['cascada_se_f4_seg']          as int?) ?? 90;
        _cascadaFnF2Seg              = (row['cascada_fn_f2_seg']          as int?) ?? 30;
        _cascadaFnF2TimeoutSeg       = (row['cascada_fn_f2_timeout_seg']  as int?) ?? 30;
        _cascadaFnF3Seg              = (row['cascada_fn_f3_seg']          as int?) ?? 60;
        _cascadaFnF4Seg              = (row['cascada_fn_f4_seg']          as int?) ?? 90;
      });
    } catch (_) {}
  }

  /// Número de orden visible = id - offset (arranca desde 1 tras cada reset)
  int _consec(int id) => (id - _serviciosConsecutivoOffset).clamp(1, 999999);

  Future<void> _toggleBloqueoInactividad(bool nuevoValor) async {
    setState(() => _bloqueoInactividadActivo = nuevoValor);
    try {
      await Supabase.instance.client
          .from('config_sistema')
          .update({'bloqueo_inactividad_activo': nuevoValor})
          .eq('id', 1);
    } catch (e) {
      // Revertir si falla
      if (mounted) setState(() => _bloqueoInactividadActivo = !nuevoValor);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al actualizar: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _abrirPanelReportes(BuildContext context) async {
    // Marcar todos como leídos
    await Supabase.instance.client
        .from('reportes_servicio')
        .update({'leido': true})
        .eq('leido', false);
    if (mounted) setState(() => _reportesSinLeer = 0);

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const _PanelReportesScreen()),
    );
  }

  // Carga REST de móviles y servicios (ver _construirStreams).
  Future<void> _preCargarDatosIniciales() async {
    await Future.wait([_recargarMovilesCentral(), _recargarServiciosMonitor()]);
  }

  // Historial de las últimas 24 h de un móvil (sección "Desconectados" del
  // panel). Una consulta por móvil cada 2 min, no en cada redibujo.
  Future<List<Map<String, dynamic>>> _historial24hMovil(dynamic movilId) {
    final previo = _cacheHist24h[movilId];
    if (previo != null &&
        DateTime.now().difference(previo.$1).inMinutes < 2) {
      return previo.$2;
    }
    final hace24h = DateTime.now()
        .toUtc()
        .subtract(const Duration(hours: 24))
        .toIso8601String();
    final fut = Supabase.instance.client
        .from('servicios')
        .select('id, origen, destino, estado, observacion, created_at')
        .eq('movil_id', movilId)
        .not('estado', 'eq', 'pendiente')
        .not('estado', 'eq', 'en_curso')
        .not('estado', 'eq', 'problema')
        .gte('created_at', hace24h)
        .then((d) => List<Map<String, dynamic>>.from(d));
    _cacheHist24h[movilId] = (DateTime.now(), fut);
    return fut;
  }

  // "Líneas directas" del menú del servicio: el móvil sale de _movilesCache
  // (ya cargado, sin consulta); si no estuviera, una consulta cacheada.
  Future<Map<String, dynamic>?> _contactoMovil(dynamic movilId) {
    final m = _movilesCache.firstWhere(
      (x) => x['id'].toString() == movilId.toString(),
      orElse: () => const <String, dynamic>{},
    );
    if (m.isNotEmpty) return Future.value(m);
    return _cacheContactoCliente['m_$movilId'] ??= Supabase.instance.client
        .from('usuarios')
        .select('telefono, nombre, usuario, rol')
        .eq('id', movilId)
        .maybeSingle();
  }

  Future<Map<String, dynamic>?> _contactoCliente(dynamic clienteId) {
    return _cacheContactoCliente['c_$clienteId'] ??= Supabase.instance.client
        .from('usuarios')
        .select('telefono, nombre')
        .eq('id', clienteId)
        .maybeSingle();
  }

  // ── USUARIOS POR ACTIVAR (antes 2 canales extra sobre `usuarios`) ────────
  // Mantiene el set de ids pendientes (activo=false, rol != cliente) con los
  // avisos que ya llegan al canal de móviles. Sin consultas extra a la BD.
  void _procesarPendientes(PostgresChangePayload payload) {
    final doc = payload.newRecord;
    final esBorrado =
        payload.eventType == PostgresChangeEvent.delete || doc.isEmpty;
    final id = (esBorrado ? payload.oldRecord['id'] : doc['id'])?.toString();
    if (id == null) return;
    final antes = _pendientesIds.length;

    if (esBorrado) {
      _pendientesIds.remove(id);
    } else if (doc['rol']?.toString() == 'cliente') {
      _pendientesIds.remove(id);
    } else if (doc['activo'] == true) {
      if (_pendientesIds.remove(id) && !kIsWeb) {
        // Activado: quitar su notificación "por activar" de la bandeja
        final nid = _activacionNotifIds.remove(id);
        if (nid != null) OneSignal.Notifications.removeNotification(nid);
      }
    } else {
      _pendientesIds.add(id);
      // Registro NUEVO por activar: sonido + aviso (el push ya lo envía
      // registro_screen al crear la cuenta).
      if (payload.eventType == PostgresChangeEvent.insert && mounted) {
        final rol = doc['rol']?.toString() ?? '';
        // Identificador visible: MOVIL##, nunca el nombre real
        final numStr = (doc['usuario']?.toString() ?? '')
            .replaceAll(RegExp(r'[^0-9]'), '');
        final identificador = numStr.isNotEmpty
            ? 'MOVIL$numStr'
            : (rol == 'local' ? 'LOCAL' : 'MOVIL');
        _sonidos.reproducir(Sonidos.centralRadar);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('👤 $identificador por activar'),
          backgroundColor: Colors.orange[800],
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: 'ACTIVAR',
            textColor: Colors.white,
            // Ir directo a la pestaña "Por Activar" (tab 1)
            onPressed: () => _abrirGestionUsuarios(context, tabInicial: 1),
          ),
        ));
      }
    }
    if (_pendientesIds.length != antes && mounted) {
      setState(() => _usuariosPendientes = _pendientesIds.length);
    }
  }

  // F: ya NO hay .stream() de usuarios ni de servicios (cada cambio llegaba
  // duplicado: stream + canal). Las listas se cargan por REST aquí y se
  // mantienen en vivo con los canales _canalRadarCentral (servicios) y
  // _canalUbicacionesMoviles (móviles). Se llama al abrir, al pulsar
  // "Actualizar radar", tras purgar y cuando el vigilante detecta caída.
  void _construirStreams() {
    _subUsuariosMoviles?.cancel();
    _subServiciosMonitor?.cancel();
    _streamCentralConError = false;
    _ultimaReconstruccionCentral = DateTime.now();
    _recargarMovilesCentral();
    _recargarServiciosMonitor();
  }

  // Móviles + cuentas duales (mapa, panel, resolver movil_id → #numero).
  Future<void> _recargarMovilesCentral() async {
    try {
      final data = await Supabase.instance.client
          .from('usuarios')
          .select()
          .or('rol.eq.movil,es_dual.eq.true');
      if (!mounted) return;
      _movilesCache = List<Map<String, dynamic>>.from(data);
      if (!_ctrlUsuariosMoviles.isClosed) {
        _ctrlUsuariosMoviles.add(List.from(_movilesCache));
      }
    } catch (e) {
      _streamCentralConError = true; // el vigilante reintenta
    }
  }

  // Servicios no archivados — incluye finalizados/cancelados recientes
  // (< 4h, aún no archivados por pg_cron). Máx. 500, como antes.
  Future<void> _recargarServiciosMonitor() async {
    try {
      final data = await Supabase.instance.client
          .from('servicios')
          .select()
          .eq('archivado', false)
          .order('id', ascending: false)
          .limit(500);
      if (!mounted) return;
      _ultimaActualizacion = DateTime.now();
      _cacheSvcMonitor = List<Map<String, dynamic>>.from(data);
      _chatServicioTotal.value = _cacheSvcMonitor.where((s) =>
          s['chat_movil_central'] == true ||
          s['chat_cliente_central'] == true).length;
      if (!_ctrlServiciosMonitor.isClosed) {
        _ctrlServiciosMonitor.add(List.from(_cacheSvcMonitor));
      }
    } catch (e) {
      _streamCentralConError = true; // el vigilante reintenta
    }
  }

  // Vigilante de conexión (cada 30 s). Antes reconstruía (y re-descargaba
  // 500 servicios) si no había cambios en 35 s, aunque la conexión estuviera
  // bien. Ahora solo si la conexión Realtime cayó, si un stream dio error,
  // o como red de seguridad tras 5 min sin datos y sin reconstruir.
  void _iniciarVigilanteDeConexion() {
    _reconexionTimer?.cancel();
    _reconexionTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      final ahora = DateTime.now();
      final socketCaido = !Supabase.instance.client.realtime.isConnected;
      final sinDatosLargo =
          ahora.difference(_ultimaActualizacion).inMinutes >= 5 &&
              ahora.difference(_ultimaReconstruccionCentral).inMinutes >= 5;
      if (socketCaido || _streamCentralConError || sinDatosLargo) {
        _construirStreams();
      }
    });
  }

  // =========================================================================
  // FAB CHAT — abre el chat del servicio pendiente más reciente
  // =========================================================================
  void _abrirChatServicioPendiente() {
    final svc = _cacheSvcMonitor.firstWhere(
      (s) => s['chat_movil_central'] == true || s['chat_cliente_central'] == true,
      orElse: () => {},
    );
    if (svc.isEmpty) return;
    final id = svc['id'] as int;

    if (svc['chat_movil_central'] == true) {
      Supabase.instance.client
          .from('servicios')
          .update({'chat_movil_central': false}).eq('id', id);
      final movil = _movilesCache.firstWhere(
        (m) => m['id'] == svc['movil_id'],
        orElse: () => {},
      );
      final nom = _formatearNombreCentral(movil.isEmpty ? null : movil);
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => ChatScreen(
          salaId: 'soporte_movil_$id',
          miId: 0,
          miNombre: 'Central',
          titulo: 'Chat con $nom',
          servicioId: id,
          alarmaLocal: 'chat_movil_central',
          alarmaDestino: 'chat_central_movil',
          destinatarioId: (svc['movil_id'] as num?)?.toInt(),
          tipoFaq: TipoFaqChat.central,
        ),
      ));
    } else {
      Supabase.instance.client
          .from('servicios')
          .update({'chat_cliente_central': false}).eq('id', id);
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => ChatScreen(
          salaId: 'soporte_cliente_$id',
          miId: 0,
          miNombre: 'Central',
          titulo: 'Chat con Cliente',
          servicioId: id,
          alarmaLocal: 'chat_cliente_central',
          alarmaDestino: 'chat_central_cliente',
          destinatarioId: (svc['cliente_id'] as num?)?.toInt(),
          tipoFaq: TipoFaqChat.central,
        ),
      ));
    }
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
    _canalUbicacionesMoviles?.unsubscribe();
    _debounceUbicaciones?.cancel();
    _canalFn?.unsubscribe();
    _canalBilletera?.unsubscribe();
    if (_listenerActivacion != null && !kIsWeb) {
      OneSignal.Notifications.removeForegroundWillDisplayListener(
          _listenerActivacion!);
    }
    _reloj?.cancel();
    _reconexionTimer?.cancel();
    _subUsuariosMoviles?.cancel();
    _subServiciosMonitor?.cancel();
    _ctrlUsuariosMoviles.close();
    _ctrlServiciosMonitor.close();
    _busquedaCtrl.dispose();
    _filtroVersion.dispose();
    _seleccionadoId.dispose();
    _chatServicioTotal.dispose();
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

    // 2. Desvincular OneSignal para que no lleguen push al dispositivo
    //    después de cerrar sesión. Sin esto, el dispositivo queda ligado
    //    al external user ID y sigue recibiendo notificaciones.
    if (!kIsWeb) OneSignal.logout();

    // 3. Cierre forzoso en Supabase
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {}

    // 4. Redirección absoluta
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
    if (enServicioIds.contains(m['id'])) return '🏍️ EN SERVICIO · $sufijo';
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
      key: _scaffoldKey,
      backgroundColor: Colors.grey[300],
      endDrawer: esPantallaGrande ? null : _buildMenuLateral(context),
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
                // Botón FN Farmanorte
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF002da2),
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
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.receipt_long, color: Color(0xFF002da2), size: 22),
                  tooltip: 'Facturación FN',
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const FnFacturacionScreen(titulo: 'Facturación FN — Central'),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.location_on, color: Color(0xFF002da2), size: 22),
                  tooltip: 'Red de direcciones FN',
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const FnRedDireccionesScreen(),
                    ),
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
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey[850],
                        foregroundColor: Colors.white,
                      ),
                      // Si hay pendientes de activación → ir directo a "Por Activar" (tab 1)
                      onPressed: () => _usuariosPendientes > 0
                          ? _abrirGestionUsuarios(context, tabInicial: 1)
                          : _abrirPanelGestion(context),
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
                // Acceso rápido: FN
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
                  child: InkWell(
                    onTap: () => _abrirFormularioFN(context),
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: Colors.indigo[900], borderRadius: BorderRadius.circular(6)),
                      child: const Text('FN', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 1.5)),
                    ),
                  ),
                ),
                // Acceso rápido: Nuevo servicio
                IconButton(
                  icon: const Icon(Icons.add_box_rounded, color: Color(0xff3AF500)),
                  tooltip: 'Nuevo servicio',
                  onPressed: () => _abrirFormularioDespacho(context),
                ),
                // Badge de gestión + menú lateral
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.menu_rounded, color: Colors.white),
                      tooltip: 'Menú',
                      onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
                    ),
                    if (_usuariosPendientes > 0)
                      Positioned(
                        top: 6, right: 6,
                        child: Container(
                          width: 8, height: 8,
                          decoration: const BoxDecoration(color: Colors.orange, shape: BoxShape.circle),
                        ),
                      ),
                  ],
                ),
              ],
      ),

      // ---> BOTONES FLOTANTES: chats de servicio + soporte general <---
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // FAB 1: chats de servicios pendientes (móvil o cliente → central)
          ValueListenableBuilder<int>(
            valueListenable: _chatServicioTotal,
            builder: (_, total, __) {
              if (total == 0) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: PulsingPanicoButton(
                  color: Colors.orange,
                  child: FloatingActionButton.extended(
                    heroTag: 'fab_chat_svc',
                    backgroundColor: Colors.orange[800],
                    onPressed: _abrirChatServicioPendiente,
                    icon: const Icon(Icons.chat_rounded, color: Colors.white, size: 20),
                    label: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        const Text('Servicio', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                        Positioned(
                          top: -10, right: -18,
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              color: Colors.yellow[600],
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.orange[900]!, width: 1),
                            ),
                            constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                            child: Text('$total', style: const TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          // FAB 2: soporte general (alarma_soporte)
          StreamBuilder<List<Map<String, dynamic>>>(
            // Creado UNA vez (antes se recreaba en cada redibujo de la
            // central → nueva conexión + consulta cada vez).
            stream: _streamAlarmaSoporte,
            builder: (context, snap) {
              final lista = snap.data ?? [];
              if (lista.isEmpty) return const SizedBox.shrink();
              return PulsingPanicoButton(
                color: Colors.red,
                child: FloatingActionButton(
                  heroTag: 'fab_soporte',
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
        ],
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

  // ── Menú lateral (endDrawer) — solo en vista móvil ───────────────────────
  Widget _buildMenuLateral(BuildContext context) {
    void cerrar() => Navigator.of(context).pop();

    Widget _item(IconData icon, String label, Color color, VoidCallback onTap) =>
        InkWell(
          onTap: () { cerrar(); onTap(); },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            child: Row(children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 14),
              Text(label, style: const TextStyle(color: Colors.white, fontSize: 14)),
            ]),
          ),
        );

    return Drawer(
      width: 270,
      backgroundColor: const Color(0xFF111111),
      child: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // ── Cabecera ──
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            color: Colors.black,
            child: Row(children: [
              const Icon(Icons.settings_suggest_rounded, color: Color(0xff3AF500), size: 20),
              const SizedBox(width: 10),
              const Expanded(child: Text('Comando Central',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15))),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white54, size: 20),
                padding: EdgeInsets.zero, constraints: const BoxConstraints(),
                onPressed: cerrar,
              ),
            ]),
          ),
          const Divider(color: Colors.white10, height: 1),

          Expanded(child: ListView(padding: EdgeInsets.zero, children: [
            // ── FN Farmanorte ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text('FN FARMANORTE', style: TextStyle(color: Color(0xFF002da2), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
            ),
            _item(Icons.local_pharmacy_rounded, 'Crear servicio FN', const Color(0xFF002da2), () => _abrirFormularioFN(context)),
            _item(Icons.receipt_long_rounded, 'Facturación FN', const Color(0xFF002da2), () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FnFacturacionScreen(titulo: 'Facturación FN — Central')))),
            _item(Icons.location_on_rounded, 'Red de direcciones FN', const Color(0xFF002DA2), () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FnRedDireccionesScreen()))),

            const Divider(color: Colors.white10, height: 20),

            // ── Operaciones ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Text('OPERACIONES', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
            ),
            _item(Icons.add_box_rounded, 'Nuevo servicio', const Color(0xff3AF500), () => _abrirFormularioDespacho(context)),
            _item(Icons.share_rounded, 'Enviar link al cliente', const Color(0xff25D366), () => _enviarLinkInvitado(context)),

            const Divider(color: Colors.white10, height: 20),

            // ── Gestión ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Text('GESTIÓN', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
            ),
            InkWell(
              onTap: () { cerrar(); _abrirPanelGestion(context); },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                child: Row(children: [
                  const Icon(Icons.admin_panel_settings_rounded, color: Colors.orangeAccent, size: 20),
                  const SizedBox(width: 14),
                  const Text('Gestión de usuarios', style: TextStyle(color: Colors.white, fontSize: 14)),
                  if (_usuariosPendientes > 0) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(color: Colors.orange, borderRadius: BorderRadius.circular(10)),
                      child: Text('$_usuariosPendientes', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ]),
              ),
            ),
            const Divider(color: Colors.white10, height: 20),

            // ── Sesión ──
            _item(Icons.power_settings_new_rounded, 'Cerrar sesión', Colors.redAccent, _cerrarSesionSegura),
          ])),
        ]),
      ),
    );
  }

  // ---> BUZÓN DE SOPORTE: lista de móviles que necesitan atención <---
  void _abrirBuzonSoporte(BuildContext context, List<Map<String, dynamic>> lista) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(children: [
              Icon(Icons.support_agent, color: Colors.redAccent, size: 20),
              SizedBox(width: 8),
              Text('Soporte — mensajes pendientes',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
            ]),
          ),
          const Divider(color: Colors.white12, height: 1),
          ...lista.map((movil) {
            final usr = movil['usuario']?.toString() ?? '';
            final num = usr.replaceAll(RegExp(r'[^0-9]'), '');
            final etiqueta = num.isNotEmpty ? 'Móvil $num' : (movil['nombre'] ?? 'Móvil');
            return ListTile(
              leading: const CircleAvatar(
                backgroundColor: Colors.redAccent,
                child: Icon(Icons.chat_bubble_outline, color: Colors.white, size: 18),
              ),
              title: Text(etiqueta, style: const TextStyle(color: Colors.white)),
              trailing: const Icon(Icons.chevron_right, color: Colors.white54),
              onTap: () {
                Navigator.pop(ctx);
                _abrirChatDirectoMovil(movil);
              },
            );
          }),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

// ============================================================
// PANEL DE PRECIOS POR LOCAL — sectores + tarifas
// ============================================================