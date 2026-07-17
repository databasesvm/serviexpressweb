// ignore_for_file: use_build_context_synchronously
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:serviexpress_app/utils/sonido_manager.dart';
import 'package:serviexpress_app/utils/onesignal_api.dart';
import 'package:serviexpress_app/screens/login_screen.dart';

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
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (_) => false,
                );
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

  // Destino
  final _destinoCtrl = TextEditingController();

  // Factura
  final _facturaNumCtrl = TextEditingController();
  final _facturaValCtrl = TextEditingController();

  // Instrucciones
  final _instruccionesCtrl = TextEditingController();

  bool _conDatafono = false;
  bool _pagarProducto = false;
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
    _facturaValCtrl.dispose();
    _instruccionesCtrl.dispose();
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
    for (final r in _recogidasSel) {
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

    // Validar al menos 1 recogida seleccionada
    final recogidasValidas = _recogidasSel.whereType<Map<String, dynamic>>().toList();
    if (recogidasValidas.isEmpty) {
      _snack('Selecciona al menos una sede de recogida.');
      return;
    }

    setState(() => _enviando = true);
    try {
      // Construir lista de recogidas para el JSONB
      final recogidasList = recogidasValidas.map((s) => {
        'id': s['id'],
        'tipo': s['tipo'],
        'nombre': s['nombre'],
        'numero': s['numero'],
        'zona': s['zona'],
        'lat': s['lat'],
        'lng': s['lng'],
        'cobertura': s['cobertura'] ?? 'dentro',
      }).toList();

      // Generar consecutivo
      final consec = await _db
          .rpc('fn_generar_consecutivo', params: {'p_sede_id': sedeId});

      // Nombre de la sede solicitante
      final sedeData = widget.sede;
      final nombreSede = sedeData != null
          ? _labelSede(sedeData)
          : 'Sede FN';

      final altaDemanda = widget.altaDemanda;

      // Factura valor
      final factValorStr = _facturaValCtrl.text
          .replaceAll('.', '')
          .replaceAll(',', '')
          .trim();
      final factValor = double.tryParse(factValorStr);

      await _db.from('servicios').insert({
        'origen': nombreSede,
        'destino': _destinoCtrl.text.trim().toUpperCase(),
        'estado': 'cotizacion',
        'creador': 'FN-Sede',
        'tipo_servicio': 'FARMANORTE',
        'tipo_fn': true,
        'fn_origen': 'sede',
        'fn_sede_solicitante_id': sedeId,
        'fn_sede_id': recogidasValidas.first['id'], // primera recogida como sede principal
        'recogidas': recogidasList,
        'metodo_pago': _conDatafono ? 'Datafono' : 'Efectivo',
        'fn_pagar_producto': _pagarProducto,
        'fn_factura_numero': _facturaNumCtrl.text.trim().isEmpty
            ? null
            : _facturaNumCtrl.text.trim(),
        'fn_factura_valor': factValor,
        'fn_alta_demanda': altaDemanda,
        'fn_consecutivo': consec?.toString(),
        'fn_recotizacion': 1,
        'archivado': false,
        if (_instruccionesCtrl.text.trim().isNotEmpty)
          'instrucciones_especiales': _instruccionesCtrl.text.trim(),
        // Coordenadas de la primera sede de recogida como origen
        if (recogidasValidas.first['lat'] != null)
          'origen_lat': (recogidasValidas.first['lat'] as num).toDouble(),
        if (recogidasValidas.first['lng'] != null)
          'origen_lng': (recogidasValidas.first['lng'] as num).toDouble(),
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
        _recogidasSel
          ..clear()
          ..add(null);
        _conDatafono = false;
        _pagarProducto = false;
      });
      _destinoCtrl.clear();
      _facturaNumCtrl.clear();
      _facturaValCtrl.clear();
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
    return SingleChildScrollView(
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
            _seccionLabel('📦 Recogidas (sedes donde recoger)'),
            const SizedBox(height: 8),

            if (_cargandoSedes)
              const Center(child: CircularProgressIndicator(color: Colors.indigo))
            else ...[
              ...List.generate(_recogidasSel.length, (i) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<Map<String, dynamic>>(
                        value: _recogidasSel[i],
                        decoration: _inputDeco(
                          'Recogida ${i + 1}',
                          hint: 'Seleccionar sede FN',
                        ),
                        dropdownColor: const Color(0xFF1E1E1E),
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        isExpanded: true,
                        items: _sedesDisponibles.map((s) => DropdownMenuItem(
                          value: s,
                          child: Text(_labelSede(s),
                              style: const TextStyle(color: Colors.white, fontSize: 13)),
                        )).toList(),
                        onChanged: (v) =>
                            setState(() => _recogidasSel[i] = v),
                        validator: (v) =>
                            (i == 0 && v == null) ? 'Requerido' : null,
                      ),
                    ),
                    if (_recogidasSel.length > 1) ...[
                      const SizedBox(width: 6),
                      IconButton(
                        icon: const Icon(Icons.remove_circle,
                            color: Colors.red),
                        onPressed: () =>
                            setState(() => _recogidasSel.removeAt(i)),
                      ),
                    ],
                  ],
                ),
              )),
              TextButton.icon(
                onPressed: () =>
                    setState(() => _recogidasSel.add(null)),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Agregar recogida',
                    style: TextStyle(fontSize: 13)),
                style: TextButton.styleFrom(
                    foregroundColor: Colors.indigo[300]),
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
            _switchTile(
              '¿El móvil debe pagar el producto?',
              _pagarProducto,
              (v) => setState(() => _pagarProducto = v),
            ),

            const SizedBox(height: 16),

            // ── Factura ─────────────────────────────────────────────────────
            _seccionLabel('🧾 Datos de la factura (opcional)'),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _facturaNumCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: _inputDeco('N° factura'),
                    keyboardType: TextInputType.text,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: _facturaValCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: _inputDeco('Valor (\$)'),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                ),
              ],
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
    );
  }

  Widget _seccionLabel(String texto) => Text(
        texto,
        style: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5),
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

  // ── Aprobar cotización ──────────────────────────────────────────────────────
  Future<void> _aprobar(Map<String, dynamic> s) async {
    try {
      await _db.from('servicios').update({
        'estado': 'pendiente',
      }).eq('id', s['id']);
      // Notificar a la central que fue aprobada
      await MotorNotificaciones.dispararACentral(
        titulo: '✅ Cotización aprobada — ${s['fn_consecutivo'] ?? '#${s['id']}'}',
        mensaje: '${_labelSede(s)} aprobó. Enviando al radar FN.',
        urgente: false,
        sonido: Sonidos.fnCotizacion,
      );
    } catch (e) {
      _snack('Error: $e');
    }
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
  Timer? _etaTimer;
  int _etaSegundos = 0;

  @override
  void initState() {
    super.initState();
    _iniciarEta();
  }

  @override
  void didUpdateWidget(_CardServicioActivo old) {
    super.didUpdateWidget(old);
    _iniciarEta();
  }

  void _iniciarEta() {
    _etaTimer?.cancel();
    final s = widget.servicio;
    // ETA arranca cuando se asigna el móvil (fn_movil_asignado_at)
    final raw = s['fn_movil_asignado_at']?.toString() ?? s['updated_at']?.toString();
    final etaBase = (s['fn_sedes']?['eta_base'] as int?) ?? 15;
    if (raw == null || !['en_ruta_origen', 'pendiente'].contains(s['estado'])) {
      return;
    }
    try {
      final inicio = DateTime.parse(raw).toLocal();
      final metaSeg = etaBase * 60;
      void tick() {
        if (!mounted) return;
        final transcurridos = DateTime.now().difference(inicio).inSeconds;
        setState(() => _etaSegundos = (metaSeg - transcurridos).clamp(0, metaSeg));
      }
      tick();
      _etaTimer = Timer.periodic(const Duration(seconds: 1), (_) => tick());
    } catch (_) {}
  }

  @override
  void dispose() {
    _etaTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.servicio;
    final estado = s['estado']?.toString() ?? '';
    final consec = s['fn_consecutivo']?.toString() ?? '#${s['id']}';
    final destino = s['destino']?.toString() ?? '—';
    final numMovil = s['numero_movil']?.toString();
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

            // ── Móvil asignado + ETA ──────────────────────────────────────
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
                  if (_etaSegundos > 0 && estado == 'en_ruta_origen') ...[
                    const SizedBox(width: 12),
                    const Icon(Icons.timer,
                        size: 12, color: Colors.orange),
                    const SizedBox(width: 4),
                    Text(
                      'ETA: ${(_etaSegundos ~/ 60).toString().padLeft(2, '0')}:${(_etaSegundos % 60).toString().padLeft(2, '0')}',
                      style: const TextStyle(
                          color: Colors.orange,
                          fontSize: 12,
                          fontWeight: FontWeight.bold),
                    ),
                  ],
                ],
              ),
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

            // ── Acciones secundarias ──────────────────────────────────────
            if (estado != 'cotizacion') ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (widget.onCancelar != null)
                    TextButton(
                      onPressed: widget.onCancelar,
                      child: const Text('Cancelar',
                          style: TextStyle(color: Colors.red, fontSize: 12)),
                    ),
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
              'accepted_at, created_at, fn_alta_demanda, recogidas, metodo_pago')
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
                          final numMovil = s['numero_movil']?.toString();
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
                    if (s['fn_pagar_producto'] != null && (s['fn_pagar_producto'] as num) > 0)
                      _filaDetalle('Pagar producto', fmtPeso(s['fn_pagar_producto'])),
                    if (recogidasCount != null)
                      _filaDetalle('Recogidas', '$recogidasCount sede${recogidasCount == 1 ? "" : "s"}'),
                    if (s['numero_movil'] != null)
                      _filaDetalle('M\u00F3vil asignado', 'M\u00F3vil ${s["numero_movil"]}'),
                    if (s['metodo_pago'] != null)
                      _filaDetalle('M\u00E9todo de pago', fmt(s['metodo_pago'])),
                    if (s['fn_alta_demanda'] == true)
                      _filaDetalle('Alta demanda', '\u{1F525} S\u00ED'),
                    _filaDetalle('Creado', _formatFecha(s['created_at']?.toString())),
                    if (s['accepted_at'] != null)
                      _filaDetalle('Aceptado', _formatFecha(s['accepted_at']?.toString())),
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
