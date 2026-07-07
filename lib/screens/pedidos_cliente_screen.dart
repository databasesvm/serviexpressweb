import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:serviexpress_app/utils/sonido_manager.dart';

// ============================================================
// HELPERS GLOBALES — TIPO DE SERVICIO POR CATEGORÍA
// ============================================================

/// Mapea categoria_local → tipo_servicio que va al pedido
String tipoServicioDesdeCategoria(String cat) {
  final s = cat.toLowerCase();
  if (s.contains('comida') || s.contains('restaurante') ||
      s.contains('panadería') || s.contains('pastelería')) return 'COMIDA';
  if (s.contains('bebidas') || s.contains('licores')) return 'BEBIDAS';
  return 'COMPRAS'; // mercado, farmacia, ferretería, papelería, etc.
}

/// Devuelve (icono, color, label) según tipo_servicio
(IconData, Color, String) infoTipoServicio(String tipo) {
  switch (tipo.toUpperCase()) {
    case 'COMIDA':    return (Icons.dining,            Colors.red[700]!,          'COMIDA');
    case 'BEBIDAS':   return (Icons.nightlife,          Colors.purple[600]!,      'BEBIDAS');
    case 'MOTOTAXI':  return (Icons.two_wheeler,        Colors.orange[700]!,      'MOTOTAXI');
    case 'COMPRAS':   return (Icons.shopping_basket,    Colors.teal[600]!,        'ENCARGO');
    default:          return (Icons.inventory_2_rounded, Colors.brown[500]!,      'PAQUETERÍA');
  }
}

/// Ícono por categoria_local (para chips de filtro)
(IconData, Color) iconoCategoria(String cat) {
  final s = cat.toLowerCase();
  if (s.contains('restaurante') || s.contains('comida')) return (Icons.dining,              Colors.red[700]!);
  if (s.contains('bebidas') || s.contains('licores'))    return (Icons.nightlife,            Colors.purple[600]!);
  if (s.contains('panadería') || s.contains('pastelería')) return (Icons.cake_outlined,     Colors.red[400]!);
  if (s.contains('mercado') || s.contains('supermercado')) return (Icons.local_grocery_store, Colors.teal[600]!);
  if (s.contains('farmacia') || s.contains('droguería')) return (Icons.medication_liquid,   Colors.blue[700]!);
  if (s.contains('ferretería'))    return (Icons.construction,          Colors.teal[700]!);
  if (s.contains('papelería'))     return (Icons.edit_note,             Colors.blue[600]!);
  if (s.contains('tecnología') || s.contains('electrónica')) return (Icons.smartphone,      Colors.blue[800]!);
  if (s.contains('ropa') || s.contains('accesorios'))  return (Icons.style,                 Colors.teal[500]!);
  if (s.contains('mascotas'))      return (Icons.cruelty_free,          Colors.teal[400]!);
  return (Icons.storefront_outlined,                                     Colors.teal[600]!);
}


// ============================================================
// MODELOS
// ============================================================

class CartItem {
  final Map<String, dynamic> producto;
  int cantidad;
  String notas;
  CartItem({required this.producto, this.cantidad = 1, this.notas = ''});
  int get subtotal => (producto['precio'] as int) * cantidad;
}

// ============================================================
// PANTALLA 1 — LOCALES CON DOMICILIO ACTIVO
// ============================================================

class PedidosClienteScreen extends StatefulWidget {
  final Map<String, dynamic> usuario;
  const PedidosClienteScreen({super.key, required this.usuario});

  @override
  State<PedidosClienteScreen> createState() => _PedidosClienteScreenState();
}

class _PedidosClienteScreenState extends State<PedidosClienteScreen> {
  final _db = Supabase.instance.client;
  List<Map<String, dynamic>> _locales = [];
  List<Map<String, dynamic>> _pedidosActivos = [];
  List<Map<String, dynamic>> _pedidosEntregados = [];
  final Set<String> _calificacionesMostradas = {};
  Map<int, double> _ratingPorLocal = {};
  String _searchQuery = '';
  String _catFiltro = 'Todos';
  bool _cargando = true;
  RealtimeChannel? _canalPedidos;

  List<Map<String, dynamic>> get _localesFiltrados {
    return _locales.where((l) {
      final matchesSearch = _searchQuery.isEmpty ||
          l['nombre'].toString().toLowerCase().contains(_searchQuery.toLowerCase());
      final matchesCat = _catFiltro == 'Todos' ||
          (l['categoria_local']?.toString() ?? '') == _catFiltro;
      return matchesSearch && matchesCat;
    }).toList();
  }

  List<String> get _categoriasLocales {
    final cats = _locales
        .map((l) => l['categoria_local']?.toString() ?? '')
        .where((c) => c.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return ['Todos', ...cats];
  }

  @override
  void initState() {
    super.initState();
    _cargarDatos();
    _suscribirPedidos();
  }

  @override
  void dispose() {
    _canalPedidos?.unsubscribe();
    super.dispose();
  }

  Future<void> _cargarDatos() async {
    setState(() => _cargando = true);
    try {
      final locales = await _db
          .from('usuarios')
          .select(
              'id, nombre, direccion, foto_perfil_url, activo, domicilios_activo, tiempo_entrega, categoria_local, horario_apertura, horario_cierre, dias_semana, pedido_minimo')
          .eq('rol', 'local')
          .order('nombre');

      // Ratings por local
      final ratingsData = await _db
          .from('calificaciones')
          .select('local_id, estrellas')
          .eq('calificador_tipo', 'cliente_local')
          .not('local_id', 'is', null);

      final Map<int, List<int>> ratingsPorLocal = {};
      for (final r in (ratingsData as List)) {
        final lid = (r['local_id'] as num?)?.toInt();
        if (lid != null) {
          ratingsPorLocal
              .putIfAbsent(lid, () => [])
              .add((r['estrellas'] as num).toInt());
        }
      }
      final Map<int, double> promedios = {};
      ratingsPorLocal.forEach((lid, stars) {
        promedios[lid] = stars.reduce((a, b) => a + b) / stars.length;
      });

      final pedidos = await _db
          .from('pedidos')
          .select('*, items_pedido(nombre_snapshot, cantidad, precio_snapshot)')
          .eq('cliente_id', widget.usuario['id'])
          .neq('estado', 'entregado')
          .neq('estado', 'cancelado')
          .order('created_at', ascending: false);

      final entregados = await _db
          .from('pedidos')
          .select(
              'id, estado, total, metodo_pago, created_at, movil_id, local_id, items_pedido(nombre_snapshot, cantidad, producto_id, precio_snapshot)')
          .eq('cliente_id', widget.usuario['id'])
          .eq('estado', 'entregado')
          .gte(
              'created_at',
              DateTime.now()
                  .subtract(const Duration(days: 7))
                  .toIso8601String())
          .order('created_at', ascending: false);

      final entregadosIds =
          (entregados as List).map((p) => p['id'].toString()).toList();
      Set<String> yaCalificados = {};
      if (entregadosIds.isNotEmpty) {
        final cals = await _db
            .from('calificaciones')
            .select('pedido_id')
            .eq('calificador_tipo', 'cliente_domicilio')
            .inFilter('pedido_id', entregadosIds);
        yaCalificados =
            (cals as List).map((c) => c['pedido_id'].toString()).toSet();
      }

      if (!mounted) return;
      final sinCalificar = (entregados as List)
          .where((p) => !yaCalificados.contains(p['id'].toString()))
          .toList();

      // Ordenar: abiertos primero, cerrados segundo, sin domicilio al final
      final listaLocales = List<Map<String, dynamic>>.from(locales);
      listaLocales.sort((a, b) {
        int prioridad(Map<String, dynamic> l) {
          if (l['domicilios_activo'] != true) return 2; // sin domicilio
          if (_estaAbierto(l)) return 0;               // abierto
          return 1;                                     // cerrado
        }
        final pa = prioridad(a), pb = prioridad(b);
        if (pa != pb) return pa - pb;
        return (a['nombre']?.toString() ?? '').compareTo(b['nombre']?.toString() ?? '');
      });

      setState(() {
        _locales = listaLocales;
        _ratingPorLocal = promedios;
        _pedidosActivos = List<Map<String, dynamic>>.from(pedidos);
        _pedidosEntregados = List<Map<String, dynamic>>.from(entregados);
        _cargando = false;
      });

      for (final p in sinCalificar) {
        final pid = p['id'].toString();
        if (!_calificacionesMostradas.contains(pid) && mounted) {
          _calificacionesMostradas.add(pid);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _mostrarDialogoCalificacion(p);
          });
          break;
        }
      }
    } catch (e) {
      if (mounted) setState(() => _cargando = false);
    }
  }

  void _suscribirPedidos() {
    _canalPedidos = _db
        .channel('pedidos_cliente_${widget.usuario['id']}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'pedidos',
          callback: (payload) {
            final rec = payload.newRecord;
            if (rec.isEmpty) return;
            if ((rec['cliente_id'] as num?)?.toInt() != widget.usuario['id']) {
              return;
            }
            _cargarDatos();
          },
        )
        .subscribe();
  }

  bool _estaAbierto(Map<String, dynamic> local) {
    // Override manual: local cerró manualmente
    if (local['activo'] == false) return false;
    // Check day of week (Mon=0..Sun=6)
    final rawDias = local['dias_semana']?.toString();
    if (rawDias != null && rawDias.length == 7) {
      final idx = DateTime.now().weekday - 1;
      if (idx >= 0 && idx < 7 && rawDias[idx] == '0') return false;
    }
    // Check time
    final apertura = local['horario_apertura']?.toString();
    final cierre = local['horario_cierre']?.toString();
    if (apertura == null || cierre == null) return true;
    final now = TimeOfDay.now();
    int toMin(String s) {
      final p = s.split(':');
      if (p.length < 2) return 0;
      return (int.tryParse(p[0]) ?? 0) * 60 + (int.tryParse(p[1]) ?? 0);
    }
    final nowMin = now.hour * 60 + now.minute;
    final aMin = toMin(apertura);
    final cMin = toMin(cierre);
    if (aMin < cMin) return nowMin >= aMin && nowMin < cMin;
    return nowMin >= aMin || nowMin < cMin; // crosses midnight
  }

  String _labelEstado(String estado) {
    const m = {
      'pendiente_confirmacion': '⏳ Esperando confirmación del local',
      'confirmado': '✅ Pedido confirmado',
      'en_preparacion': '👨‍🍳 En preparación',
      'listo_para_recoger': '🛵 Esperando al móvil',
      'en_camino': '🛵 En camino a tu puerta',
      'entregado': '✅ Entregado',
      'cancelado': '❌ Cancelado',
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

  String _fmt(int precio) {
    final s = precio.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return '\$ ${buf.toString()}';
  }

  @override
  Widget build(BuildContext context) {
    final filtrados = _localesFiltrados;
    final categorias = _categoriasLocales;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: IconThemeData(color: Colors.white),
        title: Text('Pedir Domicilio',
            style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16)),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: Colors.black))
          : RefreshIndicator(
              onRefresh: _cargarDatos,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // ---- PEDIDOS ACTIVOS ----
                  if (_pedidosActivos.isNotEmpty) ...[
                    const Text('TUS PEDIDOS EN CURSO',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            letterSpacing: 1.2,
                            color: Colors.black54)),
                    const SizedBox(height: 8),
                    ..._pedidosActivos.map((p) => _buildPedidoTracking(p)),
                    const SizedBox(height: 20),
                  ],

                  // ---- BÚSQUEDA ----
                  TextField(
                    onChanged: (v) => setState(() => _searchQuery = v),
                    decoration: InputDecoration(
                      hintText: 'Buscar local...',
                      hintStyle: const TextStyle(fontSize: 13),
                      prefixIcon: const Icon(Icons.search, size: 20),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () =>
                                  setState(() => _searchQuery = ''),
                            )
                          : null,
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.08),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none),
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 10),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 10),

                  // ---- FILTRO CATEGORÍAS ----
                  if (categorias.length > 1)
                    SizedBox(
                      height: 36,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: categorias.length,
                        itemBuilder: (_, i) {
                          final cat = categorias[i];
                          final activa = cat == _catFiltro;
                          final isAll = cat == 'Todos';
                          final (ico, clr) = isAll
                              ? (Icons.apps, Colors.black)
                              : iconoCategoria(cat);
                          return GestureDetector(
                            onTap: () => setState(() => _catFiltro = cat),
                            child: Container(
                              margin: const EdgeInsets.only(right: 8),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: activa ? Colors.black : Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                    color: activa ? Colors.black : Colors.grey[300]!),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(ico,
                                      size: 13,
                                      color: activa ? const Color(0xff3AF500) : clr),
                                  const SizedBox(width: 4),
                                  Text(
                                    cat.split(' / ').first.split(' y ').first,
                                    style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: activa ? const Color(0xff3AF500) : Colors.black54),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 12),

                  // ---- LOCALES ----
                  const Text('LOCALES DISPONIBLES',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          letterSpacing: 1.2,
                          color: Colors.black54)),
                  const SizedBox(height: 8),
                  if (filtrados.isEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(40),
                        child: Column(
                          children: [
                            Icon(Icons.store_mall_directory_outlined,
                                size: 60, color: Colors.grey[300]),
                            const SizedBox(height: 12),
                            Text(
                              _searchQuery.isNotEmpty ||
                                      _catFiltro != 'Todos'
                                  ? 'Sin locales que coincidan'
                                  : 'No hay locales registrados aún',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey[500]),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    ...filtrados.map((l) => _buildLocalCard(l)),

                  // ---- HISTORIAL ----
                  if (_pedidosEntregados.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    const Text('ENTREGAS RECIENTES',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            letterSpacing: 1.2,
                            color: Colors.black54)),
                    const SizedBox(height: 8),
                    ..._pedidosEntregados
                        .map((p) => _buildHistorialCard(p)),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildPedidoTracking(Map<String, dynamic> p) {
    final estado = p['estado'].toString();
    final items = p['items_pedido'] as List? ?? [];
    final color = _colorEstado(estado);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                        color: color, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(_labelEstado(estado),
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: color,
                          fontSize: 13)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              items
                  .map((i) =>
                      '${i['cantidad']}x ${i['nombre_snapshot']}')
                  .join(' · '),
              style:
                  TextStyle(fontSize: 12, color: Colors.grey[600]),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text('Total: ${_fmt((p['total'] as num).toInt())}',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Widget _buildLocalCard(Map<String, dynamic> local) {
    final tieneDomicilio = local['domicilios_activo'] == true;
    final abierto = tieneDomicilio && _estaAbierto(local);
    final localId = (local['id'] as num).toInt();
    final rating = _ratingPorLocal[localId];
    final tiempoEntrega =
        (local['tiempo_entrega'] as num?)?.toInt() ?? 35;
    final pedidoMinimo =
        (local['pedido_minimo'] as num?)?.toInt() ?? 0;
    final categoria = local['categoria_local']?.toString() ?? '';

    // Texto del badge de estado
    String badgeLabel = '';
    Color badgeColor = Colors.red[700]!;
    if (!tieneDomicilio) {
      badgeLabel = 'SIN DOMICILIO';
      badgeColor = Colors.grey[700]!;
    } else if (!abierto) {
      final ap = local['horario_apertura']?.toString();
      badgeLabel = ap != null && ap.length >= 5
          ? 'CERRADO · Abre ${ap.substring(0, 5)}'
          : 'CERRADO';
      badgeColor = Colors.red[700]!;
    }

    // Abierto = color normal | Cerrado = ligeramente gris | Sin domicilio = muy gris
    final opacidad = abierto ? 1.0 : (tieneDomicilio ? 0.65 : 0.45);

    return Opacity(
      opacity: opacidad,
      child: Card(
        margin: const EdgeInsets.only(bottom: 10),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: abierto
              ? () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MenuLocalScreen(
                          local: local,
                          usuario: widget.usuario),
                    ),
                  ).then((_) => _cargarDatos())
              : () => ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(!tieneDomicilio
                          ? '${local['nombre']} no tiene domicilio activo aún'
                          : '${local['nombre']} está cerrado ahora'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ---- BANNER ----
              if (local['foto_perfil_url'] != null)
                SizedBox(
                  height: 110,
                  width: double.infinity,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.network(local['foto_perfil_url'],
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              Container(color: Colors.grey[200])),
                      if (badgeLabel.isNotEmpty)
                        Container(
                          color: Colors.black.withValues(alpha: 0.45),
                          alignment: Alignment.center,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 6),
                            decoration: BoxDecoration(
                                color: badgeColor,
                                borderRadius: BorderRadius.circular(20)),
                            child: Text(badgeLabel,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    letterSpacing: 0.8)),
                          ),
                        ),
                    ],
                  ),
                ),

              // ---- INFO ----
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (local['foto_perfil_url'] == null)
                      Container(
                        width: 50,
                        height: 50,
                        margin: const EdgeInsets.only(right: 10),
                        decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius:
                                BorderRadius.circular(10)),
                        child: const Icon(Icons.storefront,
                            color: Colors.grey, size: 28),
                      ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(local['nombre'],
                                    style: const TextStyle(
                                        fontWeight:
                                            FontWeight.bold,
                                        fontSize: 15)),
                              ),
                              if (badgeLabel.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                      color: badgeColor.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(20)),
                                  child: Text(badgeLabel,
                                      style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                          color: badgeColor)),
                                )
                              else if (abierto)
                                Container(
                                  padding:
                                      const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 3),
                                  decoration: BoxDecoration(
                                      color: const Color(0xff3AF500)
                                          .withValues(alpha: 0.15),
                                      borderRadius:
                                          BorderRadius.circular(
                                              20)),
                                  child: const Text('ABIERTO',
                                      style: TextStyle(
                                          fontSize: 9,
                                          fontWeight:
                                              FontWeight.bold,
                                          color:
                                              Color(0xff2aaa00))),
                                ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              if (categoria.isNotEmpty) ...[
                                Text(categoria,
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey[600])),
                                const SizedBox(width: 8),
                              ],
                              if (rating != null) ...[
                                const Icon(Icons.star,
                                    color: Colors.amber,
                                    size: 13),
                                const SizedBox(width: 2),
                                Text(rating.toStringAsFixed(1),
                                    style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight:
                                            FontWeight.bold)),
                                const SizedBox(width: 8),
                              ],
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(Icons.access_time,
                                  size: 12, color: Colors.grey),
                              const SizedBox(width: 3),
                              Text('$tiempoEntrega min',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey[600])),
                              if (pedidoMinimo > 0)
                                Text(
                                    '  ·  Mín ${_fmt(pedidoMinimo)}',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey[600])),
                            ],
                          ),
                          if ((local['direccion'] ?? '')
                              .toString()
                              .isNotEmpty)
                            Padding(
                              padding:
                                  const EdgeInsets.only(top: 2),
                              child: Text(local['direccion'],
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey[500])),
                            ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right,
                        color: Colors.grey),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHistorialCard(Map<String, dynamic> p) {
    final items = p['items_pedido'] as List? ?? [];
    final resumen = items
        .take(2)
        .map((i) => '${i["cantidad"]}x ${i["nombre_snapshot"]}')
        .join(', ');
    final extra =
        items.length > 2 ? ' +${items.length - 2} más' : '';
    final fecha =
        DateTime.tryParse(p['created_at']?.toString() ?? '');
    final fechaStr = fecha != null
        ? '${fecha.day}/${fecha.month} ${fecha.hour.toString().padLeft(2, '0')}:${fecha.minute.toString().padLeft(2, '0')}'
        : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: Colors.green.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.check_circle,
                      color: Colors.green, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          resumen.isEmpty
                              ? 'Pedido entregado'
                              : '$resumen$extra',
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      Text(
                          '$fechaStr  ·  ${_fmt(p['total'] as int? ?? 0)}',
                          style: const TextStyle(
                              fontSize: 11, color: Colors.grey)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding:
                          const EdgeInsets.symmetric(vertical: 6),
                      side: const BorderSide(
                          color: Colors.deepPurple),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.star_border,
                        size: 14, color: Colors.deepPurple),
                    label: const Text('Calificar',
                        style: TextStyle(
                            fontSize: 11,
                            color: Colors.deepPurple)),
                    onPressed: () =>
                        _mostrarDialogoCalificacion(p),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      padding:
                          const EdgeInsets.symmetric(vertical: 6),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.replay,
                        size: 14, color: Color(0xff3AF500)),
                    label: const Text('Repetir',
                        style: TextStyle(
                            fontSize: 11,
                            color: Color(0xff3AF500))),
                    onPressed: () => _repetirPedido(p),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _repetirPedido(
      Map<String, dynamic> pedidoHistorial) async {
    final localId =
        (pedidoHistorial['local_id'] as num?)?.toInt();
    if (localId == null) return;

    try {
      final localData = await _db
          .from('usuarios')
          .select(
              'id, nombre, direccion, foto_perfil, tiempo_entrega, categoria_local, horario_apertura, horario_cierre, dias_semana, pedido_minimo')
          .eq('id', localId)
          .single();

      final items =
          pedidoHistorial['items_pedido'] as List? ?? [];
      final productoIds = items
          .map((i) => i['producto_id'])
          .where((id) => id != null)
          .toList();

      List<Map<String, dynamic>> productos = [];
      if (productoIds.isNotEmpty) {
        final prodsData = await _db
            .from('productos')
            .select()
            .inFilter('id', productoIds)
            .eq('disponible', true);
        productos = List<Map<String, dynamic>>.from(prodsData);
      }

      final carritoInicial = <CartItem>[];
      for (final item in items) {
        if (item['producto_id'] == null) continue;
        final prod = productos.firstWhere(
          (p) =>
              p['id'].toString() ==
              item['producto_id'].toString(),
          orElse: () => <String, dynamic>{},
        );
        if (prod.isNotEmpty) {
          carritoInicial.add(CartItem(
              producto: prod,
              cantidad: (item['cantidad'] as num).toInt()));
        }
      }

      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MenuLocalScreen(
            local: Map<String, dynamic>.from(localData),
            usuario: widget.usuario,
            carritoInicial: carritoInicial,
          ),
        ),
      ).then((_) => _cargarDatos());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('No se pudo cargar el local: $e'),
            backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _mostrarDialogoCalificacion(
      Map<String, dynamic> pedido) async {
    int estrellasMovil = 5;
    int estrellasLocal = 5;
    final comentMovilCtrl = TextEditingController();
    final comentLocalCtrl = TextEditingController();

    final confirmar = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          title: const Text('¿Cómo fue tu experiencia?',
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ---- MÓVIL ----
                const Text('Móvil 🛵',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment:
                      MainAxisAlignment.center,
                  children: List.generate(
                      5,
                      (i) => GestureDetector(
                            onTap: () => setDlg(
                                () => estrellasMovil = i + 1),
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(
                                      horizontal: 4),
                              child: Icon(
                                  i < estrellasMovil
                                      ? Icons.star
                                      : Icons.star_border,
                                  color: Colors.amber,
                                  size: 32),
                            ),
                          )),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: comentMovilCtrl,
                  decoration: InputDecoration(
                    hintText:
                        'Comentario para el móvil…',
                    hintStyle:
                        const TextStyle(fontSize: 11),
                    border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(8)),
                    contentPadding:
                        const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                    isDense: true,
                  ),
                  maxLines: 2,
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 16),

                // ---- LOCAL ----
                const Text('Local 🍽️',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment:
                      MainAxisAlignment.center,
                  children: List.generate(
                      5,
                      (i) => GestureDetector(
                            onTap: () => setDlg(
                                () => estrellasLocal = i + 1),
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(
                                      horizontal: 4),
                              child: Icon(
                                  i < estrellasLocal
                                      ? Icons.star
                                      : Icons.star_border,
                                  color: Colors.orange,
                                  size: 32),
                            ),
                          )),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: comentLocalCtrl,
                  decoration: InputDecoration(
                    hintText: 'Comentario para el local…',
                    hintStyle:
                        const TextStyle(fontSize: 11),
                    border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(8)),
                    contentPadding:
                        const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                    isDense: true,
                  ),
                  maxLines: 2,
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Ahora no',
                  style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: const Color(0xff3AF500),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Enviar',
                  style:
                      TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );

    if (confirmar != true || !mounted) return;

    try {
      final movilId =
          (pedido['movil_id'] as num?)?.toInt();
      final localId =
          (pedido['local_id'] as num?)?.toInt();
      final nombre =
          widget.usuario['nombre']?.toString() ?? 'Cliente';

      // Calificación móvil
      if (movilId != null) {
        await _db.from('calificaciones').insert({
          'calificador_tipo': 'cliente_domicilio',
          'calificador_nombre': nombre,
          'pedido_id': pedido['id'],
          'movil_entero': movilId,
          'estrellas': estrellasMovil,
          'comentario':
              comentMovilCtrl.text.trim().isEmpty
                  ? null
                  : comentMovilCtrl.text.trim(),
        });
      }

      // Calificación local
      if (localId != null) {
        await _db.from('calificaciones').insert({
          'calificador_tipo': 'cliente_local',
          'calificador_nombre': nombre,
          'pedido_id': pedido['id'],
          'local_id': localId,
          'estrellas': estrellasLocal,
          'comentario':
              comentLocalCtrl.text.trim().isEmpty
                  ? null
                  : comentLocalCtrl.text.trim(),
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('¡Gracias por calificar! 🌟'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error al guardar: $e')));
      }
    }
  }
}

// ============================================================
// BOTTOM SHEET — PERSONALIZAR ÍTEM
// ============================================================
class _PersonalizarItemSheet extends StatefulWidget {
  final String nombreProducto;
  const _PersonalizarItemSheet({required this.nombreProducto});
  @override
  State<_PersonalizarItemSheet> createState() => _PersonalizarItemSheetState();
}

class _PersonalizarItemSheetState extends State<_PersonalizarItemSheet> {
  final _ctrl = TextEditingController();
  final _selectedChips = <String>{};

  static const _chips = [
    // Ingredientes
    'Sin cebolla', 'Sin ajo', 'Sin cilantro', 'Sin pimentón',
    'Sin vegetales', 'Sin tomate', 'Sin lechuga', 'Sin pepino',
    // Salsas
    'Sin salsas', 'Sin salsa rosada', 'Sin mostaza', 'Sin mayonesa',
    'Sin picante', 'Sin limón', 'Sin sal',
    // Extras
    'Extra queso', 'Extra salsa', 'Extra porción',
    // Cocción
    'Bien cocido', 'Término medio', 'Poco cocido',
    // Empaque
    'Empaque separado', 'Sin bolsa plástica',
  ];

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String _buildNotas() {
    final chips = _selectedChips.join(', ');
    final libre = _ctrl.text.trim();
    if (chips.isEmpty && libre.isEmpty) return '';
    if (chips.isEmpty) return libre;
    if (libre.isEmpty) return chips;
    return '$chips. $libre';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          const SizedBox(height: 8),
          Container(width: 36, height: 4,
              decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Icon(Icons.tune, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Personalizar: ${widget.nombreProducto}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Quick chips
          SizedBox(
            height: 120,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _chips.map((chip) {
                  final sel = _selectedChips.contains(chip);
                  return FilterChip(
                    label: Text(chip, style: TextStyle(
                        fontSize: 11,
                        color: sel ? Colors.white : Colors.black87,
                        fontWeight: sel ? FontWeight.bold : FontWeight.normal)),
                    selected: sel,
                    onSelected: (v) => setState(() => v ? _selectedChips.add(chip) : _selectedChips.remove(chip)),
                    selectedColor: Colors.black,
                    backgroundColor: Colors.grey.shade200,
                    checkmarkColor: const Color(0xff3AF500),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    visualDensity: VisualDensity.compact,
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(height: 10),
          // Text field
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _ctrl,
              maxLines: 2,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: 'Algo más específico... (opcional)',
                isDense: true,
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.08),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey[300]!)),
                contentPadding: const EdgeInsets.all(10),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, ''),
                    style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                    child: const Text('Sin cambios'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    icon: const Icon(Icons.add_shopping_cart, color: Color(0xff3AF500), size: 18),
                    label: Text('Agregar al carrito', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    onPressed: () => Navigator.pop(context, _buildNotas()),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// PANTALLA 2 — MENÚ DEL LOCAL + CARRITO
// ============================================================

class MenuLocalScreen extends StatefulWidget {
  final Map<String, dynamic> local;
  final Map<String, dynamic> usuario;
  final List<CartItem> carritoInicial;

  const MenuLocalScreen({
    super.key,
    required this.local,
    required this.usuario,
    this.carritoInicial = const [],
  });

  @override
  State<MenuLocalScreen> createState() =>
      _MenuLocalScreenState();
}

class _MenuLocalScreenState extends State<MenuLocalScreen> {
  final _db = Supabase.instance.client;
  final _busquedaCtrl = TextEditingController();
  final _sonidos = SonidoManager();
  List<Map<String, dynamic>> _productos = [];
  List<String> _categorias = [];
  String _catActual = '';
  String _busqueda = '';
  late List<CartItem> _carrito;
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _carrito = List.from(widget.carritoInicial);
    _cargarProductos();
  }

  @override
  void dispose() {
    _busquedaCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarProductos() async {
    try {
      final data = await _db
          .from('productos')
          .select()
          .eq('local_id', widget.local['id'])
          .eq('disponible', true)
          .order('categoria')
          .order('orden');
      if (!mounted) return;
      final prods = List<Map<String, dynamic>>.from(data);
      final cats = prods
          .map((p) => p['categoria'].toString())
          .toSet()
          .toList()
        ..sort();
      setState(() {
        _productos = prods;
        _categorias = cats;
        _catActual = cats.isNotEmpty ? cats.first : '';
        _cargando = false;
      });
    } catch (e) {
      if (mounted) setState(() => _cargando = false);
    }
  }

  int get _totalItems =>
      _carrito.fold(0, (s, i) => s + i.cantidad);
  int get _totalPrecio =>
      _carrito.fold(0, (s, i) => s + i.subtotal);

  Future<void> _agregar(Map<String, dynamic> p) async {
    final idx = _carrito.indexWhere((c) => c.producto['id'] == p['id']);
    if (idx >= 0) {
      setState(() => _carrito[idx].cantidad++);
      _sonidos.reproducirSuave(Sonidos.movilConfirmar);
      return;
    }
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => _PersonalizarItemSheet(nombreProducto: p['nombre']),
    );
    if (!mounted) return;
    setState(() {
      _carrito.add(CartItem(producto: p, notas: result ?? ''));
    });
    _sonidos.reproducirSuave(Sonidos.movilConfirmar);
  }

  void _quitar(Map<String, dynamic> p) {
    setState(() {
      final idx =
          _carrito.indexWhere((c) => c.producto['id'] == p['id']);
      if (idx < 0) return;
      if (_carrito[idx].cantidad <= 1) {
        _carrito.removeAt(idx);
      } else {
        _carrito[idx].cantidad--;
      }
    });
  }

  int _cantidadEn(Map<String, dynamic> p) {
    final idx =
        _carrito.indexWhere((c) => c.producto['id'] == p['id']);
    return idx >= 0 ? _carrito[idx].cantidad : 0;
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

  void _abrirCarrito() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _CarritoSheet(
        carrito: _carrito,
        local: widget.local,
        usuario: widget.usuario,
        onCambiarCantidad: (item, delta) {
          setState(() {
            item.cantidad += delta;
            if (item.cantidad <= 0) _carrito.remove(item);
          });
        },
        onPedidoOk: () {
          setState(() => _carrito.clear());
          Navigator.pop(ctx);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content:
                  Text('¡Pedido enviado! El local lo está revisando.'),
              backgroundColor: Colors.black,
            ),
          );
          Navigator.pop(context);
        },
      ),
    );
  }

  Widget _buildLocalHeader() {
    final local = widget.local;
    final tiempoEntrega =
        (local['tiempo_entrega'] as num?)?.toInt() ?? 35;
    final pedidoMinimo =
        (local['pedido_minimo'] as num?)?.toInt() ?? 0;
    final categoria = local['categoria_local']?.toString() ?? '';
    final apertura = local['horario_apertura']?.toString();
    final cierre = local['horario_cierre']?.toString();

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if ((local['direccion'] ?? '').toString().isNotEmpty)
            Text(local['direccion'],
                style:
                    TextStyle(fontSize: 12, color: Colors.grey[600])),
          const SizedBox(height: 6),
          Wrap(
            spacing: 16,
            runSpacing: 4,
            children: [
              _infoChip(
                  Icons.access_time, '$tiempoEntrega min'),
              if (pedidoMinimo > 0)
                _infoChip(Icons.shopping_bag_outlined,
                    'Mín ${_fmt(pedidoMinimo)}'),
              if (categoria.isNotEmpty)
                Builder(builder: (ctx) {
                  final (ico, clr, lbl) = infoTipoServicio(tipoServicioDesdeCategoria(categoria));
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: clr.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: clr.withValues(alpha: 0.4)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(ico, size: 11, color: clr),
                      const SizedBox(width: 3),
                      Text(lbl, style: TextStyle(fontSize: 10, color: clr, fontWeight: FontWeight.bold)),
                    ]),
                  );
                }),
              if (categoria.isNotEmpty)
                _infoChip(Icons.category_outlined, categoria.split(' / ').first),
              if (apertura != null && cierre != null)
                _infoChip(Icons.schedule,
                    '${apertura.substring(0, 5)} – ${cierre.substring(0, 5)}'),
              Builder(builder: (ctx) {
                final rawDias = local['dias_semana']?.toString();
                if (rawDias == null || rawDias.length != 7 || rawDias == '1111111') return const SizedBox.shrink();
                const labels = ['L','M','X','J','V','S','D'];
                final dias = List.generate(7, (i) => rawDias[i] == '1' ? labels[i] : null)
                    .whereType<String>().join(' ');
                return _infoChip(Icons.calendar_month_outlined, dias);
              }),
            ],
          ),
        ],
      ),
    );
  }

  Widget _infoChip(IconData icon, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.grey[600]),
          const SizedBox(width: 4),
          Text(label,
              style:
                  TextStyle(fontSize: 12, color: Colors.grey[700])),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final productosCat = _busqueda.isEmpty
        ? _productos
            .where((p) => p['categoria'] == _catActual)
            .toList()
        : _productos
            .where((p) =>
                p['nombre']
                    .toString()
                    .toLowerCase()
                    .contains(_busqueda.toLowerCase()) ||
                (p['descripcion'] ?? '')
                    .toString()
                    .toLowerCase()
                    .contains(_busqueda.toLowerCase()))
            .toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: IconThemeData(color: Colors.white),
        title: Text(
          widget.local['nombre'],
          style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 15),
        ),
      ),
      floatingActionButton: _totalItems > 0
          ? FloatingActionButton.extended(
              backgroundColor: Colors.black,
              onPressed: _abrirCarrito,
              icon: Stack(
                clipBehavior: Clip.none,
                children: [
                  const Icon(Icons.shopping_cart,
                      color: Color(0xff3AF500)),
                  Positioned(
                    top: -6,
                    right: -6,
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle),
                      child: Center(
                        child: Text('$_totalItems',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ),
                ],
              ),
              label: Text(
                _fmt(_totalPrecio),
                style: const TextStyle(
                    color: Color(0xff3AF500),
                    fontWeight: FontWeight.bold),
              ),
            )
          : null,
      body: _cargando
          ? const Center(
              child: CircularProgressIndicator(
                  color: Colors.black))
          : _productos.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.restaurant_menu,
                          size: 60, color: Colors.grey[300]),
                      const SizedBox(height: 12),
                      Text(
                          'Este local aún no tiene productos publicados',
                          style:
                              TextStyle(color: Colors.grey[500])),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // ---- INFO HEADER ----
                    _buildLocalHeader(),

                    // ---- BÚSQUEDA ----
                    Container(
                      color: Colors.white,
                      padding:
                          const EdgeInsets.fromLTRB(12, 4, 12, 8),
                      child: TextField(
                        controller: _busquedaCtrl,
                        onChanged: (v) =>
                            setState(() => _busqueda = v),
                        decoration: InputDecoration(
                          hintText: 'Buscar en el menú...',
                          hintStyle:
                              const TextStyle(fontSize: 12),
                          prefixIcon: const Icon(Icons.search,
                              size: 18),
                          suffixIcon: _busqueda.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear,
                                      size: 16),
                                  onPressed: () {
                                    _busquedaCtrl.clear();
                                    setState(
                                        () => _busqueda = '');
                                  },
                                )
                              : null,
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.08),
                          border: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(10),
                              borderSide: BorderSide.none),
                          contentPadding:
                              const EdgeInsets.symmetric(
                                  vertical: 8),
                          isDense: true,
                        ),
                      ),
                    ),

                    // ---- TABS CATEGORÍAS (ocultas al buscar) ----
                    if (_busqueda.isEmpty &&
                        _categorias.length > 1)
                      Container(
                        color: Colors.white,
                        height: 46,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12),
                          itemCount: _categorias.length,
                          itemBuilder: (_, i) {
                            final cat = _categorias[i];
                            final activa = cat == _catActual;
                            return GestureDetector(
                              onTap: () => setState(
                                  () => _catActual = cat),
                              child: Container(
                                margin:
                                    const EdgeInsets.symmetric(
                                        horizontal: 4,
                                        vertical: 8),
                                padding:
                                    const EdgeInsets.symmetric(
                                        horizontal: 14),
                                decoration: BoxDecoration(
                                  color: activa
                                      ? Colors.black
                                      : Colors.grey[100],
                                  borderRadius:
                                      BorderRadius.circular(20),
                                ),
                                child: Center(
                                  child: Text(cat,
                                      style: TextStyle(
                                          fontSize: 12,
                                          fontWeight:
                                              FontWeight.bold,
                                          color: activa
                                              ? const Color(
                                                  0xff3AF500)
                                              : Colors.black54)),
                                ),
                              ),
                            );
                          },
                        ),
                      ),

                    // ---- LISTA PRODUCTOS ----
                    Expanded(
                      child: productosCat.isEmpty
                          ? Center(
                              child: Text(
                                  'Sin resultados para "$_busqueda"',
                                  style: TextStyle(
                                      color: Colors.grey[500])),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(
                                  12, 12, 12, 100),
                              itemCount: productosCat.length,
                              itemBuilder: (_, i) =>
                                  _buildProductoCard(
                                      productosCat[i]),
                            ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildProductoCard(Map<String, dynamic> p) {
    final cant = _cantidadEn(p);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          // Foto
          ClipRRect(
            borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                bottomLeft: Radius.circular(12)),
            child: p['foto_url'] != null
                ? Image.network(p['foto_url'],
                    width: 100,
                    height: 100,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        _placeholder())
                : _placeholder(),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p['nombre'],
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14)),
                  if ((p['descripcion'] ?? '')
                      .toString()
                      .isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(p['descripcion'],
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[600])),
                    ),
                  const SizedBox(height: 6),
                  Text(_fmt(p['precio'] as int),
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14)),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: cant == 0
                ? ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      minimumSize: const Size(40, 36),
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(8)),
                    ),
                    onPressed: () => _agregar(p),
                    child: const Icon(Icons.add,
                        color: Color(0xff3AF500), size: 20),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _btnControle(Icons.remove, Colors.red,
                          () => _quitar(p)),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8),
                        child: Text('$cant',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16)),
                      ),
                      _btnControle(Icons.add, Colors.black,
                          () => _agregar(p)),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _placeholder() => Container(
        width: 100,
        height: 100,
        color: Colors.grey[100],
        child: Icon(Icons.fastfood,
            color: Colors.grey[300], size: 36),
      );

  Widget _btnControle(
          IconData icon, Color color, VoidCallback onTap) =>
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6)),
          child: Icon(icon, size: 16, color: color),
        ),
      );
}

// ============================================================
// CARRITO BOTTOM SHEET
// ============================================================

class _CarritoSheet extends StatefulWidget {
  final List<CartItem> carrito;
  final Map<String, dynamic> local;
  final Map<String, dynamic> usuario;
  final void Function(CartItem, int) onCambiarCantidad;
  final VoidCallback onPedidoOk;

  const _CarritoSheet({
    required this.carrito,
    required this.local,
    required this.usuario,
    required this.onCambiarCantidad,
    required this.onPedidoOk,
  });

  @override
  State<_CarritoSheet> createState() => _CarritoSheetState();
}

class _CarritoSheetState extends State<_CarritoSheet> {
  final _db = Supabase.instance.client;
  final _sonidos = SonidoManager();
  final _dirCtrl = TextEditingController();
  final _notasCtrl = TextEditingController();
  String _metodoPago = 'efectivo';
  bool _enviando = false;
  bool _enCheckout = false;
  XFile? _comprobanteImg;
  Uint8List? _comprobanteBytes;
  bool _guardarDireccion = false;
  List<String> _direccionesGuardadas = [];

  @override
  void initState() {
    super.initState();
    _cargarDirecciones();
  }

  void _cargarDirecciones() {
    final raw = widget.usuario['direcciones_guardadas'];
    List<String> dirs = [];
    if (raw is List) {
      dirs = raw.map((d) => d.toString()).toList();
    } else if (raw is String && raw.isNotEmpty && raw != '[]') {
      try {
        final parsed = jsonDecode(raw) as List;
        dirs = parsed.map((d) => d.toString()).toList();
      } catch (_) {}
    }
    _direccionesGuardadas = dirs;

    if (dirs.isNotEmpty) {
      _dirCtrl.text = dirs.first;
    } else {
      _dirCtrl.text =
          widget.usuario['ultimo_destino']?.toString() ??
              widget.usuario['direccion']?.toString() ??
              '';
    }
  }

  @override
  void dispose() {
    _dirCtrl.dispose();
    _notasCtrl.dispose();
    super.dispose();
  }

  int get _subtotal =>
      widget.carrito.fold(0, (s, i) => s + i.subtotal);
  int get _tarifaDomicilio => 2000;
  int get _total => _subtotal + _tarifaDomicilio;

  String _fmt(int precio) {
    final s = precio.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return '\$ ${buf.toString()}';
  }

  Future<void> _confirmar() async {
    if (_dirCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Ingresa tu dirección de entrega'),
          backgroundColor: Colors.red));
      return;
    }
    // Validar comprobante obligatorio si es transferencia
    if (_metodoPago == 'transferencia' && _comprobanteImg == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Adjunta el comprobante de transferencia para continuar'),
          backgroundColor: Colors.purple));
      return;
    }
    setState(() => _enviando = true);
    try {
      final catLocal = widget.local['categoria_local']?.toString() ?? '';
      final tipoSvcPedido = tipoServicioDesdeCategoria(catLocal);
      final pedido = await _db.from('pedidos').insert({
        'cliente_id': widget.usuario['id'],
        'local_id': widget.local['id'],
        'estado': 'pendiente_confirmacion',
        'tipo_servicio': tipoSvcPedido,
        'direccion_entrega': _dirCtrl.text.trim(),
        'subtotal': _subtotal,
        'tarifa_domicilio': _tarifaDomicilio,
        'total': _total,
        'metodo_pago': _metodoPago,
        'notas': _notasCtrl.text.trim().isEmpty
            ? null
            : _notasCtrl.text.trim(),
      }).select().single();

      final pedidoId = pedido['id'];

      // ── Subir comprobante si existe ─────────────────────────────────────
      if (_comprobanteImg != null) {
        try {
          final bytes = _comprobanteBytes ?? await _comprobanteImg!.readAsBytes();
          final ext = _comprobanteImg!.path.split('.').last.toLowerCase();
          final storagePath = 'comprobantes/$pedidoId.$ext';
          await Supabase.instance.client.storage
              .from('comprobantes')
              .uploadBinary(storagePath, bytes,
                  fileOptions: FileOptions(
                      contentType: 'image/$ext', upsert: true));
          final url = Supabase.instance.client.storage
              .from('comprobantes')
              .getPublicUrl(storagePath);
          await _db
              .from('pedidos')
              .update({'comprobante_url': url})
              .eq('id', pedidoId);
        } catch (_) {
          // comprobante falla silenciosamente — el pedido ya fue creado
        }
      }

      final items = widget.carrito
          .map((c) => {
                'pedido_id': pedidoId,
                'producto_id': c.producto['id'],
                'nombre_snapshot': c.producto['nombre'],
                'precio_snapshot': c.producto['precio'],
                'cantidad': c.cantidad,
                'subtotal': c.subtotal,
                if (c.notas.isNotEmpty) 'notas_snapshot': c.notas,
              })
          .toList();
      await _db.from('items_pedido').insert(items);

      // Guardar dirección si el usuario lo solicitó
      if (_guardarDireccion) {
        final dir = _dirCtrl.text.trim();
        final nuevas = [
          dir,
          ..._direccionesGuardadas.where((d) => d != dir)
        ].take(5).toList();
        await _db
            .from('usuarios')
            .update({'direcciones_guardadas': nuevas})
            .eq('id', widget.usuario['id']);
      }

      _sonidos.reproducir(Sonidos.movilConfirmar);
      widget.onPedidoOk();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Error al enviar: $e'),
            backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom:
              MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2))),
            ),
            const SizedBox(height: 16),
            Text(
              _enCheckout ? 'Confirmar pedido' : 'Tu carrito',
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const SizedBox(height: 14),

            if (!_enCheckout) ...[
              // ---- ITEMS ----
              ...widget.carrito.map((item) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        _btnCtrl(
                            Icons.remove,
                            Colors.red,
                            () => setState(() =>
                                widget.onCambiarCantidad(item, -1))),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10),
                          child: Text('${item.cantidad}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15)),
                        ),
                        _btnCtrl(
                            Icons.add,
                            Colors.black,
                            () => setState(() =>
                                widget.onCambiarCantidad(item, 1))),
                        const SizedBox(width: 10),
                        Expanded(
                            child: Text(item.producto['nombre'],
                                style: const TextStyle(
                                    fontSize: 13))),
                        Text(_fmt(item.subtotal),
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13)),
                      ],
                    ),
                  )),
              const Divider(),
              _filaTotal('Subtotal', _subtotal),
              _filaTotal('Tarifa domicilio', _tarifaDomicilio),
              const SizedBox(height: 4),
              _filaTotal('TOTAL', _total, negrita: true),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () =>
                      setState(() => _enCheckout = true),
                  child: const Text('CONTINUAR AL PAGO',
                      style: TextStyle(
                          color: Color(0xff3AF500),
                          fontWeight: FontWeight.bold)),
                ),
              ),
            ] else ...[
              // ---- CHECKOUT ----

              // Tarjeta de identificación del cliente
              Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: Colors.black,
                      child: Text(
                        (widget.usuario['nombre']?.toString() ?? '?')
                            .trim()
                            .split(' ')
                            .map((p) => p.isNotEmpty ? p[0] : '')
                            .take(2)
                            .join(),
                        style: const TextStyle(
                            color: Color(0xff3AF500),
                            fontWeight: FontWeight.bold,
                            fontSize: 13),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.usuario['nombre']?.toString() ?? '—',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 13),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Icon(Icons.phone_outlined,
                                  size: 12, color: Colors.grey[500]),
                              const SizedBox(width: 4),
                              Text(
                                widget.usuario['telefono']?.toString() ?? '—',
                                style: TextStyle(
                                    fontSize: 11, color: Colors.grey[600]),
                              ),
                              if (widget.usuario['cedula'] != null &&
                                  widget.usuario['cedula'].toString().isNotEmpty) ...[
                                const SizedBox(width: 10),
                                Icon(Icons.badge_outlined,
                                    size: 12, color: Colors.grey[500]),
                                const SizedBox(width: 4),
                                Text(
                                  widget.usuario['cedula'].toString(),
                                  style: TextStyle(
                                      fontSize: 11, color: Colors.grey[600]),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Direcciones guardadas
              if (_direccionesGuardadas.isNotEmpty) ...[
                const Text('Direcciones guardadas:',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                SizedBox(
                  height: 34,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _direccionesGuardadas.length,
                    itemBuilder: (_, i) {
                      final dir = _direccionesGuardadas[i];
                      final activa = _dirCtrl.text == dir;
                      return GestureDetector(
                        onTap: () =>
                            setState(() => _dirCtrl.text = dir),
                        child: Container(
                          margin:
                              const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: activa
                                ? Colors.black
                                : Colors.grey[100],
                            borderRadius:
                                BorderRadius.circular(20),
                            border: Border.all(
                                color: activa
                                    ? Colors.black
                                    : Colors.grey[300]!),
                          ),
                          child: Text(
                            dir.length > 24
                                ? '${dir.substring(0, 24)}…'
                                : dir,
                            style: TextStyle(
                                fontSize: 11,
                                color: activa
                                    ? const Color(0xff3AF500)
                                    : Colors.black87),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 10),
              ],

              TextField(
                controller: _dirCtrl,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Dirección de entrega *',
                  prefixIcon: Icon(Icons.location_on_outlined),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              Row(
                children: [
                  Checkbox(
                    value: _guardarDireccion,
                    onChanged: (v) => setState(
                        () => _guardarDireccion = v ?? false),
                    visualDensity: VisualDensity.compact,
                  ),
                  const Text('Guardar esta dirección',
                      style: TextStyle(fontSize: 12)),
                ],
              ),
              const SizedBox(height: 4),

              const Text('Método de pago:',
                  style: TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 8),
              Row(
                children: [
                  _chipPago('efectivo', '💵 Efectivo'),
                  const SizedBox(width: 8),
                  _chipPago(
                      'transferencia', '📲 Nequi / Bancolombia'),
                ],
              ),
              const SizedBox(height: 12),

              TextField(
                controller: _notasCtrl,
                maxLines: 2,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Notas especiales (opcional)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              _filaTotal('Total a pagar', _total, negrita: true),
              if (_metodoPago == 'transferencia') ...[
                const SizedBox(height: 10),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.purple[50],
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.purple[200]!),
                  ),
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Icon(Icons.receipt_long_rounded, size: 16, color: Colors.purple[700]),
                        const SizedBox(width: 6),
                        Text('Comprobante de transferencia',
                            style: TextStyle(
                                fontSize: 12, fontWeight: FontWeight.bold,
                                color: Colors.purple[800])),
                      ]),
                      const SizedBox(height: 4),
                      Text('Adjunta la foto de tu comprobante antes de confirmar.',
                          style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                      const SizedBox(height: 8),
                      if (_comprobanteImg != null && _comprobanteBytes != null) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.memory(
                            _comprobanteBytes!,
                            height: 160, width: double.infinity,
                            fit: BoxFit.cover,
                          ),
                        ),
                        const SizedBox(height: 6),
                      ],
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.purple[700],
                            side: BorderSide(color: Colors.purple[400]!),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                          ),
                          icon: Icon(_comprobanteImg == null
                              ? Icons.add_photo_alternate_outlined
                              : Icons.edit_outlined,
                              size: 18),
                          label: Text(_comprobanteImg == null
                              ? 'Adjuntar comprobante'
                              : 'Cambiar imagen',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 12)),
                          onPressed: () async {
                            final picker = ImagePicker();
                            final src = await showModalBottomSheet<ImageSource>(
                              context: context,
                              builder: (ctx) => SafeArea(
                                child: Column(mainAxisSize: MainAxisSize.min, children: [
                                  ListTile(
                                    leading: const Icon(Icons.camera_alt_outlined),
                                    title: const Text('Cámara'),
                                    onTap: () => Navigator.pop(ctx, ImageSource.camera),
                                  ),
                                  ListTile(
                                    leading: const Icon(Icons.photo_library_outlined),
                                    title: const Text('Galería'),
                                    onTap: () => Navigator.pop(ctx, ImageSource.gallery),
                                  ),
                                ]),
                              ),
                            );
                            if (src == null) return;
                            final img = await picker.pickImage(
                                source: src, imageQuality: 75, maxWidth: 1200);
                            if (img != null) {
                              final bytes = await img.readAsBytes();
                              setState(() { _comprobanteImg = img; _comprobanteBytes = bytes; });
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  TextButton(
                    onPressed: () =>
                        setState(() => _enCheckout = false),
                    child: const Text('← Volver'),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black,
                          shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(10)),
                        ),
                        onPressed:
                            _enviando ? null : _confirmar,
                        child: _enviando
                            ? SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2))
                            : const Text('CONFIRMAR PEDIDO',
                                style: TextStyle(
                                    color: Color(0xff3AF500),
                                    fontWeight:
                                        FontWeight.bold)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _btnCtrl(
          IconData icon, Color color, VoidCallback onTap) =>
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6)),
          child: Icon(icon, size: 15, color: color),
        ),
      );

  Widget _filaTotal(String label, int valor,
          {bool negrita = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: negrita ? 14 : 12,
                    fontWeight: negrita
                        ? FontWeight.bold
                        : FontWeight.normal,
                    color: negrita
                        ? Colors.black
                        : Colors.grey[700])),
            Text(_fmt(valor),
                style: TextStyle(
                    fontSize: negrita ? 14 : 12,
                    fontWeight: negrita
                        ? FontWeight.bold
                        : FontWeight.normal)),
          ],
        ),
      );

  Widget _chipPago(String value, String label) => Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _metodoPago = value),
          child: Container(
            padding: const EdgeInsets.symmetric(
                vertical: 10, horizontal: 8),
            decoration: BoxDecoration(
              color: _metodoPago == value
                  ? Colors.black
                  : C