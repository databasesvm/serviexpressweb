// lib/screens/sectores_tarifa_screen.dart
//
// SECTORES Y TARIFA POR KM (Central)
// Regla de precio (la calcula el servidor, fn_tarifa_por_km):
//   • Mínima = la del sector de ORIGEN (o una excepción origen→destino).
//     Sin sector o sin mínima propia → mínima general.
//   • Sale y llega dentro del mismo sector (o es excepción): solo la mínima.
//   • Si sale del sector: +1 km apenas sale, y +1 km cada vez que la distancia
//     TOTAL pasa al siguiente mil (borde a 2.300 m → 2.400–2.999 = +1;
//     3.000–3.999 = +2; …).
//   • Origen sin sector dibujado: hasta 1.000 m = 0; 1.001–1.999 = +1 km;
//     2.000–2.999 = +2 km; …
// Aquí la central:
//   1) dibuja el contorno de cada sector y le pone su mínima,
//   2) ve/ajusta a qué sector pertenece cada local,
//   3) edita la mínima general, el valor por km, el factor de distancia y
//      las excepciones entre sectores.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _fondo = Color(0xFF111111);
const _tarjeta = Color(0xFF1A1A1A);
const _verde = Color(0xFF3AF500);
const LatLng _centroDefecto = LatLng(7.8634, -72.4757);

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

List<LatLng> _contornoDe(dynamic json) {
  if (json is! List) return [];
  return json
      .whereType<List>()
      .where((p) => p.length >= 2)
      .map((p) => LatLng((p[0] as num).toDouble(), (p[1] as num).toDouble()))
      .toList();
}

/// Mismo cálculo que el servidor (ray casting) para mostrar en vivo.
bool _puntoDentro(LatLng p, List<LatLng> poli) {
  if (poli.length < 3) return false;
  bool dentro = false;
  for (int i = 0, j = poli.length - 1; i < poli.length; j = i++) {
    final yi = poli[i].latitude, xi = poli[i].longitude;
    final yj = poli[j].latitude, xj = poli[j].longitude;
    if (((yi > p.latitude) != (yj > p.latitude)) &&
        (p.longitude < (xj - xi) * (p.latitude - yi) / ((yj - yi) == 0 ? 1e-12 : (yj - yi)) + xi)) {
      dentro = !dentro;
    }
  }
  return dentro;
}

// ═════════════════════════════════════════════════════════════════════════════
class SectoresTarifaScreen extends StatefulWidget {
  const SectoresTarifaScreen({super.key});
  @override
  State<SectoresTarifaScreen> createState() => _SectoresTarifaScreenState();
}

class _SectoresTarifaScreenState extends State<SectoresTarifaScreen> {
  final _db = Supabase.instance.client;
  bool _cargando = true;
  List<Map<String, dynamic>> _sectores = [];
  List<Map<String, dynamic>> _locales = [];
  List<Map<String, dynamic>> _excepciones = [];
  Map<String, dynamic> _config = {};
  String _busqueda = '';
  bool _soloDibujados = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  void _aviso(String t, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(t),
      backgroundColor: error ? Colors.red : const Color(0xFF2E7D32),
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final r = await Future.wait([
        _db
            .from('sectores')
            .select('id, nombre, municipio, activo, contorno, minima_primer_km')
            .eq('activo', true)
            .order('nombre'),
        _db
            .from('usuarios')
            .select('id, nombre, lat_fija, lng_fija, sector_tarifa_id, sector_tarifa_manual, cotizacion_auto_modo')
            .eq('rol', 'local')
            .order('nombre'),
        _db
            .from('tarifa_excepciones')
            .select('id, sector_origen_id, sector_destino_id, minima, activo')
            .order('id'),
        _db
            .from('config_sistema')
            .select('tarifa_minima_general, tarifa_valor_km, tarifa_factor_distancia, cotizacion_auto')
            .eq('id', 1)
            .maybeSingle(),
      ]);
      if (!mounted) return;
      setState(() {
        _sectores = List<Map<String, dynamic>>.from(r[0] as List);
        _locales = List<Map<String, dynamic>>.from(r[1] as List);
        _excepciones = List<Map<String, dynamic>>.from(r[2] as List);
        _config = Map<String, dynamic>.from((r[3] as Map?) ?? {});
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _cargando = false);
      _aviso('Error al cargar: $e', error: true);
    }
  }

  int get _minimaGeneral => (_config['tarifa_minima_general'] as num?)?.toInt() ?? 6000;

  String _nombreSector(dynamic id) {
    if (id == null) return 'Sin sector';
    final s = _sectores.firstWhere((x) => x['id'] == id, orElse: () => {});
    return s.isEmpty ? 'Sector $id' : s['nombre'].toString();
  }

  // ── Nuevo sector ──────────────────────────────────────────────────────────
  Future<void> _nuevoSector() async {
    final nomCtrl = TextEditingController();
    String municipio = 'V. Rosario';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          backgroundColor: _tarjeta,
          title: const Text('Nuevo sector', style: TextStyle(color: Colors.white)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: nomCtrl,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                  labelText: 'Nombre (ej: Trapiches parte alta)',
                  labelStyle: TextStyle(color: Colors.white54)),
            ),
            const SizedBox(height: 10),
            DropdownButton<String>(
              value: municipio,
              isExpanded: true,
              dropdownColor: _tarjeta,
              items: const ['V. Rosario', 'Cúcuta', 'Los Patios']
                  .map((m) => DropdownMenuItem(value: m, child: Text(m, style: TextStyle(color: Colors.white))))
                  .toList(),
              onChanged: (v) => setD(() => municipio = v ?? municipio),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCELAR')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('CREAR')),
          ],
        ),
      ),
    );
    if (ok != true || nomCtrl.text.trim().isEmpty) return;
    try {
      final nuevo = await _db
          .from('sectores')
          .insert({'nombre': nomCtrl.text.trim(), 'municipio': municipio, 'activo': true})
          .select('id, nombre, municipio, activo, contorno, minima_primer_km')
          .single();
      await _cargar();
      if (mounted) _abrirEditor(Map<String, dynamic>.from(nuevo));
    } catch (e) {
      _aviso('Error al crear: $e', error: true);
    }
  }

  Future<void> _abrirEditor(Map<String, dynamic> sector) async {
    final guardado = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => _EditorSectorScreen(
          sector: sector,
          otrosSectores: _sectores.where((s) => s['id'] != sector['id']).toList(),
          locales: _locales,
          minimaGeneral: _minimaGeneral,
        ),
      ),
    );
    if (guardado == true) {
      _aviso('Sector guardado. Los locales se reasignaron solos.');
      await _cargar();
    }
  }

  // ── TAB 1: sectores ───────────────────────────────────────────────────────
  Widget _tabSectores() {
    final q = _busqueda.trim().toLowerCase();
    final lista = _sectores.where((s) {
      if (_soloDibujados && s['contorno'] == null) return false;
      return q.isEmpty || s['nombre'].toString().toLowerCase().contains(q);
    }).toList()
      ..sort((a, b) {
        final da = a['contorno'] != null ? 0 : 1, dbb = b['contorno'] != null ? 0 : 1;
        if (da != dbb) return da - dbb;
        return a['nombre'].toString().compareTo(b['nombre'].toString());
      });
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: Row(children: [
          Expanded(
            child: TextField(
              onChanged: (v) => setState(() => _busqueda = v),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Buscar sector',
                hintStyle: const TextStyle(color: Colors.white38),
                prefixIcon: const Icon(Icons.search, color: Colors.white38),
                isDense: true,
                filled: true,
                fillColor: _tarjeta,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              ),
            ),
          ),
          const SizedBox(width: 8),
          FilterChip(
            label: const Text('Dibujados'),
            selected: _soloDibujados,
            onSelected: (v) => setState(() => _soloDibujados = v),
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        child: Text(
          'Solo los sectores DIBUJADOS cuentan para la tarifa. Sin dibujar o sin mínima propia → mínima general ${_pesos(_minimaGeneral)}.',
          style: const TextStyle(color: Colors.white38, fontSize: 11),
        ),
      ),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 80),
          children: lista.map((s) {
            final dibujado = s['contorno'] != null;
            final minima = s['minima_primer_km'] as int?;
            final nLocales = _locales.where((l) => l['sector_tarifa_id'] == s['id']).length;
            return Card(
              color: _tarjeta,
              child: ListTile(
                onTap: () => _abrirEditor(s),
                leading: Icon(dibujado ? Icons.pentagon_rounded : Icons.pentagon_outlined,
                    color: dibujado ? _verde : Colors.white24),
                title: Text(s['nombre'].toString(), style: const TextStyle(color: Colors.white)),
                subtitle: Text(
                  '${s['municipio'] ?? ''} · ${dibujado ? 'dibujado' : 'sin dibujar'}'
                  '${nLocales > 0 ? ' · $nLocales local${nLocales == 1 ? '' : 'es'}' : ''}',
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
                trailing: Text(
                  minima != null ? _pesos(minima) : 'General',
                  style: TextStyle(
                      color: minima != null ? Colors.amber : Colors.white38, fontWeight: FontWeight.bold),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    ]);
  }

  // ── TAB 2: locales ────────────────────────────────────────────────────────
  Future<void> _cambiarSectorLocal(Map<String, dynamic> l) async {
    final dibujados = _sectores.where((s) => s['contorno'] != null || s['minima_primer_km'] != null).toList();
    final elegido = await showDialog<Object>(
      context: context,
      builder: (ctx) => SimpleDialog(
        backgroundColor: _tarjeta,
        title: Text('Sector de ${l['nombre']}', style: const TextStyle(color: Colors.white, fontSize: 15)),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'auto'),
            child: const Text('🔄 Automático (según su ubicación)', style: TextStyle(color: _verde)),
          ),
          ...dibujados.map((s) => SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, s['id']),
                child: Text(
                    '${s['nombre']}  ·  ${s['minima_primer_km'] != null ? _pesos(s['minima_primer_km']) : 'general'}',
                    style: const TextStyle(color: Colors.white70)),
              )),
        ],
      ),
    );
    if (elegido == null) return;
    try {
      await _db.rpc('fn_asignar_sector_local', params: {
        'p_local': l['id'],
        'p_sector': elegido == 'auto' ? null : elegido,
      });
      _aviso('Sector actualizado');
      await _cargar();
    } catch (e) {
      _aviso('Error: $e', error: true);
    }
  }

  Widget _tabLocales() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text(
            'El sector del local define la mínima de los servicios que salen de él. '
            'Automático = según la ubicación fija del local dentro de un sector dibujado.',
            style: TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ),
        ..._locales.map((l) {
          final sid = l['sector_tarifa_id'];
          final manual = l['sector_tarifa_manual'] == true;
          final s = _sectores.firstWhere((x) => x['id'] == sid, orElse: () => {});
          final minima = (s['minima_primer_km'] as int?) ?? _minimaGeneral;
          return Card(
            color: _tarjeta,
            child: ListTile(
              onTap: () => _cambiarSectorLocal(l),
              leading: const Icon(Icons.storefront_rounded, color: Colors.white54),
              title: Text(l['nombre'].toString(), style: const TextStyle(color: Colors.white)),
              subtitle: Text(
                '${_nombreSector(sid)} · ${manual ? 'asignado a mano' : 'automático'}'
                '${l['lat_fija'] == null ? ' · sin ubicación fija' : ''}',
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('Mín. ${_pesos(minima)}',
                      style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
                  InkWell(
                    onTap: () => _cambiarAutoLocal(l),
                    child: Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        switch (l['cotizacion_auto_modo']) {
                          'si' => '🤖 Auto: SÍ',
                          'no' => 'Auto: NO',
                          _ => 'Auto: general',
                        },
                        style: TextStyle(
                            color: l['cotizacion_auto_modo'] == 'si' ? _verde : Colors.white54,
                            fontSize: 11,
                            decoration: TextDecoration.underline),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  // ── TAB 3: general + excepciones ──────────────────────────────────────────
  Future<void> _editarConfig() async {
    final minCtrl = TextEditingController(text: '${_config['tarifa_minima_general'] ?? 6000}');
    final kmCtrl = TextEditingController(text: '${_config['tarifa_valor_km'] ?? 1000}');
    final facCtrl = TextEditingController(text: '${_config['tarifa_factor_distancia'] ?? 1.3}');
    InputDecoration deco(String l, {String? h}) => InputDecoration(
        labelText: l, helperText: h, helperMaxLines: 2,
        labelStyle: const TextStyle(color: Colors.white54),
        helperStyle: const TextStyle(color: Colors.white38));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _tarjeta,
        title: const Text('Tarifa general', style: TextStyle(color: Colors.white)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: minCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(color: Colors.white),
              decoration: deco('Mínima general (primer km)', h: 'Se usa fuera de sectores o si el sector no tiene mínima')),
          TextField(
              controller: kmCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(color: Colors.white),
              decoration: deco('Valor por km adicional')),
          TextField(
              controller: facCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: Colors.white),
              decoration: deco('Factor de distancia',
                  h: 'Línea recta × factor ≈ recorrido por calles (1,3 recomendado)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCELAR')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('GUARDAR')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _db.rpc('fn_guardar_config_tarifa', params: {
        'p_minima': int.parse(minCtrl.text),
        'p_valor_km': int.parse(kmCtrl.text),
        'p_factor': double.parse(facCtrl.text.replaceAll(',', '.')),
      });
      _aviso('Tarifa general guardada');
      await _cargar();
    } catch (e) {
      _aviso('Error: $e', error: true);
    }
  }

  Future<void> _nuevaExcepcion() async {
    final candidatos = _sectores.where((s) => s['contorno'] != null).toList();
    if (candidatos.length < 2) {
      _aviso('Primero dibuja al menos dos sectores.', error: true);
      return;
    }
    int? origen, destino;
    final minCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          DropdownButton<int> selector(int? valor, ValueChanged<int?> cambio, String hint) => DropdownButton<int>(
                value: valor,
                isExpanded: true,
                dropdownColor: _tarjeta,
                hint: Text(hint, style: const TextStyle(color: Colors.white54)),
                items: candidatos
                    .map((s) => DropdownMenuItem<int>(
                        value: s['id'] as int,
                        child: Text(s['nombre'].toString(), style: const TextStyle(color: Colors.white))))
                    .toList(),
                onChanged: (v) => setD(() => cambio(v)),
              );
          return AlertDialog(
            backgroundColor: _tarjeta,
            title: const Text('Nueva excepción', style: TextStyle(color: Colors.white)),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              selector(origen, (v) => origen = v, 'Sale de…'),
              selector(destino, (v) => destino = v, 'Llega a…'),
              TextField(
                controller: minCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                    labelText: 'Mínima del primer km', labelStyle: TextStyle(color: Colors.white54)),
              ),
            ]),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCELAR')),
              ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('GUARDAR')),
            ],
          );
        },
      ),
    );
    final minima = int.tryParse(minCtrl.text);
    if (ok != true || origen == null || destino == null || minima == null) return;
    try {
      await _db.from('tarifa_excepciones').upsert(
        {'sector_origen_id': origen, 'sector_destino_id': destino, 'minima': minima, 'activo': true},
        onConflict: 'sector_origen_id,sector_destino_id',
      );
      _aviso('Excepción guardada');
      await _cargar();
    } catch (e) {
      _aviso('Error: $e', error: true);
    }
  }

  Future<void> _cambiarAutoGeneral(bool v) async {
    try {
      await _db.rpc('fn_guardar_cotizacion_auto', params: {'p_general': v});
      _aviso(v ? 'Cotización automática ENCENDIDA' : 'Cotización automática apagada');
      await _cargar();
    } catch (e) {
      _aviso('Error: $e', error: true);
    }
  }

  Future<void> _cambiarAutoLocal(Map<String, dynamic> l) async {
    final modo = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        backgroundColor: _tarjeta,
        title: Text('Cotización automática — ${l['nombre']}',
            style: const TextStyle(color: Colors.white, fontSize: 15)),
        children: [
          for (final op in const [
            ['heredar', 'Igual que el general'],
            ['si', 'Siempre automático (para probar)'],
            ['no', 'Nunca automático'],
          ])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, op[0]),
              child: Text(op[1], style: const TextStyle(color: Colors.white70)),
            ),
        ],
      ),
    );
    if (modo == null) return;
    try {
      await _db.rpc('fn_guardar_cotizacion_auto_local', params: {'p_local': l['id'], 'p_modo': modo});
      _aviso('Guardado');
      await _cargar();
    } catch (e) {
      _aviso('Error: $e', error: true);
    }
  }

  Widget _tabGeneral() {
    final bool auto = _config['cotizacion_auto'] == true;
    return ListView(padding: const EdgeInsets.all(12), children: [
      Card(
        color: _tarjeta,
        child: SwitchListTile(
          value: auto,
          activeColor: _verde,
          onChanged: _cambiarAutoGeneral,
          title: const Text('Cotización automática (general)', style: TextStyle(color: Colors.white)),
          subtitle: Text(
            auto
                ? 'ENCENDIDA: si la ruta es confiable (3 confirmaciones sin cambios), el local ve el precio y pide directo.'
                : 'APAGADA: todo pasa por la central, con el precio calculado ya escrito para confirmar o editar.',
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),
        ),
      ),
      const SizedBox(height: 8),
      Card(
        color: _tarjeta,
        child: ListTile(
          onTap: _editarConfig,
          leading: const Icon(Icons.tune_rounded, color: Colors.amber),
          title: const Text('Tarifa general', style: TextStyle(color: Colors.white)),
          subtitle: Text(
            'Mínima ${_pesos(_minimaGeneral)} · +${_pesos(_config['tarifa_valor_km'] as num? ?? 1000)} por km · '
            'factor ${_config['tarifa_factor_distancia'] ?? 1.3}',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          trailing: const Icon(Icons.edit, color: Colors.white38),
        ),
      ),
      const Padding(
        padding: EdgeInsets.fromLTRB(4, 12, 4, 4),
        child: Text(
          'Cómo se cobra: dentro del mismo sector, solo la mínima (sin importar la distancia). '
          'Apenas sale del sector suma 1 km, y otro km cada vez que la distancia total pasa al '
          'siguiente mil (ej: borde a 2.300 m → 2.400–2.999 = +1; 3.000–3.999 = +2…). '
          'Si el origen no está en un sector dibujado: hasta 1.000 m solo la mínima; '
          '1.001–1.999 = +1 km; 2.000–2.999 = +2 km…',
          style: TextStyle(color: Colors.white38, fontSize: 11),
        ),
      ),
      const SizedBox(height: 12),
      Row(children: [
        const Expanded(
          child: Text('EXCEPCIONES ENTRE SECTORES',
              style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1)),
        ),
        TextButton.icon(
            onPressed: _nuevaExcepcion, icon: const Icon(Icons.add, size: 16), label: const Text('AGREGAR')),
      ]),
      const Text('Ej: sale de Trapiches baja y llega a Trapiches alta → mínima \$5.000.',
          style: TextStyle(color: Colors.white38, fontSize: 11)),
      const SizedBox(height: 6),
      if (_excepciones.isEmpty)
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text('Sin excepciones.', style: TextStyle(color: Colors.white38)),
        ),
      ..._excepciones.map((e) => Card(
            color: _tarjeta,
            child: ListTile(
              title: Text('${_nombreSector(e['sector_origen_id'])} → ${_nombreSector(e['sector_destino_id'])}',
                  style: const TextStyle(color: Colors.white, fontSize: 13)),
              subtitle: Text('Mínima ${_pesos(e['minima'] as num?)}',
                  style: const TextStyle(color: Colors.amber, fontSize: 12)),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                onPressed: () async {
                  try {
                    await _db.from('tarifa_excepciones').delete().eq('id', e['id']);
                    await _cargar();
                  } catch (err) {
                    _aviso('Error: $err', error: true);
                  }
                },
              ),
            ),
          )),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: _fondo,
        appBar: AppBar(
          backgroundColor: _tarjeta,
          foregroundColor: Colors.white,
          title: const Text('Sectores y tarifa por km', style: TextStyle(fontSize: 16)),
          actions: [IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _cargar)],
          bottom: const TabBar(
            indicatorColor: _verde,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white38,
            tabs: [Tab(text: 'SECTORES'), Tab(text: 'LOCALES'), Tab(text: 'GENERAL')],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: _verde,
          foregroundColor: Colors.black,
          onPressed: _nuevoSector,
          icon: const Icon(Icons.add),
          label: const Text('NUEVO SECTOR', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        body: _cargando
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(children: [_tabSectores(), _tabLocales(), _tabGeneral()]),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// EDITOR DE CONTORNO
//   • Tocar el mapa: agrega un punto (después del punto seleccionado).
//   • Tocar un punto: lo selecciona. Con un punto seleccionado y "MOVER"
//     activo, el siguiente toque en el mapa lo lleva ahí.
//   • Borrar punto / deshacer / borrar todo.
//   • Los locales se ven en verde si quedan dentro y en gris si quedan fuera.
class _EditorSectorScreen extends StatefulWidget {
  final Map<String, dynamic> sector;
  final List<Map<String, dynamic>> otrosSectores;
  final List<Map<String, dynamic>> locales;
  final int minimaGeneral;
  const _EditorSectorScreen({
    required this.sector,
    required this.otrosSectores,
    required this.locales,
    required this.minimaGeneral,
  });
  @override
  State<_EditorSectorScreen> createState() => _EditorSectorScreenState();
}

class _EditorSectorScreenState extends State<_EditorSectorScreen> {
  late List<LatLng> _puntos;
  final List<List<LatLng>> _historial = [];
  int? _sel;
  bool _mover = false;
  bool _guardando = false;
  late final TextEditingController _minCtrl;

  @override
  void initState() {
    super.initState();
    _puntos = _contornoDe(widget.sector['contorno']);
    _minCtrl = TextEditingController(text: widget.sector['minima_primer_km']?.toString() ?? '');
  }

  @override
  void dispose() {
    _minCtrl.dispose();
    super.dispose();
  }

  LatLng get _centroInicial {
    if (_puntos.isNotEmpty) {
      final lat = _puntos.map((p) => p.latitude).reduce((a, b) => a + b) / _puntos.length;
      final lng = _puntos.map((p) => p.longitude).reduce((a, b) => a + b) / _puntos.length;
      return LatLng(lat, lng);
    }
    final conUbic = widget.locales.where((l) => l['lat_fija'] != null).toList();
    if (conUbic.isNotEmpty) {
      return LatLng((conUbic.first['lat_fija'] as num).toDouble(), (conUbic.first['lng_fija'] as num).toDouble());
    }
    return _centroDefecto;
  }

  void _guardarHistorial() {
    _historial.add(List<LatLng>.from(_puntos));
    if (_historial.length > 50) _historial.removeAt(0);
  }

  void _tocarMapa(LatLng p) {
    setState(() {
      _guardarHistorial();
      if (_mover && _sel != null) {
        _puntos[_sel!] = p;
        _mover = false;
      } else {
        final idx = _sel != null ? _sel! + 1 : _puntos.length;
        _puntos.insert(idx, p);
        _sel = idx;
      }
    });
  }

  Future<void> _guardar() async {
    final txt = _minCtrl.text.trim();
    final int? minima = txt.isEmpty ? null : int.tryParse(txt);
    if (txt.isNotEmpty && (minima == null || minima < 1000)) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Mínima inválida (vacío = general)')));
      return;
    }
    if (_puntos.isNotEmpty && _puntos.length < 3) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('El contorno necesita al menos 3 puntos')));
      return;
    }
    setState(() => _guardando = true);
    try {
      await Supabase.instance.client.rpc('fn_guardar_sector_tarifa', params: {
        'p_sector': widget.sector['id'],
        'p_contorno': _puntos.map((p) => [p.latitude, p.longitude]).toList(),
        'p_minima': minima,
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _guardando = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    final localesConUbic = widget.locales.where((l) => l['lat_fija'] != null).toList();
    final dentro = localesConUbic
        .where((l) => _puntoDentro(
            LatLng((l['lat_fija'] as num).toDouble(), (l['lng_fija'] as num).toDouble()), _puntos))
        .toList();

    return Scaffold(
      backgroundColor: _fondo,
      appBar: AppBar(
        backgroundColor: _tarjeta,
        foregroundColor: Colors.white,
        title: Text(widget.sector['nombre'].toString(), style: const TextStyle(fontSize: 15)),
        actions: [
          TextButton(
            onPressed: _guardando ? null : _guardar,
            child: _guardando
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('GUARDAR', style: TextStyle(color: _verde, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: Column(children: [
        // Mínima
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: TextField(
            controller: _minCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Mínima del primer km',
              helperText: 'Vacío = general (${_pesos(widget.minimaGeneral)})',
              labelStyle: const TextStyle(color: Colors.white54),
              helperStyle: const TextStyle(color: Colors.white38),
              prefixText: '\$ ',
              isDense: true,
              filled: true,
              fillColor: _tarjeta,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
            ),
          ),
        ),
        // Mapa
        Expanded(
          child: FlutterMap(
            options: MapOptions(
              initialCenter: _centroInicial,
              initialZoom: 15.5,
              onTap: (_, p) => _tocarMapa(p),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.serviexpress.express',
              ),
              // Otros sectores dibujados (tenues, de referencia)
              PolygonLayer(polygons: [
                for (final s in widget.otrosSectores)
                  if (_contornoDe(s['contorno']).length >= 3)
                    Polygon(
                      points: _contornoDe(s['contorno']),
                      color: Colors.blueGrey.withValues(alpha: 0.12),
                      borderColor: Colors.blueGrey,
                      borderStrokeWidth: 1,
                      label: s['nombre'].toString(),
                    ),
                if (_puntos.length >= 3)
                  Polygon(
                    points: _puntos,
                    color: _verde.withValues(alpha: 0.18),
                    borderColor: _verde,
                    borderStrokeWidth: 3,
                  ),
              ]),
              if (_puntos.length == 2)
                PolylineLayer(polylines: [Polyline(points: _puntos, color: _verde, strokeWidth: 3)]),
              // Locales
              MarkerLayer(markers: [
                for (final l in localesConUbic)
                  Marker(
                    point: LatLng((l['lat_fija'] as num).toDouble(), (l['lng_fija'] as num).toDouble()),
                    width: 120,
                    height: 44,
                    child: Column(children: [
                      Icon(Icons.storefront_rounded,
                          size: 22, color: dentro.contains(l) ? _verde : Colors.grey),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        color: Colors.black54,
                        child: Text(l['nombre'].toString(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontSize: 9)),
                      ),
                    ]),
                  ),
              ]),
              // Puntos del contorno
              MarkerLayer(markers: [
                for (int i = 0; i < _puntos.length; i++)
                  Marker(
                    point: _puntos[i],
                    width: 26,
                    height: 26,
                    child: GestureDetector(
                      onTap: () => setState(() {
                        _sel = _sel == i ? null : i;
                        _mover = false;
                      }),
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _sel == i ? Colors.amber : Colors.white,
                          border: Border.all(color: _verde, width: 3),
                        ),
                        alignment: Alignment.center,
                        child: Text('${i + 1}',
                            style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.black)),
                      ),
                    ),
                  ),
              ]),
            ],
          ),
        ),
        // Barra de herramientas
        Container(
          color: _tarjeta,
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(
              _mover
                  ? 'Toca el mapa donde quieres llevar el punto ${(_sel ?? 0) + 1}'
                  : _sel != null
                      ? 'Punto ${_sel! + 1} seleccionado: el próximo toque agrega un punto después de él'
                      : 'Toca el mapa para agregar puntos del borde. Toca un punto para seleccionarlo.',
              style: const TextStyle(color: Colors.white54, fontSize: 11),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              '${_puntos.length} puntos · Locales dentro: '
              '${dentro.isEmpty ? 'ninguno' : dentro.map((l) => l['nombre']).join(', ')}',
              style: const TextStyle(color: _verde, fontSize: 11),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Wrap(spacing: 6, alignment: WrapAlignment.center, children: [
              OutlinedButton.icon(
                onPressed: _sel == null ? null : () => setState(() => _mover = !_mover),
                icon: const Icon(Icons.open_with, size: 16),
                label: Text(_mover ? 'CANCELAR MOVER' : 'MOVER'),
              ),
              OutlinedButton.icon(
                onPressed: _sel == null
                    ? null
                    : () => setState(() {
                          _guardarHistorial();
                          _puntos.removeAt(_sel!);
                          _sel = _puntos.isEmpty ? null : (_sel! - 1).clamp(0, _puntos.length - 1).toInt();
                          _mover = false;
                        }),
                icon: const Icon(Icons.remove_circle_outline, size: 16),
                label: const Text('BORRAR PUNTO'),
              ),
              OutlinedButton.icon(
                onPressed: _historial.isEmpty
                    ? null
                    : () => setState(() {
                          _puntos = _historial.removeLast();
                          _sel = null;
                          _mover = false;
                        }),
                icon: const Icon(Icons.undo, size: 16),
                label: const Text('DESHACER'),
              ),
              OutlinedButton.icon(
                onPressed: _puntos.isEmpty
                    ? null
                    : () => setState(() {
                          _guardarHistorial();
                          _puntos = [];
                          _sel = null;
                          _mover = false;
                        }),
                icon: const Icon(Icons.layers_clear, size: 16, color: Colors.redAccent),
                label: const Text('BORRAR TODO', style: TextStyle(color: Colors.redAccent)),
              ),
            ]),
          ]),
        ),
      ]),
    );
  }
}
