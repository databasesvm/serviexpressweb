// ignore_for_file: use_build_context_synchronously
part of 'central_screen.dart';

// ══════════════════════════════════════════════════════════════════════════════
// PANEL DE REPORTES — quejas de clientes y sedes FN durante servicios activos
// ══════════════════════════════════════════════════════════════════════════════

class _PanelReportesBottomSheet extends StatefulWidget {
  const _PanelReportesBottomSheet();

  @override
  State<_PanelReportesBottomSheet> createState() =>
      _PanelReportesBottomSheetState();
}

class _PanelReportesBottomSheetState
    extends State<_PanelReportesBottomSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  bool _cargando = true;
  List<Map<String, dynamic>> _reportes = [];
  // Para la pestaña de horas activas
  bool _cargandoHoras = true;
  List<Map<String, dynamic>> _horasMoviles = [];
  String _filtroOrigen = 'todos'; // 'todos' | 'cliente' | 'fn_sede'

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _cargarReportes();
    _cargarHorasMoviles();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _cargarReportes() async {
    try {
      final rows = await Supabase.instance.client
          .from('reportes_servicio')
          .select('id, servicio_id, movil_id, origen, categoria, nota, created_at')
          .order('created_at', ascending: false)
          .limit(100);
      if (mounted) setState(() { _reportes = List<Map<String, dynamic>>.from(rows); _cargando = false; });
    } catch (_) {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _cargarHorasMoviles() async {
    try {
      final hoy = DateTime.now();
      final fechaHoy =
          '${hoy.year}-${hoy.month.toString().padLeft(2, '0')}-${hoy.day.toString().padLeft(2, '0')}';

      // Sesiones del día
      final sesiones = await Supabase.instance.client
          .from('sesiones_movil')
          .select('movil_id, duracion_minutos')
          .eq('fecha', fechaHoy)
          .not('duracion_minutos', 'is', null);

      // Usuarios móviles
      final usuarios = await Supabase.instance.client
          .from('usuarios')
          .select('id, usuario, nombre, en_linea')
          .eq('rol', 'movil')
          .eq('activo', true);

      // Agrupar minutos por movil_id
      final Map<int, int> minPorMovil = {};
      for (final s in sesiones as List) {
        final mid = s['movil_id'] as int?;
        if (mid == null) continue;
        minPorMovil[mid] = (minPorMovil[mid] ?? 0) + ((s['duracion_minutos'] as num?)?.toInt() ?? 0);
      }

      final List<Map<String, dynamic>> lista = [];
      for (final u in usuarios as List) {
        final id = u['id'] as int;
        lista.add({
          'id': id,
          'usuario': u['usuario'] ?? u['nombre'] ?? 'MOVIl$id',
          'en_linea': u['en_linea'] == true,
          'minutos': minPorMovil[id] ?? 0,
        });
      }
      // Ordenar: más horas arriba
      lista.sort((a, b) => (b['minutos'] as int).compareTo(a['minutos'] as int));

      if (mounted) setState(() { _horasMoviles = lista; _cargandoHoras = false; });
    } catch (_) {
      if (mounted) setState(() => _cargandoHoras = false);
    }
  }

  List<Map<String, dynamic>> get _reportesFiltrados {
    if (_filtroOrigen == 'todos') return _reportes;
    return _reportes.where((r) => r['origen'] == _filtroOrigen).toList();
  }

  String _formatFecha(String? raw) {
    if (raw == null) return '—';
    try {
      final dt = DateTime.parse(raw).toLocal();
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      final d = dt.day.toString().padLeft(2, '0');
      final mo = dt.month.toString().padLeft(2, '0');
      return '$d/$mo ${h}:$m';
    } catch (_) {
      return '—';
    }
  }

  String _formatMinutos(int mins) {
    if (mins == 0) return '—';
    final h = mins ~/ 60;
    final m = mins % 60;
    return h > 0 ? '${h}h ${m.toString().padLeft(2, '0')}m' : '${m}m';
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (ctx, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1A1A1A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Handle
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10, bottom: 8),
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  const Icon(Icons.flag_outlined, color: Colors.orange, size: 20),
                  const SizedBox(width: 8),
                  const Text(
                    'REPORTES Y TIEMPO ACTIVO',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54, size: 18),
                    onPressed: () => Navigator.pop(ctx),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
            // Tabs
            TabBar(
              controller: _tab,
              indicatorColor: Colors.orange,
              labelColor: Colors.orange,
              unselectedLabelColor: Colors.white38,
              labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              tabs: [
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.warning_amber_outlined, size: 14),
                      const SizedBox(width: 4),
                      Text('QUEJAS (${_reportes.length})'),
                    ],
                  ),
                ),
                const Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.access_time_outlined, size: 14),
                      SizedBox(width: 4),
                      Text('HORAS ACTIVAS HOY'),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 1, color: Colors.white12),
            Expanded(
              child: TabBarView(
                controller: _tab,
                children: [
                  _tabQuejas(scrollCtrl),
                  _tabHorasActivas(scrollCtrl),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tabQuejas(ScrollController scrollCtrl) {
    return Column(
      children: [
        // Filtros
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: [
              const Text('Filtrar:', style: TextStyle(color: Colors.white54, fontSize: 11)),
              const SizedBox(width: 8),
              ...[
                ('todos', 'Todos'),
                ('cliente', 'Cliente'),
                ('fn_sede', 'Sede FN'),
              ].map((e) => Padding(
                padding: const EdgeInsets.only(right: 6),
                child: FilterChip(
                  label: Text(e.$2, style: TextStyle(
                    fontSize: 11,
                    color: _filtroOrigen == e.$1 ? Colors.black : Colors.white60,
                  )),
                  selected: _filtroOrigen == e.$1,
                  selectedColor: Colors.orange,
                  backgroundColor: Colors.white12,
                  showCheckmark: false,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  onSelected: (_) => setState(() => _filtroOrigen = e.$1),
                ),
              )),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh, color: Colors.white38, size: 16),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () { setState(() => _cargando = true); _cargarReportes(); },
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: Colors.white12),
        Expanded(
          child: _cargando
              ? const Center(child: CircularProgressIndicator(color: Colors.orange))
              : _reportesFiltrados.isEmpty
                  ? const Center(
                      child: Text('Sin reportes', style: TextStyle(color: Colors.white38)),
                    )
                  : ListView.separated(
                      controller: scrollCtrl,
                      padding: const EdgeInsets.all(12),
                      itemCount: _reportesFiltrados.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, color: Colors.white10),
                      itemBuilder: (_, i) {
                        final r = _reportesFiltrados[i];
                        final esCliente = r['origen'] == 'cliente';
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 6,
                                height: 40,
                                margin: const EdgeInsets.only(right: 10, top: 2),
                                decoration: BoxDecoration(
                                  color: esCliente ? Colors.blue[400] : Colors.indigo[400],
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: esCliente
                                                ? Colors.blue.withValues(alpha: 0.2)
                                                : Colors.indigo.withValues(alpha: 0.2),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            esCliente ? 'CLIENTE' : 'SEDE FN',
                                            style: TextStyle(
                                              fontSize: 9,
                                              fontWeight: FontWeight.bold,
                                              color: esCliente ? Colors.blue[300] : Colors.indigo[300],
                                              letterSpacing: 0.5,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          'Servicio #${r['servicio_id']}',
                                          style: const TextStyle(color: Colors.white70, fontSize: 11),
                                        ),
                                        const Spacer(),
                                        Text(
                                          _formatFecha(r['created_at']?.toString()),
                                          style: const TextStyle(color: Colors.white30, fontSize: 10),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      r['categoria']?.toString() ?? '—',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                    if (r['nota'] != null && r['nota'].toString().isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 2),
                                        child: Text(
                                          r['nota'].toString(),
                                          style: const TextStyle(color: Colors.white54, fontSize: 11),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Widget _tabHorasActivas(ScrollController scrollCtrl) {
    return _cargandoHoras
        ? const Center(child: CircularProgressIndicator(color: Colors.orange))
        : _horasMoviles.isEmpty
            ? const Center(
                child: Text('Sin datos de hoy', style: TextStyle(color: Colors.white38)),
              )
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                    child: Row(
                      children: [
                        const Text(
                          'Acumulado de sesiones cerradas hoy',
                          style: TextStyle(color: Colors.white38, fontSize: 10),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.refresh, color: Colors.white38, size: 16),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () { setState(() => _cargandoHoras = true); _cargarHorasMoviles(); },
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: Colors.white12),
                  Expanded(
                    child: ListView.separated(
                      controller: scrollCtrl,
                      padding: const EdgeInsets.all(12),
                      itemCount: _horasMoviles.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, color: Colors.white10),
                      itemBuilder: (_, i) {
                        final m = _horasMoviles[i];
                        final mins = m['minutos'] as int;
                        final enLinea = m['en_linea'] as bool;
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            children: [
                              Container(
                                width: 8, height: 8,
                                margin: const EdgeInsets.only(right: 10),
                                decoration: BoxDecoration(
                                  color: enLinea ? Colors.green : Colors.white24,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              Text(
                                (m['usuario'] ?? '').toString().toUpperCase(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                              if (enLinea) ...[
                                const SizedBox(width: 6),
                                const Text(
                                  'EN LÍNEA',
                                  style: TextStyle(
                                    color: Colors.green,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                              const Spacer(),
                              Text(
                                _formatMinutos(mins),
                                style: TextStyle(
                                  color: mins > 0 ? Colors.orange[300] : Colors.white30,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );
  }
}
