// ignore_for_file: use_build_context_synchronously
part of 'central_screen.dart';

// ══════════════════════════════════════════════════════════════════════════════
// RED DE DIRECCIONES SE — por usuario (local / cliente)
// Tabs: Direcciones guardadas | Tarifas por Sector
// ══════════════════════════════════════════════════════════════════════════════

class _PanelRedSe extends StatefulWidget {
  const _PanelRedSe();

  @override
  State<_PanelRedSe> createState() => _PanelRedSeState();
}

class _PanelRedSeState extends State<_PanelRedSe>
    with SingleTickerProviderStateMixin {
  // ── Datos globales ──────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _usuarios = [];
  List<Map<String, dynamic>> _sectores = [];
  bool _cargandoInicial = true;

  // ── Usuario seleccionado ────────────────────────────────────────────────────
  Map<String, dynamic>? _userSel;
  List<Map<String, dynamic>> _dirs    = [];
  List<Map<String, dynamic>> _tarifas = [];
  bool _cargandoUser = false;

  // ── Filtro direcciones ──────────────────────────────────────────────────────
  String _filtroMun = 'Todos';

  late final TabController _tab;

  // ── Municipios disponibles ──────────────────────────────────────────────────
  static const _municipios = ['Todos', 'Cúcuta', 'Los Patios', 'V. Rosario'];

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _cargarInicial();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  // ── Carga inicial: usuarios + sectores ──────────────────────────────────────
  Future<void> _cargarInicial() async {
    setState(() => _cargandoInicial = true);
    try {
      final usuarios = await Supabase.instance.client
          .from('usuarios')
          .select('id, nombre, rol, usuario')
          .inFilter('rol', ['local', 'cliente'])
          .eq('activo', true)
          .order('nombre');

      final sectores = await Supabase.instance.client
          .from('sectores')
          .select('id, nombre, municipio')
          .eq('activo', true)
          .order('nombre');

      if (mounted) {
        setState(() {
          _usuarios = List<Map<String, dynamic>>.from(usuarios);
          _sectores = List<Map<String, dynamic>>.from(sectores);
          _cargandoInicial = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _cargandoInicial = false);
    }
  }

  // ── Carga datos del usuario seleccionado ────────────────────────────────────
  Future<void> _cargarUser(int userId) async {
    setState(() => _cargandoUser = true);
    try {
      final dirs = await Supabase.instance.client
          .from('dir_usuario')
          .select('id, nombre, municipio, sector_id, precio, activo, sectores(nombre)')
          .eq('usuario_id', userId)
          .order('nombre');

      final tarifas = await Supabase.instance.client
          .from('tarifas_usuario_sector')
          .select('sector_id, precio')
          .eq('usuario_id', userId);

      if (mounted) {
        setState(() {
          _dirs    = List<Map<String, dynamic>>.from(dirs);
          _tarifas = List<Map<String, dynamic>>.from(tarifas);
          _cargandoUser = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _cargandoUser = false);
    }
  }

  // ── Etiqueta de usuario ─────────────────────────────────────────────────────
  String _etiqueta(Map<String, dynamic> u) {
    final rol  = u['rol'] as String? ?? '';
    final nom  = u['nombre']?.toString() ?? '';
    final tipo = rol == 'local' ? '🏪' : '👤';
    return '$tipo $nom';
  }

  // ══════════════════════════════════════════════════════════════════════════
  // CRUD — DIRECCIONES
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> _formDir({Map<String, dynamic>? existing}) async {
    final nomCtrl    = TextEditingController(text: existing?['nombre'] ?? '');
    final precioCtrl = TextEditingController(text: existing?['precio']?.toString() ?? '');
    String mun       = existing?['municipio'] ?? 'Cúcuta';
    int?   sectorId  = existing?['sector_id'] as int?;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDlg) {
        final sectoresFilt = _sectores.where((s) => s['municipio'] == mun).toList();
        if (!sectoresFilt.any((s) => s['id'] == sectorId)) sectorId = null;

        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: Text(
            existing != null ? 'Editar dirección' : 'Nueva dirección',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: nomCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nombre / Dirección',
                  isDense: true, border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: mun,
                decoration: const InputDecoration(
                  labelText: 'Municipio',
                  isDense: true, border: OutlineInputBorder(),
                ),
                items: ['Cúcuta', 'Los Patios', 'V. Rosario']
                    .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                    .toList(),
                onChanged: (v) => setDlg(() { mun = v!; sectorId = null; }),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<int>(
                value: sectorId,
                decoration: const InputDecoration(
                  labelText: 'Sector (opcional)',
                  isDense: true, border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem(value: null, child: Text('— Sin sector —')),
                  ...sectoresFilt.map((s) => DropdownMenuItem<int>(
                    value: s['id'] as int,
                    child: Text(s['nombre']?.toString() ?? ''),
                  )),
                ],
                onChanged: (v) => setDlg(() => sectorId = v),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: precioCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Precio (\$)',
                  isDense: true, border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.attach_money, size: 18),
                ),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCELAR')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.black),
              onPressed: () async {
                final nom   = nomCtrl.text.trim();
                final precio = int.tryParse(precioCtrl.text.trim());
                if (nom.isEmpty) return;
                final userId = _userSel!['id'] as int;
                final payload = {
                  'usuario_id': userId,
                  'nombre':     nom,
                  'municipio':  mun,
                  'sector_id':  sectorId,
                  'precio':     precio,
                };
                if (existing != null) {
                  await Supabase.instance.client
                      .from('dir_usuario')
                      .update(payload)
                      .eq('id', existing['id']);
                } else {
                  await Supabase.instance.client
                      .from('dir_usuario')
                      .insert(payload);
                }
                if (ctx.mounted) Navigator.pop(ctx);
                await _cargarUser(userId);
              },
              child: Text(
                existing != null ? 'GUARDAR' : 'AGREGAR',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        );
      }),
    );
    nomCtrl.dispose(); precioCtrl.dispose();
  }

  Future<void> _eliminarDir(int id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Eliminar dirección?',
            style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCELAR')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ELIMINAR', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await Supabase.instance.client.from('dir_usuario').delete().eq('id', id);
    await _cargarUser(_userSel!['id'] as int);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // CRUD — TARIFAS POR SECTOR
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> _upsertTarifa(int sectorId, String val) async {
    final precio = int.tryParse(val.trim());
    if (precio == null || precio <= 0) return;
    final userId = _userSel!['id'] as int;
    await Supabase.instance.client.from('tarifas_usuario_sector').upsert(
      {'usuario_id': userId, 'sector_id': sectorId, 'precio': precio},
      onConflict: 'usuario_id, sector_id',
    );
    await _cargarUser(userId);
  }

  Future<void> _eliminarTarifa(int sectorId) async {
    final userId = _userSel!['id'] as int;
    await Supabase.instance.client
        .from('tarifas_usuario_sector')
        .delete()
        .eq('usuario_id', userId)
        .eq('sector_id', sectorId);
    await _cargarUser(userId);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Red de Direcciones SE',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        bottom: _userSel != null
            ? TabBar(
                controller: _tab,
                labelColor: const Color(0xff3AF500),
                unselectedLabelColor: Colors.white54,
                indicatorColor: const Color(0xff3AF500),
                tabs: const [
                  Tab(icon: Icon(Icons.place, size: 16), text: 'Direcciones'),
                  Tab(icon: Icon(Icons.price_change, size: 16), text: 'Tarifas por Sector'),
                ],
              )
            : null,
      ),
      body: _cargandoInicial
          ? const Center(child: CircularProgressIndicator(color: Color(0xff3AF500)))
          : Column(children: [
              _buildUserSelector(),
              if (_userSel == null)
                const Expanded(
                  child: Center(
                    child: Text(
                      'Selecciona un usuario para gestionar\nsu red de direcciones',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white38, fontSize: 14),
                    ),
                  ),
                )
              else if (_cargandoUser)
                const Expanded(child: Center(child: CircularProgressIndicator(color: Color(0xff3AF500))))
              else
                Expanded(
                  child: TabBarView(
                    controller: _tab,
                    children: [
                      _buildTabDirecciones(),
                      _buildTabTarifas(),
                    ],
                  ),
                ),
            ]),
      floatingActionButton: _userSel != null
          ? FloatingActionButton(
              backgroundColor: const Color(0xff3AF500),
              onPressed: () async {
                if (_tab.index == 0) {
                  await _formDir();
                } else {
                  _mostrarAyudaTarifas();
                }
              },
              child: Icon(
                _tab.index == 0 ? Icons.add_location_alt : Icons.info_outline,
                color: Colors.black,
              ),
            )
          : null,
    );
  }

  // ── Selector de usuario ─────────────────────────────────────────────────────
  Widget _buildUserSelector() {
    return Container(
      color: const Color(0xFF111111),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: DropdownButtonFormField<int>(
        value: _userSel?['id'] as int?,
        dropdownColor: const Color(0xFF1A1A1A),
        style: const TextStyle(color: Colors.white, fontSize: 13),
        decoration: InputDecoration(
          labelText: 'Usuario (local / cliente)',
          labelStyle: const TextStyle(color: Colors.white54, fontSize: 12),
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Colors.white24),
          ),
          prefixIcon: const Icon(Icons.person_search, color: Colors.white38, size: 18),
        ),
        items: _usuarios.map((u) => DropdownMenuItem<int>(
          value: u['id'] as int,
          child: Text(_etiqueta(u),
              style: const TextStyle(color: Colors.white, fontSize: 13)),
        )).toList(),
        onChanged: (id) {
          final u = _usuarios.firstWhere((u) => u['id'] == id);
          setState(() { _userSel = u; _dirs = []; _tarifas = []; });
          _cargarUser(id!);
        },
        hint: const Text('Selecciona un usuario…',
            style: TextStyle(color: Colors.white38, fontSize: 13)),
      ),
    );
  }

  // ── Tab: Direcciones ────────────────────────────────────────────────────────
  Widget _buildTabDirecciones() {
    // Filtro municipio
    final filtrados = _filtroMun == 'Todos'
        ? _dirs
        : _dirs.where((d) => d['municipio'] == _filtroMun).toList();

    return Column(children: [
      // Chips filtro
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
        child: Row(
          children: _municipios.map((m) {
            final sel = _filtroMun == m;
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text(m, style: TextStyle(fontSize: 11, color: sel ? Colors.black : Colors.white70)),
                selected: sel,
                selectedColor: const Color(0xff3AF500),
                backgroundColor: const Color(0xFF222222),
                onSelected: (_) => setState(() => _filtroMun = m),
              ),
            );
          }).toList(),
        ),
      ),
      // Lista
      Expanded(
        child: filtrados.isEmpty
            ? Center(
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.add_location_alt, color: Colors.white24, size: 48),
                  const SizedBox(height: 12),
                  const Text('Sin direcciones guardadas',
                      style: TextStyle(color: Colors.white38)),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xff3AF500)),
                    onPressed: () => _formDir(),
                    icon: const Icon(Icons.add, color: Colors.black, size: 16),
                    label: const Text('Agregar', style: TextStyle(color: Colors.black)),
                  ),
                ]),
              )
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 80),
                itemCount: filtrados.length,
                itemBuilder: (_, i) {
                  final d = filtrados[i];
                  final sectorNom = (d['sectores'] as Map?)
                          ?['nombre']
                          ?.toString() ??
                      '';
                  final precio = d['precio'] as int?;
                  return Card(
                    color: const Color(0xFF1A1A1A),
                    margin: const EdgeInsets.only(bottom: 6),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                      leading: CircleAvatar(
                        backgroundColor: const Color(0xff3AF500).withValues(alpha: 0.15),
                        child: const Icon(Icons.place, color: Color(0xff3AF500), size: 18),
                      ),
                      title: Text(
                        d['nombre']?.toString() ?? '',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                      subtitle: Text(
                        [d['municipio'], if (sectorNom.isNotEmpty) sectorNom].join(' · '),
                        style: const TextStyle(color: Colors.white54, fontSize: 11),
                      ),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        if (precio != null)
                          Container(
                            margin: const EdgeInsets.only(right: 4),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.green[900],
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '\$${_fmt(precio)}',
                              style: const TextStyle(color: Color(0xff3AF500), fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          ),
                        IconButton(
                          icon: const Icon(Icons.edit, color: Colors.blue, size: 18),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                          onPressed: () => _formDir(existing: d),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.red, size: 18),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                          onPressed: () => _eliminarDir(d['id'] as int),
                        ),
                      ]),
                    ),
                  );
                },
              ),
      ),
    ]);
  }

  // ── Tab: Tarifas por Sector ─────────────────────────────────────────────────
  Widget _buildTabTarifas() {
    // Build a map: sectorId → precio
    final tarifaMap = {
      for (final t in _tarifas) t['sector_id'] as int: t['precio'] as int,
    };

    // Group sectors by municipio
    final municipios = _sectores.map((s) => s['municipio'] as String).toSet().toList()..sort();

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
      children: [
        for (final mun in municipios) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
            child: Text(mun.toUpperCase(),
                style: const TextStyle(color: Colors.white38, fontSize: 11, letterSpacing: 1.2)),
          ),
          ...(_sectores.where((s) => s['municipio'] == mun).map((s) {
            final sId  = s['id'] as int;
            final nom  = s['nombre']?.toString() ?? '';
            final pre  = tarifaMap[sId];
            final ctrl = TextEditingController(text: pre?.toString() ?? '');
            return Card(
              color: const Color(0xFF1A1A1A),
              margin: const EdgeInsets.only(bottom: 6),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Row(children: [
                  Expanded(
                    child: Text(nom,
                        style: const TextStyle(color: Colors.white, fontSize: 13)),
                  ),
                  SizedBox(
                    width: 90,
                    child: TextField(
                      controller: ctrl,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      textAlign: TextAlign.right,
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: 'Sin tarifa',
                        hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
                        filled: true,
                        fillColor: const Color(0xFF2A2A2A),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide(
                            color: pre != null ? const Color(0xff3AF500).withValues(alpha: 0.4) : Colors.white12,
                          ),
                        ),
                        prefixText: '\$ ',
                        prefixStyle: const TextStyle(color: Colors.white54, fontSize: 12),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      ),
                      onSubmitted: (v) => _upsertTarifa(sId, v),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: Icon(
                      pre != null ? Icons.check_circle : Icons.radio_button_unchecked,
                      color: pre != null ? const Color(0xff3AF500) : Colors.white24,
                      size: 18,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    onPressed: pre != null ? () => _eliminarTarifa(sId) : null,
                    tooltip: pre != null ? 'Quitar tarifa' : 'Sin tarifa',
                  ),
                ]),
              ),
            );
          })),
        ],
      ],
    );
  }

  void _mostrarAyudaTarifas() {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Escribe el precio y presiona Enter para guardar. Toca ✓ para quitar la tarifa.'),
      backgroundColor: Colors.black87,
      duration: Duration(seconds: 4),
    ));
  }

  String _fmt(int v) {
    final s = v.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}
