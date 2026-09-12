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
          backgroundColor: const Color(0xFF002DA2),
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
              Tab(icon: Icon(Icons.map, size: 18), text: 'Sectores/Barrios'),
              Tab(icon: Icon(Icons.location_on, size: 18), text: 'Direcciones'),
            ],
          ),
        ),
        body: _cargandoSedes
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFF002DA2)))
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
  Map<int, int> _tarifasConvenio = {}; // sector_id → precio_convenio
  bool _cargando = true;
  String _filtroMun = 'Cúcuta';
  int? _filtroSector;
  // #99 — búsqueda de texto
  final _busquedaCtrl = TextEditingController();
  String _busqueda = '';
  // #108 — filtro por campo incompleto
  String? _filtroIncompleto; // null=todos | 'sinPrecio' | 'inactivo'

  static const _municipios = ['Cúcuta', 'Los Patios', 'V. Rosario'];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _busquedaCtrl.addListener(() => setState(() => _busqueda = _busquedaCtrl.text.trim().toLowerCase()));
    _cargar();
  }

  @override
  void dispose() {
    _busquedaCtrl.dispose();
    super.dispose();
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
          .select('id, nombre, activo, municipio, parent_id')
          .order('municipio')
          .order('nombre');
      final tars = await widget.db
          .from('fn_tarifas_sede')
          .select('sector_id, precio, precio_convenio')
          .eq('sede_id', widget.sede['id']);
      if (mounted) {
        final tarifaMap = <int, int>{};
        final convenioMap = <int, int>{};
        for (final t in List<Map<String, dynamic>>.from(tars)) {
          final sid = t['sector_id'] as int;
          tarifaMap[sid] = (t['precio'] as num).toInt();
          if (t['precio_convenio'] != null) {
            convenioMap[sid] = (t['precio_convenio'] as num).toInt();
          }
        }
        setState(() {
          _sectores = List<Map<String, dynamic>>.from(secs);
          _tarifas = tarifaMap;
          _tarifasConvenio = convenioMap;
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


  // Guardar/actualizar tarifa para esta sede (con precio_convenio opcional)
  Future<void> _guardarTarifa(int sectorId, int precio, {int? precioConvenio}) async {
    final existing = await widget.db
        .from('fn_tarifas_sede')
        .select('id')
        .eq('sede_id', widget.sede['id'])
        .eq('sector_id', sectorId)
        .maybeSingle();
    final data = {
      'precio': precio,
      'precio_convenio': precioConvenio,
    };
    if (existing != null) {
      await widget.db.from('fn_tarifas_sede').update(data).eq('id', existing['id']);
    } else {
      await widget.db.from('fn_tarifas_sede').insert({
        'sede_id': widget.sede['id'],
        'sector_id': sectorId,
        ...data,
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
    final precioConvenioCtrl = TextEditingController(
      text: sId != null && _tarifasConvenio.containsKey(sId)
          ? _tarifasConvenio[sId].toString()
          : '',
    );
    bool activo = sector?['activo'] != false;
    String? municipio =
        sector?['municipio']?.toString() ?? _filtroMun;
    int? parentId = sector?['parent_id'] as int?;

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
                  onChanged: (v) => setD(() { municipio = v; parentId = null; }),
                ),
                const SizedBox(height: 12),
                // 1b. ¿Barrio de...?
                Builder(builder: (ctx) {
                  final padres = _sectores
                      .where((s) =>
                          s['municipio'] == municipio &&
                          s['parent_id'] == null &&
                          (sId == null || s['id'] != sId))
                      .toList()
                    ..sort((a, b) => (a['nombre'] ?? '')
                        .toString()
                        .compareTo((b['nombre'] ?? '').toString()));
                  return DropdownButtonFormField<int?>(
                    value: padres.any((s) => s['id'] == parentId) ? parentId : null,
                    dropdownColor: const Color(0xFF1A1A1A),
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: '¿Barrio de...? (opcional)',
                      labelStyle: TextStyle(color: Colors.white54),
                      hintText: 'Dejar vacío si es sector raíz',
                      hintStyle: TextStyle(color: Colors.white24, fontSize: 12),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('— Es un sector raíz —',
                            style: TextStyle(color: Colors.white54, fontSize: 13)),
                      ),
                      ...padres.map((p) => DropdownMenuItem<int?>(
                            value: p['id'] as int,
                            child: Text(p['nombre']?.toString() ?? '',
                                style: const TextStyle(color: Colors.white)),
                          )),
                    ],
                    onChanged: (v) => setD(() => parentId = v),
                  );
                }),
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
                // 3a. Convenio (principal) → columna `precio`
                TextField(
                  controller: precioCtrl,
                  style: const TextStyle(color: Colors.white),
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Convenio (principal) (\$)',
                    labelStyle: TextStyle(color: Colors.amber),
                    hintText: 'Precio configurado del sector',
                    hintStyle: TextStyle(color: Colors.white24),
                    border: OutlineInputBorder(),
                    isDense: true,
                    prefixText: '\$ ',
                    prefixStyle: TextStyle(color: Colors.amber),
                  ),
                ),
                const SizedBox(height: 10),
                // 3b. Particular (opcional) → columna `precio_convenio`
                TextField(
                  controller: precioConvenioCtrl,
                  style: const TextStyle(color: Colors.white),
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Particular (opcional) (\$)',
                    labelStyle: TextStyle(color: Colors.white54),
                    hintText: 'Solo si aplica tarifa particular',
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
                  backgroundColor: const Color(0xFF002DA2)),
              onPressed: () async {
                final nombre = ctrl.text.trim();
                if (nombre.isEmpty) return;
                // #109 — detección de duplicado
                final duplicado = _sectores.any((s) =>
                    (s['nombre'] ?? '').toString().toLowerCase() == nombre.toLowerCase() &&
                    s['municipio'] == municipio &&
                    (sector == null || s['id'] != sector['id']));
                if (duplicado) {
                  ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                    content: Text('⚠️ Ya existe un sector/barrio con ese nombre en este municipio'),
                    backgroundColor: Colors.orange,
                  ));
                  return;
                }
                final nav = Navigator.of(ctx);
                try {
                  int newSectorId;
                  if (sector == null) {
                    final res = await widget.db
                        .from('sectores')
                        .insert({
                          'nombre': nombre,
                          'activo': true,
                          if (municipio != null) 'municipio': municipio,
                          if (parentId != null) 'parent_id': parentId,
                        })
                        .select('id')
                        .single();
                    newSectorId = res['id'] as int;
                  } else {
                    await widget.db.from('sectores').update({
                      'nombre': nombre,
                      'activo': activo,
                      'municipio': municipio,
                      'parent_id': parentId,
                    }).eq('id', sector['id']);
                    newSectorId = sector['id'] as int;
                  }
                  // MAPEO: precio (Convenio/principal) ← precioCtrl | precio_convenio (Particular/opcional) ← precioConvenioCtrl
                  final convenioTexto = precioCtrl.text.trim();
                  final convenioVal = int.tryParse(convenioTexto);
                  final particularVal = int.tryParse(precioConvenioCtrl.text.trim());
                  if (convenioVal != null && convenioVal > 0) {
                    await _guardarTarifa(
                      newSectorId,
                      convenioVal,              // → `precio` column (Convenio)
                      precioConvenio: particularVal, // → `precio_convenio` column (Particular, null si vacío)
                    );
                  } else if (convenioTexto.isEmpty && sector != null) {
                    // Usuario borró la tarifa convenio → eliminar tarifa existente
                    await widget.db
                        .from('fn_tarifas_sede')
                        .delete()
                        .eq('sede_id', widget.sede['id'])
                        .eq('sector_id', newSectorId);
                  }
                  nav.pop(true);
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text('Error al guardar: $e'),
                      backgroundColor: Colors.red,
                    ));
                  }
                }
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
    final precioConvenioActual = _tarifasConvenio[sId];
    final ctrl = TextEditingController(
        text: precioActual != null ? precioActual.toString() : '');
    final convenioCtrl = TextEditingController(
        text: precioConvenioActual != null ? precioConvenioActual.toString() : '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(
          'Tarifa — ${sector['nombre']}',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ctrl,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Convenio (principal) (\$)',
                labelStyle: TextStyle(color: Colors.amber),
                border: OutlineInputBorder(),
                isDense: true,
                prefixText: '\$ ',
                prefixStyle: TextStyle(color: Colors.white70),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: convenioCtrl,
              style: const TextStyle(color: Colors.white),
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Particular (opcional) (\$)',
                labelStyle: TextStyle(color: Colors.white54),
                border: OutlineInputBorder(),
                isDense: true,
                prefixText: '\$ ',
                prefixStyle: TextStyle(color: Colors.amber),
              ),
            ),
          ],
        ),
        actions: [
          if (precioActual != null)
            TextButton(
              onPressed: () async {
                final nav = Navigator.of(ctx);
                await widget.db
                    .from('fn_tarifas_sede')
                    .delete()
                    .eq('sede_id', widget.sede['id'])
                    .eq('sector_id', sId);
                nav.pop(true);
              },
              child: const Text('Quitar tarifa', style: TextStyle(color: Colors.red)),
            ),
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('CANCELAR', style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF002DA2)),
            onPressed: () async {
              final precio = int.tryParse(ctrl.text.trim());
              if (precio == null || precio <= 0) return;
              final convenio = int.tryParse(convenioCtrl.text.trim());
              final nav = Navigator.of(ctx);
              await _guardarTarifa(sId, precio, precioConvenio: convenio);
              nav.pop(true);
            },
            child: const Text('GUARDAR', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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

  // #108 — chip de filtro por campo incompleto
  Widget _chipFiltro(String label, String? valor) {
    final sel = _filtroIncompleto == valor;
    return GestureDetector(
      onTap: () => setState(() => _filtroIncompleto = valor),
      child: Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: sel ? const Color(0xFF002DA2) : const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: sel ? const Color(0xFF002DA2) : Colors.white24),
        ),
        child: Text(label,
            style: TextStyle(
                color: sel ? Colors.white : Colors.white54,
                fontSize: 11,
                fontWeight: sel ? FontWeight.bold : FontWeight.normal)),
      ),
    );
  }

  // #105 — actualización masiva de tarifas
  Future<void> _actualizarMasivo() async {
    final ajusteCtrl = TextEditingController();
    String modo = 'todos'; // 'todos' | 'sector'
    int? sectorSelId;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          final raices = _sectores
              .where((s) => s['municipio'] == _filtroMun && s['parent_id'] == null)
              .toList()
            ..sort((a, b) => (a['nombre'] ?? '').toString().compareTo((b['nombre'] ?? '').toString()));
          return AlertDialog(
            backgroundColor: const Color(0xFF1A1A1A),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            title: const Text('📈 Actualización masiva', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
            content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('Suma o resta \$X a todos los precios existentes.', style: TextStyle(color: Colors.white60, fontSize: 12)),
                const SizedBox(height: 12),
                TextField(
                  controller: ajusteCtrl,
                  style: const TextStyle(color: Colors.white),
                  keyboardType: const TextInputType.numberWithOptions(signed: true),
                  decoration: const InputDecoration(
                    labelText: 'Ajuste (\$X o -\$X)',
                    labelStyle: TextStyle(color: Colors.white54),
                    border: OutlineInputBorder(),
                    isDense: true,
                    prefixText: '\$ ',
                    prefixStyle: TextStyle(color: Colors.white70),
                    hintText: 'Ej: 500 o -200',
                    hintStyle: TextStyle(color: Colors.white24),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: modo,
                  dropdownColor: const Color(0xFF1A1A1A),
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(labelText: 'Aplicar a', labelStyle: TextStyle(color: Colors.white54), border: OutlineInputBorder(), isDense: true),
                  items: const [
                    DropdownMenuItem(value: 'todos', child: Text('Todos en este municipio', style: TextStyle(color: Colors.white))),
                    DropdownMenuItem(value: 'sector', child: Text('Un sector específico', style: TextStyle(color: Colors.white))),
                  ],
                  onChanged: (v) => setD(() { modo = v!; sectorSelId = null; }),
                ),
                if (modo == 'sector') ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int?>(
                    value: sectorSelId,
                    dropdownColor: const Color(0xFF1A1A1A),
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(labelText: 'Sector', labelStyle: TextStyle(color: Colors.white54), border: OutlineInputBorder(), isDense: true),
                    items: raices.map((s) => DropdownMenuItem<int?>(value: s['id'] as int, child: Text(s['nombre']?.toString() ?? '', style: const TextStyle(color: Colors.white)))).toList(),
                    onChanged: (v) => setD(() => sectorSelId = v),
                  ),
                ],
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCELAR', style: TextStyle(color: Colors.white54))),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF002DA2)),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('APLICAR', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );

    if (ok != true) return;
    final ajuste = int.tryParse(ajusteCtrl.text.trim());
    if (ajuste == null || ajuste == 0) return;

    try {
      // Obtener IDs de sectores a actualizar
      List<int> sectorIds;
      if (modo == 'sector' && sectorSelId != null) {
        // El sector raíz + sus barrios
        sectorIds = _sectores
            .where((s) => s['id'] == sectorSelId || s['parent_id'] == sectorSelId)
            .map<int>((s) => s['id'] as int)
            .toList();
      } else {
        sectorIds = _sectores
            .where((s) => s['municipio'] == _filtroMun)
            .map<int>((s) => s['id'] as int)
            .toList();
      }
      // Actualizar solo filas que ya tienen precio
      for (final sId in sectorIds) {
        if (_tarifas.containsKey(sId)) {
          final nuevoPrecio = (_tarifas[sId]! + ajuste).clamp(0, 9999999);
          await widget.db.from('fn_tarifas_sede')
              .update({'precio': nuevoPrecio})
              .eq('sede_id', widget.sede['id'])
              .eq('sector_id', sId);
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Precios actualizados (${ajuste > 0 ? '+' : ''}\$$ajuste)'),
          backgroundColor: Colors.green,
        ));
        _cargar();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    }
  }

  // #106 — copiar tarifas de otra sede
  Future<void> _copiarDeSede() async {
    List<Map<String, dynamic>> otrasSedes = [];
    try {
      final data = await widget.db.from('fn_sedes').select('id, tipo, numero, nombre').eq('activo', true).order('numero');
      otrasSedes = List<Map<String, dynamic>>.from(data).where((s) => s['id'] != widget.sede['id']).toList();
    } catch (_) {}

    if (!mounted) return;
    Map<String, dynamic>? fuenteSel;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: const Text('📋 Copiar tarifas de otra sede', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
          content: otrasSedes.isEmpty
              ? const Text('No hay otras sedes disponibles.', style: TextStyle(color: Colors.white54))
              : DropdownButtonFormField<int?>(
                  value: fuenteSel?['id'] as int?,
                  dropdownColor: const Color(0xFF1A1A1A),
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(labelText: 'Copiar desde', labelStyle: TextStyle(color: Colors.white54), border: OutlineInputBorder(), isDense: true),
                  items: otrasSedes.map((s) {
                    final label = (s['nombre']?.toString().isNotEmpty == true)
                        ? '${s['tipo']}${s['numero']} – ${s['nombre']}'
                        : '${s['tipo']}${s['numero']}';
                    return DropdownMenuItem<int?>(value: s['id'] as int, child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 13)));
                  }).toList(),
                  onChanged: (v) => setD(() => fuenteSel = otrasSedes.firstWhere((s) => s['id'] == v)),
                ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCELAR', style: TextStyle(color: Colors.white54))),
            if (otrasSedes.isNotEmpty)
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF002DA2)),
                onPressed: fuenteSel == null ? null : () => Navigator.pop(ctx, true),
                child: const Text('COPIAR', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
          ],
        ),
      ),
    );

    if (ok != true || fuenteSel == null) return;
    try {
      final tars = await widget.db.from('fn_tarifas_sede').select('sector_id, precio').eq('sede_id', fuenteSel!['id']);
      for (final t in List<Map<String, dynamic>>.from(tars)) {
        await widget.db.from('fn_tarifas_sede').upsert({
          'sede_id': widget.sede['id'],
          'sector_id': t['sector_id'],
          'precio': t['precio'],
        }, onConflict: 'sede_id,sector_id');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tarifas copiadas exitosamente'), backgroundColor: Colors.green));
        _cargar();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    }
  }

  // #106b — Copiar desde lista plantilla (sectores)
  Future<void> _copiarDeLista() async {
    final listas = await widget.db.from('listas_precios').select().order('nombre');
    final listasList = List<Map<String, dynamic>>.from(listas);
    if (listasList.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No hay listas plantilla. Créalas desde el panel Central → Red SE.'),
          backgroundColor: Colors.orange,
        ));
      }
      return;
    }
    int? listaId;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: const Text('Aplicar lista plantilla: sectores',
              style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
          content: DropdownButtonFormField<int>(
            value: listaId,
            dropdownColor: const Color(0xFF1A1A1A),
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'Lista plantilla',
              labelStyle: TextStyle(color: Colors.white54),
              isDense: true, border: OutlineInputBorder(),
            ),
            items: listasList.map((l) => DropdownMenuItem<int>(
              value: l['id'] as int,
              child: Text(l['nombre']?.toString() ?? '',
                  style: const TextStyle(color: Colors.white, fontSize: 13)),
            )).toList(),
            onChanged: (v) => setD(() => listaId = v),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false),
                child: const Text('CANCELAR', style: TextStyle(color: Colors.white54))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF002DA2)),
              onPressed: listaId == null ? null : () => Navigator.pop(ctx, true),
              child: const Text('APLICAR', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
    if (ok != true || listaId == null) return;
    try {
      final rows = await widget.db.from('lista_precios_sectores')
          .select('sector_id, precio').eq('lista_id', listaId!);
      for (final r in List<Map<String, dynamic>>.from(rows)) {
        await widget.db.from('fn_tarifas_sede').upsert({
          'sede_id': widget.sede['id'],
          'sector_id': r['sector_id'],
          'precio': r['precio'],
        }, onConflict: 'sede_id,sector_id');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('✅ Lista aplicada correctamente'),
          backgroundColor: Colors.green,
        ));
        _cargar();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      floatingActionButton: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // #105/#106 — menú de acciones masivas
          FloatingActionButton(
            heroTag: 'sec_menu',
            backgroundColor: const Color(0xFF1A1A1A),
            mini: true,
            tooltip: 'Acciones masivas',
            onPressed: () => showModalBottomSheet(
              context: context,
              backgroundColor: const Color(0xFF1A1A1A),
              shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
              builder: (_) => Wrap(children: [
                ListTile(
                  leading: const Icon(Icons.price_change, color: Color(0xFF002DA2)),
                  title: const Text('Actualizar precios masivamente', style: TextStyle(color: Colors.white)),
                  onTap: () { Navigator.pop(context); _actualizarMasivo(); },
                ),
                ListTile(
                  leading: const Icon(Icons.content_copy, color: Color(0xFF002DA2)),
                  title: const Text('Copiar precios de otra sede', style: TextStyle(color: Colors.white)),
                  onTap: () { Navigator.pop(context); _copiarDeSede(); },
                ),
                ListTile(
                  leading: const Icon(Icons.list_alt_outlined, color: Color(0xFF002DA2)),
                  title: const Text('Copiar desde lista plantilla', style: TextStyle(color: Colors.white)),
                  onTap: () { Navigator.pop(context); _copiarDeLista(); },
                ),
              ]),
            ),
            child: const Icon(Icons.more_vert, color: Colors.white70),
          ),
          const SizedBox(width: 8),
          FloatingActionButton.extended(
            heroTag: 'sec_add',
            backgroundColor: const Color(0xFF002DA2),
            icon: const Icon(Icons.add, color: Colors.white),
            label: const Text('Nuevo sector',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            onPressed: _abrirFormulario,
          ),
        ],
      ),
      body: _cargando
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF002DA2)))
          : Column(
              children: [
                // ── Filtro municipio ──────────────────────────────────────
                Container(
                  color: const Color(0xFF111111),
                  height: 42,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: _municipios.map((m) {
                      final sel = _filtroMun == m;
                      return GestureDetector(
                        onTap: () => setState(() { _filtroMun = m; _filtroSector = null; }),
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: sel
                                ? const Color(0xFF002DA2)
                                : const Color(0xFF1A1A1A),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: sel
                                    ? const Color(0xFF002DA2)
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
                // ── Sub-filtro sector (dropdown) ──────────────────────────
                Builder(builder: (ctx) {
                  final subSecs = _sectores
                      .where((s) => s['municipio'] == _filtroMun && s['parent_id'] == null)
                      .toList()
                    ..sort((a, b) => (a['nombre'] ?? '').toString()
                        .compareTo((b['nombre'] ?? '').toString()));
                  if (subSecs.isEmpty) return const SizedBox.shrink();
                  return Container(
                    color: const Color(0xFF0D0D0D),
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                    child: DropdownButtonFormField<int?>(
                      value: _filtroSector,
                      dropdownColor: const Color(0xFF1A1A1A),
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Colors.white24),
                        ),
                        prefixIcon: const Icon(Icons.map_outlined, color: Colors.white38, size: 16),
                      ),
                      items: [
                        const DropdownMenuItem<int?>(value: null, child: Text('Todos los sectores', style: TextStyle(color: Colors.white54))),
                        ...subSecs.map((s) => DropdownMenuItem<int?>(
                          value: s['id'] as int?,
                          child: Text(s['nombre']?.toString() ?? '', style: const TextStyle(color: Colors.white)),
                        )),
                      ],
                      onChanged: (v) => setState(() => _filtroSector = v),
                    ),
                  );
                }),
                // ── Barra de búsqueda (#99) ───────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                  child: TextField(
                    controller: _busquedaCtrl,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Buscar sector o barrio…',
                      hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                      isDense: true,
                      filled: true,
                      fillColor: const Color(0xFF1A1A1A),
                      prefixIcon: const Icon(Icons.search, color: Colors.white38, size: 18),
                      suffixIcon: _busqueda.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, color: Colors.white38, size: 16),
                              onPressed: () => _busquedaCtrl.clear(),
                            )
                          : null,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),
                ),
                // ── Chips filtro incompleto (#108) ────────────────────────
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
                  child: Row(
                    children: [
                      _chipFiltro('Todos', null),
                      _chipFiltro('Sin precio', 'sinPrecio'),
                      _chipFiltro('Inactivos', 'inactivo'),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Colors.white12),
                // ── Lista ─────────────────────────────────────────────────
                Expanded(
                  child: Builder(builder: (ctx) {
                    var filtrados = _sectores
                        .where((s) =>
                            s['municipio']?.toString() == _filtroMun &&
                            s['parent_id'] == null)
                        .toList();
                    if (_filtroSector != null) {
                      filtrados = filtrados
                          .where((s) => s['id'] == _filtroSector)
                          .toList();
                    }
                    // #99 — búsqueda de texto
                    if (_busqueda.isNotEmpty) {
                      filtrados = _sectores
                          .where((s) =>
                              s['municipio']?.toString() == _filtroMun &&
                              (s['nombre'] ?? '').toString().toLowerCase().contains(_busqueda))
                          .toList();
                    }
                    // #108 — filtro por campo incompleto
                    if (_filtroIncompleto == 'sinPrecio') {
                      filtrados = filtrados.where((s) => !_tarifas.containsKey(s['id'] as int)).toList();
                    } else if (_filtroIncompleto == 'inactivo') {
                      filtrados = filtrados.where((s) => s['activo'] == false).toList();
                    }
                    filtrados.sort((a, b) => (a['nombre'] ?? '')
                        .toString()
                        .compareTo((b['nombre'] ?? '').toString()));
                    if (filtrados.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.map_outlined,
                                color: Colors.white24, size: 48),
                            const SizedBox(height: 12),
                            Text(_busqueda.isNotEmpty ? 'Sin resultados para "$_busqueda"' : 'Sin sectores en $_filtroMun',
                                style: const TextStyle(color: Colors.white38)),
                            const SizedBox(height: 8),
                            if (_busqueda.isEmpty)
                            TextButton.icon(
                              onPressed: _abrirFormulario,
                              icon: const Icon(Icons.add,
                                  color: Color(0xFF002DA2)),
                              label: const Text('Crear primer sector',
                                  style:
                                      TextStyle(color: Color(0xFF002DA2))),
                            ),
                          ],
                        ),
                      );
                    }
                    // Expandir: sectores raíz + sus barrios anidados
                    final items = <Map<String, dynamic>>[];
                    for (final s in filtrados) {
                      items.add({...s, '_tipo': 'sector'});
                      final barrios = _sectores
                          .where((b) => b['parent_id'] == s['id'])
                          .toList()
                        ..sort((a, b) => (a['nombre'] ?? '').toString()
                            .compareTo((b['nombre'] ?? '').toString()));
                      for (final b in barrios) {
                        items.add({...b, '_tipo': 'barrio'});
                      }
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
                      itemCount: items.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: 6),
                      itemBuilder: (ctx, i) {
                        final s = items[i];
                        final sId = s['id'] as int;
                        final activo = s['activo'] != false;
                        final precio = _tarifas[sId];
                        final esBarrio = s['_tipo'] == 'barrio';
                        return Padding(
                          padding: EdgeInsets.only(left: esBarrio ? 20 : 0),
                          child: Container(
                          decoration: BoxDecoration(
                            color: activo
                                ? const Color(0xFF1A1A1A)
                                : const Color(0xFF111111),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: activo
                                  ? const Color(0xFF002DA2)
                                      .withValues(alpha: 0.4)
                                  : Colors.white12,
                            ),
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              radius: esBarrio ? 14 : 18,
                              backgroundColor: activo
                                  ? (esBarrio
                                      ? const Color(0xFF002DA2).withValues(alpha: 0.25)
                                      : const Color(0xFF0070CC))
                                  : Colors.grey[800],
                              child: Icon(
                                esBarrio ? Icons.location_city : Icons.map,
                                color: activo ? Colors.white : Colors.white38,
                                size: esBarrio ? 14 : 18,
                              ),
                            ),
                            title: Text(
                              s['nombre']?.toString() ?? '',
                              style: TextStyle(
                                color: activo ? Colors.white : Colors.white38,
                                fontWeight: esBarrio ? FontWeight.normal : FontWeight.bold,
                                fontSize: esBarrio ? 12 : 13,
                              ),
                            ),
                            subtitle: Row(
                              children: [
                                Text(
                                  activo ? 'Activo' : 'Inactivo',
                                  style: TextStyle(
                                    color: activo
                                        ? const Color(0xFF002DA2)
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
                                      color: Color(0xFF002DA2), size: 20),
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
                        ), // Container
                        ); // Padding
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
  Map<int, int> _preciosConvenio = {}; // dir_id → precio_convenio
  List<Map<String, dynamic>> _sectores = [];
  bool _cargando = true;
  String _filtroMun = 'Cúcuta';
  int? _filtroSector;
  // #101 — barrio sub-filtro (hijo del sector seleccionado)
  int? _filtroBarrio;
  // #99 — búsqueda de texto
  final _busquedaCtrl = TextEditingController();
  String _busqueda = '';
  // #108 — filtro por campo incompleto
  String? _filtroIncompleto; // null=todos | 'sinPrecio' | 'sinGps' | 'inactivo'

  static const _municipios = ['Cúcuta', 'Los Patios', 'V. Rosario'];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _busquedaCtrl.addListener(() => setState(() => _busqueda = _busquedaCtrl.text.trim().toLowerCase()));
    _cargar();
  }

  @override
  void dispose() {
    _busquedaCtrl.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(_TabDirecciones old) {
    super.didUpdateWidget(old);
    if (old.sede['id'] != widget.sede['id']) {
      _filtroMun = 'Cúcuta';
      _filtroSector = null;
      _filtroBarrio = null;
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
          .select('dir_id, precio, precio_convenio')
          .eq('sede_id', widget.sede['id']);
      final secs = await widget.db
          .from('sectores')
          .select('id, nombre, municipio, parent_id')
          .eq('activo', true)
          .order('municipio')
          .order('nombre');
      if (mounted) {
        final precioMap = <int, int>{};
        final convenioMap = <int, int>{};
        for (final p in List<Map<String, dynamic>>.from(precios)) {
          final did = p['dir_id'] as int;
          precioMap[did] = (p['precio'] as num).toInt();
          if (p['precio_convenio'] != null) {
            convenioMap[did] = (p['precio_convenio'] as num).toInt();
          }
        }
        setState(() {
          _dirs = List<Map<String, dynamic>>.from(dirs);
          _precios = precioMap;
          _preciosConvenio = convenioMap;
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
    final precioConvenioCtrl = TextEditingController(
      text: dId != null && _preciosConvenio.containsKey(dId)
          ? _preciosConvenio[dId].toString()
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
                  // 5a. Convenio (principal) para esta sede → columna `precio`
                  TextField(
                    controller: precioCtrl,
                    style: const TextStyle(color: Colors.white),
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Convenio (principal) (\$)',
                      labelStyle: TextStyle(color: Colors.amber),
                      hintText: 'Sin precio → no aparece en autocomplete',
                      hintStyle: TextStyle(color: Colors.white24, fontSize: 11),
                      border: OutlineInputBorder(),
                      isDense: true,
                      prefixText: '\$ ',
                      prefixStyle: TextStyle(color: Colors.white70),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // 5b. Particular (opcional) → columna `precio_convenio`
                  TextField(
                    controller: precioConvenioCtrl,
                    style: const TextStyle(color: Colors.white),
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Particular (opcional) (\$)',
                      labelStyle: TextStyle(color: Colors.white54),
                      hintText: 'Solo si aplica precio especial',
                      hintStyle: TextStyle(color: Colors.white24, fontSize: 11),
                      border: OutlineInputBorder(),
                      isDense: true,
                      prefixText: '\$ ',
                      prefixStyle: TextStyle(color: Colors.amber),
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
                              color: Color(0xFF002DA2), size: 18)
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
                            color: Color(0xFF002DA2), size: 13),
                        const SizedBox(width: 4),
                        Text(
                          'GPS: ${gpsLat!.toStringAsFixed(5)}, ${gpsLng!.toStringAsFixed(5)}',
                          style: const TextStyle(
                              color: Color(0xFF002DA2), fontSize: 11),
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
                    backgroundColor: const Color(0xFF002DA2)),
                onPressed: () async {
                  final nombre = nombreCtrl.text.trim();
                  final direccion = direccionCtrl.text.trim();
                  if (nombre.isEmpty || direccion.isEmpty) {
                    ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                        content:
                            Text('Nombre y dirección son obligatorios')));
                    return;
                  }
                  // #109 — detectar duplicado
                  final duplicado = _dirs.any((d) =>
                      (d['nombre'] ?? '').toString().toLowerCase() ==
                          nombre.toLowerCase() &&
                      d['municipio'] == municipio &&
                      (dir == null || d['id'] != dir['id']));
                  if (duplicado) {
                    ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                      content: Text(
                          '⚠️ Ya existe una dirección con ese nombre en este municipio'),
                      backgroundColor: Colors.orange,
                    ));
                    return;
                  }
                  final nav = Navigator.of(ctx);
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
                  final precioTexto = precioCtrl.text.trim();
                  final precio = int.tryParse(precioTexto);
                  final precioConvenio = int.tryParse(precioConvenioCtrl.text.trim());
                  if (precio != null && precio > 0) {
                    await widget.db
                        .from('fn_precios_dir')
                        .delete()
                        .eq('sede_id', widget.sede['id'])
                        .eq('dir_id', newDirId);
                    await widget.db.from('fn_precios_dir').insert({
                      'sede_id': widget.sede['id'],
                      'dir_id': newDirId,
                      'precio': precio,
                      'precio_convenio': precioConvenio,
                    });
                  } else if (precioTexto.isEmpty) {
                    await widget.db
                        .from('fn_precios_dir')
                        .delete()
                        .eq('sede_id', widget.sede['id'])
                        .eq('dir_id', newDirId);
                  }
                  nav.pop(true);
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

  Widget _chip(String label, bool selected, VoidCallback onTap, {bool small = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: EdgeInsets.only(right: small ? 6 : 8),
        padding: small
            ? const EdgeInsets.symmetric(horizontal: 10, vertical: 2)
            : const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: selected
              ? small
                  ? const Color(0xFF002DA2).withValues(alpha: 0.25)
                  : const Color(0xFF002DA2)
              : small ? Colors.transparent : const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: selected ? const Color(0xFF002DA2) : Colors.white24),
        ),
        child: Text(label,
            style: TextStyle(
              color: selected ? Colors.white : Colors.white54,
              fontSize: small ? 11 : 12,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            )),
      ),
    );
  }

  // #108 — chip de filtro incompleto (dirs)
  Widget _chipFiltro(String label, String? valor) {
    final sel = _filtroIncompleto == valor;
    return GestureDetector(
      onTap: () => setState(() => _filtroIncompleto = valor),
      child: Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: sel ? const Color(0xFF002DA2) : const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: sel ? const Color(0xFF002DA2) : Colors.white24),
        ),
        child: Text(label,
            style: TextStyle(
                color: sel ? Colors.white : Colors.white54,
                fontSize: 11,
                fontWeight: sel ? FontWeight.bold : FontWeight.normal)),
      ),
    );
  }

  // #105 — actualización masiva de precios (dirs)
  Future<void> _actualizarMasivo() async {
    final ajusteCtrl = TextEditingController();
    String modo = 'todos';
    int? sectorSelId;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          final raices = _sectores
              .where((s) => s['municipio'] == _filtroMun && s['parent_id'] == null)
              .toList()
            ..sort((a, b) => (a['nombre'] ?? '').toString().compareTo((b['nombre'] ?? '').toString()));
          return AlertDialog(
            backgroundColor: const Color(0xFF1A1A1A),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            title: const Text('📈 Actualización masiva', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
            content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('Suma o resta \$X a los precios existentes.', style: TextStyle(color: Colors.white60, fontSize: 12)),
              const SizedBox(height: 12),
              TextField(
                controller: ajusteCtrl,
                style: const TextStyle(color: Colors.white),
                keyboardType: const TextInputType.numberWithOptions(signed: true),
                decoration: const InputDecoration(
                  labelText: 'Ajuste (\$X o -\$X)',
                  labelStyle: TextStyle(color: Colors.white54),
                  border: OutlineInputBorder(),
                  isDense: true,
                  prefixText: '\$ ',
                  prefixStyle: TextStyle(color: Colors.white70),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: modo,
                dropdownColor: const Color(0xFF1A1A1A),
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: 'Aplicar a', labelStyle: TextStyle(color: Colors.white54), border: OutlineInputBorder(), isDense: true),
                items: const [
                  DropdownMenuItem(value: 'todos', child: Text('Todas las direcciones del municipio', style: TextStyle(color: Colors.white))),
                  DropdownMenuItem(value: 'sector', child: Text('Un sector específico', style: TextStyle(color: Colors.white))),
                ],
                onChanged: (v) => setD(() { modo = v!; sectorSelId = null; }),
              ),
              if (modo == 'sector') ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<int?>(
                  value: sectorSelId,
                  dropdownColor: const Color(0xFF1A1A1A),
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(labelText: 'Sector', labelStyle: TextStyle(color: Colors.white54), border: OutlineInputBorder(), isDense: true),
                  items: raices.map((s) => DropdownMenuItem<int?>(value: s['id'] as int, child: Text(s['nombre']?.toString() ?? '', style: const TextStyle(color: Colors.white)))).toList(),
                  onChanged: (v) => setD(() => sectorSelId = v),
                ),
              ],
            ])),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCELAR', style: TextStyle(color: Colors.white54))),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF002DA2)),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('APLICAR', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );

    if (ok != true) return;
    final ajuste = int.tryParse(ajusteCtrl.text.trim());
    if (ajuste == null || ajuste == 0) return;

    try {
      // Obtener dir_ids según el filtro
      List<int> dirIds;
      if (modo == 'sector' && sectorSelId != null) {
        final secIds = _sectores
            .where((s) => s['id'] == sectorSelId || s['parent_id'] == sectorSelId)
            .map<int>((s) => s['id'] as int)
            .toList();
        dirIds = _dirs
            .where((d) => d['municipio'] == _filtroMun && secIds.contains(d['sector_id']))
            .map<int>((d) => d['id'] as int)
            .toList();
      } else {
        dirIds = _dirs
            .where((d) => d['municipio'] == _filtroMun)
            .map<int>((d) => d['id'] as int)
            .toList();
      }

      for (final dId in dirIds) {
        if (_precios.containsKey(dId)) {
          final nuevo = (_precios[dId]! + ajuste).clamp(0, 9999999);
          await widget.db.from('fn_precios_dir')
              .update({'precio': nuevo})
              .eq('sede_id', widget.sede['id'])
              .eq('dir_id', dId);
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Precios actualizados (${ajuste > 0 ? '+' : ''}\$$ajuste)'),
          backgroundColor: Colors.green,
        ));
        _cargar();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    }
  }

  // #106 — copiar precios de otra sede (dirs)
  Future<void> _copiarDeSede() async {
    List<Map<String, dynamic>> otrasSedes = [];
    try {
      final data = await widget.db.from('fn_sedes').select('id, tipo, numero, nombre').eq('activo', true).order('numero');
      otrasSedes = List<Map<String, dynamic>>.from(data).where((s) => s['id'] != widget.sede['id']).toList();
    } catch (_) {}

    if (!mounted) return;
    Map<String, dynamic>? fuenteSel;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: const Text('📋 Copiar precios de otra sede', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
          content: otrasSedes.isEmpty
              ? const Text('No hay otras sedes disponibles.', style: TextStyle(color: Colors.white54))
              : DropdownButtonFormField<int?>(
                  value: fuenteSel?['id'] as int?,
                  dropdownColor: const Color(0xFF1A1A1A),
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(labelText: 'Copiar desde', labelStyle: TextStyle(color: Colors.white54), border: OutlineInputBorder(), isDense: true),
                  items: otrasSedes.map((s) {
                    final label = (s['nombre']?.toString().isNotEmpty == true)
                        ? '${s['tipo']}${s['numero']} – ${s['nombre']}'
                        : '${s['tipo']}${s['numero']}';
                    return DropdownMenuItem<int?>(value: s['id'] as int, child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 13)));
                  }).toList(),
                  onChanged: (v) => setD(() => fuenteSel = otrasSedes.firstWhere((s) => s['id'] == v)),
                ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCELAR', style: TextStyle(color: Colors.white54))),
            if (otrasSedes.isNotEmpty)
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF002DA2)),
                onPressed: fuenteSel == null ? null : () => Navigator.pop(ctx, true),
                child: const Text('COPIAR', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
          ],
        ),
      ),
    );

    if (ok != true || fuenteSel == null) return;
    try {
      final precios = await widget.db.from('fn_precios_dir').select('dir_id, precio').eq('sede_id', fuenteSel!['id']);
      for (final p in List<Map<String, dynamic>>.from(precios)) {
        await widget.db.from('fn_precios_dir').upsert({
          'sede_id': widget.sede['id'],
          'dir_id': p['dir_id'],
          'precio': p['precio'],
        }, onConflict: 'sede_id,dir_id');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Precios copiados exitosamente'), backgroundColor: Colors.green));
        _cargar();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    }
  }

  // #106b — Copiar desde lista plantilla (direcciones)
  Future<void> _copiarDeLista() async {
    final listas = await widget.db.from('listas_precios').select().order('nombre');
    final listasList = List<Map<String, dynamic>>.from(listas);
    if (listasList.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No hay listas plantilla. Créalas desde el panel Central → Red SE.'),
          backgroundColor: Colors.orange,
        ));
      }
      return;
    }
    int? listaId;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: const Text('Aplicar lista plantilla: direcciones',
              style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
          content: DropdownButtonFormField<int>(
            value: listaId,
            dropdownColor: const Color(0xFF1A1A1A),
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'Lista plantilla',
              labelStyle: TextStyle(color: Colors.white54),
              isDense: true, border: OutlineInputBorder(),
            ),
            items: listasList.map((l) => DropdownMenuItem<int>(
              value: l['id'] as int,
              child: Text(l['nombre']?.toString() ?? '',
                  style: const TextStyle(color: Colors.white, fontSize: 13)),
            )).toList(),
            onChanged: (v) => setD(() => listaId = v),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false),
                child: const Text('CANCELAR', style: TextStyle(color: Colors.white54))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF002DA2)),
              onPressed: listaId == null ? null : () => Navigator.pop(ctx, true),
              child: const Text('APLICAR', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
    if (ok != true || listaId == null) return;
    try {
      final rows = await widget.db.from('lista_precios_dirs')
          .select('dir_id, precio').eq('lista_id', listaId!);
      for (final r in List<Map<String, dynamic>>.from(rows)) {
        await widget.db.from('fn_precios_dir').upsert({
          'sede_id': widget.sede['id'],
          'dir_id': r['dir_id'],
          'precio': r['precio'],
        }, onConflict: 'sede_id,dir_id');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('✅ Lista aplicada correctamente'),
          backgroundColor: Colors.green,
        ));
        _cargar();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      floatingActionButton: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: 'dir_menu',
            backgroundColor: const Color(0xFF1A1A1A),
            mini: true,
            tooltip: 'Acciones masivas',
            onPressed: () => showModalBottomSheet(
              context: context,
              backgroundColor: const Color(0xFF1A1A1A),
              shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
              builder: (_) => Wrap(children: [
                ListTile(
                  leading: const Icon(Icons.price_change, color: Color(0xFF002DA2)),
                  title: const Text('Actualizar precios masivamente', style: TextStyle(color: Colors.white)),
                  onTap: () { Navigator.pop(context); _actualizarMasivo(); },
                ),
                ListTile(
                  leading: const Icon(Icons.content_copy, color: Color(0xFF002DA2)),
                  title: const Text('Copiar precios de otra sede', style: TextStyle(color: Colors.white)),
                  onTap: () { Navigator.pop(context); _copiarDeSede(); },
                ),
                ListTile(
                  leading: const Icon(Icons.list_alt_outlined, color: Color(0xFF002DA2)),
                  title: const Text('Copiar desde lista plantilla', style: TextStyle(color: Colors.white)),
                  onTap: () { Navigator.pop(context); _copiarDeLista(); },
                ),
              ]),
            ),
            child: const Icon(Icons.more_vert, color: Colors.white70),
          ),
          const SizedBox(width: 8),
          FloatingActionButton.extended(
            heroTag: 'dir_add',
            backgroundColor: const Color(0xFF002DA2),
            icon: const Icon(Icons.add_location_alt, color: Colors.white),
            label: const Text('Nueva dirección',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            onPressed: _abrirFormulario,
          ),
        ],
      ),
      body: _cargando
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF002DA2)))
          : Column(
              children: [
                // ── Filtro municipio ──────────────────────────────────────
                Container(
                  color: const Color(0xFF111111),
                  height: 42,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: _municipios
                        .map((m) => _chip(m, _filtroMun == m,
                            () => setState(() { _filtroMun = m; _filtroSector = null; _filtroBarrio = null; })))
                        .toList(),
                  ),
                ),
                // ── Sub-filtro sector raíz (#101) ──────────────────────────
                Builder(builder: (ctx) {
                  final raices = _sectores
                      .where((s) => s['municipio'] == _filtroMun && s['parent_id'] == null)
                      .toList()
                    ..sort((a, b) => (a['nombre'] ?? '').toString()
                        .compareTo((b['nombre'] ?? '').toString()));
                  if (raices.isEmpty) return const SizedBox.shrink();
                  return Container(
                    color: const Color(0xFF0D0D0D),
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                    child: DropdownButtonFormField<int?>(
                      value: _filtroSector,
                      dropdownColor: const Color(0xFF1A1A1A),
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Colors.white24),
                        ),
                        prefixIcon: const Icon(Icons.map_outlined, color: Colors.white38, size: 16),
                      ),
                      items: [
                        const DropdownMenuItem<int?>(value: null, child: Text('Todos los sectores', style: TextStyle(color: Colors.white54))),
                        ...raices.map((s) => DropdownMenuItem<int?>(
                          value: s['id'] as int?,
                          child: Text(s['nombre']?.toString() ?? '', style: const TextStyle(color: Colors.white)),
                        )),
                      ],
                      onChanged: (v) => setState(() { _filtroSector = v; _filtroBarrio = null; }),
                    ),
                  );
                }),
                // ── Sub-filtro barrio (#101) ──────────────────────────────
                if (_filtroSector != null)
                  Builder(builder: (ctx) {
                    final barrios = _sectores
                        .where((s) => s['parent_id'] == _filtroSector)
                        .toList()
                      ..sort((a, b) => (a['nombre'] ?? '').toString().compareTo((b['nombre'] ?? '').toString()));
                    if (barrios.isEmpty) return const SizedBox.shrink();
                    return Container(
                      color: const Color(0xFF0A0A0A),
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                      child: DropdownButtonFormField<int?>(
                        value: _filtroBarrio,
                        dropdownColor: const Color(0xFF1A1A1A),
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: Colors.white12),
                          ),
                          prefixIcon: const Icon(Icons.location_city, color: Colors.white38, size: 16),
                        ),
                        items: [
                          const DropdownMenuItem<int?>(value: null, child: Text('Todos los barrios', style: TextStyle(color: Colors.white54))),
                          ...barrios.map((b) => DropdownMenuItem<int?>(
                            value: b['id'] as int?,
                            child: Text(b['nombre']?.toString() ?? '', style: const TextStyle(color: Colors.white)),
                          )),
                        ],
                        onChanged: (v) => setState(() => _filtroBarrio = v),
                      ),
                    );
                  }),
                // ── Barra de búsqueda (#99) ───────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                  child: TextField(
                    controller: _busquedaCtrl,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Buscar dirección, nombre o alias…',
                      hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                      isDense: true,
                      filled: true,
                      fillColor: const Color(0xFF1A1A1A),
                      prefixIcon: const Icon(Icons.search, color: Colors.white38, size: 18),
                      suffixIcon: _busqueda.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, color: Colors.white38, size: 16),
                              onPressed: () => _busquedaCtrl.clear(),
                            )
                          : null,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),
                ),
                // ── Chips filtro incompleto (#108) ────────────────────────
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
                  child: Row(children: [
                    _chipFiltro('Todos', null),
                    _chipFiltro('Sin precio', 'sinPrecio'),
                    _chipFiltro('Sin GPS', 'sinGps'),
                    _chipFiltro('Inactivas', 'inactivo'),
                  ]),
                ),
                const Divider(height: 1, color: Colors.white12),
                // ── Lista ─────────────────────────────────────────────────
                Expanded(
                  child: Builder(builder: (ctx) {
                    var filtradas = _dirs
                        .where((d) =>
                            d['municipio']?.toString() == _filtroMun)
                        .toList();
                    if (_filtroSector != null) {
                      if (_filtroBarrio != null) {
                        // barrio específico
                        filtradas = filtradas.where((d) => d['sector_id'] == _filtroBarrio).toList();
                      } else {
                        // sector raíz + sus barrios
                        final secIds = _sectores
                            .where((s) => s['id'] == _filtroSector || s['parent_id'] == _filtroSector)
                            .map<int>((s) => s['id'] as int)
                            .toList();
                        filtradas = filtradas.where((d) => secIds.contains(d['sector_id'])).toList();
                      }
                    }
                    // #99 — búsqueda de texto
                    if (_busqueda.isNotEmpty) {
                      filtradas = filtradas.where((d) {
                        final n = (d['nombre'] ?? '').toString().toLowerCase();
                        final a = (d['alias'] ?? '').toString().toLowerCase();
                        final dir = (d['direccion'] ?? '').toString().toLowerCase();
                        return n.contains(_busqueda) || a.contains(_busqueda) || dir.contains(_busqueda);
                      }).toList();
                    }
                    // #108 — filtro por campo incompleto
                    if (_filtroIncompleto == 'sinPrecio') {
                      filtradas = filtradas.where((d) => !_precios.containsKey(d['id'] as int)).toList();
                    } else if (_filtroIncompleto == 'sinGps') {
                      filtradas = filtradas.where((d) => d['lat'] == null || d['lng'] == null).toList();
                    } else if (_filtroIncompleto == 'inactivo') {
                      filtradas = filtradas.where((d) => d['activo'] == false).toList();
                    }
                    filtradas.sort((a, b) => (a['nombre'] ?? '')
                        .toString()
                        .compareTo((b['nombre'] ?? '').toString()));
                    if (filtradas.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.location_off,
                                color: Colors.white24, size: 48),
                            const SizedBox(height: 12),
                            Text(_busqueda.isNotEmpty ? 'Sin resultados para "$_busqueda"' : 'Sin direcciones en $_filtroMun',
                                style: const TextStyle(
                                    color: Colors.white38)),
                            const SizedBox(height: 8),
                            if (_busqueda.isEmpty)
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF002DA2)),
                              onPressed: _abrirFormulario,
                              icon: const Icon(Icons.add, color: Colors.white, size: 16),
                              label: const Text('Agregar primera dirección',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold)),
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
                                  ? const Color(0xFF002DA2)
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
                                      color: const Color(0xFF002DA2)
                                          .withValues(alpha: 0.2),
                                      borderRadius:
                                          BorderRadius.circular(10),
                                      border: Border.all(
                                          color: const Color(0xFF002DA2)
                                              .withValues(alpha: 0.5)),
                                    ),
                                    child: Text(sectorNombre,
                                        style: const TextStyle(
                                            color: Colors.white,
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
                            trailing: SizedBox(
                              width: 80,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    constraints: const BoxConstraints(),
                                    padding: const EdgeInsets.all(4),
                                    icon: const Icon(Icons.edit_outlined,
                                        color: Color(0xFF002DA2), size: 20),
                                    onPressed: () =>
                                        _abrirFormulario(dir: d),
                                  ),
                                  IconButton(
                                    constraints: const BoxConstraints(),
                                    padding: const EdgeInsets.all(4),
                                    icon: const Icon(
                                        Icons.delete_outline,
                                        color: Colors.red,
                                        size: 20),
                                    onPressed: () => _eliminar(d),
                                  ),
                                ],
                              ),
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
