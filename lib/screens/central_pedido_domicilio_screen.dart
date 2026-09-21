import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:serviexpress_app/screens/pedidos_cliente_screen.dart';

// ============================================================
// CENTRAL — PEDIDO DOMICILIO EN NOMBRE DE UN CLIENTE EXTERNO
// Flujo: seleccionar local → menú con modificadores → checkout
// con nombre y teléfono del cliente (no requiere cuenta).
// ============================================================

class CentralPedidoDomicilioScreen extends StatefulWidget {
  const CentralPedidoDomicilioScreen({super.key});

  @override
  State<CentralPedidoDomicilioScreen> createState() =>
      _CentralPedidoDomicilioScreenState();
}

class _CentralPedidoDomicilioScreenState
    extends State<CentralPedidoDomicilioScreen> {
  final _db = Supabase.instance.client;
  List<Map<String, dynamic>> _locales = [];
  bool _cargando = true;
  String _busqueda = '';
  String _catFiltro = 'Todos';

  List<Map<String, dynamic>> get _localesFiltrados {
    return _locales.where((l) {
      final matchSearch = _busqueda.isEmpty ||
          l['nombre'].toString().toLowerCase().contains(_busqueda.toLowerCase());
      final matchCat = _catFiltro == 'Todos' ||
          (l['categoria_local']?.toString() ?? '') == _catFiltro;
      return matchSearch && matchCat;
    }).toList();
  }

  List<String> get _categorias {
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
    _cargarLocales();
  }

  Future<void> _cargarLocales() async {
    setState(() => _cargando = true);
    try {
      final data = await _db
          .from('usuarios')
          .select(
              'id, nombre, direccion, foto_perfil_url, domicilios_activo, '
              'tiempo_entrega, categoria_local, horario_apertura, horario_cierre, '
              'dias_semana, pedido_minimo, lat_fija, lng_fija')
          .eq('rol', 'local')
          .eq('activo', true)
          .eq('domicilios_activo', true)
          .order('nombre');
      if (mounted) {
        setState(() {
          _locales = List<Map<String, dynamic>>.from(data);
          _cargando = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text(
          '📦 Pedido Domicilio — Central',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Recargar',
            onPressed: _cargarLocales,
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Banner informativo ──────────────────────────────────────
          Container(
            width: double.infinity,
            color: Colors.orange[50],
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 14, color: Colors.orange[800]),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Pedido solicitado por cliente externo (teléfono / WhatsApp). '
                    'Selecciona el local y arma el pedido.',
                    style: TextStyle(fontSize: 11, color: Colors.orange[900]),
                  ),
                ),
              ],
            ),
          ),

          // ── Búsqueda ───────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: TextField(
              onChanged: (v) => setState(() => _busqueda = v),
              decoration: InputDecoration(
                hintText: 'Buscar local…',
                prefixIcon: const Icon(Icons.search, size: 18),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                isDense: true,
              ),
            ),
          ),

          // ── Filtro por categoría ───────────────────────────────────
          if (_categorias.length > 2)
            SizedBox(
              height: 36,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: _categorias.length,
                itemBuilder: (_, i) {
                  final cat = _categorias[i];
                  final sel = cat == _catFiltro;
                  return GestureDetector(
                    onTap: () => setState(() => _catFiltro = cat),
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: sel ? Colors.black : Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: sel ? Colors.black : Colors.grey[300]!),
                      ),
                      child: Text(
                        cat,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: sel ? const Color(0xff3AF500) : Colors.black87,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

          const SizedBox(height: 6),

          // ── Lista de locales ───────────────────────────────────────
          Expanded(
            child: _cargando
                ? const Center(child: CircularProgressIndicator())
                : _localesFiltrados.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.storefront_outlined,
                                size: 48, color: Colors.grey[300]),
                            const SizedBox(height: 8),
                            Text(
                              'No hay locales con domicilio activo',
                              style: TextStyle(
                                  color: Colors.grey[500], fontSize: 13),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _cargarLocales,
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                          itemCount: _localesFiltrados.length,
                          itemBuilder: (_, i) =>
                              _buildLocalCard(_localesFiltrados[i]),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocalCard(Map<String, dynamic> local) {
    final nombre = local['nombre']?.toString() ?? '—';
    final direccion = local['direccion']?.toString() ?? '';
    final cat = local['categoria_local']?.toString() ?? '';
    final tiempo = (local['tiempo_entrega'] as num?)?.toInt() ?? 35;
    final pedidoMin = (local['pedido_minimo'] as num?)?.toInt() ?? 0;
    final foto = local['foto_perfil_url']?.toString();
    final (ico, clr) = iconoCategoria(cat);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey[200]!),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _abrirMenu(local),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Foto / avatar
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: foto != null && foto.isNotEmpty
                    ? Image.network(foto,
                        width: 56, height: 56, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _avatarLocal(ico, clr))
                    : _avatarLocal(ico, clr),
              ),
              const SizedBox(width: 12),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(nombre,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14)),
                    if (direccion.isNotEmpty)
                      Text(direccion,
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey[600]),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Wrap(spacing: 10, children: [
                      _chip(Icons.access_time, '$tiempo min'),
                      if (pedidoMin > 0)
                        _chip(Icons.shopping_bag_outlined,
                            'Mín \$${_fmt(pedidoMin)}'),
                      if (cat.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: clr.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(cat,
                              style: TextStyle(
                                  fontSize: 10,
                                  color: clr,
                                  fontWeight: FontWeight.w600)),
                        ),
                    ]),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: Colors.black38),
            ],
          ),
        ),
      ),
    );
  }

  Widget _avatarLocal(IconData ico, Color clr) => Container(
        width: 56,
        height: 56,
        color: clr.withValues(alpha: 0.1),
        child: Icon(ico, color: clr, size: 28),
      );

  Widget _chip(IconData icon, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.grey[500]),
          const SizedBox(width: 3),
          Text(label,
              style: TextStyle(fontSize: 11, color: Colors.grey[600])),
        ],
      );

  String _fmt(int v) {
    final s = v.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  void _abrirMenu(Map<String, dynamic> local) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MenuLocalScreen(
          local: local,
          usuario: const {},   // No se usa en modoCentral
          modoCentral: true,
        ),
      ),
    );
  }
}
