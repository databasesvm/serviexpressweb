// ignore_for_file: curly_braces_in_flow_control_structures, no_leading_underscores_for_local_identifiers, unnecessary_string_interpolations, empty_catches, deprecated_member_use, use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import 'package:serviexpress_app/screens/ranking_screen.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:serviexpress_app/utils/motor_rutas.dart';
import 'package:serviexpress_app/utils/onesignal_api.dart'; // MotorNotificaciones — necesario para el botón de pánico
import 'package:serviexpress_app/utils/sonido_manager.dart'; // Motor de audio in-app
import 'package:serviexpress_app/utils/panico_widgets.dart'; // Botón de pánico
import 'package:serviexpress_app/utils/permisos_criticos.dart'; // Permisos críticos en segundo plano
import 'package:serviexpress_app/services/ota_updater.dart'; // OTA updates
import 'package:url_launcher/url_launcher.dart';
import 'package:serviexpress_app/screens/chat_screen.dart';
import 'package:flutter/foundation.dart';
// geolocator_apple removido — no compila en web; usamos LocationSettings genérico para iOS
import 'package:shared_preferences/shared_preferences.dart';
import 'package:latlong2/latlong.dart' hide Path; // <--- MOTOR DE DISTANCIAS (hide Path evita conflicto con ui.Path)
import 'package:image_picker/image_picker.dart';
import 'package:serviexpress_app/utils/auth_helper.dart'; // hashContrasena — cambio de contraseña
import 'package:serviexpress_app/utils/widgets_compartidos.dart'; // PulsingPanicoButton y otros widgets compartidos
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';

part 'movil_widgets.dart';

class MovilScreen extends StatefulWidget {
  final Map<String, dynamic> usuario;
  const MovilScreen({super.key, required this.usuario});

  @override
  State<MovilScreen> createState() => _MovilScreenState();
}

class _MovilScreenState extends State<MovilScreen>
    with WidgetsBindingObserver {
  late bool _estaEnLinea;
  // Recuerda el último estado de suspensión conocido para detectar el
  // momento EXACTO en que Central lo reactiva — sin esto, el chequeo
  // periódico se apagaba solo justo cuando más falta hacía (ver
  // _iniciarRelojSupervisionMultitarea).
  late bool _estabaSuspendido;
  bool _procesando = false;

  Timer? _supervisionTimer;
  StreamSubscription<Position>? _gpsTimer;

  List<Map<String, dynamic>> _serviciosActivosData = [];
  final Set<int> _serviciosOcultosLocales = {};
  DateTime _ultimaActividadUtc = DateTime.now().toUtc();
  bool _alertaInactividadMostrada = false;

  // --- VARIABLES DE ESTADO TÁCTICAS ---
  final Set<int> _serviciosExpandidos = {};
  // REDISEÑO PANEL: 0 = Radar (operativo), 1 = Perfil (cuenta, datos,
  // historial). Antes todo vivía amontonado en un solo Scaffold con 4
  // íconos en el AppBar — ahora Perfil tiene su propia pestaña.
  int _tabActual = 0;

  // Controllers del tab de Perfil — instancia única (no se recrean en
  // cada rebuild) para no perder lo que el moto esté escribiendo si
  // el stream de su propio perfil emite mientras edita.
  late final TextEditingController _perfilTelefonoCtrl;
  late final TextEditingController _perfilNequiCtrl;
  late final TextEditingController _perfilDaviplataCtrl;
  late final TextEditingController _perfilBancolombiaCtrl;
  bool _guardandoPerfil = false;
  bool _subiendoFoto = false;
  // REDISEÑO PANEL: la "Fila en Vivo" ahora es colapsable — por
  // defecto solo muestra un resumen de una línea, no compite por
  // atención con el resto del panel.
  bool _filaVirtualExpandida = false;
  Position? _ultimaPosicionConocida;
  // ------------------------------------

  // --- COMPARTIDO DE UBICACIÓN POR PÁNICO (24H) ---
  int? _eventoPanicoActivoId;
  DateTime? _panicoUbicacionExpiraAt;

  // --- CONTROL DE BOTÓN DE PÁNICO ---
  // Solo visible cuando hay servicio activo Y no se ha usado hoy.
  bool _tieneServicioActivo = false;
  bool _panicoUsadoHoy = false;
  // -------------------------------------------------

  // --- ZONAS DE PARADERO: nombre -> [lat, lng, radio en metros] ---
  // Fuente única — la usan tanto _intentarRegistroParadero() (registro
  // manual/automático) como el loop de GPS (expulsión automática por
  // geocerca). Evita que ambos lugares tengan números mágicos propios
  // que puedan desincronizarse si alguno se actualiza y el otro no.
  static const Map<String, List<double>> _kZonasParadero = {
    'BASE CASA': [7.860035, -72.482059, 200],
    'EXPUENTE': [7.863439, -72.475760, 100],
    'MEMOS': [7.863976, -72.479256, 100],
    'NOCTURNO': [7.863283, -72.476152, 100],
  };

  // Caché local del paradero actual — se sincroniza en
  // _intentarRegistroParadero() y _salirDelParadero(). El loop de GPS
  // lo usa para saber si debe vigilar la geocerca, sin tener que
  // consultar la BD en cada tick de posición.
  String? _miParaderoCache;
  // -------------------------------------------------

  final Map<int, bool> _alertasPrecaucion = {};

  final SonidoManager _sonidos = SonidoManager();
  bool _reproduciendoAudio =
      false; // Compuerta anti-duplicados para nuevo_pedido
  int _cantidadPendientesAnterior = 0;

  bool _sonidoSoporteReproducido = false;

  // PRODUCCIÓN — cargados una vez al abrir la pantalla para evitar el
  // parpadeo "Cargando..." de FutureBuilder dentro de StreamBuilder.
  int _serviciosHoy = 0;
  int _serviciosTotal = 0;
  double _producidoHoy = 0;

  // =====================================================================
  bool _gpsEnProceso = false;

  // ARQUITECTURA ANTI-PARPADEO: el StreamBuilder consume estos
  // controllers, que NUNCA cambian de identidad durante toda la vida
  // de la pantalla. Por debajo, _construirStreams() puede reconectar
  // el canal real de Supabase cuantas veces haga falta — el
  // StreamBuilder nunca se entera, nunca resetea su snapshot, nunca
  // muestra el loading spinner. El dato anterior se queda visible
  // hasta que llega el dato nuevo, sin parpadeo.
  final StreamController<List<Map<String, dynamic>>> _ctrlUsuarios =
      StreamController<List<Map<String, dynamic>>>.broadcast();
  final StreamController<List<Map<String, dynamic>>> _ctrlServicios =
      StreamController<List<Map<String, dynamic>>>.broadcast();
  Stream<List<Map<String, dynamic>>> get _streamUsuarios =>
      _ctrlUsuarios.stream;
  Stream<List<Map<String, dynamic>>> get _streamServicios =>
      _ctrlServicios.stream;
  // Cache del último dato — se usa como initialData para que al volver
  // de la pestaña de Perfil el radar no muestre spinner sino el dato previo.
  List<Map<String, dynamic>>? _cacheUsuarios;
  List<Map<String, dynamic>>? _cacheServicios;
  StreamSubscription<List<Map<String, dynamic>>>? _subUsuarios;
  StreamSubscription<List<Map<String, dynamic>>>? _subServicios;
  RealtimeChannel? _canalUpdateServicios; // refresh inmediato al cambiar estado

  // SILENCIADOR PRIMER PLANO: guardamos la referencia para poder removerloen dispose()
  // y evitar que se acumulen listeners si la pantalla se reinicia.
  void Function(OSNotificationWillDisplayEvent)? _onForegroundNotif;

  // Referencias a los canales Realtime — necesarias para cancelarlos
  // correctamente en dispose(). Sin guardar la referencia, .unsubscribe()
  // en dispose() crea un objeto nuevo y el canal original queda activo.
  RealtimeChannel? _canalRadarBg;
  RealtimeChannel? _canalPanico;
  // ---- DOMICILIOS ----
  RealtimeChannel? _canalPedidosMovil;
  Map<String, dynamic>? _pedidoDomicilioActivo;
  bool _alertaPedidoMostrada = false;


  // VIGILANTE DE CONEXIÓN — ver _iniciarVigilanteDeConexion() más abajo.
  // Reconstruye los streams de Realtime periódicamente. Una conexión
  // websocket de larga duración puede morir en silencio por cambios de
  // red, el sistema operativo suspendiendo la app, o el propio canal
  // quedando en un estado inconsistente — sin esto, la única forma de
  // recuperarse era cerrar la app y volver a abrirla.
  Timer? _reconexionTimer;

  // OPTIMIZACIÓN DE REBUILD: en lugar de setState(() {}) cada 5s
  // (que reconstruye toda la pantalla), solo notificamos al bloque
  // del radar vía ValueListenableBuilder. El resto de la UI (AppBar,
  // tabs, perfil) no se toca en cada tick.
  final ValueNotifier<int> _radarTick = ValueNotifier(0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // PERMISOS CRÍTICOS — chequeo SILENCIOSO primero, sin mostrar nada.
    // Antes esta pantalla aparecía SIEMPRE al abrir la app, incluso con
    // todo ya concedido — tedioso e invasivo. Ahora solo se muestra si
    // de verdad falta algo por activar.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final faltaAlgo = await PermisosCriticosScreen.hayPermisosPendientes();
      if (faltaAlgo && mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const PermisosCriticosScreen(
              permisosOpcionales: kPermisosOpcionalesMovil,
            ),
            fullscreenDialog: true,
          ),
        );
      }
      // OTA: verificar actualización (solo Android/iOS, no aplica en web)
      if (!kIsWeb && mounted) await OtaUpdater.verificar(context);
    });

    Future.microtask(() async {
      OneSignal.login(widget.usuario['id'].toString());
      // Obligamos a Android/iOS a pedirle permiso al piloto para la barra de notificaciones
      await OneSignal.Notifications.requestPermission(true);

      // ---> INYECCIÓN: SONIDO EN PRIMER PLANO <---
      // Guardamos referencia para limpiar en dispose() y no acumular
      // múltiples instancias del listener si la pantalla se reconstruye.
      _onForegroundNotif = (event) {
        // Suprimimos el banner del sistema (el radar ya muestra el servicio),
        // pero disparamos el sonido de alerta para que el piloto se entere
        // aunque tenga la pantalla encendida y la app abierta.
        event.preventDefault();
        if (mounted) _sonidos.reproducir(Sonidos.alerta);
      };
      OneSignal.Notifications.addForegroundWillDisplayListener(_onForegroundNotif!);
      // --------------------------------------------------
    });

    _estaEnLinea = widget.usuario['en_linea'] ?? false;
    _perfilTelefonoCtrl = TextEditingController(
      text: widget.usuario['telefono']?.toString() ?? '',
    );
    _perfilNequiCtrl = TextEditingController(
      text: widget.usuario['pago_nequi']?.toString() ?? '',
    );
    _perfilDaviplataCtrl = TextEditingController(
      text: widget.usuario['pago_daviplata']?.toString() ?? '',
    );
    _perfilBancolombiaCtrl = TextEditingController(
      text: widget.usuario['pago_bancolombia']?.toString() ?? '',
    );
    _estabaSuspendido = widget.usuario['suspendido'] ?? false;
    _miParaderoCache = widget.usuario['paradero_actual']?.toString();

    _construirStreams(); // primera vez — luego se reconstruyen solos
    _iniciarVigilanteDeConexion();
    _cargarProduccion();
    _verificarPanicoUsadoHoy();

    // ---- DOMICILIOS: suscripción a pedidos sin asignar ----
    _suscribirAlertasDomicilio();

    // ---> INYECCIÓN: RADAR EN SEGUNDO PLANO (OÍDO SATELITAL) <---
    _canalRadarBg = Supabase.instance.client
        .channel('radar_bg_${widget.usuario['id']}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'servicios',
          callback: (payload) {
            // Solo dejamos la lógica de sincronización si es necesaria,
            // pero sin declarar variables que no usamos.
            if (!_estaEnLinea) return;

            // AUTO-RETORNO AL PARADERO: si Central canceló MI servicio
            // activo, vuelvo a intentar registrarme en la fila sin
            // necesidad de tocar el botón manualmente. No usamos
            // payload.oldRecord para esto — Realtime no siempre trae
            // el valor anterior completo salvo REPLICA IDENTITY FULL,
            // así que basta con leer el estado NUEVO directamente.
            final doc = payload.newRecord;
            if (doc.isNotEmpty) {
              final String miId = widget.usuario['id'].toString();
              final bool fueMiCancelacion =
                  doc['movil_id']?.toString() == miId &&
                  [
                    'cancelado',
                    'finalizado_por_demora',
                    'finalizado_con_problema',
                  ].contains(doc['estado']?.toString());

              if (fueMiCancelacion) {
                _intentarRegistroParadero();
              }
            }

            // El radar sigue recibiendo datos para que el StreamBuilder
            // de abajo sepa que debe refrescar la pantalla automáticamente.
            if (mounted) setState(() {});
          },
        )
        .subscribe();
    // ------------------------------------------------------------

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
            final miId = widget.usuario['id'];

            // SILENCIO PARA EL DISPARADOR: por seguridad, quien activa el
            // pánico no recibe su propia alerta (overlay ni sonido).
            if (disparadorId != null &&
                disparadorId.toString() == miId.toString()) {
              return;
            }

            // Para alertas individuales: solo mostramos si somos el destino
            if (tipo == 'individual' &&
                destinoId?.toString() != miId.toString()) {
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

    _arranqueSeguro();
    _iniciarRelojSupervisionMultitarea();
  }

  void _cambiarTab(int index) {
    if (!mounted || index == _tabActual) return;
    setState(() => _tabActual = index);
  }


  // =========================================================================
  // DOMICILIOS — Suscripción, alerta y tarjeta de pedido activo
  // =========================================================================

  void _suscribirAlertasDomicilio() {
    final miId = widget.usuario['id'] as int;
    _canalPedidosMovil = Supabase.instance.client
        .channel('pedidos_movil_$miId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'pedidos',
          callback: (payload) async {
            final rec = payload.newRecord;
            if (rec.isEmpty) return;
            final estado = rec['estado']?.toString() ?? '';
            final movilId = (rec['movil_id'] as num?)?.toInt();
            final pedidoId = rec['id']?.toString() ?? '';

            // Pedido sin asignar que acaba de entrar — mostrar alerta
            if (estado == 'pendiente_confirmacion' && movilId == null) {
              if (!_alertaPedidoMostrada && mounted) {
                _alertaPedidoMostrada = true;
                await _cargarYMostrarAlertaPedido(pedidoId);
                _alertaPedidoMostrada = false;
              }
              return;
            }

            // Pedido asignado a este móvil — actualizar tarjeta activa
            if (movilId == miId) {
              final pedido = await Supabase.instance.client
                  .from('pedidos')
                  .select('*, items_pedido(nombre_snapshot, cantidad)')
                  .eq('id', pedidoId)
                  .maybeSingle();
              if (pedido == null) return;
              if (!mounted) return;
              final esTerminal = ['entregado', 'cancelado'].contains(estado);
              setState(() => _pedidoDomicilioActivo = esTerminal ? null : pedido);
            }

            // Pedido ya asignado a otro — cerrar alerta si estaba abierta
            if (movilId != null && movilId != miId && _alertaPedidoMostrada) {
              if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
            }
          },
        )
        .subscribe();
    // Verificar si ya hay un pedido asignado a este movil
    _cargarPedidoActivoPropio();
  }

  Future<void> _cargarPedidoActivoPropio() async {
    final miId = widget.usuario['id'] as int;
    try {
      final data = await Supabase.instance.client
          .from('pedidos')
          .select('*, items_pedido(nombre_snapshot, cantidad)')
          .eq('movil_id', miId)
          .not('estado', 'in', '("entregado","cancelado")')
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      if (!mounted) return;
      setState(() => _pedidoDomicilioActivo = data);
    } catch (_) {}
  }

  Future<void> _cargarYMostrarAlertaPedido(String pedidoId) async {
    try {
      final pedido = await Supabase.instance.client
          .from('pedidos')
          .select('*, items_pedido(nombre_snapshot, cantidad, precio_snapshot)')
          .eq('id', pedidoId)
          .maybeSingle();
      if (pedido == null) return;

      // Cargar nombre del local
      final local = await Supabase.instance.client
          .from('usuarios')
          .select('nombre, direccion')
          .eq('id', pedido['local_id'])
          .maybeSingle();

      if (!mounted) return;
      await _mostrarAlertaPedido(pedido, local);
    } catch (_) {}
  }

  Future<void> _mostrarAlertaPedido(
    Map<String, dynamic> pedido,
    Map<String, dynamic>? local,
  ) async {
    final items = pedido['items_pedido'] as List? ?? [];
    final total = (pedido['total'] as num?)?.toInt() ?? 0;

    String fmt(int p) {
      final s = p.toString();
      final buf = StringBuffer();
      for (int i = 0; i < s.length; i++) {
        if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
        buf.write(s[i]);
      }
      return '\$ ${buf.toString()}';
    }

    final aceptado = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        titlePadding: EdgeInsets.zero,
        contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        title: Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Row(
            children: [
              Icon(Icons.delivery_dining, color: Color(0xff3AF500), size: 26),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  '¡NUEVO DOMICILIO!',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15),
                ),
              ),
            ],
          ),
        ),
        content: Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (local != null) ...[
                Row(
                  children: [
                    const Icon(Icons.storefront, size: 14, color: Colors.grey),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(local['nombre']?.toString() ?? '',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              ...items.map((i) => Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text('• ${i["cantidad"]}x ${i["nombre_snapshot"]}',
                        style: const TextStyle(fontSize: 12)),
                  )),
              const Divider(height: 16),
              Row(
                children: [
                  const Icon(Icons.location_on_outlined, size: 14, color: Colors.grey),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                        pedido['direccion_entrega']?.toString() ?? '',
                        style: TextStyle(fontSize: 12, color: Colors.grey[700])),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    pedido['metodo_pago'] == 'efectivo' ? '💵 Efectivo' : '📲 Transferencia',
                    style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                  ),
                  Text(fmt(total),
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14)),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('RECHAZAR',
                style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ACEPTAR',
                style: TextStyle(
                    color: Color(0xff3AF500), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (aceptado != true) return;
    // Intentar tomar el pedido
    try {
      final miId = widget.usuario['id'] as int;
      final result = await Supabase.instance.client
          .from('pedidos')
          .update({'movil_id': miId, 'estado': 'confirmado'})
          .eq('id', pedido['id'])
          .isFilter('movil_id', null) // solo si no fue tomado ya
          .select()
          .maybeSingle();
      if (!mounted) return;
      if (result == null) {
        // Ya fue tomado por otro
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Ya fue tomado por otro móvil'),
          backgroundColor: Colors.orange,
        ));
      } else {
        await _cargarPedidoActivoPropio();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('¡Pedido aceptado! Ve al local a recogerlo.'),
            backgroundColor: Colors.black,
          ));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: \$e'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  Future<void> _avanzarEstadoDomicilio() async {
    final p = _pedidoDomicilioActivo;
    if (p == null) return;
    const flujo = {
      'confirmado': 'en_camino',
      'listo_para_recoger': 'en_camino',
      'en_camino': 'entregado',
    };
    final siguiente = flujo[p['estado']?.toString()];
    if (siguiente == null) return;
    try {
      await Supabase.instance.client
          .from('pedidos')
          .update({'estado': siguiente})
          .eq('id', p['id']);
      if (siguiente == 'entregado') {
        setState(() => _pedidoDomicilioActivo = null);
      } else {
        await _cargarPedidoActivoPropio();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _cancelarDomicilio() async {
    final p = _pedidoDomicilioActivo;
    if (p == null) return;
    final db = Supabase.instance.client;

    // Motivos: (texto, esFuerzaMayor)
    final motivos = <(String, bool)>[
      ('No puedo ir a recoger en este momento', false),
      ('El local está demasiado lejos', false),
      ('Error en la dirección de entrega', false),
      ('No me encuentro disponible', false),
      ('🔧 Problema mecánico con la moto', true),
      ('🛞 Pinchado / Llanta baja', true),
      ('⚙️ Avería mecánica', true),
      ('🚨 Accidente de tránsito', true),
      ('Otro motivo', false),
    ];
    (String, bool)? motivoSeleccionado;
    final otroCtrl = TextEditingController();

    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setDlg) {
          final esFM = motivoSeleccionado?.$2 ?? false;
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            title: const Text('¿Por qué liberas el domicilio?',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: esFM ? Colors.green[50] : Colors.red[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: esFM ? Colors.green : Colors.red),
                      ),
                      child: Text(
                        esFM
                            ? '✅ Fuerza mayor — no se descuentan puntos.'
                            : '⚠️ Esta liberación descontará 1.0 pt de tu puntuación.',
                        style: TextStyle(
                            fontSize: 12,
                            color: esFM ? Colors.green[800] : Colors.red[800],
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Padding(
                      padding: EdgeInsets.only(left: 4, bottom: 6),
                      child: Text('Los motivos en verde (fuerza mayor) no penalizan.',
                          style: TextStyle(fontSize: 10, color: Colors.black38)),
                    ),
                    ...motivos.map((m) => RadioListTile<(String, bool)>(
                          title: Text(m.$1,
                              style: TextStyle(
                                  fontSize: 13,
                                  color: m.$2 ? Colors.green[700] : Colors.black87,
                                  fontWeight: m.$2 ? FontWeight.bold : FontWeight.normal)),
                          value: m,
                          groupValue: motivoSeleccionado,
                          dense: true,
                          activeColor: m.$2 ? Colors.green : Colors.red,
                          onChanged: (v) => setDlg(() => motivoSeleccionado = v),
                        )),
                    if (motivoSeleccionado?.$1 == 'Otro motivo') ...[
                      const SizedBox(height: 8),
                      TextField(
                        controller: otroCtrl,
                        maxLines: 2,
                        decoration: InputDecoration(
                          hintText: 'Describe el motivo...',
                          isDense: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Volver', style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: esFM ? Colors.green : Colors.red,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: motivoSeleccionado == null
                    ? null
                    : () => Navigator.pop(ctx, true),
                child: Text('Liberar domicilio',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );

    if (confirmado != true || motivoSeleccionado == null) return;

    final esFuerzaMayor = motivoSeleccionado!.$2;
    final motivo = motivoSeleccionado!.$1 == 'Otro motivo' && otroCtrl.text.trim().isNotEmpty
        ? otroCtrl.text.trim()
        : motivoSeleccionado!.$1;

    try {
      final pedidoId = p['id'] as int;
      final movilId = widget.usuario['id'];

      // 1. Liberar — vuelve a 'pendiente' para que cualquiera pueda tomarlo
      await db.from('pedidos').update({
        'movil_id': null,
        'estado': 'pendiente',
      }).eq('id', pedidoId);

      // 2. Registrar cancelación
      await db.from('cancelaciones_domicilio').insert({
        'movil_id': p['movil_id'] ?? movilId,
        'pedido_id': pedidoId,
        'motivo': motivo,
        'fuerza_mayor': esFuerzaMayor,
      });

      // 3. Penalizar puntaje solo si NO es fuerza mayor
      if (movilId != null && !esFuerzaMayor) {
        final movilData = await db.from('usuarios').select('puntuacion').eq('id', movilId).maybeSingle();
        if (movilData != null) {
          final puntActual = (movilData['puntuacion'] as num?)?.toDouble() ?? 5.0;
          final nuevoPunt = (puntActual - 1.0).clamp(1.0, 5.0);
          await db.from('usuarios').update({'puntuacion': double.parse(nuevoPunt.toStringAsFixed(2))}).eq('id', movilId);
        }
      }

      // 4. Limpiar estado local
      setState(() => _pedidoDomicilioActivo = null);

      // 5. Notificar al local
      final localId = p['local_id'];
      if (localId != null) {
        final localData = await db.from('usuarios').select('nombre').eq('id', localId).maybeSingle();
        final localNombre = localData?['nombre'] ?? 'el local';
        MotorNotificaciones.dispararMisil(
          idDestino: localId.toString(),
          titulo: '⚠️ Domicilio cancelado — $localNombre',
          mensaje: 'El móvil canceló tu pedido. Motivo: $motivo. Buscamos otro.',
          urgente: true,
          sonido: 'alerta',
        );
      }

      // 6. REINICIAR CASCADA — igual que un servicio nuevo
      final local = p['local_nombre']?.toString() ?? 'local';
      final msgAlerta = '🔄 Domicilio liberado — busca nuevo móvil para: $local';

      // T=0: Masters + Central
      final mastersData = await db
          .from('usuarios')
          .select('id')
          .or('rol.eq.central,rol.eq.master,rango_movil.eq.MASTER')
          .eq('activo', true)
          .neq('suspendido', true);
      final masterIds = mastersData.map((u) => u['id'].toString()).toList();
      if (masterIds.isNotEmpty) {
        await MotorNotificaciones.dispararRafa(
          idsDestinos: masterIds,
          titulo: '🔄 DOMICILIO SIN MÓVIL',
          mensaje: msgAlerta,
        );
      }

      // T=30s: paradero (misil — sobrevive aunque el widget se desmonte)
      final enParaderoData = await db
          .from('usuarios')
          .select('id')
          .eq('rol', 'movil')
          .eq('en_linea', true)
          .neq('suspendido', true)
          .not('paradero_actual', 'is', null);
      final paraderoIds = (enParaderoData as List)
          .map((u) => u['id'].toString())
          .where((id) => id != movilId?.toString() && !masterIds.contains(id))
          .toList();
      if (paraderoIds.isNotEmpty) {
        await MotorNotificaciones.programarMisilRetardado(
          externalIds: paraderoIds,
          titulo: '🔄 DOMICILIO SIN MÓVIL',
          mensaje: msgAlerta,
          segundosRetardo: 30,
        );
      }

      // T=60s: todos los disponibles — misil server-side
      {
        final todosD = await db.from('usuarios').select('id').eq('rol', 'movil').eq('en_linea', true).neq('suspendido', true);
        final idsTodosD = (todosD as List).map((u) => u['id'].toString()).where((id) => !masterIds.contains(id)).toList();
        if (idsTodosD.isNotEmpty) {
          final id60sD = await MotorNotificaciones.programarMisilRetardado(
            externalIds: idsTodosD,
            titulo: '🚨 DOMICILIO SIN TOMAR',
            mensaje: msgAlerta,
            segundosRetardo: 60,
          );
          if (id60sD != null) {
            await db.from('pedidos').update({'onesignal_2m': id60sD}).eq('id', pedidoId);
          }
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Domicilio liberado. Se está buscando otro móvil.'),
            backgroundColor: Colors.orange));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Widget _buildTarjetaDomicilio() {
    final p = _pedidoDomicilioActivo;
    if (p == null) return const SizedBox.shrink();
    final estado = p['estado']?.toString() ?? '';
    final items = p['items_pedido'] as List? ?? [];

    String labelBoton() {
      switch (estado) {
        case 'confirmado': return '🛍️ Ya recogí el pedido → EN CAMINO';
        case 'listo_para_recoger': return '🛍️ Ya recogí el pedido → EN CAMINO';
        case 'en_camino': return '✅ Entregado al cliente';
        default: return '';
      }
    }

    final mostrarBoton = ['confirmado', 'listo_para_recoger', 'en_camino'].contains(estado);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.deepPurple.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.deepPurple.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Builder(builder: (ctx) {
            final tipoSvc = p['tipo_servicio']?.toString().toUpperCase() ?? '';
            IconData icoTipo = Icons.electric_moped;
            Color clrTipo = const Color(0xff3AF500);
            String lblTipo = 'DOMICILIO';
            if (tipoSvc == 'COMIDA') {
              icoTipo = Icons.dining;             clrTipo = Colors.red[400]!;    lblTipo = 'COMIDA';
            } else if (tipoSvc == 'BEBIDAS') {
              icoTipo = Icons.nightlife;          clrTipo = Colors.purple[300]!; lblTipo = 'BEBIDAS';
            } else if (tipoSvc == 'COMPRAS') {
              icoTipo = Icons.shopping_basket;    clrTipo = Colors.teal[400]!;   lblTipo = 'ENCARGO';
            } else if (tipoSvc == 'PAQUETERÍA') {
              icoTipo = Icons.inventory_2_rounded; clrTipo = Colors.brown[300]!; lblTipo = 'PAQUETE';
            }
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.deepPurple,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Row(
                children: [
                  Icon(icoTipo, color: clrTipo, size: 20),
                  const SizedBox(width: 8),
                  Text('DOMICILIO EN CURSO',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          letterSpacing: 0.5)),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: clrTipo.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: clrTipo.withValues(alpha: 0.6)),
                    ),
                    child: Text(lblTipo,
                        style: TextStyle(
                            color: clrTipo,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5)),
                  ),
                ],
              ),
            );
          }),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(estado.replaceAll('_', ' ').toUpperCase(),
                    style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.deepPurple,
                        letterSpacing: 0.8)),
                const SizedBox(height: 6),
                ...items.map((i) => Text(
                      '• ${i["cantidad"]}x ${i["nombre_snapshot"]}',
                      style: const TextStyle(fontSize: 12),
                    )),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.location_on_outlined, size: 13, color: Colors.grey),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                          p['direccion_entrega']?.toString() ?? '',
                          style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
                if (mostrarBoton) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurple,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      onPressed: _avanzarEstadoDomicilio,
                      child: Text(labelBoton(),
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12)),
                    ),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                      icon: const Icon(Icons.lock_open_outlined, size: 16),
                      label: const Text('Liberar domicilio', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      onPressed: _cancelarDomicilio,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _canalRadarBg?.unsubscribe();
    _canalPanico?.unsubscribe();
    _canalUpdateServicios?.unsubscribe();
    _canalPedidosMovil?.unsubscribe();

    // Remover el silenciador de primer plano para no acumular listeners
    if (_onForegroundNotif != null) {
      OneSignal.Notifications.removeForegroundWillDisplayListener(_onForegroundNotif!);
    }

    _supervisionTimer?.cancel();
    _reconexionTimer?.cancel();
    _gpsTimer?.cancel();
    _subUsuarios?.cancel();
    _subServicios?.cancel();
    _radarTick.dispose();
    _ctrlUsuarios.close();
    _ctrlServicios.close();
    _perfilTelefonoCtrl.dispose();
    _perfilNequiCtrl.dispose();
    _perfilDaviplataCtrl.dispose();
    _perfilBancolombiaCtrl.dispose();
    // silenciar() en lugar de dispose(): SonidoManager es singleton —
    // dispose() destruiría los AudioPlayers para todas las pantallas activas.
    _sonidos.silenciar();
    super.dispose();
  }

  // =========================================================================
  // VIGILANTE DE CONEXIÓN — radar en tiempo real a prueba de fallos
  // =========================================================================
  // PROBLEMA DETECTADO EN LA PRUEBA PILOTO: de 6 teléfonos probados en
  // paralelo, 4 dejaron de recibir actualizaciones en vivo del radar en
  // algún momento — sin ningún error visible, sin desconexión aparente.
  // La única forma de recuperarlos era cerrar la app y volver a abrirla.
  //
  // CAUSA: una conexión websocket de larga duración (el canal de
  // Supabase Realtime) puede morir en silencio por cambios de red,
  // el sistema operativo suspendiendo la app en segundo plano, o el
  // propio canal quedando en un estado inconsistente tras horas
  // conectado. Esto es un problema conocido en conexiones realtime
  // de apps móviles — no depende de si los filtros del stream son
  // correctos o no.
  //
  // SOLUCIÓN: en vez de diagnosticar la causa exacta caso por caso
  // (puede variar por dispositivo, red, fabricante de Android), se
  // reconstruye el stream periódicamente — esto fuerza a Supabase a
  // tirar el canal viejo (sano o no) y abrir uno nuevo desde cero,
  // con una recarga completa de datos incluida. Funciona sin importar
  // la causa real del cuelgue.
  //
  // Con 50 móviles trabajando a la vez, esto se traduce en ~1-2
  // peticiones por segundo en promedio para toda la flota — nada
  // para Postgres con el índice idx_servicios_estado ya puesto.
  void _construirStreams() {
    // Cancelamos las suscripciones VIEJAS al canal crudo de Supabase
    // (si las había) — esto es lo que realmente "tira la conexión
    // muerta y abre una nueva". Los controllers de arriba (_ctrlUsuarios
    // / _ctrlServicios) NO se tocan — siguen siendo los mismos objetos
    // de siempre, así que el StreamBuilder nunca lo nota.
    _subUsuarios?.cancel();
    _subServicios?.cancel();

    // PRE-CARGA RÁPIDA: fetch REST normal antes de que el WebSocket de
    // Realtime negocie (~2-5s). El StreamBuilder deja el estado
    // "waiting" en cuanto llega este primer dato — sin spinner largo.
    // El stream de Realtime lo reemplazará cuando llegue.
    Supabase.instance.client
        .from('servicios')
        .select()
        .inFilter('estado', [
          'pendiente',
          'en_ruta_origen',
          'en_origen',
          'en_ruta_destino',
          'problema',
        ])
        .order('id', ascending: false)
        .limit(50)
        .then((data) {
          _cacheServicios = List<Map<String, dynamic>>.from(data);
          if (!_ctrlServicios.isClosed) _ctrlServicios.add(_cacheServicios!);
        })
        .catchError((_) {});

    Supabase.instance.client
        .from('usuarios')
        .select()
        .eq('rol', 'movil')
        .then((data) {
          _cacheUsuarios = List<Map<String, dynamic>>.from(data);
          if (!_ctrlUsuarios.isClosed) _ctrlUsuarios.add(_cacheUsuarios!);
        })
        .catchError((_) {});

    final crudoUsuarios = Supabase.instance.client
        .from('usuarios')
        .stream(primaryKey: ['id'])
        .eq('rol', 'movil');

    final crudoServicios = Supabase.instance.client
        .from('servicios')
        .stream(primaryKey: ['id'])
        // FIX #9: antes descargaba 150 servicios sin ningún filtro —
        // cancelados, finalizados, de otras zonas, todo. El builder
        // solo necesita 5 estados. Reducción aprox. del 90% en datos.
        //
        // 'pendiente'        → radar del Francotirador y fila de paradero
        // 'en_ruta_origen'   → servicio activo del móvil (yendo al origen)
        // 'en_origen'        → servicio activo (esperando en origen)
        // 'en_ruta_destino'  → servicio activo (yendo al destino)
        // 'problema'         → servicio activo con incidencia
        .inFilter('estado', [
          'pendiente',
          'en_ruta_origen',
          'en_origen',
          'en_ruta_destino',
          'problema',
        ])
        .order('id', ascending: false)
        .limit(50); // Reducido de 150: sin histórico, sin cancelados

    // Reenviamos cada evento del canal crudo hacia el controller
    // estable. Mientras no llegue el primer dato del canal nuevo, el
    // controller simplemente no emite nada — y el StreamBuilder sigue
    // mostrando el último dato bueno que ya tenía. Cero parpadeo.
    _subUsuarios = crudoUsuarios.listen(
      (data) {
        _cacheUsuarios = data;
        if (!_ctrlUsuarios.isClosed) _ctrlUsuarios.add(data);
      },
      onError: (e) {
        if (!_ctrlUsuarios.isClosed) _ctrlUsuarios.addError(e);
      },
    );
    _subServicios = crudoServicios.listen(
      (data) {
        _cacheServicios = data;
        if (!_ctrlServicios.isClosed) _ctrlServicios.add(data);
      },
      onError: (e) {
        if (!_ctrlServicios.isClosed) _ctrlServicios.addError(e);
      },
    );

    // CANAL UPDATE — cuando la Central cambia el estado de un servicio
    // (cancela, finaliza, reactiva), el .stream() con .inFilter() puede
    // tardar hasta 20s en quitar/agregar la fila. Este canal Postgres
    // escucha cualquier UPDATE en servicios y fuerza un refresh REST
    // inmediato para que el radar se actualice al instante.
    _canalUpdateServicios?.unsubscribe();
    _canalUpdateServicios = Supabase.instance.client
        .channel('movil_svc_update_${widget.usuario['id']}')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'servicios',
          callback: (_) {
            Supabase.instance.client
                .from('servicios')
                .select()
                .inFilter('estado', [
                  'pendiente',
                  'en_ruta_origen',
                  'en_origen',
                  'en_ruta_destino',
                  'problema',
                ])
                .order('id', ascending: false)
                .limit(50)
                .then((data) {
                  _cacheServicios = List<Map<String, dynamic>>.from(data);
                  if (!_ctrlServicios.isClosed) _ctrlServicios.add(_cacheServicios!);
                })
                .catchError((_) {});
          },
        )
        .subscribe();
  }

  // Reconstruye los streams cada 30s — bastante seguido para que una
  // caída silenciosa nunca dure más de medio minuto sin corregirse
  // sola, pero sin saturar la base de datos con la flota completa.
  // No usa setState() — la reconexión es invisible para el árbol de
  // widgets, así que no hace falta forzar ningún rebuild para lograrla.
  void _iniciarVigilanteDeConexion() {
    _reconexionTimer?.cancel();
    _reconexionTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (!mounted) return;
      _construirStreams();
      // BAN CHECK (movido aquí desde el timer de 5s — era 12 queries/min,
      // ahora son 2/min, suficiente para detectar suspensión en ≤30s).
      if (_estaEnLinea || _estabaSuspendido) {
        try {
          final myUser = await Supabase.instance.client
              .from('usuarios')
              .select('suspendido, en_linea')
              .eq('id', widget.usuario['id'])
              .maybeSingle()
              .timeout(const Duration(seconds: 5));
          if (!mounted || myUser == null) return;
          final bool suspendidoAhora = myUser['suspendido'] == true;
          if (suspendidoAhora && _estaEnLinea) {
            _ejecutarSuspensionInmediata();
            _estabaSuspendido = true;
          } else if (!suspendidoAhora && _estabaSuspendido) {
            _notificarSuspensionLevantada();
            _estabaSuspendido = false;
          } else if (myUser['en_linea'] == false && _estaEnLinea) {
            setState(() => _estaEnLinea = false);
          }
          _estabaSuspendido = suspendidoAhora;
        } catch (e) {}
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Cuando la app vuelve de segundo plano es el momento de MÁS
    // riesgo de que el canal haya muerto (el sistema operativo suele
    // suspender la red al minimizar). Reconstruimos de inmediato en
    // vez de esperar hasta el próximo tick de los 30s.
    if (state == AppLifecycleState.resumed && mounted) {
      _construirStreams();
      // Cuando la app vuelve del background, el canal Realtime pudo haber
      // perdido el INSERT de pánico que llegó mientras estaba suspendida.
      // Verificamos en DB si hay alertas recientes sin atender.
      _verificarPanicoPendiente();
    }
  }

  // Busca eventos de pánico de los últimos 2 minutos dirigidos a este móvil
  // (global o individual). Si encuentra uno y el overlay NO está visible,
  // lo muestra — cubre el caso de app minimizada al recibir la alerta.
  Future<void> _verificarPanicoPendiente() async {
    try {
      final miId = widget.usuario['id'].toString();
      final hace2min = DateTime.now().toUtc().subtract(const Duration(minutes: 2));
      final eventos = await Supabase.instance.client
          .from('eventos_panico')
          .select()
          .neq('disparado_por_id', widget.usuario['id'])
          .gte('created_at', hace2min.toIso8601String())
          .order('created_at', ascending: false)
          .limit(5);

      for (final ev in (eventos as List)) {
        final tipo = ev['tipo']?.toString() ?? 'global';
        final destinoId = ev['destino_id']?.toString() ?? '';
        // Filtramos: global (todos) o individual (solo si el destino soy yo)
        if (tipo == 'individual' && destinoId != miId) continue;

        // Verificamos que el evento no esté ya expirado manualmente
        final expiraStr = ev['ubicacion_expira_at']?.toString();
        if (expiraStr != null) {
          final expira = DateTime.tryParse(expiraStr)?.toUtc();
          if (expira != null && DateTime.now().toUtc().isAfter(expira)) continue;
        }

        // Solo mostramos el más reciente
        bool tieneUbicacion = false;
        if ((ev['rol_disparador']?.toString() ?? '') == 'movil' &&
            ev['ultima_lat'] != null &&
            ev['ubicacion_expira_at'] != null) {
          final expira = DateTime.tryParse(ev['ubicacion_expira_at'].toString())?.toUtc();
          tieneUbicacion = expira != null && DateTime.now().toUtc().isBefore(expira);
        }
        if (mounted) {
          _mostrarPanicoOverlay(
            disparadoPor: ev['disparado_por_nombre'] ?? 'Sistema',
            usuarioDisparador: ev['disparado_por_usuario']?.toString(),
            rolDisparador: ev['rol_disparador'] ?? '',
            eventoId: ev['id'] as int?,
            tieneUbicacion: tieneUbicacion,
          );
        }
        break; // Solo mostramos una vez el más reciente
      }
    } catch (_) {}
  }

  // =========================================================================
  // PÁNICO — Alerta de emergencia
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

  // Verifica si este móvil ya disparó pánico hoy (zona horaria local).
  // Actualiza _panicoUsadoHoy para controlar la visibilidad del botón.
  Future<void> _verificarPanicoUsadoHoy() async {
    try {
      final hoyInicio = DateTime.now().toLocal();
      final hoyInicioUtc = DateTime(
        hoyInicio.year,
        hoyInicio.month,
        hoyInicio.day,
      ).toUtc().toIso8601String();

      final resultado = await Supabase.instance.client
          .from('eventos_panico')
          .select('id')
          .eq('disparado_por_id', widget.usuario['id'])
          .eq('rol_disparador', 'movil')
          .gte('created_at', hoyInicioUtc)
          .limit(1);

      if (mounted) {
        setState(() => _panicoUsadoHoy = (resultado as List).isNotEmpty);
      }
    } catch (_) {}
  }

  Future<void> _dispararPanico() async {
    try {
      final yo = widget.usuario;

      // Capturamos la última posición conocida para compartirla 24h
      // con todos los receptores — más oportunidad de ubicar al
      // móvil si pasa lo peor.
      final pos = _ultimaPosicionConocida;
      final ahoraUtc = DateTime.now().toUtc();
      final expiraUtc = ahoraUtc.add(const Duration(hours: 24));

      final insertado = await Supabase.instance.client
          .from('eventos_panico')
          .insert({
            'disparado_por_id': yo['id'],
            'disparado_por_nombre': yo['nombre'],
            'disparado_por_usuario': yo['usuario'],
            'rol_disparador': yo['rol'] ?? 'movil',
            'tipo': 'global',
            if (pos != null) 'ultima_lat': pos.latitude,
            if (pos != null) 'ultima_lng': pos.longitude,
            if (pos != null)
              'ubicacion_actualizada_at': ahoraUtc.toIso8601String(),
            if (pos != null) 'ubicacion_expira_at': expiraUtc.toIso8601String(),
          })
          .select('id')
          .single();

      // Activamos el compartido en vivo: el GPS tracker (siempre activo)
      // alimentará este evento con cada nueva posición durante 24h.
      if (pos != null) {
        _eventoPanicoActivoId = insertado['id'] as int;
        _panicoUbicacionExpiraAt = expiraUtc;
      }

      // Push a Central/Master siempre (sin filtro en_linea — ellos no lo usan)
      // + todos los móviles que estén en línea. Excluir suspendidos en ambos casos.
      final centralesYMasters = await Supabase.instance.client
          .from('usuarios')
          .select('id')
          .inFilter('rol', ['central', 'master'])
          .eq('activo', true)
          .neq('suspendido', true);

      final movilesEnLinea = await Supabase.instance.client
          .from('usuarios')
          .select('id')
          .eq('rol', 'movil')
          .eq('en_linea', true)
          .neq('suspendido', true);

      final ids = [
        ...centralesYMasters.map((u) => u['id'].toString()),
        ...movilesEnLinea.map((u) => u['id'].toString()),
      ].where((id) => id != yo['id'].toString()).toSet().toList();

      if (ids.isNotEmpty) {
        await MotorNotificaciones.dispararRafa(
          idsDestinos: ids,
          titulo: '🚨 ALERTA DE PÁNICO',
          mensaje:
              '${yo['nombre']} (${(yo['usuario'] ?? '').toString().toUpperCase()}) activó la alerta de emergencia. Revisa tu situación.',
          urgente: true,
          sonido: Sonidos.panico,
        );
      }

      // Marcar como usado hoy — el botón desaparece hasta mañana
      if (mounted) setState(() => _panicoUsadoHoy = true);

      // Confirmación discreta — solo para quien disparó.
      // Sin colores de alarma: en una situación crítica, no debe
      // delatar al usuario frente a terceros mirando su pantalla.
      if (mounted) mostrarConfirmacionDiscreta(context);
    } catch (e) {
      debugPrint('_dispararPanico: $e');
    }
  }

  // --- DETENER MI PROPIA ALERTA — antes de que se cumplan las 24h ---
  // Sin esto, la única forma de que el compartido de ubicación parara
  // era esperar la ventana completa de 24h — las alertas se podían
  // acumular sin cerrarse nunca de verdad.
  //
  // silencioso=true: usado por el auto-cierre (ver abajo) cuando el
  // sistema detecta que el moto ya está trabajando con normalidad
  // (aceptó un servicio o se registró en un paradero) — eso por sí
  // solo es una señal fuerte de que la emergencia ya pasó. No pide
  // confirmación ni interrumpe el flujo en el que está, solo avisa
  // con un toast discreto.
  Future<void> _detenerMiAlertaPanico({bool silencioso = false}) async {
    if (_eventoPanicoActivoId == null) return;

    if (!silencioso) {
      final confirmar = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: const Text('¿Detener tu alerta?'),
          content: const Text(
            'Dejas de compartir tu ubicación en vivo. Solo hazlo si ya '
            'estás bien — Central y los demás móviles dejarán de ver tu '
            'posición a partir de ahora.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Seguir compartiendo'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green[700]),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(
                'YA ESTOY BIEN',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      );
      if (confirmar != true) return;
    }

    final idEvento = _eventoPanicoActivoId!;
    try {
      await Supabase.instance.client
          .from('eventos_panico')
          .update({
            // Expira YA — el campo que el GPS timer y el resto del
            // sistema ya respetan para saber cuándo dejar de compartir.
            'ubicacion_expira_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', idEvento);

      if (mounted) {
        setState(() {
          _eventoPanicoActivoId = null;
          _panicoUbicacionExpiraAt = null;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              silencioso
                  ? '✅ Alerta cerrada automáticamente — ya estás trabajando con normalidad.'
                  : '✅ Alerta detenida. Ya no se comparte tu ubicación.',
            ),
            backgroundColor: Colors.green[700],
          ),
        );
      }
    } catch (e) {
      debugPrint('_detenerMiAlertaPanico: $e');
    }
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

    setState(() => _procesando = true);
    try {
      // 1. Reportar baja en la base de datos (Apagar el radar)
      if (_estaEnLinea) {
        await Supabase.instance.client
            .from('usuarios')
            .update({
              'en_linea': false,
              'paradero_actual': null,
              'ingreso_fila': null,
            })
            .eq('id', widget.usuario['id']);
      }
      _gpsTimer?.cancel();
      _supervisionTimer?.cancel();

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('sesion_usuario_json');
      await prefs.setBool('auto_login', false);

      // 3. Cierre de sesión forzoso en el servidor de Supabase
      try {
        await Supabase.instance.client.auth.signOut();
      } catch (_) {}

      // 4. Redirección absoluta (Mata el historial para que no vuelva a entrar)
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cerrar: $e'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _procesando = false);
      }
    }
  }

  Widget _chipDetalle(String texto, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        texto,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
      ),
    );
  }

  String _formatearMoneda(dynamic monto, {bool mostrarCero = false}) {
    if (monto == null || monto == 0 || monto == 0.0) return mostrarCero ? '\$0' : 'SIN TARIFA';
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

  Future<void> _arranqueSeguro() async {
    // PÁNICO 24H: si la app se cerró/reinició dentro de la ventana de 24h
    // de una alerta propia, retomamos el compartido de ubicación.
    await _restaurarPanicoActivo();

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      if (_estaEnLinea) {
        await Supabase.instance.client
            .from('usuarios')
            .update({
              'en_linea': false,
              'paradero_actual': null,
              'ingreso_fila': null,
            })
            .eq('id', widget.usuario['id']);
        if (mounted) {
          setState(() {
            _estaEnLinea = false;
          });
        }
      }
    } else {
      // El GPS arranca si está en línea, O si hay un pánico activo dentro
      // de su ventana de 24h (la ubicación de emergencia no espera turno).
      final compartiendoPanico =
          _eventoPanicoActivoId != null &&
          _panicoUbicacionExpiraAt != null &&
          DateTime.now().toUtc().isBefore(_panicoUbicacionExpiraAt!);

      if (_estaEnLinea || compartiendoPanico) {
        _ultimaActividadUtc = DateTime.now().toUtc();
        _iniciarRastreoGps();
      }
    }
  }

  /// Busca si este usuario disparó un pánico cuya ventana de 24h aún
  /// no expiró, y de ser así, retoma el compartido de ubicación en vivo.
  Future<void> _restaurarPanicoActivo() async {
    try {
      final nowIso = DateTime.now().toUtc().toIso8601String();
      final activo = await Supabase.instance.client
          .from('eventos_panico')
          .select('id, ubicacion_expira_at')
          .eq('disparado_por_id', widget.usuario['id'])
          .eq('rol_disparador', 'movil')
          .not('ubicacion_expira_at', 'is', null)
          .gt('ubicacion_expira_at', nowIso)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (activo != null) {
        _eventoPanicoActivoId = activo['id'] as int;
        _panicoUbicacionExpiraAt = DateTime.parse(
          activo['ubicacion_expira_at'].toString(),
        ).toUtc();
      }
    } catch (e) {
      debugPrint('_restaurarPanicoActivo: $e');
    }
  }

  Future<Position?> _obtenerPosicionSegura() async {
    if (_gpsEnProceso) return null;
    _gpsEnProceso = true;

    try {
      Position? ultima = await Geolocator.getLastKnownPosition();
      if (ultima != null &&
          DateTime.now().difference(ultima.timestamp).inSeconds < 20) {
        _gpsEnProceso = false;
        return ultima;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 7),
        ),
      );
      _gpsEnProceso = false;
      return pos;
    } catch (e) {
      _gpsEnProceso = false;
      return null;
    }
  }

  void _iniciarRastreoGps() {
    _gpsTimer?.cancel();

    late LocationSettings locationSettings;

    if (defaultTargetPlatform == TargetPlatform.android) {
      locationSettings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
        // NOTA: forceLocationManager: true estaba activado antes.
        // Eso desactiva FusedLocationProvider de Google y usa el GPS
        // nativo puro → primera lectura tardaba hasta 60s en frío.
        // Sin el flag, FusedLocationProvider da fix inmediato via red/celda
        // y refina después con GPS. Mucho más rápido al conectarse.
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationText: "ServiExpress está ejecutándose en segundo plano.",
          notificationTitle: "Radar ServiExpress Activo",
          enableWakeLock: true,
        ),
      );
    } else {
      // iOS y Web: LocationSettings genérico (AppleSettings fue removido por incompatibilidad web)
      locationSettings = const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      );
    }

    _gpsTimer = Geolocator.getPositionStream(locationSettings: locationSettings)
        .listen((Position? pos) async {
          if (pos != null && _estaEnLinea) {
            _ultimaPosicionConocida = pos; // <-- RADAR ACTUALIZADO
            try {
              await Supabase.instance.client
                  .from('usuarios')
                  .update({'latitud': pos.latitude, 'longitud': pos.longitude})
                  .eq('id', widget.usuario['id']);
            } catch (e) {}

            // --- EXPULSIÓN AUTOMÁTICA POR GEOCERCA ---
            // Si estoy registrado en un paradero y me alejo de su zona,
            // salgo solo de la fila — sin tocar ningún botón. Evita que
            // alguien se quede "fantasma" ocupando un puesto en la fila
            // mientras ya está lejos atendiendo otra cosa.
            if (_miParaderoCache != null &&
                _kZonasParadero.containsKey(_miParaderoCache)) {
              final zona = _kZonasParadero[_miParaderoCache]!;
              final distancia = Geolocator.distanceBetween(
                pos.latitude,
                pos.longitude,
                zona[0],
                zona[1],
              );
              // Margen de 50m extra sobre el radio de entrada — evita
              // que el GPS oscilando justo en el borde expulse y
              // re-registre en bucle.
              if (distancia > zona[2] + 50) {
                final paraderoQueDejo = _miParaderoCache!;
                _miParaderoCache = null;
                try {
                  await Supabase.instance.client
                      .from('usuarios')
                      .update({'paradero_actual': null, 'ingreso_fila': null})
                      .eq('id', widget.usuario['id']);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          '📍 Saliste del área de $paraderoQueDejo — te '
                          'sacamos de la fila automáticamente.',
                        ),
                        backgroundColor: Colors.orange,
                        duration: const Duration(seconds: 4),
                      ),
                    );
                  }
                } catch (_) {
                  // Si falla el guardado, restauramos la caché para
                  // reintentar en el próximo tick de GPS.
                  _miParaderoCache = paraderoQueDejo;
                }
              }
            }
          } else if (pos != null) {
            // Aunque esté offline, igual guardamos la última posición
            // conocida — la necesitamos para el compartido de pánico.
            _ultimaPosicionConocida = pos;
          }

          // --- COMPARTIDO DE PÁNICO 24H ---
          // Si hay un evento de pánico activo y la ventana de 24h no ha
          // expirado, también actualizamos su ubicación en tiempo real.
          // Esto corre SIEMPRE, sin importar si el móvil está en línea —
          // en una emergencia real, la ubicación debe seguir reportándose.
          if (pos != null &&
              _eventoPanicoActivoId != null &&
              _panicoUbicacionExpiraAt != null) {
            if (DateTime.now().toUtc().isBefore(_panicoUbicacionExpiraAt!)) {
              try {
                await Supabase.instance.client
                    .from('eventos_panico')
                    .update({
                      'ultima_lat': pos.latitude,
                      'ultima_lng': pos.longitude,
                      'ubicacion_actualizada_at': DateTime.now()
                          .toUtc()
                          .toIso8601String(),
                    })
                    .eq('id', _eventoPanicoActivoId!);
              } catch (_) {}
            } else {
              // La ventana de 24h expiró — dejamos de compartir
              _eventoPanicoActivoId = null;
              _panicoUbicacionExpiraAt = null;
            }
          }
        });
  }

  Future<void> _intentarRegistroParadero() async {
    if (!_estaEnLinea) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '⚠️ Debes estar EN LÍNEA antes de registrarte en un paradero.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ Activa el GPS del teléfono primero.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '⚠️ Permiso de ubicación denegado. Actívalo en Ajustes del teléfono.',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    setState(() => _procesando = true);
    try {
      // Reutiliza la posición del radar activo antes de pedir GPS de nuevo
      Position? pos = _ultimaPosicionConocida;
      if (pos == null ||
          DateTime.now().difference(pos.timestamp).inSeconds > 45) {
        pos = await _obtenerPosicionSegura();
      }
      if (pos == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                '⏳ Escaneando satélites. Espera unos segundos e intenta de nuevo.',
              ),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      final hora = DateTime.now().hour;
      String? nuevoParadero;

      // 1. Calculamos la distancia a tu casa (Polígono de pruebas)
      final casa = _kZonasParadero['BASE CASA']!;
      double distCasa = Geolocator.distanceBetween(
        pos.latitude,
        pos.longitude,
        casa[0],
        casa[1],
      );

      // 2. Evaluamos primero tu casa. Si estás a menos de 200m, entras directo.
      if (distCasa <= casa[2]) {
        nuevoParadero = 'BASE CASA';
      }
      // 3. Si no estás en tu casa, evalúa los paraderos reales
      else if (hora >= 6 &&
          Geolocator.distanceBetween(
                pos.latitude,
                pos.longitude,
                _kZonasParadero['EXPUENTE']![0],
                _kZonasParadero['EXPUENTE']![1],
              ) <=
              _kZonasParadero['EXPUENTE']![2]) {
        nuevoParadero = 'EXPUENTE';
      } else if (hora >= 16 &&
          Geolocator.distanceBetween(
                pos.latitude,
                pos.longitude,
                _kZonasParadero['MEMOS']![0],
                _kZonasParadero['MEMOS']![1],
              ) <=
              _kZonasParadero['MEMOS']![2]) {
        // Horario ampliado: 4:00pm a 11:59pm (antes 6:00pm-10:59pm).
        // No hace falta tope superior — la hora vuelve a 0 a medianoche,
        // así que "hora >= 16" ya cubre exactamente hasta las 11:59pm.
        nuevoParadero = 'MEMOS';
      } else if (hora < 6 &&
          Geolocator.distanceBetween(
                pos.latitude,
                pos.longitude,
                _kZonasParadero['NOCTURNO']![0],
                _kZonasParadero['NOCTURNO']![1],
              ) <=
              _kZonasParadero['NOCTURNO']![2]) {
        nuevoParadero = 'NOCTURNO';
      }

      if (nuevoParadero != null) {
        // Verificar si el móvil tiene Ticket de Prioridad por Punto a Punto
        final perfilActual = await Supabase.instance.client
            .from('usuarios')
            .select('ticket_prioridad')
            .eq('id', widget.usuario['id'])
            .single();
        final bool tieneTicket = perfilActual['ticket_prioridad'] == true;

        await Supabase.instance.client
            .from('usuarios')
            .update({
              'paradero_actual': nuevoParadero,
              // Con ticket: fecha antigua → queda #1 en el ordenamiento por tiempo
              'ingreso_fila': tieneTicket
                  ? '2000-01-01T00:00:00Z'
                  : DateTime.now().toUtc().toIso8601String(),
            })
            .eq('id', widget.usuario['id']);
        _miParaderoCache = nuevoParadero; // sincroniza la caché de geocerca

        // AUTO-CIERRE DE PÁNICO: registrarse en un paradero para seguir
        // trabajando es otra señal fuerte de que la emergencia ya pasó.
        if (_eventoPanicoActivoId != null) {
          _detenerMiAlertaPanico(silencioso: true);
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                tieneTicket
                    ? '🎟️ ¡PRIORIDAD ACTIVA! Quedaste #1 en $nuevoParadero (Punto a Punto)'
                    : '📍 Registrado en la fila: $nuevoParadero',
              ),
              backgroundColor: tieneTicket ? Colors.purple : Colors.blue[800],
              duration: Duration(seconds: tieneTicket ? 5 : 3),
            ),
          );
          _sonidos.reproducirSuave(Sonidos.movilParadero);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                '⚠️ DENEGADO: No estás dentro del área de un paradero activo en este horario.',
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al registrarse en el paradero: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  Future<void> _salirDelParadero() async {
    setState(() => _procesando = true);
    try {
      await Supabase.instance.client
          .from('usuarios')
          .update({'paradero_actual': null, 'ingreso_fila': null})
          .eq('id', widget.usuario['id']);
      _miParaderoCache = null; // sincroniza la caché de geocerca
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🚶 Has salido de la fila.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al salir: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  Future<void> _abrirNavegadorSatelital(
    Map<String, dynamic> servicio,
    bool haciaOrigen,
  ) async {
    setState(() => _procesando = true);
    try {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🛰️ Localizando objetivo...'),
            duration: Duration(seconds: 1),
          ),
        );
      }

      double? lat = haciaOrigen
          ? (servicio['origen_lat'] as num?)?.toDouble()
          : (servicio['destino_lat'] as num?)?.toDouble();
      double? lng = haciaOrigen
          ? (servicio['origen_lng'] as num?)?.toDouble()
          : (servicio['destino_lng'] as num?)?.toDouble();
      String textoDireccion = haciaOrigen ? servicio['origen'] : servicio['destino'];

      Uri url;

      if (lat != null && lng != null) {
        // URL limpia — un solo '?', el resto con '&'. La versión
        // anterior tenía un '?' duplicado a mitad de la cadena, lo
        // cual es una URL inválida.
        url = Uri.parse(
          'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving',
        );
      } else {
        // FIX: antes, aunque el geocodificador SÍ encontrara
        // coordenadas, el link seguía armándose con las variables
        // originales $lat,$lng — que en este punto siguen siendo
        // null porque estamos en la rama "sin coordenadas guardadas".
        // Por eso aparecía "Null" incluso cuando debería haber
        // funcionado. Ahora usa coords consistentemente.
        final coords = await MotorRutas.obtenerCoordenadas(textoDireccion);
        if (coords != null &&
            coords['lat'] != null &&
            coords['lng'] != null) {
          url = Uri.parse(
            'https://www.google.com/maps/dir/?api=1&destination=${coords['lat']},${coords['lng']}&travelmode=driving',
          );
        } else {
          // Último recurso: que Google Maps busque por el texto tal
          // cual, ya que no hay ninguna coordenada disponible.
          url = Uri.parse(
            'https://www.google.com/maps/dir/?api=1&destination=${Uri.encodeComponent(textoDireccion)}&travelmode=driving',
          );
        }
      }

      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                '⚠️ No se pudo abrir Google Maps. Verifique que esté instalado.',
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error de ruteo: $e')));
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  void _iniciarRelojSupervisionMultitarea() {
    _supervisionTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      // OPTIMIZADO: solo notificamos al radar (ValueListenableBuilder),
      // sin reconstruir toda la pantalla con setState(() {}).
      // El ban check se movió al timer de 30s para no hacer 12 queries/min.
      if (mounted) _radarTick.value++;

      // 3. Control de Inactividad (80 min desconecta, 60 min avisa)
      if (_estaEnLinea && _serviciosActivosData.isEmpty) {
        final inactividad = DateTime.now()
            .toUtc()
            .difference(_ultimaActividadUtc)
            .inMinutes;
        if (inactividad >= 80) {
          _autoDesconectarPorInactividad();
          return;
        } else if (inactividad >= 60 && !_alertaInactividadMostrada) {
          _alertaInactividadMostrada = true;
          _mostrarAlertaSigoActivo();
        }
      } else if (_estaEnLinea && _serviciosActivosData.isNotEmpty) {
        _ultimaActividadUtc = DateTime.now().toUtc();
        _alertaInactividadMostrada = false;
      }

      // 4. Supervisión estricta de demoras en pedidos activos
      if (_serviciosActivosData.isNotEmpty) {
        for (var servicio in _serviciosActivosData) {
          if (servicio['estado'] != 'en_ruta_destino' || servicio['picked_up_at'] == null)
            continue;

          final int id = servicio['id'];
          final pickedUpUtc = DateTime.parse(servicio['picked_up_at']).toUtc();
          final elapsed = DateTime.now()
              .toUtc()
              .difference(pickedUpUtc)
              .inMinutes;
          final extension = servicio['extension_minutes'] as int? ?? 0;
          final efectivos = elapsed - extension;
          final tiempoMeta = servicio['tiempo_estimado_minutos'] ?? 15;

          if (efectivos >= tiempoMeta - 2 &&
              efectivos < tiempoMeta &&
              !(_alertasPrecaucion[id] ?? false)) {
            _alertasPrecaucion[id] = true;
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    '⚠️ Tiempo de entrega casi expirado para Orden #${servicio['numero_movil'] ?? id}.',
                  ),
                  backgroundColor: Colors.orange[800],
                ),
              );
            }
          }
        }
      }
    });
  }

  void _ejecutarSuspensionInmediata() {
    _gpsTimer?.cancel();
    setState(() {
      _estaEnLinea = false;
    });
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Colors.red, width: 2),
        ),
        title: const Text(
          '🛑 SUSPENSIÓN INMEDIATA',
          style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'La Central acaba de revocar tu acceso disciplinariamente. Quedas fuera de servicio inmediatamente.',
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.black),
            onPressed: () => Navigator.pop(context),
            child: const Text('ENTENDIDO', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  // Avisa al moto cuando Central le levanta la suspensión — sea
  // manual o automática por vencimiento de tiempo. Sin esto, el moto
  // se quedaba "ciego": solo se enteraba si intentaba conectarse de
  // nuevo por su cuenta, sin que nadie le avisara que ya podía.
  void _notificarSuspensionLevantada() {
    if (!mounted) return;
    _sonidos.reproducir(Sonidos.alerta);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0xff3AF500), width: 2),
        ),
        title: const Text(
          '✅ SUSPENSIÓN LEVANTADA',
          style: TextStyle(
            color: Color(0xff3AF500),
            fontWeight: FontWeight.bold,
          ),
        ),
        content: const Text(
          'La Central restauró tu acceso. Ya puedes conectarte y volver '
          'a recibir servicios con normalidad.',
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.black),
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'ENTENDIDO',
              style: TextStyle(color: Color(0xff3AF500)),
            ),
          ),
        ],
      ),
    );
  }

  void _mostrarAlertaSigoActivo() {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.orange[800]!, width: 2.5),
        ),
        title: Text(
          '⚠️ REPORTE DE ACTIVIDAD',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.orange[800],
          ),
        ),
        content: const Text(
          'Llevas 60 minutos sin tomar servicios. ¿Sigues disponible?',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _autoDesconectarPorInactividad();
            },
            child: const Text(
              'DESCONECTARME',
              style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.black),
            onPressed: () {
              setState(() {
                _ultimaActividadUtc = DateTime.now().toUtc();
                _alertaInactividadMostrada = false;
              });
              Navigator.pop(context);
            },
            child: const Text(
              'SIGO ACTIVO',
              style: TextStyle(
                color: Color(0xff3AF500),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _autoDesconectarPorInactividad() async {
    _alertaInactividadMostrada = false;
    try {
      await Supabase.instance.client
          .from('usuarios')
          .update({
            'en_linea': false,
            'paradero_actual': null,
            'ingreso_fila': null,
          })
          .eq('id', widget.usuario['id']);
      if (mounted) {
        setState(() {
          _estaEnLinea = false;
        });
        // Cerrar el diálogo de REPORTE DE ACTIVIDAD si sigue abierto —
        // sin esto el moto puede tocar "SIGO ACTIVO" después del corte
        // y el timer se resetea aunque Supabase ya lo desconectó.
        if (Navigator.of(context).canPop()) Navigator.of(context).pop();
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text(
              '⚠️ DESCONEXIÓN AUTOMÁTICA',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
            content: const Text(
              'El sistema te ha desconectado tras 80 minutos de inactividad total.',
            ),
            actions: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.black),
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  'ENTENDIDO',
                  style: TextStyle(color: Color(0xff3AF500)),
                ),
              ),
            ],
          ),
        );
      }
    } catch (e) {}
  }

  Future<void> _cambiarEstado() async {
    if (_serviciosActivosData.isNotEmpty && _estaEnLinea) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Error: Tienes servicios activos. Finalízalos primero.',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (!_estaEnLinea) {
      final userCheck = await Supabase.instance.client
          .from('usuarios')
          .select('suspendido')
          .eq('id', widget.usuario['id'])
          .maybeSingle();
      if (userCheck != null && userCheck['suspendido'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '⚠️ ACCESO DENEGADO: Estás suspendido por la Central.',
            ),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('⚠️ Activa el GPS del teléfono primero.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied ||
            permission == LocationPermission.deniedForever) {
          return;
        }
      }
    }

    setState(() => _procesando = true);
    try {
      final nuevoEstado = !_estaEnLinea;
      await Supabase.instance.client
          .from('usuarios')
          .update({
            'en_linea': nuevoEstado,
            'paradero_actual': null,
            'ingreso_fila': null,
          })
          .eq('id', widget.usuario['id']);
      _miParaderoCache = null; // sincroniza la caché de geocerca

      // PARADERO FLASH: al conectarse, refrescamos la lista de usuarios y servicios
      // via REST de inmediato — sin esperar al WebSocket (~2-5s).
      // Esto es crítico: el lugar en la fila depende de quién cargó primero.
      // El refresh de servicios también elimina el spinner de 20s en el radar.
      if (nuevoEstado) {
        Supabase.instance.client
            .from('usuarios')
            .select()
            .eq('rol', 'movil')
            .then((data) {
              if (!_ctrlUsuarios.isClosed) _ctrlUsuarios.add(data);
            })
            .catchError((_) {});
        Supabase.instance.client
            .from('servicios')
            .select()
            .inFilter('estado', [
              'pendiente',
              'en_ruta_origen',
              'en_origen',
              'en_ruta_destino',
              'problema',
            ])
            .order('id', ascending: false)
            .limit(50)
            .then((data) {
              _cacheServicios = List<Map<String, dynamic>>.from(data);
              if (!_ctrlServicios.isClosed) _ctrlServicios.add(_cacheServicios!);
            })
            .catchError((_) {});
      }

      setState(() {
        _estaEnLinea = nuevoEstado;
        if (nuevoEstado) {
          _ultimaActividadUtc = DateTime.now().toUtc();
          _alertaInactividadMostrada = false;
          _iniciarRastreoGps();
        } else {
          // PÁNICO 24H: si hay una alerta activa dentro de su ventana de
          // 24h, el GPS sigue corriendo aunque el móvil se marque offline.
          // La ubicación de emergencia no se detiene por un toggle de turno.
          final compartiendoPanico =
              _eventoPanicoActivoId != null &&
              _panicoUbicacionExpiraAt != null &&
              DateTime.now().toUtc().isBefore(_panicoUbicacionExpiraAt!);

          if (!compartiendoPanico) {
            _gpsTimer?.cancel();
          }
        }
      });
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      setState(() => _procesando = false);
    }
  }

  void _abrirMenuProrroga(
    BuildContext context,
    int servicioId,
    int minutosActuales,
  ) {
    String motivo = 'Pedido retrasado en cocina / preparación';
    final detalle = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            'PRÓRROGA (+15M) | #$servicioId',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.blue,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButton<String>(
                value: motivo,
                isExpanded: true,
                items:
                    [
                          'Pedido retrasado en cocina / preparación',
                          'Tráfico pesado / Lluvia',
                          'Retraso por requisa / retén',
                          'Dirección compleja',
                          'Incidente menor',
                        ]
                        .map(
                          (String v) => DropdownMenuItem(
                            value: v,
                            child: Text(
                              v,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        )
                        .toList(),
                onChanged: (val) {
                  if (val != null) setDialogState(() => motivo = val);
                },
              ),
              TextField(
                controller: detalle,
                decoration: const InputDecoration(
                  labelText: 'Detalle para Central',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CANCELAR'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue[800],
              ),
              onPressed: () async {
                final arg = detalle.text.trim().isEmpty
                    ? motivo
                    : '$motivo: ${detalle.text.trim()}';
                await Supabase.instance.client
                    .from('servicios')
                    .update({
                      'extension_minutes': minutosActuales + 15,
                      'observacion': 'PRÓRROGA | $arg',
                    })
                    .eq('id', servicioId);
                _ultimaActividadUtc = DateTime.now().toUtc();
                if (context.mounted) Navigator.pop(context);
              },
              child: Text(
                'ENVIAR',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _abrirMenuJustificacion(BuildContext context, int servicioId) {
    final detalle = TextEditingController();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text(
          '⚠️ DEMORA EXCEDIDA',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Superaste el tiempo del satélite. Si no solicitaste prórroga a tiempo, el sistema descontará -2 puntos de tu récord. Ingresa el motivo forzoso para auditar:',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: detalle,
              decoration: const InputDecoration(
                labelText: 'Justificación requerida',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('VOLVER A LA RUTA'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red[900]),
            onPressed: () async {
              if (detalle.text.trim().length < 5) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Escribe una excusa real.')),
                );
                return;
              }
              _alertasPrecaucion.remove(servicioId);

              // La calificación se recalcula automáticamente al calificar en local_screen
              // (suma += 1.0 para servicios demorados). No se manipula directamente aquí.
              await Supabase.instance.client
                  .from('servicios')
                  .update({
                    'estado': 'finalizado_por_demora',
                    'observacion':
                        'FINALIZADO CON DEMORA | Excusa: ${detalle.text.trim()}',
                  })
                  .eq('id', servicioId);

              MotorNotificaciones.dispararACentral(
                titulo: '⚠️ SERVICIO DEMORADO',
                mensaje:
                    '${widget.usuario['nombre']} cerró el servicio #$servicioId con demora.',
                urgente: true,
                sonido: 'central_demora',
              );

              _ultimaActividadUtc = DateTime.now().toUtc();
              if (context.mounted) Navigator.pop(context);
            },
            child: Text(
              'ENVIAR Y CERRAR',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _iniciarRutaDestino(Map<String, dynamic> servicio) async {
    setState(() => _procesando = true);
    try {
      Position? pos = await _obtenerPosicionSegura();
      int tiempoCalculado = 15;

      if (pos != null) {
        if (servicio['destino_lat'] != null && servicio['destino_lng'] != null) {
          final ruta = await MotorRutas.calcularRuta(
            latOrigen: pos.latitude,
            lngOrigen: pos.longitude,
            latDestino: (servicio['destino_lat'] as num).toDouble(),
            lngDestino: (servicio['destino_lng'] as num).toDouble(),
          );
          if (ruta != null) tiempoCalculado = ruta['tiempo_minutos'] as int;
        } else {
          final destCoords = await MotorRutas.obtenerCoordenadas(
            servicio['destino'],
          );
          if (destCoords != null) {
            final ruta = await MotorRutas.calcularRuta(
              latOrigen: pos.latitude,
              lngOrigen: pos.longitude,
              latDestino: destCoords['lat']!,
              lngDestino: destCoords['lng']!,
            );
            if (ruta != null) tiempoCalculado = ruta['tiempo_minutos'] as int;
          }
        }
        tiempoCalculado += 5;
      }

      _sonidos.reproducirSuave(Sonidos.movilConfirmar); // Iniciando ruta
      await Supabase.instance.client
          .from('servicios')
          .update({
            'estado': 'en_ruta_destino',
            'picked_up_at': DateTime.now().toUtc().toIso8601String(),
            'tiempo_estimado_minutos': tiempoCalculado,
          })
          .eq('id', servicio['id']);

      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('⏱️ Tiempo Límite Satelital: $tiempoCalculado min'),
            backgroundColor: Colors.black,
          ),
        );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  Future<void> _finalizarServicio(
    Map<String, dynamic> servicio,
    bool tieneProblema,
  ) async {
    final int servicioId = servicio['id'];
    _alertasPrecaucion.remove(servicioId);
    setState(() => _serviciosOcultosLocales.add(servicioId));

    try {
      if (!tieneProblema)
        _sonidos.reproducirSuave(Sonidos.movilConfirmar); // Servicio completado

      await Supabase.instance.client
          .from('servicios')
          .update({
            'estado': tieneProblema ? 'finalizado_con_problema' : 'finalizado',
          })
          .eq('id', servicioId);

      // Aprendizaje silencioso del directorio — solo en cierres
      // limpios. Un "finalizado_con_problema" no representa una
      // entrega real confirmada en el destino.
      if (!tieneProblema) {
        _intentarAprenderLugar(
          textoDireccion: servicio['destino'],
          latReclamada: (servicio['destino_lat'] as num?)?.toDouble(),
          lngReclamada: (servicio['destino_lng'] as num?)?.toDouble(),
        );
      }

      if (tieneProblema) {
        MotorNotificaciones.dispararACentral(
          titulo: '🚨 SERVICIO CON PROBLEMA',
          mensaje:
              '${widget.usuario['nombre']} cerró el servicio #$servicioId con PROBLEMA.',
          urgente: true,
          sonido: 'central_problema',
        );
      }

      if (!tieneProblema && servicio['es_punto_a_punto'] == true) {
        await Supabase.instance.client
            .from('usuarios')
            .update({'ticket_prioridad': true})
            .eq('id', widget.usuario['id']);
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                '🎟️ ¡PUNTO A PUNTO COMPLETADO! Ganaste un Ticket de Prioridad.',
              ),
              backgroundColor: Colors.purple,
              duration: Duration(seconds: 4),
            ),
          );
      }

      _ultimaActividadUtc = DateTime.now().toUtc();
    } catch (e) {
      if (mounted) setState(() => _serviciosOcultosLocales.remove(servicioId));
    }
  }

  void _mostrarMenuProblema(BuildContext context, int servicioId) {
    String opcion = 'Pinchado / Avería Mecánica';
    final detalle = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            'NOVEDAD | #$servicioId',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.red,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButton<String>(
                value: opcion,
                isExpanded: true,
                items:
                    [
                          'Pinchado / Avería Mecánica',
                          'Accidente / Tránsito',
                          'Cliente no responde',
                          'Dirección Errada',
                          'Otro',
                        ]
                        .map(
                          (String v) => DropdownMenuItem(
                            value: v,
                            child: Text(
                              v,
                              style: const TextStyle(fontSize: 14),
                            ),
                          ),
                        )
                        .toList(),
                onChanged: (val) {
                  if (val != null) setDialogState(() => opcion = val);
                },
              ),
              TextField(
                controller: detalle,
                decoration: const InputDecoration(
                  labelText: 'Detalles (Opcional)',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CANCELAR'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red[800]),
              onPressed: () async {
                final text = detalle.text.trim().isEmpty
                    ? opcion
                    : '$opcion: ${detalle.text.trim()}';
                await Supabase.instance.client
                    .from('servicios')
                    .update({'estado': 'problema', 'observacion': text})
                    .eq('id', servicioId);
                _ultimaActividadUtc = DateTime.now().toUtc();
                if (context.mounted) Navigator.pop(context);
              },
              child: Text(
                'REPORTAR',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- PANEL DE PERFIL OPERATIVO ---
  // =========================================================================
  // PESTAÑA DE PERFIL — rediseño completo
  // =========================================================================
  // Antes: un diálogo modal que solo mostraba rango/calificación +
  // teléfono + métodos de pago. Todo lo nuevo del registro (correo,
  // fecha de nacimiento, usuario) nunca llegaba a mostrarse en ningún
  // lado. Ahora es su propia pestaña, completa: identidad, datos
  // personales, contacto editable, rango y beneficios, documentos
  // (próximamente), y las acciones de cuenta que antes vivían
  // amontonadas en el AppBar (Ranking, Cerrar sesión).
  Widget _construirPerfilTab() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _streamUsuarios,
      builder: (context, snap) {
        final miPerfil = snap.hasData
            ? snap.data!.firstWhere(
                (u) => u['id'] == widget.usuario['id'],
                orElse: () => widget.usuario,
              )
            : widget.usuario;

        final String rango =
            miPerfil['rango_movil']?.toString().toUpperCase() ?? 'NOVATO';
        final dynamic calRaw = miPerfil['puntuacion'];
        final String calTexto = calRaw == null
            ? 'Sin calificar'
            : '★ ${(calRaw as num).toDouble().toStringAsFixed(1)}';
        final Color colorRango = rango == 'MASTER'
            ? const Color(0xFFE040FB)
            : rango == 'LEYENDA'
                ? const Color(0xFFFF9800)
                : rango == 'ELITE'
                    ? const Color(0xFF2196F3)
                    : rango == 'PRO'
                        ? const Color(0xFF4CAF50)
                        : Colors.white54;
        final String usuario = miPerfil['usuario']?.toString() ?? '';
        final String numeroAvatar =
            RegExp(r'\d+').firstMatch(usuario)?.group(0) ?? '?';

        String fechaNacTexto = 'No registrada';
        int? edadCalculada;
        if (miPerfil['fecha_nacimiento'] != null) {
          try {
            final f = DateTime.parse(miPerfil['fecha_nacimiento'].toString());
            fechaNacTexto =
                '${f.day.toString().padLeft(2, '0')}/${f.month.toString().padLeft(2, '0')}/${f.year}';
            final hoy = DateTime.now();
            edadCalculada = hoy.year - f.year;
            if (hoy.month < f.month ||
                (hoy.month == f.month && hoy.day < f.day)) {
              edadCalculada--;
            }
          } catch (_) {}
        }

        return Container(
          color: Colors.grey[200],
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              // --- CABECERA: avatar + nombre + rango + calificación ---
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 28),
                decoration: const BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(28),
                    bottomRight: Radius.circular(28),
                  ),
                ),
                child: Column(
                  children: [
                    GestureDetector(
                      onTap: _subiendoFoto
                          ? null
                          : () => _cambiarFotoPerfil(miPerfil['id']),
                      child: Stack(
                        children: [
                          CircleAvatar(
                            radius: 38,
                            backgroundColor: colorRango,
                            backgroundImage:
                                (miPerfil['foto_perfil_url'] != null &&
                                    miPerfil['foto_perfil_url']
                                        .toString()
                                        .isNotEmpty)
                                ? NetworkImage(
                                    miPerfil['foto_perfil_url'].toString(),
                                  )
                                : null,
                            child:
                                (miPerfil['foto_perfil_url'] == null ||
                                    miPerfil['foto_perfil_url']
                                        .toString()
                                        .isEmpty)
                                ? Text(
                                    numeroAvatar,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 28,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  )
                                : null,
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              padding: const EdgeInsets.all(5),
                              decoration: BoxDecoration(
                                color: const Color(0xff3AF500),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.black,
                                  width: 2,
                                ),
                              ),
                              child: _subiendoFoto
                                  ? const SizedBox(
                                      width: 12,
                                      height: 12,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.black,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.camera_alt,
                                      size: 14,
                                      color: Colors.black,
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      (miPerfil['nombre'] ?? '').toString().toUpperCase(),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '@$usuario',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: colorRango.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: colorRango),
                          ),
                          child: Text(
                            '🏆 $rango',
                            style: TextStyle(
                              color: colorRango,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            calTexto,
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // 1. PRODUCCIÓN — cargado en initState, sin parpadeo
              Container(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.grey[200]!),
                ),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                      child: Row(
                        children: [
                          Icon(Icons.bar_chart, size: 14, color: Colors.black54),
                          const SizedBox(width: 6),
                          const Text('PRODUCCIÓN', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black45, letterSpacing: 0.8)),
                        ],
                      ),
                    ),
                    // Fila compacta: ícono + label + número + producido hoy alineados
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Icon(Icons.today, size: 16, color: Colors.grey[500]),
                          const SizedBox(width: 8),
                          Text('Hoy', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                          const SizedBox(width: 8),
                          Text('$_serviciosHoy', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black87)),
                          const Spacer(),
                          Text(
                            _formatearMoneda(_producidoHoy, mostrarCero: true),
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.green[700]),
                          ),
                        ],
                      ),
                    ),
                    Divider(height: 1, color: Colors.grey[100]),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Icon(Icons.check_circle_outline, size: 16, color: Colors.grey[500]),
                          const SizedBox(width: 8),
                          Text('Total', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                          const SizedBox(width: 8),
                          Text('$_serviciosTotal', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black87)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // 2. RANGO Y BENEFICIOS — desplegable, Master oculto para no-masters
              _seccionPerfilDesplegable(
                titulo: 'RANGO Y BENEFICIOS',
                icono: Icons.emoji_events_outlined,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                          decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(6)),
                          child: const Row(
                            children: [
                              Expanded(flex: 4, child: Text('Rango', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black45, letterSpacing: 0.4))),
                              Expanded(flex: 3, child: Text('Cal.', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black45, letterSpacing: 0.4))),
                              Expanded(flex: 3, child: Text('Cupo', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black45, letterSpacing: 0.4))),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),
                        ...() {
                          final esMasterLocal = rango == 'MASTER';
                          final rangosData = [
                            {'nombre': 'NOVATO',  'cal': '3.0–3.5', 'cupo': '1 servicio',      'vip': false, 'color': Colors.grey[600]!},
                            {'nombre': 'PRO',     'cal': '3.6–4.2', 'cupo': '1 servicio',      'vip': false, 'color': const Color(0xFF4CAF50)},
                            {'nombre': 'ELITE',   'cal': '4.3–4.7', 'cupo': '2 servicio',      'vip': false, 'color': const Color(0xFF2196F3)},
                            {'nombre': 'LEYENDA', 'cal': '4.8–5.0', 'cupo': '3 servicio',      'vip': true,  'color': const Color(0xFFFF9800)},
                            // MASTER: solo visible si el propio usuario es Master
                            if (esMasterLocal)
                              {'nombre': 'MASTER', 'cal': '5.0+', 'cupo': 'Sin límite', 'vip': true, 'color': const Color(0xFFE040FB)},
                          ];
                          return rangosData.map<Widget>((r) {
                            final esActual = rango == r['nombre'] as String;
                            final Color c = r['color'] as Color;
                            final bool esVip = r['vip'] as bool;
                            return Container(
                              margin: const EdgeInsets.only(bottom: 4),
                              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                              decoration: BoxDecoration(
                                color: esActual ? c.withValues(alpha: 0.08) : null,
                                borderRadius: BorderRadius.circular(8),
                                border: esActual ? Border.all(color: c.withValues(alpha: 0.5), width: 1.5) : null,
                              ),
                              child: Row(
                                children: [
                                  Expanded(flex: 4, child: Row(children: [
                                    Container(width: 8, height: 8, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
                                    const SizedBox(width: 5),
                                    Flexible(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      Text(r['nombre'] as String, style: TextStyle(fontSize: 11, fontWeight: esActual ? FontWeight.bold : FontWeight.normal, color: esActual ? c : Colors.black87)),
                                      if (esVip) Text('👑 VIP', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: c)),
                                    ])),
                                  ])),
                                  Expanded(flex: 3, child: Text(r['cal'] as String, style: TextStyle(fontSize: 11, color: esActual ? c : Colors.black54, fontWeight: esActual ? FontWeight.bold : FontWeight.normal))),
                                  Expanded(flex: 3, child: Text(r['cupo'] as String, style: const TextStyle(fontSize: 11, color: Colors.black54))),
                                ],
                              ),
                            );
                          }).toList();
                        }(),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF9800).withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFFF9800).withValues(alpha: 0.3)),
                          ),
                          child: const Row(children: [
                            Text('👑', style: TextStyle(fontSize: 13)),
                            SizedBox(width: 6),
                            Expanded(child: Text('Leyenda recibe servicios VIP exclusivos con +\$3.000 de tarifa.', style: TextStyle(fontSize: 10, color: Color(0xFF8a5c00)))),
                          ]),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              // 3. CONTACTO Y PAGO — desplegable
              Builder(
                builder: (bCtx) => Container(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.grey[200]!),
                ),
                child: Theme(
                  data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    leading: const Icon(Icons.contact_phone_outlined, size: 16, color: Colors.black54),
                    title: const Text(
                      'CONTACTO Y PAGO',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.black54,
                        letterSpacing: 0.8,
                      ),
                    ),
                    trailing: const Icon(Icons.expand_more, size: 18, color: Colors.black38),
                    initiallyExpanded: false,
                    childrenPadding: EdgeInsets.zero,
                    onExpansionChanged: (expanded) {
                      if (expanded) {
                        Future.delayed(const Duration(milliseconds: 200), () {
                          Scrollable.ensureVisible(bCtx, duration: const Duration(milliseconds: 400), curve: Curves.easeInOut, alignment: 0.5);
                        });
                      }
                    },
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TextField(
                              controller: _perfilTelefonoCtrl,
                              keyboardType: TextInputType.phone,
                              decoration: const InputDecoration(
                                labelText: 'Teléfono / WhatsApp',
                                prefixIcon: Icon(Icons.phone_android, size: 20),
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.fromLTRB(12, 20, 12, 14),
                              ),
                            ),
                            const SizedBox(height: 14),
                            const Text(
                              'CUENTAS DE PAGO (opcional)',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.black45,
                                letterSpacing: 0.6,
                              ),
                            ),
                            const SizedBox(height: 8),
                            _filaCuentaPago('Nequi', const Color(0xFFE5007D), Colors.white, _perfilNequiCtrl),
                            const SizedBox(height: 8),
                            _filaCuentaPago('Daviplata', const Color(0xFFEE2A24), Colors.white, _perfilDaviplataCtrl),
                            const SizedBox(height: 8),
                            _filaCuentaPago('Bancolombia', const Color(0xFFFFCC00), Colors.black, _perfilBancolombiaCtrl),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.black,
                                  padding: const EdgeInsets.symmetric(vertical: 11),
                                ),
                                onPressed: _guardandoPerfil
                                    ? null
                                    : () => _guardarContactoPerfil(miPerfil['id']),
                                icon: _guardandoPerfil
                                    ? const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(
                                          color: Color(0xff3AF500),
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.save, size: 16, color: Color(0xff3AF500)),
                                label: const Text(
                                  'GUARDAR CAMBIOS',
                                  style: TextStyle(
                                    color: Color(0xff3AF500),
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
                  ),
                ),
              ),
              ),

              // 4. DATOS PERSONALES — desplegable
              _seccionPerfilDesplegable(
                titulo: 'DATOS PERSONALES',
                icono: Icons.badge_outlined,
                children: [
                  _filaDato(Icons.tag, 'Usuario', usuario),
                  _filaDato(
                    Icons.lock_outline,
                    'Contraseña',
                    '••••••••',
                    onEditar: () => _cambiarContrasenaPerfil(miPerfil['id']),
                  ),
                  _filaDato(
                    Icons.cake_outlined,
                    'Nacimiento',
                    edadCalculada != null
                        ? '$fechaNacTexto  ($edadCalculada años)'
                        : fechaNacTexto,
                  ),
                  _filaDato(
                    Icons.email_outlined,
                    'Correo',
                    miPerfil['correo']?.toString() ?? 'No registrado',
                    esUltimo: true,
                    onEditar: () => _cambiarCorreoPerfil(
                      miPerfil['id'],
                      miPerfil['correo']?.toString() ?? '',
                    ),
                  ),
                ],
              ),

              // 5. DOCUMENTOS — desplegable
              Builder(
                builder: (bCtx) => Container(
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.grey[200]!),
                  ),
                  child: Theme(
                    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      leading: const Icon(Icons.folder_outlined, size: 16, color: Colors.black54),
                      title: const Text(
                        'DOCUMENTOS',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black54, letterSpacing: 0.8),
                      ),
                      trailing: const Icon(Icons.expand_more, size: 18, color: Colors.black38),
                      initiallyExpanded: false,
                      childrenPadding: EdgeInsets.zero,
                      onExpansionChanged: (expanded) {
                        if (expanded) {
                          Future.delayed(const Duration(milliseconds: 200), () {
                            Scrollable.ensureVisible(bCtx, duration: const Duration(milliseconds: 400), curve: Curves.easeInOut, alignment: 0.5);
                          });
                        }
                      },
                      children: [
                        _filaDocumentoFuturo(Icons.badge, 'Cédula'),
                        _filaDocumentoFuturo(Icons.motorcycle, 'Licencia de conducción'),
                        _filaDocumentoFuturo(Icons.pin, 'Placa de la moto'),
                        _filaDocumentoFuturo(Icons.shield, 'SOAT'),
                        _filaDocumentoFuturo(Icons.gavel, 'Antecedentes'),
                        _filaDocumentoFuturo(Icons.home_outlined, 'Comprobante de domicilio'),
                        _filaDocumentoFuturo(Icons.people_outline, 'Referencias personales', esUltimo: true),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 8),

              // --- SILENCIAR RADAR (solo Masters) ---
              if (rango == 'MASTER') ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE040FB).withValues(alpha: 0.4)),
                    ),
                    child: SwitchListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      secondary: Icon(
                        miPerfil['silenciar_radar'] == true
                            ? Icons.notifications_off
                            : Icons.notifications_active,
                        color: const Color(0xFFE040FB),
                      ),
                      title: const Text('Silenciar nuevos servicios',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                      subtitle: Text(
                        miPerfil['silenciar_radar'] == true
                            ? 'No recibirás push de nuevos servicios'
                            : 'Recibes push de nuevos servicios (máx 10 activos)',
                        style: const TextStyle(fontSize: 11, color: Colors.black45),
                      ),
                      value: miPerfil['silenciar_radar'] == true,
                      activeColor: const Color(0xFFE040FB),
                      onChanged: (val) async {
                        try {
                          await Supabase.instance.client
                              .from('usuarios')
                              .update({'silenciar_radar': val})
                              .eq('id', widget.usuario['id']);
                        } catch (_) {}
                      },
                    ),
                  ),
                ),
              ],

              // --- MIS CALIFICACIONES (anónimas: el móvil nunca ve el nombre real) ---
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: Supabase.instance.client
                      .from('calificaciones')
                      .select('estrellas, comentario, calificador_tipo, created_at')
                      .eq('movil_id', widget.usuario['id'].toString())
                      .order('created_at', ascending: false),
                  builder: (context, snap) {
                    final califs = snap.data ?? [];
                    final double promedio = califs.isEmpty
                        ? 0.0
                        : califs
                                .map((c) => (c['estrellas'] as num).toDouble())
                                .reduce((a, b) => a + b) /
                            califs.length;

                    return Card(
                      elevation: 0,
                      color: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.grey[200]!),
                      ),
                      child: Theme(
                        data: Theme.of(context)
                            .copyWith(dividerColor: Colors.transparent),
                        child: ExpansionTile(
                          leading: const Icon(Icons.star_rounded,
                              color: Colors.amber),
                          title: const Text(
                            'MIS CALIFICACIONES',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: Colors.black87,
                            ),
                          ),
                          subtitle: califs.isEmpty
                              ? const Text(
                                  'Aún no tienes valoraciones',
                                  style: TextStyle(
                                      fontSize: 11, color: Colors.black45),
                                )
                              : Row(
                                  children: [
                                    Text(
                                      promedio.toStringAsFixed(1),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                        color: Colors.amber,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    ...List.generate(
                                      5,
                                      (i) => Icon(
                                        i < promedio.round()
                                            ? Icons.star
                                            : Icons.star_border,
                                        size: 12,
                                        color: Colors.amber,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '(${califs.length})',
                                      style: const TextStyle(
                                          fontSize: 11, color: Colors.black54),
                                    ),
                                  ],
                                ),
                          children: califs.isEmpty
                              ? [
                                  const Padding(
                                    padding: EdgeInsets.all(16),
                                    child: Text(
                                      'Cuando alguien califique un servicio tuyo, aparecerá aquí.',
                                      style: TextStyle(
                                          color: Colors.black45, fontSize: 12),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ]
                              : califs.map((c) {
                                  final tipo =
                                      c['calificador_tipo']?.toString() ??
                                          'invitado';
                                  final String etiqueta = tipo == 'cliente'
                                      ? 'Cliente'
                                      : tipo == 'local'
                                          ? 'Local'
                                          : 'Invitado';
                                  final int estrellas =
                                      (c['estrellas'] as num).toInt();
                                  final String? comentario =
                                      c['comentario']?.toString();
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 8),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 2),
                                              decoration: BoxDecoration(
                                                color: tipo == 'local'
                                                    ? Colors.blue[50]
                                                    : tipo == 'cliente'
                                                        ? Colors.green[50]
                                                        : Colors.grey[100],
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                etiqueta,
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  color: tipo == 'local'
                                                      ? Colors.blue[700]
                                                      : tipo == 'cliente'
                                                          ? Colors.green[700]
                                                          : Colors.grey[600],
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            ...List.generate(
                                              5,
                                              (i) => Icon(
                                                i < estrellas
                                                    ? Icons.star
                                                    : Icons.star_border,
                                                size: 14,
                                                color: Colors.amber,
                                              ),
                                            ),
                                          ],
                                        ),
                                        if (comentario != null &&
                                            comentario.isNotEmpty) ...[
                                          const SizedBox(height: 4),
                                          Text(
                                            '"$comentario"',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              fontStyle: FontStyle.italic,
                                              color: Colors.black87,
                                            ),
                                          ),
                                        ],
                                        const Divider(height: 16),
                                      ],
                                    ),
                                  );
                                }).toList(),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),

              // --- ACCIONES ---
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    _botonAccionPerfil(
                      icono: Icons.history,
                      color: Colors.blue[800]!,
                      titulo: 'Mi Historial y Producción',
                      onTap: () => _mostrarMiHistorial(context),
                    ),
                    _botonAccionPerfil(
                      icono: Icons.emoji_events,
                      color: const Color(0xff3AF500),
                      colorTexto: Colors.black,
                      titulo: 'Ver mi Ranking',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const RankingScreen(),
                        ),
                      ),
                    ),
                    _botonAccionPerfil(
                      icono: Icons.delete_forever,
                      color: Colors.red[700]!,
                      titulo: 'Eliminar mi cuenta',
                      onTap: () => _eliminarMiCuenta(context),
                    ),
                    _botonAccionPerfil(
                      icono: Icons.power_settings_new,
                      color: Colors.grey[800]!,
                      titulo: 'Cerrar sesión',
                      onTap: _procesando ? null : _cerrarSesionSegura,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }


  Future<void> _cargarProduccion() async {
    try {
      final hoy = DateTime.now();
      final inicioHoy =
          DateTime(hoy.year, hoy.month, hoy.day).toUtc().toIso8601String();
      final total = await Supabase.instance.client
          .from('servicios')
          .select('id')
          .eq('movil_id', widget.usuario['id'])
          .eq('estado', 'finalizado');
      final hoyData = await Supabase.instance.client
          .from('servicios')
          .select('id, tarifa')
          .eq('movil_id', widget.usuario['id'])
          .eq('estado', 'finalizado')
          .gte('created_at', inicioHoy);
      if (mounted) {
        final hoyList = hoyData as List;
        double producido = 0;
        for (final s in hoyList) {
          producido += (s['tarifa'] as num? ?? 0).toDouble();
        }
        setState(() {
          _serviciosTotal = (total as List).length;
          _serviciosHoy = hoyList.length;
          _producidoHoy = producido;
        });
      }
    } catch (_) {}
  }

  // Tarjeta de sección desplegable — misma estructura que _seccionPerfil
  // pero usa ExpansionTile para colapsar/expandir el contenido.
  Widget _seccionPerfilDesplegable({
    required String titulo,
    required IconData icono,
    required List<Widget> children,
    bool initiallyExpanded = false,
  }) {
    return Builder(
      builder: (builderCtx) => Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            leading: Icon(icono, size: 16, color: Colors.black54),
            title: Text(
              titulo,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Colors.black54,
                letterSpacing: 0.8,
              ),
            ),
            trailing: const Icon(Icons.expand_more, size: 18, color: Colors.black38),
            initiallyExpanded: initiallyExpanded,
            childrenPadding: EdgeInsets.zero,
            onExpansionChanged: (expanded) {
              if (expanded) {
                Future.delayed(const Duration(milliseconds: 200), () {
                  Scrollable.ensureVisible(
                    builderCtx,
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeInOut,
                    alignment: 0.5,
                  );
                });
              }
            },
            children: children,
          ),
        ),
      ),
    );
  }

  // Fila de dato de solo lectura — ícono + etiqueta + valor.
  // Fila de cuenta de pago — nombre del banco/app FIJO (no editable, lo
  // identifica visualmente con su color de marca) + campo de número
  // de cuenta al lado. Vacío es válido — no todos los móviles tienen
  // las tres.
  Widget _filaCuentaPago(
    String nombreApp,
    Color colorMarca,
    Color colorTexto,
    TextEditingController controller,
  ) {
    return Row(
      children: [
        Container(
          width: 96,
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(
            color: colorMarca,
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: Text(
            nombreApp,
            style: TextStyle(
              color: colorTexto,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: controller,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              hintText: 'Número de cuenta (opcional)',
              border: OutlineInputBorder(),
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            ),
          ),
        ),
      ],
    );
  }

  // Fila de un documento que todavía no se puede cargar — nombre +
  // insignia "PRÓXIMAMENTE". Lista completa y honesta de lo que viene,
  // en vez de un párrafo vago.
  Widget _filaDocumentoFuturo(
    IconData icono,
    String nombre, {
    bool esUltimo = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      decoration: BoxDecoration(
        border: esUltimo
            ? null
            : Border(bottom: BorderSide(color: Colors.grey[100]!)),
      ),
      child: Row(
        children: [
          Icon(icono, size: 18, color: Colors.grey[400]),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              nombre,
              style: TextStyle(fontSize: 13, color: Colors.grey[700]),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.amber[50],
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.amber[300]!),
            ),
            child: Text(
              'PRÓXIMAMENTE',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                color: Colors.amber[800],
                letterSpacing: 0.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filaDato(
    IconData icono,
    String etiqueta,
    String valor, {
    bool esUltimo = false,
    VoidCallback? onEditar,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        border: esUltimo
            ? null
            : Border(bottom: BorderSide(color: Colors.grey[100]!)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icono, size: 18, color: Colors.grey[500]),
          const SizedBox(width: 12),
          SizedBox(
            width: 90,
            child: Text(
              etiqueta,
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
          ),
          Expanded(
            child: Text(
              valor,
              textAlign: TextAlign.left,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
          ),
          if (onEditar != null)
            IconButton(
              icon: const Icon(Icons.edit, size: 15, color: Colors.black38),
              padding: const EdgeInsets.only(left: 6),
              constraints: const BoxConstraints(),
              onPressed: onEditar,
            ),
        ],
      ),
    );
  }


  Future<void> _guardarContactoPerfil(dynamic movilId) async {
    setState(() => _guardandoPerfil = true);
    try {
      await Supabase.instance.client
          .from('usuarios')
          .update({
            'telefono': _perfilTelefonoCtrl.text.trim(),
            'pago_nequi': _perfilNequiCtrl.text.trim().isEmpty
                ? null
                : _perfilNequiCtrl.text.trim(),
            'pago_daviplata': _perfilDaviplataCtrl.text.trim().isEmpty
                ? null
                : _perfilDaviplataCtrl.text.trim(),
            'pago_bancolombia': _perfilBancolombiaCtrl.text.trim().isEmpty
                ? null
                : _perfilBancolombiaCtrl.text.trim(),
          })
          .eq('id', movilId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Perfil actualizado con éxito.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      String mensajeError = 'Error: $e';
      if (e.toString().contains('23505') ||
          e.toString().contains('usuarios_telefono_key')) {
        mensajeError = 'Este número ya está registrado en otra cuenta del sistema.';
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(mensajeError), backgroundColor: Colors.red[900]),
        );
      }
    } finally {
      if (mounted) setState(() => _guardandoPerfil = false);
    }
  }

  // --- FOTO DE PERFIL — editor pan/zoom circular ---
  Future<void> _cambiarFotoPerfil(dynamic movilId) async {
    try {
      final picker = ImagePicker();
      final XFile? imagen = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1200,
        imageQuality: 90,
      );
      if (imagen == null) return;

      final bytes = await imagen.readAsBytes();

      // Mostrar editor con pan/zoom
      final Uint8List? bytesEditados = await _mostrarEditorFoto(bytes);
      if (bytesEditados == null) return; // Usuario canceló

      setState(() => _subiendoFoto = true);

      final nombreArchivo =
          'movil_${movilId}_${DateTime.now().millisecondsSinceEpoch}.jpg';

      await Supabase.instance.client.storage
          .from('perfiles')
          .uploadBinary(
            nombreArchivo,
            bytesEditados,
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
              upsert: true,
            ),
          );

      final String urlPublica = Supabase.instance.client.storage
          .from('perfiles')
          .getPublicUrl(nombreArchivo);

      await Supabase.instance.client
          .from('usuarios')
          .update({'foto_perfil_url': urlPublica})
          .eq('id', movilId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('📸 Foto de perfil actualizada.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al subir la foto: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _subiendoFoto = false);
    }
  }

  // --- EDITOR PAN/ZOOM — dialog con recorte circular ---
  Future<Uint8List?> _mostrarEditorFoto(Uint8List imageBytes) async {
    final GlobalKey boundaryKey = GlobalKey();
    final TransformationController transformCtrl = TransformationController();

    return showDialog<Uint8List>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Ajusta tu foto',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Pellizca para zoom · Arrastra para centrar',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 12),
              // Area de recorte 280×280
              SizedBox(
                width: 280,
                height: 280,
                child: Stack(
                  children: [
                    // Imagen interactiva capturada con RepaintBoundary
                    RepaintBoundary(
                      key: boundaryKey,
                      child: ClipRect(
                        child: SizedBox(
                          width: 280,
                          height: 280,
                          child: InteractiveViewer(
                            transformationController: transformCtrl,
                            minScale: 1.0,
                            maxScale: 6.0,
                            boundaryMargin: const EdgeInsets.all(double.infinity),
                            child: Image.memory(
                              imageBytes,
                              width: 280,
                              height: 280,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Overlay: máscara oscura con hueco circular + borde blanco
                    // IgnorePointer para que los toques lleguen al InteractiveViewer
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: _CircularOverlayPainter(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white54,
                        side: const BorderSide(color: Colors.white24),
                      ),
                      onPressed: () => Navigator.of(ctx).pop(null),
                      child: const Text('Cancelar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xff3AF500),
                        foregroundColor: Colors.black,
                      ),
                      onPressed: () async {
                        try {
                          final boundary = boundaryKey.currentContext!
                              .findRenderObject()! as RenderRepaintBoundary;
                          final ui.Image img =
                              await boundary.toImage(pixelRatio: 2.0);
                          final ByteData? byteData = await img.toByteData(
                            format: ui.ImageByteFormat.png,
                          );
                          transformCtrl.dispose();
                          if (byteData == null) {
                            Navigator.of(ctx).pop(null);
                            return;
                          }
                          Navigator.of(ctx)
                              .pop(byteData.buffer.asUint8List());
                        } catch (_) {
                          Navigator.of(ctx).pop(null);
                        }
                      },
                      child: const Text('Confirmar'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- CAMBIAR CORREO ---
  Future<void> _cambiarCorreoPerfil(
    dynamic movilId,
    String correoActual,
  ) async {
    final correoCtrl = TextEditingController(text: correoActual);
    bool guardando = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: const Text('Cambiar correo'),
          content: TextField(
            controller: correoCtrl,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Nuevo correo electrónico',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          actions: [
            TextButton(
              onPressed: guardando ? null : () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.black),
              onPressed: guardando
                  ? null
                  : () async {
                      final nuevoCorreo = correoCtrl.text.trim().toLowerCase();
                      if (!RegExp(r'^[\w.+-]+@[\w-]+\.[\w.-]+$').hasMatch(nuevoCorreo)) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(
                            content: Text('Escribe un correo válido.'),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }
                      setDialogState(() => guardando = true);
                      try {
                        final existe = await Supabase.instance.client
                            .from('usuarios')
                            .select('id')
                            .eq('correo', nuevoCorreo)
                            .neq('id', movilId)
                            .maybeSingle();
                        if (existe != null) {
                          setDialogState(() => guardando = false);
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(
                                content: Text('Ese correo ya está en uso por otra cuenta.'),
                                backgroundColor: Colors.orange,
                              ),
                            );
                          }
                          return;
                        }
                        await Supabase.instance.client
                            .from('usuarios')
                            .update({'correo': nuevoCorreo})
                            .eq('id', movilId);
                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Correo actualizado.'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      } catch (e) {
                        setDialogState(() => guardando = false);
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
                          );
                        }
                      }
                    },
              child: guardando
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        color: Color(0xff3AF500),
                        strokeWidth: 2,
                      ),
                    )
                  : const Text(
                      'GUARDAR',
                      style: TextStyle(color: Color(0xff3AF500), fontWeight: FontWeight.bold),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // --- CAMBIAR CONTRASEÑA ---
  // Pide la contraseña ACTUAL antes de permitir una nueva — si alguien
  // toma el teléfono desbloqueado, no debería poder cambiar la
  // contraseña sin saber la que ya existe.
  Future<void> _cambiarContrasenaPerfil(dynamic movilId) async {
    final actualCtrl = TextEditingController();
    final nuevaCtrl = TextEditingController();
    final confirmarCtrl = TextEditingController();
    bool guardando = false;
    bool verActual = false;
    bool verNueva = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: const Text('Cambiar contraseña'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: actualCtrl,
                  obscureText: !verActual,
                  decoration: InputDecoration(
                    labelText: 'Contraseña actual',
                    border: const OutlineInputBorder(),
                    isDense: true,
                    suffixIcon: IconButton(
                      icon: Icon(verActual ? Icons.visibility_off : Icons.visibility, size: 18),
                      onPressed: () => setDialogState(() => verActual = !verActual),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nuevaCtrl,
                  obscureText: !verNueva,
                  decoration: InputDecoration(
                    labelText: 'Nueva contraseña (mínimo 4 caracteres)',
                    border: const OutlineInputBorder(),
                    isDense: true,
                    suffixIcon: IconButton(
                      icon: Icon(verNueva ? Icons.visibility_off : Icons.visibility, size: 18),
                      onPressed: () => setDialogState(() => verNueva = !verNueva),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: confirmarCtrl,
                  obscureText: !verNueva,
                  decoration: const InputDecoration(
                    labelText: 'Confirmar nueva contraseña',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: guardando ? null : () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.black),
              onPressed: guardando
                  ? null
                  : () async {
                      if (nuevaCtrl.text.length < 4) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(
                            content: Text('La nueva contraseña debe tener mínimo 4 caracteres.'),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }
                      if (nuevaCtrl.text != confirmarCtrl.text) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(
                            content: Text('Las contraseñas nuevas no coinciden.'),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }
                      setDialogState(() => guardando = true);
                      try {
                        final fila = await Supabase.instance.client
                            .from('usuarios')
                            .select('contrasena')
                            .eq('id', movilId)
                            .single();
                        final hashActualGuardado = fila['contrasena']?.toString() ?? '';
                        final hashIngresado = hashContrasena(actualCtrl.text);

                        if (hashIngresado != hashActualGuardado) {
                          setDialogState(() => guardando = false);
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(
                                content: Text('La contraseña actual no es correcta.'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                          return;
                        }

                        await Supabase.instance.client
                            .from('usuarios')
                            .update({'contrasena': hashContrasena(nuevaCtrl.text)})
                            .eq('id', movilId);

                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('✅ Contraseña actualizada.'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      } catch (e) {
                        setDialogState(() => guardando = false);
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
                          );
                        }
                      }
                    },
              child: guardando
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        color: Color(0xff3AF500),
                        strokeWidth: 2,
                      ),
                    )
                  : const Text(
                      'CAMBIAR',
                      style: TextStyle(color: Color(0xff3AF500), fontWeight: FontWeight.bold),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // Botón de acción de cuenta — fila completa, ícono en cápsula de
  // color, usado para Historial, Ranking, Cerrar sesión y Eliminar.
  Widget _botonAccionPerfil({
    required IconData icono,
    required Color color,
    required String titulo,
    required VoidCallback? onTap,
    Color colorTexto = Colors.white,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: color,
            padding: const EdgeInsets.symmetric(vertical: 13),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            elevation: 0,
          ),
          onPressed: onTap,
          icon: Icon(icono, size: 18, color: colorTexto),
          label: Text(
            titulo,
            style: TextStyle(
              color: colorTexto,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }


  Widget _construirFilaVirtual(List<Map<String, dynamic>> usuariosTotales) {
    final enFila = usuariosTotales
        .where(
          (u) =>
              u['en_linea'] == true &&
              u['paradero_actual'] != null &&
              u['ingreso_fila'] != null,
        )
        .toList();
    // Ticket de prioridad va primero, luego por ingreso_fila
    enFila.sort((a, b) {
      final tA = a['ticket_prioridad'] == true ? 1 : 0;
      final tB = b['ticket_prioridad'] == true ? 1 : 0;
      if (tA != tB) return tB.compareTo(tA);
      return DateTime.parse(a['ingreso_fila']).compareTo(DateTime.parse(b['ingreso_fila']));
    });

    if (enFila.isEmpty) return const SizedBox.shrink();

    // Resumen para el encabezado colapsado: cuántos en total, y mi
    // propia posición si estoy en una de las filas.
    String miResumen = '';
    final miIndexGlobal = enFila.indexWhere(
      (u) => u['id'].toString() == widget.usuario['id'].toString(),
    );
    if (miIndexGlobal != -1) {
      final miParadero = enFila[miIndexGlobal]['paradero_actual'];
      final miFilaLocal = enFila
          .where((u) => u['paradero_actual'] == miParadero)
          .toList();
      final miPos = miFilaLocal.indexWhere(
        (u) => u['id'].toString() == widget.usuario['id'].toString(),
      );
      miResumen = ' · Eres #${miPos + 1} en $miParadero';
    }

    // MOTOR DE AGRUPACIÓN: Separa a los conductores según su paradero actual
    Map<String, List<Map<String, dynamic>>> agrupados = {};
    for (var movil in enFila) {
      String paradero = movil['paradero_actual'];
      if (!agrupados.containsKey(paradero)) agrupados[paradero] = [];
      agrupados[paradero]!.add(movil);
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ENCABEZADO — siempre visible, resumen de una línea
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => setState(
              () => _filaVirtualExpandida = !_filaVirtualExpandida,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(Icons.groups_outlined, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${enFila.length} en fila$miResumen',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[800],
                      ),
                    ),
                  ),
                  Icon(
                    _filaVirtualExpandida
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 18,
                    color: Colors.grey[500],
                  ),
                ],
              ),
            ),
          ),

          // DETALLE — animado al expandir/colapsar
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            child: _filaVirtualExpandida
                ? Padding(
              padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
              child: Column(
                children: agrupados.entries.map((entry) {
                  String nombreParadero = entry.key;
                  List<Map<String, dynamic>> lista = entry.value;

                  return Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue[50],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.blue[200]!),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.format_list_numbered, size: 16, color: Colors.blue),
                  const SizedBox(width: 6),
                  Text(
                    'FILA EN VIVO: $nombreParadero',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.blue),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ...lista.asMap().entries.map((e) {
                int idx = e.key + 1;
                var movil = e.value;
                bool soyYo = movil['id'] == widget.usuario['id'];
                final bool tieneTicket = movil['ticket_prioridad'] == true;
                final String rango = movil['rango_movil']?.toString().toUpperCase() ?? 'NOVATO';
                final dynamic calRaw = movil['puntuacion'];
                final String calTexto = calRaw == null ? '-' : '★ ${(calRaw as num).toDouble().toStringAsFixed(1)}';
                final int cap = _limitePorRango(rango);
                final String texCap = cap >= 999 ? '∞' : '$cap';
                return FadeSlideIn(
                  key: ValueKey('fila_${movil['id']}'),
                  child: Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: soyYo ? Colors.black : Colors.blue[100],
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              '$idx',
                              style: TextStyle(
                                color: soyYo ? const Color(0xff3AF500) : Colors.blue,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${(movil['usuario'] ?? movil['nombre'] ?? '').toString().toUpperCase()}',
                              style: TextStyle(
                                fontWeight: soyYo ? FontWeight.bold : FontWeight.normal,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          if (tieneTicket)
                            const Text('🎟️', style: TextStyle(fontSize: 13)),
                          if (soyYo)
                            const Padding(
                              padding: EdgeInsets.only(left: 4),
                              child: Text(
                                'TÚ',
                                style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 10),
                              ),
                            ),
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.only(left: 28, top: 1),
                        child: Row(
                          children: [
                            Text(
                              rango,
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.blue[700],
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const Text(' · ', style: TextStyle(fontSize: 10, color: Colors.black38)),
                            Text(calTexto, style: const TextStyle(fontSize: 10, color: Colors.black45)),
                            const Text(' · ', style: TextStyle(fontSize: 10, color: Colors.black38)),
                            Text('$texCap pedido${texCap == '1' ? '' : 's'}', style: const TextStyle(fontSize: 10, color: Colors.black45)),
                            if (tieneTicket) ...[
                              const Text(' · ', style: TextStyle(fontSize: 10, color: Colors.black38)),
                              const Text('Prioridad P2P', style: TextStyle(fontSize: 10, color: Colors.purple, fontWeight: FontWeight.bold)),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  ),
                );
              }),
            ],
          ),
        );
      }).toList(),
              ),
                )
              : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  // --- MODO ACORDEÓN TÁCTICO ---
  // FIX: la tarjeta hablaba siempre de "Local" y "Entrega" sin
  // importar el tipo real de servicio — un mototaxi no tiene local,
  // tiene un pasajero, y no se "entrega" a alguien, se le lleva.
  String _textoOrigenSegunTipo(dynamic tipo) {
    switch (tipo?.toString().toUpperCase()) {
      case 'MOTOTAXI':
        return 'PASAJERO';
      case 'COMIDA':
        return 'RESTAURANTE';
      case 'COMPRAS':
        return 'TIENDA';
      default:
        return 'LOCAL';
    }
  }

  bool _esMototaxi(dynamic tipo) =>
      tipo?.toString().toUpperCase() == 'MOTOTAXI';

  Widget _construirTarjetaActiva(
    Map<String, dynamic> servicio, {
    bool esMaster = false,
  }) {
    final bool estaExpandida = _serviciosExpandidos.contains(servicio['id'] as int);
    final estado = servicio['estado'];
    final bool tieneProblema = estado == 'problema';

    if (!estaExpandida) {
      return AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        child: Card(
        key: ValueKey('collapsed_${servicio['id']}_$estado'),
        elevation: 2,
        margin: const EdgeInsets.only(bottom: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            color: tieneProblema ? Colors.red : Colors.grey[400]!,
            width: 1.5,
          ),
        ),
        child: InkWell(
          onTap: () => setState(() => _serviciosExpandidos.add(servicio['id'] as int)),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(
                  tieneProblema
                      ? Icons.warning_amber_rounded
                      : Icons.motorcycle,
                  color: tieneProblema ? Colors.red : Colors.black87,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'ORDEN #${servicio['numero_movil'] ?? servicio['id']}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: tieneProblema ? Colors.red : Colors.black,
                            ),
                          ),
                          if (servicio['ruta_grupo_id'] != null) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.blue[50],
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.blue[200]!),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.alt_route, size: 10, color: Colors.blue[700]),
                                  const SizedBox(width: 2),
                                  Text(
                                    'Ruta combinada',
                                    style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.blue[700]),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                      Text(
                        estado == 'en_ruta_destino'
                            ? (_esMototaxi(servicio['tipo_servicio'])
                                ? 'Destino: ${servicio['destino']}'
                                : 'Entrega: ${servicio['destino']}')
                            : 'Recogida: ${servicio['origen']}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.expand_more, color: Colors.black54),
              ],
            ),
          ),
        ),
      ),  // Card
    );    // AnimatedSwitcher
    }

    // ── Tarjeta exclusiva para servicios FN ────────────────────────────────────
    if (servicio['tipo_fn'] == true) {
      return _construirTarjetaActivaFN(servicio, esMaster: esMaster);
    }

    int efectivos = 0;
    int tiempoMeta = servicio['tiempo_estimado_minutos'] ?? 15;
    bool mostrarReloj = false;

    // --- CÁLCULO DE TIEMPOS BIFURCADO ---
    if (estado == 'en_ruta_origen' && servicio['accepted_at'] != null) {
      final elapsed = DateTime.now()
          .toUtc()
          .difference(DateTime.parse(servicio['accepted_at']).toUtc())
          .inMinutes;
      efectivos = elapsed;
      mostrarReloj = true;
    } else if (estado == 'en_ruta_destino' && servicio['picked_up_at'] != null) {
      final elapsed = DateTime.now()
          .toUtc()
          .difference(DateTime.parse(servicio['picked_up_at']).toUtc())
          .inMinutes;
      efectivos = elapsed - (servicio['extension_minutes'] as int? ?? 0);
      if (efectivos < 0) efectivos = 0;
      mostrarReloj = true;
    }

    bool estaDemorado = efectivos >= tiempoMeta;
    final String textoTarifa = _formatearMoneda(servicio['tarifa']);
    final esComidaOCompra =
        (servicio['observacion'] ?? '').contains('[ COMIDA ]') ||
        (servicio['observacion'] ?? '').contains('[ COMPRAS ]');

    bool mostrarBotonNavegar =
        estado == 'en_ruta_destino' ||
        (estado == 'en_ruta_origen' && !esComidaOCompra);

    Widget botonAccion;
    if (tieneProblema) {
      botonAccion = ElevatedButton(
        style: ElevatedButton.styleFrom(backgroundColor: Colors.grey[400]),
        onPressed: null,
        child: Text(
          '⚠️ EN REVISIÓN POR CENTRAL',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
      );
    } else if (estado == 'en_ruta_origen') {
      // 1. VA AL LOCAL
      botonAccion = ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          elevation: 4,
        ),
        onPressed: _procesando ? null : () => _marcarLlegadaOrigen(servicio),
        child: _procesando
            ? SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 3,
                ),
              )
            : Text(
                '📍 LLEGUÉ AL ${_textoOrigenSegunTipo(servicio['tipo_servicio'])}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
      );
    } else if (estado == 'en_origen') {
      // 2. ESPERANDO EN EL LOCAL
      botonAccion = ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xff3AF500),
          foregroundColor: Colors.black,
          elevation: 4,
        ),
        onPressed: _procesando ? null : () => _iniciarRutaDestino(servicio),
        child: _procesando
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  color: Colors.black,
                  strokeWidth: 3,
                ),
              )
            : Text(
                _esMototaxi(servicio['tipo_servicio'])
                    ? 'INICIAR VIAJE'
                    : 'INICIAR RUTA DE ENTREGA',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
      );
    } else {
      // 3. EN RUTA AL CLIENTE
      if (estaDemorado) {
        botonAccion = ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red[900]),
          onPressed: () => _abrirMenuJustificacion(context, servicio['id']),
          child: Text(
            '⚠️ DEMORA - JUSTIFICAR',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
        );
      } else {
        botonAccion = BotonPresionSostenida(
          texto: _esMototaxi(servicio['tipo_servicio'])
              ? '🏁 MANTÉN PRESIONADO PARA FINALIZAR VIAJE'
              : '🏁 MANTÉN PRESIONADO PARA ENTREGAR',
          colorBase: Colors.black,
          colorTexto: const Color(0xff3AF500),
          onCompletado: () => _finalizarServicio(servicio, tieneProblema),
        );
      }
    }

    return Card(
      elevation: 4,
      margin: const EdgeInsets.only(bottom: 16),
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: tieneProblema ? Colors.red : const Color(0xff3AF500),
          width: 2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  tieneProblema
                      ? '⚠️ NOVEDAD (#${servicio['numero_movil'] ?? servicio['id']})'
                      : 'SERVICIO ACTIVO (#${servicio['numero_movil'] ?? servicio['id']})',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: tieneProblema ? Colors.red[800] : Colors.black,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.expand_less, color: Colors.black54),
                  onPressed: () =>
                      setState(() => _serviciosExpandidos.remove(servicio['id'] as int)),
                ),
              ],
            ),

            // ---> INYECCIÓN: RELOJ BIFURCADO Y FASE DE ESPERA <---
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: SizeTransition(sizeFactor: anim, child: child),
              ),
              child: mostrarReloj
                  ? Container(
                      key: ValueKey('badge_reloj_$estado${estaDemorado ? '_d' : ''}'),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: estaDemorado ? Colors.red[50] : Colors.blue[50],
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        estado == 'en_ruta_origen'
                            ? 'Tiempo hacia el ${_textoOrigenSegunTipo(servicio['tipo_servicio'])}: $efectivos / $tiempoMeta min'
                            : (_esMototaxi(servicio['tipo_servicio'])
                                ? 'Tiempo hacia el destino: $efectivos / $tiempoMeta min'
                                : 'Tiempo hacia el Cliente: $efectivos / $tiempoMeta min'),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: estaDemorado ? Colors.red[800] : Colors.blue[800],
                        ),
                      ),
                    )
                  : estado == 'en_origen'
                      ? Container(
                          key: const ValueKey('badge_en_origen'),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.orange[50],
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '⌛ ESPERANDO EL PEDIDO...',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: Colors.orange[900],
                            ),
                          ),
                        )
                      : const SizedBox.shrink(key: ValueKey('badge_none')),
            ),

            // --------------------------------------------------------
            const SizedBox(height: 12),
            if (servicio['observacion'] != null)
              Container(
                padding: const EdgeInsets.all(10),
                color: Colors.yellow[100],
                child: Text(
                  '📌 NOTA: ${servicio['observacion']}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            // Origen / Destino estándar
            if (true) ...[
            const SizedBox(height: 12),
            Text(
              '📍 Origen: ${servicio['origen']}',
              style: const TextStyle(fontSize: 16),
            ),
            Text(
              '🏁 Destino: ${servicio['destino']}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            ],
            // ---> INYECCIÓN VISUAL DEL NÚMERO <---
            if (servicio['telefono_receptor'] != null &&
                servicio['telefono_receptor'].toString().trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '📱 Recibe: ${servicio['telefono_receptor']}',
                  style: TextStyle(
                    fontSize: 15,
                    color: Colors.blue[800],
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            // -------------------------------------
            const SizedBox(height: 10),
            Text(
              'Cobrar: $textoTarifa',
              style: TextStyle(
                color: textoTarifa == 'SIN TARIFA'
                    ? Colors.orange[800]
                    : Colors.green,
                fontWeight: FontWeight.bold,
                fontSize: 22,
              ),
            ),
            // Desglose del precio si viene con tarifa_detalle
            Builder(builder: (_) {
              final detalle = servicio['tarifa_detalle'] as Map<String, dynamic>?;
              if (detalle == null) return const SizedBox.shrink();
              final int recargo = (detalle['recargo'] as num?)?.toInt() ?? 0;
              final bool lluvia = detalle['lluvia'] == true;
              final bool nocturno = detalle['nocturno'] == true;
              final bool sobrecarga = detalle['sobrecarga'] == true;
              final String fuente = detalle['fuente']?.toString() ?? '';
              final bool tieneDesglose =
                  recargo > 0 || lluvia || nocturno || sobrecarga;
              if (!tieneDesglose && fuente.isEmpty) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    if (lluvia)
                      _chipDetalle('🌧 lluvia', Colors.blue[100]!),
                    if (nocturno)
                      _chipDetalle('🌙 nocturno', Colors.indigo[100]!),
                    if (sobrecarga)
                      _chipDetalle('⚡ sobrecarga', Colors.amber[100]!),
                    if (recargo > 0)
                      _chipDetalle(
                        '+${_formatearMoneda(recargo.toDouble())} recargo',
                        Colors.orange[100]!,
                      ),
                    if (fuente.startsWith('motor'))
                      _chipDetalle('motor IA', Colors.green[100]!),
                    if (fuente == 'manual' || fuente == 'central_manual')
                      _chipDetalle('precio manual', Colors.grey[200]!),
                  ],
                ),
              );
            }),
            const SizedBox(height: 20),

            if (mostrarBotonNavegar && !tieneProblema)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.indigo[600],
                      foregroundColor: Colors.white,
                      elevation: 3,
                    ),
                    onPressed: _procesando
                        ? null
                        : () => _abrirNavegadorSatelital(
                            servicio,
                            estado == 'en_ruta_origen',
                          ),
                    icon: const Icon(Icons.explore, size: 24),
                    label: const Text(
                      'NAVEGAR EN GOOGLE MAPS',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ),

            // BOTÓN LIBERAR — exclusivo Master, solo antes de comprometerse
            // físicamente (en_ruta_origen). El servicio vuelve a nacer
            // desde cero: Master lo ve primero de nuevo, 30s después pasa
            // al paradero, y sigue el resto del embudo normal — como si
            // jamás lo hubiera tomado nadie.
            if (esMaster && estado == 'en_ruta_origen' && !tieneProblema)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFE040FB),
                      side: const BorderSide(color: Color(0xFFE040FB)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: _procesando ? null : () => _liberarServicio(servicio),
                    icon: const Icon(Icons.replay, size: 18),
                    label: const Text(
                      'LIBERAR',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ),
                ),
              ),

            // ---> INYECCIÓN: PANEL DE CONTROL SÓLIDO Y COLORIDO <---
            if (!tieneProblema)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Builder(
                  builder: (context) {
                    // --- LÓGICA TÁCTICA: ¿QUIÉN PIDIÓ EL SERVICIO? ---
                    bool esCreadoPorCentral = servicio['creador'] == 'Central';
                    bool esClienteApp = servicio['cliente_id'] != null;

                    // Solo mostramos el chat interno si NO lo despachó la Central
                    bool mostrarChatInterno =
                        !esCreadoPorCentral || esClienteApp;

                    // Asignación de nombres e íconos dinámicos
                    String textoChat = esClienteApp ? 'Cliente' : 'Local';
                    IconData iconoChat = esClienteApp
                        ? Icons.person
                        : Icons.storefront;
                    // -------------------------------------------------

                    // FUNCIÓN CONSTRUCTORA DE LA FILA (Para evitar saltos de interfaz)
                    Widget construirFilaBotones(String numeroWa) {
                      bool mostrarWa = numeroWa.isNotEmpty;
                      return Row(
                        children: [
                          // WHATSAPP
                          if (mostrarWa) ...[
                            Expanded(
                              child: BotonTacticoAccion(
                                icono: Icons.wechat,
                                texto: 'WS Cliente',
                                colorBase: const Color(0xff25D366),
                                colorFondo: Colors.green[50]!,
                                onTap: () async {
                                  String numero = numeroWa.replaceAll(
                                    RegExp(r'[^0-9]'),
                                    '',
                                  );
                                  if (numero.length == 10) numero = '57$numero';

                                  String nombreNegocio =
                                      (servicio['creador'] == 'Central')
                                      ? 'ServiExpress'
                                      : servicio['creador'].toString();

                                  // Mensaje inteligente: Diferencia si lo pidió el Local o el Cliente App
                                  String textoWa = esClienteApp
                                      ? 'Hola, soy el Móvil de Serviexpress. Voy en camino hacia tu ubicación.'
                                      : 'Hola, soy el Móvil que te está haciendo el domicilio de $nombreNegocio. Voy en camino hacia tu dirección.';

                                  final Uri url = Uri.parse(
                                    'https://wa.me/$numero?text=${Uri.encodeComponent(textoWa)}',
                                  );
                                  if (!await launchUrl(
                                    url,
                                    mode: LaunchMode.externalApplication,
                                  )) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'No se pudo abrir WhatsApp',
                                          ),
                                        ),
                                      );
                                    }
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],

                          // CHAT INTERNO (DINÁMICO: LOCAL O CLIENTE APP)
                          if (mostrarChatInterno) ...[
                            Expanded(
                              child: Builder(
                                builder: (context) {
                                  bool tieneMsg = servicio['chat_movil'] == true;
                                  if (tieneMsg) {
                                    WidgetsBinding.instance
                                        .addPostFrameCallback((_) {
                                          _sonidos.reproducirSuave(
                                            Sonidos.movilChatCliente,
                                          );
                                        });
                                  }
                                  return BotonTacticoAccion(
                                    icono: iconoChat,
                                    texto: textoChat,
                                    colorBase: Colors.blue[800]!,
                                    colorFondo: Colors.blue[50]!,
                                    tieneAlarma: tieneMsg,
                                    onTap: () {
                                      Supabase.instance.client
                                          .from('servicios')
                                          .update({'chat_movil': false})
                                          .eq('id', servicio['id']);
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => ChatScreen(
                                            salaId: 'servicio_${servicio['id']}',
                                            miId: widget.usuario['id'],
                                            miNombre: widget.usuario['nombre'],
                                            titulo: 'Chat $textoChat',
                                            servicioId: servicio['id'],
                                            alarmaLocal: 'chat_movil',
                                            alarmaDestino: 'chat_cliente',
                                            tipoFaq: TipoFaqChat.movil,
                                          ),
                                        ),
                                      );
                                    },
                                  );
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],

                          // CHAT CENTRAL (ROJO EMERGENCIA)
                          Expanded(
                            child: Builder(
                              builder: (context) {
                                bool tieneMsg =
                                    servicio['chat_central_movil'] == true;
                                // Suena al detectar alarma activa de Central
                                if (tieneMsg) {
                                  WidgetsBinding.instance.addPostFrameCallback((
                                    _,
                                  ) {
                                    _sonidos.reproducir(
                                      Sonidos.movilChatCentral,
                                    );
                                  });
                                }
                                return BotonTacticoAccion(
                                  icono: Icons.support_agent,
                                  texto: 'Central',
                                  colorBase: Colors.red[800]!,
                                  colorFondo: Colors.red[50]!,
                                  tieneAlarma: tieneMsg,
                                  onTap: () {
                                    Supabase.instance.client
                                        .from('servicios')
                                        .update({'chat_central_movil': false})
                                        .eq('id', servicio['id']);
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => ChatScreen(
                                          salaId: 'soporte_movil_${servicio['id']}',
                                          miId: widget.usuario['id'],
                                          miNombre: widget.usuario['nombre'],
                                          titulo: 'Soporte Central',
                                          servicioId: servicio['id'],
                                          alarmaLocal: 'chat_central_movil',
                                          alarmaDestino: 'chat_movil_central',
                                          tipoFaq: TipoFaqChat.movil,
                                        ),
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                          ),
                        ],
                      );
                    }

                    // --- MOTOR DE EXTRACCIÓN DE NÚMERO ---
                    String numReceptor =
                        servicio['telefono_receptor']?.toString().trim() ?? '';

                    // Si el Local digitó un número, o si NO es cliente app, dibujamos directo.
                    if (numReceptor.isNotEmpty || !esClienteApp) {
                      return construirFilaBotones(numReceptor);
                    } else {
                      // Si es Cliente App y no escribió número manual, jalamos el de su perfil.
                      return FutureBuilder<Map<String, dynamic>?>(
                        future: Supabase.instance.client
                            .from('usuarios')
                            .select('telefono')
                            .eq('id', servicio['cliente_id'])
                            .maybeSingle(),
                        builder: (context, snap) {
                          // Seguro para evitar saltos de pantalla mientras consulta a la base de datos
                          if (snap.connectionState == ConnectionState.waiting) {
                            return construirFilaBotones('');
                          }
                          String numPerfil =
                              snap.data?['telefono']?.toString().trim() ?? '';
                          return construirFilaBotones(numPerfil);
                        },
                      );
                    }
                  },
                ),
              ),
            // --------------------------------------------------------------------------
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: ScaleTransition(scale: Tween(begin: 0.92, end: 1.0).animate(anim), child: child),
              ),
              child: SizedBox(
                key: ValueKey('btn_$estado${estaDemorado ? '_d' : ''}'),
                width: double.infinity,
                height: 70,
                child: botonAccion,
              ),
            ),

            if (!tieneProblema &&
                estado == 'en_ruta_destino' &&
                efectivos >= (tiempoMeta * 0.7).floor())
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: Colors.blue[700]!, width: 2),
                    ),
                    onPressed: () => _abrirMenuProrroga(
                      context,
                      servicio['id'],
                      servicio['extension_minutes'] as int? ?? 0,
                    ),
                    icon: Icon(Icons.timer, color: Colors.blue[700], size: 22),
                    label: const Text(
                      'JUSTIFICAR (+15 MIN)',
                      style: TextStyle(
                        color: Colors.blue,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ),
            if (!tieneProblema)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: Colors.red[700]!, width: 2),
                    ),
                    onPressed: () => _mostrarMenuProblema(context, servicio['id']),
                    icon: Icon(Icons.warning, color: Colors.red[700], size: 22),
                    label: Text(
                      'REPORTAR PROBLEMA',
                      style: TextStyle(
                        color: Colors.red[700],
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── Etiqueta legible de zona FN ─────────────────────────────────────────────
  String _fnZonaLabel(String z) {
    switch (z) {
      case 'CUCUTA': return 'Cúcuta';
      case 'LOS_PATIOS': return 'Los Patios';
      case 'V_ROSARIO': return 'Villa del Rosario';
      default: return z;
    }
  }

  // ── Abrir Google Maps hacia una coordenada ───────────────────────────────────
  Future<void> _abrirMapsHaciaCoords(double lat, double lng, String label) async {
    final uri = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving');
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TARJETA ACTIVA EXCLUSIVA FN FARMANORTE
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _construirTarjetaActivaFN(
    Map<String, dynamic> servicio, {
    bool esMaster = false,
  }) {
    final bool estaExpandida =
        _serviciosExpandidos.contains(servicio['id'] as int);
    final estado = servicio['estado'];
    final bool tieneProblema = estado == 'problema';

    // ── Colapsada ────────────────────────────────────────────────────────────
    if (!estaExpandida) {
      return AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        child: Card(
          key: ValueKey('fn_col_${servicio['id']}_$estado'),
          elevation: 2,
          margin: const EdgeInsets.only(bottom: 10),
          color: Colors.indigo[50],
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(
              color: tieneProblema ? Colors.red : Colors.indigo[800]!,
              width: 1.5,
            ),
          ),
          child: InkWell(
            onTap: () => setState(
                () => _serviciosExpandidos.add(servicio['id'] as int)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
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
                            fontSize: 12,
                            letterSpacing: 1.5)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ORDEN #${servicio['numero_movil'] ?? servicio['id']}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: tieneProblema
                                ? Colors.red
                                : Colors.indigo[900],
                          ),
                        ),
                        Text(
                          estado == 'en_ruta_destino'
                              ? 'Entrega: ${servicio['destino'] ?? ''}'
                              : 'Recoge: ${servicio['origen'] ?? ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 13, color: Colors.indigo[700]),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.expand_more, color: Colors.black54),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // ── Variables ────────────────────────────────────────────────────────────
    int efectivos = 0;
    int tiempoMeta = servicio['tiempo_estimado_minutos'] ?? 20;
    bool mostrarReloj = false;

    if (estado == 'en_ruta_origen' && servicio['accepted_at'] != null) {
      efectivos = DateTime.now()
          .toUtc()
          .difference(
              DateTime.parse(servicio['accepted_at']).toUtc())
          .inMinutes;
      mostrarReloj = true;
    } else if (estado == 'en_ruta_destino' &&
        servicio['picked_up_at'] != null) {
      efectivos = DateTime.now()
              .toUtc()
              .difference(
                  DateTime.parse(servicio['picked_up_at']).toUtc())
              .inMinutes -
          (servicio['extension_minutes'] as int? ?? 0);
      if (efectivos < 0) efectivos = 0;
      mostrarReloj = true;
    }

    final bool estaDemorado = efectivos >= tiempoMeta;
    final String textoTarifa = _formatearMoneda(servicio['tarifa']);
    final recogidasRaw = servicio['recogidas'];
    final List<dynamic> recogidas =
        recogidasRaw is List ? recogidasRaw : [];

    // ── Botón de acción principal ─────────────────────────────────────────────
    Widget botonAccion;
    if (tieneProblema) {
      botonAccion = ElevatedButton(
        style:
            ElevatedButton.styleFrom(backgroundColor: Colors.grey[400]),
        onPressed: null,
        child: const Text('⚠️ EN REVISIÓN POR CENTRAL',
            style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 15)),
      );
    } else if (estado == 'en_ruta_origen') {
      botonAccion = ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.indigo[900],
          foregroundColor: Colors.white,
          elevation: 4,
        ),
        onPressed:
            _procesando ? null : () => _marcarLlegadaOrigen(servicio),
        child: _procesando
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 3))
            : const Text('📍 LLEGUÉ A LA SEDE',
                style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 16)),
      );
    } else if (estado == 'en_origen') {
      botonAccion = ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xff3AF500),
          foregroundColor: Colors.black,
          elevation: 4,
        ),
        onPressed:
            _procesando ? null : () => _iniciarRutaDestino(servicio),
        child: _procesando
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                    color: Colors.black, strokeWidth: 3))
            : const Text('INICIAR RUTA DE ENTREGA',
                style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 16)),
      );
    } else {
      botonAccion = estaDemorado
          ? ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red[900]),
              onPressed: () =>
                  _abrirMenuJustificacion(context, servicio['id']),
              child: const Text('⚠️ DEMORA - JUSTIFICAR',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15)),
            )
          : BotonPresionSostenida(
              texto: '🏁 MANTÉN PRESIONADO PARA ENTREGAR',
              colorBase: Colors.indigo[900]!,
              colorTexto: Colors.white,
              onCompletado: () =>
                  _finalizarServicio(servicio, tieneProblema),
            );
    }

    // ── Card expandida ────────────────────────────────────────────────────────
    return Card(
      elevation: 4,
      margin: const EdgeInsets.only(bottom: 16),
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: tieneProblema ? Colors.red : Colors.indigo[800]!,
          width: 2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // ── Encabezado ────────────────────────────────────────────────
            Row(
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
                          fontSize: 12,
                          letterSpacing: 1.5)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tieneProblema
                        ? '⚠️ NOVEDAD (#${servicio['numero_movil'] ?? servicio['id']})'
                        : 'SERVICIO ACTIVO (#${servicio['numero_movil'] ?? servicio['id']})',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: tieneProblema
                            ? Colors.red[800]
                            : Colors.black),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.expand_less,
                      color: Colors.black54),
                  onPressed: () => setState(() =>
                      _serviciosExpandidos
                          .remove(servicio['id'] as int)),
                ),
              ],
            ),

            // ── Tiempo ───────────────────────────────────────────────────
            if (mostrarReloj) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: estaDemorado
                      ? Colors.red[50]
                      : Colors.indigo[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  estado == 'en_ruta_origen'
                      ? 'Tiempo hacia la sede: $efectivos / $tiempoMeta min'
                      : 'Tiempo de entrega: $efectivos / $tiempoMeta min',
                  style: TextStyle(
                      color: estaDemorado
                          ? Colors.red[800]
                          : Colors.indigo[800],
                      fontWeight: FontWeight.w600,
                      fontSize: 13),
                ),
              ),
            ],

            const SizedBox(height: 12),

            // ── Bloque de ruta FN ─────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.indigo[50],
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.indigo[200]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Zona
                  if (servicio['zona_fn'] != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        _fnZonaLabel(
                            servicio['zona_fn'] as String),
                        style: TextStyle(
                            color: Colors.indigo[700],
                            fontWeight: FontWeight.w600,
                            fontSize: 13),
                      ),
                    ),

                  // Sede principal
                  Text('📦 Recoge en:',
                      style: TextStyle(
                          color: Colors.indigo[800],
                          fontSize: 11,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 3),
                  Text(servicio['origen'] ?? '—',
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                  if (servicio['origen_lat'] != null &&
                      servicio['origen_lng'] != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(
                                color: Colors.indigo[400]!),
                            padding: const EdgeInsets.symmetric(
                                vertical: 8),
                            foregroundColor: Colors.indigo[700],
                          ),
                          onPressed: () =>
                              _abrirMapsHaciaCoords(
                            (servicio['origen_lat'] as num)
                                .toDouble(),
                            (servicio['origen_lng'] as num)
                                .toDouble(),
                            servicio['origen'] ??
                                'Sede principal',
                          ),
                          icon: const Icon(Icons.directions,
                              size: 18),
                          label: const Text(
                              'Navegar a sede principal',
                              style: TextStyle(fontSize: 13)),
                        ),
                      ),
                    ),

                  // Recogidas adicionales
                  if (recogidas.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text('Paradas adicionales:',
                        style: TextStyle(
                            fontSize: 12,
                            color: Colors.indigo[800],
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    ...recogidas.map((r) {
                      final rMap = r as Map<String, dynamic>;
                      final tipo =
                          rMap['tipo'] as String? ?? '';
                      final nombre =
                          rMap['nombre'] as String? ?? '';
                      final numero = rMap['numero'];
                      final lat =
                          (rMap['lat'] as num?)?.toDouble();
                      final lng =
                          (rMap['lng'] as num?)?.toDouble();
                      final label =
                          tipo == 'FN' && numero != null
                              ? 'FN #$numero – $nombre'
                              : '$tipo – $nombre';
                      return Padding(
                        padding:
                            const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            Icon(
                                Icons
                                    .subdirectory_arrow_right,
                                size: 14,
                                color: Colors.indigo[400]),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(label,
                                  style: const TextStyle(
                                      fontSize: 13)),
                            ),
                            if (lat != null && lng != null)
                              SizedBox(
                                height: 30,
                                child: ElevatedButton.icon(
                                  style: ElevatedButton
                                      .styleFrom(
                                    backgroundColor:
                                        Colors.indigo[700],
                                    foregroundColor:
                                        Colors.white,
                                    padding:
                                        const EdgeInsets
                                            .symmetric(
                                                horizontal:
                                                    10),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius
                                                .circular(
                                                    6)),
                                    elevation: 0,
                                  ),
                                  onPressed: () =>
                                      _abrirMapsHaciaCoords(
                                          lat, lng, label),
                                  icon: const Icon(
                                      Icons.navigation,
                                      size: 14),
                                  label: const Text('GPS',
                                      style: TextStyle(
                                          fontSize: 12,
                                          fontWeight:
                                              FontWeight
                                                  .bold)),
                                ),
                              ),
                          ],
                        ),
                      );
                    }),
                  ],

                  // Destino
                  const SizedBox(height: 10),
                  Text('🏁 Entrega:',
                      style: TextStyle(
                          color: Colors.indigo[800],
                          fontSize: 11,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text(servicio['destino'] ?? '—',
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold)),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // ── Cobrar ────────────────────────────────────────────────────
            Text(
              'Cobrar: $textoTarifa',
              style: TextStyle(
                color: textoTarifa == 'SIN TARIFA'
                    ? Colors.orange[800]
                    : Colors.green,
                fontWeight: FontWeight.bold,
                fontSize: 22,
              ),
            ),

            const SizedBox(height: 14),

            // ── Reportar Factura ──────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo[900],
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(vertical: 13),
                ),
                onPressed: () async {
                  final uri = Uri.parse(
                      'https://databasesvm.github.io/appweb/');
                  if (await canLaunchUrl(uri)) {
                    launchUrl(uri,
                        mode: LaunchMode.externalApplication);
                  }
                },
                icon: const Icon(Icons.receipt_long, size: 20),
                label: const Text('REPORTAR FACTURA',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14)),
              ),
            ),

            // ── Navegar al destino (en ruta destino) ──────────────────────
            if (estado == 'en_ruta_destino' && !tieneProblema)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.indigo[600],
                      foregroundColor: Colors.white,
                      elevation: 2,
                    ),
                    onPressed: _procesando
                        ? null
                        : () => _abrirNavegadorSatelital(
                            servicio, false),
                    icon: const Icon(Icons.explore, size: 22),
                    label: const Text('NAVEGAR AL DESTINO',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13)),
                  ),
                ),
              ),

            // ── Liberar (solo Master en ruta origen) ─────────────────────
            if (esMaster &&
                estado == 'en_ruta_origen' &&
                !tieneProblema)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFE040FB),
                      side: const BorderSide(
                          color: Color(0xFFE040FB)),
                      padding: const EdgeInsets.symmetric(
                          vertical: 12),
                    ),
                    onPressed: _procesando
                        ? null
                        : () => _liberarServicio(servicio),
                    icon: const Icon(Icons.replay, size: 18),
                    label: const Text('LIBERAR',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12)),
                  ),
                ),
              ),

            // ── Chat Central ──────────────────────────────────────────────
            if (!tieneProblema)
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 4),
                child: Builder(builder: (context) {
                  final tieneMsg =
                      servicio['chat_central_movil'] == true;
                  if (tieneMsg) {
                    WidgetsBinding.instance
                        .addPostFrameCallback((_) => _sonidos
                            .reproducir(Sonidos.movilChatCentral));
                  }
                  return BotonTacticoAccion(
                    icono: Icons.support_agent,
                    texto: 'Central',
                    colorBase: Colors.red[800]!,
                    colorFondo: Colors.red[50]!,
                    tieneAlarma: tieneMsg,
                    onTap: () {
                      Supabase.instance.client
                          .from('servicios')
                          .update({'chat_central_movil': false})
                          .eq('id', servicio['id']);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ChatScreen(
                            salaId:
                                'soporte_movil_${servicio['id']}',
                            miId: widget.usuario['id'],
                            miNombre: widget.usuario['nombre'],
                            titulo: 'Soporte Central',
                            servicioId: servicio['id'],
                            alarmaLocal: 'chat_central_movil',
                            alarmaDestino: 'chat_movil_central',
                            tipoFaq: TipoFaqChat.movil,
                          ),
                        ),
                      );
                    },
                  );
                }),
              ),

            // ── Botón de acción principal ─────────────────────────────────
            const SizedBox(height: 8),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: ScaleTransition(
                    scale: Tween(begin: 0.92, end: 1.0)
                        .animate(anim),
                    child: child),
              ),
              child: SizedBox(
                key: ValueKey(
                    'fn_act_$estado${estaDemorado ? '_d' : ''}'),
                width: double.infinity,
                height: 70,
                child: botonAccion,
              ),
            ),

            // ── Reportar Problema ─────────────────────────────────────────
            if (!tieneProblema)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                          color: Colors.red[700]!, width: 2),
                    ),
                    onPressed: () => _mostrarMenuProblema(
                        context, servicio['id']),
                    icon: Icon(Icons.warning,
                        color: Colors.red[700], size: 22),
                    label: Text('REPORTAR PROBLEMA',
                        style: TextStyle(
                            color: Colors.red[700],
                            fontWeight: FontWeight.bold,
                            fontSize: 14)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _construirTarjetaPendiente(
    Map<String, dynamic> servicio, {
    bool esMaster = false,
  }) {
    // ── TARJETA ESPECIAL FN FARMANORTE ────────────────────────────────────────
    final bool esFn = servicio['tipo_fn'] == true;
    if (esFn) {
      final String zonaFn = servicio['zona_fn'] as String? ?? '';
      final String zonaLabel = _fnZonaLabel(zonaFn);
      return Card(
        elevation: 3,
        margin: const EdgeInsets.only(bottom: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.indigo[800]!, width: 2),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.indigo[900]!.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.local_pharmacy,
                    color: Colors.indigo[800], size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'TURNO FARMANORTE',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.black87,
                      ),
                    ),
                    if (zonaLabel.isNotEmpty)
                      Text(
                        zonaLabel,
                        style: TextStyle(
                            color: Colors.indigo[700],
                            fontWeight: FontWeight.w600,
                            fontSize: 13),
                      ),
                  ],
                ),
              ),
              SizedBox(
                height: 45,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo[900],
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () => _aceptarServicioConCandado(context, servicio),
                  child: const Text(
                    'ACEPTAR',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    // ─────────────────────────────────────────────────────────────────────────

    final String observacion = servicio['observacion'] ?? '';
    // tipo_servicio es la fuente de verdad — observacion era el fallback
    // anterior pero se borra al reactivar desde Central, causando que todo
    // apareciera como PAQUETERÍA. tipo_servicio nunca se toca en reactivación.
    final String tipoSvc = (servicio['tipo_servicio'] ?? '').toString().toUpperCase();
    String tipoBadge = 'PAQUETERÍA';
    IconData iconoBadge = Icons.inventory_2_rounded;
    Color colorBadge = Colors.brown[500]!;

    if (tipoSvc == 'MOTOTAXI' || observacion.contains('[ MOTOTAXI ]')) {
      tipoBadge = 'MOTOTAXI';
      iconoBadge = Icons.two_wheeler;
      colorBadge = Colors.orange[700]!;
    } else if (tipoSvc == 'COMIDA' || observacion.contains('[ COMIDA ]')) {
      tipoBadge = 'COMIDA';
      iconoBadge = Icons.dining;
      colorBadge = Colors.red[700]!;
    } else if (tipoSvc == 'COMPRAS' || observacion.contains('[ COMPRAS ]')) {
      tipoBadge = 'ENCARGO';
      iconoBadge = Icons.shopping_basket;
      colorBadge = Colors.teal[600]!;
    } else if (tipoSvc == 'BEBIDAS' || observacion.contains('[ BEBIDAS ]')) {
      tipoBadge = 'BEBIDAS';
      iconoBadge = Icons.nightlife;
      colorBadge = Colors.purple[600]!;
    }

    String textoDistancia = '';
    double? dist = servicio['distancia_temp'];
    if (dist != null && dist != 9999999) {
      if (dist < 1000) {
        textoDistancia = 'A ${dist.toInt()} mts';
      } else {
        textoDistancia = 'A ${(dist / 1000).toStringAsFixed(1)} KM';
      }
    }

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: esMaster ? const Color(0xFFE040FB) : Colors.grey[300]!,
          width: esMaster ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorBadge.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(iconoBadge, color: colorBadge, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'NUEVO SERVICIO',
                    style: TextStyle(
                      color: Colors.black54,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                  Text(
                    tipoBadge,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.black87,
                    ),
                  ),
                  if (textoDistancia.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          textoDistancia,
                          style: const TextStyle(
                            color: Color(0xff3AF500),
                            fontWeight: FontWeight.bold,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ),
                  if (servicio['etiqueta_tiempo'] != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red[800],
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          servicio['etiqueta_tiempo'],
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 9,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  height: 45,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      elevation: 4,
                    ),
                    onPressed: () => _aceptarServicioConCandado(context, servicio),
                    child: const Text(
                      'ACEPTAR',
                      style: TextStyle(
                        color: Color(0xff3AF500),
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ],
            ),
              ],
            ),

            // =================================================
            // TARJETA COMPLETA — SOLO MASTER
            // El resto de rangos ve la tarjeta "ciega" de arriba
            // (sin destino ni tarifa) para que nadie elija solo
            // los servicios más convenientes. El Master sí puede
            // ver todo para decidir si le conviene tomarlo.
            // =================================================
            if (esMaster) ...[
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Divider(height: 1, color: Color(0xFFE040FB)),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.alt_route,
                    size: 16,
                    color: Color(0xFFE040FB),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          (servicio['origen'] ?? 'Origen sin especificar')
                              .toString()
                              .toUpperCase(),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 1),
                          child: Icon(
                            Icons.arrow_downward,
                            size: 11,
                            color: Colors.black38,
                          ),
                        ),
                        Text(
                          (servicio['destino'] ?? 'Destino sin especificar')
                              .toString()
                              .toUpperCase(),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE040FB).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      servicio['tarifa'] != null && (servicio['tarifa'] as num) > 0
                          ? _formatearMoneda(servicio['tarifa'])
                          : 'COTIZAR',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: Color(0xFFE040FB),
                      ),
                    ),
                  ),
                ],
              ),
              if ((servicio['creador'] ?? '').toString().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Pide: ${servicio['creador']}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.black45,
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  // Delega al motor central — garantiza App ID y canal correctos.
  // segmento ignorado: el segmento solo se usaba para 'Subscribed Users'
  // que nunca se necesitó en la práctica — siempre se pasan externalIds.
  Future<void> _dispararMisilOneSignal({
    List<String>? externalIds,
    required String titulo,
    required String mensaje,
  }) async {
    if (externalIds != null && externalIds.isNotEmpty) {
      await MotorNotificaciones.dispararRafa(
        idsDestinos: externalIds,
        titulo: titulo,
        mensaje: mensaje,
        urgente: true,
      );
    }
    // segmento ignorado — no hay caso activo que lo use
  }

  // Cancela una notificación programada en OneSignal — delega al motor central
  Future<void> _abortarMisilOneSignal(String notificationId) =>
      MotorNotificaciones.cancelarMisil(notificationId);

  // --- FRANCOTIRADOR: BUSCA EL ID DEL LOCAL Y LE DISPARA ---
  Future<void> _notificarAlCreador(
    String creadorNombre,
    String titulo,
    String mensaje,
  ) async {
    if (creadorNombre == 'Central')
      return; // A la central no la bombardeamos con Push
    try {
      final res = await Supabase.instance.client
          .from('usuarios')
          .select('id')
          .eq('nombre', creadorNombre)
          .maybeSingle();
      if (res != null) {
        _dispararMisilOneSignal(
          externalIds: [res['id'].toString()],
          titulo: titulo,
          mensaje: mensaje,
        );
      }
    } catch (e) {
      debugPrint('Error al buscar creador: $e');
    }
  }

  // Límite de servicios simultáneos según rango del móvil
  int _limitePorRango(String? rango) {
    switch (rango?.toUpperCase().trim()) {
      case 'PRO':
        return 1;
      case 'ELITE':
        return 2;
      case 'LEYENDA':
        return 3;
      case 'MASTER':
        return 999;
      default:
        return 1; // NOVATO o sin rango
    }
  }

  Future<void> _aceptarServicioConCandado(
    BuildContext context,
    Map<String, dynamic> servicio,
  ) async {
    setState(() => _procesando = true);

    // --- MOTOR TÁCTICO: CALCULAR ETA AL ORIGEN ---
    int tiempoAlOrigen = 10;
    try {
      Position? pos = await _obtenerPosicionSegura();
      if (pos != null &&
          servicio['origen_lat'] != null &&
          servicio['origen_lng'] != null) {
        final ruta = await MotorRutas.calcularRuta(
          latOrigen: pos.latitude,
          lngOrigen: pos.longitude,
          latDestino: (servicio['origen_lat'] as num).toDouble(),
          lngDestino: (servicio['origen_lng'] as num).toDouble(),
        );
        if (ruta != null) tiempoAlOrigen = (ruta['tiempo_minutos'] as int) + 3;
      }
    } catch (_) {}
    setState(() => _procesando = false);
    // ---------------------------------------------

    final String destinoActual = servicio['destino']?.toString().trim() ?? '';

    if (destinoActual.isEmpty ||
        destinoActual.toLowerCase() == 'n/a' ||
        destinoActual.length < 3) {
      final destinoCtrl = TextEditingController();
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text(
            '⚠️ DESTINO EN BLANCO',
            style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
          ),
          content: TextField(
            controller: destinoCtrl,
            decoration: const InputDecoration(
              labelText: 'Dirección del cliente',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text(
                'CANCELAR',
                style: TextStyle(color: Colors.grey),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.black),
              onPressed: () async {
                if (destinoCtrl.text.trim().length > 3) {
                  // CANDADO ATÓMICO: la función SQL bloquea la fila del
                  // moto y verifica límite de rango + disponibilidad del
                  // servicio en una sola transacción. Ver francotirador_candado.sql
                  final resultado = await Supabase.instance.client.rpc(
                    'tomar_servicio_candado',
                    params: {
                      'p_servicio_id': servicio['id'],
                      'p_movil_id': widget.usuario['id'],
                      'p_destino_nuevo': destinoCtrl.text.trim().toUpperCase(),
                      'p_tiempo_estimado': tiempoAlOrigen,
                    },
                  );
                  final fila = (resultado as List).isNotEmpty
                      ? resultado[0] as Map<String, dynamic>
                      : null;
                  final bool exito = fila?['exito'] == true;

                  if (ctx.mounted) Navigator.pop(ctx);

                  if (!exito) {
                    final String motivo = fila?['motivo']?.toString() ?? '';
                    String mensaje;
                    if (motivo == 'limite_alcanzado') {
                      mensaje = '🚫 Alcanzaste tu límite de servicios simultáneos.';
                    } else {
                      final svcActual = await Supabase.instance.client
                          .from('servicios').select('estado').eq('id', servicio['id']).maybeSingle();
                      final est = svcActual?['estado']?.toString() ?? '';
                      if (est == 'cancelado') {
                        mensaje = '❌ La Central canceló este servicio.';
                      } else if (est == 'completado' || est == 'finalizado' || est == 'finalizado_con_problema') {
                        mensaje = '✅ Este servicio ya fue completado.';
                      } else {
                        mensaje = '⚡ Ya fue asignado a otro móvil.';
                      }
                    }
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(mensaje),
                          backgroundColor: Colors.orange,
                          duration: const Duration(seconds: 3),
                        ),
                      );
                    }
                    return;
                  }

                  // Solo sale del paradero si ganó el servicio
                  await Supabase.instance.client
                      .from('usuarios')
                      .update({'paradero_actual': null, 'ingreso_fila': null})
                      .eq('id', widget.usuario['id']);
                  _miParaderoCache = null; // sincroniza caché local con la BD

                  // AUTO-CIERRE DE PÁNICO: aceptar un servicio con
                  // normalidad es una señal fuerte de que la emergencia
                  // ya pasó — no hace falta esperar a que se cumplan
                  // las 24h para dejar de compartir la ubicación.
                  if (_eventoPanicoActivoId != null) {
                    _detenerMiAlertaPanico(silencioso: true);
                  }

                  if (servicio['onesignal_30s'] != null)
                    _abortarMisilOneSignal(servicio['onesignal_30s'].toString());
                  if (servicio['onesignal_2m'] != null)
                    _abortarMisilOneSignal(servicio['onesignal_2m'].toString());
                  if (servicio['onesignal_5m'] != null)
                    _abortarMisilOneSignal(servicio['onesignal_5m'].toString());

                  _notificarAlCreador(
                    servicio['creador'] ?? 'Central',
                    '🏍️ MÓVIL ASIGNADO',
                    '${widget.usuario['nombre']} va en camino por la Orden #${servicio['id']}.',
                  );
                }
              },
              child: const Text(
                'CONFIRMAR RUTA',
                style: TextStyle(
                  color: Color(0xff3AF500),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      );
    } else {
      // CANDADO ATÓMICO: la función SQL bloquea la fila del moto y
      // verifica límite de rango + disponibilidad del servicio en una
      // sola transacción. Ver francotirador_candado.sql
      final resultado = await Supabase.instance.client.rpc(
        'tomar_servicio_candado',
        params: {
          'p_servicio_id': servicio['id'],
          'p_movil_id': widget.usuario['id'],
          'p_tiempo_estimado': tiempoAlOrigen,
        },
      );
      final fila = (resultado as List).isNotEmpty
          ? resultado[0] as Map<String, dynamic>
          : null;
      final bool exito = fila?['exito'] == true;

      if (!exito) {
        final String motivo = fila?['motivo']?.toString() ?? '';
        String mensaje;
        if (motivo == 'limite_alcanzado') {
          mensaje = '🚫 Alcanzaste tu límite de servicios simultáneos.';
        } else {
          final svcActual = await Supabase.instance.client
              .from('servicios').select('estado').eq('id', servicio['id']).maybeSingle();
          final est = svcActual?['estado']?.toString() ?? '';
          if (est == 'cancelado') {
            mensaje = '❌ La Central canceló este servicio.';
          } else if (est == 'completado' || est == 'finalizado' || est == 'finalizado_con_problema') {
            mensaje = '✅ Este servicio ya fue completado.';
          } else {
            mensaje = '⚡ Ya fue asignado a otro móvil.';
          }
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(mensaje),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 3),
            ),
          );
        }
        return;
      }

      // Solo sale del paradero si ganó el servicio
      await Supabase.instance.client
          .from('usuarios')
          .update({'paradero_actual': null, 'ingreso_fila': null})
          .eq('id', widget.usuario['id']);
      _miParaderoCache = null; // sincroniza caché local con la BD

      // AUTO-CIERRE DE PÁNICO: aceptar un servicio con normalidad es
      // una señal fuerte de que la emergencia ya pasó — no hace falta
      // esperar a que se cumplan las 24h para dejar de compartir la
      // ubicación.
      if (_eventoPanicoActivoId != null) {
        _detenerMiAlertaPanico(silencioso: true);
      }

      if (servicio['onesignal_30s'] != null)
        _abortarMisilOneSignal(servicio['onesignal_30s'].toString());
      if (servicio['onesignal_2m'] != null)
        _abortarMisilOneSignal(servicio['onesignal_2m'].toString());
      if (servicio['onesignal_5m'] != null)
        _abortarMisilOneSignal(servicio['onesignal_5m'].toString());

      _notificarAlCreador(
        servicio['creador'] ?? 'Central',
        '🏍️ MÓVIL ASIGNADO',
        '${widget.usuario['nombre']} va en camino por la Orden #${servicio['id']}.',
      );
    }
  }

  // --- LIBERAR (exclusivo Master) — el servicio "renace" desde cero ---
  // Resetea movil_id y estado, y MUY IMPORTANTE: resetea liberacion_at
  // a NOW(). El embudo táctico calcula sus fases (Master ve todo a T=0,
  // paradero a los 30s, zonal 1km a los 60s, todos a los 90s) a partir
  // de ese campo — sin resetearlo, el servicio "heredaría" la edad
  // real desde su creación original y podría saltarse fases enteras
  // en vez de volver a empezar limpio para todos.
  Future<void> _liberarServicio(Map<String, dynamic> servicio) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('¿Liberar este servicio?'),
        content: const Text(
          'El servicio volverá al radar para todos los disponibles.\n\n'
          'Si liberas sin una excusa válida puede afectar tu calificación.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE040FB)),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'LIBERAR',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    setState(() => _procesando = true);
    try {
      // Cancelar misiles pendientes de la asignación anterior antes de reiniciar
      if (servicio['onesignal_30s'] != null)
        await MotorNotificaciones.cancelarMisil(servicio['onesignal_30s'].toString());
      if (servicio['onesignal_2m'] != null)
        await MotorNotificaciones.cancelarMisil(servicio['onesignal_2m'].toString());
      if (servicio['onesignal_5m'] != null)
        await MotorNotificaciones.cancelarMisil(servicio['onesignal_5m'].toString());

      await Supabase.instance.client
          .from('servicios')
          .update({
            'movil_id': null,
            'estado': 'pendiente',
            'liberacion_at': DateTime.now().toUtc().toIso8601String(),
            'accepted_at': null,
            'onesignal_30s': null,
            'onesignal_2m': null,
            'onesignal_5m': null,
          })
          .eq('id', servicio['id']);

      // El Master vuelve a su fila — mismo flujo que cuando Central
      // cancela un servicio (ver canal radar_bg).
      if (_estaEnLinea) _intentarRegistroParadero();

      // CASCADA DE NOTIFICACIONES — reinicio limpio desde cero:
      // T=0: Masters, T=30s: paradero #1, T=60s: zona 1km, T=90s: todos
      final servicioId = servicio['id'] as int;
      final destino = servicio['destino']?.toString() ?? 'destino';
      final msgAlerta = '📍 Servicio liberado — disponible para: $destino';

      // T=0: notificar a todos los Masters
      final mastersData = await Supabase.instance.client
          .from('usuarios')
          .select('id')
          .or('rol.eq.central,rol.eq.master,rango_movil.eq.MASTER')
          .eq('activo', true)
          .neq('suspendido', true);
      final masterIds = mastersData.map((u) => u['id'].toString()).toList();
      if (masterIds.isNotEmpty) {
        await MotorNotificaciones.dispararRafa(
          idsDestinos: masterIds,
          titulo: '👑 SERVICIO LIBERADO',
          mensaje: msgAlerta,
        );
      }

      // T=30s: notificar al #1 de paradero
      final exclusivoStr = servicio['exclusivo_id']?.toString() ?? '';
      final paraderoIds = exclusivoStr.isEmpty
          ? <String>[]
          : exclusivoStr
              .split(',')
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty && !masterIds.contains(e))
              .toList();

      if (paraderoIds.isNotEmpty) {
        // Misil programado T+30s — guardar ID para cancelar si alguien acepta
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
              .eq('id', servicioId);
        }
      }

      // T=60s: motos en radio 1km (no Masters, no paradero ya notificado)
      // T=+60s y T=+90s — misiles server-side (OneSignal programa en sus servidores)
      // Pre-fetch al momento de liberar; onesignal_2m/5m se cancelan si alguien acepta
      final double? origLat = (servicio['origen_lat'] as num?)?.toDouble();
      final double? origLng = (servicio['origen_lng'] as num?)?.toDouble();
      final movilesLib = await Supabase.instance.client
          .from('usuarios').select('id, latitud, longitud')
          .eq('rol', 'movil').eq('en_linea', true)
          .neq('suspendido', true)
          .not('rango_movil', 'in', '("MASTER")');
      final idsZona60 = movilesLib.where((u) {
        final id = u['id'].toString();
        if (masterIds.contains(id) || paraderoIds.contains(id)) return false;
        if (origLat == null || origLng == null) return true;
        final uLat = (u['latitud'] as num?)?.toDouble();
        final uLng = (u['longitud'] as num?)?.toDouble();
        if (uLat == null || uLng == null) return false;
        return const Distance().as(
              LengthUnit.Meter, LatLng(uLat, uLng), LatLng(origLat, origLng),
            ) <= 1000;
      }).map((u) => u['id'].toString()).toList();
      final idsTodos90 = movilesLib
          .map((u) => u['id'].toString())
          .where((id) => !masterIds.contains(id))
          .toList();
      String? idLib60;
      String? idLib90;
      if (idsZona60.isNotEmpty) {
        idLib60 = await MotorNotificaciones.programarMisilRetardado(
          externalIds: idsZona60,
          titulo: '📡 SERVICIO CERCA (1km)',
          mensaje: msgAlerta,
          segundosRetardo: 60,
        );
      }
      if (idsTodos90.isNotEmpty) {
        idLib90 = await MotorNotificaciones.programarMisilRetardado(
          externalIds: idsTodos90,
          titulo: '🚨 SERVICIO SIN TOMAR',
          mensaje: msgAlerta,
          segundosRetardo: 90,
        );
      }
      if (idLib60 != null || idLib90 != null) {
        await Supabase.instance.client.from('servicios').update({
          if (idLib60 != null) 'onesignal_2m': idLib60,
          if (idLib90 != null) 'onesignal_5m': idLib90,
        }).eq('id', servicioId);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🔄 Servicio liberado — vuelve a empezar para todos.'),
            backgroundColor: Color(0xFFE040FB),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  // --- NUEVA FASE: EL CONDUCTOR LLEGA AL LOCAL Y CONGELA SU TIEMPO ---
  // =========================================================================
  // APRENDIZAJE DEL DIRECTORIO — captura GPS validado al llegar/
  // finalizar, y lo manda al directorio compartido (lugares_conocidos).
  // =========================================================================
  // Nunca bloquea ni avisa nada al moto — si la validación falla, el
  // punto simplemente se descarta en silencio. Dos chequeos:
  //   - DISTANCIA: si había una coordenada reclamada (origen_lat o
  //     destino_lat), el GPS actual debe estar a menos de 200m. Esto
  //     es lo que protege contra "marqué llegada 2 cuadras antes" o
  //     "finalicé 2 cuadras después de irme".
  //   - TIEMPO: si se da una hora de referencia, exige un mínimo
  //     físicamente razonable transcurrido (evita marcar instantes
  //     después de aceptar, imposible para la distancia real).
  Future<void> _intentarAprenderLugar({
    required String? textoDireccion,
    double? latReclamada,
    double? lngReclamada,
    DateTime? horaReferencia,
    int segundosMinimos = 30,
  }) async {
    if (textoDireccion == null || textoDireccion.trim().isEmpty) return;
    try {
      if (horaReferencia != null) {
        final transcurridos = DateTime.now()
            .toUtc()
            .difference(horaReferencia)
            .inSeconds;
        if (transcurridos < segundosMinimos) return;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      ).timeout(const Duration(seconds: 6));

      if (latReclamada != null && lngReclamada != null) {
        final distM = Geolocator.distanceBetween(
          pos.latitude,
          pos.longitude,
          latReclamada,
          lngReclamada,
        );
        if (distM > 200) return;
      }

      await Supabase.instance.client.rpc(
        'registrar_confirmacion_lugar',
        params: {
          'p_texto': textoDireccion,
          'p_lat': pos.latitude,
          'p_lng': pos.longitude,
        },
      );
    } catch (_) {
      // GPS, red, o RPC fallaron — se ignora. Nunca debe afectar el
      // flujo operativo del moto.
    }
  }

  Future<void> _marcarLlegadaOrigen(Map<String, dynamic> servicio) async {
    setState(() => _procesando = true);
    try {
      _sonidos.reproducirSuave(Sonidos.movilConfirmar); // Llegué al local
      await Supabase.instance.client
          .from('servicios')
          .update({'estado': 'en_origen'})
          .eq('id', servicio['id']);

      // --- INYECCIÓN: DISPARO AL LOCAL ---
      _notificarAlCreador(
        servicio['creador'] ?? 'Central',
        '📍 MÓVIL EN LA PUERTA',
        '${widget.usuario['nombre']} ha llegado a tu local por la Orden #${servicio['id']}.',
      );
      // -----------------------------------

      // Aprendizaje silencioso del directorio — no espera respuesta,
      // no bloquea la UI.
      DateTime? horaAceptado;
      try {
        if (servicio['accepted_at'] != null) {
          horaAceptado = DateTime.parse(servicio['accepted_at']).toUtc();
        }
      } catch (_) {}
      _intentarAprenderLugar(
        textoDireccion: servicio['origen'],
        latReclamada: (servicio['origen_lat'] as num?)?.toDouble(),
        lngReclamada: (servicio['origen_lng'] as num?)?.toDouble(),
        horaReferencia: horaAceptado,
        segundosMinimos: 45,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  void _mostrarMiHistorial(BuildContext context) {
    // Rango de fechas seleccionado — null = sin filtro (comportamiento
    // de siempre: todo el historial, "Producido Hoy" como antes).
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
          initialChildSize: 0.75,
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
              const Text(
                'VER HISTORIAL E INGRESOS',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  letterSpacing: 0.5,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 10),

              // --- FILTRO POR RANGO DE FECHAS + BORRAR HISTORIAL ---
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white70,
                          side: BorderSide(color: Colors.white30),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        onPressed: () async {
                          final ahora = DateTime.now();
                          final rango = await showDateRangePicker(
                            context: context,
                            firstDate: DateTime(ahora.year - 2),
                            lastDate: ahora,
                            initialDateRange: rangoSeleccionado,
                            helpText: 'SELECCIONA UN RANGO',
                            builder: (context, child) => Theme(
                              data: Theme.of(context).copyWith(
                                colorScheme: const ColorScheme.light(
                                  primary: Colors.black,
                                  onPrimary: Colors.white,
                                ),
                              ),
                              child: child!,
                            ),
                          );
                          if (rango != null) {
                            setModalState(() => rangoSeleccionado = rango);
                          }
                        },
                        icon: const Icon(Icons.calendar_month, size: 16),
                        label: Text(
                          rangoSeleccionado == null
                              ? 'Filtrar por fecha'
                              : '${rangoSeleccionado!.start.day}/${rangoSeleccionado!.start.month} - '
                                '${rangoSeleccionado!.end.day}/${rangoSeleccionado!.end.month}',
                          style: const TextStyle(fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    if (rangoSeleccionado != null)
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        tooltip: 'Quitar filtro',
                        onPressed: () =>
                            setModalState(() => rangoSeleccionado = null),
                      ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      tooltip: 'Borrar historial anterior a hoy',
                      onPressed: () =>
                          _confirmarBorrarHistorial(context, setModalState),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),

              Expanded(
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: () {
                    var query = Supabase.instance.client
                        .from('servicios')
                        .select()
                        .eq('movil_id', widget.usuario['id'])
                        .inFilter('estado', [
                          'finalizado',
                          'cancelado',
                          'finalizado_por_demora',
                          'finalizado_con_problema',
                        ])
                        // "Borrados" por el moto no se muestran en su
                        // propia vista — pero el registro real sigue
                        // intacto para calificaciones y reportes.
                        .or('oculto_movil.is.null,oculto_movil.eq.false');

                    if (rangoSeleccionado != null) {
                      final desde = DateTime(
                        rangoSeleccionado!.start.year,
                        rangoSeleccionado!.start.month,
                        rangoSeleccionado!.start.day,
                      );
                      final hasta = DateTime(
                        rangoSeleccionado!.end.year,
                        rangoSeleccionado!.end.month,
                        rangoSeleccionado!.end.day,
                      ).add(const Duration(days: 1));
                      query = query
                          .gte('created_at', desde.toUtc().toIso8601String())
                          .lt('created_at', hasta.toUtc().toIso8601String());
                    }

                    return query.order('id', ascending: false);
                  }(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      );
                    }
                    final historial = snapshot.data ?? [];

                    // Si hay rango seleccionado, sumamos todo lo que
                    // cayó en ese rango. Si no, mantenemos el
                    // comportamiento de siempre: solo HOY.
                    double producidoCalculado = 0;
                    final hoy = DateTime.now();
                    for (var servicio in historial) {
                      if (servicio['estado'] == 'finalizado' &&
                          servicio['created_at'] != null) {
                        if (rangoSeleccionado != null) {
                          if (servicio['tarifa'] != null && servicio['tarifa'] is num) {
                            producidoCalculado += (servicio['tarifa'] as num)
                                .toDouble();
                          }
                        } else {
                          final fechaSvc = DateTime.parse(
                            servicio['created_at'],
                          ).toLocal();
                          if (fechaSvc.year == hoy.year &&
                              fechaSvc.month == hoy.month &&
                              fechaSvc.day == hoy.day) {
                            if (servicio['tarifa'] != null && servicio['tarifa'] is num) {
                              producidoCalculado += (servicio['tarifa'] as num)
                                  .toDouble();
                            }
                          }
                        }
                      }
                    }
                    final String etiquetaProducido = rangoSeleccionado == null
                        ? 'PRODUCIDO HOY:'
                        : 'PRODUCIDO EN EL RANGO:';
                    return Column(
                      children: [
                        Container(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.green[50],
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.green[400]!),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                etiquetaProducido,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green,
                                ),
                              ),
                              Text(
                                _formatearMoneda(producidoCalculado, mostrarCero: true),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 22,
                                  color: Colors.black,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: historial.isEmpty
                              ? const Center(
                                  child: Text(
                                    'No registras órdenes finalizadas aún.',
                                    style: TextStyle(color: Colors.white54),
                                  ),
                                )
                              : ListView.builder(
                                  controller: scrollController,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  itemCount: historial.length,
                                  itemBuilder: (context, index) {
                                    final servicio = historial[index];
                                    final estado = servicio['estado'];
                                    Color colorTag = Colors.green;
                                    String label = 'FINALIZADO';
                                    if (estado == 'cancelado') {
                                      colorTag = Colors.black54;
                                      label = 'CANCELADO';
                                    } else if (estado ==
                                        'finalizado_por_demora') {
                                      colorTag = Colors.deepPurple;
                                      label = 'RETRASADO';
                                    } else if (estado ==
                                            'finalizado_con_problema' ||
                                        (servicio['observacion'] ?? '').contains(
                                          '[MARCA DE FALLA]',
                                        )) {
                                      colorTag = Colors.red[700]!;
                                      label = 'CON FALLA';
                                    }
                                    return Card(
                                      margin: const EdgeInsets.only(bottom: 10),
                                      elevation: 1,
                                      child: ListTile(
                                        dense: true,
                                        title: Text(
                                          'Orden #${servicio['id']} | ${servicio['origen']} ➔ ${servicio['destino']}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        subtitle: Text(
                                          servicio['observacion'] ??
                                              'Operación finalizada sin novedades.',
                                        ),
                                        trailing: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.end,
                                          children: [
                                            Text(
                                              _formatearMoneda(servicio['tarifa']),
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 6,
                                                vertical: 2,
                                              ),
                                              decoration: BoxDecoration(
                                                color: colorTag,
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                label,
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 8,
                                                ),
                                              ),
                                            ),
                                          ],
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
            ],
          ),
        ),
      ),
    );
  }

  // Borra (oculta) el historial ANTERIOR a hoy. Lo de hoy nunca se
  // toca, sin importar la hora a la que se ejecute esto — se compara
  // contra la medianoche local del día actual, no contra "ahora".
  Future<void> _confirmarBorrarHistorial(
    BuildContext context,
    StateSetter setModalState,
  ) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Borrar historial anterior'),
        content: const Text(
          'Se ocultará de tu historial todo lo de días ANTERIORES a hoy. '
          'Los servicios de hoy no se ven afectados.\n\n'
          'Esto no cambia tu calificación ni los reportes de Central — '
          'solo limpia lo que tú ves en esta pantalla.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red[800]),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'BORRAR',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    try {
      final ahora = DateTime.now();
      final inicioHoyLocal = DateTime(ahora.year, ahora.month, ahora.day);
      final inicioHoyUtc = inicioHoyLocal.toUtc().toIso8601String();

      await Supabase.instance.client
          .from('servicios')
          .update({'oculto_movil': true})
          .eq('movil_id', widget.usuario['id'])
          .lt('created_at', inicioHoyUtc);

      setModalState(() {}); // refresca el FutureBuilder con la nueva query

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Historial anterior borrado de tu vista.'),
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
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        title: Text(
          'PANEL | ${(widget.usuario['usuario'] ?? '').toString().toUpperCase()}',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.black,
        iconTheme: IconThemeData(color: Colors.white),
        actions: [
          // AppBar simplificado: Perfil, Ranking y Cerrar sesión ahora
          // viven en la pestaña de Perfil — el AppBar solo conserva lo
          // que debe estar accesible SIEMPRE sin importar la pestaña:
          // la alerta de pánico, por seguridad.

          // ALERTA DE PÁNICO — solo visible en 2 casos:
          // 1. Ya hay una activa → botón pulsante para DETENERLA.
          // 2. Hay un servicio en curso Y no se ha usado hoy → botón para disparar.
          // Fuera de servicio o ya usado: botón oculto (reduce abuso en fases de prueba).
          if (_eventoPanicoActivoId != null &&
              _panicoUbicacionExpiraAt != null &&
              DateTime.now().toUtc().isBefore(_panicoUbicacionExpiraAt!))
            PulsingPanicoButton(
              color: Colors.red,
              child: IconButton(
                icon: const Icon(Icons.shield_rounded, color: Colors.red),
                tooltip: 'Tu alerta sigue activa — toca para detenerla',
                onPressed: () => _detenerMiAlertaPanico(),
              ),
            )
          else if (_tieneServicioActivo && !_panicoUsadoHoy)
            BotonPanicoTrigger(
              esCompacto: true,
              segundos: 2,
              icono: Icons.shield_rounded,
              colorAcento: Colors.red,
              titulo: 'ALERTA DE PÁNICO',
              descripcion:
                  'Se notificará a Central y a todos los móviles en línea. Usa esto solo en una emergencia real.',
              onActivado: _dispararPanico,
            ),
          const SizedBox(width: 6),
        ],
      ),
      // ---> INYECCIÓN: BOTÓN FLOTANTE (SOLO APARECE EN EMERGENCIA) <---
      floatingActionButton: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _streamUsuarios,
        builder: (context, snapUsuarios) {
          bool alarmaSoporte = false;
          if (snapUsuarios.hasData) {
            final miPerfil = snapUsuarios.data!.firstWhere(
              (u) => u['id'] == widget.usuario['id'],
              orElse: () => widget.usuario,
            );
            alarmaSoporte = miPerfil['chat_central'] == true;
          }

          WidgetsBinding.instance.addPostFrameCallback((_) async {
            if (mounted) {
              if (alarmaSoporte && !_sonidoSoporteReproducido) {
                _sonidoSoporteReproducido = true;
                _sonidos.reproducir(
                  Sonidos.movilChatCentral,
                ); // Mensaje urgente de Central
              } else if (!alarmaSoporte) {
                _sonidoSoporteReproducido = false;
              }
            }
          });

          // 1. SI NO HAY ALARMA, SE DESAPARECE POR COMPLETO (PANTALLA LIMPIA)
          if (!alarmaSoporte) return const SizedBox.shrink();

          // 2. SI HAY ALARMA, SALE EL BOTÓN ROJO QUE ABRE EL CHAT CON CENTRAL
          return FloatingActionButton.extended(
            backgroundColor: Colors.red[700],
            icon: Icon(Icons.support_agent, color: Colors.white),
            label: Text('Central', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            onPressed: () {
              // Apaga la alarma antes de entrar al chat
              Supabase.instance.client
                  .from('usuarios')
                  .update({'chat_central': false})
                  .eq('id', widget.usuario['id']);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ChatScreen(
                    salaId: 'soporte_${widget.usuario['id']}',
                    miId: widget.usuario['id'] as int,
                    miNombre: widget.usuario['nombre'] as String? ?? 'Móvil',
                    titulo: 'Central',
                    usuarioId: widget.usuario['id'] as int?,
                    alarmaLocal: 'chat_central',    // limpia flag en usuarios al abrir
                    alarmaDestino: 'alarma_soporte', // avisa a Central al escribir
                    tipoFaq: TipoFaqChat.movil,
                  ),
                ),
              );
            },
          );
        },
      ),
      // -----------------------------------------------------------------
      // IndexedStack mantiene ambas pestañas vivas en el árbol de widgets,
      // así el radar sigue recibiendo datos del stream mientras el móvil
      // está en Perfil — sin spinner al volver.
      // OPTIMIZACIÓN: ValueListenableBuilder reconstruye solo el body
      // (no AppBar/FAB/BottomNav) cuando _radarTick incrementa cada 5s.
      body: ValueListenableBuilder<int>(
        valueListenable: _radarTick,
        builder: (context, _, __) => IndexedStack(
          index: _tabActual,
          children: [
          StreamBuilder<List<Map<String, dynamic>>>(
        stream: _streamUsuarios,
        initialData: _cacheUsuarios, // evita el spinner al volver de Perfil
        builder: (context, snapUsuarios) {
          if (!snapUsuarios.hasData)
            return const Center(
              child: CircularProgressIndicator(color: Colors.black),
            );

          final usuariosTotales = snapUsuarios.data!;
          final miPerfilEnVivo = usuariosTotales.firstWhere(
            (u) => u['id'].toString() == widget.usuario['id'].toString(),
            orElse: () => widget.usuario,
          );

          // La base de datos es la única fuente de verdad.
          final String? paraderoActual =
              miPerfilEnVivo['paradero_actual'] as String?;

          final enFila = usuariosTotales
              .where(
                (u) =>
                    u['en_linea'] == true &&
                    u['paradero_actual'] != null &&
                    u['ingreso_fila'] != null,
              )
              .toList();
          enFila.sort((a, b) {
            final tA = a['ticket_prioridad'] == true ? 1 : 0;
            final tB = b['ticket_prioridad'] == true ? 1 : 0;
            if (tA != tB) return tB.compareTo(tA);
            return DateTime.parse(a['ingreso_fila']).compareTo(DateTime.parse(b['ingreso_fila']));
          });

          bool radarAbierto = false;
          String mensajeBloqueo = '';
          final bool esMaster =
              miPerfilEnVivo['rango_movil']?.toString().toUpperCase() ==
              'MASTER';

          if (paraderoActual == null) {
            if (esMaster) {
              radarAbierto = true;
            } else {
              radarAbierto = false;
              mensajeBloqueo = enFila.isEmpty
                  ? 'Radar bloqueado.\nDirígete a un paradero y regístrate para recibir pedidos.'
                  : 'Hay compañeros en fila.\nDirígete a un paradero y regístrate para entrar en turno.';
            }
          } else {
            // BLINDAJE TÁCTICO: Solo comparamos tu turno contra los que están en tu MISMO paradero
            final miFila = enFila
                .where((u) => u['paradero_actual'] == paraderoActual)
                .toList();
            final miTurnoIndex = miFila.indexWhere(
              (u) => u['id'].toString() == widget.usuario['id'].toString(),
            );

            if (miTurnoIndex == 0 || miFila.isEmpty) {
              radarAbierto = true;
            } else if (miTurnoIndex > 0) {
              radarAbierto = false;
              mensajeBloqueo =
                  'Estás en la posición #${miTurnoIndex + 1} de la fila $paraderoActual.\nEspera tu turno para recibir servicios.';
            } else {
              radarAbierto = false;
              mensajeBloqueo = 'Sincronizando tu turno con la Central...';
            }
          }

          // ---> HEADER REDISEÑADO: card style consistente con Perfil <---
          final Color _statusColor = _estaEnLinea
              ? (paraderoActual != null ? Colors.blue : const Color(0xff3AF500))
              : Colors.grey;
          final String _statusLabel = !_estaEnLinea
              ? 'Fuera de Servicio'
              : paraderoActual != null
                  ? 'En paradero'
                  : 'Activo · Sin paradero';

          return Column(
            children: [
              Container(
                margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.grey[200]!),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(
                    children: [
                      // Ícono de estado en círculo de color — anima al cambiar
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 350),
                        curve: Curves.easeOut,
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: _statusColor.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          child: Icon(
                            key: ValueKey(_statusLabel),
                            _estaEnLinea
                                ? (paraderoActual != null
                                    ? Icons.location_on
                                    : Icons.gps_fixed)
                                : Icons.gps_off,
                            color: _statusColor,
                            size: 22,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Estado + paradero
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          transitionBuilder: (child, anim) => FadeTransition(
                            opacity: anim,
                            child: SlideTransition(
                              position: Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero)
                                  .animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
                              child: child,
                            ),
                          ),
                          child: Column(
                            key: ValueKey('$_statusLabel::${paraderoActual ?? ''}'),
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                            Text(
                              _statusLabel,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: Colors.black87,
                              ),
                            ),
                            if (paraderoActual != null)
                              Text(
                                paraderoActual,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey[600],
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Botón conectar/desconectar — anima color + texto
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 350),
                        curve: Curves.easeOut,
                        decoration: BoxDecoration(
                          color: _estaEnLinea ? Colors.red[800] : Colors.black,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 18, vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onPressed: _procesando ? null : _cambiarEstado,
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 220),
                            child: _procesando
                                ? SizedBox(
                                    key: ValueKey('loading'),
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text(
                                    key: ValueKey(_estaEnLinea),
                                    _estaEnLinea ? 'DESCONECTAR' : 'CONECTARSE',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: _estaEnLinea
                                          ? Colors.white
                                          : const Color(0xff3AF500),
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 400),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: child,
                  ),
                  child: !_estaEnLinea
                    ? const Center(
                        key: ValueKey('offline_area'),
                        child: Text(
                          'ESTÁS FUERA DE LÍNEA\nConéctate para recibir servicios.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.grey,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      )
                    : StreamBuilder<List<Map<String, dynamic>>>(
                        key: const ValueKey('online_area'),
                        stream: _streamServicios,
                        initialData: _cacheServicios, // evita spinner al conectarse
                        builder: (context, snapshot) {
                          if (!snapshot.hasData)
                            return const Center(
                              child: CircularProgressIndicator(
                                color: Colors.black,
                              ),
                            );
                          final todos = snapshot.data ?? [];

                          _serviciosActivosData = todos
                              .where(
                                (s) =>
                                    s['movil_id'] == widget.usuario['id'] &&
                                    [
                                      'en_ruta_origen',
                                      'en_origen',
                                      'en_ruta_destino',
                                      'problema',
                                    ].contains(s['estado']) &&
                                    !_serviciosOcultosLocales.contains(s['id']),
                              )
                              .toList();

                          // SAFETY NET: si el móvil reconecta con un servicio activo
                          // pero paradero_actual quedó sucio de la sesión anterior,
                          // lo expulsamos de la fila automáticamente.
                          if (_miParaderoCache != null &&
                              _serviciosActivosData.isNotEmpty) {
                            final _paraderoQueDejo = _miParaderoCache;
                            _miParaderoCache = null; // evita re-disparar en siguientes builds
                            WidgetsBinding.instance.addPostFrameCallback((_) async {
                              if (!mounted) {
                                _miParaderoCache = _paraderoQueDejo;
                                return;
                              }
                              try {
                                await Supabase.instance.client
                                    .from('usuarios')
                                    .update({
                                      'paradero_actual': null,
                                      'ingreso_fila': null,
                                    })
                                    .eq('id', widget.usuario['id']);
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        '📍 Tienes un servicio activo — te sacamos de la fila $_paraderoQueDejo.',
                                      ),
                                      backgroundColor: Colors.orange[800],
                                      duration: const Duration(seconds: 4),
                                    ),
                                  );
                                }
                              } catch (_) {
                                _miParaderoCache = _paraderoQueDejo; // reintento en próximo tick
                              }
                            });
                          }

                          // Actualizar _tieneServicioActivo en el próximo frame
                          // para que el AppBar lo refleje sin llamar setState dentro de build().
                          final hayServicio = _serviciosActivosData.isNotEmpty;
                          if (hayServicio != _tieneServicioActivo) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted) setState(() => _tieneServicioActivo = hayServicio);
                            });
                          }

                          // Límite de servicios simultáneos según rango
                          final int limiteRango = _limitePorRango(
                            miPerfilEnVivo['rango_movil']?.toString(),
                          );
                          final bool tieneCapacidad =
                              _serviciosActivosData.length < limiteRango;
                          bool tienePermisoDeRadar =
                              tieneCapacidad && radarAbierto;

                          // --- EMBUDO TÁCTICO DE TIEMPOS Y PARADEROS (JERARQUÍA MASTER) ---
                          final ahoraUtc = DateTime.now().toUtc();
                          List<Map<String, dynamic>> pendientes = [];

                          final bool esMaster =
                              miPerfilEnVivo['rango_movil']
                                  ?.toString()
                                  .toUpperCase() ==
                              'MASTER';
                          final String miId = widget.usuario['id'].toString();
                          final Distance medidorDistancia = const Distance();

                          // Helper: tiempo canónico de un servicio (GREATEST fix)
                          DateTime _canonTime(Map<String, dynamic> s) {
                            final ca = s['created_at'] != null
                                ? DateTime.parse(s['created_at']).toUtc()
                                : ahoraUtc;
                            final lib = s['liberacion_at'] != null
                                ? DateTime.parse(s['liberacion_at']).toUtc()
                                : null;
                            return (lib != null && lib.isAfter(ca)) ? lib : ca;
                          }

                          // Helper: si exclusivo_id incluye este móvil
                          // (puede ser "id1,id2,..." para multi-paradero)
                          bool _esExclusivoMio(String excl) =>
                              excl.split(',').map((e) => e.trim()).contains(miId);

                          // PRE-CÁLCULO FASE 1 — EL #1 DEL PARADERO SOLO VE 1 SERVICIO.
                          // Regla: el más antiguo de los servicios en FASE 1
                          // que le corresponden a este móvil (exclusivo o abierto).
                          // Los 14 restantes permanecen ocultos hasta que él tome
                          // ese uno y el #2 suba al #1.
                          int? soloFase1Id;
                          if (!esMaster && radarAbierto) {
                            final candidatosFase1 = todos.where((x) {
                              if (x['estado'] != 'pendiente') return false;
                              if (_serviciosOcultosLocales.contains(x['id'])) return false;
                              final secs = ahoraUtc.difference(_canonTime(x)).inSeconds;
                              if (secs < 30 || secs >= 60) return false; // Solo FASE 1 (30s–60s)
                              final excl = x['exclusivo_id']?.toString() ?? '';
                              // Le corresponde si es exclusivo suyo O si no tiene exclusivo
                              return excl.isEmpty || _esExclusivoMio(excl);
                            }).toList();

                            if (candidatosFase1.isNotEmpty) {
                              candidatosFase1.sort(
                                (a, b) => _canonTime(a).compareTo(_canonTime(b)));
                              soloFase1Id = candidatosFase1.first['id'] as int;
                            }
                          }

                          for (var s in todos.where(
                            (x) => x['estado'] == 'pendiente',
                          )) {
                            if (_serviciosOcultosLocales.contains(s['id']))
                              continue;

                            // 1. Leemos el reloj inteligente (GREATEST fix)
                            final targetUtc = _canonTime(s);
                            final int segundos = ahoraUtc
                                .difference(targetUtc)
                                .inSeconds;

                            // 2. FILTRO FANTASMA (Diferidos):
                            if (segundos < 0 && !esMaster) continue;

                            bool puedeVer = false;
                            final String exclusivoId =
                                s['exclusivo_id']?.toString() ?? '';

                            // ─── REGLA FN (FARMANORTE) ────────────────────────
                            // Lógica propia: ignora paradero y embudo estándar.
                            //   T=0 a T+30s : solo motos en fn_primera_ola
                            //   T+31s+      : todos con tiene_fn = true
                            if (s['tipo_fn'] == true) {
                              final bool tienePermFN = esMaster ||
                                  miPerfilEnVivo['tiene_fn'] == true;
                              if (tienePermFN && tieneCapacidad) {
                                final primeraOlaRaw = s['fn_primera_ola'];
                                final List<String> primeraOla =
                                    primeraOlaRaw is List
                                        ? (primeraOlaRaw as List)
                                            .map((e) => e.toString())
                                            .toList()
                                        : [];
                                if (primeraOla.isEmpty ||
                                    primeraOla.contains(miId)) {
                                  // En primera ola o sin restricción → visible desde T=0
                                  puedeVer = true;
                                } else if (segundos >= 31) {
                                  // Segunda ola → visible a partir de T+31s
                                  puedeVer = true;
                                }
                              }
                              if (puedeVer) pendientes.add(s);
                              continue; // salta embudo estándar
                            }

                            // 3. CÁLCULO DE DISTANCIA OPERATIVA DESDE EL LOCAL
                            double distMetros = 999999;
                            if (_ultimaPosicionConocida != null &&
                                s['origen_lat'] != null &&
                                s['origen_lng'] != null) {
                              distMetros = medidorDistancia.as(
                                LengthUnit.Meter,
                                LatLng(
                                  _ultimaPosicionConocida!.latitude,
                                  _ultimaPosicionConocida!.longitude,
                                ),
                                LatLng(
                                  (s['origen_lat'] as num).toDouble(),
                                  (s['origen_lng'] as num).toDouble(),
                                ),
                              );
                            }

                            // 4. REGLA SUPREMA: MASTERS VEN todo (T=0)
                            if (esMaster) {
                              puedeVer = true;
                            }
                            // 5. EMBUDO DE TIEMPO — 4 FASES DE 30s (total 2 min)
                            else {
                              if (segundos < 30) {
                                // FASE 0: (0–29s) — PUNTO CIEGO
                                // Exclusivo del Master. Nadie más lo ve.
                                puedeVer = false;
                              } else if (segundos < 60) {
                                // FASE 1: (30–59s) — Prioridad Paradero Estricta
                                // El #1 del paradero solo ve 1 servicio: el más antiguo
                                // de la cola (soloFase1Id). Los demás quedan en espera.
                                // Si el servicio tiene exclusivo_id, solo lo ve ese móvil.
                                final bool esElMioExclusivo =
                                    exclusivoId.isNotEmpty && _esExclusivoMio(exclusivoId);
                                final bool esElUnico =
                                    exclusivoId.isEmpty &&
                                    tienePermisoDeRadar &&
                                    (s['id'] as int) == soloFase1Id;
                                if (esElMioExclusivo && (s['id'] as int) == soloFase1Id) {
                                  puedeVer = true;
                                } else if (esElUnico) {
                                  puedeVer = true;
                                }
                              } else if (segundos < 90) {
                                // FASE 2: (60–89s) — Radar Zonal 1km
                                // Se rompe el candado del paradero. Capacidad según rango.
                                if (tieneCapacidad && distMetros <= 1000) {
                                  puedeVer = true;
                                }
                              } else {
                                // FASE 3: (90s+) — Todos los disponibles
                                // Todos los rangos con capacidad disponible pueden ver.
                                if (tieneCapacidad) {
                                  puedeVer = true;
                                }
                              }
                            }

                            if (puedeVer) {
                              pendientes.add(s);
                            }
                          }
                          // --- ORDENAMIENTO FIFO ABSOLUTO ---
                          // El primero que pidió (o el que más tiempo lleva esperando) sale de primero.
                          if (pendientes.isNotEmpty) {
                            // _canonTime ya está definido arriba — reutilizamos
                            pendientes.sort(
                              (a, b) => _canonTime(a).compareTo(_canonTime(b)));
                          }
                          // --------------------------------------------------------

                          // --- AUTO-EXPANSIÓN INDEPENDIENTE ---
                          // Cada tarjeta nueva se expande automáticamente.
                          // Las ya abiertas no se cierran. El usuario puede
                          // plegar/desplegar cada una por separado.
                          for (final s in _serviciosActivosData) {
                            _serviciosExpandidos.add(s['id'] as int);
                          }
                          // Limpiar IDs de servicios que ya no existen.
                          _serviciosExpandidos.removeWhere(
                            (id) => !_serviciosActivosData.any((s) => s['id'] == id),
                          );

                          /// --- ALARMA DE NUEVO PEDIDO ---
                          WidgetsBinding.instance.addPostFrameCallback((
                            _,
                          ) async {
                            if (mounted) {
                              // INYECCIÓN TÁCTICA: Permite sonar si tienes permiso O SI un misil rompió el candado (pendientes.isNotEmpty)
                              if ((tienePermisoDeRadar ||
                                      pendientes.isNotEmpty) &&
                                  pendientes.length >
                                      _cantidadPendientesAnterior) {
                                if (!_reproduciendoAudio) {
                                  _reproduciendoAudio = true;

                                  // 1. Disparo Auditivo
                                  _sonidos.reproducir(Sonidos.alerta);

                                  // 2. Disparo Visual (Notificación emergente tipo WhatsApp en el TECHO)
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Row(
                                        children: [
                                          Icon(
                                            Icons.radar,
                                            color: Colors.white,
                                            size: 28,
                                          ),
                                          SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  '🚨 ¡NUEVO SERVICIO EN RADAR!',
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 14,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                                Text(
                                                  'Revisa el radar para ver el servicio.',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.white70,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                      backgroundColor: Colors.green,
                                      duration: const Duration(seconds: 4),
                                      behavior: SnackBarBehavior.floating,
                                      // ---> MAGIA MATEMÁTICA: Lo empuja hasta el techo de la pantalla <---
                                      margin: EdgeInsets.only(
                                        bottom:
                                            MediaQuery.of(context).size.height -
                                            150,
                                        left: 12,
                                        right: 12,
                                      ),
                                      dismissDirection: DismissDirection.up,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      elevation: 10,
                                    ),
                                  );

                                  // Seguro táctico para que el audio no se superponga si caen 3 pedidos de golpe
                                  Future.delayed(
                                    const Duration(seconds: 2),
                                    () {
                                      if (mounted) _reproduciendoAudio = false;
                                    },
                                  );
                                }
                              }
                              // Actualizamos la memoria del radar
                              _cantidadPendientesAnterior = pendientes.length;
                            }
                          });

                          // ---> INYECCIÓN: CÁLCULO DE CAJA EN VIVO <---
                          double producidoHoy = 0.0;
                          final hoyLocal = DateTime.now().toLocal();
                          for (var s in todos) {
                            if (s['estado'] == 'finalizado' &&
                                s['movil_id'] == widget.usuario['id'] &&
                                s['created_at'] != null) {
                              final fechaSvc = DateTime.parse(
                                s['created_at'],
                              ).toLocal();
                              if (fechaSvc.year == hoyLocal.year &&
                                  fechaSvc.month == hoyLocal.month &&
                                  fechaSvc.day == hoyLocal.day) {
                                producidoHoy +=
                                    (s['tarifa'] as num?)?.toDouble() ?? 0.0;
                              }
                            }
                          }
                          // --------------------------------------------

                          return ListView(
                            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                            children: [
                              if (_estaEnLinea)
                                Container(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.grey[200]!),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(Icons.bar_chart,
                                          size: 14, color: Colors.black45),
                                      const SizedBox(width: 6),
                                      const Text(
                                        'PRODUCIDO HOY',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.black45,
                                          letterSpacing: 0.8,
                                        ),
                                      ),
                                      const Spacer(),
                                      Text(
                                        _formatearMoneda(producidoHoy,
                                            mostrarCero: true),
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.green[700],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              // -------------------------------------------
                              if (_serviciosActivosData.isEmpty) ...[
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(14),
                                  margin: const EdgeInsets.only(bottom: 8),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: Colors.grey[300]!),
                                  ),
                                  child: Column(
                                    children: [
                                      if (paraderoActual == null) ...[
                                        Text(
                                          'No estás en la fila de ningún paradero',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 13,
                                            color: Colors.grey[800],
                                          ),
                                        ),
                                        const SizedBox(height: 10),
                                        SizedBox(
                                          width: double.infinity,
                                          child: ElevatedButton.icon(
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.black,
                                              padding: const EdgeInsets.symmetric(vertical: 12),
                                            ),
                                            onPressed: _procesando
                                                ? null
                                                : _intentarRegistroParadero,
                                            icon: const Icon(
                                              Icons.location_on,
                                              color: Color(0xff3AF500),
                                              size: 18,
                                            ),
                                            label: _procesando
                                                ? SizedBox(
                                                    width: 16,
                                                    height: 16,
                                                    child:
                                                        CircularProgressIndicator(
                                                          color: Colors.white,
                                                          strokeWidth: 2,
                                                        ),
                                                  )
                                                : const Text(
                                                    'REGISTRARME EN PARADERO',
                                                    style: TextStyle(
                                                      color: Color(0xff3AF500),
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: 13,
                                                    ),
                                                  ),
                                          ),
                                        ),
                                      ] else ...[
                                        Row(
                                          children: [
                                            Container(
                                              width: 8,
                                              height: 8,
                                              decoration: const BoxDecoration(
                                                color: Color(0xff3AF500),
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              'En fila: $paraderoActual',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w600,
                                                fontSize: 13,
                                                color: Colors.grey[800],
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 10),
                                        SizedBox(
                                          width: double.infinity,
                                          child: OutlinedButton.icon(
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor: Colors.red,
                                              side: const BorderSide(
                                                color: Colors.red,
                                              ),
                                            ),
                                            onPressed: _procesando
                                                ? null
                                                : _salirDelParadero,
                                            icon: const Icon(
                                              Icons.exit_to_app,
                                              size: 16,
                                            ),
                                            label: const Text(
                                              'SALIR DEL PARADERO',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 11,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                _construirFilaVirtual(usuariosTotales),
                                const SizedBox(height: 10),
                              ],

                              // ---- TARJETA DOMICILIO ACTIVO ----
                              if (_pedidoDomicilioActivo != null)
                                _buildTarjetaDomicilio(),

                              if (_serviciosActivosData.isNotEmpty) ...[
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 6, left: 2, top: 4),
                                  child: Row(children: [
                                    Icon(Icons.local_shipping_outlined, size: 13, color: Colors.black38),
                                    const SizedBox(width: 5),
                                    const Text(
                                      'ÓRDENES EN CURSO',
                                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black38, letterSpacing: 0.8),
                                    ),
                                  ]),
                                ),
                                ..._serviciosActivosData.map(
                                  (servicio) => AnimatedSize(
                                    key: ValueKey('size_activa_${servicio['id']}'),
                                    duration: const Duration(milliseconds: 280),
                                    curve: Curves.easeInOut,
                                    alignment: Alignment.topCenter,
                                    child: FadeSlideIn(
                                      key: ValueKey('activa_${servicio['id']}'),
                                      child: _construirTarjetaActiva(
                                        servicio,
                                        esMaster: esMaster,
                                      ),
                                    ),
                                  ),
                                ),
                              ],

                              // ---> DESTRUCCIÓN DEL CANDADO VISUAL AQUÍ <---
                              if (tienePermisoDeRadar ||
                                  pendientes.isNotEmpty) ...[
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 6, left: 2, top: 4),
                                  child: Row(children: [
                                    Icon(Icons.radar, size: 13, color: Colors.black38),
                                    const SizedBox(width: 5),
                                    const Text(
                                      'RADAR DE DISPONIBLES',
                                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black38, letterSpacing: 0.8),
                                    ),
                                  ]),
                                ),
                                if (pendientes.isEmpty)
                                  const Padding(
                                    padding: EdgeInsets.only(top: 20),
                                    child: Center(
                                      child: Text(
                                        'Radar limpio. Sin Servicios.',
                                        style: TextStyle(
                                          color: Colors.grey,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  )
                                else
                                  ...pendientes.map(
                                    (servicio) => FadeSlideIn(
                                      key: ValueKey('pendiente_${servicio['id']}'),
                                      child: _construirTarjetaPendiente(
                                        servicio,
                                        esMaster: esMaster,
                                      ),
                                    ),
                                  ),
                              ] else if (_serviciosActivosData.isEmpty &&
                                  !radarAbierto) ...[
                                Padding(
                                  padding: const EdgeInsets.only(top: 10),
                                  child: Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: Colors.orange[50]!,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: Colors.orange[200]!),
                                    ),
                                    child: Column(
                                      children: [
                                        Icon(
                                          Icons.lock_clock_outlined,
                                          color: Colors.orange[700],
                                          size: 32,
                                        ),
                                        const SizedBox(height: 10),
                                        Text(
                                          mensajeBloqueo.isNotEmpty
                                              ? mensajeBloqueo
                                              : 'Regístrate en un paradero para recibir servicios.',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: Colors.orange[900],
                                            fontWeight: FontWeight.w500,
                                            height: 1.4,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          );
                        },
                      ),
                ),
              ),
            ],
          );
        },
          ),
        _construirPerfilTab(),
        ],
        ), // IndexedStack
      ), // ValueListenableBuilder
    bottomNavigationBar: BottomNavigationBar(
      currentIndex: _tabActual,
      onTap: _cambiarTab,
      selectedItemColor: const Color(0xff3AF500),
      unselectedItemColor: Colors.white38,
      backgroundColor: const Color(0xFF0D0D0D),
      type: BottomNavigationBarType.fixed,
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.radar),
          label: 'Servicios',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.person_outline),
          label: 'Perfil',
        ),
      ],
    ),
  );
}
}

// ===========================================================================
// PAINTER: Overlay circular oscuro con hueco (tutorial de pantalla)
// ===========================================================================
