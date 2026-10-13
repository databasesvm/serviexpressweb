// lib/screens/rutas_aprendidas_screen.dart
//
// RUTAS Y PRECIOS APRENDIDOS (Central)
// Cada servicio finalizado de un local alimenta su ruta "local → destino".
// Aquí la central revisa lo aprendido y puede:
//   • fijar un precio (manda sobre lo aprendido) o quitarlo,
//   • unir dos rutas que son el mismo destino escrito distinto,
//   • pasar una ruta a la lista de precios del local,
//   • borrar una ruta.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RutasAprendidasScreen extends StatefulWidget {
  const RutasAprendidasScreen({super.key});
  @override
  State<RutasAprendidasScreen> createState() => _RutasAprendidasScreenState();
}

class _RutasAprendidasScreenState extends State<RutasAprendidasScreen> {
  final _db = Supabase.instance.client;
  List<Map<String, dynamic>> _rutas = [];
  bool _cargando = true;
  String _busqueda = '';
  int? _localFiltro;

  static const _fondo = Color(0xFF111111);
  static const _tarjeta = Color(0xFF1A1A1A);

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final data = await _db
          .from('rutas_precios')
          .select('id, local_id, tipo_servicio, destino, destino_norm, dest_lat, n, '
              'precio_sugerido, precio_min, precio_max, ultimo_precio, ultimo_at, '
              'precio_fijado, usuarios(nombre), rutas_alias(alias_norm)')
          // Solo rutas con servicios finalizados o con precio fijado
          // (las creadas por confirmaciones aún no tienen historial).
          .or('n.gt.0,precio_fijado.not.is.null')
          .order('n', ascending: false)
          .limit(500);
      if (!mounted) return;
      setState(() {
        _rutas = List<Map<String, dynamic>>.from(data);
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _cargando = false);
      _aviso('Error al cargar: $e', error: true);
    }
  }

  void _aviso(String t, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(t),
      backgroundColor: error ? Colors.red : const Color(0xFF2E7D32),
      behavior: SnackBarBehavior.floating,
    ));
  }

  String _pesos(num? v) {
    if (v == null) return '—';
    final s = v.round().toString();
    final b = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
      b.write(s[i]);
    }
    return '\$$b';
  }

  String _nombreLocal(Map r) =>
      ((r['usuarios'] as Map?)?['nombre'] ?? 'Local').toString();

  List<Map<String, dynamic>> get _filtradas {
    final q = _busqueda.trim().toUpperCase();
    return _rutas.where((r) {
      if (_localFiltro != null && r['local_id'] != _localFiltro) return false;
      if (q.isEmpty) return true;
      final alias = ((r['rutas_alias'] as List?) ?? [])
          .map((a) => (a as Map)['alias_norm'].toString())
          .join(' ');
      return '${r['destino_norm']} $alias ${_nombreLocal(r).toUpperCase()}'.contains(q);
    }).toList();
  }

  Future<int?> _pedirPrecio(String titulo, int? inicial) async {
    final ctrl = TextEditingController(text: inicial?.toString() ?? '');
    return showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _tarjeta,
        title: Text(titulo, style: const TextStyle(color: Colors.white, fontSize: 15)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            prefixText: '\$ ',
            hintText: 'Ej: 7000',
            hintStyle: TextStyle(color: Colors.white24),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('CANCELAR', style: TextStyle(color: Colors.white38))),
          ElevatedButton(
            onPressed: () {
              final v = int.tryParse(ctrl.text.trim());
              if (v == null || v < 1000) return;
              Navigator.pop(ctx, v);
            },
            child: const Text('GUARDAR'),
          ),
        ],
      ),
    );
  }

  Future<void> _rpc(String fn, Map<String, dynamic> params, String ok) async {
    try {
      await _db.rpc(fn, params: params);
      _aviso(ok);
      await _cargar();
    } catch (e) {
      _aviso('Error: $e', error: true);
    }
  }

  Future<void> _unir(Map<String, dynamic> r) async {
    final candidatas = _rutas
        .where((x) => x['local_id'] == r['local_id'] && x['id'] != r['id'])
        .toList();
    if (candidatas.isEmpty) {
      _aviso('Este local no tiene otras rutas para unir.', error: true);
      return;
    }
    final otra = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => SimpleDialog(
        backgroundColor: _tarjeta,
        title: Text('¿Qué ruta es el mismo destino que «${r['destino']}»?',
            style: const TextStyle(color: Colors.white, fontSize: 14)),
        children: candidatas
            .map((c) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, c),
                  child: Text('${c['destino']}  ·  ${c['n']} serv. · ${_pesos(c['precio_sugerido'])}',
                      style: const TextStyle(color: Colors.white70)),
                ))
            .toList(),
      ),
    );
    if (otra == null) return;
    await _rpc('fn_ruta_unir', {'p_dejar': r['id'], 'p_quitar': otra['id']},
        'Rutas unidas: «${otra['destino']}» ahora cuenta como «${r['destino']}»');
  }

  void _acciones(Map<String, dynamic> r) {
    showModalBottomSheet(
      context: context,
      backgroundColor: _tarjeta,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            title: Text('${r['destino']}',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            subtitle: Text(_nombreLocal(r), style: const TextStyle(color: Colors.white54)),
          ),
          const Divider(color: Colors.white10, height: 1),
          ListTile(
            leading: const Icon(Icons.push_pin_rounded, color: Colors.amber),
            title: const Text('Fijar precio', style: TextStyle(color: Colors.white)),
            subtitle: const Text('Manda sobre lo aprendido', style: TextStyle(color: Colors.white38)),
            onTap: () async {
              Navigator.pop(ctx);
              final p = await _pedirPrecio('Precio fijo para «${r['destino']}»',
                  (r['precio_fijado'] ?? r['precio_sugerido']) as int?);
              if (p != null) {
                await _rpc('fn_ruta_fijar_precio', {'p_ruta': r['id'], 'p_precio': p}, 'Precio fijado');
              }
            },
          ),
          if (r['precio_fijado'] != null)
            ListTile(
              leading: const Icon(Icons.push_pin_outlined, color: Colors.white54),
              title: const Text('Quitar precio fijo', style: TextStyle(color: Colors.white)),
              onTap: () async {
                Navigator.pop(ctx);
                await _rpc('fn_ruta_fijar_precio', {'p_ruta': r['id'], 'p_precio': null},
                    'Vuelve a usar el precio aprendido');
              },
            ),
          ListTile(
            leading: const Icon(Icons.merge_type_rounded, color: Colors.lightBlueAccent),
            title: const Text('Unir con otra ruta (mismo destino)', style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(ctx);
              _unir(r);
            },
          ),
          ListTile(
            leading: const Icon(Icons.playlist_add_rounded, color: Color(0xFF3AF500)),
            title: const Text('Pasar a la lista de precios del local', style: TextStyle(color: Colors.white)),
            onTap: () async {
              Navigator.pop(ctx);
              final p = await _pedirPrecio('Precio en la lista del local',
                  (r['precio_fijado'] ?? r['precio_sugerido']) as int?);
              if (p != null) {
                await _rpc('fn_ruta_a_lista_local', {'p_ruta': r['id'], 'p_precio': p},
                    'Agregada a la lista de precios de ${_nombreLocal(r)}');
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
            title: const Text('Borrar ruta', style: TextStyle(color: Colors.redAccent)),
            onTap: () async {
              Navigator.pop(ctx);
              final ok = await showDialog<bool>(
                context: context,
                builder: (c2) => AlertDialog(
                  backgroundColor: _tarjeta,
                  content: Text('¿Borrar la ruta «${r['destino']}»? Se vuelve a aprender con los próximos servicios.',
                      style: const TextStyle(color: Colors.white70)),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(c2, false), child: const Text('NO')),
                    TextButton(
                        onPressed: () => Navigator.pop(c2, true),
                        child: const Text('BORRAR', style: TextStyle(color: Colors.redAccent))),
                  ],
                ),
              );
              if (ok == true) await _rpc('fn_ruta_borrar', {'p_ruta': r['id']}, 'Ruta borrada');
            },
          ),
        ]),
      ),
    );
  }

  Widget _tarjetaRuta(Map<String, dynamic> r) {
    final fijado = r['precio_fijado'] as int?;
    final alias = ((r['rutas_alias'] as List?) ?? []).length;
    final tieneGps = r['dest_lat'] != null;
    return InkWell(
      onTap: () => _acciones(r),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _tarjeta,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: fijado != null ? Colors.amber.withValues(alpha: 0.5) : Colors.white10),
        ),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(
                  child: Text('${r['destino']}',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                ),
                if (tieneGps) ...[
                  const SizedBox(width: 4),
                  const Icon(Icons.location_on, size: 13, color: Color(0xFF3AF500)),
                ],
              ]),
              const SizedBox(height: 3),
              Text(
                '${_nombreLocal(r)} · ${(r['tipo_servicio'] ?? '').toString().isEmpty ? 'SIN TIPO' : r['tipo_servicio']}'
                '${alias > 0 ? ' · $alias nombre${alias == 1 ? '' : 's'} más' : ''}',
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
              const SizedBox(height: 3),
              Text(
                '${r['n']} servicio${r['n'] == 1 ? '' : 's'} · rango ${_pesos(r['precio_min'])}–${_pesos(r['precio_max'])}'
                ' · último ${_pesos(r['ultimo_precio'])}',
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ]),
          ),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(_pesos(fijado ?? r['precio_sugerido']),
                style: TextStyle(
                    color: fijado != null ? Colors.amber : const Color(0xFF3AF500),
                    fontWeight: FontWeight.bold,
                    fontSize: 15)),
            Text(fijado != null ? 'FIJADO' : 'SUGERIDO',
                style: const TextStyle(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.bold)),
          ]),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final locales = <int, String>{};
    for (final r in _rutas) {
      locales[r['local_id'] as int] = _nombreLocal(r);
    }
    final lista = _filtradas;
    return Scaffold(
      backgroundColor: _fondo,
      appBar: AppBar(
        backgroundColor: _tarjeta,
        foregroundColor: Colors.white,
        title: const Text('Rutas y precios aprendidos', style: TextStyle(fontSize: 16)),
        actions: [IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _cargar)],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Row(children: [
            Expanded(
              child: TextField(
                onChanged: (v) => setState(() => _busqueda = v),
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Buscar destino o local',
                  hintStyle: const TextStyle(color: Colors.white38),
                  prefixIcon: const Icon(Icons.search, color: Colors.white38),
                  filled: true,
                  fillColor: _tarjeta,
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                ),
              ),
            ),
            const SizedBox(width: 8),
            DropdownButton<int?>(
              value: _localFiltro,
              dropdownColor: _tarjeta,
              underline: const SizedBox.shrink(),
              hint: const Text('Todos', style: TextStyle(color: Colors.white54)),
              items: [
                const DropdownMenuItem<int?>(value: null, child: Text('Todos', style: TextStyle(color: Colors.white))),
                ...locales.entries.map((e) => DropdownMenuItem<int?>(
                    value: e.key, child: Text(e.value, style: const TextStyle(color: Colors.white)))),
              ],
              onChanged: (v) => setState(() => _localFiltro = v),
            ),
          ]),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          child: Text(
            'Se alimenta solo con cada servicio finalizado de los locales. Toca una ruta para fijar precio, unirla o pasarla a la lista del local.',
            style: TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ),
        Expanded(
          child: _cargando
              ? const Center(child: CircularProgressIndicator())
              : lista.isEmpty
                  ? const Center(child: Text('Aún no hay rutas aprendidas.', style: TextStyle(color: Colors.white38)))
                  : RefreshIndicator(
                      onRefresh: _cargar,
                      child: ListView(
                        padding: const EdgeInsets.all(12),
                        children: lista.map(_tarjetaRuta).toList(),
                      ),
                    ),
        ),
      ]),
    );
  }
}
