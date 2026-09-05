// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ─────────────────────────────────────────────────────────────────────────────
// FnRedDireccionesScreen
// Administración: Sectores + Tarifas por sede | Direcciones + Precio por sede
// Sectores y direcciones son un catálogo global compartido entre FN y SE.
// El precio vive por separado en fn_tarifas_sede y fn_precios_dir.
// ─────────────────────────────────────────────────────────────────────────────

class FnRedDireccionesScreen extends StatefulWidget {
  const FnRedDireccionesScreen({super.key});

  @override
  State<FnRedDireccionesScreen> createState() => _FnRedDireccionesScreenState();
}

class _FnRedDireccionesScreenState extends State<FnRedDireccionesScreen> {
  final _db = Supabase.instance.client;

  List<Map<String, dynamic>> _sedes = [];
  Map<String, dynamic>? _sedeSeleccionada;
  bool _cargandoSedes = true;

  @override
  void initState() {
    super.initState();
    _cargarSedes();
  }

  Future<void> _cargarSedes() async {
    try {
      final data = await _db
          .from('fn_sedes')
          .select('id, tipo, numero, nombre')
          .eq('activo', true)
          .order('numero');
      final lista = List<Map<String, dynamic>>.from(data);
      lista.sort((a, b) {
        final na = int.tryParse(a['numero']?.toString() ?? '') ?? 999;
        final nb = int.tryParse(b['numero']?.toString() ?? '') ?? 999;
        return na.compareTo(nb);
      });
      if (mounted) {
        setState(() {
          _sedes = lista;
          _cargandoSedes = false;
          if (lista.isNotEmpty) _sedeSeleccionada = lista.first;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _cargandoSedes = false);
    }
  }

  String _labelSede(Map<String, dynamic> s) {
    final tipo = s['tipo']?.toString() ?? '';
    final num = s['numero']?.toString() ?? '';
    final nombre = s['nombre']?.toString() ?? '';
    return nombre.isNotEmpty ? '$tipo$num – $nombre' : '$tipo$num';
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0A0A),
        appBar: AppBar(
          backgroundColor: const Color(0xFF008FFF),
          iconTheme: const IconThemeData(color: Colors.white),
          title: const Text(
            '📍 Red de Direcciones FN',
            style: TextStyle(
                color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
          ),
          bottom: const TabBar(
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white54,
            tabs: [
              Tab(icon: Icon(Icons.map, size: 18), text: 'Sectores'),
              Tab(icon: Icon(Icons.location_on, size: 18), text: 'Direcciones'),
            ],
          ),
        ),
        body: _cargandoSedes
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFF008FFF)))
            : Column(
                children: [
                  _SelectorSede(
                    sedes: _sedes,
                    sedeSeleccionada: _sedeSeleccionada,
                    labelSede: _labelSede,
                    onChanged: (s) => setState(() => _sedeSeleccionada = s),
                  ),
                  Expanded(
                    child: _sedeSeleccionada == null
                        ? const Center(
                            child: Text('Sin sedes',
                                style: TextStyle(color: Colors.white38)))
                        : TabBarView(
                            children: [
                              _TabSectores(
                                  sede: _sedeSeleccionada!, db: _db),
                              _TabDirecciones(
                                  sede: _sedeSeleccionada!, db: _db),
                            ],
                          ),
                  ),
                ],
              ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Selector de sede
// ═════════════════════════════════════════════════════════════════════════════

class _SelectorSede extends StatelessWidget {
  final List<Map<String, dynamic>> sedes;
  final Map<String, dynamic>? sedeSeleccionada;
  final String Function(Map<String, dynamic>) labelSede;
  final void Function(Map<String, dynamic>) onChanged;

  const _SelectorSede({
    required this.sedes,
    required this.sedeSeleccionada,
    required this.labelSede,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0F0F0F),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: DropdownButtonFormField<int>(
        value: sedeSeleccionada?['id'] as int?,
        dropdownColor: const Color(0xFF1A1A1A),
        style: const TextStyle(color: Colors.white),
        decoration: const InputDecoration(
          labelText: 'Sede FN',
          labelStyle: TextStyle(color: Colors.white54),
          border: OutlineInputBorder(),
          isDense: true,
          filled: true,
          fillColor: Color(0xFF1A1A1A),
        ),
        items: sedes
            .map((s) => DropdownMenuItem<int>(
                  value: s['id'] as int,
                  child: Text(labelSede(s),
                      style: const TextStyle(color: Colors.white, fontSize: 13)),
                ))
            .toList(),
        onChanged: (v) {
          final s = sedes.firstWhere((x) => x['id'] == v);
          onChanged(s);
        },
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// TAB 1 — SECTORES + TARIFAS POR SEDE
// Catálogo global (sectores) + precio por sede (fn_tarifas_sede)
// ═════════════════════════════════════════════════════════════════════════════

class _TabSectores extends StatefulWidget {
  final Map<String, dynamic> sede;
  final SupabaseClient db;
  const _TabSectores({required this.sede, required this.db});

  @override
  State<_TabSectores> createState() => _TabSectoresState();
}

class _TabSectoresState extends State<_TabSectores>
    with AutomaticKeepAliveClientMixin {
  List<Map<String, dynamic>> _sectores = [];
  Map<int, int> _tarifas = {}; // sector_id → precio para esta sede
  bool _cargando = true;
  String _filtroMun = 'Cúcuta';

  static const _municipios = ['Cúcuta', 'Los Patios', 'V. Rosario'];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void didUpdateWidget(_TabSectores old) {
    super.didUpdateWidget(old);
    if (old.sede['id'] != widget.sede['id']) _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final secs = await widget.db
          .from('sectores')
          .select('id, nombre, activo, municipio')
          .order('municipio')
          .order('nombre');
      final tars = await widget.db
          .from('fn_tarifas_sede')
          .select('sector_id, precio')
          .eq('sede_id', widget.sede['id']);
      if (mounted) {
        final tarifaMap = <int, int>{};
        for (final t in List<Map<String, dynamic>>.from(tars)) {
          tarifaMap[t['sector_id'] as int] = (t['precio'] as num).toInt();
        }
        setState(() {
          _sectores = List<Map<String, dynamic>>.from(secs);
          _tarifas = tarifaMap;
          _cargando = false;
        });
      }
    } catch (_) {
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

  // Guardar/actualizar tarifa para esta sede
  Future<void> _guardarTarifa(int sectorId, int precio) async {
    final existing = await widget.db
        .from('fn_tarifas_sede')
        .select('id')
        .eq('sede_id', widget.sede['id'])
        .eq('sector_id', sectorId)
        .maybeSingle();
    if (existing != null) {
      await widget.db
          .from('fn_tarifas_sede')
          .update({'precio': precio}).eq('id', existing['id']);
    } else {
      await widget.db.from('fn_tarifas_sede').insert({
        'sede_id': widget.sede['id'],
        'sector_id': sectorId,
        'precio': precio,
      });
    }
  }

  Future<void> _abrirFormulario({Map<String, dynamic>? sector}) async {
    final ctrl =
        TextEditingController(text: sector?['nombre']?.toString() ?? '');
    final sId = sector?['id'] as int?;
    final precioCtrl = TextEditingController(
      text: sId != null && _tarifas.containsKey(sId)
          ? _tarifas[sId].toString()
          : '',
    );
    bool activo = sector?['activo'] != false;
    String? municipio =
        sector?['municipio']?.toString() ?? _filtroMun;

    final guardado = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          backgroundColor: const Color(0xFF1A1A1A),
          title: Text(
            sector == null ? '➕ Nuevo sector' : '✏️ Editar sector',
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 1. Municipio
                DropdownButtonFormField<String?>(
                  value: municipio,
                  dropdownColor: const Color(0xFF1A1A1A),
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Municipio',
                    labelStyle: TextStyle(color: Colors.white54),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Sin definir',
                          style: TextStyle(color: Colors.white54)),
                    ),
                    ..._municipios.map((m) => DropdownMenuItem<String?>(
                          value: m,
                          child: Text(m,
                              style: const TextStyle(color: Colors.white)),
                        )),
                  ],
                  onChanged: (v) => setD(() => municipio = v),
                ),
                const SizedBox(height: 12),
                // 2. Nombre
                TextField(
                  controller: ctrl,
                  style: const TextStyle(color: Colors.white),
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Nombre del sector',
                    labelStyle: TextStyle(color: Colors.white54),
                    hintText: 'Ej: Norte, Centro, Aeropuerto',
                    hintStyle: TextStyle(color: Colors.white24),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                // 3. Precio para esta sede
                TextField(
                  controller: precioCtrl,
                  style: const TextStyle(color: Colors.white),
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Tarifa para esta sede (\$)',
                    labelStyle: TextStyle(color: Colors.white54),
                    hintText: 'Dejar vacío para no asignar aún',
                    hintStyle: TextStyle(color: Colors.white24),
                    border: OutlineInputBorder(),
                    isDense: true,
                    prefixText: '\$ ',
                    prefixStyle: TextStyle(color: Colors.white70),
                  ),
                ),
                if (sector != null) ...[
                  const SizedBox(height: 12),
                  SwitchListTile(
                    value: activo,
                    onChanged: (v) => setD(() => activo = v),
                    title: const Text('Activo',
                        style: TextStyle(color: Colors.white, fontSize: 13)),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('CANCELAR',
                    style: TextStyle(color: Colors.white54))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF008FFF)),
              onPressed: () async {
                final nombre = ctrl.text.trim();
                if (nombre.isEmpty) return;
                int newSectorId;
                if (sector == null) {
                  final res = await widget.db
                      .from('sectores')
                      .insert({
                        'nombre': nombre,
                        'activo': true,
                        if (municipio != null) 'municipio': municipio,
                      })
                      .select('id')
                      .single();
                  newSectorId = res['id'] as int;
                } else {
                  await widget.db.from('sectores').update({
                    'nombre': nombre,
                    'activo': activo,
                    'municipio': municipio,
                  }).eq('id', sector['id']);
                  newSectorId = sector['id'] as int;
                }
                // Guardar tarifa si se ingresó precio válido
                final precio = int.tryParse(precioCtrl.text.trim());
                if (precio != null && precio > 0) {
                  await _guardarTarifa(newSectorId, precio);
                }
                if (ctx.mounted) Navigator.pop(ctx, true);
              },
              child: const Text('GUARDAR',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
    if (guardado == true) _cargar();
  }

  Future<void> _editarPrecio(Map<String, dynamic> sector) async {
    final sId = sector['id'] as int;
    final precioActual = _tarifas[sId];
    final ctrl = TextEditingController(
        text: precioActual != null ? precioActual.toString() : '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(
          'Tarifa — ${sector['nombre']}',
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
        ),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Precio (\$)',
            labelStyle: TextStyle(color: Colors.white54),
            border: OutlineInputBorder(),
            isDense: true,
            prefixText: '\$ ',
            prefixStyle: TextStyle(color: Colors.white70),
          ),
        ),
        actions: [
          if (precioActual != null)
            TextButton(
              onPressed: () async {
                await widget.db
                    .from('fn_tarifas_sede')
                    .delete()
                    .eq('sede_id', widget.sede['id'])
                    .eq('sector_id', sId);
                if (ctx.mounted) Navigator.pop(ctx, true);
              },
              child: const Text('Quitar tarifa',
                  style: TextStyle(color: Colors.red)),
            ),
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('CANCELAR',
                  style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF008FFF)),
            onPressed: () async {
              final precio = int.tryParse(ctrl.text.trim());
              if (precio == null || precio <= 0) return;
              await _guardarTarifa(sId, precio);
              if (ctx.mounted) Navigator.pop(ctx, true);
            },
            child: const Text('GUARDAR',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (ok == true) _cargar();
  }

  Future<void> _eliminar(Map<String, dynamic> sector) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('¿Eliminar sector?',
            style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(sector['nombre'],
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text(
              'Se eliminará del catálogo global (afecta todas las sedes y usuarios). No se puede deshacer.',
              style: TextStyle(color: Colors.orange, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('NO', style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ELIMINAR',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await widget.db.from('sectores').delete().eq('id', sector['id']);
      _cargar();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF008FFF),
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Nuevo sector',
            style:
                TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        onPressed: _abrirFormulario,
      ),
      body: _cargando
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF008FFF)))
          : Column(
              children: [
                // ── Filtro municipio ──────────────────────────────────────
                Container(
                  color: const Color(0xFF111111),
                  height: 42,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    children: _municipios.map((m) {
                      final sel = _filtroMun == m;
                      return GestureDetector(
                        onTap: () => setState(() => _filtroMun = m),
                        child: Container(
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: sel
                                ? const Color(0xFF008FFF)
                                : const Color(0xFF1A1A1A),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: sel
                                    ? const Color(0xFF008FFF)
                                    : Colors.white24),
                          ),
                          child: Text(m,
                              style: TextStyle(
                                color: sel ? Colors.white : Colors.white54,
                                fontSize: 12,
                                fontWeight: sel
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              )),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                // ── Lista ─────────────────────────────────────────────────
                Expanded(
                  child: Builder(builder: (ctx) {
                    final filtrados = _sectores
                        .where((s) =>
                            s['municipio']?.toString() == _filtroMun)
                        .toList();
                    if (filtrados.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.map_outlined,
                                color: Colors.white24, size: 48),
                            const SizedBox(height: 12),
                            Text('Sin sectores en $_filtroMun',
                                style: const TextStyle(color: Colors.white38)),
                            const SizedBox(height: 8),
                            TextButton.icon(
                              onPressed: _abrirFormulario,
                              icon: const Icon(Icons.add,
                                  color: Color(0xFF008FFF)),
                              label: const Text('Crear primer sector',
                                  style:
                                      TextStyle(color: Color(0xFF008FFF))),
                            ),
                          ],
                        ),
                      );
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
                      itemCount: filtrados.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: 8),
                      itemBuilder: (ctx, i) {
                        final s = filtrados[i];
                        final sId = s['id'] as int;
                        final activo = s['activo'] != false;
                        final precio = _tarifas[sId];
                        return Container(
                          decoration: BoxDecoration(
                            color: activo
                                ? const Color(0xFF1A1A1A)
                                : const Color(0xFF111111),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: activo
                                  ? const Color(0xFF008FFF)
                                      .withValues(alpha: 0.4)
                                  : Colors.white12,
                            ),
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: activo
                                  ? const Color(0xFF0070CC)
                                  : Colors.grey[800],
                              child: Icon(Icons.map,
                                  color: activo
                                      ? Colors.white
                                      : Colors.white38,
                                  size: 18),
                            ),
                            title: Text(
                              s['nombre']?.toString() ?? '',
                              style: TextStyle(
                                color:
                                    activo ? Colors.white : Colors.white38,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            subtitle: Row(
                              children: [
                                Text(
                                  activo ? 'Activo' : 'Inactivo',
                                  style: TextStyle(
                                    color: activo
                                        ? const Color(0xFF008FFF)
                                        : Colors.red,
                                    fontSize: 11,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                // Badge de precio (tap para editar)
                                GestureDetector(
                                  onTap: () => _editarPrecio(s),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 7, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: precio != null
                                          ? Colors.green
                                              .withValues(alpha: 0.2)
                                          : Colors.orange
                                              .withValues(alpha: 0.15),
                                      borderRadius:
                                          BorderRadius.circular(8),
                                      border: Border.all(
                                          color: precio != null
                                              ? Colors.green
                                                  .withValues(alpha: 0.6)
                                              : Colors.orange
                                                  .withValues(alpha: 0.5)),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          precio != null
                                              ? Icons.attach_money
                                              : Icons.add,
                                          size: 11,
                                          color: precio != null
                                              ? Colors.greenAccent
                                              : Colors.orange,
                                        ),
                                        Text(
                                          precio != null
                                              ? '\$${_miles(precio)}'
                                              : 'Asignar tarifa',
                                          style: TextStyle(
                                            color: precio != null
                                                ? Colors.greenAccent
                                                : Colors.orange,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit_outlined,
                                      color: Color(0xFF008FFF), size: 20),
                                  onPressed: () =>
                                      _abrirFormulario(sector: s),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline,
                                      color: Colors.red, size: 20),
                                  onPressed: () => _eliminar(s),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  }),
                ),
              ],
            ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// TAB 2 — DIRECCIONES (catálogo global + precio por sede)
// red_dir_catalogo (global) + fn_precios_dir (precio por sede)
// ═════════════════════════════════════════════════════════════════════════════

class _TabDirecciones extends StatefulWidget {
  final Map<String, dynamic> sede;
  final SupabaseClient db;
  const _TabDirecciones({required this.sede, required this.db});

  @override
  State<_TabDirecciones> createState() => _TabDireccionesState();
}

class _TabDireccionesState extends State<_TabDirecciones>
    with AutomaticKeepAliveClientMixin {
  List<Map<String, dynamic>> _dirs = [];
  Map<int, int> _precios = {}; // dir_id → precio para esta sede
  List<Map<String, dynamic>> _sectores = [];
  bool _cargando = true;
  String _filtroMun = 'Cúcuta';

  static const _municipios = ['Cúcuta', 'Los Patios', 'V. Rosario'];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void didUpdateWidget(_TabDirecciones old) {
    super.didUpdateWidget(old);
    if (old.sede['id'] != widget.sede['id']) {
      _filtroMun = 'Cúcuta';
      _cargar();
    }
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final dirs = await widget.db
          .from('red_dir_catalogo')
          .select(
              'id, nombre, alias, direccion, municipio, sector_id, activo, lat, lng')
          .order('municipio')
          .order('nombre');
      final precios = await widget.db
          .from('fn_precios_dir')
          .select('dir_id, precio')
          .eq('sede_id', widget.sede['id']);
      final secs = await widget.db
          .from('sectores')
          .select('id, nombre, municipio')
          .eq('activo', true)
          .order('municipio')
          .order('nombre');
      if (mounted) {
        final precioMap = <int, int>{};
        for (final p in List<Map<String, dynamic>>.from(precios)) {
          precioMap[p['dir_id'] as int] = (p['precio'] as num).toInt();
        }
        setState(() {
          _dirs = List<Map<String, dynamic>>.from(dirs);
          _precios = precioMap;
          _sectores = List<Map<String, dynamic>>.from(secs);
          _cargando = false;
        });
      }
    } catch (_) {
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

  static (double?, double?) _parsearUrlMaps(String url) {
    var m = RegExp(r'@(-?\d{1,3}\.\d+),(-?\d{1,3}\.\d+)').firstMatch(url);
    if (m != null)
      return (double.tryParse(m.group(1)!), double.tryParse(m.group(2)!));
    m = RegExp(r'[?&]q=(-?\d{1,3}\.\d+),(-?\d{1,3}\.\d+)').firstMatch(url);
    if (m != null)
      return (double.tryParse(m.group(1)!), double.tryParse(m.group(2)!));
    m = RegExp(r'll=(-?\d{1,3}\.\d+),(-?\d{1,3}\.\d+)').firstMatch(url);
    if (m != null)
      return (double.tryParse(m.group(1)!), double.tryParse(m.group(2)!));
    m = RegExp(r'(-?\d{1,3}\.\d{4,}),(-?\d{1,3}\.\d{4,})').firstMatch(url);
    if (m != null)
      return (double.tryParse(m.group(1)!), double.tryParse(m.group(2)!));
    return (null, null);
  }

  Future<void> _abrirFormulario({Map<String, dynamic>? dir}) async {
    final nombreCtrl =
        TextEditingController(text: dir?['nombre']?.toString() ?? '');
    final aliasCtrl =
        TextEditingController(text: dir?['alias']?.toString() ?? '');
    final direccionCtrl =
        TextEditingController(text: dir?['direccion']?.toString() ?? '');
    final dId = dir?['id'] as int?;
    final precioCtrl = TextEditingController(
      text: dId != null && _precios.containsKey(dId)
          ? _precios[dId].toString()
          : '',
    );
    final gpsCtrl = TextEditingController();
    String? municipio = dir?['municipio']?.toString() ?? _filtroMun;
    int? sectorId = dir?['sector_id'] as int?;
    bool activo = dir?['activo'] != false;
    double? gpsLat = (dir?['lat'] as num?)?.toDouble();
    double? gpsLng = (dir?['lng'] as num?)?.toDouble();

    final guardado = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          final sectoresFiltrados = municipio == null
              ? _sectores
              : _sectores.where((s) => s['municipio'] == municipio).toList();
          final sectorValido =
              sectoresFiltrados.any((s) => s['id'] == sectorId);

          return AlertDialog(
            backgroundColor: const Color(0xFF1A1A1A),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            title: Text(
              dir == null ? '➕ Nueva dirección' : '✏️ Editar dirección',
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 1. Nombre / alias
                  TextField(
                    controller: nombreCtrl,
                    style: const TextStyle(color: Colors.white),
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Nombre / alias',
                      labelStyle: TextStyle(color: Colors.white54),
                      hintText: 'Ej: Clínica Norte, Tennis Park',
                      hintStyle: TextStyle(color: Colors.white24),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  // 2. Municipio
                  DropdownButtonFormField<String?>(
                    value: municipio,
                    dropdownColor: const Color(0xFF1A1A1A),
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Municipio',
                      labelStyle: TextStyle(color: Colors.white54),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Sin definir',
                            style: TextStyle(color: Colors.white54)),
                      ),
                      ..._municipios.map((m) => DropdownMenuItem<String?>(
                            value: m,
                            child: Text(m,
                                style:
                                    const TextStyle(color: Colors.white)),
                          )),
                    ],
                    onChanged: (v) => setD(() {
                      municipio = v;
                      sectorId = null;
                    }),
                  ),
                  const SizedBox(height: 10),
                  // 3. Sector (opcional)
                  DropdownButtonFormField<int?>(
                    value: sectorValido ? sectorId : null,
                    dropdownColor: const Color(0xFF1A1A1A),
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Sector (opcional)',
                      labelStyle: const TextStyle(color: Colors.white54),
                      border: const OutlineInputBorder(),
                      isDense: true,
                      hintText: sectoresFiltrados.isEmpty
                          ? 'Sin sectores en este municipio'
                          : null,
                      hintStyle: const TextStyle(
                          color: Colors.white38, fontSize: 12),
                    ),
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('Sin sector',
                            style: TextStyle(color: Colors.white54)),
                      ),
                      ...sectoresFiltrados.map((s) => DropdownMenuItem<int?>(
                            value: s['id'] as int,
                            child: Text(s['nombre'].toString(),
                                style:
                                    const TextStyle(color: Colors.white)),
                          )),
                    ],
                    onChanged: (v) => setD(() => sectorId = v),
                  ),
                  const SizedBox(height: 10),
                  // 4. Dirección completa
                  TextField(
                    controller: direccionCtrl,
                    style: const TextStyle(color: Colors.white),
                    maxLines: 2,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Dirección completa',
                      labelStyle: TextStyle(color: Colors.white54),
                      hintText: 'Ej: Calle 10 # 5-20, Barrio X',
                      hintStyle: TextStyle(color: Colors.white24),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  // 5. Precio para esta sede
                  TextField(
                    controller: precioCtrl,
                    style: const TextStyle(color: Colors.white),
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Precio sugerido para esta sede (\$)',
                      labelStyle: TextStyle(color: Colors.white54),
                      hintText: 'Sin precio → no aparece en autocomplete',
                      hintStyle:
                          TextStyle(color: Colors.white24, fontSize: 11),
                      border: OutlineInputBorder(),
                      isDense: true,
                      prefixText: '\$ ',
                      prefixStyle: TextStyle(color: Colors.white70),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // 6. GPS link (opcional)
                  TextField(
                    controller: gpsCtrl,
                    style:
                        const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      labelText: 'Link GPS (opcional)',
                      labelStyle: const TextStyle(
                          color: Colors.white54, fontSize: 13),
                      hintText: 'Pega un link de Google Maps',
                      hintStyle: const TextStyle(
                          color: Colors.white24, fontSize: 12),
                      border: const OutlineInputBorder(),
                      isDense: true,
                      suffixIcon: gpsLat != null
                          ? const Icon(Icons.gps_fixed,
                              color: Color(0xFF008FFF), size: 18)
                          : const Icon(Icons.gps_not_fixed,
                              color: Colors.white38, size: 18),
                    ),
                    onChanged: (v) {
                      if (v.trim().isEmpty) {
                        setD(() {
                          gpsLat = null;
                          gpsLng = null;
                        });
                        return;
                      }
                      final (lat, lng) = _parsearUrlMaps(v.trim());
                      setD(() {
                        gpsLat = lat;
                        gpsLng = lng;
                      });
                    },
                  ),
                  if (gpsLat != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(children: [
                        const Icon(Icons.check_circle,
                            color: Color(0xFF008FFF), size: 13),
                        const SizedBox(width: 4),
                        Text(
                          'GPS: ${gpsLat!.toStringAsFixed(5)}, ${gpsLng!.toStringAsFixed(5)}',
                          style: const TextStyle(
                              color: Color(0xFF008FFF), fontSize: 11),
                        ),
                      ]),
                    )
                  else if (gpsCtrl.text.trim().isNotEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Row(children: [
                        Icon(Icons.warning_amber,
                            color: Colors.orange, size: 13),
                        SizedBox(width: 4),
                        Text('No se pudo leer el GPS',
                            style: TextStyle(
                                color: Colors.orange, fontSize: 11)),
                      ]),
                    ),
                  if (dir != null) ...[
                    const SizedBox(height: 10),
                    SwitchListTile(
                      value: activo,
                      onChanged: (v) => setD(() => activo = v),
                      title: const Text('Activa',
                          style: TextStyle(
                              color: Colors.white, fontSize: 13)),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('CANCELAR',
                      style: TextStyle(color: Colors.white54))),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF008FFF)),
                onPressed: () async {
                  final nombre = nombreCtrl.text.trim();
                  final direccion = direccionCtrl.text.trim();
                  if (nombre.isEmpty || direccion.isEmpty) {
                    ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                        content:
                            Text('Nombre y dirección son obligatorios')));
                    return;
                  }
                  int newDirId;
                  if (dir == null) {
                    final res = await widget.db
                        .from('red_dir_catalogo')
                        .insert({
                          'nombre': nombre,
                          if (aliasCtrl.text.trim().isNotEmpty)
                            'alias': aliasCtrl.text.trim(),
                          'direccion': direccion.toUpperCase(),
                          if (municipio != null) 'municipio': municipio,
                          'sector_id': sectorId,
                          'activo': true,
                          if (gpsLat != null) 'lat': gpsLat,
                          if (gpsLng != null) 'lng': gpsLng,
                        })
                        .select('id')
                        .single();
                    newDirId = res['id'] as int;
                  } else {
                    await widget.db.from('red_dir_catalogo').update({
                      'nombre': nombre,
                      'alias': aliasCtrl.text.trim().isEmpty
                          ? null
                          : aliasCtrl.text.trim(),
                      'direccion': direccion.toUpperCase(),
                      'municipio': municipio,
                      'sector_id': sectorId,
                      'activo': activo,
                      'lat': gpsLat,
                      'lng': gpsLng,
                    }).eq('id', dir['id']);
                    newDirId = dir['id'] as int;
                  }
                  // Guardar precio para esta sede
                  final precio = int.tryParse(precioCtrl.text.trim());
                  if (precio != null && precio > 0) {
                    // PK en fn_precios_dir es (sede_id, dir_id) →
                    // borrar y reinsertar es seguro
                    await widget.db
                        .from('fn_precios_dir')
                        .delete()
                        .eq('sede_id', widget.sede['id'])
                        .eq('dir_id', newDirId);
                    await widget.db.from('fn_precios_dir').insert({
                      'sede_id': widget.sede['id'],
                      'dir_id': newDirId,
                      'precio': precio,
                    });
                  }
                  if (ctx.mounted) Navigator.pop(ctx, true);
                },
                child: const Text('GUARDAR',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
    if (guardado == true) _cargar();
  }

  Future<void> _eliminar(Map<String, dynamic> dir) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('¿Eliminar dirección?',
            style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(dir['nombre'],
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(dir['direccion']?.toString() ?? '',
                style:
                    const TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 8),
            const Text(
              'Se eliminará del catálogo global y de todas las sedes. No se puede deshacer.',
              style: TextStyle(color: Colors.orange, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('NO', style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ELIMINAR',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await widget.db.from('red_dir_catalogo').delete().eq('id', dir['id']);
      _cargar();
    }
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF008FFF)
              : const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: selected
                  ? const Color(0xFF008FFF)
                  : Colors.white24),
        ),
        child: Text(label,
            style: TextStyle(
              color: selected ? Colors.white : Colors.white54,
              fontSize: 12,
              fontWeight:
                  selected ? FontWeight.bold : FontWeight.normal,
            )),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF008FFF),
        icon: const Icon(Icons.add_location_alt, color: Colors.white),
        label: const Text('Nueva dirección',
            style:
                TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        onPressed: _abrirFormulario,
      ),
      body: _cargando
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF008FFF)))
          : Column(
              children: [
                // ── Filtro municipio ──────────────────────────────────────
                Container(
                  color: const Color(0xFF111111),
                  height: 42,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    children: _municipios
                        .map((m) => _chip(m, _filtroMun == m,
                            () => setState(() => _filtroMun = m)))
                        .toList(),
                  ),
                ),
                // ── Lista ─────────────────────────────────────────────────
                Expanded(
                  child: Builder(builder: (ctx) {
                    final filtradas = _dirs
                        .where((d) =>
                            d['municipio']?.toString() == _filtroMun)
                        .toList();
                    if (filtradas.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.location_off,
                                color: Colors.white24, size: 48),
                            const SizedBox(height: 12),
                            Text('Sin direcciones en $_filtroMun',
                                style: const TextStyle(
                                    color: Colors.white38)),
                            const SizedBox(height: 8),
                            TextButton.icon(
                              onPressed: _abrirFormulario,
                              icon: const Icon(Icons.add,
                                  color: Color(0xFF008FFF)),
                              label: const Text('Agregar primera dirección',
                                  style:
                                      TextStyle(color: Color(0xFF008FFF))),
                            ),
                          ],
                        ),
                      );
                    }
                    return ListView.separated(
                      padding:
                          const EdgeInsets.fromLTRB(12, 12, 12, 100),
                      itemCount: filtradas.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: 8),
                      itemBuilder: (ctx, i) {
                        final d = filtradas[i];
                        final dId = d['id'] as int;
                        final activo = d['activo'] != false;
                        final precio = _precios[dId];
                        final sectorNombre = d['sector_id'] != null
                            ? _sectores
                                .where((s) => s['id'] == d['sector_id'])
                                .map((s) => s['nombre']?.toString())
                                .firstOrNull
                            : null;
                        return Container(
                          decoration: BoxDecoration(
                            color: activo
                                ? const Color(0xFF1A1A1A)
                                : const Color(0xFF111111),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: activo
                                  ? const Color(0xFF008FFF)
                                      .withValues(alpha: 0.4)
                                  : Colors.white12,
                            ),
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: activo
                                  ? const Color(0xFF0070CC)
                                  : Colors.grey[800],
                              child: Icon(Icons.location_on,
                                  color: activo
                                      ? Colors.white
                                      : Colors.white38,
                                  size: 18),
                            ),
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    d['nombre']?.toString() ?? '',
                                    style: TextStyle(
                                      color: activo
                                          ? Colors.white
                                          : Colors.white38,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                if (sectorNombre != null)
                                  Container(
                                    margin:
                                        const EdgeInsets.only(left: 6),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF008FFF)
                                          .withValues(alpha: 0.2),
                                      borderRadius:
                                          BorderRadius.circular(10),
                                      border: Border.all(
                                          color: const Color(0xFF008FFF)
                                              .withValues(alpha: 0.5)),
                                    ),
                                    child: Text(sectorNombre,
                                        style: const TextStyle(
                                            color: Color(0xFF008FFF),
                                            fontSize: 10)),
                                  ),
                              ],
                            ),
                            subtitle: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                if ((d['direccion']?.toString() ?? '')
                                    .isNotEmpty)
                                  Text(
                                    d['direccion'].toString(),
                                    style: TextStyle(
                                        color: activo
                                            ? Colors.white60
                                            : Colors.white24,
                                        fontSize: 12),
                                  ),
                                Row(children: [
                                  Icon(
                                    precio != null
                                        ? Icons.attach_money
                                        : Icons.money_off,
                                    size: 13,
                                    color: precio != null
                                        ? Colors.greenAccent
                                        : Colors.orange,
                                  ),
                                  Text(
                                    precio != null
                                        ? '\$${_miles(precio)}'
                                        : 'Sin precio',
                                    style: TextStyle(
                                      color: precio != null
                                          ? Colors.greenAccent
                                          : Colors.orange,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                  if (!activo) ...[
                                    const SizedBox(width: 8),
                                    const Text('INACTIVA',
                                        style: TextStyle(
                                            color: Colors.red,
                                            fontSize: 10,
                                            fontWeight:
                                                FontWeight.bold)),
                                  ],
                                ]),
                              ],
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit_outlined,
                                      color: Color(0xFF008FFF), size: 20),
                                  onPressed: () =>
                                      _abrirFormulario(dir: d),
                                ),
                                IconButton(
                                  icon: const Icon(
                                      Icons.delete_outline,
                                      color: Colors.red,
                                      size: 20),
                                  onPressed: () => _eliminar(d),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  }),
                ),
              ],
            ),
    );
  }
}
