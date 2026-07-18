// ignore_for_file: use_build_context_synchronously
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:serviexpress_app/utils/sonido_manager.dart';
import 'package:serviexpress_app/utils/onesignal_api.dart';
import 'package:serviexpress_app/screens/login_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Panel sede FN — rol: sede_fn
// Tabs: Crear servicio | Activos | Historial
// ─────────────────────────────────────────────────────────────────────────────

class SedeFnScreen extends StatefulWidget {
  final Map<String, dynamic> usuario;
  const SedeFnScreen({super.key, required this.usuario});

  @override
  State<SedeFnScreen> createState() => _SedeFnScreenState();
}

class _SedeFnScreenState extends State<SedeFnScreen>
    with SingleTickerProviderStateMixin {
  final _db = Supabase.instance.client;
  final _sonidos = SonidoManager();
  late final TabController _tab;

  // Datos de la sede vinculada a este usuario
  Map<String, dynamic>? _sede;
  bool _altaDemanda = false;

  // Stream antiparpadeo de servicios activos
  final _ctrlServicios =
      StreamController<List<Map<String, dynamic>>>.broadcast();
  StreamSubscription? _subServicios;
  RealtimeChannel? _canalEstados;
  RealtimeChannel? _canalConfig;
  Timer? _reconTimer;

  List<Map<String, dynamic>>? _cacheServicios;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    OneSignal.login(widget.usuario['id'].toString());
    OneSignal.User.addTagWithKey('rol', 'sede_fn');
    _cargarSede();
    _cargarAltaDemanda();
    _construirStream();
    _iniciarCanalRealtime();
    _iniciarReconexion();
  }

  @override
  void dispose() {
    _tab.dispose();
    _subServicios?.cancel();
    _canalEstados?.unsubscribe();
    _canalConfig?.unsubscribe();
    _reconTimer?.cancel();
    _ctrlServicios.close();
    super.dispose();
  }

  // ── Carga la sede vinculada al usuario ─────────────────────────────────────
  Future<void> _cargarSede() async {
    final sedeId = widget.usuario['fn_sede_id'];
    if (sedeId == null) return;
    try {
      final data = await _db
          .from('fn_sedes')
          .select()
          .eq('id', sedeId)
          .maybeSingle();
      if (mounted) setState(() => _sede = data);
    } catch (_) {}
  }

  Future<void> _cargarAltaDemanda() async {
    try {
      final row = await _db
          .from('config_sistema')
          .select('alta_demanda_fn')
          .eq('id', 1)
          .maybeSingle();
      if (mounted) {
        setState(() => _altaDemanda = row?['alta_demanda_fn'] == true);
      }
    } catch (_) {}
  }

  // ── Stream antiparpadeo de servicios de esta sede ──────────────────────────
  void _construirStream() {
    _subServicios?.cancel();
    final sedeId = widget.usuario['fn_sede_id'];
    if (sedeId == null) return;

    final crudo = _db
        .from('servicios')
        .stream(primaryKey: ['id'])
        .eq('fn_sede_solicitante_id', sedeId)
        .order('id', ascending: false);

    _subServicios = crudo.listen(
      (data) {
        _cacheServicios = data;
        if (!_ctrlServicios.isClosed) _ctrlServicios.add(data);
      },
      onError: (_) {},
    );
  }

  void _iniciarCanalRealtime() {
    final sedeId = widget.usuario['fn_sede_id'];
    if (sedeId == null) return;

    // Escucha cambios de estado en sus servicios → sonido si central cotizó
    _canalEstados = _db
        .channel('sede_fn_estados_${widget.usuario['id']}')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'servicios',
          callback: (payload) {
            final nuevo = payload.newRecord;
            final viejo = payload.oldRecord;
            if (!mounted) return;
            final estadoNuevo = nuevo['estado']?.toString() ?? '';
            final estadoViejo = viejo['estado']?.toString() ?? '';
            if (nuevo['fn_sede_solicitante_id']?.toString() != sedeId.toString()) return;
            if (estadoNuevo == estadoViejo) return;
            // Central respondió cotización → sonido especial FN
            if (estadoViejo == 'cotizacion' && estadoNuevo == 'cotizada') {
              _sonidos.reproducir(Sonidos.fnCotizacion);
            } else if (estadoNuevo == 'fn_rechazado') {
              _sonidos.reproducirSuave(Sonidos.localEstado);
            } else {
              _sonidos.reproducirSuave(Sonidos.localEstado);
            }
          },
        )
        .subscribe();

    // Escucha cambios del toggle alta demanda
    _canalConfig = _db
        .channel('sede_fn_config_${widget.usuario['id']}')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'config_sistema',
          callback: (payload) {
            if (!mounted) return;
            final nuevo = payload.newRecord;
            setState(() => _altaDemanda = nuevo['alta_demanda_fn'] == true);
          },
        )
        .subscribe();
  }

  void _iniciarReconexion() {
    _reconTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _construirStream();
    });
  }

  // ── Código de sede para UI ──────────────────────────────────────────────────
  String get _codigoSede {
    if (_sede == null) return '';
    final tipo = _sede!['tipo']?.toString() ?? '';
    final num = _sede!['numero']?.toString() ?? '';
    return tipo == 'FN' && num.isNotEmpty ? 'FN$num' : (_sede!['nombre'] ?? '');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A237E),
        iconTheme: const IconThemeData(color: Colors.white),
        title: Row(
          children: [
            const Icon(Icons.local_pharmacy, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text(
              _codigoSede.isNotEmpty ? _codigoSede : 'Farmanorte',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white70),
            tooltip: 'Cerrar sesión',
            onPressed: () async {
              final confirmar = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: const Color(0xFF1A1A1A),
                  title: const Text('¿Cerrar sesión?',
                      style: TextStyle(color: Colors.white, fontSize: 16)),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancelar',
                          style: TextStyle(color: Colors.white54)),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Cerrar sesión',
                          style: TextStyle(color: Colors.redAccent)),
                    ),
                  ],
                ),
              );
              if (confirmar == true && mounted) {
                final prefs = await SharedPreferences.getInstance();
                await prefs.remove('sesion_usuario_json');
                await prefs.setBool('auto_login', false);
                if (mounted) {
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                    (_) => false,
                  );
                }
              }
            },
          ),
        ],
        bottom: TabBar(
          controller: _tab,
          indicatorColor: Colors.indigo[200],
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white54,
          tabs: const [
            Tab(icon: Icon(Icons.add_box), text: 'Nuevo'),
            Tab(icon: Icon(Icons.two_wheeler), text: 'Activos'),
            Tab(icon: Icon(Icons.history), text: 'Historial'),
          ],
        ),
      ),
      body: Column(
        children: [
          // Banner alta demanda
          if (_altaDemanda)
            Container(
              width: double.infinity,
              color: Colors.orange[900],
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.white, size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '⚠ Alta demanda: habrá demora en asignar y realizar los servicios',
                      style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [
                _FormularioTab(
                  usuario: widget.usuario,
                  sede: _sede,
                  altaDemanda: _altaDemanda,
                  onServicioCreado: () => _tab.animateTo(1),
                ),
                _ActivosTab(
                  usuario: widget.usuario,
                  sede: _sede,
                  stream: _ctrlServicios.stream,
                  cache: _cacheServicios,
                ),
                _HistorialTab(
                  usuario: widget.usuario,
                  sede: _sede,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TAB 1 — FORMULARIO NUEVO SERVICIO
// ═══════════════════════════════════════════════════════════════════════════════

class _FormularioTab extends StatefulWidget {
  final Map<String, dynamic> usuario;
  final Map<String, dynamic>? sede;
  final bool altaDemanda;
  final VoidCallback onServicioCreado;

  const _FormularioTab({
    required this.usuario,
    required this.sede,
    required this.altaDemanda,
    required this.onServicioCreado,
  });

  @override
  State<_FormularioTab> createState() => _FormularioTabState();
}

class _FormularioTabState extends State<_FormularioTab> {
  final _db = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();

  // Recogidas seleccionadas: lista de fn_sedes (pueden ser null si pendiente)
  final List<Map<String, dynamic>?> _recogidasSel = [null];
  // Modo por recogida: false=sede oficial, true=dirección libre
  final List<bool> _recogidasEsManual = [false];
  // Controladores para entradas manuales
  final List<TextEditingController> _recogidasNombreCtrl = [TextEditingController()];
  final List<TextEditingController> _recogidasDireccionCtrl = [TextEditingController()];
  final List<TextEditingController> _recogidasGpsCtrl = [TextEditingController()];

  // Destino
  final _destinoCtrl = TextEditingController();

  // Factura
  final _facturaNumCtrl = TextEditingController();

  // Instrucciones
  final _instruccionesCtrl = TextEditingController();

  bool _conDatafono = false;
  bool _enviando = false;

  // Sedes disponibles para seleccionar como recogida
  List<Map<String, dynamic>> _sedesDisponibles = [];
  bool _cargandoSedes = true;

  @override
  void initState() {
    super.initState();
    _cargarSedes();
  }

  @override
  void dispose() {
    _destinoCtrl.dispose();
    _facturaNumCtrl.dispose();
    _instruccionesCtrl.dispose();
    for (final c in _recogidasNombreCtrl) c.dispose();
    for (final c in _recogidasDireccionCtrl) c.dispose();
    for (final c in _recogidasGpsCtrl) c.dispose();
    super.dispose();
  }

  Future<void> _cargarSedes() async {
    try {
      final data = await _db
          .from('fn_sedes')
          .select('id, tipo, numero, nombre, zona, lat, lng, cobertura, activo')
          .eq('activo', true);
      final lista = List<Map<String, dynamic>>.from(data);
      lista.sort((a, b) {
        final na = int.tryParse(a['numero']?.toString() ?? '') ?? 999;
        final nb = int.tryParse(b['numero']?.toString() ?? '') ?? 999;
        return na.compareTo(nb);
      });
      setState(() {
        _sedesDisponibles = lista;
        _cargandoSedes = false;
      });
    } catch (_) {
      setState(() => _cargandoSedes = false);
    }
  }

  String _labelSede(Map<String, dynamic> s) {
    final tipo = s['tipo']?.toString() ?? '';
    final num = s['numero']?.toString() ?? '';
    final nombre = s['nombre']?.toString() ?? '';
    return tipo == 'FN' && num.isNotEmpty ? 'FN$num — $nombre' : nombre;
  }

  bool _tieneRecogidaFueraDe() {
    for (int i = 0; i < _recogidasSel.length; i++) {
      // Manual con contenido = por evaluar
      if (_recogidasEsManual[i] &&
          _recogidasNombreCtrl[i].text.trim().isNotEmpty) return true;
      final r = _recogidasSel[i];
      if (r != null && r['cobertura'] == 'fuera') return true;
      if (r != null && r['cobertura'] == 'por_evaluar') return true;
    }
    return false;
  }

  Future<void> _enviar() async {
    if (!_formKey.currentState!.validate()) return;

    final sedeId = widget.usuario['fn_sede_id'];
    if (sedeId == null) {
      _snack('Tu cuenta no tiene una sede vinculada. Contacta a la central.');
      return;
    }

    setState(() => _enviando = true);
    try {
      // Construir lista de recogidas para el JSONB
      final recogidasList = <Map<String, dynamic>>[];
      for (int i = 0; i < _recogidasSel.length; i++) {
        if (_recogidasEsManual[i]) {
          final nombre = _recogidasNombreCtrl[i].text.trim();
          if (nombre.isNotEmpty) {
            recogidasList.add({
              'es_manual': true,
              'nombre': nombre,
              'direccion': _recogidasDireccionCtrl[i].text.trim(),
              'gps_link': _recogidasGpsCtrl[i].text.trim(),
              'cobertura': 'por_evaluar',
            });
          }
        } else {
          final s = _recogidasSel[i];
          if (s != null) {
            recogidasList.add({
              'id': s['id'],
              'tipo': s['tipo'],
              'nombre': s['nombre'],
              'numero': s['numero'],
              'zona': s['zona'],
              'lat': s['lat'],
              'lng': s['lng'],
              'cobertura': s['cobertura'] ?? 'dentro',
            });
          }
        }
      }
      // Sin recogidas explícitas → la sede solicitante es el punto de recogida
      if (recogidasList.isEmpty) {
        final sedeData = widget.sede;
        if (sedeData != null) {
          recogidasList.add({
            'id': sedeData['id'],
            'tipo': sedeData['tipo'],
            'nombre': sedeData['nombre'],
            'numero': sedeData['numero'],
            'zona': sedeData['zona'],
            'lat': sedeData['lat'],
            'lng': sedeData['lng'],
            'cobertura': sedeData['cobertura'] ?? 'dentro',
            'es_sede_solicitante': true,
          });
        }
      }
      final primeraRecogida =
          recogidasList.isNotEmpty ? recogidasList.first : <String, dynamic>{};

      // Generar consecutivo
      final consec = await _db
          .rpc('fn_generar_consecutivo', params: {'p_sede_id': sedeId});

      // Nombre de la sede solicitante
      final sedeData = widget.sede;
      final nombreSede = sedeData != null
          ? _labelSede(sedeData)
          : 'Sede FN';

      final altaDemanda = widget.altaDemanda;

      await _db.from('servicios').insert({
        'origen': nombreSede,
        'destino': _destinoCtrl.text.trim().toUpperCase(),
        'estado': 'cotizacion',
        'creador': 'FN-Sede',
        'tipo_servicio': 'FARMANORTE',
        'tipo_fn': true,
        'fn_origen': 'sede',
        'fn_sede_solicitante_id': sedeId,
        'fn_sede_id': primeraRecogida['es_manual'] == true
            ? null
            : (primeraRecogida['id'] ?? sedeId),
        'recogidas': recogidasList,
        'metodo_pago': _conDatafono ? 'Datafono' : 'Efectivo',
        'fn_factura_numero': _facturaNumCtrl.text.trim().isEmpty
            ? null
            : _facturaNumCtrl.text.trim(),
        'fn_alta_demanda': altaDemanda,
        'fn_consecutivo': consec?.toString(),
        'fn_recotizacion': 1,
        'archivado': false,
        if (_instruccionesCtrl.text.trim().isNotEmpty)
          'instrucciones_especiales': _instruccionesCtrl.text.trim(),
        // Coordenadas de la primera sede de recogida como origen (solo si es sede oficial)
        if (primeraRecogida['lat'] != null)
          'origen_lat': (primeraRecogida['lat'] as num).toDouble(),
        if (primeraRecogida['lng'] != null)
          'origen_lng': (primeraRecogida['lng'] as num).toDouble(),
        // WhatsApp de la sede solicitante para que el móvil pueda contactarla
        if (widget.sede?['telefono_whatsapp'] != null &&
            (widget.sede!['telefono_whatsapp'] as String).trim().isNotEmpty)
          'fn_whatsapp': (widget.sede!['telefono_whatsapp'] as String).trim(),
      });

      // Notificar a la central con sonido especial FN
      await MotorNotificaciones.dispararACentral(
        titulo: '🏥 Solicitud FN — ${consec ?? nombreSede}',
        mensaje: _tieneRecogidaFueraDe()
            ? '⚠ Recogida fuera de cobertura · ${_destinoCtrl.text.trim()}'
            : 'Cotizar para ${_destinoCtrl.text.trim()}',
        urgente: true,
        sonido: Sonidos.fnCotizacion,
      );

      if (!mounted) return;
      // Limpiar formulario
      setState(() {
        _recogidasSel..clear()..add(null);
        _recogidasEsManual..clear()..add(false);
        for (final c in _recogidasNombreCtrl) c.dispose();
        _recogidasNombreCtrl..clear()..add(TextEditingController());
        for (final c in _recogidasDireccionCtrl) c.dispose();
        _recogidasDireccionCtrl..clear()..add(TextEditingController());
        for (final c in _recogidasGpsCtrl) c.dispose();
        _recogidasGpsCtrl..clear()..add(TextEditingController());
        _conDatafono = false;
      });
      _destinoCtrl.clear();
      _facturaNumCtrl.clear();
      _instruccionesCtrl.clear();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Solicitud enviada — esperando cotización de la central'),
          backgroundColor: Colors.green,
        ),
      );
      widget.onServicioCreado();
    } catch (e) {
      _snack('Error al enviar: $e');
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return AutofillGroup(
      onDisposeAction: AutofillContextAction.cancel,
      child: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Aviso fuera de cobertura ────────────────────────────────────
            if (_tieneRecogidaFueraDe())
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange[900]!.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange[700]!),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 16),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Una o más recogidas están fuera de cobertura o sin validar. '
                        'La cotización puede tener recargo, demorar más o ser rechazada.',
                        style: TextStyle(color: Colors.orange, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),

            // ── Sección: Recogidas ──────────────────────────────────────────
            _seccionLabel('📦 Recogidas (opcional — si hay otra sede donde recoger)'),
            const SizedBox(height: 8),

            if (_cargandoSedes)
              const Center(child: CircularProgressIndicator(color: Colors.indigo))
            else ...[
              ...List.generate(_recogidasSel.length, (i) {
                final esManual = _recogidasEsManual[i];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Toggle sede / manual ──────────────────────────────
                      Row(
                        children: [
                          _modoChip('Sede FN', !esManual,
                              () => setState(() => _recogidasEsManual[i] = false)),
                          const SizedBox(width: 8),
                          _modoChip('Dirección libre', esManual,
                              () => setState(() => _recogidasEsManual[i] = true)),
                          const Spacer(),
                          if (_recogidasSel.length > 1)
                            IconButton(
                              icon: const Icon(Icons.remove_circle, color: Colors.red, size: 20),
                              onPressed: () => setState(() {
                                _recogidasSel.removeAt(i);
                                _recogidasEsManual.removeAt(i);
                                _recogidasNombreCtrl[i].dispose();
                                _recogidasNombreCtrl.removeAt(i);
                                _recogidasDireccionCtrl[i].dispose();
                                _recogidasDireccionCtrl.removeAt(i);
                                _recogidasGpsCtrl[i].dispose();
                                _recogidasGpsCtrl.removeAt(i);
                              }),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        esManual
                            ? 'Añade una recogida en cualquier otra dirección: una sede FN no registrada o una droguería/farmacia externa'
                            : 'Selecciona una o más sedes de Farmanorte registradas como punto de recogida',
                        style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 11,
                            fontStyle: FontStyle.italic),
                      ),
                      const SizedBox(height: 6),
                      // ── Contenido según modo ──────────────────────────────
                      if (!esManual)
                        DropdownButtonFormField<Map<String, dynamic>>(
                          value: _recogidasSel[i],
                          decoration: _inputDeco('Recogida ${i + 1}'),
                          dropdownColor: const Color(0xFF1E1E1E),
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                          iconEnabledColor: Colors.white54,
                          iconDisabledColor: Colors.white24,
                          isExpanded: true,
                          hint: const Text('Seleccionar sede FN',
                              style: TextStyle(color: Colors.white54, fontSize: 12)),
                          items: _sedesDisponibles.map((s) => DropdownMenuItem(
                            value: s,
                            child: Text(_labelSede(s),
                                style: const TextStyle(color: Colors.white, fontSize: 13)),
                          )).toList(),
                          onChanged: (v) => setState(() => _recogidasSel[i] = v),
                        )
                      else ...[
                        TextFormField(
                          controller: _recogidasNombreCtrl[i],
                          textCapitalization: TextCapitalization.words,
                          style: const TextStyle(color: Colors.white),
                          decoration: _inputDeco('Nombre / referencia del local'),
                          autofillHints: const <String>[],
                        ),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _recogidasDireccionCtrl[i],
                          textCapitalization: TextCapitalization.characters,
                          style: const TextStyle(color: Colors.white),
                          decoration: _inputDeco('Dirección (opcional)'),
                          autofillHints: const <String>[],
                        ),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _recogidasGpsCtrl[i],
                          style: const TextStyle(color: Colors.white),
                          keyboardType: TextInputType.url,
                          decoration: _inputDeco('Link GPS (opcional)',
                              hint: 'https://maps.google.com/...'),
                          autofillHints: const <String>[],
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '⚠ La Central revisará y podrá añadir esta dirección oficialmente.',
                            style: TextStyle(color: Colors.orange[400], fontSize: 10),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              }),
              TextButton.icon(
                onPressed: () => setState(() {
                  _recogidasSel.add(null);
                  _recogidasEsManual.add(false);
                  _recogidasNombreCtrl.add(TextEditingController());
                  _recogidasDireccionCtrl.add(TextEditingController());
                  _recogidasGpsCtrl.add(TextEditingController());
                }),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Agregar recogida', style: TextStyle(fontSize: 13)),
                style: TextButton.styleFrom(foregroundColor: Colors.indigo[300]),
              ),
            ],

            const SizedBox(height: 16),

            // ── Destino ─────────────────────────────────────────────────────
            _seccionLabel('🏁 Destino de entrega'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _destinoCtrl,
              textCapitalization: TextCapitalization.characters,
              style: const TextStyle(color: Colors.white),
              decoration: _inputDeco('Dirección de entrega'),
              autofillHints: const <String>[],
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Requerido' : null,
            ),

            const SizedBox(height: 16),

            // ── Condiciones de pago ─────────────────────────────────────────
            _seccionLabel('💳 Pago'),
            const SizedBox(height: 8),
            _switchTile(
              '¿Va con datáfono?',
              _conDatafono,
              (v) => setState(() => _conDatafono = v),
            ),

            const SizedBox(height: 16),

            // ── Factura ─────────────────────────────────────────────────────
            _seccionLabel('🧾 Datos de la factura (opcional)'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _facturaNumCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: _inputDeco('N° factura'),
              keyboardType: TextInputType.text,
              autofillHints: const <String>[],
            ),

            const SizedBox(height: 16),

            // ── Instrucciones ───────────────────────────────────────────────
            _seccionLabel('📝 Instrucciones adicionales'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _instruccionesCtrl,
              maxLines: 3,
              style: const TextStyle(color: Colors.white),
              decoration: _inputDeco(
                  'Ej: Tocar timbre, dejar con el portero, etc.'),
              autofillHints: const <String>[],
            ),

            const SizedBox(height: 24),

            // ── Botón enviar ────────────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1A237E),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: _enviando ? null : _enviar,
                icon: _enviando
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.send_rounded),
                label: Text(
                  _enviando ? 'Enviando...' : 'SOLICITAR COTIZACIÓN',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    ),   // SingleChildScrollView
    );   // AutofillGroup
  }

  Widget _seccionLabel(String texto) => Text(
        texto,
        style: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5),
      );

  Widget _modoChip(String label, bool activo, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: activo ? Colors.indigo[700] : const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: activo ? Colors.indigo[300]! : Colors.white.withValues(alpha: 0.15),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: activo ? Colors.white : Colors.white38,
              fontSize: 11,
              fontWeight: activo ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      );

  InputDecoration _inputDeco(String label, {String? hint}) => InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(color: Colors.white54, fontSize: 13),
        hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
        filled: true,
        fillColor: const Color(0xFF1A1A1A),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Colors.indigo),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
        ),
        isDense: true,
      );

  Widget _switchTile(String label, bool value, ValueChanged<bool> onChanged) =>
      Container(
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: SwitchListTile(
          dense: true,
          title: Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 13)),
          value: value,
          onChanged: onChanged,
          activeColor: Colors.indigo[300],
        ),
      );
}

// ═══════════════════════════════════════════════════════════════════════════════
// TAB 2 — SERVICIOS ACTIVOS
// ═══════════════════════════════════════════════════════════════════════════════

class _ActivosTab extends StatefulWidget {
  final Map<String, dynamic> usuario;
  final Map<String, dynamic>? sede;
  final Stream<List<Map<String, dynamic>>> stream;
  final List<Map<String, dynamic>>? cache;

  const _ActivosTab({
    required this.usuario,
    required this.sede,
    required this.stream,
    required this.cache,
  });

  @override
  State<_ActivosTab> createState() => _ActivosTabState();
}

class _ActivosTabState extends State<_ActivosTab> {
  final _db = Supabase.instance.client;

  static const _estadosActivos = [
    'cotizacion', 'cotizada', 'pendiente', 'en_ruta_origen',
    'en_origen', 'en_ruta_destino', 'fn_renegociando',
  ];

  List<Map<String, dynamic>> _filtrarActivos(List<Map<String, dynamic>> todos) =>
      todos.where((s) => _estadosActivos.contains(s['estado'])).toList();

  // ── Aprobar cotización + lanzar cascada FN ────────────────────────────────
  Future<void> _aprobar(Map<String, dynamic> s) async {
    try {
      // 1. Móviles FN disponibles en línea
      final movilesRaw = await _db
          .from('usuarios')
          .select('id, rango_movil, latitud, longitud')
          .eq('rol', 'movil')
          .eq('en_linea', true)
          .eq('activo', true)
          .eq('tiene_fn', true)
          .neq('suspendido', true);

      // 2. Contar servicios activos por móvil
      final svActivos = await _db
          .from('servicios')
          .select('movil_id')
          .inFilter('estado', ['en_ruta_origen', 'en_origen', 'en_ruta_destino', 'problema'])
          .not('movil_id', 'is', null);

      final Map<String, int> activos = {};
      for (final sv in svActivos as List) {
        final mid = sv['movil_id'].toString();
        activos[mid] = (activos[mid] ?? 0) + 1;
      }

      int limiteRango(String? r) {
        switch (r?.toUpperCase().trim()) {
          case 'PRO':     return 1;
          case 'ELITE':   return 2;
          case 'LEYENDA': return 3;
          case 'MASTER':  return 999;
          default:        return 1;
        }
      }

      // Solo los que tienen capacidad para más servicios FN
      final moviles = (movilesRaw as List)
          .where((m) => (activos[m['id'].toString()] ?? 0) < limiteRango(m['rango_movil']?.toString()))
          .toList();

      final masters = moviles
          .where((m) => m['rango_movil']?.toString().toUpperCase() == 'MASTER')
          .map<String>((m) => m['id'].toString())
          .toList();
      final noMasters = moviles
          .where((m) => m['rango_movil']?.toString().toUpperCase() != 'MASTER')
          .toList();

      // 3. Más cercano a la sede (para fase 2)
      String? fase2Id;
      final sLat = (s['origen_lat'] as num?)?.toDouble();
      final sLng = (s['origen_lng'] as num?)?.toDouble();
      if (sLat != null && sLng != null && noMasters.isNotEmpty) {
        double minD = double.infinity;
        for (final m in noMasters) {
          final uLat = (m['latitud'] as num?)?.toDouble();
          final uLng = (m['longitud'] as num?)?.toDouble();
          if (uLat == null || uLng == null) continue;
          final d = _haversine(sLat, sLng, uLat, uLng);
          if (d < minD) { minD = d; fase2Id = m['id'].toString(); }
        }
      } else if (noMasters.isNotEmpty) {
        fase2Id = noMasters.first['id'].toString();
      }

      final fase3Ids = noMasters
          .map<String>((m) => m['id'].toString())
          .where((id) => id != fase2Id)
          .toList();

      final zona   = s['zona_fn']?.toString() ?? 'FN';
      final consec = s['fn_consecutivo']?.toString() ?? '#${s['id']}';

      // ── FASE 1 (T=0): Masters ────────────────────────────────────────────────
      if (masters.isNotEmpty) {
        await MotorNotificaciones.dispararRafa(
          idsDestinos: masters,
          titulo: '👑 TURNO FN — MASTER',
          mensaje: 'Servicio disponible · $zona',
          urgente: true,
          sonido: Sonidos.movilParadero,
        );
      }

      // Pasar a pendiente + registrar radar_t0
      final ahora = DateTime.now().toUtc().toIso8601String();
      await _db.from('servicios').update({
        'estado': 'pendiente',
        'fn_radar_t0': ahora,
        'fn_asignacion_tipo': 'radar',
        if (masters.isNotEmpty) 'fn_notificados_fase1': masters,
        if (fase2Id != null) 'fn_fase2_movil_id': fase2Id,
      }).eq('id', s['id']);

      // ── FASE 2 (T+31s): Más cercano ─────────────────────────────────────────
      String? notifF2;
      if (fase2Id != null) {
        notifF2 = await MotorNotificaciones.programarMisilRetardado(
          externalIds: [fase2Id],
          titulo: '🔵 TURNO FN — PARA TI',
          mensaje: 'Servicio disponible · $zona',
          segundosRetardo: 31,
          sonido: Sonidos.movilParadero,
        );
      }

      // ── FASE 3 (T+61s): Resto ───────────────────────────────────────────────
      String? notifF3;
      if (fase3Ids.isNotEmpty) {
        notifF3 = await MotorNotificaciones.programarMisilRetardado(
          externalIds: fase3Ids,
          titulo: '🔵 TURNO FN DISPONIBLE',
          mensaje: 'Servicio sin tomar · $zona',
          segundosRetardo: 61,
          sonido: Sonidos.movilParadero,
        );
      }

      // Guardar IDs de notificaciones programadas para cancelarlas si alguien acepta
      if (notifF2 != null || notifF3 != null) {
        await _db.from('servicios').update({
          if (notifF2 != null) 'fn_notif_fase2': notifF2,
          if (notifF3 != null) 'fn_notif_fase3': notifF3,
        }).eq('id', s['id']);
      }

      // Notificar a la central
      await MotorNotificaciones.dispararACentral(
        titulo: '✅ Cotización aprobada — $consec',
        mensaje: '${_labelSede(s)} aprobó. Enviando al radar FN.',
        urgente: false,
        sonido: Sonidos.fnCotizacion,
      );
    } catch (e) {
      _snack('Error: \$e');
    }
  }

  // Distancia Haversine en metros (sin dependencia de latlong2)
  double _haversine(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371000.0;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLng = (lng2 - lng1) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) * math.cos(lat2 * math.pi / 180) *
        math.sin(dLng / 2) * math.sin(dLng / 2);
    return 2 * r * math.asin(math.sqrt(a));
  }

  // ── Rechazar cotización ─────────────────────────────────────────────────────
  Future<void> _rechazar(Map<String, dynamic> s) async {
    String motivoSel = 'precio_alto';
    final _motivos = {
      'precio_alto': 'Precio muy alto',
      'ya_no_necesita': 'Ya no se necesita',
      'error_datos': 'Error en los datos',
      'otro': 'Otro motivo',
    };
    final _precioCtrl = TextEditingController();
    bool renegociar = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('¿Por qué rechazas la cotización?',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ..._motivos.entries.map((e) => RadioListTile<String>(
                      dense: true,
                      title: Text(e.value, style: const TextStyle(fontSize: 13)),
                      value: e.key,
                      groupValue: motivoSel,
                      onChanged: (v) => setS(() => motivoSel = v!),
                    )),
                const Divider(),
                CheckboxListTile(
                  dense: true,
                  title: const Text('Renegociar con precio sugerido',
                      style: TextStyle(fontSize: 13)),
                  value: renegociar,
                  onChanged: (v) => setS(() => renegociar = v!),
                ),
                if (renegociar) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: _precioCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Precio sugerido (\$)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red[800]),
              onPressed: () async {
                Navigator.pop(ctx);
                try {
                  if (renegociar && _precioCtrl.text.isNotEmpty) {
                    final precio = double.tryParse(
                        _precioCtrl.text.replaceAll('.', '').trim());
                    await _db.from('servicios').update({
                      'estado': 'fn_renegociando',
                      'fn_rechazo_motivo': motivoSel,
                      'fn_precio_sugerido_sede': precio,
                    }).eq('id', s['id']);
                    await MotorNotificaciones.dispararACentral(
                      titulo: '🔄 Renegociación FN — ${s['fn_consecutivo'] ?? '#${s['id']}'}',
                      mensaje: '${_labelSede(s)} propone \$${_precioCtrl.text}',
                      urgente: false,
                      sonido: Sonidos.fnCotizacion,
                    );
                  } else {
                    await _db.from('servicios').update({
                      'estado': 'fn_rechazado',
                      'fn_rechazo_motivo': motivoSel,
                    }).eq('id', s['id']);
                  }
                } catch (e) {
                  _snack('Error: $e');
                }
              },
              child: Text(renegociar ? 'Renegociar' : 'Rechazar',
                  style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
    _precioCtrl.dispose();
  }

  // ── Cancelar (solo ≤5 min desde aprobación) ────────────────────────────────
  Future<void> _cancelar(Map<String, dynamic> s) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancelar servicio'),
        content: const Text('¿Confirmas cancelar este servicio?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('No')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sí, cancelar',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmar != true) return;
    try {
      await _db.from('servicios').update({
        'estado': 'cancelado',
        'observacion': 'Cancelado por la sede dentro de los 5 minutos.',
      }).eq('id', s['id']);
    } catch (e) {
      _snack('Error: $e');
    }
  }

  // ── Reportar problema / queja desde la sede FN ──────────────────────────────
  Future<void> _reportarProblema(Map<String, dynamic> s) async {
    const categoriasSedeF = [
      'Tardanza',
      'No recogió correctamente',
      'Daño al paquete',
      'Mala actitud',
      'Otro',
    ];
    String? categoriaSeleccionada;
    final notaCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDs) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: Text(
            'Queja — ${s['fn_consecutivo'] ?? '#${s['id']}'}',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('¿Cuál es el problema?',
                    style: TextStyle(fontSize: 12, color: Colors.black54)),
                const SizedBox(height: 6),
                ...categoriasSedeF.map((cat) => RadioListTile<String>(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(cat, style: const TextStyle(fontSize: 13)),
                      value: cat,
                      groupValue: categoriaSeleccionada,
                      onChanged: (v) => setDs(() => categoriaSeleccionada = v),
                    )),
                const SizedBox(height: 8),
                TextField(
                  controller: notaCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    hintText: 'Nota adicional (opcional)...',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar',
                  style: TextStyle(color: Colors.black54)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange[800],
                  foregroundColor: Colors.white),
              onPressed: categoriaSeleccionada == null
                  ? null
                  : () async {
                      final cat = categoriaSeleccionada!;
                      final nota = notaCtrl.text.trim();
                      Navigator.pop(ctx);
                      try {
                        await _db.from('reportes_servicio').insert({
                          'servicio_id': s['id'],
                          'movil_id': s['movil_id'],
                          'origen': 'fn_sede',
                          'categoria': cat,
                          'nota': nota.isEmpty ? null : nota,
                        });
                        await MotorNotificaciones.dispararACentral(
                          titulo:
                              '⚠️ Queja sede FN — ${s['fn_consecutivo'] ?? '#${s['id']}'}',
                          mensaje: nota.isNotEmpty ? '$cat: $nota' : cat,
                          urgente: true,
                          sonido: Sonidos.fnCotizacion,
                        );
                        _snack('Queja enviada a la central.');
                      } catch (e) {
                        _snack('Error: $e');
                      }
                    },
              child: const Text('ENVIAR'),
            ),
          ],
        ),
      ),
    );
    notaCtrl.dispose();
  }

  String _labelSede(Map<String, dynamic> s) {
    final sede = widget.sede;
    if (sede == null) return 'Sede FN';
    final tipo = sede['tipo']?.toString() ?? '';
    final num = sede['numero']?.toString() ?? '';
    return tipo == 'FN' && num.isNotEmpty ? 'FN$num' : (sede['nombre'] ?? 'Sede');
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  bool _puedeCanselar(Map<String, dynamic> s) {
    // Solo si pasó ≤5 min desde la última actualización (aprobación → pendiente)
    if (s['estado'] != 'pendiente') return false;
    final raw = s['updated_at']?.toString();
    if (raw == null) return false;
    try {
      final dt = DateTime.parse(raw).toLocal();
      return DateTime.now().difference(dt).inMinutes < 5;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: widget.stream,
      initialData: widget.cache,
      builder: (context, snap) {
        final todos = snap.data ?? [];
        final activos = _filtrarActivos(todos);

        if (activos.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle, color: Colors.white24, size: 48),
                SizedBox(height: 12),
                Text('Sin servicios activos',
                    style: TextStyle(color: Colors.white38, fontSize: 14)),
              ],
            ),
          );
        }

        return RefreshIndicator(
          color: Colors.indigo,
          onRefresh: () async {},
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: activos.length,
            itemBuilder: (ctx, i) => _CardServicioActivo(
              servicio: activos[i],
              onAprobar: () => _aprobar(activos[i]),
              onRechazar: () => _rechazar(activos[i]),
              onCancelar: _puedeCanselar(activos[i])
                  ? () => _cancelar(activos[i])
                  : null,
              onReportarProblema: () => _reportarProblema(activos[i]),
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Card de servicio activo para la sede FN
// ─────────────────────────────────────────────────────────────────────────────

class _CardServicioActivo extends StatefulWidget {
  final Map<String, dynamic> servicio;
  final VoidCallback onAprobar;
  final VoidCallback onRechazar;
  final VoidCallback? onCancelar;
  final VoidCallback onReportarProblema;

  const _CardServicioActivo({
    required this.servicio,
    required this.onAprobar,
    required this.onRechazar,
    required this.onCancelar,
    required this.onReportarProblema,
  });

  @override
  State<_CardServicioActivo> createState() => _CardServicioActivoState();
}

class _CardServicioActivoState extends State<_CardServicioActivo> {
  final _db = Supabase.instance.client;
  String? _movilTelefono;
  String? _movilNumero; // número real: extraído de usuarios.usuario
  String? _movilIdCargado;

  @override
  void initState() {
    super.initState();
    _cargarDatosMovil();
  }

  @override
  void didUpdateWidget(_CardServicioActivo old) {
    super.didUpdateWidget(old);
    final nuevoId = widget.servicio['movil_id']?.toString();
    if (nuevoId != _movilIdCargado) _cargarDatosMovil();
  }

  Future<void> _cargarDatosMovil() async {
    final mid = widget.servicio['movil_id']?.toString();
    if (mid == null) return;
    _movilIdCargado = mid;
    try {
      final row = await _db
          .from('usuarios')
          .select('telefono, usuario')
          .eq('id', mid)
          .maybeSingle();
      if (!mounted) return;
      final usuarioField = row?['usuario']?.toString();
      final numExtraido = usuarioField != null
          ? (RegExp(r'\d+').firstMatch(usuarioField)?.group(0) ?? usuarioField)
          : null;
      setState(() {
        _movilTelefono = row?['telefono']?.toString();
        _movilNumero = numExtraido;
      });
    } catch (_) {}
  }


  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.servicio;
    final estado = s['estado']?.toString() ?? '';
    final consec = s['fn_consecutivo']?.toString() ?? '#${s['id']}';
    final destino = s['destino']?.toString() ?? '—';
    // Usar número real cargado desde usuarios.usuario; fallback vacío mientras carga
    final numMovil = _movilNumero;
    final tarifa = (s['tarifa'] as num?)?.toInt();

    final recogidas = s['recogidas'] is List
        ? (s['recogidas'] as List).cast<Map<String, dynamic>>()
        : <Map<String, dynamic>>[];

    final color = _colorEstado(estado);
    final label = _labelEstado(estado);

    return Card(
      color: const Color(0xFF111111),
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withValues(alpha: 0.4), width: 1.2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Cabecera ──────────────────────────────────────────────────
            Row(
              children: [
                Text(consec,
                    style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 11,
                        letterSpacing: 0.5)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: color, width: 0.7),
                  ),
                  child: Text(label,
                      style: TextStyle(
                          color: color,
                          fontSize: 10,
                          fontWeight: FontWeight.bold)),
                ),
                if (s['fn_alta_demanda'] == true) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.orange[900],
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('ALTA DEMANDA',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold)),
                  ),
                ],
                const Spacer(),
                if (tarifa != null)
                  Text('\$${_miles(tarifa)}',
                      style: const TextStyle(
                          color: Colors.green,
                          fontWeight: FontWeight.bold,
                          fontSize: 14)),
              ],
            ),

            const SizedBox(height: 10),

            // ── Recogidas ─────────────────────────────────────────────────
            ...recogidas.map((r) => Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(
                children: [
                  Icon(Icons.local_pharmacy,
                      size: 13, color: Colors.indigo[300]),
                  const SizedBox(width: 5),
                  Text(
                    _labelRecogida(r),
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  if (r['cobertura'] == 'fuera' || r['cobertura'] == 'por_evaluar')
                    const Padding(
                      padding: EdgeInsets.only(left: 4),
                      child: Text('⚠',
                          style: TextStyle(fontSize: 11)),
                    ),
                ],
              ),
            )),

            // ── Destino ───────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Row(
                children: [
                  const Icon(Icons.place,
                      size: 13, color: Colors.white38),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(destino,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 13,
                            fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ),

            // ── Detalles factura ──────────────────────────────────────────
            if (s['fn_factura_numero'] != null || s['fn_pagar_producto'] == true) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: [
                  if (s['fn_factura_numero'] != null)
                    _chip('Fac. ${s['fn_factura_numero']}', Colors.blueGrey),
                  if (s['fn_factura_valor'] != null)
                    _chip('\$${_miles((s['fn_factura_valor'] as num).toInt())}', Colors.blueGrey),
                  if (s['fn_pagar_producto'] == true)
                    _chip('PAGAR PRODUCTO', Colors.red[800]!),
                  if (s['metodo_pago'] == 'Datafono')
                    _chip('DATÁFONO', Colors.blue[800]!),
                ],
              ),
            ],

            // ── Móvil asignado + WA ───────────────────────────────────────
            if (numMovil != null && estado != 'cotizacion' && estado != 'cotizada') ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.two_wheeler, size: 14, color: Colors.white54),
                  const SizedBox(width: 5),
                  Text('Móvil $numMovil',
                      style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.bold)),
                  const Spacer(),
                  // Botón WhatsApp del móvil asignado
                  if (_movilTelefono != null && _movilTelefono!.isNotEmpty)
                    GestureDetector(
                      onTap: () {
                        final tel = _movilTelefono!.replaceAll(RegExp(r'\D'), '');
                        launchUrl(Uri.parse('https://wa.me/57$tel'),
                            mode: LaunchMode.externalApplication);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF25D366).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                              color: const Color(0xFF25D366).withValues(alpha: 0.5)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.chat, size: 13, color: Color(0xFF25D366)),
                            SizedBox(width: 4),
                            Text('WA Móvil',
                                style: TextStyle(
                                    color: Color(0xFF25D366),
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),

              // ── Tiempo estimado según estado ────────────────────────────
              Builder(builder: (_) {
                // Extra recogidas = las que NO son la sede solicitante
                final extraRec = recogidas
                    .where((r) => r['es_sede_solicitante'] != true)
                    .length;

                if (estado == 'en_ruta_origen') {
                  return Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          const Icon(Icons.schedule, size: 12, color: Colors.orange),
                          const SizedBox(width: 4),
                          const Text('Llegada a sede: ~15 min',
                              style: TextStyle(color: Colors.orange, fontSize: 11)),
                        ]),
                        if (extraRec > 0) ...[
                          const SizedBox(height: 2),
                          Row(children: [
                            const Icon(Icons.add_location_alt_outlined,
                                size: 12, color: Colors.orange),
                            const SizedBox(width: 4),
                            Text(
                              '+ ~${extraRec * 5} min por '
                              '${extraRec == 1 ? "1 recogida adicional" : "$extraRec recogidas adicionales"}',
                              style: TextStyle(
                                  color: Colors.orange[300], fontSize: 10),
                            ),
                          ]),
                        ],
                      ],
                    ),
                  );
                }

                if (estado == 'en_ruta_destino') {
                  return Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Row(children: [
                      const Icon(Icons.schedule, size: 12, color: Colors.greenAccent),
                      const SizedBox(width: 4),
                      const Text('Entrega: ~15 min',
                          style: TextStyle(
                              color: Colors.greenAccent, fontSize: 11)),
                    ]),
                  );
                }

                return const SizedBox.shrink();
              }),
            ],

            // ── Renegociación: cotización aceptada por central ────────────
            if (estado == 'fn_renegociando' && s['fn_precio_sugerido_sede'] != null) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.purple[900]!.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.purple[400]!),
                ),
                child: Text(
                  'Tu precio sugerido: \$${_miles((s['fn_precio_sugerido_sede'] as num).toInt())} — esperando respuesta de la central',
                  style: const TextStyle(color: Colors.purple, fontSize: 12),
                ),
              ),
            ],

            // ── Acciones para estado 'cotizada' ───────────────────────────
            if (estado == 'cotizada' && tarifa != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.green[900]!.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green[700]!),
                ),
                child: Column(
                  children: [
                    Text(
                      'La central cotizó este servicio en \$${_miles(tarifa)}',
                      style: const TextStyle(
                          color: Colors.white, fontSize: 13,
                          fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: widget.onRechazar,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.red,
                              side: const BorderSide(color: Colors.red),
                            ),
                            child: const Text('Rechazar'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: widget.onAprobar,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green[700],
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('Aprobar',
                                style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],

            // ── Cancelar (≤5 min desde aprobación) ──────────────────────
            if (widget.onCancelar != null) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: widget.onCancelar,
                  icon: const Icon(Icons.cancel_outlined, size: 15, color: Colors.red),
                  label: const Text('Cancelar servicio',
                      style: TextStyle(color: Colors.red, fontSize: 13)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.red),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ],

            // ── Acciones secundarias ──────────────────────────────────────
            if (estado != 'cotizacion') ...[
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (!['cotizada', 'fn_renegociando'].contains(estado))
                    TextButton(
                      onPressed: widget.onReportarProblema,
                      child: const Text('Reportar problema',
                          style: TextStyle(color: Colors.orange, fontSize: 12)),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _labelRecogida(Map<String, dynamic> r) {
    if (r['es_manual'] == true) {
      final dir = r['direccion']?.toString() ?? '';
      final nom = r['nombre']?.toString() ?? '';
      return dir.isNotEmpty ? '$nom · $dir' : nom.isNotEmpty ? nom : 'Dirección libre';
    }
    final tipo = r['tipo']?.toString() ?? '';
    final num = r['numero']?.toString() ?? '';
    final nombre = r['nombre']?.toString() ?? '';
    return tipo == 'FN' && num.isNotEmpty ? 'FN$num — $nombre' : nombre;
  }

  Widget _chip(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Text(label,
            style: TextStyle(
                color: color == Colors.blueGrey ? Colors.blueGrey[200] : Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold)),
      );

  Color _colorEstado(String e) {
    return switch (e) {
      'cotizacion' => Colors.orange,
      'cotizada' => Colors.green,
      'pendiente' => Colors.blue,
      'en_ruta_origen' => Colors.indigo,
      'en_origen' => Colors.purple,
      'en_ruta_destino' => Colors.teal,
      'fn_renegociando' => Colors.deepPurple,
      'fn_rechazado' => Colors.red,
      _ => Colors.grey,
    };
  }

  String _labelEstado(String e) {
    return switch (e) {
      'cotizacion' => 'EN COTIZACIÓN',
      'cotizada' => 'PRECIO LISTO',
      'pendiente' => 'BUSCANDO MÓVIL',
      'en_ruta_origen' => 'MÓVIL EN CAMINO',
      'en_origen' => 'MÓVIL EN SEDE',
      'en_ruta_destino' => 'EN RUTA',
      'finalizado' => 'ENTREGADO',
      'fn_renegociando' => 'RENEGOCIANDO',
      'fn_rechazado' => 'RECHAZADO',
      _ => e.toUpperCase().replaceAll('_', ' '),
    };
  }

  String _miles(int v) {
    final s = v.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TAB 3 — HISTORIAL
// ═══════════════════════════════════════════════════════════════════════════════

class _HistorialTab extends StatefulWidget {
  final Map<String, dynamic> usuario;
  final Map<String, dynamic>? sede;

  const _HistorialTab({required this.usuario, required this.sede});

  @override
  State<_HistorialTab> createState() => _HistorialTabState();
}

class _HistorialTabState extends State<_HistorialTab> {
  final _db = Supabase.instance.client;
  List<Map<String, dynamic>> _servicios = [];
  bool _cargando = true;
  DateTimeRange? _rango;
  String _filtroEstado = 'todos';

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final sedeId = widget.usuario['fn_sede_id'];
      if (sedeId == null) {
        setState(() => _cargando = false);
        return;
      }

      var q = _db
          .from('servicios')
          .select(
              'id, fn_consecutivo, estado, creador, destino, tarifa, fn_factura_numero, '
              'fn_factura_valor, fn_pagar_producto, numero_movil, fn_movil_asignado_at, '
              'accepted_at, created_at, fn_alta_demanda, recogidas, metodo_pago, '
              'instrucciones_especiales, fn_rechazo_motivo, '
              'movil_data:usuarios!servicios_movil_id_fkey(usuario)')
          .eq('fn_sede_solicitante_id', sedeId)
          .not('estado', 'in', '("cotizacion","cotizada","pendiente","en_ruta_origen","en_origen","en_ruta_destino","fn_renegociando")')
          .gte('created_at', _rango?.start.toUtc().toIso8601String() ?? '2000-01-01T00:00:00Z')
          .lte('created_at', _rango?.end.toUtc().toIso8601String() ?? '2100-01-01T00:00:00Z')
          .order('id', ascending: false)
          .limit(100);

      final data = await q;
      var lista = List<Map<String, dynamic>>.from(data);

      if (_filtroEstado != 'todos') {
        lista = lista.where((s) => s['estado'] == _filtroEstado).toList();
      }

      setState(() => _servicios = lista);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _seleccionarRango() async {
    final rango = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      initialDateRange: _rango,
    );
    if (rango != null) {
      setState(() => _rango = rango);
      _cargar();
    }
  }

  String _miles(int v) {
    final s = v.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  String _formatFecha(String? raw) {
    if (raw == null) return '—';
    try {
      final dt = DateTime.parse(raw).toLocal();
      return '${dt.day.toString().padLeft(2, '0')}/'
          '${dt.month.toString().padLeft(2, '0')} '
          '${dt.hour.toString().padLeft(2, '0')}:'
          '${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return raw;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── Filtros ───────────────────────────────────────────────────────
        Container(
          color: const Color(0xFF0F0F0F),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final (val, lbl) in [
                        ('todos', 'Todos'),
                        ('finalizado', 'Entregados'),
                        ('cancelado', 'Cancelados'),
                        ('fn_rechazado', 'Rechazados'),
                        ('caducado', 'Caducados'),
                      ])
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: Text(lbl,
                                style: TextStyle(
                                    fontSize: 11,
                                    color: _filtroEstado == val
                                        ? Colors.white
                                        : Colors.white54)),
                            selected: _filtroEstado == val,
                            onSelected: (_) {
                              setState(() => _filtroEstado = val);
                              _cargar();
                            },
                            selectedColor: Colors.indigo[800],
                            backgroundColor: const Color(0xFF1A1A1A),
                            side: BorderSide.none,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              IconButton(
                icon: Icon(
                  Icons.date_range,
                  color: _rango != null ? Colors.indigo[300] : Colors.white38,
                  size: 20,
                ),
                tooltip: 'Filtrar por fecha',
                onPressed: _seleccionarRango,
              ),
              if (_rango != null)
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white38, size: 18),
                  onPressed: () {
                    setState(() => _rango = null);
                    _cargar();
                  },
                ),
            ],
          ),
        ),

        // ── Lista ─────────────────────────────────────────────────────────
        Expanded(
          child: _cargando
              ? const Center(
                  child: CircularProgressIndicator(color: Colors.indigo))
              : _servicios.isEmpty
                  ? const Center(
                      child: Text('Sin registros',
                          style: TextStyle(color: Colors.white38)))
                  : RefreshIndicator(
                      color: Colors.indigo,
                      onRefresh: _cargar,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _servicios.length,
                        itemBuilder: (ctx, i) {
                          final s = _servicios[i];
                          final estado = s['estado']?.toString() ?? '';
                          final consecutivo = s['fn_consecutivo']?.toString();
                          final tarifa = (s['tarifa'] as num?)?.toInt();
                          // Número real del móvil desde usuarios.usuario (ej: "movil05" → "05")
                          final movilUsuario = s['movil_data']?['usuario']?.toString();
                          final numMovil = movilUsuario != null
                              ? (RegExp(r'\d+').firstMatch(movilUsuario)?.group(0) ?? movilUsuario)
                              : null;
                          final facturaNum = s['fn_factura_numero']?.toString();
                          final recogidas = s['recogidas'];
                          final altaDemanda = s['fn_alta_demanda'] == true;

                          Color color = estado == 'finalizado'
                              ? Colors.green[700]!
                              : estado == 'cancelado' || estado == 'fn_rechazado'
                                  ? Colors.red[800]!
                                  : Colors.grey[600]!;

                          String labelEstado;
                          switch (estado) {
                            case 'finalizado': labelEstado = 'ENTREGADO'; break;
                            case 'cancelado': labelEstado = 'CANCELADO'; break;
                            case 'fn_rechazado': labelEstado = 'RECHAZADO'; break;
                            case 'caducado': labelEstado = 'CADUCADO'; break;
                            case 'finalizado_con_problema': labelEstado = 'FIN+PROB'; break;
                            default: labelEstado = estado.toUpperCase();
                          }

                          return GestureDetector(
                            onTap: () => _mostrarDetalle(context, s),
                            child: Card(
                              color: const Color(0xFF111111),
                              margin: const EdgeInsets.only(bottom: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                                side: BorderSide(color: color.withValues(alpha: 0.3)),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: color.withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(4),
                                            border: Border.all(color: color.withValues(alpha: 0.5), width: 0.8),
                                          ),
                                          child: Text(labelEstado,
                                              style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: color)),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          consecutivo != null ? 'FN-$consecutivo' : '#${s["id"]}',
                                          style: const TextStyle(
                                              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                        ),
                                        if (altaDemanda) ...[
                                          const SizedBox(width: 6),
                                          const Text('\u{1F525}', style: TextStyle(fontSize: 11)),
                                        ],
                                        const Spacer(),
                                        Text(_formatFecha(s['created_at']?.toString()),
                                            style: const TextStyle(color: Colors.white38, fontSize: 10)),
                                      ],
                                    ),
                                    if (s['destino'] != null) ...[
                                      const SizedBox(height: 5),
                                      Text(
                                        s['destino'].toString(),
                                        style: const TextStyle(color: Colors.white60, fontSize: 11),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        if (numMovil != null) ...[
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.indigo[900],
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text('\u{1F343} M\u00F3vil $numMovil',
                                                style: const TextStyle(
                                                    color: Colors.white70, fontSize: 9, fontWeight: FontWeight.bold)),
                                          ),
                                          const SizedBox(width: 8),
                                        ],
                                        if (tarifa != null && tarifa > 0)
                                          Text('\$${_miles(tarifa)}',
                                              style: const TextStyle(
                                                  color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                                        if (facturaNum != null) ...[
                                          const SizedBox(width: 8),
                                          Text('Fact. $facturaNum',
                                              style: TextStyle(color: Colors.indigo[300], fontSize: 10)),
                                        ],
                                        if (s['fn_factura_valor'] != null && (s['fn_factura_valor'] as num) > 0) ...[
                                          const SizedBox(width: 8),
                                          Text(
                                            '\$${_miles((s['fn_factura_valor'] as num).toInt())} prod.',
                                            style: TextStyle(color: Colors.indigo[200], fontSize: 10),
                                          ),
                                        ],
                                        const Spacer(),
                                        if (recogidas is List && recogidas.isNotEmpty)
                                          Text('${recogidas.length} recog.',
                                              style: const TextStyle(color: Colors.white38, fontSize: 10)),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
              ],
            );
  }

  void _mostrarDetalle(BuildContext context, Map<String, dynamic> s) {
    String fmt(dynamic v) => v == null ? '\u2014' : v.toString();
    String fmtPeso(dynamic v) {
      if (v == null) return '\u2014';
      final n = (v as num).toInt();
      return n == 0 ? '\u2014' : '\$${_miles(n)}';
    }

    final consecutivo = s['fn_consecutivo']?.toString();
    final estado = s['estado']?.toString() ?? '';
    final recogidas = s['recogidas'];
    final recogidasCount = recogidas is List ? recogidas.length : null;
    // Número real del móvil desde join usuarios.usuario
    final movilUsuarioDetalle = s['movil_data']?['usuario']?.toString();
    final numMovilDetalle = movilUsuarioDetalle != null
        ? (RegExp(r'\d+').firstMatch(movilUsuarioDetalle)?.group(0) ?? movilUsuarioDetalle)
        : null;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        builder: (_, ctrl) => Container(
          decoration: const BoxDecoration(
            color: Color(0xFF1A1A1A),
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            children: [
              Container(
                width: 36, height: 4,
                margin: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Text(
                      consecutivo != null ? 'FN-$consecutivo' : 'Servicio #${s["id"]}',
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.indigo.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(estado.toUpperCase(),
                          style: const TextStyle(color: Colors.indigo, fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
              const Divider(height: 16, color: Colors.white12),
              Expanded(
                child: ListView(
                  controller: ctrl,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    if (s['destino'] != null) _filaDetalle('Destino', fmt(s['destino'])),
                    _filaDetalle('Tarifa', fmtPeso(s['tarifa'])),
                    if (s['fn_factura_numero'] != null)
                      _filaDetalle('N\u00B0 Factura', fmt(s['fn_factura_numero'])),
                    if (s['fn_factura_valor'] != null)
                      _filaDetalle('Valor factura', fmtPeso(s['fn_factura_valor'])),
                    if (s['fn_pagar_producto'] == true ||
                        (s['fn_pagar_producto'] is num && (s['fn_pagar_producto'] as num) > 0))
                      _filaDetalle('Pagar producto',
                          s['fn_pagar_producto'] is num
                              ? fmtPeso(s['fn_pagar_producto'])
                              : 'Sí'),
                    if (recogidasCount != null)
                      _filaDetalle('Recogidas', '$recogidasCount sede${recogidasCount == 1 ? "" : "s"}'),
                    if (numMovilDetalle != null)
                      _filaDetalle('M\u00F3vil asignado', 'M\u00F3vil $numMovilDetalle'),
                    if (s['metodo_pago'] != null)
                      _filaDetalle('M\u00E9todo de pago', fmt(s['metodo_pago'])),
                    if (s['fn_alta_demanda'] == true)
                      _filaDetalle('Alta demanda', '\u{1F525} S\u00ED'),
                    _filaDetalle('Creado', _formatFecha(s['created_at']?.toString())),
                    if (s['accepted_at'] != null)
                      _filaDetalle('Aceptado', _formatFecha(s['accepted_at']?.toString())),
                    if (s['fn_movil_asignado_at'] != null)
                      _filaDetalle('Llegada a sede', _formatFecha(s['fn_movil_asignado_at']?.toString())),
                    if (s['fn_rechazo_motivo'] != null)
                      _filaDetalle('Motivo rechazo', s['fn_rechazo_motivo'].toString()),
                    if (s['instrucciones_especiales'] != null &&
                        s['instrucciones_especiales'].toString().isNotEmpty)
                      _filaDetalle('Instrucciones', s['instrucciones_especiales'].toString()),
                    const SizedBox(height: 12),
                    // ── Editar factura (sec. 7 de la especificación) ─────────
                    if (['finalizado', 'finalizado_con_problema'].contains(estado))
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.edit_note, size: 16, color: Colors.indigo),
                          label: const Text('Editar datos de factura',
                              style: TextStyle(color: Colors.indigo, fontSize: 13)),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.indigo),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                          onPressed: () {
                            Navigator.pop(context);
                            _editarFactura(s);
                          },
                        ),
                      ),
                    // ── Auditoría de cambios ──────────────────────────────────
                    FutureBuilder<List<Map<String, dynamic>>>(
                      future: _db
                          .from('fn_auditorias_factura')
                          .select('campo, valor_anterior, valor_nuevo, editor_tipo, created_at')
                          .eq('servicio_id', s['id'])
                          .order('created_at', ascending: false),
                      builder: (_, snap) {
                        final audits = snap.data ?? [];
                        if (audits.isEmpty) return const SizedBox.shrink();
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 12),
                            const Text('Historial de ediciones',
                                style: TextStyle(color: Colors.white38, fontSize: 11,
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(height: 6),
                            ...audits.map((a) => Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                '${_formatFecha(a['created_at']?.toString())} · '
                                '${a['editor_tipo']} cambió ${a['campo']}: '
                                '${a['valor_anterior'] ?? '—'} → ${a['valor_nuevo'] ?? '—'}',
                                style: const TextStyle(color: Colors.white30, fontSize: 10),
                              ),
                            )),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Editar N° factura con auditoría ────────────────────────────────────────
  Future<void> _editarFactura(Map<String, dynamic> s) async {
    final numCtrl = TextEditingController(text: s['fn_factura_numero']?.toString() ?? '');

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('Editar N° de factura',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
        content: TextField(
          controller: numCtrl,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: 'N° de factura',
            labelStyle: TextStyle(color: Colors.white54),
            enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.white24)),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar', style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Guardar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    numCtrl.dispose();
    if (confirmar != true || !mounted) return;

    try {
      final nuevoNum = numCtrl.text.trim().isEmpty ? null : numCtrl.text.trim();

      if (nuevoNum == s['fn_factura_numero']?.toString()) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Sin cambios que guardar')));
        return;
      }

      final editorId = widget.usuario['id'];

      await _db.from('servicios').update({
        'fn_factura_numero': nuevoNum,
      }).eq('id', s['id']);

      await _db.from('fn_auditorias_factura').insert({
        'servicio_id': s['id'],
        'editor_id': editorId,
        'editor_tipo': 'sede_fn',
        'campo': 'fn_factura_numero',
        'valor_anterior': s['fn_factura_numero']?.toString(),
        'valor_nuevo': nuevoNum,
      });

      setState(() {
        final idx = _servicios.indexWhere((x) => x['id'] == s['id']);
        if (idx >= 0) {
          _servicios[idx] = {
            ..._servicios[idx],
            'fn_factura_numero': nuevoNum,
          };
        }
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ N° de factura actualizado y registrado en auditoría'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Widget _filaDetalle(String label, String valor) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 130,
              child: Text(label,
                  style: const TextStyle(color: Colors.white38, fontSize: 12, fontWeight: FontWeight.w600)),
            ),
            Expanded(
              child: Text(valor, style: const TextStyle(color: Colors.white, fontSize: 12)),
            ),
          ],
        ),
      );
}
