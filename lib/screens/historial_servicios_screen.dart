import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Pantalla de historial de servicios — accesible desde el menú de Gestión.
class HistorialServiciosScreen extends StatefulWidget {
  const HistorialServiciosScreen({super.key});
  @override
  State<HistorialServiciosScreen> createState() => _HistorialServiciosScreenState();
}

class _HistorialServiciosScreenState extends State<HistorialServiciosScreen> {
  _RangoFecha _rangoSeleccionado = _RangoFecha.hoy;
  String? _estadoFiltro;
  String _busqueda = '';
  List<Map<String, dynamic>> _servicios = [];
  List<Map<String, dynamic>> _movilesCache = [];
  bool _cargando = true;
  String? _error;
  final TextEditingController _busquedaCtrl = TextEditingController();
  final _fmt = NumberFormat('#,###', 'es_CO');
  final _fmtHora = DateFormat('dd/MM HH:mm');

  @override
  void initState() {
    super.initState();
    _cargarMoviles();
    _cargarHistorial();
  }

  @override
  void dispose() {
    _busquedaCtrl.dispose();
    super.dispose();
  }

  DateTimeRange _obtenerRango() {
    final ahora = DateTime.now();
    final hoy = DateTime(ahora.year, ahora.month, ahora.day);
    switch (_rangoSeleccionado) {
      case _RangoFecha.hoy:
        return DateTimeRange(start: hoy, end: ahora);
      case _RangoFecha.ayer:
        final ayer = hoy.subtract(const Duration(days: 1));
        return DateTimeRange(start: ayer, end: hoy);
      case _RangoFecha.semana:
        return DateTimeRange(start: hoy.subtract(const Duration(days: 7)), end: ahora);
      case _RangoFecha.mes:
        return DateTimeRange(start: DateTime(ahora.year, ahora.month, 1), end: ahora);
    }
  }

  Future<void> _cargarMoviles() async {
    final data = await Supabase.instance.client
        .from('usuarios')
        .select('id, usuario, nombre, rol')
        .eq('rol', 'movil');
    if (mounted) setState(() => _movilesCache = List.from(data));
  }

  Future<void> _cargarHistorial() async {
    if (!mounted) return;
    setState(() { _cargando = true; _error = null; });
    try {
      final rango = _obtenerRango();
      final base = Supabase.instance.client
          .from('servicios')
          .select()
          .gte('created_at', rango.start.toUtc().toIso8601String())
          .lte('created_at', rango.end.toUtc().toIso8601String());
      final data = await (_estadoFiltro != null
          ? base.eq('estado', _estadoFiltro!).order('id', ascending: false)
          : base.order('id', ascending: false));
      if (mounted) setState(() { _servicios = List<Map<String, dynamic>>.from(data); _cargando = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _cargando = false; });
    }
  }

  String _nombreMovil(dynamic movilId) {
    if (movilId == null) return '—';
    final m = _movilesCache.firstWhere((m) => m['id'] == movilId, orElse: () => {});
    if (m.isEmpty) return '#$movilId';
    final usr = m['usuario']?.toString() ?? '';
    final num = usr.replaceAll(RegExp(r'[^0-9]'), '');
    return num.isNotEmpty ? 'Móvil $num' : (m['nombre']?.toString() ?? '#$movilId');
  }

  String _fmtPeso(dynamic v) {
    if (v == null || v == 0) return '—';
    return '\$${_fmt.format((v as num).toInt())}';
  }

  Color _colorEstado(String estado) {
    switch (estado) {
      case 'finalizado': return Colors.green[700]!;
      case 'finalizado_con_problema': return Colors.orange[700]!;
      case 'finalizado_por_demora': return Colors.orange[900]!;
      case 'cancelado': return Colors.red[600]!;
      case 'caducado': return Colors.grey[600]!;
      case 'problema': return Colors.red[800]!;
      case 'pendiente': return Colors.blue[600]!;
      case 'cotizacion': return Colors.orange[600]!;
      case 'en_ruta_origen':
      case 'en_origen':
      case 'en_ruta_destino': return Colors.blue[800]!;
      default: return Colors.blueGrey[600]!;
    }
  }

  String _labelEstado(String estado) {
    const map = {
      'pendiente': 'LIBRE', 'cotizacion': 'COTIZ.', 'cotizada': 'ENVIADA',
      'cotizacion_aprobada': 'APROB.', 'programado': 'PROGR.',
      'en_ruta_origen': 'RECOG.', 'en_origen': 'EN LOCAL',
      'en_ruta_destino': 'ENTREGA', 'problema': 'PROBLEMA',
      'finalizado': 'ENTREGADO', 'finalizado_con_problema': 'FIN+PROB',
      'finalizado_por_demora': 'FIN+DEMORA', 'caducado': 'CADUCADO',
      'cancelado': 'CANCELADO',
    };
    return map[estado] ?? estado.toUpperCase();
  }

  List<Map<String, dynamic>> get _filtrados {
    if (_busqueda.isEmpty) return _servicios;
    final q = _busqueda.toLowerCase();
    return _servicios.where((s) {
      return (s['origen']?.toString().toLowerCase().contains(q) ?? false) ||
          (s['destino']?.toString().toLowerCase().contains(q) ?? false) ||
          (s['creador']?.toString().toLowerCase().contains(q) ?? false) ||
          (s['id']?.toString().contains(q) ?? false) ||
          _nombreMovil(s['movil_id']).toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Historial de Servicios',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(88),
          child: Container(
            color: Colors.black,
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Column(children: [
              Row(children: _RangoFecha.values.map((r) {
                final sel = r == _rangoSeleccionado;
                return Expanded(
                  child: GestureDetector(
                    onTap: () { setState(() => _rangoSeleccionado = r); _cargarHistorial(); },
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      decoration: BoxDecoration(
                        color: sel ? const Color(0xff3AF500) : Colors.white12,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(r.label,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: sel ? Colors.black : Colors.white70)),
                    ),
                  ),
                );
              }).toList()),
              SizedBox(
                height: 36,
                child: TextField(
                  controller: _busquedaCtrl,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  onChanged: (v) => setState(() => _busqueda = v.toLowerCase().trim()),
                  decoration: InputDecoration(
                    hintText: 'Buscar por ruta, móvil, local, #ID…',
                    hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                    prefixIcon: const Icon(Icons.search, color: Colors.white38, size: 18),
                    filled: true,
                    fillColor: Colors.white12,
                    contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  ),
                ),
              ),
            ]),
          ),
        ),
        actions: [
          PopupMenuButton<String?>(
            icon: Icon(Icons.filter_list,
                color: _estadoFiltro != null ? const Color(0xff3AF500) : Colors.white),
            tooltip: 'Filtrar por estado',
            onSelected: (v) { setState(() => _estadoFiltro = v); _cargarHistorial(); },
            itemBuilder: (_) => [
              const PopupMenuItem(value: null, child: Text('Todos los estados')),
              const PopupMenuItem(value: 'finalizado', child: Text('Entregados')),
              const PopupMenuItem(value: 'cancelado', child: Text('Cancelados')),
              const PopupMenuItem(value: 'caducado', child: Text('Caducados')),
              const PopupMenuItem(value: 'problema', child: Text('Problema')),
              const PopupMenuItem(value: 'finalizado_con_problema', child: Text('Fin + Prob')),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.download_rounded, color: Colors.white),
            tooltip: 'Exportar CSV',
            onPressed: _exportarCSV,
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            tooltip: 'Recargar',
            onPressed: _cargarHistorial,
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: Colors.black))
          : _error != null
              ? Center(child: Text('Error: $_error', style: const TextStyle(color: Colors.red)))
              : _buildLista(),
    );
  }

  Widget _buildLista() {
    final lista = _filtrados;
    if (lista.isEmpty) {
      return const Center(
        child: Text('Sin servicios en este período.',
            style: TextStyle(color: Colors.grey, fontSize: 14)),
      );
    }
    final finalizados = lista.where((s) => s['estado'].toString().startsWith('finalizado')).length;
    final cancelados = lista.where((s) => s['estado'] == 'cancelado').length;
    final facturacion = lista
        .where((s) => s['estado'].toString().startsWith('finalizado'))
        .fold<double>(0, (a, s) => a + ((s['tarifa'] as num?)?.toDouble() ?? 0));

    return Column(children: [
      Container(
        color: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(children: [
          _chipResumen('${lista.length} total', Colors.blueGrey[700]!),
          const SizedBox(width: 6),
          _chipResumen('$finalizados entregados', Colors.green[700]!),
          const SizedBox(width: 6),
          _chipResumen('$cancelados cancelados', Colors.red[600]!),
          const Spacer(),
          Text(_fmtPeso(facturacion),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87)),
        ]),
      ),
      const Divider(height: 1),
      Expanded(
        child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          itemCount: lista.length,
          itemBuilder: (ctx, i) => _cardServicio(lista[i]),
        ),
      ),
    ]);
  }

  Widget _cardServicio(Map<String, dynamic> s) {
    final estado = s['estado']?.toString() ?? '';
    final color = _colorEstado(estado);
    final fecha = s['created_at'] != null
        ? _fmtHora.format(DateTime.parse(s['created_at']).toLocal()) : '—';
    final tarifa = _fmtPeso(s['tarifa']);
    final movil = _nombreMovil(s['movil_id']);
    final esVip = s['es_vip'] == true;

    return GestureDetector(
      onTap: () => _mostrarDetalle(context, s),
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: BorderSide(color: color.withValues(alpha: 0.3)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(color: color.withValues(alpha: 0.5), width: 0.8),
                ),
                child: Text(_labelEstado(estado),
                    style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: color)),
              ),
              const SizedBox(width: 5),
              if (s['tipo_fn'] == true) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  margin: const EdgeInsets.only(right: 4),
                  decoration: BoxDecoration(
                    color: Colors.indigo.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(color: Colors.indigo.withValues(alpha: 0.5), width: 0.8),
                  ),
                  child: Text(
                    s['fn_consecutivo'] != null ? 'FN-${s["fn_consecutivo"]}' : 'FN',
                    style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.indigo),
                  ),
                ),
              ],
              if (esVip) const Text('👑 ', style: TextStyle(fontSize: 11)),
              Expanded(
                child: Text(
                  '${s["origen"] ?? "—"} ➔ ${s["destino"] ?? "—"}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text('#${s["id"]}', style: const TextStyle(fontSize: 10, color: Colors.black38)),
            ]),
            const SizedBox(height: 3),
            Row(children: [
              Text(tarifa,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black87)),
              if (movil != '—') ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.blueGrey[700],
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text('🍃 $movil',
                      style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                ),
              ],
              const Spacer(),
              Text(fecha, style: const TextStyle(fontSize: 9, color: Colors.black45)),
            ]),
            if (s['creador'] != null && s['creador'] != 'Central') ...[
              const SizedBox(height: 2),
              Text('🏢 ${s["creador"]}', style: const TextStyle(fontSize: 9, color: Colors.black45)),
            ],
            if (s['multi_ruta_id'] != null) ...[
              const SizedBox(height: 2),
              Text('🔗 Multi-ruta · Orden #${s["multi_ruta_orden"] ?? "?"}',
                  style: const TextStyle(fontSize: 9, color: Colors.indigo)),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _chipResumen(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Text(label,
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color)),
      );

  void _mostrarDetalle(BuildContext context, Map<String, dynamic> s) {
    final fmtFull = DateFormat('dd/MM/yyyy HH:mm', 'es_CO');
    String fmt(dynamic v) => v == null ? '—' : v.toString();
    String fmtFecha(dynamic v) {
      if (v == null) return '—';
      try { return fmtFull.format(DateTime.parse(v.toString()).toLocal()); }
      catch (_) { return v.toString(); }
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.65,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (_, ctrl) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(children: [
            Container(
              width: 36, height: 4,
              margin: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                Text('Servicio #${s["id"]}',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _colorEstado(s['estado']?.toString() ?? '').withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _labelEstado(s['estado']?.toString() ?? ''),
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: _colorEstado(s['estado']?.toString() ?? '')),
                  ),
                ),
              ]),
            ),
            const Divider(height: 16),
            Expanded(
              child: ListView(
                controller: ctrl,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _detalleRow('Origen', fmt(s['origen'])),
                  _detalleRow('Destino', fmt(s['destino'])),
                  _detalleRow('Tarifa', _fmtPeso(s['tarifa'])),
                  _detalleRow('Móvil', _nombreMovil(s['movil_id'])),
                  _detalleRow('Creado por', fmt(s['creador'])),
                  _detalleRow('Tipo', fmt(s['tipo_servicio'])),
                  _detalleRow('Fecha', fmtFecha(s['created_at'])),
                  if (s['es_vip'] == true) _detalleRow('VIP', '👑 Sí'),
                  if (s['notas'] != null) _detalleRow('Notas', fmt(s['notas'])),
                  if (s['multi_ruta_id'] != null)
                    _detalleRow('Multi-ruta', 'Orden #${s["multi_ruta_orden"] ?? "?"}'),
                  // ── Sección exclusiva FN ────────────────────────────
                  if (s['tipo_fn'] == true) ...[
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Divider(height: 1),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text('FARMANORTE',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.indigo[700],
                              letterSpacing: 0.8)),
                    ),
                    if (s['fn_consecutivo'] != null)
                      _detalleRow('Consecutivo', 'FN-${s["fn_consecutivo"]}'),
                    if (s['fn_factura_numero'] != null)
                      _detalleRow('N° Factura', fmt(s['fn_factura_numero'])),
                    if (s['fn_factura_valor'] != null && (s['fn_factura_valor'] as num) > 0)
                      _detalleRow('Valor factura', _fmtPeso(s['fn_factura_valor'])),
                    if (s['fn_pagar_producto'] != null && (s['fn_pagar_producto'] as num) > 0)
                      _detalleRow('Pagar producto', _fmtPeso(s['fn_pagar_producto'])),
                    if (s['recogidas'] is List && (s['recogidas'] as List).isNotEmpty)
                      _detalleRow('Recogidas', '${(s["recogidas"] as List).length} sede(s)'),
                    if (s['metodo_pago'] != null)
                      _detalleRow('Método pago', fmt(s['metodo_pago'])),
                    if (s['fn_alta_demanda'] == true)
                      _detalleRow('Alta demanda', '🔥 Sí'),
                    if (s['accepted_at'] != null)
                      _detalleRow('Aceptado', fmtFecha(s['accepted_at'])),
                  ],
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _detalleRow(String label, String valor) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 100,
            child: Text(label,
                style: const TextStyle(fontSize: 12, color: Colors.black45, fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Text(valor, style: const TextStyle(fontSize: 12, color: Colors.black87)),
          ),
        ]),
      );

  Future<void> _exportarCSV() async {
    final lista = _filtrados;
    if (lista.isEmpty) return;
    final buf = StringBuffer();
    buf.writeln('ID,Estado,Origen,Destino,Tarifa,Móvil,Creador,Fecha');
    for (final s in lista) {
      final fecha = s['created_at'] != null
          ? DateFormat('dd/MM/yyyy HH:mm').format(DateTime.parse(s['created_at']).toLocal())
          : '';
      buf.writeln([
        s['id'], s['estado'],
        '"${(s['origen'] ?? '').toString().replaceAll('"', "'")}"',
        '"${(s['destino'] ?? '').toString().replaceAll('"', "'")}"',
        s['tarifa'] ?? '',
        _nombreMovil(s['movil_id']),
        s['creador'] ?? '',
        fecha,
      ].join(','));
    }
    final dir = await getTemporaryDirectory();
    final file = File(
        '${dir.path}/historial_${DateFormat("yyyyMMdd_HHmm").format(DateTime.now())}.csv');
    await file.writeAsString(buf.toString());
    // ignore: deprecated_member_use
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'text/csv')],
      subject: 'Historial Servicios Servimoto',
    );
  }
}

enum _RangoFecha {
  hoy('Hoy'), ayer('Ayer'), semana('7 días'), mes('Este mes');
  const _RangoFecha(this.label);
  final String label;
}
