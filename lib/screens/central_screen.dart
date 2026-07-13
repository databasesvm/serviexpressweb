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
part 'central_panel_precios.dart';
part 'central_corte_financiero.dart';
part 'central_gestion_usuarios.dart';

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

  // MENÚ DE FILTRO DEL MONITOR — qué secciones se muestran. Vacío =
  // todas visibles (comportamiento de siempre). Las claves coinciden
  // con las usadas en _construirBloqueServicios.
  final Set<String> _seccionesOcultasMonitor = {};
  // Notifier para que el monitor se actualice solo cuando cambia el filtro,
  // sin reconstruir todo el Scaffold.
  final ValueNotifier<int> _filtroVersion = ValueNotifier(0);

  // Card seleccionado en el monitor (muestra botones de acción)
  final ValueNotifier<int?> _seleccionadoId = ValueNotifier(null);

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

  // Caché de motos — se actualiza en el listener de _subUsuariosMoviles
  // para que _construirBloqueServicios pueda resolver movil_id → #numero real.
  List<Map<String, dynamic>> _movilesCache = [];

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

  // Formatea la calificación 1-5 para mostrar en UI
  String _formatCalificacion(dynamic val) {
    if (val == null) return 'Sin calificar';
    final double v = (val as num).toDouble();
    return '★ ${v.toStringAsFixed(1)}';
  }

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

  void _abrirFormularioDespacho(BuildContext context) {
    final origenController = TextEditingController();
    final destinoController = TextEditingController();
    final tarifaController = TextEditingController();
    final telReceptorController = TextEditingController();
    final telEmisorController = TextEditingController();
    final detallesController = TextEditingController();

    String tipoServicio = 'PAQUETERÍA';
    bool procesando = false;
    // Coordenadas del Local elegido por autocompletado — null si
    // todavía no se seleccionó nada de la lista (texto libre).
    double? origenLatCapturada;
    double? origenLngCapturada;

    // Desglose del precio capturado por CampoTarifaInteligente.
    Map<String, dynamic>? detalleActual;

    // Red de direcciones — se carga una vez al abrir el formulario
    List<String> redDireccionesCentral = [];
    List<String> sugerenciasDestino = [];
    Supabase.instance.client
        .from('red_direcciones')
        .select('nombre, municipio')
        .eq('activo', true)
        .order('nombre', ascending: true)
        .then((data) {
      redDireccionesCentral = List<Map<String, dynamic>>.from(data)
          .map((e) => '${e['nombre']} (${e['municipio']})')
          .toList();
    });

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          // FIX: el insetPadding por defecto de AlertDialog (40px a
          // cada lado) se come buena parte del ancho en un celular
          // angosto — por eso se sentía apretado y el texto se
          // cortaba. Lo reducimos y forzamos el contenido a usar
          // todo el ancho disponible en vez de encogerse solo.
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 24,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          title: const Text(
            'NUEVO SERVICIO MANUAL',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'TIPO DE SERVICIO',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.black54,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: ['PAQUETERÍA', 'COMIDA', 'COMPRAS', 'MOTOTAXI'].map(
                    (tipo) {
                      final bool seleccionado = tipoServicio == tipo;
                      return ChoiceChip(
                        label: Text(
                          tipo,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: seleccionado ? Colors.white : Colors.black87,
                          ),
                        ),
                        selected: seleccionado,
                        selectedColor: Colors.black,
                        backgroundColor: Colors.grey[200],
                        onSelected: (val) {
                          if (val) {
                            setDialogState(() {
                              tipoServicio = tipo;
                              if (tipo != 'PAQUETERÍA') {
                                telEmisorController.clear();
                              }
                            });
                          }
                        },
                      );
                    },
                  ).toList(),
                ),
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 16),

                Autocomplete<Map<String, dynamic>>(
                  displayStringForOption: (local) =>
                      (local['nombre'] ?? '').toString(),
                  optionsBuilder: (TextEditingValue valorTexto) async {
                    final texto = valorTexto.text.trim();
                    if (texto.length < 2) {
                      return const Iterable<Map<String, dynamic>>.empty();
                    }
                    try {
                      final resultados = await Supabase.instance.client
                          .from('usuarios')
                          .select('id, nombre, lat_fija, lng_fija')
                          .eq('rol', 'local')
                          .ilike('nombre', '%$texto%')
                          .limit(5);
                      return (resultados as List)
                          .cast<Map<String, dynamic>>();
                    } catch (_) {
                      return const Iterable<Map<String, dynamic>>.empty();
                    }
                  },
                  onSelected: (local) {
                    origenController.text = (local['nombre'] ?? '').toString();
                    setDialogState(() {
                      origenLatCapturada = local['lat_fija'] != null
                          ? (local['lat_fija'] as num).toDouble()
                          : null;
                      origenLngCapturada = local['lng_fija'] != null
                          ? (local['lng_fija'] as num).toDouble()
                          : null;
                    });
                  },
                  fieldViewBuilder:
                      (context, fieldController, focusNode, onFieldSubmitted) {
                    // Mantiene sincronizado el controller externo
                    // (origenController, usado por el resto del
                    // formulario) con el campo de autocompletado.
                    return TextField(
                      controller: fieldController,
                      focusNode: focusNode,
                      textInputAction: TextInputAction.next,
                      onChanged: (val) => origenController.text = val,
                      onSubmitted: (_) => onFieldSubmitted(),
                      decoration: InputDecoration(
                        labelText: tipoServicio == 'COMIDA'
                            ? 'Restaurante (*)'
                            : tipoServicio == 'COMPRAS'
                            ? 'Lugar de compra (*)'
                            : 'Punto de Recogida (*)',
                        helperText: origenLatCapturada != null
                            ? '📍 Ubicación guardada de este local'
                            : 'Escribe 2+ letras para ver locales registrados',
                        helperStyle: TextStyle(
                          fontSize: 10,
                          color: origenLatCapturada != null
                              ? Colors.green[700]
                              : Colors.grey[500],
                        ),
                        border: const OutlineInputBorder(),
                        isDense: true,
                        prefixIcon: Icon(
                          tipoServicio == 'COMIDA'
                              ? Icons.restaurant
                              : tipoServicio == 'COMPRAS'
                              ? Icons.shopping_cart
                              : Icons.storefront,
                          size: 18,
                        ),
                      ),
                    );
                  },
                  optionsViewBuilder: (context, onSelected, options) {
                    return Align(
                      alignment: Alignment.topLeft,
                      child: Material(
                        elevation: 4,
                        borderRadius: BorderRadius.circular(8),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 200),
                          child: ListView.builder(
                            padding: EdgeInsets.zero,
                            shrinkWrap: true,
                            itemCount: options.length,
                            itemBuilder: (context, index) {
                              final local = options.elementAt(index);
                              final bool tieneUbicacion =
                                  local['lat_fija'] != null;
                              return ListTile(
                                dense: true,
                                leading: Icon(
                                  Icons.storefront,
                                  size: 18,
                                  color: tieneUbicacion
                                      ? Colors.green[700]
                                      : Colors.grey[400],
                                ),
                                title: Text(
                                  (local['nombre'] ?? '').toString(),
                                  style: const TextStyle(fontSize: 13),
                                ),
                                trailing: tieneUbicacion
                                    ? const Icon(
                                        Icons.check_circle,
                                        size: 14,
                                        color: Colors.green,
                                      )
                                    : null,
                                onTap: () => onSelected(local),
                              );
                            },
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),

                if (tipoServicio == 'PAQUETERÍA') ...[
                  TextField(
                    controller: telEmisorController,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Teléfono de quien envía (Opcional)',
                      border: OutlineInputBorder(),
                      isDense: true,
                      prefixIcon: Icon(Icons.phone, size: 18),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                TextField(
                  controller: destinoController,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: tipoServicio == 'MOTOTAXI'
                        ? 'Punto de Destino (*)'
                        : 'Dirección de Entrega (*)',
                    border: const OutlineInputBorder(),
                    isDense: true,
                    prefixIcon: const Icon(Icons.flag, size: 18),
                  ),
                  onChanged: (texto) {
                    if (texto.length < 2) {
                      setDialogState(() => sugerenciasDestino = []);
                      return;
                    }
                    final t = texto.toLowerCase();
                    setDialogState(() {
                      sugerenciasDestino = redDireccionesCentral
                          .where((d) => d.toLowerCase().contains(t))
                          .take(5)
                          .toList();
                    });
                  },
                ),

                // Sugerencias de la red de direcciones
                if (sugerenciasDestino.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6, bottom: 4),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: sugerenciasDestino.map((zona) => InkWell(
                        onTap: () {
                          destinoController.text = '$zona - ';
                          setDialogState(() => sugerenciasDestino = []);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 7),
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.grey[400]!),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.location_city,
                                  color: Colors.grey[600], size: 14),
                              const SizedBox(width: 4),
                              Text(zona,
                                  style: TextStyle(
                                    color: Colors.grey[800],
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  )),
                            ],
                          ),
                        ),
                      )).toList(),
                    ),
                  ),

                const SizedBox(height: 12),

                TextField(
                  controller: telReceptorController,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: tipoServicio == 'MOTOTAXI'
                        ? 'Teléfono del Pasajero'
                        : tipoServicio == 'PAQUETERÍA'
                        ? 'Teléfono de quien recibe'
                        : 'Teléfono de Contacto',
                    border: const OutlineInputBorder(),
                    isDense: true,
                    prefixIcon: const Icon(Icons.phone_android, size: 18),
                  ),
                ),
                const SizedBox(height: 12),

                TextField(
                  controller: detallesController,
                  maxLines:
                      (tipoServicio == 'COMIDA' || tipoServicio == 'COMPRAS')
                      ? 3
                      : 2,
                  decoration: InputDecoration(
                    labelText: tipoServicio == 'COMIDA'
                        ? '¿Qué vas a pedir?'
                        : tipoServicio == 'COMPRAS'
                        ? 'Lista de productos'
                        : 'Detalles / Notas (Opcional)',
                    border: const OutlineInputBorder(),
                    isDense: true,
                    prefixIcon: const Icon(Icons.notes, size: 18),
                  ),
                ),
                const SizedBox(height: 12),

                // MOTOR DE TARIFAS — sugiere precio basado en historial,
                // incluye panel de recargos (lluvia/nocturno/sobrecarga).
                CampoTarifaInteligente(
                  origenController: origenController,
                  destinoController: destinoController,
                  tarifaController: tarifaController,
                  tipoServicio: tipoServicio,
                  onDetalleChanged: (d) => detalleActual = d,
                ),
              ],
            ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: procesando ? null : () => Navigator.pop(context),
              child: const Text(
                'CANCELAR',
                style: TextStyle(color: Colors.red),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.black),
              onPressed: procesando
                  ? null
                  : () async {
                      if (origenController.text.trim().isEmpty ||
                          destinoController.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Origen y Destino son obligatorios.'),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }

                      // La cotización (precio vacío) existe para que Local
                      // o Cliente le pidan un precio a Central. No tiene
                      // sentido que Central se pida una cotización a sí
                      // misma — siempre debe poner el precio final.
                      final String tarifaSinFormato = tarifaController.text
                          .replaceAll('\$', '')
                          .replaceAll('.', '')
                          .replaceAll(',', '')
                          .trim();
                      final double tarifaValidada =
                          double.tryParse(tarifaSinFormato) ?? 0.0;
                      if (tarifaValidada <= 0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'La tarifa es obligatoria. Central no puede '
                              'dejarla vacía para cotización.',
                            ),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }

                      setDialogState(() => procesando = true);

                      String tarifaLimpia = tarifaController.text
                          .replaceAll('\$', '')
                          .replaceAll('.', '')
                          .replaceAll(',', '')
                          .trim();
                      double tarifaFinal = double.tryParse(tarifaLimpia) ?? 0.0;

                      String telReceptor = telReceptorController.text.trim();
                      String telEmisor = telEmisorController.text.trim();
                      String detalles = detallesController.text.trim();
                      String observacionFinal = '';

                      if (tipoServicio == 'PAQUETERÍA') {
                        observacionFinal = '[ PAQUETERÍA ]';
                        if (telEmisor.isNotEmpty) { observacionFinal += ' - 📞 Envía: $telEmisor'; }
                        if (telReceptor.isNotEmpty) { observacionFinal += ' | 📞 Recibe: $telReceptor'; }
                        if (detalles.isNotEmpty) { observacionFinal += '\n$detalles'; }
                      } else if (tipoServicio == 'COMIDA') {
                        observacionFinal = '[ COMIDA ] - 🍔 PEDIDO:\n$detalles';
                        if (telReceptor.isNotEmpty) { observacionFinal += '\n---\n📞 Tel: $telReceptor'; }
                      } else if (tipoServicio == 'COMPRAS') {
                        observacionFinal = '[ COMPRAS ] - 🛒 LISTA:\n$detalles';
                        if (telReceptor.isNotEmpty) { observacionFinal += '\n---\n📞 Tel: $telReceptor'; }
                      } else if (tipoServicio == 'MOTOTAXI') {
                        observacionFinal = '[ MOTOTAXI ]';
                        if (telReceptor.isNotEmpty) { observacionFinal += ' - 📱 Pasajero: $telReceptor'; }
                        if (detalles.isNotEmpty) { observacionFinal += '\n$detalles'; }
                      }

                      try {
                        // ---> UNIFICACIÓN: ESCÁNER MULTI-PARADERO DESDE CENTRAL <---
                        String? exclusivoIdCampo;
                        List<String> pilotosSeleccionadosIds = [];

                        // Regla de capacidad por rango (igual que dentro de
                        // la app): NOVATO/PRO no reciben nada si ya tienen
                        // un servicio activo; ELITE/LEYENDA/MASTER mientras
                        // les quede cupo. Se resuelve en SQL para no
                        // repetir esta lógica en cada ola por separado.
                        Set<String> idsElegiblesPorCapacidad = {};
                        try {
                          final elegibles = await Supabase.instance.client
                              .rpc(
                                'moviles_elegibles_notificacion',
                                params: {
                                  'p_solo_master': false,
                                  // T=0: el #1 de paradero debe estar
                                  // completamente libre — el cupo de 2/3
                                  // pedidos no aplica al turno inicial,
                                  // solo a partir de +2min/+5min.
                                  'p_solo_completamente_libres': true,
                                },
                              );
                          idsElegiblesPorCapacidad = (elegibles as List)
                              .map((e) => e['id'].toString())
                              .toSet();
                        } catch (_) {
                          // Si la función no existe todavía (falta correr
                          // el SQL), no bloqueamos el despacho — solo no
                          // filtramos por capacidad esta vez.
                        }

                        if (tarifaFinal > 0) {
                          final serviciosPendientes = await Supabase
                              .instance
                              .client
                              .from('servicios')
                              .select('exclusivo_id')
                              .eq('estado', 'pendiente')
                              .not('exclusivo_id', 'is', null);

                          List<String> ocupados = [];
                          for (var s in serviciosPendientes) {
                            ocupados.addAll(
                              s['exclusivo_id']
                                  .toString()
                                  .split(',')
                                  .map((e) => e.trim()),
                            );
                          }

                          final movilesLibres = await Supabase.instance.client
                              .from('usuarios')
                              .select('id, paradero_actual, ingreso_fila')
                              .eq('rol', 'movil')
                              .eq('en_linea', true)
                              .not('paradero_actual', 'is', null);

                          Map<String, List<Map<String, dynamic>>>
                          gruposParaderos = {};
                          for (var m in movilesLibres) {
                            String pName = m['paradero_actual']
                                .toString()
                                .trim()
                                .toLowerCase();
                            gruposParaderos.putIfAbsent(pName, () => []).add(m);
                          }

                          // Extraemos el #1 de cada paradero disponible que
                          // no esté ocupado NI bloqueado por capacidad de
                          // su rango — si el #1 es Novato/Pro y está
                          // ocupado, pasamos al siguiente de la fila.
                          gruposParaderos.forEach((pName, listaFila) {
                            listaFila.sort(
                              (a, b) =>
                                  DateTime.parse(
                                    a['ingreso_fila'] ??
                                        DateTime.now().toIso8601String(),
                                  ).compareTo(
                                    DateTime.parse(
                                      b['ingreso_fila'] ??
                                          DateTime.now().toIso8601String(),
                                    ),
                                  ),
                            );

                            for (var candidato in listaFila) {
                              String candId = candidato['id'].toString();
                              final bool elegible =
                                  idsElegiblesPorCapacidad.isEmpty ||
                                  idsElegiblesPorCapacidad.contains(candId);
                              if (!ocupados.contains(candId) && elegible) {
                                pilotosSeleccionadosIds.add(candId);
                                break;
                              }
                            }
                          });

                          if (pilotosSeleccionadosIds.isNotEmpty) {
                            exclusivoIdCampo = pilotosSeleccionadosIds.join(
                              ',',
                            );
                          }
                        }

                        // FALLBACK DE UBICACIÓN — si el autocompletado no
                        // encontró un local con base sellada, usamos las
                        // coordenadas del paradero MEMOS como punto de
                        // partida. Sin esto, un servicio sin ubicación
                        // reconocida nunca podría medir el radio de 1km
                        // en la ola zonal de +2min.
                        if (origenLatCapturada == null ||
                            origenLngCapturada == null) {
                          origenLatCapturada = 7.863976;
                          origenLngCapturada = -72.479256;
                        }

                        // INSERCIÓN EN BD CON MULTI-ID DE PARADERO
                        final insertedSvc = await Supabase.instance.client
                            .from('servicios')
                            .insert({
                              'origen': origenController.text
                                  .trim()
                                  .toUpperCase(),
                              'destino': destinoController.text
                                  .trim()
                                  .toUpperCase(),
                              'telefono_receptor': telReceptor.isEmpty
                                  ? null
                                  : telReceptor,
                              'tarifa': tarifaFinal,
                              'tarifa_detalle': detalleActual ??
                                  {'total': tarifaFinal, 'fuente': 'central'},
                              'observacion': observacionFinal,
                              'estado': tarifaFinal > 0
                                  ? 'pendiente'
                                  : 'cotizacion',
                              'creador': 'Central',
                              // FIX: el tipo seleccionado en los chips
                              // (PAQUETERÍA/COMIDA/COMPRAS/MOTOTAXI) se
                              // capturaba pero nunca se guardaba — el
                              // servicio quedaba con el valor por
                              // defecto 'Normal' sin importar qué se
                              // eligiera. Por eso la tarjeta del moto
                              // nunca pudo hablar distinto para un
                              // mototaxi vs. una entrega.
                              'tipo_servicio': tipoServicio,
                              'metodo_pago': 'Efectivo',
                              'archivado': false,
                              'exclusivo_id': exclusivoIdCampo,
                              if (origenLatCapturada != null)
                                'origen_lat': origenLatCapturada,
                              if (origenLngCapturada != null)
                                'origen_lng': origenLngCapturada,
                            }).select('id').single();
                        final int nuevoServicioId =
                            (insertedSvc['id'] as num).toInt();

                        // DISPARO DE NOTIFICACIONES — 3 olas, espejando
                        // exactamente las fases del embudo táctico dentro
                        // de la app:
                        //
                        //   T=0    → Masters en línea (mensaje propio) +
                        //            #1 de cada paradero (mensaje propio)
                        //   +2min  → ZONAL: si nadie lo tomó, se abre a
                        //            quien esté a máx. 1km del origen.
                        //            NOTA: Central todavía no captura
                        //            coordenadas del origen al despachar
                        //            manualmente — sin eso, esta ola no
                        //            puede filtrar por distancia todavía
                        //            y se comporta como la global. Para
                        //            que el radio de 1km funcione de
                        //            verdad aquí, hace falta agregar un
                        //            selector de ubicación al formulario
                        //            de despacho (igual al de los
                        //            formularios de invitado).
                        //   +5min  → GLOBAL: todos los conectados.
                        //
                        // Las 3 olas respetan la regla de capacidad por
                        // rango (NOVATO/PRO bloqueados si están ocupados;
                        // ELITE/LEYENDA/MASTER según su cupo libre) vía
                        // moviles_elegibles_notificacion() en SQL.
                        if (tarifaFinal > 0) {
                          // --- T=0: MASTERS (mensaje propio) ---
                          var idsMasters = <String>[];
                          try {
                            final mastersResp = await Supabase.instance.client
                                .rpc(
                                  'moviles_elegibles_notificacion',
                                  params: {
                                    'p_solo_master': true,
                                    // Mismo turno único — un Master con
                                    // un servicio activo no debe ver
                                    // ofertas nuevas a T=0, solo cuando
                                    // el servicio se libera más adelante.
                                    'p_solo_completamente_libres': true,
                                  },
                                );
                            idsMasters = (mastersResp as List)
                                .map((m) => m['id'].toString())
                                .toList();
                            if (idsMasters.isNotEmpty) {
                              await MotorNotificaciones.dispararRafa(
                                idsDestinos: idsMasters,
                                titulo: '⚡ TURNO DE MASTER',
                                mensaje: 'Nuevo servicio disponible en el radar',
                                urgente: true,
                                sonido: Sonidos.movilParadero,
                              );
                            }
                          } catch (_) {
                            // Si la función SQL no existe todavía, no
                            // bloqueamos el despacho — solo se omite
                            // esta ola hasta que se corra el script.
                          }

                          // --- T=+30s: #1 DE CADA PARADERO (mensaje propio) ---
                          // Se retrasa 30s para que coincida con el contador
                          // de cuenta regresiva que muestra movil_screen al
                          // #1 de la fila antes de abrir el servicio.
                          // Capturamos los valores antes del delay — los
                          // controllers del diálogo pueden disponerse antes.
                          // T=+30s: misil programado al #1 de cada paradero.
                          // Misil retardado (no Future.delayed) — sobrevive si
                          // Central navega fuera de pantalla, y su ID se guarda
                          // para cancelarlo si alguien acepta antes de los 30s.
                          if (pilotosSeleccionadosIds.isNotEmpty) {
                            final idsSnap =
                                List<String>.from(pilotosSeleccionadosIds);
                            final id30s = await MotorNotificaciones
                                .programarMisilRetardado(
                              externalIds: idsSnap,
                              titulo: '📍 TU TURNO EN EL PARADERO',
                              mensaje: 'Un servicio está esperando por ti',
                              segundosRetardo: 30,
                              sonido: Sonidos.movilParadero,
                            );
                            if (id30s != null) {
                              await Supabase.instance.client
                                  .from('servicios')
                                  .update({'onesignal_30s': id30s})
                                  .eq('id', nuevoServicioId);
                            }
                          }

                          // --- T=+60s ZONAL y T=+90s GLOBAL ---
                          // Capturo el servicioId antes del delay para
                          // que no dependa del estado del diálogo.
                          {
                            final int svcId = nuevoServicioId;
                            final String msg =
                                'Nuevo servicio disponible en el radar';
                            final List<String> masterSnap =
                                List<String>.from(idsMasters);
                            final List<String> paraderoSnap =
                                List<String>.from(pilotosSeleccionadosIds);

                            // T=+60s y T=+90s — misiles server-side (pre-fetch al despacho)
                            final double? oLat = origenLatCapturada;
                            final double? oLng = origenLngCapturada;
                            final movilesC = await Supabase.instance.client
                                .from('usuarios').select('id, latitud, longitud')
                                .eq('rol', 'movil').eq('en_linea', true)
                                .neq('suspendido', true)
                                .not('rango_movil', 'in', '("MASTER")');
                            final idsZonaC = movilesC.where((u) {
                              final id = u['id'].toString();
                              if (masterSnap.contains(id) || paraderoSnap.contains(id)) return false;
                              if (oLat == null || oLng == null) return true;
                              final uLat = (u['latitud'] as num?)?.toDouble();
                              final uLng = (u['longitud'] as num?)?.toDouble();
                              if (uLat == null || uLng == null) return false;
                              return const Distance().as(
                                    LengthUnit.Meter,
                                    LatLng(uLat, uLng),
                                    LatLng(oLat, oLng),
                                  ) <= 1000;
                            }).map((u) => u['id'].toString()).toList();
                            final idsTodosC = movilesC
                                .map((u) => u['id'].toString())
                                .where((id) => !masterSnap.contains(id))
                                .toList();
                            String? id60sC;
                            String? id90sC;
                            if (idsZonaC.isNotEmpty) {
                              id60sC = await MotorNotificaciones.programarMisilRetardado(
                                externalIds: idsZonaC,
                                titulo: '📡 SERVICIO CERCA (1km)',
                                mensaje: msg,
                                segundosRetardo: 60,
                                sonido: Sonidos.movilParadero,
                              );
                            }
                            if (idsTodosC.isNotEmpty) {
                              id90sC = await MotorNotificaciones.programarMisilRetardado(
                                externalIds: idsTodosC,
                                titulo: '🚨 SERVICIO SIN TOMAR',
                                mensaje: msg,
                                segundosRetardo: 90,
                                sonido: Sonidos.movilParadero,
                              );
                            }
                            if (id60sC != null || id90sC != null) {
                              await Supabase.instance.client.from('servicios').update({
                                if (id60sC != null) 'onesignal_2m': id60sC,
                                if (id90sC != null) 'onesignal_5m': id90sC,
                              }).eq('id', svcId);
                            }
                          }
                        }

                        if (context.mounted) {
                          // ---> CIERRE Y OFERTA DE GUARDAR EN LA RED DE DIRECCIONES <---
                          // Capturamos antes del pop porque los controllers se
                          // pueden disponer en cuanto el diálogo se destruye.
                          final String destinoCapturado =
                              destinoController.text.trim();
                          Navigator.pop(context);

                          final String destinoMayus =
                              destinoCapturado.toUpperCase();
                          // Extraemos el barrio base (la parte antes del " - "
                          // si el destino viene de un chip de sugerencia, que
                          // rellena con "ZONA - "; si es texto libre, usamos
                          // el texto completo).
                          final String barrioExtraido =
                              destinoMayus.contains(' - ')
                              ? destinoMayus.split(' - ')[0].trim()
                              : destinoMayus;

                          // Revisamos si ya existe en la red cargada al abrir
                          // el formulario — comparación nombre vs. nombre.
                          final bool yaEstaEnRed = redDireccionesCentral.any((
                            dir,
                          ) {
                            final String nombreDir = dir.contains(' (')
                                ? dir.split(' (')[0].trim().toUpperCase()
                                : dir.trim().toUpperCase();
                            return nombreDir == barrioExtraido;
                          });

                          if (tarifaFinal > 0 &&
                              !yaEstaEnRed &&
                              barrioExtraido.isNotEmpty) {
                            final barrioCtrl = TextEditingController(
                              text: barrioExtraido,
                            );
                            String zonaSeleccionada = 'CÚCUTA';
                            bool guardandoRed = false;

                            // Usamos this.context (del State) en lugar del
                            // context del builder del diálogo, que ya se
                            // destruyó con el Navigator.pop de arriba.
                            showDialog(
                              context: this.context, // ignore: use_build_context_synchronously
                              builder: (ctxSave) => StatefulBuilder(
                                builder: (ctxSave, setSaveState) => AlertDialog(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  title: const Text(
                                    '💾 ¿GUARDAR EN LA RED?',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  content: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Esta dirección no está en la red de zonas. '
                                        '¿La agregamos para que todos los locales '
                                        'la vean como sugerencia?',
                                        style: TextStyle(fontSize: 13),
                                      ),
                                      const SizedBox(height: 12),
                                      TextField(
                                        controller: barrioCtrl,
                                        textCapitalization:
                                            TextCapitalization.characters,
                                        decoration: const InputDecoration(
                                          labelText:
                                              'Barrio / Zona (Ej: COCONUCO)',
                                          border: OutlineInputBorder(),
                                          isDense: true,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      const Text(
                                        '¿A qué municipio pertenece?',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Wrap(
                                        spacing: 6,
                                        runSpacing: 0,
                                        children: [
                                          'CÚCUTA',
                                          'LOS PATIOS',
                                          'V. ROSARIO',
                                        ].map((z) {
                                          return ChoiceChip(
                                            label: Text(
                                              z,
                                              style: const TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            selected: zonaSeleccionada == z,
                                            selectedColor: Colors.blue[100],
                                            onSelected: (bool selected) {
                                              if (selected) {
                                                setSaveState(
                                                  () => zonaSeleccionada = z,
                                                );
                                              }
                                            },
                                          );
                                        }).toList(),
                                      ),
                                    ],
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctxSave),
                                      child: const Text(
                                        'NO GUARDAR',
                                        style: TextStyle(color: Colors.grey),
                                      ),
                                    ),
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.black,
                                      ),
                                      onPressed: guardandoRed
                                          ? null
                                          : () async {
                                              if (barrioCtrl.text
                                                  .trim()
                                                  .isEmpty) {
                                                return;
                                              }
                                              setSaveState(
                                                () => guardandoRed = true,
                                              );
                                              try {
                                                await Supabase.instance.client
                                                    .from('red_direcciones')
                                                    .insert({
                                                      'nombre': barrioCtrl.text
                                                          .trim()
                                                          .toUpperCase(),
                                                      'municipio':
                                                          zonaSeleccionada,
                                                      'zona_lluvia': 'general',
                                                      'activo': true,
                                                    });
                                                if (ctxSave.mounted) {
                                                  Navigator.pop(ctxSave);
                                                  ScaffoldMessenger.of(
                                                    this.context, // ignore: use_build_context_synchronously
                                                  ).showSnackBar(
                                                    const SnackBar(
                                                      content: Text(
                                                        '✅ Dirección agregada a la red. '
                                                        'Todos los locales la verán.',
                                                      ),
                                                      backgroundColor:
                                                          Colors.green,
                                                    ),
                                                  );
                                                }
                                              } catch (e) {
                                                setSaveState(
                                                  () => guardandoRed = false,
                                                );
                                                if (ctxSave.mounted) {
                                                  ScaffoldMessenger.of(
                                                    this.context, // ignore: use_build_context_synchronously
                                                  ).showSnackBar(
                                                    SnackBar(
                                                      content: Text(
                                                        'Error BD: $e',
                                                      ),
                                                      backgroundColor:
                                                          Colors.red,
                                                    ),
                                                  );
                                                }
                                              }
                                            },
                                      child: guardandoRed
                                          ? const SizedBox(
                                              width: 16,
                                              height: 16,
                                              child: CircularProgressIndicator(
                                                color: Color(0xff3AF500),
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : const Text(
                                              'GUARDAR EN LA RED',
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
                        }
                      } catch (e) {
                        setDialogState(() => procesando = false);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Error al despachar: $e'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
              child: procesando
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xff3AF500),
                      ),
                    )
                  : const Text(
                      'ENVIAR AL RADAR',
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

  // ─── HELPERS FN ────────────────────────────────────────────────────────────

  String _fnLabelZona(String z) {
    switch (z) {
      case 'CUCUTA':
        return 'Cúcuta';
      case 'LOS_PATIOS':
        return 'Los Patios';
      case 'V_ROSARIO':
        return 'Villa del Rosario';
      default:
        return z;
    }
  }

  String _fnLabelSede(Map<String, dynamic> s) {
    final tipo = s['tipo'] as String;
    final nombre = s['nombre'] as String;
    if (tipo == 'FN') return 'FN #${s['numero']} – $nombre';
    return '$tipo – $nombre';
  }

  // ─── FORMULARIO FN ─────────────────────────────────────────────────────────
  // Crea un servicio FARMANORTE con cascada FN de 2 olas:
  //   T=0   → FN motos dentro de 2km de la sede (si vacío → todos)
  //   T+31s → Todos los FN motos (solo si T=0 fue subconjunto)

  void _abrirFormularioFN(BuildContext context) async {
    // ── Cargar sedes activas ──────────────────────────────────────────────────
    List<Map<String, dynamic>> sedes = [];
    try {
      sedes = List<Map<String, dynamic>>.from(
        await Supabase.instance.client
            .from('fn_sedes')
            .select()
            .eq('activo', true)
            .order('tipo')
            .order('numero', nullsFirst: false)
            .order('nombre'),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error cargando sedes FN: $e')));
      }
      return;
    }

    if (!context.mounted) return;

    if (sedes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay sedes FN activas. Créalas en Gestión → Farmanorte FN.')),
      );
      return;
    }

    // ── Ordenar sedes: numéricamente ascendente (menor a mayor) ──────────────
    final sedesOrdenadas = List<Map<String, dynamic>>.from(sedes)
      ..sort((a, b) {
        final na = int.tryParse(a['numero']?.toString() ?? '') ?? -1;
        final nb = int.tryParse(b['numero']?.toString() ?? '') ?? -1;
        return na.compareTo(nb);
      });

    // ── Estado del diálogo ────────────────────────────────────────────────────
    Map<String, dynamic>? sedeSolicitante;
    final List<Map<String, dynamic>?> recogidasSel = [null];
    final destinoCtrl = TextEditingController();
    final tarifaCtrl = TextEditingController();
    bool procesando = false;

    // Helper: dropdown de sedes ordenadas
    Widget dropdownSede({
      Map<String, dynamic>? value,
      void Function(Map<String, dynamic>?)? onChanged,
      String? label,
    }) =>
        DropdownButtonFormField<Map<String, dynamic>>(
          initialValue: value,
          isExpanded: true,
          hint: const Text('Seleccionar sede...',
              style: TextStyle(fontSize: 13, color: Colors.black38)),
          decoration: InputDecoration(
            labelText: label,
            labelStyle: TextStyle(fontSize: 11, color: Colors.indigo[700]),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          items: sedesOrdenadas
              .map((s) => DropdownMenuItem(
                    value: s,
                    child: Text(
                      _fnLabelSede(s),
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ))
              .toList(),
          onChanged: onChanged,
        );

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {

          return AlertDialog(
            insetPadding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 24),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            backgroundColor: Colors.white,
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.indigo[900],
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('FN',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          letterSpacing: 1.5)),
                ),
                const SizedBox(width: 10),
                const Text(
                  'SERVICIO FARMANORTE',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [

                    // ── Sede FN Solicitante ─────────────────────────────────
                    const Text('Sede FN solicitante:',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.black54,
                            fontSize: 12)),
                    const SizedBox(height: 4),
                    dropdownSede(
                      value: sedeSolicitante,
                      onChanged: procesando
                          ? null
                          : (v) => setDialogState(
                              () => sedeSolicitante = v),
                    ),
                    const SizedBox(height: 6),
                    // Zona chip — solo si hay sede seleccionada
                    if (sedeSolicitante != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.indigo[50],
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.location_on_outlined,
                                size: 13, color: Colors.indigo[700]),
                            const SizedBox(width: 4),
                            Text(
                              _fnLabelZona(
                                  sedeSolicitante!['zona'] as String),
                              style: TextStyle(
                                  color: Colors.indigo[800],
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),

                    const SizedBox(height: 14),

                    // ── Recogidas (lista dinámica de dropdowns) ─────────────
                    Row(
                      children: [
                        const Text('Recogidas:',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.black54,
                                fontSize: 12)),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: procesando
                              ? null
                              : () => setDialogState(() =>
                                  recogidasSel.add(null)),
                          icon: const Icon(Icons.add_circle_outline, size: 16),
                          label: const Text('Agregar',
                              style: TextStyle(fontSize: 12)),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.indigo[700],
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 0),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ...List.generate(recogidasSel.length, (i) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: dropdownSede(
                              value: recogidasSel[i],
                              label: 'Recogida ${i + 1}',
                              onChanged: procesando
                                  ? null
                                  : (v) => setDialogState(
                                      () => recogidasSel[i] = v),
                            ),
                          ),
                          if (recogidasSel.length > 1) ...[
                            const SizedBox(width: 4),
                            IconButton(
                              icon: const Icon(Icons.remove_circle,
                                  color: Colors.red, size: 20),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              tooltip: 'Quitar',
                              onPressed: procesando
                                  ? null
                                  : () => setDialogState(
                                      () => recogidasSel.removeAt(i)),
                            ),
                          ],
                        ],
                      ),
                    )),

                    const SizedBox(height: 8),

                    // ── Destino ─────────────────────────────────────────────
                    const Text('Destino:',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.black54,
                            fontSize: 12)),
                    const SizedBox(height: 4),
                    TextField(
                      controller: destinoCtrl,
                      textCapitalization: TextCapitalization.characters,
                      decoration: InputDecoration(
                        hintText: 'Dirección o barrio de entrega',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // ── Tarifa ──────────────────────────────────────────────
                    const Text('Tarifa:',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.black54,
                            fontSize: 12)),
                    const SizedBox(height: 4),
                    TextField(
                      controller: tarifaCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        hintText: '\$0',
                        prefixIcon: const Icon(Icons.attach_money),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed:
                    procesando ? null : () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: procesando
                    ? null
                    : () async {
                        if (sedeSolicitante == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Selecciona la sede solicitante')),
                          );
                          return;
                        }
                        if (destinoCtrl.text.trim().isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Ingresa el destino')),
                          );
                          return;
                        }
                        final tarifa = double.tryParse(
                                tarifaCtrl.text.replaceAll(',', '.')) ??
                            0;

                        setDialogState(() => procesando = true);

                        try {
                          final sede = sedeSolicitante!;
                          final zona = sede['zona'] as String;
                          final zonaLabel = _fnLabelZona(zona);
                          final sLat = (sede['lat'] as num?)?.toDouble();
                          final sLng = (sede['lng'] as num?)?.toDouble();
                          final nombreSede = _fnLabelSede(sede);

                          // Recogidas seleccionadas (solo las no nulas)
                          final recogidasList = recogidasSel
                              .whereType<Map<String, dynamic>>()
                              .map((s) => {
                                    'id': s['id'],
                                    'tipo': s['tipo'],
                                    'nombre': s['nombre'],
                                    'numero': s['numero'],
                                    'zona': s['zona'],
                                    'lat': s['lat'],
                                    'lng': s['lng'],
                                  })
                              .toList();

                          // ── Cargar FN motos online ─────────────────────────
                          final movilesConFn = await Supabase
                              .instance.client
                              .from('usuarios')
                              .select('id, latitud, longitud')
                              .eq('rol', 'movil')
                              .eq('en_linea', true)
                              .eq('tiene_fn', true)
                              .neq('suspendido', true);

                          final idsTodos = (movilesConFn as List)
                              .map<String>((m) => m['id'].toString())
                              .toList();

                          // ── Calcular ola 1: 2km desde la sede ─────────────
                          List<String> ids2km = [];
                          if (sLat != null && sLng != null) {
                            ids2km = movilesConFn.where((u) {
                              final uLat =
                                  (u['latitud'] as num?)?.toDouble();
                              final uLng =
                                  (u['longitud'] as num?)?.toDouble();
                              if (uLat == null || uLng == null) return false;
                              return const Distance().as(
                                    LengthUnit.Meter,
                                    LatLng(uLat, uLng),
                                    LatLng(sLat, sLng),
                                  ) <=
                                  2000;
                            }).map<String>((u) => u['id'].toString()).toList();
                          }

                          final wave1Ids =
                              ids2km.isNotEmpty ? ids2km : idsTodos;
                          // Ola 2 solo si ola 1 fue subconjunto
                          final wave2Needed = ids2km.isNotEmpty &&
                              ids2km.length < idsTodos.length;

                          // ── T=0: Disparo ola 1 ─────────────────────────────
                          if (wave1Ids.isNotEmpty) {
                            await MotorNotificaciones.dispararRafa(
                              idsDestinos: wave1Ids,
                              titulo: '🔵 TURNO FARMANORTE',
                              mensaje: 'Servicio FN · $zonaLabel',
                              urgente: true,
                              sonido: Sonidos.movilParadero,
                            );
                          }

                          // ── Insertar servicio ──────────────────────────────
                          final insertedSvc = await Supabase
                              .instance.client
                              .from('servicios')
                              .insert({
                                'origen': nombreSede,
                                'destino': destinoCtrl.text
                                    .trim()
                                    .toUpperCase(),
                                'tarifa': tarifa,
                                'estado':
                                    tarifa > 0 ? 'pendiente' : 'cotizacion',
                                'creador': 'Central FN',
                                'tipo_servicio': 'FARMANORTE',
                                'tipo_fn': true,
                                'zona_fn': zona,
                                'fn_sede_id': sede['id'],
                                'recogidas': recogidasList,
                                'fn_primera_ola': wave1Ids,
                                'metodo_pago': 'Efectivo',
                                'archivado': false,
                                if (sLat != null) 'origen_lat': sLat,
                                if (sLng != null) 'origen_lng': sLng,
                              })
                              .select('id')
                              .single();

                          final int nuevoId =
                              (insertedSvc['id'] as num).toInt();

                          // ── T+31s: Disparo ola 2 (todos FN) ───────────────
                          if (wave2Needed && idsTodos.isNotEmpty) {
                            final id31s = await MotorNotificaciones
                                .programarMisilRetardado(
                              externalIds: idsTodos,
                              titulo: '🔵 TURNO FARMANORTE',
                              mensaje:
                                  'Servicio FN sin tomar · $zonaLabel',
                              segundosRetardo: 31,
                              sonido: Sonidos.movilParadero,
                            );
                            if (id31s != null) {
                              await Supabase.instance.client
                                  .from('servicios')
                                  .update({'onesignal_30s': id31s})
                                  .eq('id', nuevoId);
                            }
                          }

                          if (context.mounted) {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  wave1Ids.isEmpty
                                      ? 'Servicio FN creado (sin motos FN en línea)'
                                      : 'Servicio FN enviado a ${wave1Ids.length} moto${wave1Ids.length == 1 ? '' : 's'}',
                                ),
                                backgroundColor: Colors.indigo[700],
                              ),
                            );
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Error: $e'),
                                backgroundColor: Colors.red[700],
                              ),
                            );
                            setDialogState(() => procesando = false);
                          }
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo[900],
                ),
                child: procesando
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('ENVIAR AL RADAR',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  void _mostrarMenuAsignacion(BuildContext contextoPrincipal, int servicioId) {
    showDialog(
      context: contextoPrincipal,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text(
          'ASIGNAR / REASIGNAR MÓVIL',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue),
        ),
        content: SizedBox(
          width: 400,
          height: 450,
          child: FutureBuilder<List<dynamic>>(
            // Cruce de tablas: Usuarios online + Servicios en curso
            future: Future.wait([
              Supabase.instance.client
                  .from('usuarios')
                  .select()
                  .eq('rol', 'movil')
                  .eq('en_linea', true),
              Supabase.instance.client
                  .from('servicios')
                  .select('movil_id')
                  .inFilter('estado', [
                    'en_ruta_origen',
                    'en_origen',
                    'en_ruta_destino',
                  ]),
            ]),
            builder: (ctx, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(color: Colors.black),
                );
              }

              final moviles =
                  List<Map<String, dynamic>>.from(snapshot.data?[0] ?? []).map((
                    m,
                  ) {
                    final map = Map<String, dynamic>.from(m);
                    map['nombre'] = _formatearNombreCentral(map);
                    return map;
                  }).toList();
              final activos = List<Map<String, dynamic>>.from(
                snapshot.data?[1] ?? [],
              );

              if (moviles.isEmpty) {
                return const Center(
                  child: Text(
                    'No hay móviles en línea.',
                    style: TextStyle(
                      color: Colors.grey,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                );
              }

              // Motor de Carga
              for (var m in moviles) {
                m['carga'] = activos
                    .where((s) => s['movil_id'] == m['id'])
                    .length;
              }

              // Ordenamiento táctico: Primero libres, luego por nombre
              moviles.sort((a, b) {
                int cmp = (a['carga'] as int).compareTo(b['carga'] as int);
                if (cmp == 0) {
                  return a['nombre'].toString().compareTo(
                    b['nombre'].toString(),
                  );
                }
                return cmp;
              });

              return ListView.builder(
                itemCount: moviles.length,
                itemBuilder: (ctx, index) {
                  final movil = moviles[index];
                  final int carga = movil['carga'];

                  Color colorCarga = const Color(0xff3AF500);
                  String txtCarga = 'LIBRE';
                  if (carga == 1) {
                    colorCarga = Colors.blue;
                    txtCarga = '1 VIAJE';
                  } else if (carga >= 2) {
                    colorCarga = Colors.red;
                    txtCarga = '$carga VIAJES';
                  }

                  return Card(
                    elevation: 1,
                    shape: RoundedRectangleBorder(
                      side: BorderSide(
                        color: carga >= 2
                            ? Colors.red[200]!
                            : Colors.transparent,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ListTile(
                      leading: CircleAvatar(
                        radius: 14,
                        backgroundColor: colorCarga,
                        child: Text(
                          _extraerNumeroAvatar(movil),
                          style: const TextStyle(
                            color: Colors.black,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      title: Text(
                        movil['nombre'],
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        'Rango: ${movil['rango_movil'] ?? 'NOVATO'}',
                        style: const TextStyle(fontSize: 11),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: colorCarga.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              txtCarga,
                              style: TextStyle(
                                color: colorCarga == const Color(0xff3AF500)
                                    ? Colors.green[900]
                                    : colorCarga,
                                fontWeight: FontWeight.bold,
                                fontSize: 10,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(Icons.send, color: Colors.blue, size: 18),
                        ],
                      ),
                      onTap: () async {
                        // 1. Asignamos el servicio
                        await Supabase.instance.client
                            .from('servicios')
                            .update({
                              'estado': 'en_ruta_origen',
                              'movil_id': movil['id'],
                              'accepted_at': DateTime.now()
                                  .toUtc()
                                  .toIso8601String(),
                              'picked_up_at': null,
                              'extension_minutes': 0,
                              'observacion':
                                  'Asignado a ${movil['nombre']} por Central',
                            })
                            .eq('id', servicioId);

                        // 2. QUEMAMOS EL TICKET VIP (Cobro del favor)
                        if (movil['ticket_prioridad'] == true) {
                          await Supabase.instance.client
                              .from('usuarios')
                              .update({'ticket_prioridad': false})
                              .eq('id', movil['id']);
                        }

                        // 3. Disparamos la notificación
                        await MotorNotificaciones.dispararMisil(
                          idDestino: movil['id'].toString(),
                          titulo: '🚨 NUEVO SERVICIO ASIGNADO',
                          mensaje:
                              'La Central te ha asignado un servicio manual. Revisa tu radar.',
                          sonido: Sonidos.alerta,
                        );

                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                          Navigator.pop(contextoPrincipal);
                        }
                      },
                    ),
                  );
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CANCELAR', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _mostrarMenuFusion(
    BuildContext contextoPrincipal,
    Map<String, dynamic> svcPrincipal,
  ) {
    showDialog(
      context: contextoPrincipal,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(
          'FUSIONAR ORDEN #${svcPrincipal['id']}',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.purple,
          ),
        ),
        content: SizedBox(
          width: 400,
          height: 400,
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: Supabase.instance.client
                .from('servicios')
                .select()
                .eq('estado', 'pendiente')
                .neq('id', svcPrincipal['id']),
            builder: (ctx, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(color: Colors.black),
                );
              }

              final pendientes = snapshot.data ?? [];
              if (pendientes.isEmpty) {
                return const Center(
                  child: Text(
                    'No hay otras órdenes pendientes en el radar para fusionar.',
                    style: TextStyle(
                      color: Colors.grey,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                    textAlign: TextAlign.center,
                  ),
                );
              }

              return Column(
                children: [
                  const Text(
                    'Selecciona la orden secundaria para amarrarla a esta. Se sumarán las tarifas y se unirán las rutas en un solo bloque.',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: ListView.builder(
                      itemCount: pendientes.length,
                      itemBuilder: (ctx, index) {
                        final svcSecundario = pendientes[index];
                        return Card(
                          elevation: 1,
                          child: ListTile(
                            title: Text(
                              'Orden #${svcSecundario['id']} | ${fmtPeso(svcSecundario['tarifa'])}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            subtitle: Text(
                              '${svcSecundario['origen']} ➔ ${svcSecundario['destino']}',
                              style: const TextStyle(fontSize: 11),
                            ),
                            trailing: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.purple[800],
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                              ),
                              onPressed: () async {
                                final double tarifa1 =
                                    (svcPrincipal['tarifa'] as num?)
                                        ?.toDouble() ??
                                    0.0;
                                final double tarifa2 =
                                    (svcSecundario['tarifa'] as num?)
                                        ?.toDouble() ??
                                    0.0;

                                final String obs1 =
                                    svcPrincipal['observacion'] ?? 'Sin notas';
                                final String obs2 =
                                    svcSecundario['observacion'] ?? 'Sin notas';
                                final String nuevaObs =
                                    '[FUSIÓN CON #${svcSecundario['id']}]\n1: $obs1\n2: $obs2';

                                final String nuevoDestino =
                                    '${svcPrincipal['destino']} Y ${svcSecundario['destino']}';
                                final String nuevoOrigen =
                                    '${svcPrincipal['origen']} Y ${svcSecundario['origen']}';

                                await Supabase.instance.client
                                    .from('servicios')
                                    .update({
                                      'origen': nuevoOrigen,
                                      'destino': nuevoDestino,
                                      'tarifa': tarifa1 + tarifa2,
                                      'tarifa_detalle': {
                                        'base': tarifa1 + tarifa2,
                                        'total': tarifa1 + tarifa2,
                                        'fuente': 'fusion',
                                        'ajuste_manual': 0,
                                      },
                                      'observacion': nuevaObs,
                                    })
                                    .eq('id', svcPrincipal['id']);

                                await Supabase.instance.client
                                    .from('servicios')
                                    .update({
                                      'estado': 'cancelado',
                                      'observacion':
                                          'SISTEMA: Fusionado dentro del bloque #${svcPrincipal['id']}',
                                    })
                                    .eq('id', svcSecundario['id']);

                                if (ctx.mounted) {
                                  Navigator.pop(ctx);
                                  Navigator.pop(contextoPrincipal);
                                  ScaffoldMessenger.of(
                                    contextoPrincipal,
                                  ).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        '¡Órdenes amarradas con éxito!',
                                      ),
                                      backgroundColor: Colors.purple,
                                    ),
                                  );
                                }
                              },
                              child: const Text(
                                'UNIR',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CANCELAR'),
          ),
        ],
      ),
    );
  }

  Future<void> _abrirWhatsAppCentral(String telefono, int idPedido) async {
    if (telefono.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Sin número registrado.')));
      }
      return;
    }
    String numero = telefono.replaceAll(RegExp(r'[^0-9]'), '');
    if (numero.length == 10) numero = '57$numero';
    final Uri url = Uri.parse(
      'https://wa.me/$numero?text=${Uri.encodeComponent('Central ServiExpress 📡 | Sobre la Orden #$idPedido: ')}',
    );
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar( // ignore: use_build_context_synchronously
          const SnackBar(content: Text('No se pudo abrir WhatsApp.')),
        );
      }
    }
  }

  /// Fast-path para cotizaciones: llama a sugerir_tarifa y, si hay alta
  /// confianza, ofrece resolver con un solo tap sin abrir el formulario
  /// completo. Devuelve `true` si el asunto quedó resuelto (o cancelado
  /// por el usuario), `false` si debe abrirse el diálogo completo.
  Future<bool> _fastPathCotizacion(
    BuildContext context,
    Map<String, dynamic> servicio,
    bool esVip,
  ) async {
    if (!mounted) return false;

    final String origen  = servicio['creador']?.toString() ?? '';
    final String destino = servicio['destino']?.toString()  ?? '';
    final String? tipo   = servicio['tipo_servicio']?.toString();

    // Llamada rápida al motor
    Map<String, dynamic>? row;
    try {
      final params = <String, dynamic>{
        'p_origen':  origen,
        'p_destino': destino,
        if (servicio['destino_lat'] != null) 'p_destino_lat': (servicio['destino_lat'] as num).toDouble(),
        if (servicio['destino_lng'] != null) 'p_destino_lng': (servicio['destino_lng'] as num).toDouble(),
        if (tipo != null)               'p_tipo_servicio': tipo,
      };
      final res = await Supabase.instance.client.rpc('sugerir_tarifa', params: params);
      if (res != null && (res as List).isNotEmpty) row = res[0] as Map<String, dynamic>;
    } catch (_) {
      return false; // cualquier error → caer al diálogo completo
    }

    if (row == null) return false;
    final String confianza = row['confianza']?.toString() ?? 'sin_historial';
    if (confianza != 'alta') return false; // solo fast-path con alta confianza

    final int precioSugerido = (row['precio_sugerido'] as num?)?.toInt() ?? 0;
    if (precioSugerido <= 0) return false;

    final double tarifaFinal = esVip ? (precioSugerido + 3000).toDouble() : precioSugerido.toDouble();
    final String textoTarifa = _formatearMonedaCentral(tarifaFinal);

    if (!mounted) return false;

    final bool? confirmar = await showDialog<bool>(
      context: context, // ignore: use_build_context_synchronously
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Row(
          children: [
            const Text('⚡', style: TextStyle(fontSize: 20)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Cotización Rápida #${servicio['id']}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${servicio['creador']?.toString() ?? ''} → $destino',
              style: const TextStyle(fontSize: 13, color: Colors.black54),
            ),
            if (tipo != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(tipo, style: const TextStyle(fontSize: 12, color: Colors.black38)),
              ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.green[300]!),
              ),
              child: Column(
                children: [
                  Text(
                    textoTarifa,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.green[800],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.auto_graph, size: 13, color: Colors.green[700]),
                      const SizedBox(width: 4),
                      Text(
                        '● Alta confianza · ${row?['num_precedentes'] ?? 0} servicios similares',
                        style: TextStyle(fontSize: 11, color: Colors.green[700]),
                      ),
                    ],
                  ),
                  if (esVip) ...[
                    const SizedBox(height: 4),
                    Text(
                      '(+\$3.000 VIP incluido)',
                      style: TextStyle(fontSize: 11, color: Colors.amber[800]),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null), // null → abrir diálogo completo
            child: const Text('Revisar manualmente', style: TextStyle(color: Colors.black45)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green[700],
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'COTIZAR A $textoTarifa',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirmar != true) {
      // null = "Revisar manualmente" → caer al diálogo completo
      return confirmar == false; // false = usuario cerró el dialog (cancelar)
    }

    // Confirmar → aplicar directamente en BD
    try {
      await Supabase.instance.client.from('servicios').update({
        'tarifa': tarifaFinal,
        'tarifa_detalle': {
          'total': tarifaFinal,
          'base': precioSugerido,
          'fuente': 'motor_alta_fast',
          if (esVip) 'vip': 3000,
        },
        'estado': 'cotizada',
      }).eq('id', servicio['id']);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar( // ignore: use_build_context_synchronously
          SnackBar(
            content: Text('⚡ Cotización enviada: $textoTarifa'),
            backgroundColor: Colors.green[700],
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar( // ignore: use_build_context_synchronously
          SnackBar(content: Text('Error al cotizar: $e'), backgroundColor: Colors.red),
        );
      }
    }
    return true;
  }

  Future<void> _abrirMenuGestion(BuildContext context, Map<String, dynamic> servicio) async {
    final String estado = servicio['estado'];
    final int id = servicio['id'];

    final double tarifaActual = (servicio['tarifa'] is num)
        ? (servicio['tarifa'] as num).toDouble()
        : 0.0;
    final String textoInicial = (tarifaActual == 0.0)
        ? ''
        : _formatearMonedaCentral(tarifaActual);
    final tarifaController = TextEditingController(text: textoInicial);

    // Desglose capturado por CampoTarifaInteligente en esta cotización.
    Map<String, dynamic>? detalleCotizacion;

    final bool esVip = servicio['es_vip'] == true;

    if (estado == 'cotizacion') {
      // FAST-PATH: si el motor tiene alta confianza, ofrecemos resolución en 1 tap.
      // Si el usuario elige "Revisar manualmente" (null), caemos al diálogo completo.
      // Si la llamada falla o confianza != 'alta', también caemos al diálogo completo.
      final bool resueltoPorMotor = await _fastPathCotizacion(context, servicio, esVip);
      if (resueltoPorMotor) return;

      if (!mounted) return;
      showDialog(
        context: context, // ignore: use_build_context_synchronously
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          title: esVip
              ? ShaderMask(
                  shaderCallback: (bounds) => const LinearGradient(
                    colors: [
                      Color(0xFFB8860B),
                      Color(0xFFFFD700),
                      Color(0xFFFFF0A0),
                      Color(0xFFFFD700),
                      Color(0xFFB8860B),
                    ],
                    stops: [0.0, 0.25, 0.5, 0.75, 1.0],
                  ).createShader(bounds),
                  child: Text(
                    '👑 COTIZACIÓN VIP #$id',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                )
              : Text(
                  'RESOLVER COTIZACIÓN #$id',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.orange,
                  ),
                ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '🏢 Origen: ${servicio['creador'].toString().toUpperCase()}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Text('🏁 Va para: ${servicio['destino']}'),
              const SizedBox(height: 16),
              // Motor de tarifas: sugiere precio basado en historial
              // usando el origen/destino de la cotización
              CampoTarifaInteligente(
                origenController: TextEditingController(
                  text: servicio['creador']?.toString() ?? '',
                ),
                destinoController: TextEditingController(
                  text: servicio['destino']?.toString() ?? '',
                ),
                tarifaController: tarifaController,
                destinoLat: (servicio['destino_lat'] as num?)?.toDouble(),
                destinoLng: (servicio['destino_lng'] as num?)?.toDouble(),
                tipoServicio: servicio['tipo_servicio']?.toString(),
                onDetalleChanged: (d) => detalleCotizacion = d,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CERRAR'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.black),
              onPressed: () async {
                // --- INYECCIÓN DE LIMPIEZA TÁCTICA ---
                String tarifaLimpia = tarifaController.text
                    .replaceAll('\$', '')
                    .replaceAll('.', '')
                    .replaceAll(',', '')
                    .trim();
                double precioAsignado = double.tryParse(tarifaLimpia) ?? 0.0;

                if (precioAsignado <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Ingresa un precio para enviar la cotización.',
                      ),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                if (precioAsignado > 0) {
                  // Si es VIP se suman $3.000 automáticamente
                  final double tarifaFinal = esVip ? precioAsignado + 3000 : precioAsignado;
                  await Supabase.instance.client
                      .from('servicios')
                      .update({
                        'tarifa': tarifaFinal,
                        'tarifa_detalle': detalleCotizacion != null
                            ? {...detalleCotizacion!, 'total': tarifaFinal}
                            : {'total': tarifaFinal, 'fuente': 'central_cotizacion'},
                        'estado': 'cotizada',
                      })
                      .eq('id', id);
                  if (context.mounted) Navigator.pop(context);
                }
              },
              child: const Text(
                'ENVIAR PRECIO',
                style: TextStyle(
                  color: Color(0xff3AF500),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      );
      return;
    }

    if (estado == 'cotizada') {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          title: Text(
            'COTIZACIÓN ENVIADA #$id',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.blue,
            ),
          ),
          content: Text(
            'Ya enviaste una tarifa de ${fmtPeso(servicio['tarifa'])}. Esperando respuesta del cliente o local.',
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await Supabase.instance.client
                    .from('servicios')
                    .update({
                      'estado': 'cancelado',
                      'observacion':
                          'Central canceló la cotización por falta de respuesta.',
                    })
                    .eq('id', id);
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text(
                'CANCELAR COTIZACIÓN',
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.black),
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'ESPERAR',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'CONTROL DE ORDEN #$id',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('📍 Origen: ${servicio['origen']}'),
            Text('🏁 Destino: ${servicio['destino']}'),
            Text(
              '📱 Tel. Receptor: ${servicio['telefono_receptor'] ?? 'No registrado'}',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.blue,
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    inputFormatters: [CurrencyInputFormatter()],
                    controller: tarifaController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: (tarifaActual == 0.0)
                          ? 'Fijar Tarifa de Central (\$)'
                          : 'Modificar Tarifa',
                      border: const OutlineInputBorder(),
                      isDense: true,
                      filled: true,
                      fillColor: Colors.green[50],
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        tooltip: 'Borrar',
                        onPressed: () => tarifaController.clear(),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green[800],
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    onPressed: () async {
                      // --- INYECCIÓN DE LIMPIEZA TÁCTICA ---
                      String tarifaLimpia = tarifaController.text
                          .replaceAll('\$', '')
                          .replaceAll('.', '')
                          .replaceAll(',', '')
                          .trim();
                      double nuevoPrecio = double.tryParse(tarifaLimpia) ?? 0.0;

                      if (nuevoPrecio > 0) {
                        await Supabase.instance.client
                            .from('servicios')
                            .update({
                              'tarifa': nuevoPrecio,
                              'tarifa_detalle': {
                                'total': nuevoPrecio,
                                'fuente': 'central_manual',
                                'ajuste_manual': nuevoPrecio,
                              },
                            })
                            .eq('id', id);
                        if (context.mounted) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('✅ Tarifa inyectada con éxito'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      }
                    },
                    child: const Text(
                      'FIJAR',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (servicio['observacion'] != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(8),
                color: Colors.grey[200],
                child: Text(
                  '📝 NOTA: ${servicio['observacion']}',
                  style: const TextStyle(
                    color: Colors.black87,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 15),
            const Text(
              'LÍNEAS DIRECTAS:',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 6),

            // FILA DEL MÓVIL
            if (servicio['movil_id'] != null)
              FutureBuilder<Map<String, dynamic>?>(
                future: Supabase.instance.client
                    .from('usuarios')
                    .select('telefono, nombre, usuario, rol')
                    .eq('id', servicio['movil_id'])
                    .maybeSingle(),
                builder: (ctx, snap) {
                  final tel = snap.data?['telefono']?.toString() ?? '';
                  final nom = _formatearNombreCentral(snap.data);
                  bool alarmaMovil = servicio['chat_movil_central'] == true;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xff25D366),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                            ),
                            onPressed: () => _abrirWhatsAppCentral(tel, id),
                            icon: const Icon(Icons.wechat, size: 14),
                            label: const Text(
                              'WS MÓVIL',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: alarmaMovil
                                  ? Colors.red[700]
                                  : Colors.black,
                              foregroundColor: alarmaMovil
                                  ? Colors.white
                                  : Colors.blue,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                            ),
                            onPressed: () {
                              final salaMovil = 'soporte_movil_$id';
                              setState(() => _noLeidos.remove(salaMovil));
                              Supabase.instance.client
                                  .from('servicios')
                                  .update({'chat_movil_central': false})
                                  .eq('id', id);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ChatScreen(
                                    salaId: salaMovil,
                                    miId: 0,
                                    miNombre: 'Central',
                                    titulo: 'Chat con $nom',
                                    servicioId: id,
                                    alarmaLocal: 'chat_movil_central',
                                    alarmaDestino: 'chat_central_movil',
                                    destinatarioId: servicio['movil_id'] as int?,
                                    tipoFaq: TipoFaqChat.central,
                                  ),
                                ),
                              );
                            },
                            icon: Icon(
                              alarmaMovil
                                  ? Icons.mark_email_unread
                                  : Icons.chat,
                              size: 14,
                            ),
                            label: Builder(builder: (_) {
                              final cnt = _noLeidos['soporte_movil_$id'] ?? 0;
                              return Text(
                                alarmaMovil
                                    ? (cnt > 0 ? '$cnt SIN LEER' : 'NUEVO MSG')
                                    : 'CHAT MÓVIL',
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              );
                            }),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),

            // FILA DEL CLIENTE
            if (servicio['cliente_id'] != null)
              FutureBuilder<Map<String, dynamic>?>(
                future: Supabase.instance.client
                    .from('usuarios')
                    .select('telefono, nombre')
                    .eq('id', servicio['cliente_id'])
                    .maybeSingle(),
                builder: (ctx, snap) {
                  final tel = snap.data?['telefono']?.toString() ?? '';
                  final nom = snap.data?['nombre']?.toString() ?? 'Cliente';
                  bool alarmaCliente = servicio['chat_cliente_central'] == true;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xff128C7E),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                            ),
                            onPressed: () => _abrirWhatsAppCentral(tel, id),
                            icon: const Icon(Icons.wechat, size: 14),
                            label: const Text(
                              'WS CLIENTE',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: alarmaCliente
                                  ? Colors.red[700]
                                  : Colors.black,
                              foregroundColor: alarmaCliente
                                  ? Colors.white
                                  : const Color(0xff3AF500),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                            ),
                            onPressed: () {
                              final salaCliente = 'soporte_cliente_$id';
                              setState(() => _noLeidos.remove(salaCliente));
                              Supabase.instance.client
                                  .from('servicios')
                                  .update({'chat_cliente_central': false})
                                  .eq('id', id);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ChatScreen(
                                    salaId: salaCliente,
                                    miId: 0,
                                    miNombre: 'Central',
                                    titulo: 'Chat con $nom',
                                    servicioId: id,
                                    alarmaLocal: 'chat_cliente_central',
                                    alarmaDestino: 'chat_central_cliente',
                                    destinatarioId: servicio['cliente_id'] as int?,
                                    tipoFaq: TipoFaqChat.central,
                                  ),
                                ),
                              );
                            },
                            icon: Icon(
                              alarmaCliente
                                  ? Icons.mark_email_unread
                                  : Icons.chat,
                              size: 14,
                            ),
                            label: Builder(builder: (_) {
                              final cnt = _noLeidos['soporte_cliente_$id'] ?? 0;
                              return Text(
                                alarmaCliente
                                    ? (cnt > 0
                                        ? '$cnt SIN LEER'
                                        : 'NUEVO MSG')
                                    : 'CHAT CLIENTE',
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              );
                            }),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
        actions: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            alignment: WrapAlignment.end,
            children: [
              // ---> INYECTA EL BOTÓN DE FUSIÓN AQUÍ <---
              if (estado == 'pendiente')
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purple[800],
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 0,
                    ),
                  ),
                  onPressed: () => _mostrarMenuFusion(context, servicio),
                  child: const Text(
                    'FUSIONAR',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),
              // ------------------------------------------

              // ── BOTÓN GPS (solo servicios activos) ───────────────────
              if (!['finalizado', 'finalizado_por_demora',
                    'finalizado_con_problema', 'cancelado', 'caducado']
                  .contains(estado))
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[700],
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 0),
                  ),
                  icon: const Icon(Icons.my_location,
                      color: Colors.white, size: 13),
                  label: const Text(
                    'PEDIR GPS',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 11),
                  ),
                  onPressed: () async {
                    final link =
                        'https://oukiofdtargjrclualgm.supabase.co'
                        '/functions/v1/capturar-ubicacion?id=$id';
                    final mensaje = Uri.encodeComponent(
                      'Hola 👋 Para que el conductor llegue exactamente '
                      'donde estás, toca este enlace y activa tu GPS '
                      '(un segundo):\n$link',
                    );
                    final uri = Uri.parse('https://wa.me/?text=$mensaje');
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri,
                          mode: LaunchMode.externalApplication);
                    }
                  },
                ),
              // ── FIN BOTÓN GPS ─────────────────────────────────────────
              if ([
                'cancelado',
                'finalizado_por_demora',
                'finalizado_con_problema',
                'caducado',
              ].contains(estado))
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xff3AF500),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 0,
                    ),
                  ),
                  onPressed: () async {
                    await Supabase.instance.client
                        .from('servicios')
                        .update({
                          'estado': 'pendiente',
                          'movil_id': null,
                          'observacion': null,
                          'accepted_at': null,
                          'picked_up_at': null,
                          'extension_minutes': 0,
                        })
                        .eq('id', id);
                    if (context.mounted) Navigator.pop(context);
                  },
                  child: const Text(
                    'REACTIVAR',
                    style: TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue[800],
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 0,
                  ),
                ),
                onPressed: () => _mostrarMenuAsignacion(context, id),
                child: const Text(
                  'REASIGNAR',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ),
              if (estado != 'cancelado' && estado != 'finalizado')
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red[800],
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 0,
                    ),
                  ),
                  onPressed: () async {
                    await Supabase.instance.client
                        .from('servicios')
                        .update({'estado': 'cancelado'})
                        .eq('id', id);
                    if (context.mounted) Navigator.pop(context);
                  },
                  child: const Text(
                    'CANCELAR',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),
              if (estado != 'finalizado')
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 0,
                    ),
                  ),
                  onPressed: () async {
                    String obsAnterior = servicio['observacion'] ?? '';
                    String nuevaObs = obsAnterior;
                    if ([
                      'cancelado',
                      'finalizado_por_demora',
                      'finalizado_con_problema',
                    ].contains(estado)) {
                      nuevaObs =
                          '[MARCA DE FALLA] ${obsAnterior.isEmpty ? 'Cerrado forzoso por Central' : obsAnterior}';
                    }
                    await Supabase.instance.client
                        .from('servicios')
                        .update({
                          'estado': 'finalizado',
                          'observacion': nuevaObs.isEmpty ? null : nuevaObs,
                        })
                        .eq('id', id);
                    if (context.mounted) Navigator.pop(context);
                  },
                  child: const Text(
                    'FINALIZAR',
                    style: TextStyle(
                      color: Color(0xff3AF500),
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  'VOLVER',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── BOTONES DE ACCIÓN EN CARD ─────────────────────────────────────────────

  Widget _botonCard(
          String label, IconData icon, Color color, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: color.withValues(alpha: 0.5), width: 0.8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 11, color: color),
              const SizedBox(width: 4),
              Text(label,
                  style: TextStyle(
                      fontSize: 10,
                      color: color,
                      fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      );

  List<Widget> _botonesAccion(
      BuildContext context, Map<String, dynamic> servicio, String estado) {
    const finales = {
      'finalizado',
      'finalizado_con_problema',
      'finalizado_por_demora',
      'cancelado',
    };
    final btns = <Widget>[];

    // 💰 PRECIO (solo cotizacion — el tap normal ya lo hace pero aquí queda explícito)
    if (estado == 'cotizacion') {
      btns.add(_botonCard('PRECIO', Icons.attach_money, Colors.orange[700]!,
          () => _cotizarRapido(context, servicio)));
    }

    // 🏍 ASIGNAR
    if (['pendiente', 'cotizacion_aprobada', 'cotizada'].contains(estado)) {
      btns.add(_botonCard('ASIGNAR', Icons.motorcycle, Colors.blue[700]!,
          () => _asignarMotoManual(context, servicio)));
    }

    // 🔄 REASIGNAR
    if (estado == 'programado') {
      btns.add(_botonCard('REASIGNAR', Icons.motorcycle, Colors.blue[600]!,
          () => _asignarMotoManual(context, servicio)));
    }

    // ✅ FINALIZAR
    if (['programado', 'en_ruta_origen', 'en_origen', 'en_ruta_destino']
        .contains(estado)) {
      btns.add(_botonCard('FINALIZAR', Icons.check_circle_outline,
          Colors.green[700]!, () => _finalizarServicio(context, servicio)));
    }

    // ⚠️ PROBLEMA
    if (['en_ruta_origen', 'en_origen', 'en_ruta_destino', 'programado']
        .contains(estado)) {
      btns.add(_botonCard('PROBLEMA', Icons.warning_amber_rounded,
          Colors.orange[800]!, () => _marcarProblema(context, servicio)));
    }

    // 🔄 REACTIVAR
    if (['cancelado', 'caducado', 'problema', 'finalizado_por_demora']
        .contains(estado)) {
      btns.add(_botonCard('REACTIVAR', Icons.refresh, Colors.teal[700]!,
          () => _reactivarServicio(servicio)));
    }

    // 🏁 FINALIZAR CON PROBLEMA
    if (estado == 'problema') {
      btns.add(_botonCard('FIN+PROB', Icons.flag_outlined, Colors.red[700]!,
          () => _finalizarConProblema(context, servicio)));
    }

    // ❌ CANCELAR — todo excepto estados finales y ya cancelado
    if (!finales.contains(estado)) {
      btns.add(_botonCard('CANCELAR', Icons.close, Colors.red[700]!,
          () => _cancelarServicio(context, servicio)));
    }

    return btns;
  }

  Future<void> _asignarMotoManual(
      BuildContext context, Map<String, dynamic> servicio) async {
    final ahora = DateTime.now().toUtc();
    final motos = List<Map<String, dynamic>>.from(_movilesCache)
      ..sort((a, b) {
        final pa = a['ultimo_ping'] != null
            ? DateTime.parse(a['ultimo_ping']).toUtc()
            : DateTime(2000);
        final pb = b['ultimo_ping'] != null
            ? DateTime.parse(b['ultimo_ping']).toUtc()
            : DateTime(2000);
        return pb.compareTo(pa); // más reciente primero
      });

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(ctx).size.height * 0.6,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 4),
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.motorcycle, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${servicio["origen"] ?? ""} ➔ ${servicio["destino"] ?? ""}',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: motos.isEmpty
                  ? const Center(child: Text('Sin motos registradas'))
                  : ListView.builder(
                      itemCount: motos.length,
                      itemBuilder: (ctx, i) {
                        final moto = motos[i];
                        final ping = moto['ultimo_ping'] != null
                            ? DateTime.parse(moto['ultimo_ping']).toUtc()
                            : null;
                        final mins = ping != null
                            ? ahora.difference(ping).inMinutes
                            : null;
                        final conectado = mins != null && mins < 5;
                        final nombre = _formatearNombreCentral(moto);
                        final rango =
                            moto['rango_movil']?.toString() ?? 'NOVATO';

                        return ListTile(
                          dense: true,
                          leading: CircleAvatar(
                            radius: 16,
                            backgroundColor: conectado
                                ? Colors.green[50]
                                : Colors.grey[100],
                            child: Icon(Icons.motorcycle,
                                size: 16,
                                color: conectado
                                    ? Colors.green[700]
                                    : Colors.grey[400]),
                          ),
                          title: Text(nombre,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13)),
                          subtitle: Text(
                            '$rango${mins != null ? " · hace ${mins}min" : " · sin ping"}',
                            style: const TextStyle(fontSize: 11),
                          ),
                          trailing: Icon(Icons.circle,
                              size: 10,
                              color: conectado
                                  ? Colors.green
                                  : Colors.grey[400]),
                          onTap: () async {
                            Navigator.pop(ctx);
                            await Supabase.instance.client
                                .from('servicios')
                                .update({
                                  'movil_id': moto['id'],
                                  'estado': 'programado',
                                })
                                .eq('id', servicio['id']);
                            _seleccionadoId.value = null;
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _cancelarServicio(
      BuildContext context, Map<String, dynamic> servicio) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Cancelar servicio',
            style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text(
            'Servicio #${servicio["id"]}\n${servicio["origen"]} ➔ ${servicio["destino"]}'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('NO', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style:
                ElevatedButton.styleFrom(backgroundColor: Colors.red[700]),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('SÍ, CANCELAR',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await Supabase.instance.client.from('servicios').update({
        'estado': 'cancelado',
        'observacion': servicio['observacion'] != null
            ? '${servicio["observacion"]} | Cancelado por central'
            : 'Cancelado por central',
      }).eq('id', servicio['id']);
      _seleccionadoId.value = null;
    }
  }

  Future<void> _finalizarServicio(
      BuildContext context, Map<String, dynamic> servicio) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Finalizar servicio',
            style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text('¿Marcar #${servicio["id"]} como finalizado?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('NO', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green[700]),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('FINALIZAR',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await Supabase.instance.client
          .from('servicios')
          .update({'estado': 'finalizado'})
          .eq('id', servicio['id']);
      _seleccionadoId.value = null;
    }
  }

  Future<void> _finalizarConProblema(
      BuildContext context, Map<String, dynamic> servicio) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Finalizar con problema',
            style: TextStyle(fontWeight: FontWeight.bold)),
        content:
            Text('¿Cerrar #${servicio["id"]} como finalizado con problema?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('NO', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style:
                ElevatedButton.styleFrom(backgroundColor: Colors.red[700]),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('CONFIRMAR',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await Supabase.instance.client
          .from('servicios')
          .update({'estado': 'finalizado_con_problema'})
          .eq('id', servicio['id']);
      _seleccionadoId.value = null;
    }
  }

  Future<void> _marcarProblema(
      BuildContext context, Map<String, dynamic> servicio) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Marcar problema',
            style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text('¿Reportar problema en servicio #${servicio["id"]}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('NO', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange[700]),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('CONFIRMAR',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await Supabase.instance.client
          .from('servicios')
          .update({'estado': 'problema'})
          .eq('id', servicio['id']);
      _seleccionadoId.value = null;
    }
  }

  Future<void> _reactivarServicio(Map<String, dynamic> servicio) async {
    await Supabase.instance.client.from('servicios').update({
      'estado': 'pendiente',
      'movil_id': null,
      'onesignal_30s': null,
    }).eq('id', servicio['id']);
    _seleccionadoId.value = null;
  }

  // ── COTIZACIÓN RÁPIDA (bottom sheet) ──────────────────────────────────────

  Future<void> _cotizarRapido(
      BuildContext context, Map<String, dynamic> servicio) async {
    final TextEditingController precioCtrl = TextEditingController();
    bool esVip = servicio['es_vip'] == true;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding:
              EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle visual
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Ruta
                Row(
                  children: [
                    const Icon(Icons.route, size: 16, color: Colors.black54),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${servicio["origen"] ?? "—"} ➔ ${servicio["destino"] ?? "—"}',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                if (servicio['cliente_nombre'] != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    '👤 ${servicio["cliente_nombre"]}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
                const SizedBox(height: 16),

                // Campo precio
                TextField(
                  controller: precioCtrl,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    prefixText: '\$ ',
                    prefixStyle: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.bold),
                    hintText: '0',
                    labelText: 'Precio del servicio',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8)),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide:
                          const BorderSide(color: Colors.black, width: 2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Toggle VIP
                GestureDetector(
                  onTap: () => setSheet(() => esVip = !esVip),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: esVip
                          ? const Color(0xFFFFF8E1)
                          : Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: esVip
                            ? const Color(0xFFFFD700)
                            : Colors.grey[300]!,
                      ),
                    ),
                    child: Row(
                      children: [
                        Text(esVip ? '👑' : '⬜',
                            style: const TextStyle(fontSize: 18)),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text('Servicio VIP  (+\$3.000)',
                              style: TextStyle(fontWeight: FontWeight.w600)),
                        ),
                        Switch(
                          value: esVip,
                          onChanged: (v) => setSheet(() => esVip = v),
                          activeColor: const Color(0xFFB8860B),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Botones
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          side: const BorderSide(color: Colors.black38),
                        ),
                        child: const Text('Cancelar'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: () async {
                          final raw = precioCtrl.text
                              .replaceAll(RegExp(r'[^0-9]'), '');
                          final base = int.tryParse(raw) ?? 0;
                          if (base <= 0) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(
                                  content: Text('Ingresa un precio válido'),
                                  duration: Duration(seconds: 2)),
                            );
                            return;
                          }
                          final tarifaFinal = esVip ? base + 3000 : base;
                          Navigator.pop(ctx);
                          await Supabase.instance.client
                              .from('servicios')
                              .update({
                                'tarifa': tarifaFinal,
                                'es_vip': esVip,
                                'estado': 'cotizada',
                              })
                              .eq('id', servicio['id']);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text(
                          'CONFIRMAR PRECIO',
                          style: TextStyle(
                            color: Color(0xff3AF500),
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    precioCtrl.dispose();
  }

  // ── HELPERS MONITOR ────────────────────────────────────────────────────────

  Widget _kpiChip(String label, int count, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: RichText(
          text: TextSpan(children: [
            TextSpan(
              text: '$count ',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: color,
                  height: 1),
            ),
            TextSpan(
              text: label,
              style: TextStyle(fontSize: 8, color: color, height: 1),
            ),
          ]),
        ),
      );

  String _tiempoRelativo(DateTime utc) {
    final diff = DateTime.now().toUtc().difference(utc);
    if (diff.inMinutes < 1) return 'ahora';
    if (diff.inMinutes < 60) return 'hace ${diff.inMinutes}min';
    final h = diff.inHours;
    final m = diff.inMinutes % 60;
    return m == 0 ? 'hace ${h}h' : 'hace ${h}h ${m}m';
  }

  Widget _chipEstadoMonitor(String estado, Color colorBase) {
    const labels = <String, String>{
      'pendiente': 'LIBRE',
      'cotizacion': 'COTIZ.',
      'cotizada': 'ENVIADA',
      'cotizacion_aprobada': 'APROB.',
      'programado': 'PROGR.',
      'en_ruta_origen': 'RECOG.',
      'en_origen': 'EN LOCAL',
      'en_ruta_destino': 'ENTREGA',
      'problema': 'PROBL.',
      'finalizado': 'FIN.',
      'finalizado_con_problema': 'FIN.PROB',
      'finalizado_por_demora': 'DEMORA',
      'caducado': 'CADUC.',
      'cancelado': 'CANCEL.',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: colorBase.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: colorBase.withValues(alpha: 0.6), width: 0.8),
      ),
      child: Text(
        labels[estado] ?? estado.toUpperCase(),
        style: TextStyle(
            fontSize: 8,
            fontWeight: FontWeight.bold,
            color: colorBase,
            letterSpacing: 0.3),
      ),
    );
  }

  Widget _construirBloqueServicios(
    BuildContext context,
    String titulo,
    List<Map<String, dynamic>> lista,
    Color colorBase,
    IconData icono, {
    bool visible = true,
  }) {
    final int count = lista.length;

    // Ocultar bloque completo si está filtrado fuera o no hay servicios de este tipo
    if (!visible || count == 0) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          margin: const EdgeInsets.only(top: 10, bottom: 4, left: 6, right: 6),
          decoration: BoxDecoration(
            color: colorBase.withValues(alpha: 0.12),
            border: Border(
              left: BorderSide(color: colorBase, width: 4),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  titulo,
                  style: const TextStyle(
                    color: Colors.black87,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                    letterSpacing: 1,
                  ),
                ),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: Container(
                  key: ValueKey(count),
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: colorBase,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$count',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        ...lista.map((servicio) {
          // Resolver el número real del moto a partir de su campo 'usuario'
          // (ej: movil05 → #5). numero_movil es un contador acumulativo de
          // servicios, no el identificador del moto.
          final movCacheEntry = _movilesCache.firstWhere(
            (m) => m['id'] == servicio['movil_id'],
            orElse: () => <String, dynamic>{},
          );
          final movUsuario = movCacheEntry['usuario']?.toString() ?? '';
          final movNumStr =
              RegExp(r'\d+').firstMatch(movUsuario)?.group(0) ?? '';

          final estado = servicio['estado'];

          // --- MOTOR CENTINELA DE RETRASO ---
          final fechaCreacion = servicio['created_at'] != null
              ? DateTime.parse(servicio['created_at']).toUtc()
              : DateTime.now().toUtc();
          final minutosTranscurridos = DateTime.now()
              .toUtc()
              .difference(fechaCreacion)
              .inMinutes;

          // Alerta primaria: Si lleva más de 15 minutos y sigue buscando móvil, yendo al local, o esperando en el local
          bool alertaRetraso =
              (estado == 'pendiente' ||
                  estado == 'en_curso' ||
                  estado == 'en_ruta_origen' ||
                  estado == 'en_origen') &&
              minutosTranscurridos >= 15;

          // Alerta secundaria: Lógica estricta para cuando ya recogió el pedido y va al destino (30 min efectivos)
          if (estado == 'en_ruta_destino' && servicio['picked_up_at'] != null) {
            final startTime = DateTime.parse(servicio['picked_up_at']).toUtc();
            final elapsed = DateTime.now()
                .toUtc()
                .difference(startTime)
                .inMinutes;
            final extension = servicio['extension_minutes'] as int? ?? 0;
            if ((elapsed - extension) >= 30) alertaRetraso = true;
          }

          // Pintamos la tarjeta de rojo si el centinela se activa
          Color tileBackground = alertaRetraso
              ? const Color(0xfffff0f0)
              : Colors.white;
          Color tileBorder = alertaRetraso ? Colors.red[800]! : colorBase;

          // Si no hay retraso, respetamos los colores originales de tu código
          if (!alertaRetraso) {
            if (estado == 'problema') {
              tileBackground = const Color(0xfffff5f5);
              tileBorder = Colors.red[400]!;
            } else if (estado == 'cancelado') {
              tileBackground = const Color(0xfff7f7f7);
              tileBorder = Colors.grey[400]!;
            } else if (estado == 'finalizado_por_demora') {
              tileBackground = const Color(0xfffaf5ff);
              tileBorder = Colors.deepPurple[300]!;
            } else if (estado == 'caducado') {
              tileBackground = const Color(0xfff4e6fa);
              tileBorder = Colors.purple[800]!;
            } else if (estado == 'cotizacion') {
              tileBackground = const Color(0xfffff9f2);
              tileBorder = Colors.orange[400]!;
            } else if (estado == 'programado') {
              // <--- INYECCIÓN DE COLOR
              tileBackground = const Color(0xffe0f2f1); // Verde agua muy claro
              tileBorder = Colors.teal[600]!;
            }
          }

          bool alarmaCentral =
              servicio['chat_movil_central'] == true ||
              servicio['chat_cliente_central'] == true;

          return FadeSlideIn(
            key: ValueKey('monitor_${servicio['id']}'),
            child: Card(
              margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              elevation: 0,
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
                side: BorderSide(
                  color: alarmaCentral ? Colors.red[700]! : tileBorder,
                  width: alarmaCentral ? 2.5 : 1.2,
                ),
              ),
              color: tileBackground,
              child: InkWell(
                onTap: () {
                  final thisId = servicio['id'] as int;
                  _seleccionadoId.value =
                      _seleccionadoId.value == thisId ? null : thisId;
                },
                onLongPress: () => _abrirMenuGestion(context, servicio),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── FILA 1: chip estado · ruta · alarma/acción ──────────
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          _chipEstadoMonitor(estado, colorBase),
                          const SizedBox(width: 5),
                          if (servicio['es_vip'] == true)
                            const Text('👑 ', style: TextStyle(fontSize: 11)),
                          Expanded(
                            child: Text(
                              '${servicio["origen"]} ➔ ${servicio["destino"]}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: alarmaCentral ? Colors.red[800] : Colors.black87,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (alarmaCentral)
                            const Padding(
                              padding: EdgeInsets.only(left: 4),
                              child: Icon(Icons.mark_email_unread, color: Colors.red, size: 15),
                            ),
                          const SizedBox(width: 4),
                          Icon(icono, color: colorBase, size: 14),
                        ],
                      ),
                      const SizedBox(height: 3),
                      // ── FILA 2: tarifa · moto chip · tiempo relativo ─────────
                      Row(
                        children: [
                          Text(
                            estado == 'cotizacion'
                                ? 'PRECIO PEND.'
                                : _formatearMonedaCentral(servicio['tarifa']),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: (servicio['tarifa'] == null ||
                                      servicio['tarifa'] == 0 ||
                                      servicio['tarifa'] == 0.0)
                                  ? Colors.orange[700]
                                  : Colors.black87,
                            ),
                          ),
                          if (servicio['es_vip'] == true)
                            Text(' +VIP',
                                style: TextStyle(
                                    fontSize: 8,
                                    color: Colors.amber[800],
                                    fontWeight: FontWeight.bold)),
                          if (movNumStr.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: Colors.blueGrey[700],
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text(
                                '🏍 #$movNumStr',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                          ] else if (servicio['numero_cliente'] != null ||
                              servicio['numero_local'] != null) ...[
                            const SizedBox(width: 6),
                            Text(
                              [
                                if (servicio['numero_cliente'] != null)
                                  'C#${servicio["numero_cliente"]}',
                                if (servicio['numero_local'] != null)
                                  'L#${servicio["numero_local"]}',
                              ].join(' '),
                              style: TextStyle(
                                  fontSize: 9, color: Colors.blueGrey[400]),
                            ),
                          ],
                          const Spacer(),
                          Text(
                            _tiempoRelativo(fechaCreacion),
                            style: TextStyle(
                                fontSize: 9,
                                color: alertaRetraso
                                    ? Colors.red[700]
                                    : Colors.grey[500]),
                          ),
                        ],
                      ),
                      // ── FILA 3: sub-estado en curso ──────────────────────────
                      if (['en_ruta_origen', 'en_origen', 'en_ruta_destino']
                          .contains(estado)) ...[
                        const SizedBox(height: 2),
                        Builder(builder: (context) {
                          if (estado == 'en_ruta_origen') {
                            return const Text('🏃 En camino a recogida...',
                                style: TextStyle(
                                    color: Colors.blue,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold));
                          } else if (estado == 'en_origen') {
                            return const Text('🛒 En el local — reloj pausado',
                                style: TextStyle(
                                    color: Colors.orange,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold));
                          } else if (estado == 'en_ruta_destino' &&
                              servicio['picked_up_at'] != null) {
                            final startTime =
                                DateTime.parse(servicio['picked_up_at']).toUtc();
                            final efectivos = DateTime.now()
                                    .toUtc()
                                    .difference(startTime)
                                    .inMinutes -
                                (servicio['extension_minutes'] as int? ?? 0);
                            return Text(
                              efectivos >= 30
                                  ? '⏳ Retrasado en entrega: ${efectivos}min'
                                  : '🛵 En entrega: ${efectivos}min',
                              style: TextStyle(
                                color: efectivos >= 30
                                    ? Colors.orange[900]
                                    : Colors.black54,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            );
                          }
                          return const SizedBox.shrink();
                        }),
                      ],
                      // ── FILA 4: badges opcionales (wrap) ─────────────────────
                      if (alertaRetraso ||
                          (servicio['creador'] != null &&
                              servicio['creador'] != 'Central') ||
                          (estado == 'programado' &&
                              servicio['liberacion_at'] != null) ||
                          servicio['observacion'] != null) ...[
                        const SizedBox(height: 3),
                        Wrap(
                          spacing: 4,
                          runSpacing: 2,
                          children: [
                            if (alertaRetraso)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 5, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.red[900],
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.warning_amber_rounded,
                                          color: Colors.white, size: 10),
                                      const SizedBox(width: 3),
                                      Text(
                                        estado == 'en_ruta_destino'
                                            ? 'RETRASO ENTREGA'
                                            : 'RETRASO ${minutosTranscurridos}MIN',
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 8,
                                            fontWeight: FontWeight.bold),
                                      ),
                                    ]),
                              ),
                            if (servicio['creador'] != null &&
                                servicio['creador'] != 'Central')
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 5, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.yellowAccent[700],
                                  borderRadius: BorderRadius.circular(3),
                                  border:
                                      Border.all(color: Colors.black45, width: 0.5),
                                ),
                                child: Text(
                                  '🏢 ${servicio["creador"].toString().toUpperCase()}',
                                  style: const TextStyle(
                                      color: Colors.black,
                                      fontSize: 8,
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
                            if (estado == 'programado' &&
                                servicio['liberacion_at'] != null)
                              Builder(builder: (context) {
                                final lib = DateTime.parse(
                                        servicio['liberacion_at'])
                                    .toLocal();
                                final diff =
                                    lib.difference(DateTime.now()).inMinutes;
                                return Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 5, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.teal[100],
                                    borderRadius: BorderRadius.circular(3),
                                    border: Border.all(color: Colors.teal[300]!),
                                  ),
                                  child: Text(
                                    diff > 0
                                        ? '⏰ Disparo en ${diff}min'
                                        : '⏰ Liberando...',
                                    style: TextStyle(
                                        color: Colors.teal[900],
                                        fontSize: 8,
                                        fontWeight: FontWeight.bold),
                                  ),
                                );
                              }),
                            if (servicio['observacion'] != null)
                              ConstrainedBox(
                                constraints:
                                    const BoxConstraints(maxWidth: 240),
                                child: Text(
                                  '📝 ${servicio["observacion"]}',
                                  style: TextStyle(
                                      color: Colors.indigo[900],
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                        ),
                      ],

                      // ── FILA 5: acciones rápidas (expandible al seleccionar) ──
                      ValueListenableBuilder<int?>(
                        valueListenable: _seleccionadoId,
                        builder: (context, selId, _) {
                          final seleccionado = selId == servicio['id'];
                          final btns = seleccionado
                              ? _botonesAccion(context, servicio, estado)
                              : <Widget>[];
                          return AnimatedSize(
                            duration: const Duration(milliseconds: 180),
                            curve: Curves.easeInOut,
                            child: seleccionado && btns.isNotEmpty
                                ? Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Wrap(
                                      spacing: 5,
                                      runSpacing: 5,
                                      children: btns,
                                    ),
                                  )
                                : const SizedBox.shrink(),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );  // FadeSlideIn
        }),
      ],
    );
  }

  Future<void> _archivarServiciosTerminados() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text(
          '🧹 LIMPIAR RADAR',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: const Text(
          '¿Archivar todos los servicios finalizados, caducados y cancelados?\n\nDesaparecerán de esta pantalla para limpiar tu visión, pero seguirán contando en tu corte financiero de caja.',
          style: TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCELAR', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.black),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'LIMPIAR TODO',
              style: TextStyle(
                color: Color(0xff3AF500),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmar == true) {
      try {
        // 1. El misil a la base de datos (Exclusivo para terminales)
        await Supabase.instance.client
            .from('servicios')
            .update({'archivado': true})
            .inFilter('estado', [
              'finalizado',
              'cancelado',
              'finalizado_por_demora',
              'finalizado_con_problema',
              'caducado', // El caducado es un cancelado por el sistema
            ])
            .eq('archivado', false);

        if (mounted) {
          // Reinicio del canal — ahora vía el vigilante de conexión, sin
          // parpadeo (antes esto reemplazaba el Stream directo y el
          // StreamBuilder mostraba el loading spinner por un instante).
          _construirStreams();

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Radar limpio. Servicios purgados con éxito.'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error al archivar: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }


  Widget _construirPanelControl() {
    return Container(
      margin: const EdgeInsets.all(8.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
            ),
            child: const Text(
              'CONTROL OPERATIVO',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _streamServiciosMonitor,
              builder: (context, snapServicios) {
                // Servicios activos en campo (para la sección "En Servicio")
                final serviciosEnCurso = (snapServicios.data ?? [])
                    .where(
                      (s) => [
                        'en_ruta_origen',
                        'en_origen',
                        'en_ruta_destino',
                        'problema',
                      ].contains(s['estado']),
                    )
                    .toList();

                return StreamBuilder<List<Map<String, dynamic>>>(
                  stream: _streamUsuariosMoviles,
                  // initialData evita parpadeo: siempre hay datos desde el inicio
                  initialData: _movilesCache,
                  builder: (context, snapshot) {
                    // Interceptor táctico para formatear la vista
                    final moviles = (snapshot.data ?? _movilesCache).map((m) {
                      final map = Map<String, dynamic>.from(m);
                      map['nombre'] = _formatearNombreCentral(map);
                      return map;
                    }).toList();

                    // Moviles con servicio activo
                    final movilesEnServicioIds = serviciosEnCurso
                        .map((s) => s['movil_id'])
                        .toSet();
                    final movilesEnServicio = moviles
                        .where(
                          (m) =>
                              movilesEnServicioIds.contains(m['id']) &&
                              m['en_linea'] == true,
                        )
                        .toList();

                    // --- MOTOR DE ORDENAMIENTO TÁCTICO (VIP > HORA) ---
                    int ordenarPorPrioridadYHora(
                      Map<String, dynamic> a,
                      Map<String, dynamic> b,
                    ) {
                      final ticketA = a['ticket_prioridad'] == true ? 1 : 0;
                      final ticketB = b['ticket_prioridad'] == true ? 1 : 0;
                      if (ticketA != ticketB) {
                        return ticketB.compareTo(ticketA); // El que tiene ticket va primero
                      }

                      final horaA = a['ingreso_fila'] != null
                          ? DateTime.parse(a['ingreso_fila'])
                          : DateTime.fromMillisecondsSinceEpoch(0);
                      final horaB = b['ingreso_fila'] != null
                          ? DateTime.parse(b['ingreso_fila'])
                          : DateTime.fromMillisecondsSinceEpoch(0);
                      return horaA.compareTo(horaB);
                    }

                    final filaExpuente = moviles
                        .where(
                          (m) =>
                              m['en_linea'] == true &&
                              m['paradero_actual'] == 'EXPUENTE' &&
                              m['ingreso_fila'] != null &&
                              m['suspendido'] != true,
                        )
                        .toList();
                    filaExpuente.sort(ordenarPorPrioridadYHora);

                    final filaMemos = moviles
                        .where(
                          (m) =>
                              m['en_linea'] == true &&
                              m['paradero_actual'] == 'MEMOS' &&
                              m['ingreso_fila'] != null &&
                              m['suspendido'] != true,
                        )
                        .toList();
                    filaMemos.sort(ordenarPorPrioridadYHora);

                    final filaNocturno = moviles
                        .where(
                          (m) =>
                              m['en_linea'] == true &&
                              m['paradero_actual'] == 'NOCTURNO' &&
                              m['ingreso_fila'] != null &&
                              m['suspendido'] != true,
                        )
                        .toList();
                    filaNocturno.sort(ordenarPorPrioridadYHora);

                    final sinFila = moviles
                        .where(
                          (m) =>
                              m['en_linea'] == true &&
                              m['paradero_actual'] == null &&
                              m['suspendido'] != true,
                        )
                        .toList();
                    final desconectados = moviles
                        .where(
                          (m) =>
                              m['en_linea'] != true &&
                              m['suspendido'] != true &&
                              m['activo'] == true,
                        )
                        .toList();
                    final suspendidos = moviles
                        .where((m) => m['suspendido'] == true)
                        .toList();

                    // ── MOTOS FN FARMANORTE ─────────────────────────────────
                    final motosFn = moviles
                        .where(
                          (m) =>
                              m['tiene_fn'] == true &&
                              m['en_linea'] == true &&
                              m['suspendido'] != true,
                        )
                        .toList();

                    return ListView(
                      children: [
                        // ── SECCIÓN FARMANORTE ──────────────────────────────
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          color: Colors.indigo[900],
                          child: Row(
                            children: [
                              const Icon(Icons.local_pharmacy,
                                  color: Colors.white, size: 13),
                              const SizedBox(width: 6),
                              const Expanded(
                                child: Text(
                                  'FARMANORTE',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                              Container(
                                margin: const EdgeInsets.only(right: 6),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: motosFn.isNotEmpty
                                      ? Colors.white24
                                      : Colors.white10,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '${motosFn.length}',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (motosFn.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(8),
                            child: Text(
                              'Sin motos FN en línea',
                              style: TextStyle(color: Colors.grey, fontSize: 11),
                            ),
                          )
                        else
                          ...motosFn.map((m) => FadeSlideIn(
                                key: ValueKey('fn_${m['id']}'),
                                child: ListTile(
                                  dense: true,
                                  leading: Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      CircleAvatar(
                                        radius: 12,
                                        backgroundColor: Colors.indigo[900],
                                        child: Text(
                                          _extraerNumeroAvatar(m),
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      Positioned(
                                        right: -4,
                                        bottom: -3,
                                        child: Container(
                                          width: 12,
                                          height: 12,
                                          decoration: BoxDecoration(
                                            color: Colors.indigo[700],
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                                color: Colors.white, width: 1),
                                          ),
                                          child: const Icon(
                                              Icons.local_pharmacy,
                                              size: 7,
                                              color: Colors.white),
                                        ),
                                      ),
                                    ],
                                  ),
                                  title: Text(
                                    m['nombre'].toString().toUpperCase(),
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                      color: Colors.indigo[900],
                                    ),
                                  ),
                                  subtitle: Text(
                                    '${m['rango_movil'] ?? 'NOVATO'} · ${m['fn_ignorados_hoy'] ?? 0} ign. hoy',
                                    style: const TextStyle(
                                        fontSize: 10, color: Colors.black54),
                                  ),
                                  onTap: () =>
                                      _abrirMenuAccionesMovil(context, m),
                                ),
                              )),

                        const Divider(height: 4, color: Colors.transparent),
                        // ── FIN SECCIÓN FN ──────────────────────────────────

                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          color: Colors.blue[50],
                          child: Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  '📍 PARADERO 1 (Expuente)',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 220),
                                child: Container(
                                  key: ValueKey('exp_cnt_${filaExpuente.length}'),
                                  margin: const EdgeInsets.only(right: 6),
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: filaExpuente.isNotEmpty ? Colors.blue[800] : Colors.blue[200],
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    '${filaExpuente.length}',
                                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ),
                              if (filaExpuente.isNotEmpty)
                                TextButton.icon(
                                  onPressed: () => _vaciarParadero(
                                    'Expuente',
                                    filaExpuente,
                                  ),
                                  icon: const Icon(
                                    Icons.delete_sweep,
                                    size: 14,
                                    color: Colors.red,
                                  ),
                                  label: const Text(
                                    'Vaciar',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.red,
                                    ),
                                  ),
                                  style: TextButton.styleFrom(
                                    padding: EdgeInsets.zero,
                                    minimumSize: const Size(40, 24),
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (filaExpuente.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(8),
                            child: Text(
                              'Sin móviles en cola',
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 11,
                              ),
                            ),
                          )
                        else
                          ...filaExpuente.asMap().entries.map((e) {
                            int idx = e.key + 1;
                            var m = e.value;
                            return FadeSlideIn(
                              key: ValueKey('exp_${m['id']}'),
                              child: ListTile(
                                dense: true,
                                leading: _paraderoMovilLeading(m, Colors.blue[800]!),
                                title: Text(
                                  '#$idx. ${m['nombre'].toString().toUpperCase()}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                                subtitle: Row(
                                  children: [
                                    if (m['ticket_prioridad'] == true) ...[
                                      const Icon(
                                        Icons.local_activity,
                                        color: Colors.amber,
                                        size: 12,
                                      ),
                                      const SizedBox(width: 4),
                                    ],
                                    Text(
                                      '${m['rango_movil'] ?? 'NOVATO'} | ${_formatCalificacion(m['puntuacion'])}',
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: Colors.black54,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                                trailing: _movilTrailing(m),
                                onTap: () => _abrirMenuAccionesMovil(context, m),
                              ),
                            );
                          }),

                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          color: Colors.purple[50],
                          child: Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  '📍 PARADERO 2 (Memos)',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.purple,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 220),
                                child: Container(
                                  key: ValueKey('mem_cnt_${filaMemos.length}'),
                                  margin: const EdgeInsets.only(right: 6),
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: filaMemos.isNotEmpty ? Colors.purple[800] : Colors.purple[200],
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    '${filaMemos.length}',
                                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ),
                              if (filaMemos.isNotEmpty)
                                TextButton.icon(
                                  onPressed: () =>
                                      _vaciarParadero('Memos', filaMemos),
                                  icon: const Icon(
                                    Icons.delete_sweep,
                                    size: 14,
                                    color: Colors.red,
                                  ),
                                  label: const Text(
                                    'Vaciar',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.red,
                                    ),
                                  ),
                                  style: TextButton.styleFrom(
                                    padding: EdgeInsets.zero,
                                    minimumSize: const Size(40, 24),
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (filaMemos.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(8),
                            child: Text(
                              'Sin móviles en cola',
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 11,
                              ),
                            ),
                          )
                        else
                          ...filaMemos.asMap().entries.map((e) {
                            int idx = e.key + 1;
                            var m = e.value;
                            return FadeSlideIn(
                              key: ValueKey('memos_${m['id']}'),
                              child: ListTile(
                                dense: true,
                                leading: _paraderoMovilLeading(m, Colors.purple[800]!),
                                title: Text(
                                  '#$idx. ${m['nombre'].toString().toUpperCase()}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                                subtitle: Row(
                                  children: [
                                    if (m['ticket_prioridad'] == true) ...[
                                      const Icon(
                                        Icons.local_activity,
                                        color: Colors.amber,
                                        size: 12,
                                      ),
                                      const SizedBox(width: 4),
                                    ],
                                    Text(
                                      '${m['rango_movil'] ?? 'NOVATO'} | ${_formatCalificacion(m['puntuacion'])}',
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: Colors.black54,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                                trailing: _movilTrailing(m),
                                onTap: () => _abrirMenuAccionesMovil(context, m),
                              ),
                            );
                          }),

                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          color: Colors.indigo[900],
                          child: Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  '🌙 PARADERO NOCTURNO',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 220),
                                child: Container(
                                  key: ValueKey('noc_cnt_${filaNocturno.length}'),
                                  margin: const EdgeInsets.only(right: 6),
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: filaNocturno.isNotEmpty ? Colors.indigo[300] : Colors.indigo[700],
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    '${filaNocturno.length}',
                                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ),
                              if (filaNocturno.isNotEmpty)
                                TextButton.icon(
                                  onPressed: () => _vaciarParadero(
                                    'Nocturno',
                                    filaNocturno,
                                  ),
                                  icon: const Icon(
                                    Icons.delete_sweep,
                                    size: 14,
                                    color: Colors.orangeAccent,
                                  ),
                                  label: const Text(
                                    'Vaciar',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.orangeAccent,
                                    ),
                                  ),
                                  style: TextButton.styleFrom(
                                    padding: EdgeInsets.zero,
                                    minimumSize: const Size(40, 24),
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (filaNocturno.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(8),
                            child: Text(
                              'Sin móviles en cola',
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 11,
                              ),
                            ),
                          )
                        else
                          ...filaNocturno.asMap().entries.map((e) {
                            int idx = e.key + 1;
                            var m = e.value;
                            return FadeSlideIn(
                              key: ValueKey('noc_${m['id']}'),
                              child: ListTile(
                                dense: true,
                                leading: _paraderoMovilLeading(m, Colors.indigo[400]!),
                              title: Text(
                                '#$idx. ${m['nombre'].toString().toUpperCase()}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                              subtitle: Row(
                                children: [
                                  if (m['ticket_prioridad'] == true) ...[
                                    const Icon(
                                      Icons.local_activity,
                                      color: Colors.amber,
                                      size: 12,
                                    ),
                                    const SizedBox(width: 4),
                                  ],
                                  Text(
                                    '${m['rango_movil'] ?? 'NOVATO'} | ${_formatCalificacion(m['puntuacion'])}',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: Colors.black54,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                              trailing: _movilTrailing(m),
                              onTap: () => _abrirMenuAccionesMovil(context, m),
                            ),  // ListTile
                          );    // FadeSlideIn
                          }),

                        // =====================================================
                        // SECCIÓN: EN SERVICIO
                        // =====================================================
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                          color: Colors.orange[800],
                          child: Text(
                            '🚴 EN SERVICIO  (${movilesEnServicio.length})',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              fontSize: 11,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        if (movilesEnServicio.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            child: Text(
                              'Ningún móvil en campo ahora',
                              style: TextStyle(color: Colors.grey, fontSize: 11),
                            ),
                          )
                        else
                          ...movilesEnServicio.map((movil) {
                            final svcsDelMovil = serviciosEnCurso
                                .where((s) => s['movil_id'] == movil['id'])
                                .toList();
                            return FadeSlideIn(
                              key: ValueKey('svc_${movil['id']}'),
                              child: Material(
                              color: Colors.orange[50],
                              child: InkWell(
                                onTap: () => _abrirMenuAccionesMovil(context, movil),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // Avatar
                                      CircleAvatar(
                                        radius: 13,
                                        backgroundColor: Colors.orange[700],
                                        child: Text(
                                          _extraerNumeroAvatar(movil),
                                          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      // Info principal + servicios
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              movil['nombre'].toString().toUpperCase(),
                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                            ),
                                            const SizedBox(height: 1),
                                            Text(
                                              '${movil['rango_movil'] ?? 'NOVATO'} · ${_formatCalificacion(movil['puntuacion'])}',
                                              style: const TextStyle(fontSize: 10, color: Colors.black45),
                                            ),
                                            const SizedBox(height: 4),
                                            // Servicios compactos: uno por fila
                                            ...svcsDelMovil.map((s) {
                                              final String ico;
                                              final String fase;
                                              switch (s['estado']) {
                                                case 'en_ruta_origen':  ico = '🔵'; fase = 'Ruta origen'; break;
                                                case 'en_origen':       ico = '📍'; fase = 'En origen'; break;
                                                case 'en_ruta_destino': ico = '🚀'; fase = 'Ruta destino'; break;
                                                case 'problema':        ico = '🚨'; fase = 'Problema'; break;
                                                default: ico = '●'; fase = s['estado'] ?? '';
                                              }
                                              final String origen = s['origen'] ?? '—';
                                              final String destino = s['destino'] ?? '';
                                              return Container(
                                                margin: const EdgeInsets.only(top: 3),
                                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                                decoration: BoxDecoration(
                                                  color: Colors.white,
                                                  borderRadius: BorderRadius.circular(5),
                                                  border: Border.all(color: Colors.orange[200]!),
                                                ),
                                                child: Row(
                                                  children: [
                                                    Text('$ico ', style: const TextStyle(fontSize: 11)),
                                                    Expanded(
                                                      child: Text(
                                                        '#${s['id']} $fase · $origen${destino.isNotEmpty ? ' → $destino' : ''}',
                                                        style: const TextStyle(fontSize: 10, color: Colors.black87),
                                                        overflow: TextOverflow.ellipsis,
                                                        maxLines: 1,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              );
                                            }),
                                          ],
                                        ),
                                      ),
                                      // Más opciones
                                      const Icon(
                                        Icons.more_vert,
                                        color: Colors.black38,
                                        size: 18,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              ),  // Material
                            );    // FadeSlideIn
                          }),

                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                          color: Colors.green[700],
                          child: Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  '🏍️ LIBRE / SIN PARADERO',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 220),
                                child: Container(
                                  key: ValueKey('libre_cnt_${sinFila.length}'),
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: sinFila.isNotEmpty ? Colors.green[900] : Colors.green[600],
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    '${sinFila.length}',
                                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (sinFila.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(8),
                            child: Text(
                              'Ninguno rodando libre',
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 11,
                              ),
                            ),
                          )
                        else
                          ...sinFila
                              .map(
                                (m) => ListTile(
                                  dense: true,
                                  leading: _paraderoMovilLeading(m, Colors.green[600]!),
                                  title: Text(
                                    m['nombre'].toString().toUpperCase(),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  subtitle: Text(
                                    '${m['rango_movil'] ?? 'NOVATO'} | ${_formatCalificacion(m['puntuacion'])}',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: Colors.black54,
                                    ),
                                  ),
                                  trailing: _movilTrailing(m),
                                  onTap: () =>
                                      _abrirMenuAccionesMovil(context, m),
                                ),
                              )
                              ,

                        // =====================================================
                        // SUSPENDIDOS — antes que desconectados
                        // =====================================================
                        if (suspendidos.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            color: Colors.red[900],
                            child: Row(
                              children: [
                                const Expanded(
                                  child: Text(
                                    '🛑 SUSPENDIDOS',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.red[700],
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    '${suspendidos.length}',
                                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ...suspendidos.map((movil) {
                          return Material(
                            color: Colors.transparent,
                            child: ListTile(
                              dense: true,
                              leading: _paraderoMovilLeading(movil, Colors.red[800]!),
                              title: Text(
                                movil['nombre'] ?? 'Desconocido',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  color: Colors.red[800],
                                ),
                              ),
                              subtitle: Text(
                                '${movil['rango_movil'] ?? 'NOVATO'} | ${_formatCalificacion(movil['puntuacion'])}',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.red[400],
                                ),
                              ),
                              trailing: _movilTrailing(movil),
                              onTap: () =>
                                  _abrirMenuAccionesMovil(context, movil),
                            ),
                          );
                        }),

                        // =====================================================
                        // DESCONECTADOS — desplegable
                        // =====================================================
                        InkWell(
                          onTap: () => setState(
                            () => _desconectadosExpandidos = !_desconectadosExpandidos,
                          ),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            color: Colors.grey[200],
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '⚫ DESCONECTADOS (${desconectados.length})',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black54,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                                Icon(
                                  _desconectadosExpandidos
                                      ? Icons.keyboard_arrow_up
                                      : Icons.keyboard_arrow_down,
                                  size: 16,
                                  color: Colors.black38,
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (_desconectadosExpandidos)
                          if (desconectados.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(8),
                              child: Text(
                                'Nadie desconectado',
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 11,
                                ),
                              ),
                            )
                          else
                            ...desconectados.map((movil) {
                            // Solo las últimas 24h — una falla de hace
                            // meses no debería perseguir a un moto para
                            // siempre, sobre todo si ya mejoró desde
                            // entonces. Filtrado server-side: más rápido
                            // que traer todo el historial y descartar
                            // el resto en el cliente.
                            final hace24h = DateTime.now()
                                .toUtc()
                                .subtract(const Duration(hours: 24))
                                .toIso8601String();
                            return FutureBuilder<List<Map<String, dynamic>>>(
                              future: Supabase.instance.client
                                  .from('servicios')
                                  .select(
                                    'id, origen, destino, estado, observacion, created_at',
                                  )
                                  .eq('movil_id', movil['id'])
                                  .not('estado', 'eq', 'pendiente')
                                  .not('estado', 'eq', 'en_curso')
                                  .not('estado', 'eq', 'problema')
                                  .gte('created_at', hace24h),
                              builder: (context, historySnapshot) {
                                final historialReciente =
                                    historySnapshot.data ?? [];
                                final fallasRecientes = historialReciente
                                    .where(
                                      (f) =>
                                          f['estado'] ==
                                              'finalizado_por_demora' ||
                                          f['estado'] ==
                                              'finalizado_con_problema' ||
                                          (f['observacion'] != null &&
                                              f['observacion']
                                                  .toString()
                                                  .contains(
                                                    '[MARCA DE FALLA]',
                                                  )),
                                    )
                                    .length;
                                return Material(
                                  color: Colors.transparent,
                                  child: ListTile(
                                    dense: true,
                                    leading: _paraderoMovilLeading(movil, Colors.grey[500]!),
                                    title: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            movil['nombre'] ?? 'Desconocido',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                              color: Colors.black87,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        if (fallasRecientes > 0)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 4,
                                              vertical: 1,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.red[50],
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                              border: Border.all(
                                                color: Colors.red[300]!,
                                              ),
                                            ),
                                            child: Text(
                                              // Singular si fue 1, cuenta
                                              // solo si pasó más de una
                                              // vez en las últimas 24h.
                                              fallasRecientes == 1
                                                  ? 'FALLA (24h)'
                                                  : '$fallasRecientes FALLAS (24h)',
                                              style: TextStyle(
                                                color: Colors.red[900],
                                                fontSize: 9,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                    subtitle: Text(
                                      '${movil['rango_movil'] ?? 'NOVATO'} | ${_formatCalificacion(movil['puntuacion'])}',
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: Colors.black54,
                                      ),
                                    ),
                                    trailing: _movilTrailing(movil),
                                    onTap: () => _abrirMenuAccionesMovil(
                                      context,
                                      movil,
                                    ),
                                  ),
                                );
                              },
                            );
                          }),
                      ],
                    );
                  },
                ); // cierre StreamBuilder _streamUsuariosMoviles
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _construirPanelMapa() {
    return Container(
      margin: const EdgeInsets.all(8.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: const BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'RADAR DE MÓVILES',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
                Row(
                  children: [
                    Text(
                      _radarActivo ? 'ON' : 'OFF',
                      style: TextStyle(
                        color: _radarActivo
                            ? const Color(0xff3AF500)
                            : Colors.redAccent,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                    Switch(
                      value: _radarActivo,
                      onChanged: (val) => setState(() => _radarActivo = val),
                      activeThumbColor: const Color(0xff3AF500),
                      activeTrackColor: Colors.green[900],
                      inactiveThumbColor: Colors.redAccent,
                      inactiveTrackColor: Colors.red[900],
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh_rounded, color: Colors.white70, size: 18),
                      tooltip: 'Actualizar radar',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                      onPressed: () async {
                        await _preCargarDatosIniciales();
                        _construirStreams();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('🔄 Radar actualizado.'),
                              duration: Duration(seconds: 1),
                              backgroundColor: Colors.black87,
                            ),
                          );
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: !_radarActivo
                ? Container(
                    width: double.infinity,
                    decoration: const BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.vertical(
                        bottom: Radius.circular(8),
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.radar, size: 60, color: Colors.grey[800]),
                        const SizedBox(height: 16),
                        const Text(
                          'RADAR DESACTIVADO',
                          style: TextStyle(
                            color: Colors.white54,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 2,
                          ),
                        ),
                      ],
                    ),
                  )
                : StreamBuilder<List<Map<String, dynamic>>>(
                    stream: _streamUsuariosMoviles,
                    builder: (context, snapMoviles) {
                      List<Marker> marcadores = [];
                      marcadores.add(
                        Marker(
                          point: const LatLng(7.863439, -72.475760),
                          width: 40,
                          height: 40,
                          child: const Icon(
                            Icons.location_on,
                            color: Colors.blue,
                            size: 40,
                          ),
                        ),
                      );
                      marcadores.add(
                        Marker(
                          point: const LatLng(7.863283, -72.476152),
                          width: 40,
                          height: 40,
                          child: const Icon(
                            Icons.location_on,
                            color: Colors.indigo,
                            size: 40,
                          ),
                        ),
                      );
                      marcadores.add(
                        Marker(
                          point: const LatLng(7.863976, -72.479256),
                          width: 40,
                          height: 40,
                          child: const Icon(
                            Icons.location_on,
                            color: Colors.purple,
                            size: 40,
                          ),
                        ),
                      );

                      if (snapMoviles.hasData) {
                        for (var m in snapMoviles.data!) {
                          if (m['en_linea'] == true &&
                              m['latitud'] != null &&
                              m['longitud'] != null &&
                              m['suspendido'] != true) {
                            marcadores.add(
                              Marker(
                                point: LatLng(m['latitud'], m['longitud']),
                                width: 60,
                                height: 60,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: const BoxDecoration(
                                        color: Colors.black87,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Text(
                                        _extraerNumeroAvatar(m),
                                        style: const TextStyle(
                                          color: Color(0xff3AF500),
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    const Icon(
                                      Icons.motorcycle,
                                      color: Colors.green,
                                      size: 24,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }
                        }
                      }
                      return ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(8),
                        ),
                        child: FlutterMap(
                          options: const MapOptions(
                            initialCenter: LatLng(7.8634, -72.4757),
                            initialZoom: 15.5,
                          ),
                          children: [
                            TileLayer(
                              urlTemplate:
                                  'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                              userAgentPackageName: 'com.serviexpress.express',
                            ),
                            MarkerLayer(markers: marcadores),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _construirPanelMonitor() {
    return Container(
      margin: const EdgeInsets.all(8.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: const BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'MONITOR DE SERVICIOS',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                    fontSize: 12,
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.filter_list, size: 16, color: Colors.white70),
                      tooltip: 'Filtrar Monitor',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      onPressed: () => _abrirMenuFiltroMonitor(context),
                    ),
                    IconButton(
                      icon: const Icon(Icons.history, size: 16, color: Colors.white70),
                      tooltip: 'Historial Completo',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      onPressed: () => _abrirHistorialCompletoCentral(context),
                    ),
                    IconButton(
                      icon: const Icon(Icons.cleaning_services_rounded, size: 16, color: Colors.redAccent),
                      tooltip: 'Limpiar finalizados',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      onPressed: _archivarServiciosTerminados,
                    ),
                  ],
                ),
              ],
            ),
          ),
          // ── BARRA DE BÚSQUEDA ──────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 2),
            child: TextField(
              controller: _busquedaCtrl,
              onChanged: (val) {
                _busquedaTexto = val.toLowerCase().trim();
                _filtroVersion.value++;
              },
              style: const TextStyle(fontSize: 12),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Buscar por ruta, cliente, local, móvil...',
                hintStyle: TextStyle(fontSize: 11, color: Colors.grey[400]),
                prefixIcon: const Icon(Icons.search, size: 16),
                suffixIcon: _busquedaTexto.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close, size: 14),
                        onPressed: () {
                          _busquedaCtrl.clear();
                          _busquedaTexto = '';
                          _filtroVersion.value++;
                        },
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      )
                    : null,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: Colors.black54),
                ),
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _streamServiciosMonitor,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(color: Colors.black),
                  );
                }
                final todos = snapshot.data ?? [];

                final problemas = todos
                    .where((s) => s['estado'] == 'problema')
                    .toList();
                final cotizaciones = todos
                    .where((s) => s['estado'] == 'cotizacion')
                    .toList();
                final cotizadas = todos
                    .where((s) => s['estado'] == 'cotizada')
                    .toList();
                final cotizacionesAprobadas = todos
                    .where((s) => s['estado'] == 'cotizacion_aprobada')
                    .toList();
                final finalizadosDemora = todos
                    .where((s) => s['estado'] == 'finalizado_por_demora')
                    .toList();
                final libres = todos
                    .where((s) => s['estado'] == 'pendiente')
                    .toList();
                // ---> INYECCIÓN: EXTRAER LOS PROGRAMADOS <---
                final programados = todos
                    .where((s) => s['estado'] == 'programado')
                    .toList();
                final enCurso = todos
                    .where(
                      (s) => [
                        'en_ruta_origen',
                        'en_origen',
                        'en_ruta_destino',
                      ].contains(s['estado']),
                    )
                    .toList();
                final finalizadosProblema = todos
                    .where((s) => s['estado'] == 'finalizado_con_problema')
                    .toList();
                final finalizados = todos
                    .where((s) => s['estado'] == 'finalizado')
                    .toList();
                final cancelados = todos
                    .where((s) => s['estado'] == 'cancelado')
                    .toList();
                final caducados = todos
                    .where((s) => s['estado'] == 'caducado')
                    .toList();

                // Sonidos de estado manejados por radar_central_bg channel

                // ValueListenableBuilder reacciona al filtro/búsqueda sin
                // reconstruir el StreamBuilder completo (evita parpadeo).
                return ValueListenableBuilder<int>(
                  valueListenable: _filtroVersion,
                  builder: (context, _, __) {
                    // ── FILTRO POR BÚSQUEDA ────────────────────────────────
                    bool _matchBusqueda(Map<String, dynamic> s) {
                      if (_busquedaTexto.isEmpty) return true;
                      final q = _busquedaTexto;
                      if ((s['origen'] ?? '').toString().toLowerCase().contains(q)) return true;
                      if ((s['destino'] ?? '').toString().toLowerCase().contains(q)) return true;
                      if ((s['numero_cliente'] ?? '').toString().contains(q)) return true;
                      if ((s['numero_local'] ?? '').toString().contains(q)) return true;
                      if ((s['numero_movil'] ?? '').toString().contains(q)) return true;
                      if ((s['observacion'] ?? '').toString().toLowerCase().contains(q)) return true;
                      // buscar por #moto (ej: "5" o "#5")
                      final movEntry = _movilesCache.firstWhere(
                        (m) => m['id'] == s['movil_id'], orElse: () => {});
                      if (movEntry.isNotEmpty) {
                        final usuario = movEntry['usuario']?.toString() ?? '';
                        if (usuario.toLowerCase().contains(q)) return true;
                      }
                      return false;
                    }

                    // KPIs desde todos (sin filtro de búsqueda)
                    final kpiPendientes = todos.where((s) => s['estado'] == 'pendiente').length;
                    final kpiEnCurso = todos.where((s) => ['en_ruta_origen','en_origen','en_ruta_destino'].contains(s['estado'])).length;
                    final kpiProblemas = todos.where((s) => s['estado'] == 'problema').length;
                    final hoy = DateTime.now();
                    final todosHoy = todos.where((s) {
                      if (s['created_at'] == null) return false;
                      final d = DateTime.parse(s['created_at']).toLocal();
                      return d.year == hoy.year && d.month == hoy.month && d.day == hoy.day;
                    }).toList();
                    final kpiHoy = todosHoy.length;
                    final kpiFact = todosHoy
                        .where((s) => ['finalizado', 'finalizado_con_problema', 'finalizado_por_demora'].contains(s['estado']))
                        .fold<double>(0, (acc, s) => acc + ((s['tarifa'] as num?)?.toDouble() ?? 0));
                    final segsDesde = DateTime.now().difference(_ultimaActualizacion).inSeconds;
                    final actLabel = segsDesde < 5 ? 'ahora' : 'hace ${segsDesde}s';

                    // Listas filtradas por búsqueda
                    List<Map<String, dynamic>> _filtrar(List<Map<String, dynamic>> lista) =>
                        lista.where(_matchBusqueda).toList();

                    return Column(
                      children: [
                        // ── KPIs ────────────────────────────────────────────
                        Container(
                          color: const Color(0xFFF5F5F5),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                          child: Row(
                            children: [
                              _kpiChip('LIBRE', kpiPendientes, const Color(0xff3AF500)),
                              const SizedBox(width: 5),
                              _kpiChip('CURSO', kpiEnCurso, Colors.amber[700]!),
                              const SizedBox(width: 5),
                              if (kpiProblemas > 0) ...[
                                _kpiChip('PROB', kpiProblemas, Colors.red[700]!),
                                const SizedBox(width: 5),
                              ],
                              _kpiChip('HOY', kpiHoy, Colors.blueGrey[600]!),
                              const Spacer(),
                              if (kpiFact > 0)
                                Text(
                                  _formatearMonedaCentral(kpiFact),
                                  style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black54),
                                ),
                              const SizedBox(width: 6),
                              Text(
                                '● $actLabel',
                                style: TextStyle(
                                    fontSize: 8,
                                    color: segsDesde < 10
                                        ? Colors.green[600]
                                        : Colors.orange[700]),
                              ),
                            ],
                          ),
                        ),
                        // ── LISTA ────────────────────────────────────────────
                        Expanded(
                          child: ListView(
                            padding: const EdgeInsets.only(bottom: 10),
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              _construirBloqueServicios(
                                context,
                                '⚠️ REPORTES DE PROBLEMA',
                                _filtrar(problemas),
                                Colors.red[700]!,
                                Icons.warning_rounded,
                                visible: !_seccionesOcultasMonitor.contains('problemas'),
                              ),
                              _construirBloqueServicios(
                                context,
                                '❓ COTIZACIONES PENDIENTES',
                                _filtrar(cotizaciones),
                                Colors.orange[700]!,
                                Icons.calculate_outlined,
                                visible: !_seccionesOcultasMonitor.contains('cotizaciones'),
                              ),
                              _construirBloqueServicios(
                                context,
                                '✉️ COTIZACIONES ENVIADAS',
                                _filtrar(cotizadas),
                                Colors.blue[600]!,
                                Icons.hourglass_top,
                                visible: !_seccionesOcultasMonitor.contains('cotizadas'),
                              ),
                              _construirBloqueServicios(
                                context,
                                '✅ COTIZACIONES APROBADAS · EN ESPERA',
                                _filtrar(cotizacionesAprobadas),
                                Colors.teal[700]!,
                                Icons.check_circle_outline,
                                visible: !_seccionesOcultasMonitor.contains('cotizaciones_aprobadas'),
                              ),
                              _construirBloqueServicios(
                                context,
                                '⏰ SERVICIOS PROGRAMADOS (EN ESPERA)',
                                _filtrar(programados),
                                Colors.teal[700]!,
                                Icons.schedule,
                                visible: !_seccionesOcultasMonitor.contains('programados'),
                              ),
                              _construirBloqueServicios(
                                context,
                                '♻️ SERVICIOS CADUCADOS',
                                _filtrar(caducados),
                                Colors.purple[800]!,
                                Icons.hourglass_disabled,
                                visible: !_seccionesOcultasMonitor.contains('caducados'),
                              ),
                              _construirBloqueServicios(
                                context,
                                '⏱️ SERVICIOS VENCIDOS / DEMORADOS',
                                _filtrar(finalizadosDemora),
                                Colors.deepPurple[700]!,
                                Icons.timer_off,
                                visible: !_seccionesOcultasMonitor.contains('demorados'),
                              ),
                              _construirBloqueServicios(
                                context,
                                '🟢 RADAR DE DISPONIBLES',
                                _filtrar(libres),
                                const Color(0xff3AF500),
                                Icons.add_task,
                                visible: !_seccionesOcultasMonitor.contains('libres'),
                              ),
                              _construirBloqueServicios(
                                context,
                                '🟡 SERVICIOS EN CURSO',
                                _filtrar(enCurso),
                                Colors.amber[600]!,
                                Icons.motorcycle,
                                visible: !_seccionesOcultasMonitor.contains('en_curso'),
                              ),
                              _construirBloqueServicios(
                                context,
                                '🔴 SERVICIOS FINALIZADOS CON PROBLEMA',
                                _filtrar(finalizadosProblema),
                                Colors.red[900]!,
                                Icons.report_off,
                                visible: !_seccionesOcultasMonitor.contains('finalizados_problema'),
                              ),
                              _construirBloqueServicios(
                                context,
                                '⚪ SERVICIOS FINALIZADOS',
                                _filtrar(finalizados),
                                Colors.grey[500]!,
                                Icons.check_circle_outline,
                                visible: !_seccionesOcultasMonitor.contains('finalizados'),
                              ),
                              _construirBloqueServicios(
                                context,
                                '⚫ SERVICIOS CANCELADOS',
                                _filtrar(cancelados),
                                Colors.black54,
                                Icons.block,
                                visible: !_seccionesOcultasMonitor.contains('cancelados'),
                              ),
                            ],
                          ),
                        ),
                      ],
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

  // =========================================================================
  // CONFIGURACIÓN DE RECARGOS POR LOCAL
  // =========================================================================
  // recargo_nocturno_especial: NULL = usa el default de config_sistema
  //   ($2.000). Un valor propio (ej: 1000) = convenio especial del local.
  //
  // zona_lluvia: 'general' = recibe recargo si llueve en cualquier zona
  //   monitoreada. 'trapiches' = SOLO si llueve específicamente en
  //   Trapiches (evita cobrar de más a locales que solo despachan ahí).
  // =========================================================================
  // EXPULSIÓN DE PARADERO — individual y general
  // =========================================================================
  // Saca a un moto de la fila sin afectar su cuenta — solo limpia
  // paradero_actual/ingreso_fila. Puede volver a registrarse cuando
  // quiera (sigue en línea, solo pierde su puesto en la fila).
  // =========================================================================
  // MENÚ DE ACCIONES POR MÓVIL — un solo punto de entrada, sin botones
  // apretados que se puedan tocar por error. Se abre al tocar la
  // tarjeta del moto en cualquiera de las filas de paradero.
  // =========================================================================
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
        ScaffoldMessenger.of(context).showSnackBar( // ignore: use_build_context_synchronously
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
        ScaffoldMessenger.of(context).showSnackBar( // ignore: use_build_context_synchronously
          SnackBar(
            content: Text('${movil['nombre']} fue sacado de la fila.'),
            backgroundColor: Colors.black,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar( // ignore: use_build_context_synchronously
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
        ScaffoldMessenger.of(context).showSnackBar( // ignore: use_build_context_synchronously
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
        ScaffoldMessenger.of(context).showSnackBar( // ignore: use_build_context_synchronously
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
                    Navigator.pop(context); // ignore: use_build_context_synchronously
                    _abrirGestorParaderos(); // recarga con los nuevos datos
                    ScaffoldMessenger.of(context).showSnackBar( // ignore: use_build_context_synchronously
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
                padding: const EdgeInsets.all(16),
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
                      icono: Icons.map_outlined,
                      color: Colors.indigo[700]!,
                      titulo: 'Red de Direcciones',
                      subtitulo: 'Direcciones compartidas con locales',
                      onTap: () => _abrirRedDirecciones(context),
                    ),
                    _tarjetaGestion(
                      icono: Icons.price_change_outlined,
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
