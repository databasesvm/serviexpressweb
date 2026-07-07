import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:serviexpress_app/utils/onesignal_api.dart';
import 'package:serviexpress_app/screens/pedidos_cliente_screen.dart';

// ============================================================
// MONITOR DE PEDIDOS — PANTALLA CENTRAL
// Panel completo: todos los pedidos activos, toggle por local,
// cambio de estado manual y asignación de móvil.
// ============================================================

class MonitorPedidosScreen extends StatefulWidget {
  final Map<String, dynamic> usuario;
  const MonitorPedidosScreen({super.key, required this.usuario});

  @override
  State<MonitorPedidosScreen> createState() => _MonitorPedidosScreenState();
}

class _MonitorPedidosScreenState extends State<MonitorPedidosScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  final _db = Supabase.instance.client;

  List<Map<String, dynamic>> _pedidos = [];
  List<Map<String, dynamic>> _locales = [];
  List<Map<String, dynamic>> _moviles = [];
  bool _cargando = true;
  RealtimeChannel? _canal;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _cargarDatos();
    _suscribir();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _canal?.unsubscribe();
    super.dispose();
  }

  // -----------------------------------------------------------------------
  // DATOS
  // -----------------------------------------------------------------------
  Future<void> _cargarDatos() async {
    setState(() => _cargando = true);
    try {
      // Pedidos activos (todos los estados excepto terminal)
      final pedidos = await _db
          .from('pedidos')
          .select(
              '*, items_pedido(nombre_snapshot, cantidad, precio_snapshot)')
          .not('estado', 'in', '("entregado","cancelado")')
          .order('created_at', ascending: false);

      // Locales (para mostrar nombre en pedido + toggle domicilios)
      final locales = await _db
          .from('usuarios')
          .select('id, nombre, domicilios_activo, activo')
          .eq('rol', 'local')
          .order('nombre');

      // Móviles conectados (para asignación manual)
      final moviles = await _db
          .from('usuarios')
          .select('id, nombre, usuario')
          .eq('rol', 'movil')
          .eq('activo', true)
          .order('nombre');

      if (!mounted) return;
      setState(() {
        _pedidos = List<Map<String, dynamic>>.from(pedidos);
        _locales = List<Map<String, dynamic>>.from(locales);
        _moviles = List<Map<String, dynamic>>.from(moviles);
        _cargando = false;
      });
    } catch (e) {
      if (mounted) setState(() => _cargando = false);
    }
  }

  void _suscribir() {
    _canal = _db
        .channel('monitor_pedidos_central')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'pedidos',
          callback: (_) => _cargarDatos(),
        )
        .subscribe();
  }

  // -----------------------------------------------------------------------
  // ACCIONES SOBRE PEDIDOS
  // -----------------------------------------------------------------------
  final _estadosFlujo = const [
    'pendiente_confirmacion',
    'confirmado',
    'en_preparacion',
    'listo_para_recoger',
    'en_camino',
    'entregado',
  ];

  Future<void> _cambiarEstado(String pedidoId, String nuevoEstado, {String? clienteId}) async {
    try {
      await _db
          .from('pedidos')
          .update({'estado': nuevoEstado})
          .eq('id', pedidoId);
      await _cargarDatos();
      if (clienteId != null && clienteId.isNotEmpty) {
        const msgs = {
          'confirmado':         ('✅ Pedido confirmado',     'Tu pedido fue confirmado. ¡Ya lo están preparando!'),
          'en_preparacion':     ('👨‍🍳 Preparando tu pedido', 'El local ya está preparando tu pedido.'),
          'listo_para_recoger': ('📦 Listo para recoger',    'Tu pedido está listo. El móvil lo recoge pronto.'),
          'en_camino':          ('🛵 ¡En camino!',           'Tu pedido está en camino. Pronto llega a tu puerta.'),
          'entregado':          ('✅ Pedido entregado',      '¡Tu pedido fue entregado! Esperamos que lo disfrutes.'),
        };
        final info = msgs[nuevoEstado];
        if (info != null) {
          MotorNotificaciones.dispararMisil(
            idDestino: clienteId,
            titulo: info.$1,
            mensaje: info.$2,
            urgente: nuevoEstado == 'entregado' || nuevoEstado == 'en_camino',
            sonido: 'alerta',
          );
        }
      }
    } catch (e) {
      _snack('Error: \$e', error: true);
    }
  }

  Future<void> _cancelar(String pedidoId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Cancelar pedido?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('NO')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('CANCELAR',
                  style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok != true) return;
    // Buscar clienteId del pedido
    final pedidoData = _pedidos.firstWhere(
      (p) => p['id'].toString() == pedidoId,
      orElse: () => <String, dynamic>{},
    );
    final clienteId = pedidoData['cliente_id']?.toString() ?? '';
    await _cambiarEstado(pedidoId, 'cancelado', clienteId: clienteId.isNotEmpty ? clienteId : null);
    if (clienteId.isNotEmpty) {
      MotorNotificaciones.dispararMisil(
        idDestino: clienteId,
        titulo: '❌ Pedido cancelado',
        mensaje: 'Tu pedido fue cancelado por la central. Disculpa los inconvenientes.',
        urgente: false,
        sonido: 'alerta',
      );
    }
  }

  Future<void> _asignarMovil(Map<String, dynamic> pedido) async {
    final movilId = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Asignar móvil manualmente'),
        children: _moviles.map((m) {
          return SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, m['id'] as int),
            child: Text('${m['nombre']} (${m['usuario'] ?? 'movil${m['id']}'})',
                style: const TextStyle(fontSize: 14)),
          );
        }).toList(),
      ),
    );
    if (movilId == null) return;
    try {
      await _db.from('pedidos').update({
        'movil_id': movilId,
        'estado': 'confirmado',
      }).eq('id', pedido['id']);
      await _cargarDatos();
    } catch (e) {
      _snack('Error: $e', error: true);
    }
  }

  Future<void> _toggleDomicilios(Map<String, dynamic> local) async {
    final nuevoValor = !(local['domicilios_activo'] as bool? ?? false);
    try {
      await _db
          .from('usuarios')
          .update({'domicilios_activo': nuevoValor})
          .eq('id', local['id']);
      await _cargarDatos();
    } catch (e) {
      _snack('Error: $e', error: true);
    }
  }

  // -----------------------------------------------------------------------
  // HELPERS
  // -----------------------------------------------------------------------
  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: error ? Colors.red : Colors.black));
  }

  String _fmt(int precio) {
    final s = precio.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return '\$ ${buf.toString()}';
  }

  String _labelEstado(String estado) {
    const m = {
      'pendiente_confirmacion': 'Pendiente confirmación',
      'confirmado': 'Confirmado',
      'en_preparacion': 'En preparación',
      'listo_para_recoger': 'Listo p/ recoger',
      'en_camino': 'En camino',
      'entregado': 'Entregado',
      'cancelado': 'Cancelado',
    };
    return m[estado] ?? estado;
  }

  Color _colorEstado(String estado) {
    const c = {
      'pendiente_confirmacion': Colors.orange,
      'confirmado': Colors.blue,
      'en_preparacion': Colors.purple,
      'listo_para_recoger': Colors.teal,
      'en_camino': Colors.indigo,
      'entregado': Colors.green,
      'cancelado': Colors.red,
    };
    return c[estado] ?? Colors.grey;
  }

  String _nombreLocal(int localId) {
    final l = _locales.firstWhere((l) => l['id'] == localId,
        orElse: () => {'nombre': 'Local $localId'});
    return l['nombre'].toString();
  }

  String _nombreMovil(int? movilId) {
    if (movilId == null) return '—';
    final m = _moviles.firstWhere((m) => m['id'] == movilId,
        orElse: () => {'nombre': 'Movil $movilId', 'usuario': ''});
    return '${m['nombre']} (${m['usuario'] ?? ''})';
  }

  // -----------------------------------------------------------------------
  // BUILD
  // -----------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: IconThemeData(color: Colors.white),
        title: Text('Monitor Domicilios',
            style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 15)),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: Colors.white),
            onPressed: _cargarDatos,
          ),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          labelColor: const Color(0xff3AF500),
          unselectedLabelColor: Colors.white60,
          indicatorColor: const Color(0xff3AF500),
          tabs: [
            Tab(
              icon: Stack(
                clipBehavior: Clip.none,
                children: [
                  const Icon(Icons.receipt_long),
                  if (_pedidos.isNotEmpty)
                    Positioned(
                      top: -4,
                      right: -8,
                      child: Container(
                        width: 16,
                        height: 16,
                        decoration: const BoxDecoration(
                            color: Colors.red, shape: BoxShape.circle),
                        child: Center(
                          child: Text('${_pedidos.length}',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ),
                ],
              ),
              text: 'PEDIDOS',
            ),
            const Tab(icon: Icon(Icons.storefront), text: 'LOCALES'),
            const Tab(icon: Icon(Icons.add_shopping_cart), text: 'PEDIR'),
          ],
        ),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: Colors.black))
          : TabBarView(
              controller: _tabCtrl,
              children: [
                _buildTabPedidos(),
                _buildTabLocales(),
                _buildTabPedir(),
              ],
            ),
    );
  }

  // -----------------------------------------------------------------------
  // TAB 1 — PEDIDOS ACTIVOS
  // -----------------------------------------------------------------------
  Widget _buildTabPedidos() {
    if (_pedidos.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline, size: 60, color: Colors.grey[300]),
            const SizedBox(height: 12),
            Text('No hay pedidos activos',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: Colors.grey[600])),
          ],
        ),
      );
    }

    // Agrupar por estado
    final grupos = <String, List<Map<String, dynamic>>>{};
    for (final p in _pedidos) {
      final e = p['estado'].toString();
      grupos.putIfAbsent(e, () => []).add(p);
    }

    return RefreshIndicator(
      onRefresh: _cargarDatos,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          for (final estado in _estadosFlujo)
            if (grupos.containsKey(estado)) ...[
              _groupHeader(estado, grupos[estado]!.length),
              ...grupos[estado]!.map((p) => _buildPedidoCard(p)),
              const SizedBox(height: 8),
            ],
        ],
      ),
    );
  }

  Widget _groupHeader(String estado, int count) {
    final color = _colorEstado(estado);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                  color: color, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text(_labelEstado(estado).toUpperCase(),
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                  color: color,
                  letterSpacing: 0.8)),
          const SizedBox(width: 6),
          Text('($count)',
              style: TextStyle(fontSize: 11, color: Colors.grey[500])),
        ],
      ),
    );
  }

  Widget _buildPedidoCard(Map<String, dynamic> p) {
    final estado = p['estado'].toString();
    final items = p['items_pedido'] as List? ?? [];
    final colorEst = _colorEstado(estado);
    final idxActual = _estadosFlujo.indexOf(estado);
    final puedeAvanzar =
        idxActual >= 0 && idxActual < _estadosFlujo.length - 1;
    final siguienteEstado =
        puedeAvanzar ? _estadosFlujo[idxActual + 1] : estado;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: colorEst.withValues(alpha: 0.1),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _nombreLocal(p['local_id'] as int),
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
                Text(
                    '#${p['id'].toString().substring(0, 8).toUpperCase()}',
                    style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey[600],
                        fontFamily: 'monospace')),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Items
                ...items.map((i) => Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Row(
                        children: [
                          Text('${i['cantidad']}x ',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12)),
                          Expanded(
                              child: Text(i['nombre_snapshot'],
                                  style: const TextStyle(fontSize: 12))),
                        ],
                      ),
                    )),
                const Divider(height: 12),

                // Info logística
                _infoRow(Icons.location_on_outlined,
                    p['direccion_entrega']?.toString() ?? '—'),
                _infoRow(Icons.payments_outlined,
                    '${p['metodo_pago'] == 'efectivo' ? 'Efectivo' : 'Transferencia'} — Total: ${_fmt((p['total'] as num).toInt())}'),
                _infoRow(Icons.motorcycle,
                    'Móvil: ${_nombreMovil(p['movil_id'] as int?)}'),

                const SizedBox(height: 10),

                // Acciones
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    // Avanzar estado
                    if (puedeAvanzar)
                      _botonAccion(
                        '→ ${_labelEstado(siguienteEstado)}',
                        Colors.black,
                        const Color(0xff3AF500),
                        () => _cambiarEstado(
                            p['id'].toString(), siguienteEstado, clienteId: p['cliente_id']?.toString()),
                      ),
                    // Asignar móvil
                    if (p['movil_id'] == null && _moviles.isNotEmpty)
                      _botonAccion(
                        '🛵 Asignar móvil',
                        Colors.indigo,
                        Colors.white,
                        () => _asignarMovil(p),
                      ),
                    // Cancelar
                    if (!['entregado', 'cancelado', 'en_camino']
                        .contains(estado))
                      _botonAccion(
                        'Cancelar',
                        Colors.red.shade50,
                        Colors.red,
                        () => _cancelar(p['id'].toString()),
                        border: Colors.red,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Row(
          children: [
            Icon(icon, size: 14, color: Colors.grey),
            const SizedBox(width: 6),
            Expanded(
                child: Text(text,
                    style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis)),
          ],
        ),
      );

  Widget _botonAccion(String label, Color bg, Color fg, VoidCallback onTap,
      {Color? border}) =>
      Material(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: border != null
                    ? Border.all(color: border)
                    : null),
            child: Text(label,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: fg)),
          ),
        ),
      );

  // -----------------------------------------------------------------------
  // TAB 2 — LOCALES (toggle domicilios)
  // -----------------------------------------------------------------------
  Widget _buildTabLocales() {
    final conDomicilio =
        _locales.where((l) => l['domicilios_activo'] == true).toList();
    final sinDomicilio =
        _locales.where((l) => l['domicilios_activo'] != true).toList();

    if (_locales.isEmpty) {
      return const Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.storefront, color: Colors.white24, size: 48),
          SizedBox(height: 12),
          Text('No hay locales registrados', style: TextStyle(color: Colors.white38, fontSize: 13)),
        ]),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (conDomicilio.isNotEmpty) ...[
          _sectionLabel('✅ CON DOMICILIO ACTIVO (${conDomicilio.length})'),
          ...conDomicilio.map((l) => _buildLocalTile(l)),
          const SizedBox(height: 12),
        ],
        if (sinDomicilio.isNotEmpty) ...[
          _sectionLabel('⏸ SIN DOMICILIO (${sinDomicilio.length})'),
          ...sinDomicilio.map((l) => _buildLocalTile(l)),
        ],
      ],
    );
  }

  Widget _sectionLabel(String txt) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(txt,
            style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 11,
                letterSpacing: 0.8,
                color: Colors.white54)),
      );

  Widget _buildLocalTile(Map<String, dynamic> local) {
    final activo = local['domicilios_activo'] == true;
    final pedidosDeEste =
        _pedidos.where((p) => p['local_id'] == local['id']).length;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ListTile(
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: activo
                ? const Color(0xff3AF500).withValues(alpha: 0.12)
                : Colors.grey[100],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(Icons.storefront,
              color: activo ? const Color(0xff3AF500) : Colors.grey,
              size: 22),
        ),
        title: Text(local['nombre'],
            style: const TextStyle(
                fontWeight: FontWeight.bold, fontSize: 13)),
        subtitle: pedidosDeEste > 0
            ? Text('$pedidosDeEste pedido${pedidosDeEste > 1 ? 's' : ''} activo${pedidosDeEste > 1 ? 's' : ''}',
                style: const TextStyle(
                    fontSize: 11, color: Colors.orange))
            : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.history, color: Colors.black38, size: 20),
              tooltip: 'Ver historial',
              onPressed: () => _verHistorialLocal(local),
            ),
            Text(activo ? 'ON' : 'OFF',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: activo ? const Color(0xff3AF500) : Colors.grey)),
            const SizedBox(width: 6),
            Switch(
              value: activo,
              activeColor: const Color(0xff3AF500),
              onChanged: (_) => _toggleDomicilios(local),
            ),
          ],
        ),
      ),
    );
  }
  // -----------------------------------------------------------------------
  // TAB 3 — PEDIR (vista tipo cliente)
  // -----------------------------------------------------------------------
  Widget _buildTabPedir() {
    return Column(
      children: [
        // Botón compartir link
        Container(
          color: Colors.black,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              const Icon(Icons.link, color: Colors.white60, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Link: serviexpress://locales',
                  style: TextStyle(color: Colors.grey[400], fontSize: 12),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy, color: Color(0xff3AF500), size: 18),
                onPressed: () {
                  Clipboard.setData(const ClipboardData(text: 'https://serviexpress.app/locales'));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Link copiado'), backgroundColor: Colors.black),
                  );
                },
                tooltip: 'Copiar link',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ),
        Expanded(
          child: PedidosClienteScreen(usuario: widget.usuario),
        ),
      ],
    );
  }

  // -----------------------------------------------------------------------
  // HISTORIAL POR LOCAL
  // -----------------------------------------------------------------------
  Future<void> _verHistorialLocal(Map<String, dynamic> local) async {
    setState(() => _cargando = true);
    List<Map<String, dynamic>> historial = [];
    try {
      final data = await _db
          .from('pedidos')
          .select('id, estado, total, metodo_pago, created_at, items_pedido(nombre_snapshot, cantidad)')
          .eq('local_id', local['id'])
          .inFilter('estado', ['entregado', 'cancelado'])
          .order('created_at', ascending: false)
          .limit(30);
      historial = List<Map<String, dynamic>>.from(data);
    } catch (_) {}
    if (mounted) setState(() => _cargando = false);

    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0D0D0D),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        builder: (_, scroll) => Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.history, color: Color(0xff3AF500)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Historial — ${local['nombre']}',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ),
                  Text('${historial.length} pedidos',
                      style: const TextStyle(color: Colors.white54, fontSize: 12)),
                ],
              ),
            ),
            Expanded(
              child: historial.isEmpty
                  ? const Center(
                      child: Text('Sin pedidos finalizados',
                          style: TextStyle(color: Colors.black45)))
                  : ListView.builder(
                      controller: scroll,
                      padding: const EdgeInsets.all(12),
                      itemCount: historial.length,
                      itemBuilder: (_, i) {
                        final p = historial[i];
                        final items = p['items_pedido'] as List? ?? [];
                        final estado = p['estado'].toString();
                        final entregado = estado == 'entregado';
                        final fecha = DateTime.tryParse(p['created_at'].toString())?.toLocal();
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor:
                                  entregado ? Colors.green[50] : Colors.red[50],
                              child: Icon(
                                  entregado ? Icons.check_circle : Icons.cancel,
                                  color: entregado ? Colors.green : Colors.red,
                                  size: 20),
                            ),
                            title: Text(
                              items.map((i) => '${i['cantidad']}x ${i['nombre_snapshot']}').join(', '),
                              style: const TextStyle(fontSize: 12),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              fecha != null
                                  ? '${fecha.day}/${fecha.month}/${fecha.year} ${fecha.hour}:${fecha.minute.toString().padLeft(2, '0')}'
                                  : '',
                              style: const TextStyle(fontSize: 11),
                            ),
                            trailing: Text(
                              _fmt((p['total'] as num).toInt()),
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }


}