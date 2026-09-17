// ignore_for_file: use_build_context_synchronously
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'fn_facturacion_screen.dart';
import 'login_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Panel supervisor FN — rol: supervisor_fn
// Tabs: En vivo | Historial | Dashboard | Auditoría
// Solo lectura (no puede cotizar ni asignar)
// ─────────────────────────────────────────────────────────────────────────────

class SupervisorFnScreen extends StatefulWidget {
  final Map<String, dynamic> usuario;
  const SupervisorFnScreen({super.key, required this.usuario});

  @override
  State<SupervisorFnScreen> createState() => _SupervisorFnScreenState();
}

class _SupervisorFnScreenState extends State<SupervisorFnScreen>
    with SingleTickerProviderStateMixin {
  final _db = Supabase.instance.client;
  late final TabController _tab;

  // Stream antiparpadeo — todos los servicios FN de sedes
  final _ctrl = StreamController<List<Map<String, dynamic>>>.broadcast();
  StreamSubscription? _sub;
  List<Map<String, dynamic>>? _cache;
  Timer? _reconTimer;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    OneSignal.login(widget.usuario['id'].toString());
    OneSignal.User.addTagWithKey('rol', 'supervisor_fn');
    _construirStream();
    _reconTimer = Timer.periodic(const Duration(seconds: 30), (_) => _construirStream());
  }

  @override
  void dispose() {
    _tab.dispose();
    _sub?.cancel();
    _reconTimer?.cancel();
    _ctrl.close();
    super.dispose();
  }

  void _construirStream() {
    _sub?.cancel();
    final crudo = _db
        .from('servicios')
        .stream(primaryKey: ['id'])
        .eq('fn_origen', 'sede')
        .order('id', ascending: false);

    _sub = crudo.listen(
      (data) {
        _cache = data;
        if (!_ctrl.isClosed) _ctrl.add(data);
      },
      onError: (_) {},
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF002DA2),
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Row(
          children: [
            Icon(Icons.supervisor_account, color: Colors.white, size: 18),
            SizedBox(width: 8),
            Text('Supervisor FN',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 17)),
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
            Tab(icon: Icon(Icons.two_wheeler), text: 'Activos'),
            Tab(icon: Icon(Icons.history_rounded), text: 'Historial'),
            Tab(icon: Icon(Icons.bar_chart_rounded), text: 'Resumen'),
          ],
        ),
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _ctrl.stream,
        initialData: _cache,
        builder: (context, snap) {
          final todos = snap.data ?? [];
          return TabBarView(
            controller: _tab,
            children: [
              _TabEnVivo(todos: todos),
              const FnFacturacionScreen(embedded: true),
              _TabDashboard(todos: todos, db: _db),
            ],
          );
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TAB 1 — EN VIVO (solo lectura)
// ═══════════════════════════════════════════════════════════════════════════════

class _TabEnVivo extends StatelessWidget {
  final List<Map<String, dynamic>> todos;
  const _TabEnVivo({required this.todos});

  static const _activos = [
    'cotizacion', 'cotizada', 'pendiente', 'en_ruta_origen',
    'en_origen', 'en_ruta_destino', 'fn_renegociando',
  ];

  @override
  Widget build(BuildContext context) {
    final activos = todos.where((s) => _activos.contains(s['estado'])).toList();

    if (activos.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline, color: Colors.white24, size: 48),
            SizedBox(height: 12),
            Text('Sin servicios FN activos',
                style: TextStyle(color: Colors.white38, fontSize: 14)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: activos.length,
      itemBuilder: (ctx, i) => _CardEnVivo(servicio: activos[i]),
    );
  }
}

class _CardEnVivo extends StatelessWidget {
  final Map<String, dynamic> servicio;
  const _CardEnVivo({required this.servicio});

  @override
  Widget build(BuildContext context) {
    final estado = servicio['estado']?.toString() ?? '';
    final consec = servicio['fn_consecutivo']?.toString() ?? '#${servicio['id']}';
    final destino = servicio['destino']?.toString() ?? '—';
    final tarifa = (servicio['tarifa'] as num?)?.toInt();
    final numMovil = servicio['numero_movil']?.toString();
    final recogidas = servicio['recogidas'] is List
        ? (servicio['recogidas'] as List).cast<Map<String, dynamic>>()
        : <Map<String, dynamic>>[];

    final color = _color(estado);
    final label = (estado == 'pendiente' && servicio['movil_id'] != null)
        ? 'MÓVIL NOTIFICADO'
        : _labelEstado(estado);

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
            // ── Cabecera ──────────────────────────────────────────────
            Row(
              children: [
                Text(consec,
                    style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 11,
                        letterSpacing: 0.5)),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: color, width: 0.7),
                  ),
                  child: Text(label,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold)),
                ),
                if (servicio['fn_alta_demanda'] == true) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
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

            // ── Recogidas ─────────────────────────────────────────────
            ...recogidas.map((r) {
              final tipo = r['tipo']?.toString() ?? '';
              final num = r['numero']?.toString() ?? '';
              final nombre = r['nombre']?.toString() ?? '';
              final cobertura = r['cobertura']?.toString() ?? '';
              final texto = tipo == 'FN' && num.isNotEmpty
                  ? 'FN$num — $nombre'
                  : nombre;
              return Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Row(
                  children: [
                    Icon(Icons.local_pharmacy,
                        size: 13, color: Colors.indigo[300]),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(texto,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 12),
                          overflow: TextOverflow.ellipsis),
                    ),
                    if (cobertura == 'fuera' ||
                        cobertura == 'por_evaluar')
                      const Padding(
                        padding: EdgeInsets.only(left: 4),
                        child: Text('⚠', style: TextStyle(fontSize: 11)),
                      ),
                  ],
                ),
              );
            }),

            // ── Destino ───────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Row(
                children: [
                  const Icon(Icons.place, size: 13, color: Colors.white38),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(destino,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ),

            // ── Detalles factura ──────────────────────────────────────
            if (servicio['fn_factura_numero'] != null ||
                servicio['fn_pagar_producto'] == true) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: [
                  if (servicio['fn_factura_numero'] != null)
                    _chip('Fac. ${servicio['fn_factura_numero']}',
                        Colors.blueGrey),
                  if (servicio['fn_factura_valor'] != null)
                    _chip(
                        '\$${_miles((servicio['fn_factura_valor'] as num).toInt())}',
                        Colors.blueGrey),
                  if (servicio['fn_pagar_producto'] == true)
                    _chip('PAGAR PRODUCTO', Colors.red[800]!),
                  if (servicio['metodo_pago'] == 'Datafono')
                    _chip('DATÁFONO', Colors.blue[800]!),
                ],
              ),
            ],

            // ── Móvil asignado ────────────────────────────────────────
            if (numMovil != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.two_wheeler,
                      size: 14, color: Colors.white54),
                  const SizedBox(width: 5),
                  Text('Móvil $numMovil',
                      style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.bold)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color, width: 0.7),
        ),
        child: Text(label,
            style: TextStyle(
                color: color,
                fontSize: 9,
                fontWeight: FontWeight.bold)),
      );

  Color _color(String e) => switch (e) {
        'cotizacion' => Colors.orange,
        'cotizada' => Colors.green,
        'pendiente' => Colors.blue,
        'en_ruta_origen' => Colors.indigo,
        'en_origen' => Colors.purple,
        'en_ruta_destino' => Colors.teal,
        'fn_renegociando' => Colors.deepPurple,
        _ => Colors.grey,
      };

  String _labelEstado(String e) => switch (e) {
        'cotizacion' => 'EN COTIZACIÓN',
        'cotizada' => 'PRECIO LISTO',
        'pendiente' => 'BUSCANDO MÓVIL',
        'en_ruta_origen' => 'MÓVIL EN CAMINO',
        'en_origen' => 'MÓVIL EN SEDE',
        'en_ruta_destino' => 'EN RUTA',
        'fn_renegociando' => 'RENEGOCIANDO',
        _ => e.toUpperCase().replaceAll('_', ' '),
      };

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
// TAB 2 — HISTORIAL CONSOLIDADO (FnFacturacionScreen embedded)
// ═══════════════════════════════════════════════════════════════════════════════

class _TabHistorial extends StatefulWidget {
  final SupabaseClient db;
  const _TabHistorial({required this.db});

  @override
  State<_TabHistorial> createState() => _TabHistorialState();
}

class _TabHistorialState extends State<_TabHistorial> {
  List<Map<String, dynamic>> _lista = [];
  bool _cargando = true;
  DateTimeRange? _rango;
  String _filtroEstado = 'todos';
  String _filtroSede = 'todas';
  List<Map<String, dynamic>> _sedes = [];

  @override
  void initState() {
    super.initState();
    _cargarSedes();
    _cargar();
  }

  Future<void> _cargarSedes() async {
    try {
      final data = await widget.db
          .from('fn_sedes')
          .select('id, tipo, numero, nombre');
      final lista = List<Map<String, dynamic>>.from(data);
      lista.sort((a, b) {
        final na = int.tryParse(a['numero']?.toString() ?? '') ?? 999;
        final nb = int.tryParse(b['numero']?.toString() ?? '') ?? 999;
        return na.compareTo(nb);
      });
      setState(() => _sedes = lista);
    } catch (_) {}
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      var q = widget.db
          .from('servicios')
          .select(
              'id, fn_consecutivo, estado, destino, tarifa, fn_factura_numero, '
              'fn_factura_valor, fn_pagar_producto, numero_movil, fn_factura_auto, '
              'created_at, fn_alta_demanda, recogidas, metodo_pago, fn_sede_solicitante_id')
          .eq('fn_origen', 'sede')
          .not('estado', 'in',
              '("cotizacion","cotizada","pendiente","en_ruta_origen","en_origen","en_ruta_destino","fn_renegociando")');

      if (_rango != null) {
        q = q
            .gte('created_at', _rango!.start.toUtc().toIso8601String())
            .lte('created_at', _rango!.end.toUtc().toIso8601String());
      }
      if (_filtroEstado != 'todos') {
        q = q.eq('estado', _filtroEstado);
      }
      if (_filtroSede != 'todas') {
        q = q.eq('fn_sede_solicitante_id', int.tryParse(_filtroSede) ?? 0);
      }

      final data = await q.order('id', ascending: false).limit(200);
      setState(() => _lista = List<Map<String, dynamic>>.from(data));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _cargando = false);
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

  String _fecha(String? raw) {
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
    // KPIs rápidos
    final total = _lista.length;
    final entregados = _lista.where((s) => s['estado'] == 'finalizado').length;
    final valorTotal = _lista
        .where((s) => s['estado'] == 'finalizado' && s['tarifa'] != null)
        .fold<int>(0, (sum, s) => sum + (s['tarifa'] as num).toInt());

    return Column(
      children: [
        // ── Filtros ───────────────────────────────────────────────────────
        Container(
          color: const Color(0xFF0F0F0F),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final (v, l) in [
                            ('todos', 'Todos'),
                            ('finalizado', 'Entregados'),
                            ('cancelado', 'Cancelados'),
                            ('fn_rechazado', 'Rechazados'),
                          ])
                            Padding(
                              padding: const EdgeInsets.only(right: 5),
                              child: ChoiceChip(
                                label: Text(l,
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: _filtroEstado == v
                                            ? Colors.white
                                            : Colors.white54)),
                                selected: _filtroEstado == v,
                                onSelected: (_) {
                                  setState(() => _filtroEstado = v);
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
                    icon: Icon(Icons.date_range,
                        color: _rango != null
                            ? Colors.indigo[300]
                            : Colors.white38,
                        size: 20),
                    onPressed: () async {
                      final r = await showDateRangePicker(
                        context: context,
                        firstDate: DateTime(2024),
                        lastDate: DateTime.now(),
                        initialDateRange: _rango,
                      );
                      if (r != null) {
                        setState(() => _rango = r);
                        _cargar();
                      }
                    },
                  ),
                  if (_rango != null)
                    IconButton(
                      icon: const Icon(Icons.close,
                          color: Colors.white38, size: 16),
                      onPressed: () {
                        setState(() => _rango = null);
                        _cargar();
                      },
                    ),
                ],
              ),
              // Filtro por sede
              if (_sedes.isNotEmpty)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 5),
                        child: ChoiceChip(
                          label: const Text('Todas',
                              style: TextStyle(
                                  fontSize: 11, color: Colors.white54)),
                          selected: _filtroSede == 'todas',
                          onSelected: (_) {
                            setState(() => _filtroSede = 'todas');
                            _cargar();
                          },
                          selectedColor: Colors.indigo[800],
                          backgroundColor: const Color(0xFF1A1A1A),
                          side: BorderSide.none,
                        ),
                      ),
                      ..._sedes.map((s) {
                        final id = s['id'].toString();
                        final label = 'FN${s['numero']}';
                        return Padding(
                          padding: const EdgeInsets.only(right: 5),
                          child: ChoiceChip(
                            label: Text(label,
                                style: TextStyle(
                                    fontSize: 11,
                                    color: _filtroSede == id
                                        ? Colors.white
                                        : Colors.white54)),
                            selected: _filtroSede == id,
                            onSelected: (_) {
                              setState(() => _filtroSede = id);
                              _cargar();
                            },
                            selectedColor: Colors.indigo[800],
                            backgroundColor: const Color(0xFF1A1A1A),
                            side: BorderSide.none,
                          ),
                        );
                      }),
                    ],
                  ),
                ),
            ],
          ),
        ),

        // ── KPIs rápidos ──────────────────────────────────────────────────
        Container(
          color: const Color(0xFF111111),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              _kpi('Total', '$total', Colors.white54),
              const SizedBox(width: 16),
              _kpi('Entregados', '$entregados', Colors.green),
              const SizedBox(width: 16),
              _kpi('Recaudado', '\$${_miles(valorTotal)}', Colors.indigo[300]!),
            ],
          ),
        ),

        // ── Lista ─────────────────────────────────────────────────────────
        Expanded(
          child: _cargando
              ? const Center(
                  child: CircularProgressIndicator(color: Colors.indigo))
              : _lista.isEmpty
                  ? const Center(
                      child: Text('Sin registros',
                          style: TextStyle(color: Colors.white38)))
                  : RefreshIndicator(
                      color: Colors.indigo,
                      onRefresh: _cargar,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(10),
                        itemCount: _lista.length,
                        itemBuilder: (ctx, i) {
                          final s = _lista[i];
                          final estado = s['estado']?.toString() ?? '';
                          final tarifa = (s['tarifa'] as num?)?.toInt();
                          Color borde = estado == 'finalizado'
                              ? Colors.green[800]!
                              : estado == 'cancelado' ||
                                      estado == 'fn_rechazado'
                                  ? Colors.red[800]!
                                  : Colors.grey[700]!;
                          return Card(
                            color: const Color(0xFF111111),
                            margin: const EdgeInsets.only(bottom: 6),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                              side: BorderSide(
                                  color: borde.withValues(alpha: 0.4)),
                            ),
                            child: ListTile(
                              dense: true,
                              title: Row(
                                children: [
                                  Text(
                                    s['fn_consecutivo']?.toString() ??
                                        '#${s['id']}',
                                    style: const TextStyle(
                                        color: Colors.white70,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12),
                                  ),
                                  if (s['fn_factura_numero'] != null) ...[
                                    const SizedBox(width: 6),
                                    Text(
                                      'Fac. ${s['fn_factura_numero']}',
                                      style: const TextStyle(
                                          color: Colors.white38,
                                          fontSize: 11),
                                    ),
                                  ],
                                ],
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    s['destino']?.toString() ?? '—',
                                    style: const TextStyle(
                                        color: Colors.white54,
                                        fontSize: 11),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    _fecha(s['created_at']?.toString()),
                                    style: const TextStyle(
                                        color: Colors.white24,
                                        fontSize: 10),
                                  ),
                                ],
                              ),
                              trailing: tarifa != null
                                  ? Text('\$${_miles(tarifa)}',
                                      style: const TextStyle(
                                          color: Colors.green,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13))
                                  : null,
                            ),
                          );
                        },
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _kpi(String label, String value, Color color) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(color: Colors.white38, fontSize: 10)),
          Text(value,
              style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 14)),
        ],
      );
}

// ═══════════════════════════════════════════════════════════════════════════════
// TAB 3 — DASHBOARD
// ═══════════════════════════════════════════════════════════════════════════════

class _TabDashboard extends StatelessWidget {
  final List<Map<String, dynamic>> todos;
  final SupabaseClient db;
  const _TabDashboard({required this.todos, required this.db});

  String _miles(int v) {
    final s = v.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    // Servicios del día (hoy)
    final hoy = DateTime.now();
    final inicioDia = DateTime(hoy.year, hoy.month, hoy.day).toUtc();

    final deHoy = todos.where((s) {
      try {
        final dt = DateTime.parse(s['created_at'].toString()).toUtc();
        return dt.isAfter(inicioDia);
      } catch (_) {
        return false;
      }
    }).toList();

    final totalHoy = deHoy.length;
    final finalizadosHoy =
        deHoy.where((s) => s['estado'] == 'finalizado').length;
    final canceladosHoy =
        deHoy.where((s) => s['estado'] == 'cancelado').length;
    final enCurso = todos
        .where((s) => [
              'cotizacion',
              'cotizada',
              'pendiente',
              'en_ruta_origen',
              'en_origen',
              'en_ruta_destino'
            ].contains(s['estado']))
        .length;
    final recaudadoHoy = deHoy
        .where((s) => s['estado'] == 'finalizado' && s['tarifa'] != null)
        .fold<int>(0, (sum, s) => sum + (s['tarifa'] as num).toInt());

    // ── Nombre de cada sede por fn_sede_solicitante_id ─────────────────────
    // Escanea TODOS los servicios (no solo hoy) para mapear id → nombre
    final Map<int, String> idANombre = {};
    for (final s in todos) {
      final rawId = s['fn_sede_solicitante_id'];
      if (rawId == null) continue;
      final id = rawId is int ? rawId : int.tryParse(rawId.toString()) ?? -1;
      if (id < 0 || idANombre.containsKey(id)) continue;
      final recog = s['recogidas'];
      if (recog is List) {
        for (final r in recog) {
          if (r is! Map || r['tipo']?.toString() != 'FN') continue;
          final nombre = r['nombre']?.toString() ?? '';
          final num = r['numero']?.toString() ?? '';
          idANombre[id] = nombre.isNotEmpty
              ? nombre
              : (num.isNotEmpty ? 'FN$num' : 'Sede $id');
          break;
        }
      }
      if (!idANombre.containsKey(id)) idANombre[id] = 'Sede $id';
    }

    String _labelSede(dynamic rawId) {
      if (rawId == null) return 'Sin sede';
      final id = rawId is int ? rawId : int.tryParse(rawId.toString()) ?? -1;
      return idANombre[id] ?? 'Sin sede';
    }

    // ── Servicios DIRECTOS por sede (hoy, agrupado por fn_sede_solicitante_id)
    final Map<String, int> porSedeDirecto = {};
    for (final s in deHoy) {
      final label = _labelSede(s['fn_sede_solicitante_id']);
      porSedeDirecto[label] = (porSedeDirecto[label] ?? 0) + 1;
    }

    // ── Recogidas adicionales: cuántas veces aparece cada sede FN
    //    como parada extra en servicios de OTRAS sedes (hoy)
    final Map<String, int> porSedeRecogida = {};
    for (final s in deHoy) {
      final mainLabel = _labelSede(s['fn_sede_solicitante_id']);
      final recog = s['recogidas'];
      if (recog is! List) continue;
      bool primarySaltada = false;
      for (final r in recog) {
        if (r is! Map || r['tipo']?.toString() != 'FN') continue;
        final nombre = r['nombre']?.toString() ?? '';
        final num = r['numero']?.toString() ?? '';
        final label = nombre.isNotEmpty
            ? nombre
            : (num.isNotEmpty ? 'FN$num' : '');
        if (label.isEmpty) continue;
        if (!primarySaltada && label == mainLabel) {
          primarySaltada = true;
          continue; // saltar la recogida principal de esa sede
        }
        porSedeRecogida[label] = (porSedeRecogida[label] ?? 0) + 1;
      }
    }

    final sedesSorted = porSedeDirecto.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── KPIs de hoy ──────────────────────────────────────────────────
          const Text('HOY',
              style: TextStyle(
                  color: Colors.white38,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1)),
          const SizedBox(height: 10),
          LayoutBuilder(builder: (ctx, constraints) {
            final wide = constraints.maxWidth > 500;
            return GridView.count(
              crossAxisCount: wide ? 4 : 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: wide ? 2.2 : 2.4,
              children: [
                _kpiCard('Creados', '$totalHoy', Colors.indigo),
                _kpiCard('En curso', '$enCurso', Colors.blue),
                _kpiCard('Entregados', '$finalizadosHoy', Colors.green),
                _kpiCard('Cancelados', '$canceladosHoy', Colors.red),
              ],
            );
          }),
          const SizedBox(height: 10),
          _kpiCard('Servicios Pagados Hoy', '\$${_miles(recaudadoHoy)}',
              Colors.teal, full: true),

          // ── Por sede ─────────────────────────────────────────────────────
          if (sedesSorted.isNotEmpty) ...[
            const SizedBox(height: 20),
            const Text('SERVICIOS HOY POR SEDE',
                style: TextStyle(
                    color: Colors.white38,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1)),
            const SizedBox(height: 10),
            ...sedesSorted.map((e) {
              final pct =
                  totalHoy > 0 ? e.value / totalHoy : 0.0;
              final recogExtra = porSedeRecogida[e.key] ?? 0;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(e.key,
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 12)),
                        ),
                        Text('${e.value}',
                            style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 12,
                                fontWeight: FontWeight.bold)),
                        if (recogExtra > 0) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.orange.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                  color: Colors.orange.withOpacity(0.3)),
                            ),
                            child: Text(
                              '+$recogExtra recog.',
                              style: const TextStyle(
                                  color: Colors.orange,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    LinearProgressIndicator(
                      value: pct,
                      backgroundColor: Colors.white12,
                      color: Colors.indigo[400],
                      minHeight: 5,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _kpiCard(String label, String value, Color color,
      {bool full = false}) =>
      Container(
        width: full ? double.infinity : null,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label,
                style: TextStyle(
                    color: color.withValues(alpha: 0.7),
                    fontSize: 11)),
            const SizedBox(height: 4),
            Text(value,
                style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: full ? 22 : 18)),
          ],
        ),
      );
}

// ═══════════════════════════════════════════════════════════════════════════════
// TAB 4 — AUDITORÍA DE FACTURAS
// ═══════════════════════════════════════════════════════════════════════════════

class _TabAuditoria extends StatefulWidget {
  final SupabaseClient db;
  const _TabAuditoria({required this.db});

  @override
  State<_TabAuditoria> createState() => _TabAuditoriaState();
}

class _TabAuditoriaState extends State<_TabAuditoria> {
  List<Map<String, dynamic>> _auditorias = [];
  bool _cargando = true;
  DateTimeRange? _rango;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      var q = widget.db
          .from('fn_auditorias_factura')
          .select(
              'id, servicio_id, editor_id, editor_tipo, campo, '
              'valor_anterior, valor_nuevo, created_at, '
              'servicios(fn_consecutivo, fn_factura_numero, fn_factura_valor, '
              'fn_pagar_producto, fn_factura_auto)');

      if (_rango != null) {
        q = q
            .gte('created_at', _rango!.start.toUtc().toIso8601String())
            .lte('created_at', _rango!.end.toUtc().toIso8601String());
      }

      final data = await q.order('id', ascending: false).limit(200);
      setState(() => _auditorias = List<Map<String, dynamic>>.from(data));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  String _fecha(String? raw) {
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

  String _miles(int v) {
    final s = v.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── Filtro fechas ──────────────────────────────────────────────────
        Container(
          color: const Color(0xFF0F0F0F),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              const Text('Auditoría de facturas FN',
                  style: TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                      fontWeight: FontWeight.bold)),
              const Spacer(),
              IconButton(
                icon: Icon(Icons.date_range,
                    color: _rango != null
                        ? Colors.indigo[300]
                        : Colors.white38,
                    size: 20),
                onPressed: () async {
                  final r = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(2024),
                    lastDate: DateTime.now(),
                    initialDateRange: _rango,
                  );
                  if (r != null) {
                    setState(() => _rango = r);
                    _cargar();
                  }
                },
              ),
              if (_rango != null)
                IconButton(
                  icon: const Icon(Icons.close,
                      color: Colors.white38, size: 16),
                  onPressed: () {
                    setState(() => _rango = null);
                    _cargar();
                  },
                ),
            ],
          ),
        ),

        // ── Lista ──────────────────────────────────────────────────────────
        Expanded(
          child: _cargando
              ? const Center(
                  child: CircularProgressIndicator(color: Colors.indigo))
              : _auditorias.isEmpty
                  ? const Center(
                      child: Text('Sin registros de auditoría',
                          style: TextStyle(color: Colors.white38, fontSize: 13)))
                  : RefreshIndicator(
                      color: Colors.indigo,
                      onRefresh: _cargar,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(10),
                        itemCount: _auditorias.length,
                        itemBuilder: (ctx, i) {
                          final a = _auditorias[i];
                          final serv = a['servicios'] as Map<String, dynamic>? ?? {};
                          final campo = a['campo']?.toString() ?? '—';
                          final valorAnterior = a['valor_anterior']?.toString() ?? '—';
                          final valorNuevo = a['valor_nuevo']?.toString() ?? '—';
                          final editorTipo = a['editor_tipo']?.toString() ?? '—';
                          final consecutivo = serv['fn_consecutivo']?.toString() ??
                              '#${a['servicio_id']}';
                          final factNum = serv['fn_factura_numero']?.toString();
                          final factVal = (serv['fn_factura_valor'] as num?)?.toInt();
                          final pagarProd = serv['fn_pagar_producto'] == true;
                          final auto = serv['fn_factura_auto'] == true;

                          return Card(
                            color: const Color(0xFF111111),
                            margin: const EdgeInsets.only(bottom: 6),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                              side: BorderSide(
                                  color: Colors.indigo.withValues(alpha: 0.3)),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // ── Encabezado: consecutivo + campo + fecha ──
                                  Row(
                                    children: [
                                      Text(
                                        consecutivo,
                                        style: const TextStyle(
                                            color: Colors.white70,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.indigo.withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(3),
                                          border: Border.all(
                                              color: Colors.indigo, width: 0.6),
                                        ),
                                        child: Text(
                                          campo.toUpperCase().replaceAll('_', ' '),
                                          style: const TextStyle(
                                              color: Colors.indigo,
                                              fontSize: 9,
                                              fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                      if (auto) ...[
                                        const SizedBox(width: 5),
                                        const Text('AUTO',
                                            style: TextStyle(
                                                color: Colors.teal,
                                                fontSize: 9,
                                                fontWeight: FontWeight.bold)),
                                      ],
                                      const Spacer(),
                                      Text(_fecha(a['created_at']?.toString()),
                                          style: const TextStyle(
                                              color: Colors.white24,
                                              fontSize: 10)),
                                    ],
                                  ),
                                  // ── Cambio: anterior → nuevo ──────────────────
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          valorAnterior,
                                          style: const TextStyle(
                                              color: Colors.red, fontSize: 11),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const Padding(
                                        padding: EdgeInsets.symmetric(horizontal: 6),
                                        child: Icon(Icons.arrow_forward,
                                            color: Colors.white38, size: 12),
                                      ),
                                      Expanded(
                                        child: Text(
                                          valorNuevo,
                                          style: const TextStyle(
                                              color: Colors.green, fontSize: 11),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                  // ── Info factura del servicio ─────────────────
                                  if (factNum != null || factVal != null || pagarProd) ...[
                                    const SizedBox(height: 5),
                                    Wrap(
                                      spacing: 6,
                                      children: [
                                        if (factNum != null)
                                          Text('Fac. $factNum',
                                              style: const TextStyle(
                                                  color: Colors.white38,
                                                  fontSize: 11)),
                                        if (factVal != null)
                                          Text('\$${_miles(factVal)}',
                                              style: const TextStyle(
                                                  color: Colors.green,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold)),
                                        if (pagarProd)
                                          const Text('PAGAR PRODUCTO',
                                              style: TextStyle(
                                                  color: Colors.orange,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold)),
                                      ],
                                    ),
                                  ],
                                  // ── Editor ───────────────────────────────────
                                  const SizedBox(height: 4),
                                  Text(
                                    editorTipo.toUpperCase().replaceAll('_', ' '),
                                    style: const TextStyle(
                                        color: Colors.white24, fontSize: 10),
                                  ),
                                ],
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
}
