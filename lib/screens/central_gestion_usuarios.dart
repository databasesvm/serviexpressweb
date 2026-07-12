part of 'central_screen.dart';
// // Gestión de usuarios (activaciones / rangos)

class _PanelGestionUsuarios extends StatefulWidget {
  final int tabInicial;
  const _PanelGestionUsuarios({this.tabInicial = 0});
  @override
  State<_PanelGestionUsuarios> createState() => _PanelGestionUsuariosState();
}

class _PanelGestionUsuariosState extends State<_PanelGestionUsuarios>
    with SingleTickerProviderStateMixin {
  final _db = Supabase.instance.client;
  late final TabController _tabCtrl;
  final _busqCtrl = TextEditingController();
  String _busq = '';

  List<Map<String, dynamic>> _solicitudes = [];
  List<Map<String, dynamic>> _activaciones = [];
  List<Map<String, dynamic>> _moviles = [];
  List<Map<String, dynamic>> _registros = [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 4, vsync: this, initialIndex: widget.tabInicial);
    _cargar();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _busqCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final hace30 = DateTime.now().subtract(const Duration(days: 30)).toIso8601String();
      final results = await Future.wait([
        _db.from('usuarios')
            .select('id, nombre, usuario, correo, telefono, direccion_local, tipo_negocio, zona_cobertura, created_at')
            .eq('rol', 'local').eq('estado_local', 'pendiente').order('created_at'),
        _db.from('usuarios')
            .select('id, nombre, usuario, rol, telefono, correo, activo, suspendido, created_at')
            .eq('activo', false).neq('suspendido', true).order('created_at'),
        _db.from('usuarios')
            .select('id, nombre, usuario, rango_movil, puntuacion, activo')
            .eq('rol', 'movil').order('nombre'),
        _db.from('usuarios')
            .select('id, nombre, usuario, rol, estado_local, activo, suspendido, created_at')
            .gte('created_at', hace30).order('created_at', ascending: false),
      ]);
      if (!mounted) return;
      setState(() {
        _solicitudes = List<Map<String, dynamic>>.from(results[0] as List);
        _activaciones = List<Map<String, dynamic>>.from(results[1] as List);
        _moviles     = List<Map<String, dynamic>>.from(results[2] as List);
        _registros   = List<Map<String, dynamic>>.from(results[3] as List);
        _cargando = false;
      });
    } catch (_) {
      if (mounted) setState(() => _cargando = false);
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  Color _colorRol(String? rol) {
    switch (rol) {
      case 'local':   return const Color(0xFFF59E0B);
      case 'movil':   return const Color(0xFF3B82F6);
      case 'cliente': return const Color(0xFF22C55E);
      case 'central': return const Color(0xFFA855F7);
      default:        return Colors.grey;
    }
  }

  Color _colorRango(String? r) => switch (r) {
    'NOVATO'  => const Color(0xFF6B7280),
    'PRO'     => const Color(0xFF3B82F6),
    'ÉLITE'   => const Color(0xFFA855F7),
    'LEYENDA' => const Color(0xFFEF8C0E),
    'MASTER'  => const Color(0xFFEF4444),
    _         => Colors.grey,
  };

  String _numMovil(String? usuario) {
    if (usuario == null || usuario.isEmpty) return '';
    final m = RegExp(r'\d+').firstMatch(usuario);
    return m != null ? '#${m.group(0)}' : '';
  }

  String _iniciales(String? n) {
    if (n == null || n.trim().isEmpty) return '?';
    final p = n.trim().split(' ');
    return p.length >= 2 ? '${p[0][0]}${p[1][0]}'.toUpperCase() : n[0].toUpperCase();
  }

  Widget _chip(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withValues(alpha: 0.4)),
    ),
    child: Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600)),
  );

  List<Map<String, dynamic>> _filtrar(List<Map<String, dynamic>> lista) {
    if (_busq.isEmpty) return lista;
    final q = _busq.toLowerCase();
    return lista.where((u) =>
      (u['nombre'] ?? '').toString().toLowerCase().contains(q) ||
      (u['usuario'] ?? '').toString().toLowerCase().contains(q) ||
      (u['rol'] ?? '').toString().toLowerCase().contains(q) ||
      (u['tipo_negocio'] ?? '').toString().toLowerCase().contains(q),
    ).toList();
  }


  // ── Acciones ──────────────────────────────────────────────────────────────
  Future<void> _aprobarLocal(Map<String, dynamic> l) async {
    await _db.from('usuarios').update({'estado_local': 'aprobado', 'motivo_rechazo': null}).eq('id', l['id']);
    _pushLocal(l['id'].toString(), l['nombre']?.toString() ?? '', '✅ ¡Cuenta aprobada!',
        'Tu local "${l['nombre']}" ya está activo en Serviexpress. ¡Bienvenido!', 'local_aprobado');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${l['nombre']} aprobado'), backgroundColor: Colors.green[700]));
    _cargar();
  }

  Future<void> _rechazarLocal(Map<String, dynamic> l) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Rechazar solicitud', style: TextStyle(color: Colors.white, fontSize: 16)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(l['nombre'] ?? '', style: const TextStyle(color: Colors.white54, fontSize: 13)),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl, maxLines: 3,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Motivo del rechazo (opcional)',
              hintStyle: const TextStyle(color: Colors.white30),
              filled: true, fillColor: Colors.white.withValues(alpha: 0.06),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
            ),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar', style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red[700], shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Rechazar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final motivo = ctrl.text.trim().isEmpty ? 'Solicitud no aprobada por Central' : ctrl.text.trim();
    await _db.from('usuarios').update({'estado_local': 'rechazado', 'motivo_rechazo': motivo}).eq('id', l['id']);
    _pushLocal(l['id'].toString(), l['nombre']?.toString() ?? '', '❌ Solicitud no aprobada',
        'Tu solicitud para "${l['nombre']}" no fue aprobada. Contáctanos para más información.', 'local_rechazado');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${l['nombre']} rechazado'), backgroundColor: Colors.red[700]));
    _cargar();
  }

  void _pushLocal(String id, String nombre, String titulo, String cuerpo, String tipo) {
    Supabase.instance.client.functions.invoke('enviar-push', body: {
      'filtros': {'external_id': id},
      'titulo': titulo, 'cuerpo': cuerpo, 'data': {'tipo': tipo},
    }).ignore();
  }

  Future<void> _activarUsuario(Map<String, dynamic> u) async {
    await _db.from('usuarios').update({'activo': true}).eq('id', u['id']);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${u['nombre']} activado'), backgroundColor: Colors.green[700]));
    _cargar();
  }

  Future<void> _cambiarRango(Map<String, dynamic> u, String rango) async {
    try {
      await _db.from('usuarios').update({'rango_movil': rango}).eq('id', u['id']);
      final idx = _moviles.indexWhere((m) => m['id'] == u['id']);
      if (idx >= 0 && mounted) {
        setState(() => _moviles[idx] = {..._moviles[idx], 'rango_movil': rango});
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${u['nombre']} ascendido a $rango'),
          backgroundColor: const Color(0xFF3B82F6),
          duration: const Duration(seconds: 2),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red[800]));
      }
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: NestedScrollView(
        headerSliverBuilder: (ctx, _) => [
          SliverAppBar(
            pinned: true,
            backgroundColor: const Color(0xFF0A0A0A),
            iconTheme: const IconThemeData(color: Colors.white),
            expandedHeight: _cargando ? 60 : 132,
            title: const Text('Gestión de Usuarios',
                style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
            centerTitle: false,
            actions: [IconButton(icon: const Icon(Icons.refresh_rounded, color: Colors.white60), onPressed: _cargar)],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                    colors: [Color(0xFF0D1520), Color(0xFF0A0A0A)]),
                ),
                padding: const EdgeInsets.fromLTRB(16, 60, 16, 10),
                child: _cargando ? const SizedBox() : Row(children: [
                  _statBox('${_solicitudes.length}', 'Solicitudes', const Color(0xFFF59E0B), onTap: () => _tabCtrl.animateTo(0)),
                  const SizedBox(width: 8),
                  _statBox('${_activaciones.length}', 'Por activar', const Color(0xFF3B82F6), onTap: () => _tabCtrl.animateTo(1)),
                  const SizedBox(width: 8),
                  _statBox('${_moviles.length}', 'Móviles', const Color(0xff3AF500), onTap: () => _tabCtrl.animateTo(2)),
                  const SizedBox(width: 8),
                  _statBox('${_registros.length}', 'Recientes', const Color(0xFFA855F7), onTap: () => _tabCtrl.animateTo(3)),
                ]),
              ),
            ),
            bottom: TabBar(
              controller: _tabCtrl,
              indicatorColor: const Color(0xff3AF500),
              indicatorWeight: 2,
              labelColor: const Color(0xff3AF500),
              unselectedLabelColor: Colors.white38,
              labelStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
              unselectedLabelStyle: const TextStyle(fontSize: 10),
              tabs: [
                Tab(text: _solicitudes.isEmpty ? 'Solicitudes' : 'Solicitudes (${_solicitudes.length})'),
                Tab(text: _activaciones.isEmpty ? 'Activar'     : 'Activar (${_activaciones.length})'),
                const Tab(text: 'Ascensos'),
                const Tab(text: 'Recientes'),
              ],
            ),
          ),
        ],
        body: _cargando
          ? const Center(child: CircularProgressIndicator(color: Color(0xff3AF500)))
          : Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                child: TextField(
                  controller: _busqCtrl,
                  onChanged: (v) => setState(() => _busq = v),
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Buscar por nombre, usuario o tipo...',
                    hintStyle: const TextStyle(color: Colors.white30, fontSize: 12),
                    prefixIcon: const Icon(Icons.search_rounded, color: Colors.white30, size: 18),
                    suffixIcon: _busq.isNotEmpty
                      ? IconButton(icon: const Icon(Icons.close_rounded, color: Colors.white30, size: 16),
                          onPressed: () { _busqCtrl.clear(); setState(() => _busq = ''); })
                      : null,
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.06),
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Expanded(child: TabBarView(controller: _tabCtrl, children: [
                _tabSolicitudes(),
                _tabActivaciones(),
                _tabAscensos(),
                _tabRecientes(),
              ])),
            ]),
      ),
    );
  }

  Widget _statBox(String val, String label, Color color, {VoidCallback? onTap}) => Expanded(
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 7),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(val, style: TextStyle(color: color, fontSize: 17, fontWeight: FontWeight.bold)),
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 8), textAlign: TextAlign.center),
        ]),
      ),
    ),
  );

  // ── Tab 0: Solicitudes de locales ──────────────────────────────────────────
  Widget _tabSolicitudes() {
    final lista = _filtrar(_solicitudes);
    if (lista.isEmpty) return _empty(Icons.store_mall_directory_rounded, 'Sin solicitudes pendientes');
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 24),
      itemCount: lista.length,
      itemBuilder: (_, i) {
        final l = lista[i];
        final fecha = l['created_at'] != null ? DateTime.tryParse(l['created_at'].toString()) : null;
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF141414),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.3)),
          ),
          child: Column(children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [const Color(0xFFF59E0B).withValues(alpha: 0.12), Colors.transparent]),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                  child: Text(_iniciales(l['nombre']), style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 15, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(l['nombre'] ?? '—', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
                  Text('@${l['usuario'] ?? ''}', style: const TextStyle(color: Colors.white54, fontSize: 11)),
                ])),
                if (fecha != null) Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('${fecha.day}/${fecha.month}/${fecha.year}', style: const TextStyle(color: Colors.white38, fontSize: 10)),
                  Text('${fecha.hour}:${fecha.minute.toString().padLeft(2,'0')}', style: const TextStyle(color: Colors.white24, fontSize: 9)),
                ]),
              ]),
            ),
            // Info rows
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Column(children: [
                if ((l['tipo_negocio'] ?? '').toString().isNotEmpty) _infoR(Icons.category_outlined, l['tipo_negocio'].toString(), const Color(0xFFF59E0B)),
                if ((l['direccion_local'] ?? '').toString().isNotEmpty) _infoR(Icons.location_on_outlined, l['direccion_local'].toString(), Colors.white38),
                if ((l['zona_cobertura'] ?? '').toString().isNotEmpty) _infoR(Icons.map_outlined, 'Zona: ${l['zona_cobertura']}', Colors.white38),
                if ((l['telefono'] ?? '').toString().isNotEmpty) _infoR(Icons.phone_outlined, l['telefono'].toString(), Colors.white38),
                if ((l['correo'] ?? '').toString().isNotEmpty) _infoR(Icons.email_outlined, l['correo'].toString(), Colors.white38),
              ]),
            ),
            // Buttons
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Row(children: [
                Expanded(child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red[400], side: BorderSide(color: Colors.red[900]!),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  icon: const Icon(Icons.close_rounded, size: 15),
                  label: const Text('Rechazar', style: TextStyle(fontSize: 12)),
                  onPressed: () => _rechazarLocal(l),
                )),
                const SizedBox(width: 10),
                Expanded(child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[700],
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  icon: const Icon(Icons.check_rounded, size: 15),
                  label: const Text('Aprobar', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  onPressed: () => _aprobarLocal(l),
                )),
              ]),
            ),
          ],
        ),
        );
      },
    );
  }

  // ── Helper: fila de info con icono ───────────────────────────────────────
  Widget _infoR(IconData icon, String text, Color color) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(children: [
      Icon(icon, size: 13, color: color),
      const SizedBox(width: 6),
      Expanded(child: Text(text, style: TextStyle(color: color, fontSize: 12), overflow: TextOverflow.ellipsis)),
    ]),
  );

  // ── Helper: pantalla vacía ────────────────────────────────────────────────
  Widget _empty(IconData icon, String msg) => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 48, color: Colors.white12),
      const SizedBox(height: 10),
      Text(msg, style: const TextStyle(color: Colors.white38, fontSize: 13)),
    ]),
  );

  // ── Tab 1: Activaciones pendientes (usuarios inactivos no suspendidos) ────
  Widget _tabActivaciones() {
    final lista = _filtrar(_activaciones);
    if (lista.isEmpty) return _empty(Icons.how_to_reg_rounded, 'Sin activaciones pendientes');
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 24),
      itemCount: lista.length,
      itemBuilder: (_, i) {
        final u = lista[i];
        final rol = u['rol']?.toString() ?? '';
        final color = _colorRol(rol);
        final numMovil = rol == 'movil' ? _numMovil(u['usuario']?.toString()) : '';
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF141414),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.25)),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            leading: CircleAvatar(
              radius: 20,
              backgroundColor: numMovil.isNotEmpty ? color : color.withValues(alpha: 0.15),
              child: numMovil.isNotEmpty
                  ? Text(numMovil, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10))
                  : Text(_iniciales(u['nombre']), style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
            ),
            title: Text(u['nombre'] ?? '—', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
            subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if ((u['usuario'] ?? '').toString().isNotEmpty)
                Text('@${u["usuario"]}', style: const TextStyle(color: Colors.white54, fontSize: 11)),
              _chip(rol.toUpperCase(), color),
            ]),
            trailing: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green[700],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
              onPressed: () => _activarUsuario(u),
              child: const Text('ACTIVAR'),
            ),
          ),
        );
      },
    );
  }

  // ── Tab 2: Ascensos / gestión de rangos de móviles ───────────────────────
  Widget _tabAscensos() {
    final lista = _filtrar(_moviles);
    if (lista.isEmpty) return _empty(Icons.military_tech_rounded, 'Sin móviles registrados');
    const rangos = ['NOVATO', 'PRO', 'ÉLITE', 'LEYENDA', 'MASTER'];
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 24),
      itemCount: lista.length,
      itemBuilder: (_, i) {
        final u = lista[i];
        final rangoActual = u['rango_movil']?.toString();
        final rc = _colorRango(rangoActual);
        final numMovil = _numMovil(u['usuario']?.toString());
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF141414),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: rc.withValues(alpha: 0.25)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: numMovil.isNotEmpty ? rc : rc.withValues(alpha: 0.15),
                  child: numMovil.isNotEmpty
                      ? Text(numMovil, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10))
                      : Text(_iniciales(u['nombre']),
                          style: TextStyle(color: rc, fontWeight: FontWeight.bold, fontSize: 12)),
                ),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(u['nombre'] ?? '—', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                  Text('@${u['usuario'] ?? ''}', style: const TextStyle(color: Colors.white38, fontSize: 11)),
                ])),
                if (rangoActual != null && rangoActual.isNotEmpty)
                  _chip(rangoActual, rc),
              ]),
              const SizedBox(height: 10),
              Wrap(spacing: 6, runSpacing: 6, children: rangos.map((r) {
                final activo = rangoActual == r;
                final rangoColor = _colorRango(r);
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _cambiarRango(u, r),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: activo ? rangoColor : Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: activo ? rangoColor : rangoColor.withValues(alpha: 0.4)),
                    ),
                    child: Text(r,
                        style: TextStyle(
                          color: activo ? Colors.white : rangoColor.withValues(alpha: 0.85),
                          fontSize: 11, fontWeight: activo ? FontWeight.bold : FontWeight.normal)),
                  ),
                );
              }).toList()),
            ]),
          ),
        );
      },
    );
  }

  // ── Tab 3: Registros recientes (últimos 30 días) ──────────────────────────
  Widget _tabRecientes() {
    final lista = _filtrar(_registros);
    if (lista.isEmpty) return _empty(Icons.person_add_rounded, 'Sin registros en los últimos 30 días');
    return Column(children: [
      Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(14, 8, 14, 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          'Usuarios que se registraron en los últimos 30 días. '
          '"Activo" significa que ya pueden iniciar sesión.',
          style: const TextStyle(color: Colors.white38, fontSize: 11),
        ),
      ),
      Expanded(
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 24),
          itemCount: lista.length,
          itemBuilder: (_, i) {
            final u = lista[i];
            final rol = u['rol']?.toString() ?? '';
            final color = _colorRol(rol);
            final activo = u['activo'] as bool? ?? false;
            final suspendido = u['suspendido'] as bool? ?? false;
            final numMovil = rol == 'movil' ? _numMovil(u['usuario']?.toString()) : '';
            final String estado;
            if (suspendido) {
              estado = 'SUSPENDIDO';
            } else if (activo) {
              estado = 'ACTIVO';
            } else {
              estado = 'PENDIENTE';
            }
            final estadoColor = suspendido
                ? Colors.red[400]!
                : activo
                    ? Colors.green[400]!
                    : Colors.orange[400]!;
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF141414),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: color.withValues(alpha: 0.25)),
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                leading: CircleAvatar(
                  radius: 20,
                  backgroundColor: numMovil.isNotEmpty ? color : color.withValues(alpha: 0.15),
                  child: numMovil.isNotEmpty
                      ? Text(numMovil, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10))
                      : Text(_iniciales(u['nombre']), style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
                ),
                title: Text(u['nombre'] ?? '—', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if ((u['usuario'] ?? '').toString().isNotEmpty)
                    Text('@${u["usuario"]}', style: const TextStyle(color: Colors.white54, fontSize: 11)),
                  Row(children: [
                    _chip(rol.toUpperCase(), color),
                    const SizedBox(width: 6),
                    _chip(estado, estadoColor),
                  ]),
                ]),
              ),
            );
          },
        ),
      ),
    ]);
  }
}
