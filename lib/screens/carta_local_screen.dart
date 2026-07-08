import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:serviexpress_app/utils/onesignal_api.dart';
import 'package:serviexpress_app/utils/sonido_manager.dart';

// ============================================================
// CARTA LOCAL SCREEN — Gestión de menú y pedidos entrantes
// ============================================================

class CartaLocalScreen extends StatefulWidget {
  final int localId;
  final String localNombre;
  final int initialTab;

  const CartaLocalScreen({
    super.key,
    required this.localId,
    required this.localNombre,
    this.initialTab = 0,
  });

  @override
  State<CartaLocalScreen> createState() => _CartaLocalScreenState();
}

class _CartaLocalScreenState extends State<CartaLocalScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  final _db = Supabase.instance.client;
  final _sonidos = SonidoManager();

  // ---- Estado ----
  bool _domiciliosActivo = false;
  bool _cargando = true;
  List<Map<String, dynamic>> _productos = [];
  List<Map<String, dynamic>> _pedidos = [];
  List<String> _categorias = [];

  // ---- Streams ----
  RealtimeChannel? _canalPedidos;
  Timer? _timerReloj;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this, initialIndex: widget.initialTab);
    _tabCtrl.addListener(() {
      if (mounted) setState(() {});
    });
    _timerReloj = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
    _cargarDatos();
    _iniciarCanalPedidos();
  }

  @override
  void dispose() {
    _timerReloj?.cancel();
    _tabCtrl.dispose();
    _canalPedidos?.unsubscribe();
    super.dispose();
  }

  // -----------------------------------------------------------------------
  // CARGA DE DATOS
  // -----------------------------------------------------------------------
  Future<void> _cargarDatos() async {
    setState(() => _cargando = true);
    try {
      final user = await _db
          .from('usuarios')
          .select('domicilios_activo')
          .eq('id', widget.localId)
          .maybeSingle();
      final prods = await _db
          .from('productos')
          .select()
          .eq('local_id', widget.localId)
          .order('categoria')
          .order('orden');
      final peds = await _db
          .from('pedidos')
          .select('*, comprobante_url, items_pedido(nombre_snapshot, cantidad, precio_snapshot)')
          .eq('local_id', widget.localId)
          .neq('estado', 'entregado')
          .neq('estado', 'cancelado')
          .order('created_at', ascending: false);

      if (!mounted) return;
      setState(() {
        _domiciliosActivo = user?['domicilios_activo'] ?? false;
        _productos = List<Map<String, dynamic>>.from(prods);
        _pedidos = List<Map<String, dynamic>>.from(peds);
        _actualizarCategorias();
        _cargando = false;
      });
    } catch (e) {
      if (mounted) setState(() => _cargando = false);
    }
  }

  void _actualizarCategorias() {
    final cats =
        _productos.map((p) => p['categoria'].toString()).toSet().toList();
    cats.sort();
    _categorias = cats;
  }

  void _iniciarCanalPedidos() {
    _canalPedidos = _db
        .channel('pedidos_local_${widget.localId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'pedidos',
          callback: (payload) {
            final rec = payload.newRecord;
            if (rec.isEmpty) return;
            if ((rec['local_id'] as num?)?.toInt() != widget.localId) return;
            _cargarDatos();
          },
        )
        .subscribe();
  }

  // -----------------------------------------------------------------------
  // TOGGLE DOMICILIOS
  // -----------------------------------------------------------------------
  Future<void> _toggleDomicilios(bool val) async {
    try {
      await _db
          .from('usuarios')
          .update({'domicilios_activo': val}).eq('id', widget.localId);
      setState(() => _domiciliosActivo = val);
      _sonidos.reproducirSuave(Sonidos.localEstado);
    } catch (e) {
      _snack('Error al cambiar estado: $e', error: true);
    }
  }

  // -----------------------------------------------------------------------
  // PRODUCTOS — CRUD
  // -----------------------------------------------------------------------
  Future<String?> _subirFoto(XFile img) async {
    final bytes = await img.readAsBytes();
    final path =
        'local_${widget.localId}/${DateTime.now().millisecondsSinceEpoch}.jpg';
    await _db.storage.from('productos').uploadBinary(path, bytes,
        fileOptions:
            const FileOptions(contentType: 'image/jpeg', upsert: true));
    return _db.storage.from('productos').getPublicUrl(path);
  }

  void _mostrarFormProducto({Map<String, dynamic>? producto}) {
    final esEdicion = producto != null;
    final nombreCtrl =
        TextEditingController(text: producto?['nombre'] ?? '');
    final descCtrl =
        TextEditingController(text: producto?['descripcion'] ?? '');
    final precioCtrl = TextEditingController(
        text: producto != null ? producto['precio'].toString() : '');
    String categoria = producto?['categoria'] ??
        (_categorias.isNotEmpty ? _categorias.first : 'General');
    String? nuevaCatCtrl;
    bool disponible = producto?['disponible'] ?? true;
    String? fotoUrl = producto?['foto_url'];
    XFile? fotoLocal;
    Uint8List? fotoBytesLocal;
    bool subiendo = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0D0D0D),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          Future<void> pickImage(ImageSource source) async {
            final picker = ImagePicker();
            final img =
                await picker.pickImage(source: source, imageQuality: 70);
            if (img != null) {
              final bytes = await img.readAsBytes();
              setLocal(() { fotoLocal = img; fotoBytesLocal = bytes; });
            }
          }

          return Padding(
            padding:
                EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ---- FOTO (full-width) ----
                  Stack(
                    children: [
                      Container(
                        width: double.infinity,
                        height: 200,
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(24)),
                          image: fotoLocal != null && fotoBytesLocal != null
                              ? DecorationImage(
                                  image: MemoryImage(fotoBytesLocal!),
                                  fit: BoxFit.contain)
                              : fotoUrl != null
                                  ? DecorationImage(
                                      image: NetworkImage(fotoUrl),
                                      fit: BoxFit.contain)
                                  : null,
                        ),
                        child: (fotoLocal == null && fotoUrl == null)
                            ? Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.add_photo_alternate_outlined,
                                      color: Colors.grey[400], size: 52),
                                  const SizedBox(height: 8),
                                  Text('Toca para agregar foto del producto',
                                      style: TextStyle(
                                          color: Colors.grey[500],
                                          fontSize: 13)),
                                ],
                              )
                            : null,
                      ),
                      // Botones cámara / galería
                      Positioned(
                        bottom: 10,
                        right: 12,
                        child: Row(
                          children: [
                            _fotoBtn(Icons.camera_alt_outlined, 'Cámara',
                                () => pickImage(ImageSource.camera)),
                            const SizedBox(width: 8),
                            _fotoBtn(Icons.photo_library_outlined, 'Galería',
                                () => pickImage(ImageSource.gallery)),
                          ],
                        ),
                      ),
                    ],
                  ),

                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          esEdicion ? 'Editar producto' : 'Nuevo producto',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 20, color: Colors.white),
                        ),
                        const SizedBox(height: 20),

                        // ---- NOMBRE ----
                        _campoTexto(
                          controller: nombreCtrl,
                          label: 'Nombre del producto *',
                          icon: Icons.fastfood_outlined,
                          capitalization: TextCapitalization.sentences,
                        ),
                        const SizedBox(height: 14),

                        // ---- PRECIO ----
                        _campoTexto(
                          controller: precioCtrl,
                          label: 'Precio *',
                          icon: Icons.attach_money,
                          keyboardType: TextInputType.number,
                          prefixText: '\$ ',
                        ),
                        const SizedBox(height: 14),

                        // ---- CATEGORÍA ----
                        DropdownButtonFormField<String>(
                          value: (_categorias.contains(categoria)
                              ? categoria
                              : null),
                          dropdownColor: const Color(0xFF1E1E1E),
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: 'Categoría',
                            labelStyle: const TextStyle(color: Colors.white54),
                            prefixIcon: const Icon(Icons.category_outlined, color: Colors.white54),
                            filled: true,
                            fillColor: Colors.white.withValues(alpha: 0.08),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: Colors.white30)),
                            enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: Colors.white30)),
                            focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                    color: Color(0xff3AF500), width: 1.5)),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 16),
                          ),
                          items: [
                            ..._categorias.map((c) =>
                                DropdownMenuItem(value: c, child: Text(c))),
                            const DropdownMenuItem(
                                value: '__nueva__',
                                child: Text('+ Nueva categoría',
                                    style:
                                        TextStyle(color: Colors.greenAccent))),
                          ],
                          onChanged: (v) {
                            if (v == '__nueva__') {
                              setLocal(() => categoria = '__nueva__');
                            } else if (v != null) {
                              setLocal(() => categoria = v);
                            }
                          },
                        ),
                        if (categoria == '__nueva__') ...[
                          const SizedBox(height: 10),
                          _campoTexto(
                            label: 'Nombre de la nueva categoría',
                            icon: Icons.new_label_outlined,
                            capitalization: TextCapitalization.sentences,
                            onChanged: (v) => nuevaCatCtrl = v,
                          ),
                        ],
                        const SizedBox(height: 14),

                        // ---- DESCRIPCIÓN ----
                        _campoTexto(
                          controller: descCtrl,
                          label: 'Descripción (opcional)',
                          icon: Icons.notes_outlined,
                          maxLines: 2,
                          capitalization: TextCapitalization.sentences,
                        ),
                        const SizedBox(height: 14),

                        // ---- DISPONIBLE ----
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          decoration: BoxDecoration(
                            color: disponible
                                ? const Color(0xff3AF500)
                                    .withValues(alpha: 0.08)
                                : Colors.grey[50],
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: disponible
                                    ? const Color(0xff3AF500)
                                        .withValues(alpha: 0.4)
                                    : Colors.grey[300]!),
                          ),
                          child: SwitchListTile(
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 0),
                            title: Text(
                                disponible ? 'Disponible' : 'Agotado',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600, color: Colors.white)),
                            subtitle: Text(
                                disponible
                                    ? 'Visible para los clientes'
                                    : 'No aparece en el menú',
                                style: const TextStyle(fontSize: 12, color: Colors.white54)),
                            value: disponible,
                            activeColor: const Color(0xff3AF500),
                            onChanged: (v) =>
                                setLocal(() => disponible = v),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // ---- GUARDAR ----
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.black,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                              elevation: 0,
                            ),
                            onPressed: subiendo
                                ? null
                                : () async {
                                    final nombre =
                                        nombreCtrl.text.trim();
                                    final precio = int.tryParse(
                                            precioCtrl.text.trim()) ??
                                        -1;
                                    final catFinal =
                                        categoria == '__nueva__'
                                            ? (nuevaCatCtrl?.trim() ??
                                                'General')
                                            : categoria;
                                    if (nombre.isEmpty || precio < 0) {
                                      _snack(
                                          'Nombre y precio son obligatorios',
                                          error: true);
                                      return;
                                    }
                                    setLocal(() => subiendo = true);
                                    try {
                                      String? urlFinal = fotoUrl;
                                      if (fotoLocal != null) {
                                        urlFinal =
                                            await _subirFoto(fotoLocal!);
                                      }
                                      final data = {
                                        'local_id': widget.localId,
                                        'nombre': nombre,
                                        'descripcion':
                                            descCtrl.text.trim(),
                                        'precio': precio,
                                        'categoria': catFinal,
                                        'disponible': disponible,
                                        'foto_url': urlFinal,
                                      };
                                      if (esEdicion) {
                                        await _db
                                            .from('productos')
                                            .update(data)
                                            .eq('id', producto['id']);
                                      } else {
                                        await _db
                                            .from('productos')
                                            .insert(data);
                                      }
                                      _sonidos.reproducirSuave(Sonidos.localAccion);
                                      if (ctx.mounted) {
                                        Navigator.pop(ctx);
                                      }
                                      await _cargarDatos();
                                    } catch (e) {
                                      _snack('Error: $e', error: true);
                                    } finally {
                                      setLocal(() => subiendo = false);
                                    }
                                  },
                            child: subiendo
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                        color: Color(0xff3AF500),
                                        strokeWidth: 2.5))
                                : Text(
                                    esEdicion
                                        ? 'GUARDAR CAMBIOS'
                                        : 'AGREGAR PRODUCTO',
                                    style: const TextStyle(
                                        color: Color(0xff3AF500),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _eliminarProducto(Map<String, dynamic> p) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Eliminar producto?'),
        content: Text('Se eliminará "${p['nombre']}" de tu carta.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('CANCELAR')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('ELIMINAR',
                  style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _db.from('productos').delete().eq('id', p['id']);
      await _cargarDatos();
    } catch (e) {
      _snack('Error: $e', error: true);
    }
  }

  Future<void> _toggleDisponible(Map<String, dynamic> p) async {
    try {
      await _db
          .from('productos')
          .update({'disponible': !(p['disponible'] as bool)}).eq(
              'id', p['id']);
      _sonidos.reproducirSuave(Sonidos.localAccion);
      await _cargarDatos();
    } catch (e) {
      _snack('Error: $e', error: true);
    }
  }

  // -----------------------------------------------------------------------
  // PEDIDOS — CAMBIO DE ESTADO
  // -----------------------------------------------------------------------
  String _siguienteEstado(String actual) {
    const flujo = {
      'pendiente_confirmacion': 'confirmado',
      'confirmado': 'en_preparacion',
      'en_preparacion': 'listo_para_recoger',
      'listo_para_recoger': 'listo_para_recoger',
    };
    return flujo[actual] ?? actual;
  }

  String _labelEstado(String estado) {
    const labels = {
      'pendiente_confirmacion': 'Confirmar pedido',
      'confirmado': 'Iniciar preparación',
      'en_preparacion': 'Marcar listo',
      'listo_para_recoger': 'Esperando móvil',
      'en_camino': 'En camino',
      'entregado': 'Entregado',
      'cancelado': 'Cancelado',
    };
    return labels[estado] ?? estado;
  }

  Color _colorEstado(String estado) {
    const colors = {
      'pendiente_confirmacion': Colors.orange,
      'confirmado': Colors.blue,
      'en_preparacion': Colors.purple,
      'listo_para_recoger': Colors.teal,
      'en_camino': Colors.indigo,
      'entregado': Colors.green,
      'cancelado': Colors.red,
    };
    return colors[estado] ?? Colors.grey;
  }

  IconData _iconoAccion(String estado) {
    const icons = {
      'pendiente_confirmacion': Icons.check_circle_outline,
      'confirmado': Icons.restaurant,
      'en_preparacion': Icons.done_all,
    };
    return icons[estado] ?? Icons.arrow_forward;
  }

  Future<void> _avanzarEstado(Map<String, dynamic> pedido) async {
    final siguiente = _siguienteEstado(pedido['estado']);
    if (siguiente == pedido['estado']) return;
    try {
      await _db
          .from('pedidos')
          .update({'estado': siguiente}).eq('id', pedido['id']);
      _sonidos.reproducir(Sonidos.localRespuesta);
      await _cargarDatos();
      final clienteId = pedido['cliente_id']?.toString() ?? '';
      if (clienteId.isNotEmpty) {
        const msgs = {
          'confirmado': (
            '✅ Pedido confirmado',
            'Tu pedido fue confirmado por el local. ¡Ya lo están preparando!'
          ),
          'en_preparacion': (
            '👨‍🍳 Preparando tu pedido',
            'El local ya está preparando tu pedido.'
          ),
          'listo_para_recoger': (
            '📦 Listo para recoger',
            'Tu pedido está listo. El móvil lo recoge pronto.'
          ),
          'en_camino': (
            '🛵 ¡En camino!',
            'Tu pedido está en camino. Pronto llega a tu puerta.'
          ),
          'entregado': (
            '✅ Pedido entregado',
            '¡Tu pedido fue entregado! Esperamos que lo disfrutes.'
          ),
        };
        final info = msgs[siguiente];
        if (info != null) {
          MotorNotificaciones.dispararMisil(
            idDestino: clienteId,
            titulo: info.$1,
            mensaje: info.$2,
            urgente:
                siguiente == 'entregado' || siguiente == 'en_camino',
            sonido: 'alerta',
          );
        }
      }
    } catch (e) {
      _snack('Error: $e', error: true);
    }
  }

  Future<void> _cancelarPedido(Map<String, dynamic> pedido) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Cancelar pedido?'),
        content:
            const Text('El cliente será notificado de la cancelación.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('NO')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('CANCELAR PEDIDO',
                  style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _db
          .from('pedidos')
          .update({'estado': 'cancelado'}).eq('id', pedido['id']);
      _sonidos.reproducirSuave(Sonidos.localAccion);
      await _cargarDatos();
      final clienteId = pedido['cliente_id']?.toString() ?? '';
      if (clienteId.isNotEmpty) {
        MotorNotificaciones.dispararMisil(
          idDestino: clienteId,
          titulo: '❌ Pedido cancelado',
          mensaje:
              'Tu pedido fue cancelado por el local. Disculpa los inconvenientes.',
          urgente: false,
          sonido: 'alerta',
        );
      }
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
      backgroundColor: error ? Colors.red : Colors.black,
    ));
  }

  String _formatPrecio(int precio) {
    final s = precio.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return '\$ ${buf.toString()}';
  }

  String _tiempoElapsado(String? createdAt) {
    if (createdAt == null) return '';
    try {
      final t = DateTime.parse(createdAt).toLocal();
      final diff = DateTime.now().difference(t);
      if (diff.inMinutes < 1) return 'Hace un momento';
      if (diff.inMinutes < 60) return 'Hace ${diff.inMinutes} min';
      return 'Hace ${diff.inHours}h ${diff.inMinutes.remainder(60)}min';
    } catch (_) {
      return '';
    }
  }

  // -----------------------------------------------------------------------
  // WIDGETS REUTILIZABLES
  // -----------------------------------------------------------------------
  Widget _fotoBtn(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 15),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    color: Colors.white, fontSize: 11)),
          ],
        ),
      ),
    );
  }

  Widget _campoTexto({
    TextEditingController? controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    int maxLines = 1,
    TextCapitalization capitalization = TextCapitalization.none,
    String? prefixText,
    void Function(String)? onChanged,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      textCapitalization: capitalization,
      onChanged: onChanged,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white54),
        prefixIcon: Icon(icon, color: Colors.white54),
        prefixText: prefixText,
        prefixStyle: const TextStyle(color: Colors.white),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.08),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.white30)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.white30)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide:
                const BorderSide(color: Color(0xff3AF500), width: 1.5)),
      ),
    );
  }

  // -----------------------------------------------------------------------
  // BUILD
  // -----------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final pendientes = _pedidos
        .where((p) => p['estado'] == 'pendiente_confirmacion')
        .length;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.localNombre,
            style: const TextStyle(
                fontWeight: FontWeight.bold, fontSize: 16)),
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: const Color(0xff3AF500),
          labelColor: const Color(0xff3AF500),
          unselectedLabelColor: Colors.white60,
          tabs: [
            const Tab(text: 'MI CARTA'),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('PEDIDOS'),
                  if (pendientes > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$pendientes',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabCtrl,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildTabCarta(),
                _buildTabPedidos(),
              ],
            ),
      floatingActionButton: _tabCtrl.index == 0
          ? FloatingActionButton.extended(
              backgroundColor: Colors.black,
              icon: const Icon(Icons.add, color: Color(0xff3AF500)),
              label: const Text('Agregar',
                  style: TextStyle(
                      color: Color(0xff3AF500),
                      fontWeight: FontWeight.bold)),
              onPressed: () => _mostrarFormProducto(),
            )
          : null,
    );
  }

  // -----------------------------------------------------------------------
  // TAB 1 — MI CARTA
  // -----------------------------------------------------------------------
  Widget _buildTabCarta() {
    final porCategoria = <String, List<Map<String, dynamic>>>{};
    for (final p in _productos) {
      final cat = p['categoria'].toString();
      porCategoria.putIfAbsent(cat, () => []).add(p);
    }
    final cats = porCategoria.keys.toList()..sort();

    return Column(
      children: [
        _buildDomiciliosToggle(),
        Expanded(
          child: _productos.isEmpty
              ? _buildEmptyCarta()
              : CustomScrollView(
                  slivers: [
                    for (final cat in cats) ...[
                      SliverToBoxAdapter(
                        child: _buildCategoriaHeader(
                            cat, porCategoria[cat]!.length),
                      ),
                      SliverPadding(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 12),
                        sliver: SliverGrid(
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: 10,
                            crossAxisSpacing: 10,
                            childAspectRatio: 0.68,
                          ),
                          delegate: SliverChildBuilderDelegate(
                            (ctx, i) => _buildProductoCard(
                                porCategoria[cat]![i]),
                            childCount: porCategoria[cat]!.length,
                          ),
                        ),
                      ),
                      const SliverToBoxAdapter(
                          child: SizedBox(height: 8)),
                    ],
                    const SliverToBoxAdapter(
                        child: SizedBox(height: 100)),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildDomiciliosToggle() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: _domiciliosActivo
              ? [
                  const Color(0xff3AF500).withValues(alpha: 0.15),
                  const Color(0xff3AF500).withValues(alpha: 0.05),
                ]
              : [Colors.grey[200]!, Colors.grey[100]!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _domiciliosActivo
              ? const Color(0xff3AF500).withValues(alpha: 0.5)
              : Colors.grey[300]!,
        ),
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: _domiciliosActivo
                ? const Color(0xff3AF500)
                : Colors.grey[400],
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.delivery_dining,
              color: _domiciliosActivo ? Colors.black : Colors.white,
              size: 24),
        ),
        title: Text(
          _domiciliosActivo
              ? '¡Domicilios activos!'
              : 'Domicilios inactivos',
          style: const TextStyle(
              fontWeight: FontWeight.bold, fontSize: 14),
        ),
        subtitle: Text(
          _domiciliosActivo
              ? 'Tu carta está visible para los clientes'
              : 'Los clientes no pueden ver tu carta',
          style: TextStyle(fontSize: 11, color: Colors.grey[600]),
        ),
        trailing: Switch(
          value: _domiciliosActivo,
          activeColor: const Color(0xff3AF500),
          onChanged: _toggleDomicilios,
        ),
      ),
    );
  }

  Widget _buildCategoriaHeader(String cat, int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              cat.toUpperCase(),
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                letterSpacing: 1.4,
                color: Colors.black87,
              ),
            ),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.black12,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text('$count',
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.black54)),
          ),
        ],
      ),
    );
  }

  Widget _buildProductoCard(Map<String, dynamic> p) {
    final disponible = p['disponible'] as bool;
    return GestureDetector(
      onTap: () => _mostrarFormProducto(producto: p),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Foto
                Expanded(
                  flex: 4,
                  child: SizedBox(
                    width: double.infinity,
                    child: p['foto_url'] != null
                        ? Image.network(
                            p['foto_url'],
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                _fotoPlaceholderGrid(),
                          )
                        : _fotoPlaceholderGrid(),
                  ),
                ),
                // Info
                Expanded(
                  flex: 4,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p['nombre'],
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: disponible
                                ? Colors.black
                                : Colors.grey,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        GestureDetector(
                          onTap: () => _toggleDisponible(p),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: disponible
                                  ? Colors.green[50]
                                  : Colors.orange[50],
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                  color: disponible
                                      ? Colors.green[300]!
                                      : Colors.orange[300]!),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: disponible
                                        ? Colors.green
                                        : Colors.orange,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  disponible ? 'Activo' : 'Agotado',
                                  style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                      color: disponible
                                          ? Colors.green[700]
                                          : Colors.orange[700]),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const Spacer(),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _formatPrecio(p['precio'] as int),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: Color(0xff1fa800),
                                ),
                              ),
                            ),
                            _buildMenuProducto(p),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            // Badge agotado
            if (!disponible)
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.orange,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('AGOTADO',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold)),
                ),
              ),
            // Overlay semitransparente si agotado
            if (!disponible)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuProducto(Map<String, dynamic> p) {
    final disponible = p['disponible'] as bool;
    return PopupMenuButton<String>(
      iconSize: 20,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      icon: const Icon(Icons.more_vert, size: 18, color: Colors.black38),
      onSelected: (val) {
        if (val == 'editar') _mostrarFormProducto(producto: p);
        if (val == 'toggle') _toggleDisponible(p);
        if (val == 'eliminar') _eliminarProducto(p);
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'editar',
          child: Row(children: [
            const Icon(Icons.edit_outlined, size: 18, color: Colors.blue),
            const SizedBox(width: 10),
            const Text('Editar'),
          ]),
        ),
        PopupMenuItem(
          value: 'toggle',
          child: Row(children: [
            Icon(
                disponible
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                size: 18,
                color: Colors.orange),
            const SizedBox(width: 10),
            Text(disponible ? 'Marcar agotado' : 'Marcar disponible'),
          ]),
        ),
        PopupMenuItem(
          value: 'eliminar',
          child: Row(children: [
            const Icon(Icons.delete_outline, size: 18, color: Colors.red),
            const SizedBox(width: 10),
            const Text('Eliminar',
                style: TextStyle(color: Colors.red)),
          ]),
        ),
      ],
    );
  }

  Widget _fotoPlaceholderGrid() {
    return Container(
      color: Colors.grey[100],
      child: Center(
        child:
            Icon(Icons.fastfood, color: Colors.grey[300], size: 44),
      ),
    );
  }

  Widget _buildEmptyCarta() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: Colors.grey[100],
              shape: BoxShape.circle,
            ),
            child:
                Icon(Icons.restaurant_menu, size: 50, color: Colors.grey[300]),
          ),
          const SizedBox(height: 20),
          Text('Tu carta está vacía',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: Colors.grey[700])),
          const SizedBox(height: 8),
          Text('Agrega tus platos para que los\nclientes puedan hacer pedidos',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey[500])),
          const SizedBox(height: 28),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(
                  horizontal: 28, vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.add, color: Color(0xff3AF500)),
            label: const Text('AGREGAR PRIMER PRODUCTO',
                style: TextStyle(
                    color: Color(0xff3AF500),
                    fontWeight: FontWeight.bold)),
            onPressed: () => _mostrarFormProducto(),
          ),
        ],
      ),
    );
  }

  // -----------------------------------------------------------------------
  // TAB 2 — PEDIDOS ENTRANTES
  // -----------------------------------------------------------------------
  Widget _buildTabPedidos() {
    if (_pedidos.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                  color: Colors.grey[100], shape: BoxShape.circle),
              child: Icon(Icons.receipt_long,
                  size: 50, color: Colors.grey[300]),
            ),
            const SizedBox(height: 20),
            Text('Sin pedidos activos',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: Colors.grey[700])),
            const SizedBox(height: 8),
            Text(
                'Los pedidos de tus clientes\naparecerán aquí en tiempo real',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.grey[500])),
          ],
        ),
      );
    }

    final sorted = [..._pedidos];
    const prioridad = [
      'pendiente_confirmacion',
      'confirmado',
      'en_preparacion',
      'listo_para_recoger',
      'en_camino',
    ];
    sorted.sort((a, b) {
      final pa = prioridad.indexOf(a['estado'].toString());
      final pb = prioridad.indexOf(b['estado'].toString());
      if (pa != pb) return pa.compareTo(pb);
      return a['created_at']
          .toString()
          .compareTo(b['created_at'].toString());
    });

    return RefreshIndicator(
      onRefresh: _cargarDatos,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
        itemCount: sorted.length,
        itemBuilder: (_, i) => _buildPedidoCard(sorted[i]),
      ),
    );
  }

  Widget _buildPedidoCard(Map<String, dynamic> p) {
    final estado = p['estado'].toString();
    final items = p['items_pedido'] as List? ?? [];
    final colorEst = _colorEstado(estado);
    final puedeAvanzar = [
      'pendiente_confirmacion',
      'confirmado',
      'en_preparacion'
    ].contains(estado);
    final puedeCancelar =
        ['pendiente_confirmacion', 'confirmado'].contains(estado);
    final esPendiente = estado == 'pendiente_confirmacion';
    final total = (p['total'] as num?)?.toInt() ?? 0;
    final elapsed = _tiempoElapsado(p['created_at']?.toString());

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border(left: BorderSide(color: colorEst, width: 5)),
        boxShadow: [
          BoxShadow(
            color: esPendiente
                ? colorEst.withValues(alpha: 0.18)
                : Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                      color: colorEst,
                      borderRadius: BorderRadius.circular(20)),
                  child: Text(
                    _labelEstado(estado).toUpperCase(),
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5),
                  ),
                ),
                const Spacer(),
                if (elapsed.isNotEmpty)
                  Text(elapsed,
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey[500])),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 2, 14, 10),
            child: Text(
              '#${p['id'].toString().substring(0, 8).toUpperCase()}',
              style: TextStyle(
                  fontSize: 10,
                  color: Colors.grey[400],
                  fontFamily: 'monospace'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 0),
            child: Column(
              children: [
                ...items.map((item) => Padding(
                      padding: const EdgeInsets.only(bottom: 5),
                      child: Row(
                        children: [
                          Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              color: Colors.black,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Center(
                              child: Text(
                                '${item['cantidad']}',
                                style: const TextStyle(
                                    color: Color(0xff3AF500),
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                              child: Text(
                                  item['nombre_snapshot'] ?? '',
                                  style: const TextStyle(fontSize: 13))),
                          Text(
                            _formatPrecio(
                                (item['precio_snapshot'] as num).toInt() *
                                    (item['cantidad'] as num).toInt()),
                            style: const TextStyle(
                                fontSize: 12, color: Colors.black54),
                          ),
                        ],
                      ),
                    )),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Divider(height: 1),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.location_on_outlined,
                      size: 14, color: Colors.grey[500]),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      p['direccion_entrega'] ?? '',
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey[700]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ]),
                const SizedBox(height: 4),
                Row(children: [
                  Icon(
                    p['metodo_pago'] == 'efectivo'
                        ? Icons.payments_outlined
                        : Icons.receipt_long_rounded,
                    size: 14,
                    color: p['metodo_pago'] == 'efectivo'
                        ? Colors.grey[500]
                        : Colors.purple[500],
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${p['metodo_pago'] == 'efectivo' ? 'Efectivo' : 'Transferencia'} — ${_formatPrecio(total)}',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: p['metodo_pago'] == 'transferencia'
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: p['metodo_pago'] == 'efectivo'
                            ? Colors.grey[700]
                            : Colors.purple[700]),
                  ),
                ]),
                if ((p['comprobante_url'] ?? '').toString().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () => showDialog(
                      context: context,
                      builder: (_) => Dialog(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ClipRRect(
                              borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(12)),
                              child: Image.network(
                                p['comprobante_url'],
                                fit: BoxFit.contain,
                                errorBuilder: (_, __, ___) =>
                                    const Padding(
                                        padding: EdgeInsets.all(16),
                                        child: Text('No se pudo cargar')),
                              ),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Cerrar'),
                            ),
                          ],
                        ),
                      ),
                    ),
                    child: Container(
                      height: 90,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.purple[200]!),
                        color: Colors.purple[50],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(7),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.network(
                              p['comprobante_url'],
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  const Center(child: Icon(Icons.broken_image)),
                            ),
                            Positioned(
                              bottom: 0, left: 0, right: 0,
                              child: Container(
                                color: Colors.purple.withValues(alpha: 0.7),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 3),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.zoom_in,
                                        size: 13, color: Colors.white),
                                    const SizedBox(width: 4),
                                    Text('Ver comprobante',
                                        style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
                if ((p['notas'] ?? '').toString().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.sticky_note_2_outlined,
                          size: 14, color: Colors.grey[500]),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          p['notas'],
                          style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                              fontStyle: FontStyle.italic),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (puedeAvanzar || estado == 'listo_para_recoger')
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Row(
                children: [
                  if (puedeAvanzar)
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colorEst,
                          foregroundColor: Colors.white,
                          padding:
                              const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                          elevation: 0,
                        ),
                        icon: Icon(_iconoAccion(estado), size: 18),
                        label: Text(
                          _labelEstado(estado),
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13),
                        ),
                        onPressed: () => _avanzarEstado(p),
                      ),
                    ),
                  if (puedeAvanzar && puedeCancelar)
                    const SizedBox(width: 8),
                  if (puedeCancelar)
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                        padding: const EdgeInsets.symmetric(
                            vertical: 13, horizontal: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () => _cancelarPedido(p),
                      child: const Icon(Icons.close, size: 20),
                    ),
                  if (estado == 'listo_para_recoger')
                    Expanded(
                      child: Container(
                        padding:
                            const EdgeInsets.symmetric(vertical: 13),
                        decoration: BoxDecoration(
                          color: Colors.teal.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: Colors.teal.shade200),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.motorcycle,
                                size: 18, color: Colors.teal),
                            SizedBox(width: 8),
                            Text('Esperando al móvil',
                                style: TextStyle(
                                    color: Colors.teal,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13)),
                          ],
                        ),
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
