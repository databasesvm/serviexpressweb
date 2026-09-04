// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ─────────────────────────────────────────────────────────────────────────────
// FnRedDireccionesScreen
// Administración Central: Sectores · Direcciones · Tarifas por Sector
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
      length: 3,
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
            indicatorColor: const Color(0xFF008FFF),
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white54,
            tabs: [
              Tab(icon: Icon(Icons.map, size: 18), text: 'Sectores'),
              Tab(icon: Icon(Icons.price_change, size: 18), text: 'Tarifas'),
              Tab(icon: Icon(Icons.location_on, size: 18), text: 'Direcciones'),
            ],
          ),
        ),
        body: _cargandoSedes
            ? const Center(
                child: CircularProgressIndicator(color: const Color(0xFF008FFF)))
            : Column(
                children: [
                  // ── Selector de sede ──────────────────────────────────────
                  _SelectorSede(
                    sedes: _sedes,
                    sedeSeleccionada: _sedeSeleccionada,
                    labelSede: _labelSede,
                    onChanged: (s) => setState(() => _sedeSeleccionada = s),
                  ),
                  // ── Tabs ──────────────────────────────────────────────────
                  Expanded(
                    child: _sedeSeleccionada == null
                        ? const Center(
                            child: Text('Sin sedes',
                                style: TextStyle(color: Colors.white38)))
                        : TabBarView(
                            children: [
                              _TabSectores(
                                  sede: _sedeSeleccionada!, db: _db),
                              _TabTarifas(
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
// Selector de sede (barra compartida entre tabs)
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
                      style:
                          const TextStyle(color: Colors.white, fontSize: 13)),
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
// TAB 1 — SECTORES
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
  bool _cargando = true;

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
      final data = await widget.db
          .from('fn_sectores')
          .select('id, nombre, activo, municipio')
          .order('nombre');
      if (mounted) {
        setState(() {
          _sectores = List<Map<String, dynamic>>.from(data);
          _cargando = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _cargando = false);
    }
  }

  static const _municipios = ['Cúcuta', 'Los Patios', 'Villa del Rosario'];

  Future<void> _abrirFormulario({Map<String, dynamic>? sector}) async {
    final ctrl = TextEditingController(text: sector?['nombre']?.toString() ?? '');
    bool activo = sector?['activo'] != false;
    String? municipio = sector?['municipio']?.toString();
    final guardado = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          backgroundColor: const Color(0xFF1A1A1A),
          title: Text(
            sector == null ? '➕ Nuevo sector' : '✏️ Editar sector',
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ctrl,
                style: const TextStyle(color: Colors.white),
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Nombre del sector / zona',
                  labelStyle: TextStyle(color: Colors.white54),
                  hintText: 'Ej: Norte, Centro, Aeropuerto',
                  hintStyle: TextStyle(color: Colors.white24),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
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
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('CANCELAR',
                    style: TextStyle(color: Colors.white54))),
            ElevatedButton(
              style:
                  ElevatedButton.styleFrom(backgroundColor: const Color(0xFF008FFF)),
              onPressed: () async {
                final nombre = ctrl.text.trim();
                if (nombre.isEmpty) return;
                if (sector == null) {
                  await widget.db.from('fn_sectores').insert({
                    'nombre': nombre,
                    'activo': true,
                    if (municipio != null) 'municipio': municipio,
                  });
                } else {
                  await widget.db.from('fn_sectores').update({
                    'nombre': nombre,
                    'activo': activo,
                    'municipio': municipio,
                  }).eq('id', sector['id']);
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

  Future<void> _eliminar(Map<String, dynamic> sector) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('¿Eliminar sector?',
            style: TextStyle(color: Colors.white)),
        content: Text(sector['nombre'],
            style: const TextStyle(color: Colors.white70)),
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
      await widget.db.from('fn_sectores').delete().eq('id', sector['id']);
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
          ? const Center(child: CircularProgressIndicator(color: const Color(0xFF008FFF)))
          : _sectores.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.map_outlined,
                          color: Colors.white24, size: 48),
                      const SizedBox(height: 12),
                      const Text('Sin sectores para esta sede',
                          style: TextStyle(color: Colors.white38)),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: _abrirFormulario,
                        icon: const Icon(Icons.add, color: const Color(0xFF008FFF)),
                        label: const Text('Crear primer sector',
                            style: TextStyle(color: const Color(0xFF008FFF))),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding:
                      const EdgeInsets.fromLTRB(12, 12, 12, 100),
                  itemCount: _sectores.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (ctx, i) {
                    final s = _sectores[i];
                    final activo = s['activo'] != false;
                    return Container(
                      decoration: BoxDecoration(
                        color: activo
                            ? const Color(0xFF1A1A1A)
                            : const Color(0xFF111111),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: activo
                              ? const Color(0xFF008FFF).withValues(alpha: 0.4)
                              : Colors.white12,
                        ),
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor:
                              activo ? const Color(0xFF0070CC) : Colors.grey[800],
                          child: Icon(Icons.map,
                              color: activo ? Colors.white : Colors.white38,
                              size: 18),
                        ),
                        title: Text(
                          s['nombre']?.toString() ?? '',
                          style: TextStyle(
                            color: activo ? Colors.white : Colors.white38,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        subtitle: Row(
                          children: [
                            Text(
                              activo ? 'Activo' : 'Inactivo',
                              style: TextStyle(
                                color: activo ? const Color(0xFF008FFF) : Colors.red,
                                fontSize: 11,
                              ),
                            ),
                            if (s['municipio'] != null) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF008FFF).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: const Color(0xFF008FFF).withValues(alpha: 0.4)),
                                ),
                                child: Text(
                                  s['municipio'].toString(),
                                  style: const TextStyle(color: Color(0xFF008FFF), fontSize: 10),
                                ),
                              ),
                            ],
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined,
                                  color: const Color(0xFF008FFF), size: 20),
                              onPressed: () => _abrirFormulario(sector: s),
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
                ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// TAB 2 — DIRECCIONES
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
  List<Map<String, dynamic>> _direcciones = [];
  List<Map<String, dynamic>> _sectores = [];
  bool _cargando = true;

  // Filtro por sector
  int? _filtroSectorId;

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
      _filtroSectorId = null;
      _cargar();
    }
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final dirs = await widget.db
          .from('fn_red_direcciones')
          .select('id, nombre, direccion, precio, activo, sector_id, fn_sectores(nombre)')
          .eq('sede_id', widget.sede['id'])
          .order('nombre');
      final secs = await widget.db
          .from('fn_sectores')
          .select('id, nombre')
          .eq('activo', true)
          .order('nombre');
      if (mounted) {
        setState(() {
          _direcciones = List<Map<String, dynamic>>.from(dirs);
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

  Future<void> _abrirFormulario({Map<String, dynamic>? dir}) async {
    final sedeId = widget.sede['id'];
    final nombreCtrl =
        TextEditingController(text: dir?['nombre']?.toString() ?? '');
    final direccionCtrl =
        TextEditingController(text: dir?['direccion']?.toString() ?? '');
    final precioCtrl = TextEditingController(
      text: dir != null ? (dir['precio'] as num).toInt().toString() : '',
    );
    int? sectorId = dir?['sector_id'] as int?;
    bool activo = dir?['activo'] != false;
    double? gpsLat = (dir?['lat'] as num?)?.toDouble();
    double? gpsLng = (dir?['lng'] as num?)?.toDouble();
    final gpsCtrl = TextEditingController();

    final guardado = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: Text(
            dir == null ? '➕ Nueva dirección' : '✏️ Editar dirección',
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
          ),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              // Nombre/alias
              TextField(
                controller: nombreCtrl,
                style: const TextStyle(color: Colors.white),
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Nombre / alias',
                  labelStyle: TextStyle(color: Colors.white54),
                  hintText: 'Ej: Clínica Norte',
                  hintStyle: TextStyle(color: Colors.white24),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              // Sector
              DropdownButtonFormField<int?>(
                value: sectorId,
                dropdownColor: const Color(0xFF1A1A1A),
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Sector',
                  labelStyle: TextStyle(color: Colors.white54),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  const DropdownMenuItem<int?>(
                      value: null,
                      child: Text('Sin sector',
                          style: TextStyle(color: Colors.white54))),
                  ..._sectores.map((s) => DropdownMenuItem<int?>(
                        value: s['id'] as int,
                        child: Text(s['nombre'].toString(),
                            style: const TextStyle(color: Colors.white)),
                      )),
                ],
                onChanged: (v) => setD(() => sectorId = v),
              ),
              const SizedBox(height: 10),
              // Dirección
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
              // Precio
              TextField(
                controller: precioCtrl,
                style: const TextStyle(color: Colors.white),
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Precio sugerido (\$)',
                  labelStyle: TextStyle(color: Colors.white54),
                  border: OutlineInputBorder(),
                  isDense: true,
                  prefixText: '\$ ',
                  prefixStyle: TextStyle(color: Colors.white70),
                ),
              ),
              const SizedBox(height: 10),
              // GPS link
              TextField(
                controller: gpsCtrl,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  labelText: 'Link GPS (opcional)',
                  labelStyle: const TextStyle(color: Colors.white54, fontSize: 13),
                  hintText: 'Pega un link de Google Maps',
                  hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
                  border: const OutlineInputBorder(),
                  isDense: true,
                  suffixIcon: gpsLat != null
                      ? const Icon(Icons.gps_fixed, color: const Color(0xFF008FFF), size: 18)
                      : const Icon(Icons.gps_not_fixed, color: Colors.white38, size: 18),
                ),
                onChanged: (v) {
                  if (v.trim().isEmpty) {
                    setD(() { gpsLat = null; gpsLng = null; });
                    return;
                  }
                  final (lat, lng) = _parsearUrlMaps(v.trim());
                  setD(() { gpsLat = lat; gpsLng = lng; });
                },
              ),
              if (gpsLat != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(children: [
                    const Icon(Icons.check_circle, color: const Color(0xFF008FFF), size: 13),
                    const SizedBox(width: 4),
                    Text(
                      'GPS detectado: ${gpsLat!.toStringAsFixed(5)}, ${gpsLng!.toStringAsFixed(5)}',
                      style: const TextStyle(color: const Color(0xFF008FFF), fontSize: 11),
                    ),
                  ]),
                )
              else if (gpsCtrl.text.trim().isNotEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Row(children: [
                    Icon(Icons.warning_amber, color: Colors.orange, size: 13),
                    SizedBox(width: 4),
                    Text('No se pudo leer el GPS',
                        style: TextStyle(color: Colors.orange, fontSize: 11)),
                  ]),
                ),
              if (dir != null) ...[
                const SizedBox(height: 10),
                SwitchListTile(
                  value: activo,
                  onChanged: (v) => setD(() => activo = v),
                  title: const Text('Activa',
                      style: TextStyle(color: Colors.white, fontSize: 13)),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('CANCELAR',
                    style: TextStyle(color: Colors.white54))),
            ElevatedButton(
              style:
                  ElevatedButton.styleFrom(backgroundColor: const Color(0xFF008FFF)),
              onPressed: () async {
                final nombre = nombreCtrl.text.trim();
                final direccion = direccionCtrl.text.trim();
                final precio = int.tryParse(precioCtrl.text.trim());
                if (nombre.isEmpty ||
                    direccion.isEmpty ||
                    precio == null ||
                    precio <= 0) {
                  ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                      content: Text('Completa todos los campos')));
                  return;
                }
                if (dir == null) {
                  await widget.db.from('fn_red_direcciones').insert({
                    'sede_id': sedeId,
                    'nombre': nombre,
                    'direccion': direccion.toUpperCase(),
                    'precio': precio,
                    'activo': true,
                    'sector_id': sectorId,
                    if (gpsLat != null) 'lat': gpsLat,
                    if (gpsLng != null) 'lng': gpsLng,
                  });
                } else {
                  await widget.db.from('fn_red_direcciones').update({
                    'nombre': nombre,
                    'direccion': direccion.toUpperCase(),
                    'precio': precio,
                    'activo': activo,
                    'sector_id': sectorId,
                    'lat': gpsLat,
                    'lng': gpsLng,
                  }).eq('id', dir['id']);
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

  static (double?, double?) _parsearUrlMaps(String url) {
    var m = RegExp(r'@(-?\d{1,3}\.\d+),(-?\d{1,3}\.\d+)').firstMatch(url);
    if (m != null) return (double.tryParse(m.group(1)!), double.tryParse(m.group(2)!));
    m = RegExp(r'[?&]q=(-?\d{1,3}\.\d+),(-?\d{1,3}\.\d+)').firstMatch(url);
    if (m != null) return (double.tryParse(m.group(1)!), double.tryParse(m.group(2)!));
    m = RegExp(r'll=(-?\d{1,3}\.\d+),(-?\d{1,3}\.\d+)').firstMatch(url);
    if (m != null) return (double.tryParse(m.group(1)!), double.tryParse(m.group(2)!));
    m = RegExp(r'(-?\d{1,3}\.\d{4,}),(-?\d{1,3}\.\d{4,})').firstMatch(url);
    if (m != null) return (double.tryParse(m.group(1)!), double.tryParse(m.group(2)!));
    return (null, null);
  }

  Future<void> _eliminar(Map<String, dynamic> dir) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('¿Eliminar dirección?',
            style: TextStyle(color: Colors.white)),
        content: Text('${dir['nombre']} — ${dir['direccion']}',
            style: const TextStyle(color: Colors.white70)),
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
      await widget.db.from('fn_red_direcciones').delete().eq('id', dir['id']);
      _cargar();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    // Filtrar por sector seleccionado
    final filtradas = _filtroSectorId == null
        ? _direcciones
        : _direcciones
            .where((d) => d['sector_id'] == _filtroSectorId)
            .toList();

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF008FFF),
        icon: const Icon(Icons.add_location_alt, color: Colors.white),
        label: const Text('Agregar',
            style:
                TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        onPressed: _abrirFormulario,
      ),
      body: Column(
        children: [
          // ── Filtro por sector ─────────────────────────────────────────
          if (_sectores.isNotEmpty)
            Container(
              color: const Color(0xFF111111),
              height: 42,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                children: [
                  _chipFiltro('Todos', _filtroSectorId == null,
                      () => setState(() => _filtroSectorId = null)),
                  ..._sectores.map((s) => _chipFiltro(
                        s['nombre'].toString(),
                        _filtroSectorId == s['id'],
                        () => setState(
                            () => _filtroSectorId = s['id'] as int),
                      )),
                ],
              ),
            ),
          // ── Lista ─────────────────────────────────────────────────────
          Expanded(
            child: _cargando
                ? const Center(
                    child: CircularProgressIndicator(color: const Color(0xFF008FFF)))
                : filtradas.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.location_off,
                                color: Colors.white24, size: 48),
                            const SizedBox(height: 12),
                            const Text('Sin direcciones',
                                style: TextStyle(color: Colors.white38)),
                            const SizedBox(height: 8),
                            TextButton.icon(
                              onPressed: _abrirFormulario,
                              icon: const Icon(Icons.add, color: const Color(0xFF008FFF)),
                              label: const Text('Agregar primera dirección',
                                  style: TextStyle(color: const Color(0xFF008FFF))),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
                        itemCount: filtradas.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (ctx, i) {
                          final dir = filtradas[i];
                          final activo = dir['activo'] != false;
                          final sectorNombre =
                              (dir['fn_sectores'] as Map?)?['nombre']
                                  ?.toString();
                          return Container(
                            decoration: BoxDecoration(
                              color: activo
                                  ? const Color(0xFF1A1A1A)
                                  : const Color(0xFF111111),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: activo
                                    ? const Color(0xFF008FFF).withValues(alpha: 0.4)
                                    : Colors.white12,
                              ),
                            ),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: activo
                                    ? const Color(0xFF0070CC)
                                    : Colors.grey[800],
                                child: Icon(Icons.location_on,
                                    color: activo ? Colors.white : Colors.white38,
                                    size: 18),
                              ),
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      dir['nombre']?.toString() ?? '',
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
                                      margin: const EdgeInsets.only(left: 6),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF008FFF).withValues(alpha: 0.2),
                                        borderRadius:
                                            BorderRadius.circular(10),
                                        border: Border.all(
                                            color: const Color(0xFF008FFF).withValues(alpha: 0.5)),
                                      ),
                                      child: Text(
                                        sectorNombre,
                                        style: const TextStyle(
                                            color: const Color(0xFF008FFF),
                                            fontSize: 10),
                                      ),
                                    ),
                                ],
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    dir['direccion']?.toString() ?? '',
                                    style: TextStyle(
                                        color: activo
                                            ? Colors.white60
                                            : Colors.white24,
                                        fontSize: 12),
                                  ),
                                  Row(children: [
                                    Icon(Icons.attach_money,
                                        size: 13,
                                        color: activo
                                            ? Colors.greenAccent
                                            : Colors.white24),
                                    Text(
                                      '\$${_miles((dir['precio'] as num).toInt())}',
                                      style: TextStyle(
                                        color: activo
                                            ? Colors.greenAccent
                                            : Colors.white24,
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
                                              fontWeight: FontWeight.bold)),
                                    ],
                                  ]),
                                ],
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit_outlined,
                                        color: const Color(0xFF008FFF), size: 20),
                                    onPressed: () =>
                                        _abrirFormulario(dir: dir),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline,
                                        color: Colors.red, size: 20),
                                    onPressed: () => _eliminar(dir),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _chipFiltro(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color:
              selected ? const Color(0xFF008FFF) : const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: selected ? const Color(0xFF008FFF) : Colors.white24),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.white54,
            fontSize: 12,
            fontWeight:
                selected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// TAB 3 — TARIFAS POR SECTOR
// ═════════════════════════════════════════════════════════════════════════════

class _TabTarifas extends StatefulWidget {
  final Map<String, dynamic> sede;
  final SupabaseClient db;
  const _TabTarifas({required this.sede, required this.db});

  @override
  State<_TabTarifas> createState() => _TabTarifasState();
}

class _TabTarifasState extends State<_TabTarifas> {
  List<Map<String, dynamic>> _tarifas = [];
  List<Map<String, dynamic>> _sectores = [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void didUpdateWidget(_TabTarifas old) {
    super.didUpdateWidget(old);
    if (old.sede['id'] != widget.sede['id']) _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final tarifas = await widget.db
          .from('fn_tarifas_sede')
          .select('id, precio, sector_id, fn_sectores(nombre)')
          .eq('sede_id', widget.sede['id'])
          .order('precio', ascending: true);
      final sectores = await widget.db
          .from('fn_sectores')
          .select('id, nombre, municipio')
          .eq('activo', true)
          .order('nombre');
      if (mounted) {
        setState(() {
          _tarifas = List<Map<String, dynamic>>.from(tarifas);
          _sectores = List<Map<String, dynamic>>.from(sectores);
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

  static const _municipios = ['Cúcuta', 'Los Patios', 'Villa del Rosario'];

  Future<void> _abrirFormulario({Map<String, dynamic>? tarifa}) async {
    // Sectores ya configurados (excluir al agregar nuevo)
    final yaConfigurados = _tarifas
        .where((t) => t['id'] != tarifa?['id'])
        .map((t) => t['sector_id'] as int?)
        .toSet();

    final disponibles = tarifa != null
        ? _sectores
        : _sectores.where((s) => !yaConfigurados.contains(s['id'])).toList();

    if (disponibles.isEmpty && tarifa == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Todos los sectores ya tienen tarifa configurada.'),
        backgroundColor: Colors.orange,
      ));
      return;
    }

    // Al editar: pre-cargar municipio del sector actual
    int? sectorId = tarifa?['sector_id'] as int?;
    String? municipioSel = sectorId != null
        ? (_sectores.firstWhere(
            (s) => s['id'] == sectorId,
            orElse: () => {},
          )['municipio'] as String?)
        : null;

    final precioCtrl = TextEditingController(
        text: tarifa != null ? '${tarifa['precio']}' : '');

    final guardado = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          // Sectores del municipio seleccionado (o todos si no hay municipio)
          final sectoresFiltrados = municipioSel == null
              ? disponibles
              : disponibles
                  .where((s) => s['municipio'] == municipioSel)
                  .toList();

          // Si el sector seleccionado no pertenece al nuevo municipio, limpiar
          final sectorValido = sectoresFiltrados.any((s) => s['id'] == sectorId);

          return AlertDialog(
            backgroundColor: const Color(0xFF1A1A1A),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            title: Text(
              tarifa == null ? '➕ Nueva tarifa' : '✏️ Editar tarifa',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Municipio ──
                DropdownButtonFormField<String?>(
                  value: municipioSel,
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
                      child: Text('Selecciona municipio',
                          style: TextStyle(color: Colors.white54)),
                    ),
                    ..._municipios.map((m) => DropdownMenuItem<String?>(
                          value: m,
                          child: Text(m,
                              style: const TextStyle(color: Colors.white)),
                        )),
                  ],
                  onChanged: tarifa == null
                      ? (v) => setD(() {
                            municipioSel = v;
                            sectorId = null; // reset sector al cambiar municipio
                          })
                      : null,
                ),
                const SizedBox(height: 12),
                // ── Sector (filtrado por municipio) ──
                DropdownButtonFormField<int>(
                  value: sectorValido ? sectorId : null,
                  dropdownColor: const Color(0xFF1A1A1A),
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Sector',
                    labelStyle: const TextStyle(color: Colors.white54),
                    border: const OutlineInputBorder(),
                    isDense: true,
                    hintText: municipioSel == null
                        ? 'Selecciona municipio primero'
                        : sectoresFiltrados.isEmpty
                            ? 'Sin sectores en este municipio'
                            : null,
                    hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                  items: sectoresFiltrados
                      .map((s) => DropdownMenuItem<int>(
                            value: s['id'] as int,
                            child: Text(s['nombre'].toString(),
                                style: const TextStyle(color: Colors.white)),
                          ))
                      .toList(),
                  onChanged: (tarifa == null && municipioSel != null)
                      ? (v) => setD(() => sectorId = v)
                      : null,
                ),
                const SizedBox(height: 12),
                // ── Precio ──
                TextField(
                  controller: precioCtrl,
                  style: const TextStyle(color: Colors.white),
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Tarifa (\$)',
                    labelStyle: TextStyle(color: Colors.white54),
                    border: OutlineInputBorder(),
                    isDense: true,
                    prefixText: '\$ ',
                    prefixStyle: TextStyle(color: Colors.white70),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('CANCELAR',
                      style: TextStyle(color: Colors.white54))),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo[700]),
                onPressed: () async {
                  final precio = int.tryParse(precioCtrl.text.trim());
                  if (sectorId == null || precio == null || precio <= 0) {
                    ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                        content: Text('Selecciona municipio, sector e ingresa precio')));
                    return;
                  }
                  if (tarifa == null) {
                    await widget.db.from('fn_tarifas_sede').insert({
                      'sede_id': widget.sede['id'],
                      'sector_id': sectorId,
                      'precio': precio,
                    });
                  } else {
                    await widget.db.from('fn_tarifas_sede').update({
                      'precio': precio,
                    }).eq('id', tarifa['id']);
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

  Future<void> _eliminar(Map<String, dynamic> tarifa) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('¿Eliminar tarifa?',
            style: TextStyle(color: Colors.white)),
        content: Text(
          '${(tarifa['fn_sectores'] as Map?)?['nombre'] ?? 'Sector'} — \$${_miles((tarifa['precio'] as num).toInt())}',
          style: const TextStyle(color: Colors.white70),
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
      await widget.db.from('fn_tarifas_sede').delete().eq('id', tarifa['id']);
      _cargar();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Colors.indigo[700],
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Nueva tarifa',
            style:
                TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        onPressed: _abrirFormulario,
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: Colors.indigo))
          : Column(
              children: [
                // ── Cabecera informativa ──────────────────────────────────
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  color: const Color(0xFF0F0F0F),
                  child: Row(children: [
                    const Icon(Icons.info_outline,
                        color: Colors.white38, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Precio base por sector para ${_labelSede(widget.sede)}. Se aplica automáticamente al seleccionar una dirección del sector.',
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 11),
                      ),
                    ),
                  ]),
                ),
                // ── Lista ─────────────────────────────────────────────────
                Expanded(
                  child: _sectores.isEmpty
                      ? const Center(
                          child: Text(
                            'Crea primero sectores en la pestaña Sectores',
                            style: TextStyle(color: Colors.white38),
                            textAlign: TextAlign.center,
                          ),
                        )
                      : _tarifas.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.price_change,
                                      color: Colors.white24, size: 48),
                                  const SizedBox(height: 12),
                                  const Text('Sin tarifas configuradas',
                                      style:
                                          TextStyle(color: Colors.white38)),
                                  const SizedBox(height: 8),
                                  TextButton.icon(
                                    onPressed: _abrirFormulario,
                                    icon: const Icon(Icons.add,
                                        color: Colors.indigo),
                                    label: const Text('Agregar primera tarifa',
                                        style:
                                            TextStyle(color: Colors.indigo)),
                                  ),
                                ],
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(
                                  12, 12, 12, 100),
                              itemCount: _tarifas.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (ctx, i) {
                                final t = _tarifas[i];
                                final sNombre =
                                    (t['fn_sectores'] as Map?)?['nombre']
                                        ?.toString() ??
                                        'Sector';
                                return Container(
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1A1A1A),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                        color: Colors.indigo
                                            .withValues(alpha: 0.4)),
                                  ),
                                  child: ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor: Colors.indigo[800],
                                      child: const Icon(Icons.map,
                                          color: Colors.white,
                                          size: 18),
                                    ),
                                    title: Text(
                                      sNombre,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                    subtitle: Row(children: [
                                      const Icon(Icons.attach_money,
                                          size: 14,
                                          color: Colors.greenAccent),
                                      Text(
                                        '\$${_miles((t['precio'] as num).toInt())}',
                                        style: const TextStyle(
                                          color: Colors.greenAccent,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ]),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.edit_outlined,
                                              color: Colors.indigo, size: 20),
                                          onPressed: () =>
                                              _abrirFormulario(tarifa: t),
                                        ),
                                        IconButton(
                                          icon: const Icon(
                                              Icons.delete_outline,
                                              color: Colors.red,
                                              size: 20),
                                          onPressed: () => _eliminar(t),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                ),
              ],
            ),
    );
  }

  String _labelSede(Map<String, dynamic> s) {
    final tipo = s['tipo']?.toString() ?? '';
    final num = s['numero']?.toString() ?? '';
    final nombre = s['nombre']?.toString() ?? '';
    return nombre.isNotEmpty ? '$tipo$num – $nombre' : '$tipo$num';
  }
}
