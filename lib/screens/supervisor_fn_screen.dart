// ignore_for_file: use_build_context_synchronously
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';

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
    _tab = TabController(length: 4, vsync: this);
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
        backgroundColor: const Color(0xFF1A237E),
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
        bottom: TabBar(
          controller: _tab,
          indicatorColor: Colors.indigo[200],
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white54,
          isScrollable: true,
          tabs: const [
            Tab(icon: Icon(Icons.live_tv_outlined), text: 'En vivo'),
            Tab(icon: Icon(Icons.history_rounded), text: 'Historial'),
            Tab(icon: Icon(Icons.bar_chart_rounded), text: 'Dashboard'),
            Tab(icon: Icon(Icons.fact_check_outlined), text: 'Auditoría'),
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
              _TabHistorial(db: _db),
              _TabDashboard(todos: todos, db: _db),
              _TabAuditoria(db: _db),
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

    return Card(
      color: const Color(0xFF0F0F0F),
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: color.withValues(alpha: 0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(consec,
                    style: const TextStyle(
                        color: Colors.white38, fontSize: 11)),
                const SizedBox(width: 8),
                _chip(_labelEstado(estado), color),
                if (servicio['fn_alta_demanda'] == true) ...[
                  const SizedBox(width: 6),
                  _chip('ALTA DEMANDA', Colors.orange[700]!),
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
            const SizedBox(height: 6),
            ...recogidas.map((r) {
              final tipo = r['tipo']?.toString() ?? '';
              final num = r['numero']?.toString() ?? '';
              final nombre = r['nombre']?.toString() ?? '';
              return Text(
                '🏥 ${tipo == 'FN' && num.isNotEmpty ? 'FN$num — $nombre' : nombre}',
                style: const TextStyle(color: Colors.white60, fontSize: 12),
              );
            }),
            Text('🏁 $destino',
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13)),
            if (numMovil != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('🏍 Móvil $numMovil',
                    style: const TextStyle(
                        color: Colors.white54, fontSize: 11)),
              ),
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
// TAB 2 — HISTORIAL CONSOLIDADO
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
          .select('id, tipo, numero, nombre')
          .order('numero');
      setState(() => _sedes = List<Map<String, dynamic>>.from(data));
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

    // Agrupación por sede
    final Map<String, int> porSede = {};
    for (final s in deHoy) {
      final recog = s['recogidas'];
      String sedeKey = 'Sin sede';
      if (recog is List && recog.isNotEmpty) {
        final r = recog.first as Map<String, dynamic>;
        final tipo = r['tipo']?.toString() ?? '';
        final num = r['numero']?.toString() ?? '';
        sedeKey = tipo == 'FN' && num.isNotEmpty ? 'FN$num' : (r['nombre'] ?? 'Sin sede');
      }
      porSede[sedeKey] = (porSede[sedeKey] ?? 0) + 1;
    }
    final sedesSorted = porSede.entries.toList()
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
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 2.4,
            children: [
              _kpiCard('Servicios creados', '$totalHoy', Colors.indigo),
              _kpiCard('En curso', '$enCurso', Colors.blue),
              _kpiCard('Entregados', '$finalizadosHoy', Colors.green),
              _kpiCard('Cancelados', '$canceladosHoy', Colors.red),
            ],
          ),
          const SizedBox(height: 12),
          _kpiCard('Recaudado hoy', '\$${_miles(recaudadoHoy)}', Colors.teal,
              full: true),

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
              final pct = totalHoy > 0 ? e.value / totalHoy : 0.0;
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
              'id, servicio_id, fn_consecutivo, sede_id, movil_id, '
              'fn_factura_numero, fn_factura_valor, fn_pagar_producto, '
              'fn_factura_auto, accion, actor_tipo, actor_id, '
              'notas, created_at');

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
                          final accion = a['accion']?.toString() ?? '—';
                          final auto = a['fn_factura_auto'] == true;
                          final factNum = a['fn_factura_numero']?.toString();
                          final factVal = (a['fn_factura_valor'] as num?)?.toInt();
                          final pagarProd = a['fn_pagar_producto'] == true;
                          final notas = a['notas']?.toString() ?? '';

                          Color accionColor = switch (accion) {
                            'entregado' => Colors.green,
                            'cancelado' => Colors.red,
                            'factura_auto' => Colors.indigo,
                            'problema' => Colors.orange,
                            _ => Colors.grey,
                          };

                          return Card(
                            color: const Color(0xFF111111),
                            margin: const EdgeInsets.only(bottom: 6),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                              side: BorderSide(
                                  color: accionColor.withValues(alpha: 0.3)),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        a['fn_consecutivo']?.toString() ??
                                            '#${a['servicio_id']}',
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
                                          color: accionColor.withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(3),
                                          border: Border.all(
                                              color: accionColor, width: 0.6),
                                        ),
                                        child: Text(
                                          accion.toUpperCase().replaceAll('_', ' '),
                                          style: TextStyle(
                                              color: accionColor,
                                              fontSize: 9,
                                              fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                      if (auto) ...[
                                        const SizedBox(width: 5),
                                        const Text('✓ AUTO',
                                            style: TextStyle(
                                                color: Colors.indigo,
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
                                                  color: Colors.red,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold)),
                                      ],
                                    ),
                                  ],
                                  if (notas.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(notas,
                                        style: const TextStyle(
                                            color: Colors.white38,
                                            fontSize: 11,
                                            fontStyle: FontStyle.italic)),
                                  ],
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
