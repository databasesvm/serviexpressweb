// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ─────────────────────────────────────────────────────────────────────────────
// FnRedDireccionesScreen
// Gestión de la red de direcciones con precio sugerido por sede FN.
// Acceso: Central → ícono 📍 en el header del panel FN.
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
  List<Map<String, dynamic>> _direcciones = [];
  bool _cargando = true;

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
          _cargando = false;
          if (lista.isNotEmpty) {
            _sedeSeleccionada = lista.first;
            _cargarDirecciones();
          }
        });
      }
    } catch (e) {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _cargarDirecciones() async {
    final sedeId = _sedeSeleccionada?['id'];
    if (sedeId == null) return;
    setState(() => _cargando = true);
    try {
      final data = await _db
          .from('fn_red_direcciones')
          .select('id, nombre, direccion, precio, activo')
          .eq('sede_id', sedeId)
          .order('nombre');
      if (mounted) {
        setState(() {
          _direcciones = List<Map<String, dynamic>>.from(data);
          _cargando = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _cargando = false);
    }
  }

  String _labelSede(Map<String, dynamic> s) {
    final tipo = s['tipo']?.toString() ?? '';
    final num = s['numero']?.toString() ?? '';
    final nombre = s['nombre']?.toString() ?? '';
    if (nombre.isNotEmpty) return '$tipo$num – $nombre';
    return '$tipo$num';
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
    final sedeId = _sedeSeleccionada?['id'];
    if (sedeId == null) return;

    final nombreCtrl = TextEditingController(text: dir?['nombre']?.toString() ?? '');
    final direccionCtrl = TextEditingController(text: dir?['direccion']?.toString() ?? '');
    final precioCtrl = TextEditingController(
      text: dir != null ? (dir['precio'] as num).toInt().toString() : '',
    );
    bool activo = dir?['activo'] != false;

    final guardado = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: Text(
            dir == null ? '➕ Nueva dirección' : '✏️ Editar dirección',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: nombreCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nombre / alias',
                  hintText: 'Ej: Clínica Norte',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: direccionCtrl,
                decoration: const InputDecoration(
                  labelText: 'Dirección completa',
                  hintText: 'Ej: Calle 10 # 5-20, Barrio X',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                maxLines: 2,
                textCapitalization: TextCapitalization.characters,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: precioCtrl,
                decoration: const InputDecoration(
                  labelText: 'Precio sugerido (\$)',
                  border: OutlineInputBorder(),
                  isDense: true,
                  prefixText: '\$ ',
                ),
                keyboardType: TextInputType.number,
              ),
              if (dir != null) ...[
                const SizedBox(height: 12),
                SwitchListTile(
                  value: activo,
                  onChanged: (v) => setD(() => activo = v),
                  title: const Text('Activa', style: TextStyle(fontSize: 13)),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ]),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('CANCELAR'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
              onPressed: () async {
                final nombre = nombreCtrl.text.trim();
                final direccion = direccionCtrl.text.trim();
                final precio = int.tryParse(precioCtrl.text.trim());
                if (nombre.isEmpty || direccion.isEmpty || precio == null || precio <= 0) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Completa todos los campos')),
                  );
                  return;
                }
                if (dir == null) {
                  await _db.from('fn_red_direcciones').insert({
                    'sede_id': sedeId,
                    'nombre': nombre,
                    'direccion': direccion.toUpperCase(),
                    'precio': precio,
                    'activo': true,
                  });
                } else {
                  await _db.from('fn_red_direcciones').update({
                    'nombre': nombre,
                    'direccion': direccion.toUpperCase(),
                    'precio': precio,
                    'activo': activo,
                  }).eq('id', dir['id']);
                }
                if (ctx.mounted) Navigator.pop(ctx, true);
              },
              child: const Text('GUARDAR',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );

    if (guardado == true) _cargarDirecciones();
  }

  Future<void> _eliminar(Map<String, dynamic> dir) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Eliminar dirección?'),
        content: Text('${dir['nombre']} — ${dir['direccion']}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('NO')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ELIMINAR', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _db.from('fn_red_direcciones').delete().eq('id', dir['id']);
      _cargarDirecciones();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF004D40),
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          '📍 Red de direcciones FN',
          style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
        ),
      ),
      floatingActionButton: _sedeSeleccionada != null
          ? FloatingActionButton.extended(
              backgroundColor: Colors.teal,
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text('Agregar', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              onPressed: _abrirFormulario,
            )
          : null,
      body: Column(
        children: [
          // ── Selector de sede ───────────────────────────────────────────────
          Container(
            color: const Color(0xFF0F0F0F),
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: _sedes.isEmpty
                ? const Text('Sin sedes', style: TextStyle(color: Colors.white38))
                : DropdownButtonFormField<int>(
                    value: _sedeSeleccionada?['id'] as int?,
                    dropdownColor: const Color(0xFF1A1A1A),
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Sede FN',
                      labelStyle: const TextStyle(color: Colors.white54),
                      border: const OutlineInputBorder(),
                      isDense: true,
                      filled: true,
                      fillColor: const Color(0xFF1A1A1A),
                    ),
                    items: _sedes
                        .map((s) => DropdownMenuItem<int>(
                              value: s['id'] as int,
                              child: Text(_labelSede(s),
                                  style: const TextStyle(color: Colors.white, fontSize: 13)),
                            ))
                        .toList(),
                    onChanged: (v) {
                      setState(() {
                        _sedeSeleccionada = _sedes.firstWhere((s) => s['id'] == v);
                      });
                      _cargarDirecciones();
                    },
                  ),
          ),

          // ── Lista de direcciones ───────────────────────────────────────────
          Expanded(
            child: _cargando
                ? const Center(child: CircularProgressIndicator(color: Colors.teal))
                : _direcciones.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.location_off, color: Colors.white24, size: 48),
                            const SizedBox(height: 12),
                            const Text('Sin direcciones para esta sede',
                                style: TextStyle(color: Colors.white38)),
                            const SizedBox(height: 8),
                            TextButton.icon(
                              onPressed: _abrirFormulario,
                              icon: const Icon(Icons.add, color: Colors.teal),
                              label: const Text('Agregar primera dirección',
                                  style: TextStyle(color: Colors.teal)),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
                        itemCount: _direcciones.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (ctx, i) {
                          final dir = _direcciones[i];
                          final activo = dir['activo'] != false;
                          return Container(
                            decoration: BoxDecoration(
                              color: activo
                                  ? const Color(0xFF1A1A1A)
                                  : const Color(0xFF111111),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: activo ? Colors.teal.withValues(alpha: 0.4) : Colors.white12,
                              ),
                            ),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor:
                                    activo ? Colors.teal[800] : Colors.grey[800],
                                child: Icon(Icons.location_on,
                                    color: activo ? Colors.teal[200] : Colors.white38,
                                    size: 18),
                              ),
                              title: Text(
                                dir['nombre']?.toString() ?? '',
                                style: TextStyle(
                                  color: activo ? Colors.white : Colors.white38,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    dir['direccion']?.toString() ?? '',
                                    style: TextStyle(
                                        color: activo ? Colors.white60 : Colors.white24,
                                        fontSize: 12),
                                  ),
                                  Row(children: [
                                    Icon(Icons.attach_money,
                                        size: 13,
                                        color: activo ? Colors.greenAccent : Colors.white24),
                                    Text(
                                      '\$${_miles((dir['precio'] as num).toInt())}',
                                      style: TextStyle(
                                        color: activo ? Colors.greenAccent : Colors.white24,
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
                                        color: Colors.teal, size: 20),
                                    onPressed: () => _abrirFormulario(dir: dir),
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
}
