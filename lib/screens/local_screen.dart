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

class LocalScreen extends StatefulWidget {
  final Map<String, dynamic> usuario;
  const LocalScreen({super.key, required this.usuario});

  @override
  State<LocalScreen> createState() => _LocalScreenState();
}

class _LocalScreenState extends State<LocalScreen>
    with WidgetsBindingObserver {
  // Memoria táctica para ocultar servicios del panel de hoy
  final Set<int> _serviciosOcultosLocal = {};
  // Expansión de tarjetas de servicio en local_screen:
  //   activas empiezan expandidas (se guarda cuando el usuario las COLAPSA)
  //   historial empieza colapsado (se guarda cuando el usuario las EXPANDE)
  final Set<int> _tarjetasColapsadasLocal = {};  // activos contraídos
  final Set<int> _tarjetasExpandidasLocal = {};  // historial expandido

  // ---> INYECCIÓN: Controladores locales para la persistencia del perfil
  final _telLocalController = TextEditingController();
  final _instruccionesController = TextEditingController();
  String _tipoServicioDefecto = 'COMIDA';
  bool _perfilCargado = false;
  bool _guardandoPerfil = false;
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
        if (!_ctrlPerfilPropio.isClosed) _ctrlPerfilPropio.add(data);
      },
      onError: (e) {
        if (!_ctrlPerfilPropio.isClosed) _ctrlPerfilPropio.addError(e);
      },
    );
    _subServiciosLocal = crudoServicios.listen(
      (data) {
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
    _sonidos.silenciar();
    super.dispose();
  }

  void _mostrarHistorialGlobal(BuildContext context) {
    // Future cacheado ANTES del builder para que setModalState no lo recree.
    final futureHistorial = Supabase.instance.client
        .from('servicios')
        .select()
        .eq('local_id', widget.usuario['id'])
        .inFilter('estado', [
          'finalizado',
          'cancelado',
          'caducado',
          'finalizado_por_demora',
          'finalizado_con_problema',
        ])
        .or('oculto_local.is.null,oculto_local.eq.false')
        .order('created_at', ascending: false)
        .limit(100);

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
                'HISTORIAL COMPLETO',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: futureHistorial,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      );
                    }

                    // FIX #5: el filtro ya viaja en la query, no se necesita .where() aquí
                    final historialGlobal = snapshot.data ?? [];

                    if (historialGlobal.isEmpty) {
                      return const Center(
                        child: Text(
                          'No hay registros en tu auditoría.',
                          style: TextStyle(
                            color: Colors.white54,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      );
                    }

                    return ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.all(16),
                      itemCount: historialGlobal.length,
                      itemBuilder: (context, index) {
                        return _construirTarjetaServicio(
                          historialGlobal[index],
                          esHistorial: true,
                          esGlobal: true,
                          extraRebuild: () => setModalState(() {}),
                          onEliminar: () async {
                            final confirmar = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text(
                                  '⚠️ ELIMINAR REGISTRO',
                                  style: TextStyle(
                                    color: Colors.red,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                content: const Text(
                                  '¿Estás seguro de que quieres borrar este pedido? Desaparecerá de tu historial para siempre.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: const Text(
                                      'CANCELAR',
                                      style: TextStyle(color: Colors.grey),
                                    ),
                                  ),
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.red[900],
                                    ),
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: Text(
                                      'SÍ, BORRAR',
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
                              // Disparamos el borrado fantasma a la base de datos
                              await Supabase.instance.client
                                  .from('servicios')
                                  .update({'oculto_local': true})
                                  .eq('id', historialGlobal[index]['id']);

                              // Recargamos el panel en vivo
                              setModalState(() {});
                            }
                          },
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

  // =========================================================================
  // BÚSQUEDA DE DIRECCIONES POR TELÉFONO — reutilizable
  // =========================================================================
  // Extraída de la lógica original del autocompletado en el formulario.
  // La usan: el campo de WhatsApp (al escribir) Y el botón "NUEVO PEDIDO"
  // desde el CRM (precarga antes de abrir el formulario).
  Future<List<Map<String, dynamic>>> _buscarDireccionesPorTelefono(
    String telefono,
  ) async {
    try {
      final res = await Supabase.instance.client
          .from('servicios')
          .select('destino, tarifa')
          .eq('telefono_receptor', telefono)
          .eq('local_id', widget.usuario['id'])
          .not('destino', 'is', null)
          .order('id', ascending: false)
          .limit(20);

      if (res.isEmpty) return [];

      // Filtro anti-duplicados — normaliza a mayúsculas
      final mapUnicos = <String, Map<String, dynamic>>{};
      for (var r in res) {
        String destinoNormalizado = r['destino'].toString().trim().toUpperCase();
        if (!mapUnicos.containsKey(destinoNormalizado)) {
          mapUnicos[destinoNormalizado] = r;
        }
      }
      // Corte táctico a las 3 más recientes
      return mapUnicos.values.take(3).toList();
    } catch (_) {
      return [];
    }
  }

  // =========================================================================
  // MÓDULO CRM: DIRECTORIO INTELIGENTE DE CLIENTES (VERSIÓN VOLUMEN)
  // =========================================================================
  void _abrirCRMLocal(
    BuildContext contextoPrincipal,
    Map<String, dynamic> perfilEnVivo,
  ) {
    String filtroActual = '';

    showModalBottomSheet(
      context: contextoPrincipal,
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
              const Text(
                '👥 DIRECTORIO DE CLIENTES (CRM)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
              ),
              const Text(
                'Fidelización y volumen de envíos por WhatsApp',
                style: TextStyle(fontSize: 12, color: Colors.white54),
              ),

              Padding(
                padding: const EdgeInsets.all(16.0),
                child: TextField(
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Buscar por celular',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.search),
                    isDense: true,
                  ),
                  onChanged: (val) =>
                      setModalState(() => filtroActual = val.trim()),
                ),
              ),

              Expanded(
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: Supabase.instance.client
                      .from('servicios')
                      .select(
                        'id, destino, estado, created_at, telefono_receptor',
                      )
                      .eq('local_id', widget.usuario['id'])
                      .not('telefono_receptor', 'is', null),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      );
                    }

                    final servicios = snapshot.data ?? [];
                    if (servicios.isEmpty) {
                      return const Center(
                        child: Text(
                          'Aún no hay clientes registrados.',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.white54,
                          ),
                        ),
                      );
                    }

                    // --- MOTOR DE PROCESAMIENTO ---
                    Map<String, Map<String, dynamic>> directorio = {};

                    for (var servicio in servicios) {
                      String tel = servicio['telefono_receptor'].toString().trim();
                      if (tel.isEmpty || tel == 'null') continue;

                      if (!directorio.containsKey(tel)) {
                        directorio[tel] = {
                          'telefono': tel,
                          'total_pedidos': 0,
                          'completados': 0,
                          'cancelados': 0,
                          'ultima_fecha': null,
                          'direcciones': <String, int>{},
                          'historial': <Map<String, dynamic>>[],
                        };
                      }

                      directorio[tel]!['total_pedidos']++;
                      directorio[tel]!['historial'].add(servicio);

                      if (servicio['estado'] == 'finalizado') {
                        directorio[tel]!['completados']++;
                      } else if (servicio['estado'] == 'cancelado') {
                        directorio[tel]!['cancelados']++;
                      }

                      String dir =
                          servicio['destino']?.toString().toUpperCase() ?? '';
                      if (dir.isNotEmpty) {
                        Map<String, int> dirs = directorio[tel]!['direcciones'];
                        dirs[dir] = (dirs[dir] ?? 0) + 1;
                      }

                      if (servicio['created_at'] != null) {
                        DateTime fecha = DateTime.parse(servicio['created_at']);
                        DateTime? ultima = directorio[tel]!['ultima_fecha'];
                        if (ultima == null || fecha.isAfter(ultima)) {
                          directorio[tel]!['ultima_fecha'] = fecha;
                        }
                      }
                    }

                    List<Map<String, dynamic>> listaClientes = directorio.values
                        .toList();
                    if (filtroActual.isNotEmpty) {
                      listaClientes = listaClientes
                          .where(
                            (c) =>
                                c['telefono'].toString().contains(filtroActual),
                          )
                          .toList();
                    }

                    // Orden: Por cantidad de envíos exitosos
                    listaClientes.sort((a, b) {
                      int cmp = (b['completados'] as int).compareTo(
                        a['completados'] as int,
                      );
                      if (cmp == 0)
                        return (b['total_pedidos'] as int).compareTo(
                          a['total_pedidos'] as int,
                        );
                      return cmp;
                    });

                    return ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      itemCount: listaClientes.length,
                      itemBuilder: (ctx, i) {
                        final cliente = listaClientes[i];

                        Map<String, int> dirs = cliente['direcciones'];
                        String dirFavorita = 'Sin registrar';
                        if (dirs.isNotEmpty) {
                          var entradaMayor = dirs.entries.reduce(
                            (a, b) => a.value > b.value ? a : b,
                          );
                          dirFavorita = entradaMayor.key;
                        }

                        int completados = cliente['completados'];
                        Color badgeColor = Colors.grey;
                        String badgeText = 'NUEVO';
                        if (completados >= 10) {
                          badgeColor = Colors.purple;
                          badgeText = 'VIP';
                        } else if (completados >= 5) {
                          badgeColor = Colors.blue;
                          badgeText = 'FRECUENTE';
                        } else if (completados >= 2) {
                          badgeColor = Colors.green;
                          badgeText = 'CONOCIDO';
                        }

                        final DateTime? ultimaFecha = cliente['ultima_fecha'];
                        final String fechaStr = ultimaFecha != null
                            ? "${ultimaFecha.day}/${ultimaFecha.month}"
                            : "-";

                        return Card(
                          elevation: 1,
                          margin: const EdgeInsets.only(bottom: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: BorderSide(color: Colors.grey[300]!),
                          ),
                          child: InkWell(
                            onTap: () => _mostrarDetalleCliente(
                              contextoPrincipal,
                              cliente,
                              dirFavorita,
                              perfilEnVivo,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 22,
                                    backgroundColor: badgeColor.withValues(alpha: 0.1),
                                    child: Icon(
                                      Icons.person,
                                      color: badgeColor,
                                      size: 24,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Text(
                                              cliente['telefono'],
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 2,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: badgeColor,
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                badgeText,
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '📍 $dirFavorita',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Colors.black87,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            const Icon(
                                              Icons.motorcycle,
                                              size: 12,
                                              color: Colors.black54,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              '${cliente['completados']} envíos',
                                              style: const TextStyle(
                                                fontSize: 11,
                                                color: Colors.black54,
                                              ),
                                            ),
                                            if (cliente['cancelados'] > 0) ...[
                                              const SizedBox(width: 8),
                                              const Icon(
                                                Icons.cancel,
                                                size: 12,
                                                color: Colors.redAccent,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                '${cliente['cancelados']}',
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.redAccent,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Text(
                                        'Último',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.black54,
                                        ),
                                      ),
                                      Text(
                                        fechaStr,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                          color: Colors.black,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      const Icon(
                                        Icons.chevron_right,
                                        color: Colors.black38,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
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

  // SUB-PANTALLA: DETALLE EXACTO DEL CLIENTE
  void _mostrarDetalleCliente(
    BuildContext context,
    Map<String, dynamic> cliente,
    String dirFavorita,
    Map<String, dynamic> perfilEnVivo,
  ) {
    final DateTime? ultimaFecha = cliente['ultima_fecha'];
    final String fechaStr = ultimaFecha != null
        ? "${ultimaFecha.day}/${ultimaFecha.month}/${ultimaFecha.year}"
        : "Desconocida";
    final List historial = cliente['historial'];
    historial.sort(
      (a, b) => DateTime.parse(
        b['created_at'],
      ).compareTo(DateTime.parse(a['created_at'])),
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(
          children: [
            const Icon(Icons.contact_phone, color: Colors.blue),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'CLIENTE: ${cliente['telefono']}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 400,
          height: 450,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // PANEL DE MÉTRICAS (Simplificado)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue[200]!),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Column(
                      children: [
                        const Text(
                          'Exitosos',
                          style: TextStyle(fontSize: 10, color: Colors.black54),
                        ),
                        Text(
                          '${cliente['completados']}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: Colors.blue[800],
                          ),
                        ),
                      ],
                    ),
                    Container(width: 1, height: 32, color: Colors.grey[300]),
                    Column(
                      children: [
                        const Text(
                          'Cancelados',
                          style: TextStyle(fontSize: 10, color: Colors.black54),
                        ),
                        Text(
                          '${cliente['cancelados']}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: Colors.red,
                          ),
                        ),
                      ],
                    ),
                    Container(width: 1, height: 32, color: Colors.grey[300]),
                    Column(
                      children: [
                        const Text(
                          'Último',
                          style: TextStyle(fontSize: 10, color: Colors.black54),
                        ),
                        Text(
                          fechaStr,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: Colors.black,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '📍 Destino principal: $dirFavorita',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),

              const Text(
                'HISTORIAL DE DIRECCIONES:',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.black54,
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  itemCount: historial.length,
                  itemBuilder: (c, i) {
                    final servicio = historial[i];
                    final bool finalizado = servicio['estado'] == 'finalizado';
                    final dt = DateTime.parse(servicio['created_at']).toLocal();
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        finalizado ? Icons.check_circle : Icons.cancel,
                        color: finalizado ? Colors.green : Colors.red,
                        size: 20,
                      ),
                      title: Text(
                        '${servicio['destino']}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${dt.day}/${dt.month}/${dt.year} - ${servicio['estado'].toString().toUpperCase()}',
                        style: const TextStyle(fontSize: 10),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          // Fila 1: botones de acción
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xff3AF500),
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        icon: const Icon(Icons.motorcycle, size: 16),
                        label: const Text(
                          'NUEVO PEDIDO',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                        ),
                        onPressed: () {
                          Navigator.pop(ctx);
                          Navigator.pop(context);
                          _abrirFormularioPedido(
                            context,
                            esCotizacion: false,
                            perfilEnVivo: perfilEnVivo,
                            telefonoPrellenado: cliente['telefono'].toString(),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xff25D366),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        icon: const Icon(Icons.wechat, color: Colors.white, size: 16),
                        label: const Text(
                          'PROMO',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                        ),
                        onPressed: () async {
                          String numero = cliente['telefono'].toString().replaceAll(
                            RegExp(r'[^0-9]'), '');
                          if (numero.length == 10) numero = '57$numero';
                          final uri = Uri.parse(
                            'https://wa.me/$numero?text=${Uri.encodeComponent('¡Hola! Tenemos promociones especiales para ti hoy en ${widget.usuario['nombre']} 🍔🎁')}',
                          );
                          if (await canLaunchUrl(uri)) {
                            await launchUrl(uri, mode: LaunchMode.externalApplication);
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('CERRAR', style: TextStyle(color: Colors.black54)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _abrirSelectorMapa() {
    LatLng centerPos = widget.usuario['lat_fija'] != null
        ? LatLng(
            widget.usuario['lat_fija'].toDouble(),
            widget.usuario['lng_fija'].toDouble(),
          )
        : const LatLng(7.8833, -72.5053); // Default Cúcuta

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        contentPadding: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text(
          'UBICA TU LOCAL',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
        content: SizedBox(
          width: 400,
          height: 450,
          child: Stack(
            children: [
              FlutterMap(
                options: MapOptions(
                  initialCenter: centerPos,
                  initialZoom: 16.0,
                  onPositionChanged: (pos, hasGesture) {
                    centerPos = pos.center;
                  },
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.serviexpress.express',
                  ),
                ],
              ),
              const Center(
                child: Padding(
                  padding: EdgeInsets.only(bottom: 40),
                  child: Icon(Icons.location_on, color: Colors.red, size: 40),
                ),
              ),
              Positioned(
                bottom: 16,
                left: 16,
                right: 16,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () async {
                    await Supabase.instance.client
                        .from('usuarios')
                        .update({
                          'lat_fija': centerPos.latitude,
                          'lng_fija': centerPos.longitude,
                        })
                        .eq('id', widget.usuario['id']);

                    setState(() {
                      widget.usuario['lat_fija'] = centerPos.latitude;
                      widget.usuario['lng_fija'] = centerPos.longitude;
                    });

                    if (ctx.mounted) {
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            '✅ Ubicación fijada.',
                            style: TextStyle(color: Colors.white),
                          ),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.save, color: Color(0xff3AF500)),
                  label: const Text(
                    'GUARDAR AQUÍ',
                    style: TextStyle(
                      color: Color(0xff3AF500),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- HELPER: busca o crea un sector por nombre+municipio, retorna su id ---
  Future<int> _buscarOCrearSector(String nombre, String municipio) async {
    final res = await Supabase.instance.client
        .from('sectores')
        .select('id')
        .eq('nombre', nombre)
        .eq('municipio', municipio)
        .maybeSingle();
    if (res != null) return res['id'] as int;
    final nuevo = await Supabase.instance.client
        .from('sectores')
        .insert({'nombre': nombre, 'municipio': municipio})
        .select('id')
        .single();
    return nuevo['id'] as int;
  }

  // --- MÓDULO TÁCTICO: GESTOR DE TARIFAS DEL LOCAL ---
  void _abrirPanelTarifario(BuildContext contextoPrincipal) {
    String filtroActual = '';

    showModalBottomSheet(
      context: contextoPrincipal,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0D0D0D),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => DraggableScrollableSheet(
          initialChildSize: 0.8,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) => Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Container(
                  width: 40,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  '📚 MI LISTA DE PRECIOS',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                ),
                const Text(
                  'El sistema autocompletará la tarifa al detectar el Barrio/Sector/Cond./Conj..',
                  style: TextStyle(fontSize: 12, color: Colors.white54),
                ),
                const SizedBox(height: 16),

                // BARRA DE BÚSQUEDA
                TextField(
                  decoration: const InputDecoration(
                    labelText:
                        'Buscar Barrio / Sector / Cond. / Conj. o Palabra Clave',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.search),
                    isDense: true,
                  ),
                  onChanged: (val) =>
                      setModalState(() => filtroActual = val.toLowerCase()),
                ),
                const SizedBox(height: 12),

                // BOTÓN DE AGREGAR NUEVO
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      foregroundColor: const Color(0xff3AF500),
                    ),
                    icon: const Icon(Icons.add),
                    label: const Text(
                      'NUEVA TARIFA',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    onPressed: () {
                      final palabraCtrl = TextEditingController();
                      final tarifaCtrl = TextEditingController();
                      String zonaSeleccionada =
                          'CÚCUTA'; // <--- INYECCIÓN: ZONA POR DEFECTO

                      showDialog(
                        context: context,
                        builder: (ctxAdd) => StatefulBuilder(
                          builder: (ctxAdd, setAddState) => AlertDialog(
                            title: const Text(
                              'AGREGAR AL TARIFARIO',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            content: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                TextField(
                                  controller: palabraCtrl,
                                  textCapitalization:
                                      TextCapitalization.characters,
                                  decoration: const InputDecoration(
                                    labelText: 'Barrio / Sector / Cond.',
                                    isDense: true,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                // ---> SELECTOR TÁCTICO DE ZONA <---
                                const Text(
                                  'Municipio / Zona:',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black54,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 0,
                                  children:
                                      [
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
                                            if (selected)
                                              setAddState(
                                                () => zonaSeleccionada = z,
                                              );
                                          },
                                        );
                                      }).toList(),
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: tarifaCtrl,
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [CurrencyInputFormatter()],
                                  decoration: InputDecoration(
                                    labelText: 'Tarifa \$',
                                    isDense: true,
                                    suffixIcon: IconButton(
                                      icon: const Icon(Icons.clear, size: 18),
                                      tooltip: 'Borrar',
                                      onPressed: () => tarifaCtrl.clear(),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctxAdd),
                                child: const Text(
                                  'CANCELAR',
                                  style: TextStyle(color: Colors.red),
                                ),
                              ),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.black,
                                ),
                                onPressed: () async {
                                  if (palabraCtrl.text.isEmpty ||
                                      tarifaCtrl.text.isEmpty)
                                    return;
                                  String tarLimpia = tarifaCtrl.text
                                      .replaceAll('\$', '')
                                      .replaceAll('.', '')
                                      .replaceAll(',', '')
                                      .trim();

                                  final sectorId = await _buscarOCrearSector(
                                    palabraCtrl.text.trim().toUpperCase(),
                                    zonaSeleccionada,
                                  );

                                  await Supabase.instance.client
                                      .from('tarifas_locales')
                                      .upsert(
                                        {
                                          'local_id': widget.usuario['id'],
                                          'local_nombre': widget.usuario['nombre'],
                                          'sector_id': sectorId,
                                          'tarifa':
                                              double.tryParse(tarLimpia) ?? 0.0,
                                        },
                                        onConflict: 'local_id, sector_id',
                                      );

                                  if (ctxAdd.mounted) {
                                    Navigator.pop(ctxAdd);
                                    setModalState(() {});
                                  }
                                },
                                child: const Text(
                                  'GUARDAR',
                                  style: TextStyle(color: Color(0xff3AF500)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const Divider(height: 24),

                // LISTADO DE TARIFAS
                Expanded(
                  child: FutureBuilder<List<Map<String, dynamic>>>(
                    future: Supabase.instance.client
                        .from('tarifas_locales')
                        .select('id, sector_id, sectores(nombre, municipio), tarifa')
                        .eq('local_id', widget.usuario['id'])
                        .order('tarifa', ascending: true),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting)
                        return const Center(
                          child: CircularProgressIndicator(color: Colors.black),
                        );

                      final datos = snapshot.data ?? [];
                      final filtrados = datos.where((d) {
                        final s = d['sectores'] as Map<String, dynamic>?;
                        if (s == null) return false;
                        final label = '${s['nombre']} (${s['municipio']})'.toLowerCase();
                        return label.contains(filtroActual);
                      }).toList();

                      if (filtrados.isEmpty)
                        return const Center(
                          child: Text('No hay tarifas registradas.'),
                        );

                      return ListView.builder(
                        controller: scrollController,
                        itemCount: filtrados.length,
                        itemBuilder: (c, i) {
                          final item = filtrados[i];
                          final s = item['sectores'] as Map<String, dynamic>? ?? {};
                          final label = '${s['nombre'] ?? ''} (${s['municipio'] ?? ''})';
                          return Card(
                            elevation: 1,
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: const Icon(
                                Icons.location_city,
                                color: Colors.blue,
                              ),
                              title: Text(
                                label,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              subtitle: Text('Tarifa: ${fmtPeso(item['tarifa'])}'),
                              trailing: IconButton(
                                icon: const Icon(
                                  Icons.delete,
                                  color: Colors.red,
                                ),
                                onPressed: () async {
                                  await Supabase.instance.client
                                      .from('tarifas_locales')
                                      .delete()
                                      .eq('id', item['id']);
                                  setModalState(() {});
                                },
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
      ),
    );
  }

  /// Muestra el QR de la carta del local con opciones de compartir.
  void _mostrarQrCarta(Map<String, dynamic> perfil) {
    final localId = perfil['id'] as int;
    final nombre = perfil['nombre']?.toString() ?? 'Mi Local';
    const webUrl = 'https://databasesvm.github.io/serviexpressweb/';
    final link = webUrl; // QR apunta a la web para clientes sin la app
    final texto = DeeplinkService.textoCompartible(nombre, localId);

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Compartir carta',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Comparte este QR para que tus clientes abran tu menú directamente',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
              const SizedBox(height: 16),
              Center(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: QrImageView(
                    data: link,
                    version: QrVersions.auto,
                    size: 200,
                    backgroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                link,
                style: const TextStyle(fontSize: 10, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Copiar link'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: link));
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Link copiado al portapapeles'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black,
              foregroundColor: const Color(0xff3AF500),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            icon: const Icon(Icons.share, size: 16),
            label: const Text('Compartir'),
            onPressed: () {
              Navigator.pop(context);
              Share.share(texto, subject: 'Pide en $nombre por ServiExpress');
            },
          ),
        ],
      ),
    );
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

  Future<void> _abrirConfigDomicilios(Map<String, dynamic> perfil) async {
    final db = Supabase.instance.client;
    final categorias = [
      'Restaurante / Comida', 'Bebidas y Licores', 'Panadería / Pastelería',
      'Mercado / Supermercado', 'Farmacia / Droguería',
      'Ferretería', 'Papelería', 'Tecnología / Electrónica',
      'Ropa / Accesorios', 'Miscelánea', 'Mascotas', 'Otro',
    ];
    String categoria = perfil['categoria_local']?.toString() ?? 'Comida';
    final tiempoCtrl = TextEditingController(text: (perfil['tiempo_entrega'] ?? 35).toString());
    final minimoCtrl = TextEditingController(text: (perfil['pedido_minimo'] ?? 0).toString());
    TimeOfDay? apertura = _parseTime(perfil['horario_apertura']?.toString());
    TimeOfDay? cierre   = _parseTime(perfil['horario_cierre']?.toString());
    // dias_semana: string "1111111" Mon=0..Sun=6
    final rawDias = perfil['dias_semana']?.toString();
    List<bool> diasAbierto = rawDias != null && rawDias.length == 7
        ? rawDias.split('').map((c) => c == '1').toList()
        : List<bool>.filled(7, true);

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setDlg) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Config. Domicilios',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Categoría', style: TextStyle(fontSize: 12, color: Colors.black54)),
                const SizedBox(height: 4),
                DropdownButtonFormField<String>(
                  initialValue: categorias.contains(categoria) ? categoria : 'Comida',
                  items: categorias.map((cat) => DropdownMenuItem(
                      value: cat, child: Text(cat, style: const TextStyle(fontSize: 13)))).toList(),
                  onChanged: (v) {
                  if (v == null) return;
                  setDlg(() {
                    categoria = v;
                    // Reflect auto-tipo in parent state (will be overridden if user changed it manually)
                    final s = v.toLowerCase();
                    if (s.contains('comida') || s.contains('restaurante') ||
                        s.contains('panader') || s.contains('pastel')) {
                      setState(() => _tipoServicioDefecto = 'COMIDA');
                    } else if (s.contains('bebidas') || s.contains('licores')) {
                      setState(() => _tipoServicioDefecto = 'BEBIDAS');
                    } else if (s.contains('paquete')) {
                      setState(() => _tipoServicioDefecto = 'PAQUETERÍA');
                    } else {
                      setState(() => _tipoServicioDefecto = 'COMPRAS');
                    }
                  });
                },
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(height: 12),
                const Text('Tiempo estimado de entrega', style: TextStyle(fontSize: 12, color: Colors.black54)),
                const SizedBox(height: 4),
                TextField(
                  controller: tiempoCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    suffixText: 'min',
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 12),
                const Text('Pedido mínimo (COP)', style: TextStyle(fontSize: 12, color: Colors.black54)),
                const SizedBox(height: 4),
                TextField(
                  controller: minimoCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    prefixText: '\$ ',
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 12),
                const Text('Horario de atención', style: TextStyle(fontSize: 12, color: Colors.black54)),
                const SizedBox(height: 4),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.access_time, size: 14),
                      label: Text(
                        apertura != null
                            ? '${apertura!.hour.toString().padLeft(2, "0")}:${apertura!.minute.toString().padLeft(2, "0")}'
                            : 'Apertura',
                        style: const TextStyle(fontSize: 12),
                      ),
                      onPressed: () async {
                        final t = await showTimePicker(
                            context: ctx2,
                            initialTime: apertura ?? const TimeOfDay(hour: 8, minute: 0));
                        if (t != null) setDlg(() => apertura = t);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.access_time, size: 14),
                      label: Text(
                        cierre != null
                            ? '${cierre!.hour.toString().padLeft(2, "0")}:${cierre!.minute.toString().padLeft(2, "0")}'
                            : 'Cierre',
                        style: const TextStyle(fontSize: 12),
                      ),
                      onPressed: () async {
                        final t = await showTimePicker(
                            context: ctx2,
                            initialTime: cierre ?? const TimeOfDay(hour: 22, minute: 0));
                        if (t != null) setDlg(() => cierre = t);
                      },
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                const Text('Días de atención', style: TextStyle(fontSize: 12, color: Colors.black54)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  children: List.generate(7, (i) {
                    const labels = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];
                    const fullNames = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
                    final activo = diasAbierto[i];
                    return FilterChip(
                      label: Text(labels[i],
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: activo ? Colors.white : Colors.black54)),
                      tooltip: fullNames[i],
                      selected: activo,
                      onSelected: (v) => setDlg(() => diasAbierto[i] = v),
                      selectedColor: Colors.black,
                      backgroundColor: const Color(0xFF0D0D0D),
                      checkmarkColor: const Color(0xff3AF500),
                      showCheckmark: false,
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                      visualDensity: VisualDensity.compact,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    );
                  }),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: const Color(0xff3AF500),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () async {
                final tiempo = int.tryParse(tiempoCtrl.text.trim()) ?? 35;
                final minimo = int.tryParse(minimoCtrl.text.trim()) ?? 0;
                final data = <String, dynamic>{
                  'categoria_local': categoria,
                  'tiempo_entrega': tiempo,
                  'pedido_minimo': minimo,
                  if (apertura != null)
                    'horario_apertura':
                        '${apertura!.hour.toString().padLeft(2, "0")}:${apertura!.minute.toString().padLeft(2, "0")}:00',
                  if (cierre != null)
                    'horario_cierre':
                        '${cierre!.hour.toString().padLeft(2, "0")}:${cierre!.minute.toString().padLeft(2, "0")}:00',
                  'dias_semana': diasAbierto.map((v) => v ? '1' : '0').join(),
                };
                try {
                  await db.from('usuarios').update(data).eq('id', perfil['id']);
                  if (ctx.mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                        content: Text('Configuración guardada'), backgroundColor: Colors.green));
                  }
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
                  }
                }
              },
              child: const Text('Guardar', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  TimeOfDay? _parseTime(String? s) {
    if (s == null || s.isEmpty) return null;
    final parts = s.split(':');
    if (parts.length < 2) return null;
    return TimeOfDay(hour: int.tryParse(parts[0]) ?? 0, minute: int.tryParse(parts[1]) ?? 0);
  }

  void _abrirMenuUbicacion() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          '📍 UBICACIÓN DEL LOCAL',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'Configura tu ubicación para que la Central te vea en el radar y te mande la flota más cercana.',
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue[800],
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.gps_fixed),
            label: const Text('USAR MI UBICACIÓN ACTUAL'),
            onPressed: () async {
              Navigator.pop(ctx);
              await _obtenerOSellarGPSLocal(forzar: true);
            },
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.purple[800],
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.map),
            label: const Text('UBICAR PIN EN EL MAPA'),
            onPressed: () {
              Navigator.pop(ctx);
              _abrirSelectorMapa();
            },
          ),
        ],
      ),
    );
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
    await prefs.remove('saved_phone');
    await prefs.remove('saved_password');
    await prefs.setBool('auto_login', false);
    await prefs.remove('sesion_usuario_json');
    if (mounted) Navigator.pushReplacementNamed(context, '/');
  }

  // =========================================================================
  // RECARGO OBLIGATORIO — Confirma nocturno/lluvia antes de despachar.
  // =========================================================================
  // Consulta calcular_recargo_local() (respeta el convenio especial del
  // local y su zona de lluvia configurada por Central). Si hay recargo
  // activo, muestra un diálogo que no se puede ignorar tocando fuera o
  // con el botón atrás — el local debe elegir explícitamente entre:
  //   - CONFIRMAR el precio con recargo → devuelve precioBase + recargo
  //   - CANCELAR DESPACHO → devuelve null, aborta todo el envío y el
  //     local vuelve al formulario a resolverlo por su cuenta
  // No se puede aceptar el servicio ignorando el recargo: o lo paga,
  // o no despacha con este flujo.
  Future<double?> _confirmarRecargoObligatorio(double precioBase) async {
    Map<String, dynamic>? recargo;
    try {
      final resultado = await Supabase.instance.client.rpc(
        'calcular_recargo_local',
        params: {'p_local_id': widget.usuario['id']},
      );
      if (resultado != null && (resultado as List).isNotEmpty) {
        recargo = resultado[0] as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('_confirmarRecargoObligatorio: $e');
    }

    // Sin recargo activo (o error de red) → seguimos con el precio tal cual
    final bool aplica = recargo?['aplica_recargo'] == true;
    if (!aplica) return precioBase;

    final int recargoTotal = (recargo!['recargo_total'] as num).toInt();
    final String desglose = recargo['desglose']?.toString() ?? '';
    final double precioFinal = precioBase + recargoTotal;

    if (!mounted) return null;

    final bool? confirmado = await showDialog<bool>(
      context: context,
      barrierDismissible: false, // No se puede ignorar tocando fuera
      builder: (ctxRecargo) => PopScope(
        canPop: false, // El botón atrás tampoco lo evade — debe elegir una opción
        child: AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: Colors.orange[700]!, width: 2),
          ),
          title: Row(
            children: [
              Icon(Icons.nights_stay, color: Colors.orange[800]),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'RECARGO ACTIVO',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Es horario nocturno o está lloviendo en tu zona. '
                'El recargo es obligatorio para continuar con este precio.',
                style: TextStyle(fontSize: 13, color: Colors.grey[700]),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tu precio: \$${_formatPesoSimple(precioBase)}',
                      style: const TextStyle(fontSize: 13),
                    ),
                    Text(
                      '+ $desglose',
                      style: TextStyle(fontSize: 13, color: Colors.orange[800]),
                    ),
                    const Divider(height: 16),
                    Text(
                      'Total: \$${_formatPesoSimple(precioFinal)}',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Si no estás de acuerdo, puedes cancelar y resolver el '
                'pedido por tu cuenta.',
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctxRecargo, false),
              child: Text(
                'CANCELAR DESPACHO',
                style: TextStyle(
                  color: Colors.grey[700],
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                minimumSize: const Size(double.infinity, 44),
              ),
              onPressed: () => Navigator.pop(ctxRecargo, true),
              child: Text(
                'CONFIRMAR \$${_formatPesoSimple(precioFinal)}',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (confirmado != true) return null;
    return precioFinal;
  }

  String _formatPesoSimple(double valor) {
    final s = valor.toInt().toString();
    final buffer = StringBuffer();
    final inicio = s.length % 3;
    if (inicio > 0) buffer.write(s.substring(0, inicio));
    for (int i = inicio; i < s.length; i += 3) {
      if (i > 0) buffer.write('.');
      buffer.write(s.substring(i, i + 3));
    }
    return buffer.toString();
  }

  // --- MOTOR TÁCTICO: OBTENER O SELLAR COORDENADAS FIJAS ---
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

  // ---> CAÑÓN DE TIEMPO ONESIGNAL (Disparos al futuro) <---
  // Delega al motor central — garantiza App ID y canal correctos (207d1d0a / CHANNEL_ALERTA)
  Future<String?> _programarMisilRetardado({
    required List<String> externalIds,
    required String titulo,
    required String mensaje,
    int minutosRetardo = 0,
    int segundosRetardo = 0,
  }) => MotorNotificaciones.programarMisilRetardado(
        externalIds: externalIds,
        titulo: titulo,
        mensaje: mensaje,
        minutosRetardo: minutosRetardo,
        segundosRetardo: segundosRetardo,
      );

  Future<void> _dispararMisilInmediato({
    required List<String> externalIds,
    required String titulo,
    required String mensaje,
  }) => MotorNotificaciones.dispararRafa(
        idsDestinos: externalIds,
        titulo: titulo,
        mensaje: mensaje,
        urgente: true,
      );

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

  // ─── VIP: verificación periódica + diálogo de fallback ───────────────────
  //
  // Flujo:
  //   Envío VIP → notifica Masters (0s) + Leyenda #1 (30s)
  //               → espera 3 min → _verificarFallbackVip()
  //   _verificarFallbackVip:
  //     • Si el servicio ya fue tomado → no hace nada
  //     • Si hay nuevos VIP disponibles → les notifica + reinicia timer 3 min
  //     • Si no hay nadie → llama _mostrarDialogoFallbackVip()
  //   _mostrarDialogoFallbackVip:
  //     ESPERAR  → espera 5 min → vuelve a _verificarFallbackVip()
  //     ESTÁNDAR → resta $3.000, enruta como servicio normal

  Future<void> _verificarFallbackVip({
    required int servicioId,
    required String destino,
    required List<String> pilotosParadero,
    required bool esPuntoAPunto,
    required Map<String, dynamic>? coords,
    required double tarifaConVip,
  }) async {
    if (!mounted) return;
    try {
      final check = await Supabase.instance.client
          .from('servicios')
          .select('estado, es_vip, movil_id')
          .eq('id', servicioId)
          .single();
      // Ya fue tomado o degradado — nada que hacer
      if (check['estado'] != 'pendiente' ||
          check['es_vip'] != true ||
          check['movil_id'] != null) return;
    } catch (_) {
      return;
    }
    if (!mounted) return;

    // ¿Hay nuevos VIP disponibles ahora?
    final masters = await Supabase.instance.client
        .from('usuarios')
        .select('id')
        .eq('rol', 'movil')
        .eq('en_linea', true)
        .inFilter('rango_movil', ['MASTER']);
    final leyendas = await Supabase.instance.client
        .from('usuarios')
        .select('id, ingreso_fila')
        .eq('rol', 'movil')
        .eq('en_linea', true)
        .eq('rango_movil', 'LEYENDA')
        .not('paradero_actual', 'is', null)
        .order('ingreso_fila', ascending: true);

    final List<String> masterIds =
        masters.map((u) => u['id'].toString()).toList();
    final List<String> leyendaIds =
        leyendas.isNotEmpty ? [leyendas.first['id'].toString()] : [];

    if (masterIds.isNotEmpty || leyendaIds.isNotEmpty) {
      // Nuevos VIP conectados → notificar y reiniciar timer 3 min
      const String msg = 'Hay un servicio VIP esperando — revisa el radar';
      if (masterIds.isNotEmpty) {
        await _dispararMisilInmediato(
          externalIds: masterIds,
          titulo: '👑 SERVICIO VIP',
          mensaje: msg,
        );
      }
      if (leyendaIds.isNotEmpty) {
        Future.delayed(const Duration(seconds: 30), () async {
          if (!mounted) return;
          // Guardia: si el servicio ya no está pendiente (master lo aceptó), no enviar
          final estadoCheck = await Supabase.instance.client
              .from('servicios')
              .select('estado')
              .eq('id', servicioId)
              .maybeSingle();
          if (estadoCheck == null || estadoCheck['estado'] != 'pendiente') return;
          await _dispararMisilInmediato(
            externalIds: leyendaIds,
            titulo: '👑 SERVICIO VIP',
            mensaje: msg,
          );
        });
      }
      Future.delayed(const Duration(minutes: 3), () {
        _verificarFallbackVip(
          servicioId: servicioId,
          destino: destino,
          pilotosParadero: pilotosParadero,
          esPuntoAPunto: esPuntoAPunto,
          coords: coords,
          tarifaConVip: tarifaConVip,
        );
      });
    } else {
      // Aún sin VIP → mostrar diálogo al local
      if (mounted) {
        _mostrarDialogoFallbackVip(
          servicioId: servicioId,
          destino: destino,
          pilotosParadero: pilotosParadero,
          esPuntoAPunto: esPuntoAPunto,
          coords: coords,
          tarifaConVip: tarifaConVip,
        );
      }
    }
  }

  Future<void> _mostrarDialogoFallbackVip({
    required int servicioId,
    required String destino,
    required List<String> pilotosParadero,
    required bool esPuntoAPunto,
    required Map<String, dynamic>? coords,
    required double tarifaConVip,
  }) async {
    if (!mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctxVip) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [Color(0xFFB8860B), Color(0xFFFFD700), Color(0xFFB8860B)],
          ).createShader(bounds),
          child: Text(
            '👑 SIN MÓVILES VIP',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
          ),
        ),
        content: const Text(
          'Parece que no hay móviles capacitados disponibles para tu servicio VIP en este momento.\n\n¿Deseas esperar a que haya uno disponible, o prefieres pedirlo como servicio estándar?',
          style: TextStyle(fontSize: 14),
        ),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actions: [
          // ESPERAR: re-verifica en 5 minutos
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFB8860B),
              side: const BorderSide(color: Color(0xFFFFD700)),
            ),
            onPressed: () {
              Navigator.pop(ctxVip);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    '⏳ VIP en espera. Te avisamos en 5 min si hay un Leyenda o Master disponible.',
                  ),
                  backgroundColor: Color(0xFF7A5500),
                  duration: Duration(seconds: 5),
                ),
              );
              Future.delayed(const Duration(minutes: 5), () {
                _verificarFallbackVip(
                  servicioId: servicioId,
                  destino: destino,
                  pilotosParadero: pilotosParadero,
                  esPuntoAPunto: esPuntoAPunto,
                  coords: coords,
                  tarifaConVip: tarifaConVip,
                );
              });
            },
            icon: const Icon(Icons.hourglass_top, size: 16),
            label: const Text('ESPERAR'),
          ),
          // SERVICIO ESTÁNDAR: restar $3.000 y enrutar normal
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xff3AF500),
              foregroundColor: Colors.black,
            ),
            onPressed: () async {
              Navigator.pop(ctxVip);
              final double tarifaEstandar =
                  (tarifaConVip - 3000).clamp(0.0, double.infinity);
              await Supabase.instance.client
                  .from('servicios')
                  .update({
                    'es_vip': false,
                    'tarifa': tarifaEstandar,
                    'tarifa_detalle': {
                      'total': tarifaEstandar,
                      'fuente': 'local_quitar_vip',
                    },
                  })
                  .eq('id', servicioId);

              const String msgStd = 'Nuevo servicio disponible — revisa el radar';
              final mastersStd = await Supabase.instance.client
                  .from('usuarios')
                  .select('id')
                  .or('rol.eq.central,rol.eq.master,rango_movil.eq.MASTER')
                  .neq('suspendido', true);
              final List<String> masterStdIds =
                  mastersStd.map((u) => u['id'].toString()).toList();

              if (masterStdIds.isNotEmpty) {
                await _dispararMisilInmediato(
                  externalIds: masterStdIds,
                  titulo: '👑 NUEVO SERVICIO',
                  mensaje: msgStd,
                );
              }

              // T=+30s: notificar al #1 de paradero siempre (sin chequeo de cola)
              if (pilotosParadero.isNotEmpty) {
                final List<String> targetStd = pilotosParadero
                    .where((id) => !masterStdIds.contains(id))
                    .toList();
                if (targetStd.isNotEmpty) {
                  Future.delayed(const Duration(seconds: 30), () async {
                    if (!mounted) return;
                    // Guardia: si el servicio ya no está pendiente (master lo aceptó), no enviar
                    final estadoCheck = await Supabase.instance.client
                        .from('servicios')
                        .select('estado')
                        .eq('id', servicioId)
                        .maybeSingle();
                    if (estadoCheck == null || estadoCheck['estado'] != 'pendiente') return;
                    await _dispararMisilInmediato(
                      externalIds: targetStd,
                      titulo: 'TU TURNO DE PARADERO',
                      mensaje: msgStd,
                    );
                  });
                }
              }
              // T=+60s: radio 1km (no Masters, no paradero ya notificado)
              {
                final int _svcId = servicioId;
                final String _msg = msgStd;
                final List<String> _masterSnap = List<String>.from(masterStdIds);
                final List<String> _paraderoSnap = List<String>.from(pilotosParadero);
                final double? _oLat = (coords?['lat'] as num?)?.toDouble();
                final double? _oLng = (coords?['lng'] as num?)?.toDouble();

                Future.delayed(const Duration(seconds: 60), () async {
                  if (!mounted) return;
                  final chk = await Supabase.instance.client
                      .from('servicios').select('estado').eq('id', _svcId).maybeSingle();
                  if (chk == null || chk['estado'] != 'pendiente') return;
                  final candidatos = await Supabase.instance.client
                      .from('usuarios').select('id, latitud, longitud')
                      .eq('rol', 'movil').eq('en_linea', true).neq('suspendido', true)
                      .not('rango_movil', 'in', '("MASTER")');
                  final idsZ = (candidatos as List).where((u) {
                    final id = u['id'].toString();
                    if (_masterSnap.contains(id) || _paraderoSnap.contains(id)) return false;
                    if (_oLat == null || _oLng == null) return true;
                    final uLat = (u['latitud'] as num?)?.toDouble();
                    final uLng = (u['longitud'] as num?)?.toDouble();
                    if (uLat == null || uLng == null) return false;
                    return const Distance().as(
                          LengthUnit.Meter,
                          LatLng(uLat, uLng),
                          LatLng(_oLat, _oLng),
                        ) <= 1000;
                  }).map((u) => u['id'].toString()).toList();
                  if (idsZ.isNotEmpty) {
                    await _dispararMisilInmediato(
                        externalIds: idsZ, titulo: '📡 SERVICIO CERCA (1km)', mensaje: _msg);
                  }
                });

                // T=+90s: todos los disponibles (ola final)
                Future.delayed(const Duration(seconds: 90), () async {
                  if (!mounted) return;
                  final chk = await Supabase.instance.client
                      .from('servicios').select('estado').eq('id', _svcId).maybeSingle();
                  if (chk == null || chk['estado'] != 'pendiente') return;
                  final todos = await Supabase.instance.client
                      .from('usuarios').select('id')
                      .eq('rol', 'movil').eq('en_linea', true).neq('suspendido', true);
                  final idsT = (todos as List)
                      .map((u) => u['id'].toString())
                      .where((id) => !_masterSnap.contains(id))
                      .toList();
                  if (idsT.isNotEmpty) {
                    await _dispararMisilInmediato(
                        externalIds: idsT, titulo: '🚨 SERVICIO SIN TOMAR', mensaje: _msg);
                  }
                });
              }

              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('✅ Pedido enviado como servicio estándar.'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
            icon: const Icon(Icons.motorcycle, size: 16),
            label: const Text('SERVICIO ESTÁNDAR'),
          ),
        ],
      ),
    );
  }

  // --- MÓDULO 1: DESPACHO DIRECTO Y COTIZACIÓN UNIFICADA (MULTI-PARADERO + TEMPORIZADOR) ---
  void _abrirFormularioPedido(
    BuildContext context, {
    bool esPuntoAPunto = false,
    bool esCotizacion = false,
    bool esVip = false,
    required Map<String, dynamic> perfilEnVivo,
    String? telefonoPrellenado, // Viene del botón "NUEVO PEDIDO" en el CRM
  }) async {
    // --- CONSULTA ESPEJO CON "MI LOCAL" ---
    List<Map<String, dynamic>> listaPrecios = [];
    List<String> redDirecciones = []; // zonas de la red central (sin precio)

    // ---> LIBERADO: Ahora descarga la lista también cuando es Cotización <---
    if (!esPuntoAPunto) {
      try {
        final res = await Supabase.instance.client
            .from('tarifas_locales')
            .select('sector_id, sectores(nombre, municipio), tarifa')
            .eq('local_id', widget.usuario['id'])
            .order('tarifa', ascending: true);

        listaPrecios = List<Map<String, dynamic>>.from(res);
      } catch (_) {}

      // Red de direcciones compartida de Central (solo nombres, sin precio)
      try {
        final red = await Supabase.instance.client
            .from('red_direcciones')
            .select('nombre, municipio')
            .eq('activo', true)
            .order('nombre', ascending: true);

        // Excluir las que ya están en la lista propia (no duplicar)
        final propias = listaPrecios.map((e) {
          final s = e['sectores'] as Map<String, dynamic>?;
          if (s == null) return '';
          return '${s['nombre']} (${s['municipio']})'.toUpperCase();
        }).toSet();
        redDirecciones = List<Map<String, dynamic>>.from(red)
            .map((e) => '${e['nombre']} (${e['municipio']})')
            .where((nombre) => !propias.contains(nombre.toUpperCase()))
            .toList();
      } catch (_) {}
    }

    if (!context.mounted) return;

    // --- PRECARGA DEL HISTORIAL (si viene de "NUEVO PEDIDO" en el CRM) ---
    // Evita que el local tenga que volver a escribir el teléfono para que
    // aparezcan las píldoras de direcciones recientes: ya llegan listas.
    List<Map<String, dynamic>> direccionesHistoricasCliente = [];
    if (telefonoPrellenado != null && telefonoPrellenado.length >= 10) {
      direccionesHistoricasCliente = await _buscarDireccionesPorTelefono(
        telefonoPrellenado,
      );
      if (!context.mounted) return;
    }

    final destinoController = TextEditingController();
    final tarifaController = TextEditingController();
    final notasController = TextEditingController();
    final telefonoController = TextEditingController(
      text: telefonoPrellenado ?? '',
    );
    final ticketController = TextEditingController();

    bool procesando = false;
    bool buscandoCliente = false;
    String tiempoPreparacion = 'Inmediato';

    List<Map<String, dynamic>> sugerenciasListaPrecios = [];
    List<String> sugerenciasRed = []; // sugerencias de la red (sin precio)

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          // Mismo fix que en el formulario de Central — el insetPadding
          // por defecto se comía el ancho disponible en celular.
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 24,
          ),
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
                    '👑 SERVICIO VIP',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 1,
                    ),
                  ),
                )
              : Text(
                  esCotizacion
                      ? 'COTIZAR SERVICIO'
                      : (esPuntoAPunto ? 'PUNTO A PUNTO' : 'SOLICITAR MÓVIL'),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: esCotizacion
                        ? Colors.orange[800]
                        : (esPuntoAPunto ? Colors.purple : Colors.black),
                  ),
                ),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (esVip)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFF3D2B00),
                          Color(0xFF7A5500),
                          Color(0xFF3D2B00),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(6),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFFD700).withValues(alpha: 0.35),
                          blurRadius: 8,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: const Row(
                      children: [
                        Text('👑', style: TextStyle(fontSize: 16)),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Solo llega a Leyendas y Masters · +\$3.000 automático',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFFFD700),
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: esCotizacion
                          ? Colors.orange[50]
                          : (esPuntoAPunto
                                ? Colors.purple[50]
                                : Colors.grey[200]),
                      borderRadius: BorderRadius.circular(6),
                      border: esCotizacion
                          ? Border.all(color: Colors.orange[300]!)
                          : (esPuntoAPunto
                                ? Border.all(color: Colors.purple[200]!)
                                : null),
                    ),
                    child: Text(
                      esCotizacion
                          ? 'Central fijará la tarifa para esta ruta.'
                          : (esPuntoAPunto
                                ? '🏁 Destino final: ${widget.usuario['nombre']}'
                                : '📍 Local: ${widget.usuario['nombre']}'),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: esCotizacion
                            ? Colors.orange[900]
                            : (esPuntoAPunto
                                  ? Colors.purple[800]
                                  : Colors.black54),
                      ),
                    ),
                  ),
                const SizedBox(height: 16),

                // 1. TICKET
                TextField(
                  controller: ticketController,
                  keyboardType: TextInputType.text,
                  decoration: const InputDecoration(
                    labelText: 'Ticket / Factura # (Opcional)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.receipt_long),
                  ),
                ),
                const SizedBox(height: 12),

                // 2. WHATSAPP (MINI-CRM CLIENTES)
                if (!esPuntoAPunto) ...[
                  TextField(
                    controller: telefonoController,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: 'WhatsApp del cliente (*)',
                      border: const OutlineInputBorder(),
                      prefixIcon: buscandoCliente
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : const Icon(Icons.phone_android),
                    ),
                    onChanged: (val) async {
                      if (val.length >= 10) {
                        setDialogState(() => buscandoCliente = true);
                        final resultado = await _buscarDireccionesPorTelefono(
                          val,
                        );
                        setDialogState(() {
                          direccionesHistoricasCliente = resultado;
                          buscandoCliente = false;
                        });
                      } else {
                        setDialogState(() => direccionesHistoricasCliente = []);
                      }
                    },
                  ),

                  // PÍLDORAS DEL HISTORIAL DE DIRECCIONES
                  if (direccionesHistoricasCliente.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: direccionesHistoricasCliente.map((dir) {
                          String numStr = (dir['tarifa'] as num)
                              .toInt()
                              .toString();
                          String result = '';
                          int count = 0;
                          for (int i = numStr.length - 1; i >= 0; i--) {
                            result = numStr[i] + result;
                            count++;
                            if (count == 3 && i > 0) {
                              result = '.$result';
                              count = 0;
                            }
                          }
                          String tarifaStr = '\$$result';

                          return InkWell(
                            onTap: () {
                              destinoController.text = dir['destino'];
                              tarifaController.text = tarifaStr;
                              setDialogState(
                                () => direccionesHistoricasCliente = [],
                              );
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.blue[50],
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.blue[300]!),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.history,
                                    color: Colors.blue,
                                    size: 14,
                                  ),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      '${dir['destino']} ($tarifaStr)',
                                      style: TextStyle(
                                        color: Colors.blue[900],
                                        fontWeight: FontWeight.bold,
                                        fontSize: 11,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  const SizedBox(height: 12),
                ],

                // 3. DESTINO
                TextField(
                  controller: destinoController,
                  decoration: InputDecoration(
                    labelText: esPuntoAPunto
                        ? '¿Dónde compran / recogen?'
                        : 'Dirección de Entrega',
                    border: const OutlineInputBorder(),
                    prefixIcon: Icon(
                      esPuntoAPunto ? Icons.storefront : Icons.flag,
                    ),
                    // ---> LIBERADO: Muestra el botón de agenda en Cotizar <---
                    suffixIcon: (!esPuntoAPunto && listaPrecios.isNotEmpty)
                        ? IconButton(
                            icon: const Icon(
                              Icons.list_alt,
                              color: Colors.blue,
                            ),
                            tooltip: 'Ver mi lista de precios',
                            onPressed: () {
                              showDialog(
                                context: context,
                                builder: (ctxLista) => AlertDialog(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  title: const Text(
                                    '📖 MI LISTA DE PRECIOS',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
                                  ),
                                  content: SizedBox(
                                    width: double.maxFinite,
                                    height: 350,
                                    child: ListView.builder(
                                      shrinkWrap: true,
                                      itemCount: listaPrecios.length,
                                      itemBuilder: (ctx, i) {
                                        final item = listaPrecios[i];
                                        String numStr = (item['tarifa'] as num)
                                            .toInt()
                                            .toString();
                                        String result = '';
                                        int count = 0;
                                        for (
                                          int j = numStr.length - 1;
                                          j >= 0;
                                          j--
                                        ) {
                                          result = numStr[j] + result;
                                          count++;
                                          if (count == 3 && j > 0) {
                                            result = '.$result';
                                            count = 0;
                                          }
                                        }
                                        String tarifaStr = '\$$result';

                                        return Card(
                                          elevation: 0.5,
                                          margin: const EdgeInsets.only(
                                            bottom: 6,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          child: ListTile(
                                            dense: true,
                                            tileColor: Colors.blue[50],
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            title: Text(
                                              () {
                                                final s = item['sectores'] as Map<String, dynamic>?;
                                                if (s == null) return '';
                                                return '${s['nombre']} (${s['municipio']})'.toUpperCase();
                                              }(),
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13,
                                              ),
                                            ),
                                            trailing: Text(
                                              tarifaStr,
                                              style: TextStyle(
                                                color: Colors.blue[900],
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14,
                                              ),
                                            ),
                                            onTap: () {
                                              final s = item['sectores'] as Map<String, dynamic>?;
                                              final lbl = s != null ? '${s['nombre']} (${s['municipio']})'.toUpperCase() : '';
                                              destinoController.text = '$lbl - ';
                                              // Solo pega el precio si no es cotización
                                              if (!esCotizacion)
                                                tarifaController.text =
                                                    tarifaStr;

                                              setDialogState(
                                                () => sugerenciasListaPrecios =
                                                    [],
                                              );
                                              Navigator.pop(ctxLista);
                                            },
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctxLista),
                                      child: const Text(
                                        'CERRAR',
                                        style: TextStyle(
                                          color: Colors.black,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          )
                        : null,
                  ),
                  onChanged: (texto) {
                    if (esPuntoAPunto) return;

                    String textoLimpio = texto.toLowerCase();
                    if (textoLimpio.length < 2) {
                      setDialogState(() {
                        sugerenciasListaPrecios = [];
                        sugerenciasRed = [];
                      });
                      return;
                    }

                    List<String> palabrasDigitadas = textoLimpio
                        .split(RegExp(r'\s+'))
                        .where((w) => w.length > 2)
                        .toList();

                    // --- Sugerencias de lista propia (con precio, en verde) ---
                    List<Map<String, dynamic>> encontradas = [];
                    for (var t in listaPrecios) {
                      final sec = t['sectores'] as Map<String, dynamic>?;
                      if (sec == null) continue;
                      String palabraClave = '${sec['nombre']} (${sec['municipio']})'.toLowerCase();
                      bool hay = textoLimpio.contains(palabraClave) ||
                          palabrasDigitadas.any((w) => palabraClave.contains(w));
                      if (hay) {
                        String numStr = (t['tarifa'] as num).toInt().toString();
                        String result = '';
                        int count = 0;
                        for (int i = numStr.length - 1; i >= 0; i--) {
                          result = numStr[i] + result;
                          count++;
                          if (count == 3 && i > 0) { result = '.$result'; count = 0; }
                        }
                        encontradas.add({
                          'palabra': '${sec['nombre']} (${sec['municipio']})'.toUpperCase(),
                          'tarifaStr': '\$$result',
                        });
                      }
                    }

                    // --- Sugerencias de red (sin precio, en gris) ---
                    List<String> redEncontradas = redDirecciones
                        .where((nombre) {
                          String n = nombre.toLowerCase();
                          return n.contains(textoLimpio) ||
                              palabrasDigitadas.any((w) => n.contains(w));
                        })
                        .take(3)
                        .toList();

                    setDialogState(() {
                      sugerenciasListaPrecios = encontradas.take(3).toList();
                      sugerenciasRed = redEncontradas;
                    });
                  },
                ),

                if (sugerenciasListaPrecios.isNotEmpty || sugerenciasRed.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // --- SUGERENCIAS PROPIAS (con precio, verde) ---
                        if (sugerenciasListaPrecios.isNotEmpty) ...[
                          const Text(
                            '💡 Mi lista de precios:',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: sugerenciasListaPrecios.map((sug) =>
                              InkWell(
                                onTap: () {
                                  if (!esCotizacion)
                                    tarifaController.text = sug['tarifaStr'];
                                  if (destinoController.text.length <= sug['palabra'].toString().length)
                                    destinoController.text = '${sug['palabra']} - ';
                                  setDialogState(() {
                                    sugerenciasListaPrecios = [];
                                    sugerenciasRed = [];
                                  });
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: Colors.green[50],
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: Colors.green[400]!),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.add_location_alt, color: Colors.green, size: 14),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${sug['palabra']} (${sug['tarifaStr']})',
                                        style: TextStyle(color: Colors.green[900], fontWeight: FontWeight.bold, fontSize: 11),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ).toList(),
                          ),
                        ],

                        // --- SUGERENCIAS DE LA RED (sin precio, gris) ---
                        if (sugerenciasRed.isNotEmpty) ...[
                          if (sugerenciasListaPrecios.isNotEmpty) const SizedBox(height: 8),
                          const Text(
                            '🌐 Zona de la red:',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.black45,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: sugerenciasRed.map((nombre) =>
                              InkWell(
                                onTap: () {
                                  if (destinoController.text.length <= nombre.length)
                                    destinoController.text = '$nombre - ';
                                  setDialogState(() {
                                    sugerenciasListaPrecios = [];
                                    sugerenciasRed = [];
                                  });
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: Colors.grey[100],
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: Colors.grey[400]!),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.location_city, color: Colors.grey[600], size: 14),
                                      const SizedBox(width: 4),
                                      Text(
                                        nombre,
                                        style: TextStyle(color: Colors.grey[700], fontWeight: FontWeight.w600, fontSize: 11),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ).toList(),
                          ),
                        ],
                      ],
                    ),
                  ),
                const SizedBox(height: 12),

                // 4. TARIFA Y RELOJ
                if (!esPuntoAPunto) ...[
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: tarifaController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [CurrencyInputFormatter()],
                          decoration: InputDecoration(
                            labelText: esCotizacion
                                ? 'Tarifa (Se calculará)'
                                : 'Tarifa (\$)',
                            enabled: !esCotizacion,
                            border: const OutlineInputBorder(),
                            prefixIcon: const Icon(Icons.attach_money),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: tiempoPreparacion,
                        icon: const Icon(Icons.timer, color: Colors.blue),
                        items:
                            ['Inmediato', 'En 15 min', 'En 30 min', 'En 45 min']
                                .map(
                                  (String v) => DropdownMenuItem(
                                    value: v,
                                    child: Text(
                                      'Enviar móvil: $v',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                        onChanged: (val) {
                          if (val != null)
                            setDialogState(() => tiempoPreparacion = val);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // 5. NOTAS
                TextField(
                  controller: notasController,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: esPuntoAPunto
                        ? '¿Qué van a traer? (Detalles)'
                        : 'Notas de la orden',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.notes),
                  ),
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
              style: ElevatedButton.styleFrom(
                backgroundColor: esCotizacion
                    ? Colors.orange[800]
                    : (esPuntoAPunto ? Colors.purple[800] : Colors.black),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
              ),
              onPressed: procesando
                  ? null
                  : () async {
                      if (destinoController.text.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Falta la dirección.'),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }

                      // ---> REGLA DE DISCIPLINA: FILTRO ANTICIEGOS (NOMENCLATURA) <---
                      String destinoFinal = destinoController.text
                          .trim()
                          .toUpperCase();
                      bool esSoloElBarrio = listaPrecios.any((item) {
                        final s = item['sectores'] as Map<String, dynamic>?;
                        if (s == null) return false;
                        return '${s['nombre']} (${s['municipio']})'.toUpperCase() == destinoFinal;
                      });

                      if (!esPuntoAPunto &&
                          !esCotizacion &&
                          (esSoloElBarrio || destinoFinal.length <= 8)) {
                        showDialog(
                          context: context,
                          builder: (ctxAlert) => AlertDialog(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: const BorderSide(
                                color: Colors.orange,
                                width: 2,
                              ),
                            ),
                            title: const Row(
                              children: [
                                Icon(
                                  Icons.warning_amber_rounded,
                                  color: Colors.orange,
                                  size: 28,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'DIRECCIÓN CORTA',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.orange,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                            content: const Text(
                              'Parece que solo escribiste el nombre del barrio.\n\nPor favor, agrega la Calle, Avenida, o número de casa/apartamento para que el móvil llegue exacto.',
                              style: TextStyle(fontSize: 14),
                            ),
                            actions: [
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.black,
                                ),
                                onPressed: () => Navigator.pop(
                                  ctxAlert,
                                ), // Solo cierra la alerta, deja el formulario abierto
                                child: Text(
                                  'ACEPTAR Y CORREGIR',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                        return; // Frena el envío de la orden hasta que lo corrijan
                      }

                      if (!esPuntoAPunto &&
                          telefonoController.text.trim().isEmpty &&
                          !esCotizacion) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Falta WhatsApp.'),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }

                      setDialogState(() => procesando = true);
                      _sonidos.reproducirSuave(
                        Sonidos.localAccion,
                      ); // Sonido de acción
                      final coords = await _obtenerOSellarGPSLocal();
                      if (coords == null) {
                        setDialogState(() => procesando = false);
                        return;
                      }

                      try {
                        String notaManual = notasController.text.trim();
                        String ticketNum = ticketController.text.trim();

                        int retardoProgramado = 0;
                        if (tiempoPreparacion == 'En 15 min')
                          retardoProgramado = 15;
                        else if (tiempoPreparacion == 'En 30 min')
                          retardoProgramado = 30;
                        else if (tiempoPreparacion == 'En 45 min')
                          retardoProgramado = 45;

                        String liberacionCalculada = DateTime.now()
                            .toUtc()
                            .add(Duration(minutes: retardoProgramado))
                            .toIso8601String();
                        String estadoFinal = esCotizacion
                            ? 'cotizacion'
                            : (retardoProgramado > 0
                                  ? 'programado'
                                  : 'pendiente');

                        String tipoDefecto =
                            perfilEnVivo['tipo_servicio_defecto'] ?? 'COMIDA';
                        String instruccionesFijas =
                            perfilEnVivo['instrucciones_recogida'] ?? '';
                        final tipoUp = tipoDefecto.toUpperCase();
                        String tagServicio = '[ $tipoUp ]';

                        String bloqueTicket = ticketNum.isNotEmpty
                            ? '[ TICKET: #$ticketNum ] '
                            : '';

                        if (esPuntoAPunto) {
                          notaManual = '[PUNTO A PIN] $notaManual';
                        } else if (tiempoPreparacion != 'Inmediato') {
                          notaManual =
                              '[⏰ PROGRAMADO: $tiempoPreparacion] $notaManual';
                        }

                        String bloqueInstrucciones =
                            instruccionesFijas.isNotEmpty
                            ? '\n• Recogida: $instruccionesFijas'
                            : '';
                        String observacionFinal =
                            '$tagServicio $bloqueTicket$notaManual$bloqueInstrucciones';

                        String tarifaLimpia = tarifaController.text
                            .replaceAll('\$', '')
                            .replaceAll('.', '')
                            .replaceAll(',', '')
                            .trim();
                        double tarifaNueva = (esPuntoAPunto || esCotizacion)
                            ? 0.0
                            : (double.tryParse(tarifaLimpia) ?? 0.0);
                        // VIP directo (no cotización): se suman $3.000 automáticamente.
                        // Si el local elige "Estándar" en el fallback, se restan esos mismos $3.000.
                        if (esVip && !esCotizacion && tarifaNueva > 0) {
                          tarifaNueva += 3000;
                        }
                        final destinoNuevo = destinoController.text.trim();

                        // --- INTERCEPTOR DE RECARGO OBLIGATORIO ---
                        // Si el local cotizó un precio real (no cotización,
                        // no punto a punto — esos ya dan 0 arriba), revisamos
                        // si hay nocturno/lluvia activos para SU zona y
                        // obligamos a confirmar el precio final antes de
                        // continuar. El recargo no es opcional.
                        if (tarifaNueva > 0) {
                          final double? tarifaConfirmada =
                              await _confirmarRecargoObligatorio(tarifaNueva);
                          if (tarifaConfirmada == null) {
                            // El local canceló el despacho al ver el recargo
                            // (o el widget se desmontó). Abortamos todo el
                            // envío — vuelve al formulario para resolverlo
                            // por su cuenta.
                            setDialogState(() => procesando = false);
                            return;
                          }
                          tarifaNueva = tarifaConfirmada;
                        }

                        // --- ENRUTAR (antes "Doble Enganche") ---
                        // FIX: antes, al aceptar, fusionaba los dos
                        // pedidos en una sola fila — concatenaba
                        // destino como texto, sumaba tarifas, juntaba
                        // teléfonos. Eso mezclaba datos que debían
                        // quedar separados. Ahora cada pedido sigue
                        // siendo su propia fila — solo se enlazan con
                        // 'ruta_grupo_id' para que el candado atómico
                        // (tomar_servicio_candado) asigne los dos al
                        // mismo moto automáticamente al aceptar
                        // cualquiera de los dos.
                        String? rutaGrupoIdParaNuevo;
                        if (!esPuntoAPunto &&
                            !esCotizacion &&
                            retardoProgramado == 0) {
                          final pendientes = await Supabase.instance.client
                              .from('servicios')
                              .select()
                              .eq('local_id', widget.usuario['id'])
                              .eq('estado', 'pendiente')
                              .eq('es_punto_a_punto', false)
                              .order('id', ascending: true)
                              .limit(1);
                          if (pendientes.isNotEmpty) {
                            final pedidoBase = pendientes.first;
                            bool enrutar = false;
                            bool decisionTomada = false;
                            await showDialog(
                              context: context,
                              barrierDismissible: false,
                              builder: (ctxConfirm) => AlertDialog(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                title: const Row(
                                  children: [
                                    Icon(Icons.link, color: Colors.blue),
                                    SizedBox(width: 8),
                                    Text(
                                      'ENRUTAR',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.blue,
                                      ),
                                    ),
                                  ],
                                ),
                                content: Text(
                                  'Tienes la Orden #${pedidoBase['id']} pendiente de asignar móvil.\n\n¿Quieres ENRUTAR este nuevo pedido para que el mismo moto se lleve los dos? Cada uno mantiene su propio destino y tarifa — solo viajan juntos.',
                                  style: const TextStyle(fontSize: 14),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () {
                                      decisionTomada = true;
                                      enrutar = false;
                                      Navigator.pop(ctxConfirm);
                                    },
                                    child: const Text(
                                      'SEPARADOS',
                                      style: TextStyle(
                                        color: Colors.grey,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.blue,
                                    ),
                                    onPressed: () {
                                      decisionTomada = true;
                                      enrutar = true;
                                      Navigator.pop(ctxConfirm);
                                    },
                                    child: Text(
                                      'ENRUTAR (1 Moto)',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );

                            if (decisionTomada && enrutar) {
                              // El grupo usa el id del pedido base como
                              // identificador — estable, único, sin
                              // necesidad de generar nada aparte.
                              final grupoId = pedidoBase['id'].toString();
                              rutaGrupoIdParaNuevo = grupoId;
                              if (pedidoBase['ruta_grupo_id'] == null) {
                                await Supabase.instance.client
                                    .from('servicios')
                                    .update({'ruta_grupo_id': pedidoBase['id']})
                                    .eq('id', pedidoBase['id']);
                              }
                            }
                          }
                        }

                        // Variables para exclusividad de servicio — se
                        // setean ya sea por ENRUTAR a móvil activo O por
                        // el MOTOR MULTI-PARADERO (un bloque o el otro).
                        String? exclusivoIdCampo;
                        List<String> pilotosSeleccionadosIds = [];

                        // --- ENRUTAR CON MÓVIL ACTIVO ---
                        // Si ya hay un móvil haciendo una entrega de este local,
                        // ofrecemos enrutarle el nuevo encargo directamente
                        // (antes de que el servicio entre al radar).
                        if (!esCotizacion &&
                            !esPuntoAPunto &&
                            retardoProgramado == 0 &&
                            rutaGrupoIdParaNuevo == null) {
                          final svcActivos = await Supabase.instance.client
                              .from('servicios')
                              .select('id, movil_id')
                              .eq('local_id', widget.usuario['id'])
                              .inFilter('estado', ['en_ruta_origen', 'en_origen', 'en_ruta_destino'])
                              .not('movil_id', 'is', null)
                              .limit(5);

                          if (svcActivos.isNotEmpty) {
                            // IDs únicos de móviles activos
                            final Set<String> activoIds = svcActivos
                                .map((s) => s['movil_id'].toString())
                                .toSet();
                            final perfilesActivos = await Supabase.instance.client
                                .from('usuarios')
                                .select('id, usuario, nombre')
                                .inFilter('id', activoIds.toList());

                            if (perfilesActivos.isNotEmpty && context.mounted) {
                              Map<String, dynamic>? motoElegido;
                              bool decidioEnrutar = false;
                              await showDialog(
                                context: context,
                                barrierDismissible: false,
                                builder: (ctxE) => AlertDialog(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                                  title: const Row(
                                    children: [
                                      Icon(Icons.alt_route, color: Colors.blue),
                                      SizedBox(width: 8),
                                      Text('ENRUTAR',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.blue)),
                                    ],
                                  ),
                                  content: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Tienes móvil(es) en camino. ¿Enrutar este nuevo pedido?',
                                        style: TextStyle(fontSize: 13),
                                      ),
                                      const SizedBox(height: 10),
                                      ...perfilesActivos.map((m) => Padding(
                                        padding: const EdgeInsets.only(bottom: 6),
                                        child: SizedBox(
                                          width: double.infinity,
                                          child: ElevatedButton.icon(
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.blue[700],
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 12, vertical: 8)),
                                            onPressed: () {
                                              motoElegido = m;
                                              decidioEnrutar = true;
                                              Navigator.pop(ctxE);
                                            },
                                            icon: Icon(Icons.motorcycle,
                                              size: 16, color: Colors.white),
                                            label: Text(
                                              'ENRUTAR a ${(m['usuario'] ?? m['nombre'] ?? '').toString().toUpperCase()}',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold)),
                                          ),
                                        ),
                                      )),
                                    ],
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctxE),
                                      child: const Text('NO, AL RADAR',
                                        style: TextStyle(color: Colors.grey)),
                                    ),
                                  ],
                                ),
                              );

                              if (decidioEnrutar && motoElegido != null) {
                                // Enrutamos: el nuevo servicio va exclusivo
                                // al móvil elegido. También buscamos su
                                // servicio activo para vincular ruta_grupo_id.
                                final svcDelMoto = svcActivos.firstWhere(
                                  (s) => s['movil_id'].toString() == motoElegido!['id'].toString(),
                                  orElse: () => svcActivos.first,
                                );
                                rutaGrupoIdParaNuevo = svcDelMoto['id'].toString();
                                exclusivoIdCampo = motoElegido!['id'].toString();
                                pilotosSeleccionadosIds = [motoElegido!['id'].toString()];
                              }
                            }
                          }
                        }

                        // --- MOTOR MULTI-PARADERO ---
                        // Solo corre si no se enrutó ya a un móvil activo.
                        if (!esCotizacion && !esPuntoAPunto && exclusivoIdCampo == null) {
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

                          Map<String, String> numeroUnosPorParadero = {};
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
                              if (!ocupados.contains(candId)) {
                                numeroUnosPorParadero[pName] = candId;
                                break;
                              }
                            }
                          });

                          String paraderosLocalRaw =
                              widget.usuario['paradero_exclusivo']
                                  ?.toString() ??
                              '';
                          List<String> paraderosDelLocal = paraderosLocalRaw
                              .split(',')
                              .map((e) => e.trim().toLowerCase())
                              .where((e) => e.isNotEmpty)
                              .toList();

                          if (paraderosDelLocal.isEmpty) {
                            numeroUnosPorParadero.forEach((pName, driverId) {
                              pilotosSeleccionadosIds.add(driverId);
                            });
                          } else {
                            for (var pLocal in paraderosDelLocal) {
                              if (numeroUnosPorParadero.containsKey(pLocal)) {
                                pilotosSeleccionadosIds.add(
                                  numeroUnosPorParadero[pLocal]!,
                                );
                              }
                            }
                          }

                          if (pilotosSeleccionadosIds.isNotEmpty) {
                            exclusivoIdCampo = pilotosSeleccionadosIds.join(
                              ',',
                            );
                          }
                        }

                        // REGISTRO EN BD
                        final respuestaServicio = await Supabase.instance.client
                            .from('servicios')
                            .insert({
                              'origen': esPuntoAPunto
                                  ? (widget.usuario['paradero_exclusivo'] ??
                                        'LOCAL')
                                  : widget.usuario['nombre'],
                              'origen_lat': esPuntoAPunto
                                  ? null
                                  : coords['lat'],
                              'origen_lng': esPuntoAPunto
                                  ? null
                                  : coords['lng'],
                              'destino': esPuntoAPunto
                                  ? widget.usuario['nombre']
                                  : destinoNuevo,
                              'destino_lat': esPuntoAPunto
                                  ? coords['lat']
                                  : null,
                              'destino_lng': esPuntoAPunto
                                  ? coords['lng']
                                  : null,
                              'telefono_receptor': esPuntoAPunto
                                  ? null
                                  : telefonoController.text.trim(),
                              'tarifa': tarifaNueva,
                              'tarifa_detalle': {
                                'total': tarifaNueva,
                                'base': tarifaNueva,
                                'fuente': 'local',
                              },
                              'observacion': observacionFinal,
                              'estado': estadoFinal,
                              'creador': widget.usuario['nombre'],
                              // Local siempre envía algo propio — nunca
                              // es un mototaxi de pasajero, así que el
                              // tipo queda fijo (sin selector de chips
                              // como en el de Central).
                              'tipo_servicio': 'PAQUETERÍA',
                              if (rutaGrupoIdParaNuevo != null)
                                'ruta_grupo_id': int.tryParse(
                                  rutaGrupoIdParaNuevo,
                                ),
                              'local_id': widget
                                  .usuario['id'], // FIX #4: clave única del local
                              'es_punto_a_punto': esPuntoAPunto,
                              'es_vip': esVip,
                              'exclusivo_id': exclusivoIdCampo,
                              'ticket_factura': ticketNum.isEmpty
                                  ? null
                                  : ticketNum,
                              'liberacion_at': liberacionCalculada,
                            })
                            .select()
                            .single();

                        final int nuevoServicioId =
                            respuestaServicio['id'] as int;

                        // Sonido de confirmación según tipo de servicio
                        if (esCotizacion) {
                          _sonidos.reproducirSuave(Sonidos.localCotizacion);
                        } else {
                          _sonidos.reproducirSuave(Sonidos.localAccion);
                        }

                        // DISPAROS ONESIGNAL
                        if (esCotizacion) {
                          // Segmento Central — más confiable que buscar IDs en tabla
                          await MotorNotificaciones.dispararACentral(
                            titulo: esVip ? '👑 COTIZACIÓN VIP' : '❓ NUEVA COTIZACIÓN',
                            mensaje: esVip
                                ? 'Cotización VIP pendiente de respuesta'
                                : 'Un local solicita cotización de tarifa',
                            urgente: true,
                          );
                        } else if (esVip) {
                          // ── FLUJO VIP ──────────────────────────────────────────
                          // 1. Notificar Masters inmediatamente (sin paradero).
                          // 2. Notificar al Leyenda más cercano al #1 con 30s de delay.
                          // Si no hay ninguno disponible, ofrecer estándar al local.
                          const String mensajeVip =
                              'Servicio VIP disponible — revisa el radar';

                          final mastersVip = await Supabase.instance.client
                              .from('usuarios')
                              .select('id')
                              .eq('rol', 'movil')
                              .eq('en_linea', true)
                              .inFilter('rango_movil', ['MASTER']);
                          final List<String> masterVipIds = mastersVip
                              .map((u) => u['id'].toString())
                              .toList();

                          // Leyendas en paradero ordenados por ingreso_fila asc
                          // → el primero de la lista es el más cercano al #1
                          final leyendasVip = await Supabase.instance.client
                              .from('usuarios')
                              .select('id, paradero_actual, ingreso_fila')
                              .eq('rol', 'movil')
                              .eq('en_linea', true)
                              .eq('rango_movil', 'LEYENDA')
                              .not('paradero_actual', 'is', null)
                              .order('ingreso_fila', ascending: true);

                          // Tomamos solo el Leyenda más adelante en la fila
                          final List<String> leyendaVipIds =
                              leyendasVip.isNotEmpty
                              ? [leyendasVip.first['id'].toString()]
                              : [];

                          if (masterVipIds.isEmpty && leyendaVipIds.isEmpty) {
                            // No hay VIP online en este momento → diálogo inmediato
                            _mostrarDialogoFallbackVip(
                              servicioId: nuevoServicioId,
                              destino: destinoNuevo,
                              pilotosParadero: pilotosSeleccionadosIds,
                              esPuntoAPunto: esPuntoAPunto,
                              coords: coords,
                              tarifaConVip: (respuestaServicio['tarifa'] as num?)?.toDouble() ?? 0.0,
                            );
                          } else {
                            // Hay VIP online → notificar y en 3 min verificar si alguien aceptó
                            if (masterVipIds.isNotEmpty) {
                              await _dispararMisilInmediato(
                                externalIds: masterVipIds,
                                titulo: '👑 SERVICIO VIP',
                                mensaje: mensajeVip,
                              );
                            }
                            if (leyendaVipIds.isNotEmpty) {
                              // Misil retardado T+30s — sobrevive si el local navega
                              // y tiene ID para cancelar si un Master lo acepta antes
                              final id30sVip = await _programarMisilRetardado(
                                externalIds: leyendaVipIds,
                                titulo: '👑 SERVICIO VIP',
                                mensaje: mensajeVip,
                                segundosRetardo: 30,
                              );
                              if (id30sVip != null) {
                                await Supabase.instance.client
                                    .from('servicios')
                                    .update({'onesignal_30s': id30sVip})
                                    .eq('id', nuevoServicioId);
                              }
                            }
                            // Timer 3 min: si nadie acepta → diálogo al local
                            Future.delayed(const Duration(minutes: 3), () {
                              _verificarFallbackVip(
                                servicioId: nuevoServicioId,
                                destino: destinoNuevo,
                                pilotosParadero: pilotosSeleccionadosIds,
                                esPuntoAPunto: esPuntoAPunto,
                                coords: coords,
                                tarifaConVip: (respuestaServicio['tarifa'] as num?)?.toDouble() ?? 0.0,
                              );
                            });
                          }
                          // Los servicios VIP NO generan alertas +2min/+5min:
                          // son exclusivos hasta que Master/Leyenda lo acepten.
                        } else {
                          const String mensajeAlarma =
                              'Nuevo servicio disponible — revisa el radar';
                          final mastersData = await Supabase.instance.client
                              .from('usuarios')
                              .select('id')
                              .or('rol.eq.central,rol.eq.master,rango_movil.eq.MASTER')
                              .neq('suspendido', true);
                          List<String> masterIds = mastersData
                              .map((u) => u['id'].toString())
                              .toList();

                          if (masterIds.isNotEmpty) {
                            await _dispararMisilInmediato(
                              externalIds: masterIds,
                              titulo: retardoProgramado > 0
                                  ? '👑 SERVICIO PROGRAMADO'
                                  : '👑 NUEVO SERVICIO',
                              mensaje: mensajeAlarma,
                            );
                          }

                          if (pilotosSeleccionadosIds.isNotEmpty) {
                            List<String> targetPilotos = pilotosSeleccionadosIds
                                .where((id) => !masterIds.contains(id))
                                .toList();
                            if (targetPilotos.isNotEmpty) {
                              // Paradero: siempre notificamos (sin chequeo de cola)
                              String? id30s;
                              if (retardoProgramado > 0) {
                                id30s = await _programarMisilRetardado(
                                  externalIds: targetPilotos,
                                  titulo: 'TU TURNO DE PARADERO',
                                  mensaje: mensajeAlarma,
                                  minutosRetardo: retardoProgramado,
                                );
                              } else {
                                // Misil programado T+30s — no depende del widget montado
                                id30s = await _programarMisilRetardado(
                                  externalIds: targetPilotos,
                                  titulo: 'TU TURNO DE PARADERO',
                                  mensaje: mensajeAlarma,
                                  segundosRetardo: 30,
                                );
                              }
                              // Guardar ID para cancelarlo si alguien acepta antes de los 30s
                              if (id30s != null) {
                                await Supabase.instance.client
                                    .from('servicios')
                                    .update({'onesignal_30s': id30s})
                                    .eq('id', nuevoServicioId);
                              }
                            }
                          }

                          // Olas T=+60s y T=+90s
                          // • Servicio inmediato (retardoProgramado==0): Future.delayed
                          // • Servicio programado (retardoProgramado>0): misil retardado
                          if (!esPuntoAPunto) {
                            final int _svcId2 = nuevoServicioId;
                            final String _msg2 = mensajeAlarma;
                            final List<String> _mSnap = List<String>.from(masterIds);
                            final List<String> _pSnap = List<String>.from(
                                pilotosSeleccionadosIds);

                            if (retardoProgramado > 0) {
                              // Misiles programados relativo al retardo base
                              List<String> zona1kmIds = [];
                              List<String> todosIds = [];
                              final medidor = const Distance();
                              final movilesActivos = await Supabase
                                  .instance.client.from('usuarios')
                                  .select('id, latitud, longitud')
                                  .eq('rol', 'movil').eq('en_linea', true);
                              for (var m in movilesActivos) {
                                final idStr = m['id'].toString();
                                todosIds.add(idStr);
                                double dist = 999999;
                                if (m['latitud'] != null && m['longitud'] != null &&
                                    coords['lat'] != null && coords['lng'] != null) {
                                  dist = medidor.as(
                                    LengthUnit.Meter,
                                    LatLng((m['latitud'] as num).toDouble(),
                                           (m['longitud'] as num).toDouble()),
                                    LatLng((coords['lat'] as num).toDouble(),
                                           (coords['lng'] as num).toDouble()),
                                  );
                                }
                                if (dist <= 1000) zona1kmIds.add(idStr);
                              }
                              String? id1m;
                              String? id2m;
                              if (zona1kmIds.isNotEmpty)
                                id1m = await _programarMisilRetardado(
                                  externalIds: zona1kmIds,
                                  titulo: '📡 SERVICIO CERCA',
                                  mensaje: 'Servicio a menos de 1km — revisa el radar.',
                                  minutosRetardo: retardoProgramado + 1,
                                );
                              if (todosIds.isNotEmpty)
                                id2m = await _programarMisilRetardado(
                                  externalIds: todosIds,
                                  titulo: '🚨 SERVICIO SIN TOMAR',
                                  mensaje: '¡Revisa el Radar!',
                                  minutosRetardo: retardoProgramado + 2,
                                );
                              if (id1m != null || id2m != null) {
                                await Supabase.instance.client
                                    .from('servicios').update({
                                      if (id1m != null) 'onesignal_2m': id1m,
                                      if (id2m != null) 'onesignal_5m': id2m,
                                    }).eq('id', _svcId2);
                              }
                            } else {
                              // Servicio inmediato: T=+60s (1km) y T=+90s via Future.delayed
                              final double? _oLat2 = (coords['lat'] as num?)?.toDouble();
                              final double? _oLng2 = (coords['lng'] as num?)?.toDouble();
                              Future.delayed(const Duration(seconds: 60), () async {
                                final chk = await Supabase.instance.client
                                    .from('servicios').select('estado')
                                    .eq('id', _svcId2).maybeSingle();
                                if (chk == null || chk['estado'] != 'pendiente') return;
                                final candidatos = await Supabase.instance.client
                                    .from('usuarios').select('id, latitud, longitud')
                                    .eq('rol', 'movil').eq('en_linea', true)
                                    .neq('suspendido', true)
                                    .not('rango_movil', 'in', '("MASTER")');
                                final idsZ = (candidatos as List).where((u) {
                                  final id = u['id'].toString();
                                  if (_mSnap.contains(id) || _pSnap.contains(id)) return false;
                                  if (_oLat2 == null || _oLng2 == null) return true;
                                  final uLat = (u['latitud'] as num?)?.toDouble();
                                  final uLng = (u['longitud'] as num?)?.toDouble();
                                  if (uLat == null || uLng == null) return false;
                                  return const Distance().as(
                                        LengthUnit.Meter,
                                        LatLng(uLat, uLng),
                                        LatLng(_oLat2, _oLng2),
                                      ) <= 1000;
                                }).map((u) => u['id'].toString()).toList();
                                if (idsZ.isNotEmpty)
                                  await _dispararMisilInmediato(
                                    externalIds: idsZ,
                                    titulo: '📡 SERVICIO CERCA (1km)',
                                    mensaje: _msg2,
                                  );
                              });
                              Future.delayed(const Duration(seconds: 90), () async {
                                final chk = await Supabase.instance.client
                                    .from('servicios').select('estado')
                                    .eq('id', _svcId2).maybeSingle();
                                if (chk == null || chk['estado'] != 'pendiente') return;
                                final todos = await Supabase.instance.client
                                    .from('usuarios').select('id')
                                    .eq('rol', 'movil').eq('en_linea', true)
                                    .neq('suspendido', true);
                                final idsT = (todos as List)
                                    .map((u) => u['id'].toString())
                                    .where((id) => !_mSnap.contains(id))
                                    .toList();
                                if (idsT.isNotEmpty)
                                  await _dispararMisilInmediato(
                                    externalIds: idsT,
                                    titulo: '🚨 SERVICIO SIN TOMAR',
                                    mensaje: _msg2,
                                  );
                              });
                            }
                          }
                        }

                        // ---> CIERRE Y APERTURA DE POPUP PARA GUARDAR NUEVOS PRECIOS <---
                        if (context.mounted) {
                          Navigator.pop(
                            context,
                          ); // Cierra el modal principal de despacho

                          // MAGIA INTELIGENTE: Aislamos el barrio usando el guion como separador
                          String destinoMayus = destinoNuevo.toUpperCase();
                          String barrioExtraido = destinoMayus.contains('-')
                              ? destinoMayus.split('-')[0].trim()
                              : destinoMayus;

                          bool yaEstaGuardado = listaPrecios.any((item) {
                            final s = item['sectores'] as Map<String, dynamic>?;
                            if (s == null) return false;
                            final clave = '${s['nombre']} (${s['municipio']})'.toUpperCase();
                            // Es el mismo barrio exacto (antes del guion) O empieza igual y vale lo mismo
                            return barrioExtraido == clave ||
                                (destinoMayus.startsWith(clave) &&
                                    (item['tarifa'] as num).toDouble() ==
                                        tarifaNueva);
                          });

                          // Si NO es punto a punto, NO es cotización, y NO está guardado -> Preguntamos
                          if (!esPuntoAPunto &&
                              !esCotizacion &&
                              !yaEstaGuardado) {
                            final barrioCtrl = TextEditingController(
                              text: barrioExtraido,
                            );
                            String zonaSeleccionada = 'CÚCUTA';
                            bool guardandoLista = false;

                            showDialog(
                              context: context,
                              builder: (ctxSave) => StatefulBuilder(
                                builder: (ctxSave, setSaveState) => AlertDialog(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  title: const Text(
                                    '💾 ¿GUARDAR EN TU LISTA?',
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
                                      Text(
                                        'Tarifa cobrada: ${tarifaController.text}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.blue,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      TextField(
                                        controller: barrioCtrl,
                                        textCapitalization:
                                            TextCapitalization.characters,
                                        decoration: const InputDecoration(
                                          labelText:
                                              'Barrio / Lugar (Ej: COCONUCO)',
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
                                        children:
                                            [
                                              'CÚCUTA',
                                              'LOS PATIOS',
                                              'V. ROSARIO',
                                              'EL ZULIA',
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
                                                  if (selected)
                                                    setSaveState(
                                                      () =>
                                                          zonaSeleccionada = z,
                                                    );
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
                                      onPressed: guardandoLista
                                          ? null
                                          : () async {
                                              if (barrioCtrl.text
                                                  .trim()
                                                  .isEmpty)
                                                return;
                                              setSaveState(
                                                () => guardandoLista = true,
                                              );
                                              try {
                                                final sectorId = await _buscarOCrearSector(
                                                  barrioCtrl.text.trim().toUpperCase(),
                                                  zonaSeleccionada,
                                                );

                                                await Supabase.instance.client
                                                    .from('tarifas_locales')
                                                    .upsert(
                                                      {
                                                        'local_id': widget.usuario['id'],
                                                        'local_nombre': widget.usuario['nombre'],
                                                        'sector_id': sectorId,
                                                        'tarifa': tarifaNueva,
                                                      },
                                                      onConflict: 'local_id, sector_id',
                                                    );

                                                if (ctxSave.mounted) {
                                                  Navigator.pop(ctxSave);
                                                  ScaffoldMessenger.of(
                                                    context,
                                                  ).showSnackBar(
                                                    const SnackBar(
                                                      content: Text(
                                                        '✅ Dirección guardada en tu lista de precios.',
                                                      ),
                                                      backgroundColor:
                                                          Colors.green,
                                                    ),
                                                  );
                                                }
                                              } catch (e) {
                                                setSaveState(
                                                  () => guardandoLista = false,
                                                );
                                                if (ctxSave.mounted)
                                                  ScaffoldMessenger.of(
                                                    context,
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
                                            },
                                      child: guardandoLista
                                          ? const SizedBox(
                                              width: 16,
                                              height: 16,
                                              child: CircularProgressIndicator(
                                                color: Color(0xff3AF500),
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : const Text(
                                              'GUARDAR DIRECCIÓN',
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
                        if (context.mounted)
                          ScaffoldMessenger.of(
                            context,
                          ).showSnackBar(SnackBar(content: Text('Error: $e')));
                      }
                    },
              child: procesando
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Text(
                      esCotizacion ? 'ENVIAR A CENTRAL' : 'ENVIAR PEDIDO',
                      style: const TextStyle(
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

  // --- CONTROLES OPERATIVOS ---
  Future<void> _cancelarPedido(int id) async {
    try {
      // 1. Cambiamos el estado en Supabase primero (Garantiza que la orden se cancele sí o sí)
      final res = await Supabase.instance.client
          .from('servicios')
          .update({'estado': 'cancelado'})
          .eq('id', id)
          .select('onesignal_2m, onesignal_5m')
          .maybeSingle();

      // 2. Intentamos bajar las notificaciones programadas de forma silenciosa
      if (res != null) {
        // Mismo App ID que MotorNotificaciones (207d1d0a) — donde se programaron
        const String appId = '207d1d0a-0218-46e0-9f35-7d8d88f6765a';
        const String restApiKey =
            'os_v2_app_eb6r2cqcdbdobhzvpwgyr5twlinl2pbrrxzeyrmltx2iwaupqy7uibm7gyzzc6ne4shl7lcmas2mobfum347m5ljvzlahf5pkj2yuvi';

        // Motor táctico interno para no repetir código y silenciar errores
        Future<void> anularMisil(dynamic onesignalId) async {
          if (onesignalId == null) return;
          String mId = onesignalId.toString().trim();

          // El candado que te faltaba: Si está vacío o dice "null", aborta el disparo
          if (mId.isEmpty || mId == 'null') return;

          try {
            await http.delete(
              Uri.parse(
                'https://onesignal.com/api/v1/notifications/$mId?app_id=$appId',
              ),
              headers: {'Authorization': 'Basic $restApiKey'},
            );
          } catch (e) {
            // Si OneSignal falla (por Web/CORS o red), lo silenciamos. La orden ya está cancelada.
            debugPrint('Falla ignorada en OneSignal: $e');
          }
        }

        // Disparamos la anulación sin que afecte la interfaz del local
        await anularMisil(res['onesignal_2m']);
        await anularMisil(res['onesignal_5m']);
      }

      // Notificar a la Central que el pedido fue cancelado por el local
      MotorNotificaciones.dispararACentral(
        titulo: '❌ PEDIDO CANCELADO',
        mensaje: '${widget.usuario['nombre']} canceló el pedido #$id.',
        urgente: false,
        sonido: 'central_cancelado',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cancelar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // --- MOTOR DE CALIFICACIÓN 5.0 ---
  void _mostrarDialogoCalificacion(Map<String, dynamic> servicio) {
    int estrellas = 5;
    final comentarioController = TextEditingController();
    bool procesando = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          title: const Text(
            'CALIFICAR MÓVIL',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '¿Cómo estuvo el servicio de este móvil?',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (index) {
                  return IconButton(
                    icon: Icon(
                      index < estrellas ? Icons.star : Icons.star_border,
                      color: Colors.amber,
                      size: 32,
                    ),
                    onPressed: () =>
                        setDialogState(() => estrellas = index + 1),
                  );
                }),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: comentarioController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Comentario (Opcional)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: procesando ? null : () => Navigator.pop(context),
              child: const Text(
                'CANCELAR',
                style: TextStyle(color: Colors.grey),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.black),
              onPressed: procesando
                  ? null
                  : () async {
                      setDialogState(() => procesando = true);
                      try {
                        final servicioId = servicio['id'];
                        final movilId = servicio['movil_id'];
                        final comentarioFinal =
                            comentarioController.text.trim().isEmpty
                            ? null
                            : comentarioController.text.trim();

                        // 1. Sellamos la nota del local en servicios
                        await Supabase.instance.client
                            .from('servicios')
                            .update({
                              'calificacion_local': estrellas,
                              'comentario_local': comentarioFinal,
                            })
                            .eq('id', servicioId);

                        // 2. INSERT en calificaciones (fuente de verdad
                        //    para el perfil del móvil y Central).
                        await Supabase.instance.client
                            .from('calificaciones')
                            .upsert({
                              'servicio_id': servicioId,
                              'movil_id': movilId.toString(),
                              'calificador_tipo': 'local',
                              'calificador_id':
                                  widget.usuario['id'].toString(),
                              'calificador_nombre':
                                  widget.usuario['nombre'].toString(),
                              'estrellas': estrellas,
                              'comentario': comentarioFinal,
                            }, onConflict: 'servicio_id, calificador_tipo');

                        // 3. Recalculamos la puntuación del móvil — ahora
                        // vive en una sola función SQL (recalcular_
                        // puntuacion_movil) en vez de repetir esta lógica
                        // en Dart. Evita que Local y Cliente diverjan al
                        // calcular el mismo promedio cada uno por su lado.
                        await Supabase.instance.client.rpc(
                          'recalcular_puntuacion_movil',
                          params: {'p_movil_id': movilId},
                        );

                        if (context.mounted) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Calificación enviada. ¡Gracias!'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      } catch (e) {
                        setDialogState(() => procesando = false);
                        if (context.mounted) {
                          ScaffoldMessenger.of(
                            context,
                          ).showSnackBar(SnackBar(content: Text('Error: $e')));
                        }
                      }
                    },
              child: procesando
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        color: Colors.amber,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text(
                      'ENVIAR NOTA',
                      style: TextStyle(
                        color: Colors.amber,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _construirTarjetaServicio(
    Map<String, dynamic> servicio, {
    bool esHistorial = false,
    bool esGlobal = false,
    VoidCallback? onOcultar,
    VoidCallback? onEliminar,
    VoidCallback? extraRebuild,
  }) {
    final int svcId = servicio['id'] as int;
    // Activos: expandidos por defecto (colapsar los agrega al set)
    // Historial: colapsados por defecto (expandir los agrega al set)
    final bool estaExpandida = esHistorial
        ? _tarjetasExpandidasLocal.contains(svcId)
        : !_tarjetasColapsadasLocal.contains(svcId);
    void toggleExpansion() {
      setState(() {
        if (esHistorial) {
          if (_tarjetasExpandidasLocal.contains(svcId)) {
            _tarjetasExpandidasLocal.remove(svcId);
          } else {
            _tarjetasExpandidasLocal.add(svcId);
          }
        } else {
          if (_tarjetasColapsadasLocal.contains(svcId)) {
            _tarjetasColapsadasLocal.remove(svcId);
          } else {
            _tarjetasColapsadasLocal.add(svcId);
          }
        }
      });
      extraRebuild?.call();
    }
    final estado = servicio['estado'];

    late Color bordeColor;
    late Color fondoColor;
    late String textoEstado;
    late IconData iconoEstado;

    // --- NUEVO SISTEMA DE ESTADOS VISUALES ---
    if (estado == 'programado') {
      bordeColor = Colors.blue[700]!;
      fondoColor = Colors.blue[50]!;
      textoEstado = 'PROGRAMADO';
      iconoEstado = Icons.schedule;

      if (servicio['liberacion_at'] != null) {
        final lib = DateTime.parse(servicio['liberacion_at']).toLocal();
        final ahora = DateTime.now();
        final diff = lib.difference(ahora).inMinutes;

        if (diff > 0) {
          textoEstado = 'PROGRAMADO (EN $diff MIN)';
        } else {
          textoEstado = 'LIBERANDO AL RADAR...';

          // ---> GATILLO AUTOMÁTICO: Empuja el servicio a la calle al llegar a 0 <---
          Future.microtask(() async {
            try {
              await Supabase.instance.client
                  .from('servicios')
                  .update({'estado': 'pendiente'})
                  .eq('id', servicio['id']);
            } catch (_) {}
          });
        }
      }
    } else if (estado == 'pendiente') {
      bordeColor = Colors.black54;
      fondoColor = Colors.grey[100]!;
      textoEstado = 'BUSCANDO MÓVIL...';
      iconoEstado = Icons.radar;
    } else if (estado == 'en_origen') {
      // <--- INYECCIÓN: ESTADO ESPERANDO EN LOCAL
      bordeColor = Colors.orange[800]!;
      fondoColor = Colors.orange[50]!;
      textoEstado = 'MÓVIL ESPERANDO EN EL LOCAL';
      iconoEstado = Icons.storefront;
    } else if (estado == 'en_curso' ||
        estado == 'en_ruta_origen' ||
        estado == 'en_ruta_destino') {
      bordeColor = const Color(0xff3AF500);
      fondoColor = const Color(0xfff0fff0);

      if (estado == 'en_ruta_origen') {
        textoEstado = 'MÓVIL EN CAMINO AL LOCAL';
      } else if (estado == 'en_ruta_destino') {
        textoEstado = 'EN RUTA DE ENTREGA';
      } else {
        textoEstado = 'MÓVIL ASIGNADO';
      }
      iconoEstado = Icons.motorcycle;
    } else if (estado == 'problema') {
      bordeColor = Colors.red;
      fondoColor = const Color(0xfffff0f0);
      textoEstado = 'NOVEDAD REPORTADA';
      iconoEstado = Icons.warning_amber_rounded;
    } else if (estado == 'caducado') {
      bordeColor = Colors.purple;
      fondoColor = const Color(0xfff8f0ff);
      textoEstado = 'NADIE TOMÓ EL SERVICIO';
      iconoEstado = Icons.hourglass_disabled;
    } else if (estado == 'cotizacion') {
      bordeColor = Colors.orange[700]!;
      fondoColor = Colors.orange[50]!;
      textoEstado = 'ESPERANDO PRECIO...';
      iconoEstado = Icons.access_time_filled;
    } else if (estado == 'cotizada') {
      bordeColor = Colors.blue[700]!;
      fondoColor = Colors.blue[50]!;
      textoEstado = 'COTIZACIÓN RECIBIDA';
      iconoEstado = Icons.monetization_on;
    } else if (estado == 'cotizacion_aprobada') {
      bordeColor = Colors.teal[700]!;
      fondoColor = Colors.teal[50]!;
      textoEstado = 'APROBADA · EN ESPERA';
      iconoEstado = Icons.check_circle_outline;
    } else if (estado == 'finalizado') {
      bordeColor = Colors.green;
      fondoColor = Colors.white;
      textoEstado = 'COMPLETADO';
      iconoEstado = Icons.check_circle;
    } else if (estado == 'cancelado') {
      bordeColor = Colors.grey;
      fondoColor = const Color(0xfff9f9f9);
      textoEstado = 'CANCELADO';
      iconoEstado = Icons.block;
    } else if (estado == 'finalizado_por_demora' ||
        estado == 'finalizado_con_problema') {
      bordeColor = Colors.orange[800]!;
      fondoColor = Colors.orange[50]!;
      textoEstado = 'CERRADO CON NOVEDAD';
      iconoEstado = Icons.report_problem;
    } else {
      bordeColor = Colors.grey;
      fondoColor = Colors.white;
      textoEstado = 'ESTADO DESCONOCIDO';
      iconoEstado = Icons.help_outline;
    }

    String? ticketPOS = servicio['ticket_factura']?.toString();
    String? telCliente = servicio['telefono_receptor']?.toString();

    return AnimatedSize(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeInOut,
      alignment: Alignment.topCenter,
      child: Card(
      elevation: esHistorial ? 1 : 3,
      margin: const EdgeInsets.only(bottom: 12),
      color: fondoColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: bordeColor, width: esHistorial ? 1.0 : 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── HEADER SIEMPRE VISIBLE ──────────────────────────────────
          InkWell(
            onTap: toggleExpansion,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  // Badge de estado (anima con AnimatedSwitcher cuando cambia)
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 280),
                    child: Row(
                      key: ValueKey('estado_$svcId$textoEstado'),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(iconoEstado, color: bordeColor, size: 18),
                        const SizedBox(width: 6),
                        Text(
                          textoEstado,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: bordeColor,
                            fontSize: 12,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Destino truncado (solo si está colapsado)
                  if (!estaExpandida) ...[
                    const Text('·', style: TextStyle(color: Colors.black38)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        servicio['destino']?.toString() ?? '',
                        style: const TextStyle(fontSize: 12, color: Colors.black54),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ] else
                    const Spacer(),
                  Text(
                    '#${servicio['numero_local'] ?? servicio['id']}',
                    style: const TextStyle(color: Colors.black38, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    estaExpandida ? Icons.expand_less : Icons.expand_more,
                    color: Colors.black38,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
          // ── CUERPO EXPANDIBLE ───────────────────────────────────────
          if (estaExpandida) Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            const Divider(height: 16),

            if (ticketPOS != null && ticketPOS.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '🧾 Factura / Ticket: #$ticketPOS',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.blueAccent,
                  ),
                ),
              ),

            Text(
              '🏁 Destino: ${servicio['destino']}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),

            if (servicio['movil_id'] != null)
              FutureBuilder<List<Map<String, dynamic>>>(
                future: Supabase.instance.client
                    .from('usuarios')
                    .select(
                      'id, nombre, usuario, rol, telefono, foto_perfil_url, '
                      'pago_nequi, pago_daviplata, pago_bancolombia',
                    )
                    .eq('id', servicio['movil_id']),
                builder: (context, snapshot) {
                  final data =
                      (snapshot.data != null && snapshot.data!.isNotEmpty)
                      ? snapshot.data!.first
                      : null;

                  String nombreFinal = 'Desconocido';
                  // FIX: 'telMovil' es el NÚMERO DE OPERACIÓN del moto
                  // (ej: "12", sacado de "movil12") — solo sirve para
                  // mostrar/identificar, NUNCA para WhatsApp. El número
                  // real de WhatsApp vive en 'telefonoReal', el campo
                  // 'telefono' de verdad. Antes el botón de WhatsApp
                  // usaba telMovil por error — apuntaba a un número que
                  // no existe (wa.me/5712 en vez del teléfono real).
                  String telMovil = '';
                  String telefonoReal = '';
                  String numeroAvatar = '?';
                  final String? fotoUrl = data?['foto_perfil_url']?.toString();
                  final bool tieneFoto = fotoUrl != null && fotoUrl.isNotEmpty;

                  if (data != null) {
                    final rol = data['rol']?.toString() ?? 'movil';
                    final usr = data['usuario']?.toString() ?? '';
                    telMovil = usr.replaceAll(RegExp(r'[^0-9]'), '');
                    telefonoReal = data['telefono']?.toString() ?? '';
                    numeroAvatar = telMovil.isNotEmpty ? telMovil : '?';

                    if (rol == 'movil') {
                      nombreFinal = telMovil.isNotEmpty
                          ? 'Móvil $telMovil'
                          : (data['nombre']?.toString().toUpperCase() ??
                                'Móvil');
                    } else {
                      nombreFinal = data['nombre']?.toString() ?? 'Móvil';
                    }
                  }

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // --- INFO OBLIGATORIA: nombre, número, foto, pago ---
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 18,
                              backgroundColor: Colors.black87,
                              backgroundImage:
                                  tieneFoto ? NetworkImage(fotoUrl) : null,
                              child: !tieneFoto
                                  ? Text(
                                      numeroAvatar,
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    )
                                  : null,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    nombreFinal,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black87,
                                      fontSize: 13,
                                    ),
                                  ),
                                  if (data != null &&
                                      data['nombre'] != null &&
                                      data['rol'] == 'movil')
                                    Text(
                                      data['nombre'].toString().toUpperCase(),
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.grey[500],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (data != null &&
                            ((data['pago_nequi']?.toString().isNotEmpty ?? false) ||
                                (data['pago_daviplata']?.toString().isNotEmpty ?? false) ||
                                (data['pago_bancolombia']?.toString().isNotEmpty ?? false)))
                          Padding(
                            padding: const EdgeInsets.only(top: 6, left: 46),
                            child: Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                if (data['pago_nequi']?.toString().isNotEmpty ?? false)
                                  _chipPagoLocal('Nequi', const Color(0xFFE5007D), Colors.white, data['pago_nequi']),
                                if (data['pago_daviplata']?.toString().isNotEmpty ?? false)
                                  _chipPagoLocal('Daviplata', const Color(0xFFEE2A24), Colors.white, data['pago_daviplata']),
                                if (data['pago_bancolombia']?.toString().isNotEmpty ?? false)
                                  _chipPagoLocal('Bancolombia', const Color(0xFFFFCC00), Colors.black, data['pago_bancolombia']),
                              ],
                            ),
                          ),
                        if (data != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.black54,
                                  side: BorderSide(color: Colors.grey[400]!),
                                  padding: const EdgeInsets.symmetric(vertical: 6),
                                ),
                                onPressed: () => _verPerfilMovilLocal(context, data),
                                icon: const Icon(Icons.badge_outlined, size: 14),
                                label: const Text(
                                  'VER PERFIL',
                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                          ),
                        // ENRUTAR — siempre visible mientras el servicio
                        // sigue activo, no solo cuando el sistema
                        // detecta similitud o cercanía. Súmale otro
                        // encargo al mismo moto sin esperar a que
                        // termine el actual (sujeto a su cupo de rango).
                        if (data != null &&
                            ['en_ruta_origen', 'en_origen', 'en_ruta_destino']
                                .contains(estado))
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.blue[700],
                                  side: BorderSide(color: Colors.blue[300]!),
                                  padding: const EdgeInsets.symmetric(vertical: 6),
                                ),
                                onPressed: () => _abrirEnrutarAlMoto(context, servicio, data),
                                icon: const Icon(Icons.alt_route, size: 14),
                                label: const Text(
                                  'ENRUTAR (sumar otro encargo)',
                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                          ),

                        // --- CENTRO DE COMUNICACIÓN EN VIVO Y AUDITORÍA ---
                        if (data != null) ...[
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              // 1. BOTÓN DE WHATSAPP (SIEMPRE ACTIVO)
                              // FIX: antes usaba telMovil (el "12" de
                              // movil12) — apuntaba a un número que no
                              // existe. Ahora usa telefonoReal.
                              if (telefonoReal.isNotEmpty)
                                Expanded(
                                  child: OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.green[700],
                                      side: BorderSide(
                                        color: Colors.green[700]!,
                                      ),
                                      // ---> INYECCIÓN: Quitamos el margen lateral que apachurra el texto
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 8,
                                        horizontal: 2,
                                      ),
                                    ),
                                    icon: const Icon(Icons.wechat, size: 16),
                                    // ---> INYECCIÓN: FittedBox encoge la letra si la pantalla es muy pequeña
                                    label: const FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        'WhatsApp',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                    onPressed: () async {
                                      final numero = telefonoReal.startsWith('57')
                                          ? telefonoReal
                                          : '57$telefonoReal';
                                      final uri = Uri.parse(
                                        'https://wa.me/$numero',
                                      );
                                      if (await canLaunchUrl(uri)) {
                                        await launchUrl(
                                          uri,
                                          mode: LaunchMode.externalApplication,
                                        );
                                      }
                                    },
                                  ),
                                ),

                              if (telefonoReal.isNotEmpty) const SizedBox(width: 8),

                              // 2. BOTÓN DE CHAT INTERNO (MUTA ENTRE CHAT ACTIVO Y BITÁCORA DE HISTORIAL)
                              Expanded(
                                child: Builder(
                                  builder: (context) {
                                    // La alarma de parpadeo solo se activa si el pedido sigue vivo
                                    bool tieneMensajeNuevo =
                                        !esHistorial &&
                                        servicio['chat_cliente'] == true;

                                    return ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: tieneMensajeNuevo
                                            ? Colors.red[700]
                                            : (esHistorial
                                                  ? Colors.grey[800]
                                                  : Colors.blue[800]),
                                        foregroundColor: Colors.white,
                                        // ---> INYECCIÓN: Igualamos los márgenes
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 8,
                                          horizontal: 2,
                                        ),
                                      ),
                                      icon: Icon(
                                        tieneMensajeNuevo
                                            ? Icons.mark_email_unread
                                            : (esHistorial
                                                  ? Icons.history_toggle_off
                                                  : Icons.chat),
                                        size: 16,
                                      ),
                                      // ---> INYECCIÓN: FittedBox para evitar que "NUEVO MENSAJE" se parta
                                      label: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text(
                                          tieneMensajeNuevo
                                              ? 'NUEVO MENSAJE'
                                              : (esHistorial
                                                    ? 'Ver Chat'
                                                    : 'Chat'),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                      onPressed: () {
                                        // Solo limpiamos la alarma si el pedido está activo
                                        if (!esHistorial) {
                                          Supabase.instance.client
                                              .from('servicios')
                                              .update({'chat_cliente': false})
                                              .eq('id', servicio['id']);
                                        }

                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => ChatScreen(
                                              salaId: 'servicio_${servicio['id']}',
                                              miId: widget.usuario['id'],
                                              miNombre:
                                                  widget.usuario['nombre'],
                                              titulo:
                                                  'Chat con $nombreFinal ${esHistorial ? "(Historial)" : ""}',
                                              servicioId: servicio['id'],
                                              alarmaLocal: 'chat_cliente',
                                              alarmaDestino: 'chat_movil',
                                              tipoFaq: TipoFaqChat.local,
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
                        ],
                      ],
                    ),
                  );
                },
              ),

            // ---> INYECCIÓN: WHATSAPP CLIENTE REUBICADO CON MARGEN UNIFORME <---
            if (telCliente != null && telCliente.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 12),
                child: Text(
                  '📞 Cliente: $telCliente',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              )
            else
              const SizedBox(height: 12),

            // -------------------------------------------------------------------
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  estado == 'cotizacion'
                      ? 'Tarifa: Calculando...'
                      : 'Tarifa: ${fmtPeso(servicio['tarifa'])}',
                  style: TextStyle(
                    color: estado == 'cotizacion'
                        ? Colors.orange[800]
                        : Colors.green,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),

            if (servicio['observacion'] != null) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: Text(
                  '📝 ${servicio['observacion']}',
                  style: TextStyle(color: Colors.grey[800], fontSize: 13),
                ),
              ),
            ],

            if (esHistorial && !esGlobal) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.grey[700],
                    backgroundColor: const Color(0xFF0D0D0D),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  onPressed: onOcultar,
                  icon: const Icon(Icons.archive, size: 18),
                  label: const Text(
                    'OCULTAR DEL TABLERO DE HOY',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
              ),
            ],

            if (esGlobal) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red[800],
                    side: BorderSide(color: Colors.red[800]!),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  onPressed: onEliminar,
                  icon: const Icon(Icons.delete, size: 18),
                  label: const Text(
                    'ELIMINAR PERMANENTEMENTE',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
              ),
            ],

            if (esHistorial &&
                estado == 'finalizado' &&
                servicio['movil_id'] != null) ...[
              const SizedBox(height: 12),
              if (servicio['calificacion_local'] == null)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber[100],
                      foregroundColor: Colors.amber[900],
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    onPressed: () => _mostrarDialogoCalificacion(servicio),
                    icon: const Icon(Icons.star_rate_rounded),
                    label: const Text(
                      'CALIFICAR MÓVIL',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.amber[50],
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.amber[200]!),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Tu calificación:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: Colors.black87,
                        ),
                      ),
                      Row(
                        children: List.generate(5, (index) {
                          return Icon(
                            index < (servicio['calificacion_local'] as int)
                                ? Icons.star
                                : Icons.star_border,
                            color: Colors.amber,
                            size: 16,
                          );
                        }),
                      ),
                    ],
                  ),
                ),
            ],

            if (!esHistorial) ...[
              // ── BOTÓN GPS — pedir ubicación exacta al cliente vía WhatsApp ──
              if (!['finalizado', 'finalizado_por_demora',
                    'finalizado_con_problema', 'cancelado', 'caducado']
                  .contains(estado)) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.blue[700],
                      side: BorderSide(color: Colors.blue[300]!),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    icon: const Icon(Icons.my_location, size: 16),
                    label: const Text(
                      'PEDIR UBICACIÓN POR WHATSAPP',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 11),
                    ),
                    onPressed: () async {
                      final link =
                          'https://oukiofdtargjrclualgm.supabase.co'
                          '/functions/v1/capturar-ubicacion?id=${servicio['id']}';
                      final mensaje = Uri.encodeComponent(
                        'Hola 👋 Para que el conductor llegue exactamente '
                        'donde estás, por favor toca este enlace y activa '
                        'tu GPS (solo tarda un segundo):\n$link',
                      );
                      final uri = Uri.parse('https://wa.me/?text=$mensaje');
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri,
                            mode: LaunchMode.externalApplication);
                      }
                    },
                  ),
                ),
              ],
              // ── FIN BOTÓN GPS ────────────────────────────────────────────────
              if (estado == 'pendiente' || estado == 'cotizacion') ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                    ),
                    onPressed: () => _cancelarPedido(servicio['id']),
                    child: Text(
                      estado == 'cotizacion'
                          ? 'DESCARTAR COTIZACIÓN'
                          : 'CANCELAR SERVICIO',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ] else if (estado == 'cotizada') ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: Colors.red),
                        ),
                        onPressed: () => _cancelarPedido(servicio['id']),
                        child: const Text(
                          'RECHAZAR',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue[800],
                        ),
                        onPressed: () => _completarDatosYAprobar(context, servicio),
                        child: Text(
                          'APROBAR',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ] else if (estado == 'cotizacion_aprobada') ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.teal[50],
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.teal[300]!),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, size: 14, color: Colors.teal[700]),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Precio aprobado: ${fmtPeso(servicio['tarifa'])}. Cuando el pedido esté listo, solicita el móvil.',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.teal[900],
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: Colors.red),
                        ),
                        onPressed: () => _cancelarPedido(servicio['id']),
                        child: const Text(
                          'CANCELAR',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal[700],
                        ),
                        icon: Icon(Icons.motorcycle, color: Colors.white, size: 18),
                        onPressed: () => _solicitarMovilAprobado(context, servicio),
                        label: Text(
                          'SOLICITAR MÓVIL',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],        // body Column.children
            ],          // extra nesting from original
          ],            // body Column.children list
        ),              // body Column
      ),                // if (estaExpandida) Padding
      ],                // outer Card.Column.children
    ),                  // outer Card.Column
  ),                    // Card
);                      // AnimatedSize + return
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
        await prefs.remove('sesion_usuario_json'); // evita auto-login con cuenta eliminada
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

  // --- MÓDULO: COMPLETAR DATOS AL APROBAR COTIZACIÓN (MULTI-PARADERO + TEMPORIZADOR) ---
  void _completarDatosYAprobar(
    BuildContext contextoPrincipal,
    Map<String, dynamic> servicio,
  ) {
    final telefonoCtrl = TextEditingController(
      text: servicio['telefono_receptor']?.toString() ?? '',
    );
    final ticketCtrl = TextEditingController(
      text: servicio['ticket_factura']?.toString() ?? '',
    );
    final notasCtrl = TextEditingController();
    bool procesando = false;

    showDialog(
      context: contextoPrincipal,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          title: const Text(
            '📝 APROBAR COTIZACIÓN',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cotización aprobada por: ${fmtPeso(servicio['tarifa'])}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Completa los datos finales para enviarlo al radar:',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
                const SizedBox(height: 16),

                TextField(
                  controller: ticketCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Ticket / Factura # (Opcional)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.receipt_long, size: 18),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),

                TextField(
                  controller: telefonoCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'WhatsApp de Contacto (*)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.phone, size: 18),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),

                TextField(
                  controller: notasCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Notas finales de entrega / Pedido',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.notes, size: 18),
                    isDense: true,
                  ),
                ),
              ],
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
                      if (telefonoCtrl.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('El WhatsApp es obligatorio.'),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }

                      setDialogState(() => procesando = true);

                      String obsAnterior = servicio['observacion'] ?? '';
                      String ticketStr = ticketCtrl.text.trim().isNotEmpty
                          ? '[ TICKET: #${ticketCtrl.text.trim()} ] '
                          : '';
                      String notasNuevas = notasCtrl.text.trim().isNotEmpty
                          ? '\n📝 NOTAS EXTRA: ${notasCtrl.text.trim()}'
                          : '';
                      String nuevaObs = '$ticketStr$obsAnterior$notasNuevas';

                      try {
                        // Solo guardamos los datos y marcamos como aprobada.
                        // El scan de paraderos y las notificaciones se hacen
                        // cuando el local pulse "SOLICITAR MÓVIL".
                        await Supabase.instance.client
                            .from('servicios')
                            .update({
                              'estado': 'cotizacion_aprobada',
                              'observacion': nuevaObs,
                              'telefono_receptor': telefonoCtrl.text.trim(),
                              'ticket_factura': ticketCtrl.text.trim().isEmpty
                                  ? null
                                  : ticketCtrl.text.trim(),
                            })
                            .eq('id', servicio['id']);

                        if (context.mounted) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(contextoPrincipal).showSnackBar(
                            const SnackBar(
                              content: Text(
                                '✅ Cotización aprobada. Pulsa "SOLICITAR MÓVIL" cuando el pedido esté listo.',
                              ),
                              backgroundColor: Colors.teal,
                              duration: Duration(seconds: 4),
                            ),
                          );
                        }
                      } catch (e) {
                        setDialogState(() => procesando = false);
                        if (context.mounted)
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Error: $e'),
                              backgroundColor: Colors.red,
                            ),
                          );
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
                      'APROBAR',
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

  // --- MÓDULO: SOLICITAR MÓVIL DESPUÉS DE APROBAR COTIZACIÓN ---
  Future<void> _solicitarMovilAprobado(
    BuildContext contextoPrincipal,
    Map<String, dynamic> servicio,
  ) async {
    // Busca móviles que ya tienen servicios ACTIVOS de este local.
    // Si hay alguno, ofrece ENRUTAR directamente antes de ir al radar.
    List<Map<String, dynamic>> movilesActivos = [];
    try {
      final serviciosActivos = await Supabase.instance.client
          .from('servicios')
          .select('movil_id')
          .eq('local_id', widget.usuario['id'])
          .inFilter('estado', ['en_ruta_origen', 'en_origen', 'en_ruta_destino'])
          .not('movil_id', 'is', null);

      final Set<String> movilIds = serviciosActivos
          .map((s) => s['movil_id'].toString())
          .toSet();

      if (movilIds.isNotEmpty) {
        final perfiles = await Supabase.instance.client
            .from('usuarios')
            .select('id, usuario, nombre, rango_movil')
            .inFilter('id', movilIds.toList());
        movilesActivos = List<Map<String, dynamic>>.from(perfiles);
      }
    } catch (_) {}

    if (!contextoPrincipal.mounted) return;

    showDialog(
      context: contextoPrincipal,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text(
          '🏍️ SOLICITAR MÓVIL',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.teal),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Orden #${servicio['id']} → ${servicio['destino']} · ${fmtPeso(servicio['tarifa'])}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            // Si hay móviles activos, muestra opciones de ENRUTAR primero
            if (movilesActivos.isNotEmpty) ...[
              const Divider(),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  'Ya tienes móvil(es) en camino. ¿Enrutar con uno de ellos?',
                  style: TextStyle(fontSize: 12, color: Colors.blue[700]),
                ),
              ),
              ...movilesActivos.map((moto) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.blue[700],
                      side: BorderSide(color: Colors.blue[300]!),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    onPressed: () async {
                      Navigator.pop(ctx);
                      // Envía el servicio DIRECTAMENTE al móvil seleccionado
                      // (no al radar general) — como exclusivo_id para que
                      // solo él lo vea, con notificación inmediata solo a él.
                      await _enviarAprobadaAlMovilExclusivo(
                        contextoPrincipal, servicio, moto);
                    },
                    icon: const Icon(Icons.alt_route, size: 16),
                    label: Text(
                      'ENRUTAR a ${(moto['usuario'] ?? moto['nombre'] ?? '').toString().toUpperCase()}',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              )),
              const Divider(),
            ],
            const Text(
              '¿El pedido ya está listo para enviarlo al radar?',
              style: TextStyle(fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('AÚN NO', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal[700]),
            onPressed: () async {
              Navigator.pop(ctx);
              await _enviarAprobadaAlRadar(contextoPrincipal, servicio);
            },
            child: Text(
              'ENVIAR AL RADAR',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  // --- MÓDULO: ENRUTAR COTIZACIÓN APROBADA DIRECTAMENTE A UN MÓVIL ---
  // Envía el servicio cotizacion_aprobada directamente a un móvil específico
  // como exclusivo_id, sin pasar por el radar general. Solo ese móvil
  // recibe la notificación inmediata.
  Future<void> _enviarAprobadaAlMovilExclusivo(
    BuildContext contextoPrincipal,
    Map<String, dynamic> servicio,
    Map<String, dynamic> moto,
  ) async {
    final movilUsuario = (moto['usuario'] ?? moto['nombre'] ?? '').toString().toUpperCase();
    final String movilId = moto['id'].toString();

    try {
      await Supabase.instance.client
          .from('servicios')
          .update({
            'estado': 'pendiente',
            'exclusivo_id': movilId,
          })
          .eq('id', servicio['id']);

      // Notificación inmediata solo al móvil elegido
      const String mensajeNotif = 'Tienes un servicio asignado directamente';
      await _dispararMisilInmediato(
        externalIds: [movilId],
        titulo: '🔗 SERVICIO ENRUTADO A TI',
        mensaje: mensajeNotif,
      );

      if (contextoPrincipal.mounted) {
        ScaffoldMessenger.of(contextoPrincipal).showSnackBar(
          SnackBar(
            content: Text('✅ Orden #${servicio['id']} enviada directamente a $movilUsuario.'),
            backgroundColor: Colors.blue[700],
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (contextoPrincipal.mounted) {
        ScaffoldMessenger.of(contextoPrincipal).showSnackBar(
          SnackBar(
            content: Text('Error al enrutar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _enviarAprobadaAlRadar(
    BuildContext contextoPrincipal,
    Map<String, dynamic> servicio,
  ) async {
    try {
      int retardoProgramado = 0;
      if (servicio['liberacion_at'] != null) {
        final lib = DateTime.parse(servicio['liberacion_at']).toLocal();
        final ahora = DateTime.now();
        if (lib.isAfter(ahora)) {
          retardoProgramado = lib.difference(ahora).inMinutes;
        }
      }

      String destinoNuevo = servicio['destino'] ?? '';
      bool esPuntoAPunto = servicio['es_punto_a_punto'] == true;
      int nuevoServicioId = servicio['id'];
      String nuevoEstado = retardoProgramado > 0 ? 'programado' : 'pendiente';

      String? exclusivoIdCampo;
      List<String> pilotosSeleccionadosIds = [];

      if (!esPuntoAPunto) {
        final serviciosPendientes = await Supabase.instance.client
            .from('servicios')
            .select('exclusivo_id')
            .eq('estado', 'pendiente')
            .not('exclusivo_id', 'is', null);
        List<String> ocupados = [];
        for (var s in serviciosPendientes) {
          ocupados.addAll(
            s['exclusivo_id'].toString().split(',').map((e) => e.trim()),
          );
        }

        final movilesLibres = await Supabase.instance.client
            .from('usuarios')
            .select('id, paradero_actual, ingreso_fila')
            .eq('rol', 'movil')
            .eq('en_linea', true)
            .not('paradero_actual', 'is', null);

        Map<String, List<Map<String, dynamic>>> gruposParaderos = {};
        for (var m in movilesLibres) {
          String pName = m['paradero_actual'].toString().trim().toLowerCase();
          gruposParaderos.putIfAbsent(pName, () => []).add(m);
        }

        Map<String, String> numeroUnosPorParadero = {};
        gruposParaderos.forEach((pName, listaFila) {
          listaFila.sort(
            (a, b) => DateTime.parse(
              a['ingreso_fila'] ?? DateTime.now().toIso8601String(),
            ).compareTo(
              DateTime.parse(b['ingreso_fila'] ?? DateTime.now().toIso8601String()),
            ),
          );
          for (var candidato in listaFila) {
            String candId = candidato['id'].toString();
            if (!ocupados.contains(candId)) {
              numeroUnosPorParadero[pName] = candId;
              break;
            }
          }
        });

        String paraderosLocalRaw =
            widget.usuario['paradero_exclusivo']?.toString() ?? '';
        List<String> paraderosDelLocal = paraderosLocalRaw
            .split(',')
            .map((e) => e.trim().toLowerCase())
            .where((e) => e.isNotEmpty)
            .toList();

        if (paraderosDelLocal.isEmpty) {
          numeroUnosPorParadero.forEach((pName, driverId) {
            pilotosSeleccionadosIds.add(driverId);
          });
        } else {
          for (var pLocal in paraderosDelLocal) {
            if (numeroUnosPorParadero.containsKey(pLocal)) {
              pilotosSeleccionadosIds.add(numeroUnosPorParadero[pLocal]!);
            }
          }
        }

        if (pilotosSeleccionadosIds.isNotEmpty) {
          exclusivoIdCampo = pilotosSeleccionadosIds.join(',');
        }
      }

      await Supabase.instance.client
          .from('servicios')
          .update({
            'estado': nuevoEstado,
            'exclusivo_id': exclusivoIdCampo,
          })
          .eq('id', nuevoServicioId);

      String mensajeAlarma =
          '📍 ${widget.usuario['nombre']} solicitó un móvil para $destinoNuevo.';
      final mastersData = await Supabase.instance.client
          .from('usuarios')
          .select('id')
          .or('rol.eq.master,rango_movil.eq.MASTER')
          .neq('suspendido', true);
      List<String> masterIds =
          mastersData.map((u) => u['id'].toString()).toList();

      if (masterIds.isNotEmpty) {
        await _dispararMisilInmediato(
          externalIds: masterIds,
          titulo: retardoProgramado > 0 ? '👑 SERVICIO PROGRAMADO' : '👑 NUEVO SERVICIO',
          mensaje: mensajeAlarma,
        );
      }

      if (pilotosSeleccionadosIds.isNotEmpty) {
        List<String> targetPilotos =
            pilotosSeleccionadosIds.where((id) => !masterIds.contains(id)).toList();
        if (targetPilotos.isNotEmpty) {
          // Paradero: misil retardado con ID guardado — cancela si alguien acepta antes
          String? id30s;
          if (retardoProgramado > 0) {
            id30s = await _programarMisilRetardado(
              externalIds: targetPilotos,
              titulo: 'TU TURNO DE PARADERO',
              mensaje: mensajeAlarma,
              minutosRetardo: retardoProgramado,
            );
          } else {
            id30s = await _programarMisilRetardado(
              externalIds: targetPilotos,
              titulo: 'TU TURNO DE PARADERO',
              mensaje: mensajeAlarma,
              segundosRetardo: 30,
            );
          }
          if (id30s != null) {
            await Supabase.instance.client
                .from('servicios')
                .update({'onesignal_30s': id30s})
                .eq('id', nuevoServicioId);
          }
        }
      }

      // T=+60s (zonal 1km) y T=+90s (todos) — nuevas olas del embudo de 2 min
      if (!esPuntoAPunto) {
        final int _svcId3 = nuevoServicioId;
        final String _msg3 = mensajeAlarma;
        final List<String> _mSnap3 = List<String>.from(masterIds);
        final List<String> _pSnap3 = List<String>.from(pilotosSeleccionadosIds);

        if (retardoProgramado > 0) {
          // Misiles programados para servicios con retardo
          List<String> zona1kmIds = [];
          List<String> todosIds = [];
          final movilesActivos = await Supabase.instance.client
              .from('usuarios').select('id, latitud, longitud')
              .eq('rol', 'movil').eq('en_linea', true);
          for (var m in movilesActivos) {
            final idStr = m['id'].toString();
            todosIds.add(idStr);
            double dist = 999999;
            if (m['latitud'] != null && m['longitud'] != null &&
                servicio['origen_lat'] != null && servicio['origen_lng'] != null) {
              dist = const Distance().as(
                LengthUnit.Meter,
                LatLng((m['latitud'] as num).toDouble(), (m['longitud'] as num).toDouble()),
                LatLng((servicio['origen_lat'] as num).toDouble(), (servicio['origen_lng'] as num).toDouble()),
              );
            }
            if (dist <= 1000) zona1kmIds.add(idStr);
          }
          String? id1m;
          String? id2m;
          if (zona1kmIds.isNotEmpty)
            id1m = await _programarMisilRetardado(
              externalIds: zona1kmIds,
              titulo: '📡 SERVICIO CERCA',
              mensaje: 'Servicio a menos de 1km — revisa el radar.',
              minutosRetardo: retardoProgramado + 1,
            );
          if (todosIds.isNotEmpty)
            id2m = await _programarMisilRetardado(
              externalIds: todosIds,
              titulo: '🚨 SERVICIO SIN TOMAR',
              mensaje: '¡Revisa el Radar!',
              minutosRetardo: retardoProgramado + 2,
            );
          if (id1m != null || id2m != null) {
            await Supabase.instance.client.from('servicios').update({
              if (id1m != null) 'onesignal_2m': id1m,
              if (id2m != null) 'onesignal_5m': id2m,
            }).eq('id', _svcId3);
          }
        } else {
          // Servicio inmediato: T=+60s (1km) y T=+90s via Future.delayed
          final double? _oLat3 = (servicio['origen_lat'] as num?)?.toDouble();
          final double? _oLng3 = (servicio['origen_lng'] as num?)?.toDouble();
          Future.delayed(const Duration(seconds: 60), () async {
            final chk = await Supabase.instance.client
                .from('servicios').select('estado').eq('id', _svcId3).maybeSingle();
            if (chk == null || chk['estado'] != 'pendiente') return;
            final candidatos = await Supabase.instance.client
                .from('usuarios').select('id, latitud, longitud')
                .eq('rol', 'movil').eq('en_linea', true).neq('suspendido', true)
                .not('rango_movil', 'in', '("MASTER")');
            final idsZ = (candidatos as List).where((u) {
              final id = u['id'].toString();
              if (_mSnap3.contains(id) || _pSnap3.contains(id)) return false;
              if (_oLat3 == null || _oLng3 == null) return true;
              final uLat = (u['latitud'] as num?)?.toDouble();
              final uLng = (u['longitud'] as num?)?.toDouble();
              if (uLat == null || uLng == null) return false;
              return const Distance().as(
                    LengthUnit.Meter,
                    LatLng(uLat, uLng),
                    LatLng(_oLat3, _oLng3),
                  ) <= 1000;
            }).map((u) => u['id'].toString()).toList();
            if (idsZ.isNotEmpty)
              await _dispararMisilInmediato(
                  externalIds: idsZ, titulo: '📡 SERVICIO CERCA (1km)', mensaje: _msg3);
          });
          Future.delayed(const Duration(seconds: 90), () async {
            final chk = await Supabase.instance.client
                .from('servicios').select('estado').eq('id', _svcId3).maybeSingle();
            if (chk == null || chk['estado'] != 'pendiente') return;
            final todos = await Supabase.instance.client
                .from('usuarios').select('id')
                .eq('rol', 'movil').eq('en_linea', true).neq('suspendido', true);
            final idsT = (todos as List)
                .map((u) => u['id'].toString())
                .where((id) => !_mSnap3.contains(id))
                .toList();
            if (idsT.isNotEmpty)
              await _dispararMisilInmediato(
                  externalIds: idsT, titulo: '🚨 SERVICIO SIN TOMAR', mensaje: _msg3);
          });
        }
      }

      if (contextoPrincipal.mounted) {
        ScaffoldMessenger.of(contextoPrincipal).showSnackBar(
          const SnackBar(
            content: Text('✅ Móvil solicitado con éxito. Orden en el radar.'),
            backgroundColor: Colors.green,
          ),
        );
      }

      // --- DIÁLOGO RÁPIDO PARA GUARDAR EN LA LISTA DE PRECIOS ---
      if (contextoPrincipal.mounted) {
        final resLista = await Supabase.instance.client
            .from('tarifas_locales')
            .select('sector_id, sectores(nombre, municipio), tarifa')
            .eq('local_id', widget.usuario['id']);

        String destinoMayus = destinoNuevo.toUpperCase();
        String barrioExtraido = destinoMayus.contains('-')
            ? destinoMayus.split('-')[0].trim()
            : destinoMayus;
        final tarifaCobrada = (servicio['tarifa'] as num).toDouble();

        bool yaEstaGuardado = resLista.any((item) {
          final s = item['sectores'] as Map<String, dynamic>?;
          if (s == null) return false;
          final clave = '${s['nombre']} (${s['municipio']})'.toUpperCase();
          return barrioExtraido == clave ||
              (destinoMayus.startsWith(clave) &&
                  (item['tarifa'] as num).toDouble() == tarifaCobrada);
        });

        if (!yaEstaGuardado) {
          final barrioCtrl = TextEditingController(text: barrioExtraido);
          String zonaSeleccionada = 'CÚCUTA';
          bool guardandoLista = false;

          showDialog(
            context: contextoPrincipal,
            builder: (ctxSave) => StatefulBuilder(
              builder: (ctxSave, setSaveState) => AlertDialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                title: const Text(
                  '💾 GUARDAR EN LISTA',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Se cobró ${fmtPeso(servicio['tarifa'])}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: barrioCtrl,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        labelText: 'Barrio / Lugar (Ej: PRADOS)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '¿A qué municipio pertenece?',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    Wrap(
                      spacing: 6,
                      runSpacing: 0,
                      children: ['CÚCUTA', 'LOS PATIOS', 'V. ROSARIO']
                          .map((z) => ChoiceChip(
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
                                  if (selected)
                                    setSaveState(() => zonaSeleccionada = z);
                                },
                              ))
                          .toList(),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctxSave),
                    child: const Text('NO GUARDAR', style: TextStyle(color: Colors.grey)),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.black),
                    onPressed: guardandoLista
                        ? null
                        : () async {
                            if (barrioCtrl.text.trim().isEmpty) return;
                            setSaveState(() => guardandoLista = true);
                            try {
                              final sectorId = await _buscarOCrearSector(
                                barrioCtrl.text.trim().toUpperCase(),
                                zonaSeleccionada,
                              );
                              await Supabase.instance.client
                                  .from('tarifas_locales')
                                  .upsert(
                                    {
                                      'local_id': widget.usuario['id'],
                                      'local_nombre': widget.usuario['nombre'],
                                      'sector_id': sectorId,
                                      'tarifa': tarifaCobrada,
                                    },
                                    onConflict: 'local_id, sector_id',
                                  );
                              if (ctxSave.mounted) {
                                Navigator.pop(ctxSave);
                                ScaffoldMessenger.of(contextoPrincipal).showSnackBar(
                                  const SnackBar(
                                    content: Text('✅ Dirección guardada en tu Tarifario.'),
                                    backgroundColor: Colors.green,
                                  ),
                                );
                              }
                            } catch (e) {
                              setSaveState(() => guardandoLista = false);
                              if (ctxSave.mounted)
                                ScaffoldMessenger.of(contextoPrincipal).showSnackBar(
                                  SnackBar(
                                    content: Text('Error BD: $e'),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                            }
                          },
                    child: guardandoLista
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              color: Color(0xff3AF500),
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            'GUARDAR DIRECCIÓN',
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
      if (contextoPrincipal.mounted)
        ScaffoldMessenger.of(contextoPrincipal).showSnackBar(
          SnackBar(
            content: Text('Error al solicitar móvil: $e'),
            backgroundColor: Colors.red,
          ),
        );
    }
  }

  // -----------------------------------------------------------------------
  // HUB HELPERS — usados en la pestaña MI LOCAL
  // -----------------------------------------------------------------------
  Widget _hubCard({
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Widget? secondaryAction,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey[600])),
                    if (secondaryAction != null) ...[
                      const SizedBox(height: 10),
                      secondaryAction,
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right, color: Colors.black26, size: 22),
            ],
          ),
        ),
      ),
    );
  }

  Widget _hubListTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: iconColor, size: 22),
      title: Text(title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
      subtitle: subtitle != null
          ? Text(subtitle,
              style:
                  const TextStyle(fontSize: 10, color: Colors.black54))
          : null,
      trailing: const Icon(Icons.chevron_right, size: 18),
      onTap: onTap,
      dense: true,
    );
  }

  // ---> INYECCIÓN: NÚCLEO DE LA INTERFAZ CON EL PANEL DE PERFIL <---
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _streamPerfilPropio,
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

        return DefaultTabController(
          length: 3, // <--- Mutamos a 3 Pestañas
          child: Scaffold(
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
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
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

                return TabBarView(
                  children: [
                    // --- PESTAÑA 1: ACTIVOS ---
                    Column(
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          color: Colors.white,
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    flex: 6,
                                    child: ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(
                                          0xff3AF500,
                                        ),
                                        foregroundColor: Colors.black,
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 14,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                      ),
                                      onPressed: () => _abrirFormularioPedido(
                                        context,
                                        esCotizacion: false,
                                        perfilEnVivo:
                                            perfilEnVivo, // Pasamos el perfil
                                      ),
                                      icon: const Icon(
                                        Icons.motorcycle,
                                        size: 20,
                                      ),
                                      label: const Text(
                                        'SOLICITAR MÓVIL',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    flex: 4,
                                    child: OutlinedButton.icon(
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: Colors.orange[800],
                                        side: BorderSide(
                                          color: Colors.orange[800]!,
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 14,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                      ),
                                      onPressed: () => _abrirFormularioPedido(
                                        context,
                                        esCotizacion: true,
                                        perfilEnVivo: perfilEnVivo,
                                      ),
                                      icon: const Icon(
                                        Icons.request_quote,
                                        size: 20,
                                      ),
                                      label: const Text(
                                        'COTIZAR',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _puedeUsarPuntoAPunto()
                                        ? Colors.purple[800]
                                        : Colors.grey[300],
                                    foregroundColor: _puedeUsarPuntoAPunto()
                                        ? Colors.white
                                        : Colors.grey[600],
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    elevation: _puedeUsarPuntoAPunto() ? 2 : 0,
                                  ),
                                  onPressed: _puedeUsarPuntoAPunto()
                                      ? () => _abrirFormularioPedido(
                                          context,
                                          esPuntoAPunto: true,
                                          perfilEnVivo: perfilEnVivo,
                                        )
                                      : null,
                                  icon: const Icon(Icons.flash_on, size: 20),
                                  label: Text(
                                    _puedeUsarPuntoAPunto()
                                        ? 'PUNTO A PUNTO (1 GRATIS / DÍA)'
                                        : 'PUNTO A PUNTO AGOTADO POR HOY',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              // ── BOTÓN VIP ─────────────────────────────────────
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xFFB8860B),
                                    side: const BorderSide(color: Color(0xFFB8860B)),
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  onPressed: () => _abrirFormularioPedido(
                                    context,
                                    esVip: true,
                                    perfilEnVivo: perfilEnVivo,
                                  ),
                                  icon: const Text('👑', style: TextStyle(fontSize: 15)),
                                  label: const Text(
                                    'VIP  ·  +\$3.000',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                ),
                              ),
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
                              : ListView.builder(
                                  padding: const EdgeInsets.all(12),
                                  itemCount: activos.length,
                                  itemBuilder: (c, i) => FadeSlideIn(
                                    key: ValueKey('activo_local_${activos[i]['id']}'),
                                    child: _construirTarjetaServicio(activos[i]),
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
                        : ListView.builder(
                            padding: const EdgeInsets.all(12),
                            itemCount: historial.length,
                            itemBuilder: (c, i) => FadeSlideIn(
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
          ),
        );
      },
    );
  }

  // Perfil rápido del moto visto desde el local — nombre, usuario,
  // teléfono y métodos de pago disponibles en un AlertDialog compacto.
  void _verPerfilMovilLocal(BuildContext ctx, Map<String, dynamic> moto) {
    final nombre = moto['nombre']?.toString() ?? '—';
    final usuario = moto['usuario_movil']?.toString() ?? '';
    final tel = moto['telefono']?.toString() ?? '—';
    final foto = moto['foto_url']?.toString();
    showDialog(
      context: ctx,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 32,
              backgroundImage:
                  foto != null && foto.isNotEmpty ? NetworkImage(foto) : null,
              backgroundColor: const Color(0xFF0D0D0D),
              child: foto == null || foto.isEmpty
                  ? const Icon(Icons.person, size: 32, color: Colors.grey)
                  : null,
            ),
            const SizedBox(height: 10),
            Text(nombre,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            if (usuario.isNotEmpty)
              Text(usuario,
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.phone, size: 14, color: Colors.grey),
              const SizedBox(width: 4),
              Text(tel, style: const TextStyle(fontSize: 13)),
            ]),
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 4, children: [
              if (moto['pago_nequi'] != null && moto['pago_nequi'].toString().isNotEmpty)
                _chipPagoLocal('Nequi', const Color(0xFFE5007D), Colors.white, moto['pago_nequi']),
              if (moto['pago_daviplata'] != null && moto['pago_daviplata'].toString().isNotEmpty)
                _chipPagoLocal('Daviplata', const Color(0xFFEE2A24), Colors.white, moto['pago_daviplata']),
              if (moto['pago_bancolombia'] != null && moto['pago_bancolombia'].toString().isNotEmpty)
                _chipPagoLocal('Bancolombia', const Color(0xFFFFCC00), Colors.black, moto['pago_bancolombia']),
            ]),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('CERRAR')),
        ],
      ),
    );
  }

  // Chip de cuenta de pago — nombre fijo de la app + número, usado
  // inline en la tarjeta de servicio (info obligatoria, no opcional).
  // Tocarlo copia el número al portapapeles, listo para pegar en la
  // app de pago correspondiente.
  Widget _chipPagoLocal(
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
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              app,
              style: TextStyle(
                color: colorTexto,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              numero.toString(),
              style: TextStyle(
                color: colorTexto,
                fontSize: 10,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.copy, size: 10, color: colorTexto.withAlpha(180)),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // ENRUTAR ENCARGO AL MÓVIL ACTIVO
  // Abre un diálogo para crear un nuevo servicio asignado
  // directamente al mismo móvil que ya está haciendo una entrega.
  // ─────────────────────────────────────────────────────────────
  void _abrirEnrutarAlMoto(
    BuildContext context,
    Map<String, dynamic> servicio,
    Map<String, dynamic> moto,
  ) {
    final destinoCtrl = TextEditingController();
    final telefonoCtrl = TextEditingController();
    final movilNombre = (moto['usuario'] ?? moto['nombre'] ?? '').toString().toUpperCase();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(children: [
          const Icon(Icons.alt_route, color: Colors.blue),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              'ENRUTAR A $movilNombre',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.blue),
            ),
          ),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Crea un nuevo encargo para $movilNombre sin esperar a que termine el actual.',
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: destinoCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Destino del nuevo encargo',
                border: OutlineInputBorder(),
                isDense: true,
                prefixIcon: Icon(Icons.flag_outlined),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: telefonoCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Teléfono receptor (opcional)',
                border: OutlineInputBorder(),
                isDense: true,
                prefixIcon: Icon(Icons.phone_outlined),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CANCELAR', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue[700],
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.send, size: 16),
            label: const Text('ENVIAR', style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: () async {
              final destino = destinoCtrl.text.trim();
              if (destino.isEmpty) return;
              Navigator.pop(ctx);
              try {
                await Supabase.instance.client.from('servicios').insert({
                  'local_id': widget.usuario['id'],
                  'creador': widget.usuario['nombre'],
                  'origen': (widget.usuario['nombre'] ?? '').toString().toUpperCase(),
                  'destino': destino.toUpperCase(),
                  'tarifa': 0.0,
                  'tarifa_detalle': {'total': 0.0, 'base': 0.0, 'fuente': 'local_enrutado'},
                  'observacion': '[ ENRUTADO ] ↪ Encargo adicional para $movilNombre',
                  'estado': 'pendiente',
                  'tipo_servicio': 'PAQUETERÍA',
                  'exclusivo_id': moto['id'].toString(),
                  'ruta_grupo_id': servicio['id'],
                  if (telefonoCtrl.text.trim().isNotEmpty)
                    'telefono_receptor': telefonoCtrl.text.trim(),
                });
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('✅ Encargo enrutado a $movilNombre.'),
                      backgroundColor: Colors.blue[700],
                      duration: const Duration(seconds: 3),
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error al enrutar: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
          ),
        ],
      ),
    );
  }
}
