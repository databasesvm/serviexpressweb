import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:dio/dio.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Panel FN – tres pestañas:
//   • Sedes     → CRUD de fn_sedes (FN numeradas, FARMACIA, DEPOSITO)
//   • Motos FN  → Motos disponibles, toggle tiene_fn, contador ignorados del día
//   • Historial → Servicios tipo_fn=true, ordenados por fecha desc
// ─────────────────────────────────────────────────────────────────────────────

class FnPanelScreen extends StatefulWidget {
  const FnPanelScreen({super.key});

  @override
  State<FnPanelScreen> createState() => _FnPanelScreenState();
}

class _FnPanelScreenState extends State<FnPanelScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Farmanorte FN',
          style: TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        bottom: TabBar(
          controller: _tab,
          indicatorColor: Colors.indigo[300],
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white38,
          tabs: const [
            Tab(icon: Icon(Icons.local_pharmacy_outlined), text: 'Sedes'),
            Tab(icon: Icon(Icons.two_wheeler), text: 'Motos FN'),
            Tab(icon: Icon(Icons.history_rounded), text: 'Historial'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: const [
          _SedesTab(),
          _MotosTab(),
          _HistorialTab(),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PESTAÑA: SEDES
// ═══════════════════════════════════════════════════════════════════════════════

class _SedesTab extends StatefulWidget {
  const _SedesTab();

  @override
  State<_SedesTab> createState() => _SedesTabState();
}

class _SedesTabState extends State<_SedesTab> {
  final _db = Supabase.instance.client;
  List<Map<String, dynamic>> _sedes = [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final data = await _db
          .from('fn_sedes')
          .select();
      final lista = List<Map<String, dynamic>>.from(data);
      lista.sort((a, b) {
        final na = int.tryParse(a['numero']?.toString() ?? '') ?? 999999;
        final nb = int.tryParse(b['numero']?.toString() ?? '') ?? 999999;
        final cmp = na.compareTo(nb);
        if (cmp != 0) return cmp;
        return (a['nombre'] ?? '').toString().compareTo((b['nombre'] ?? '').toString());
      });
      setState(() => _sedes = lista);
    } catch (e) {
      _snack('Error cargando sedes: $e');
    } finally {
      setState(() => _cargando = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _toggleActivo(Map<String, dynamic> sede) async {
    final nuevo = !(sede['activo'] as bool);
    try {
      await _db
          .from('fn_sedes')
          .update({'activo': nuevo})
          .eq('id', sede['id']);
      setState(() {
        final i = _sedes.indexOf(sede);
        if (i >= 0) _sedes[i] = {...sede, 'activo': nuevo};
      });
    } catch (e) {
      _snack('Error actualizando sede: $e');
    }
  }

  Future<void> _eliminar(Map<String, dynamic> sede) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar sede'),
        content: Text('¿Eliminar ${sede['nombre']}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Eliminar',
                  style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _db.from('fn_sedes').delete().eq('id', sede['id']);
      setState(() => _sedes.remove(sede));
    } catch (e) {
      _snack('Error eliminando: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) {
      return const Center(child: CircularProgressIndicator(color: Colors.indigo));
    }

    return Stack(
      children: [
        _sedes.isEmpty
            ? const Center(
                child: Text('Sin sedes registradas',
                    style: TextStyle(color: Colors.white38)))
            : ListView.builder(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                itemCount: _sedes.length,
                itemBuilder: (_, i) => _SedeCard(
                  sede: _sedes[i],
                  onToggle: () => _toggleActivo(_sedes[i]),
                  onEdit: () async {
                    await showDialog(
                      context: context,
                      builder: (_) => _SedeDialog(sede: _sedes[i]),
                    );
                    _cargar();
                  },
                  onDelete: () => _eliminar(_sedes[i]),
                ),
              ),

        // FAB
        Positioned(
          bottom: 20,
          right: 20,
          child: FloatingActionButton.extended(
            backgroundColor: Colors.indigo[700],
            icon: const Icon(Icons.add, color: Colors.white),
            label: const Text('Nueva sede',
                style: TextStyle(color: Colors.white)),
            onPressed: () async {
              await showDialog(
                context: context,
                builder: (_) => const _SedeDialog(sede: null),
              );
              _cargar();
            },
          ),
        ),
      ],
    );
  }
}

// ─── Tarjeta de sede ──────────────────────────────────────────────────────────

class _SedeCard extends StatelessWidget {
  final Map<String, dynamic> sede;
  final VoidCallback onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _SedeCard({
    required this.sede,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });

  Color _colorTipo(String tipo) {
    switch (tipo) {
      case 'FN':
        return Colors.indigo[700]!;
      case 'FARMACIA':
        return Colors.teal[600]!;
      case 'DEPOSITO':
        return Colors.brown[600]!;
      default:
        return Colors.grey;
    }
  }

  IconData _iconoTipo(String tipo) {
    switch (tipo) {
      case 'FN':
        return Icons.local_pharmacy;
      case 'FARMACIA':
        return Icons.medication_outlined;
      case 'DEPOSITO':
        return Icons.warehouse_outlined;
      default:
        return Icons.store;
    }
  }

  String _labelZona(String zona) {
    switch (zona) {
      case 'CUCUTA':
        return 'Cúcuta';
      case 'LOS_PATIOS':
        return 'Los Patios';
      case 'V_ROSARIO':
        return 'Villa del Rosario';
      default:
        return zona;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tipo = sede['tipo'] as String;
    final numero = sede['numero'] as String?;
    final nombre = sede['nombre'] as String;
    final zona = sede['zona'] as String;
    final activo = sede['activo'] as bool;
    final lat = sede['lat'];
    final lng = sede['lng'];

    final tieneCoords = lat != null && lng != null;
    final colorT = _colorTipo(tipo);

    return Card(
      color: const Color(0xFF1A1A1A),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            // Icono tipo
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: colorT.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(_iconoTipo(tipo), color: colorT, size: 22),
            ),
            const SizedBox(width: 12),

            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: colorT,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        tipo == 'FN' && numero != null
                            ? 'FN #$numero'
                            : tipo,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2A2A2A),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _labelZona(zona),
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 10),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 4),
                  Text(
                    nombre,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600),
                  ),
                  if (tieneCoords)
                    Text(
                      '${(lat as double).toStringAsFixed(5)}, ${(lng as double).toStringAsFixed(5)}',
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 11),
                    ),
                ],
              ),
            ),

            // Controles
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Switch(
                  value: activo,
                  activeColor: Colors.green[400],
                  onChanged: (_) => onToggle(),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onTap: onEdit,
                      child: const Icon(Icons.edit_outlined,
                          color: Colors.white38, size: 20),
                    ),
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTap: onDelete,
                      child: const Icon(Icons.delete_outline,
                          color: Colors.red, size: 20),
                    ),
                  ],
                )
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Diálogo agregar/editar sede ─────────────────────────────────────────────

class _SedeDialog extends StatefulWidget {
  final Map<String, dynamic>? sede; // null = nueva

  const _SedeDialog({this.sede});

  @override
  State<_SedeDialog> createState() => _SedeDialogState();
}

class _SedeDialogState extends State<_SedeDialog> {
  final _db = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();

  String _tipo = 'FN';
  String _zona = 'CUCUTA';
  bool _activo = true;

  final _ctrlNumero = TextEditingController();
  final _ctrlNombre = TextEditingController();
  final _ctrlMapsUrl = TextEditingController();
  final _ctrlLat = TextEditingController();
  final _ctrlLng = TextEditingController();

  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    final s = widget.sede;
    if (s != null) {
      _tipo = s['tipo'] as String;
      _zona = s['zona'] as String;
      _activo = s['activo'] as bool;
      _ctrlNumero.text = s['numero'] ?? '';
      _ctrlNombre.text = s['nombre'] ?? '';
      if (s['lat'] != null) _ctrlLat.text = s['lat'].toString();
      if (s['lng'] != null) _ctrlLng.text = s['lng'].toString();
    }
  }

  @override
  void dispose() {
    _ctrlNumero.dispose();
    _ctrlNombre.dispose();
    _ctrlMapsUrl.dispose();
    _ctrlLat.dispose();
    _ctrlLng.dispose();
    super.dispose();
  }

  /// Extrae lat/lng de URL de Google Maps.
  /// Soporta URLs completas y URLs cortas (maps.app.goo.gl / goo.gl)
  /// siguiendo el redirect con una petición HTTP.
  Future<void> _extraerCoordenadas() async {
    final raw = _ctrlMapsUrl.text.trim();
    if (raw.isEmpty) return;

    setState(() => _guardando = true); // reutilizo el flag para deshabilitar el botón

    String urlFinal = raw;

    // URLs cortas: goo.gl o maps.app.goo.gl
    if (raw.contains('goo.gl')) {
      if (kIsWeb) {
        // El navegador bloquea redirects cross-origin (CORS).
        // En producción (Android) esto no ocurre.
        setState(() => _guardando = false);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'En Web: abre el enlace en el navegador, '
              'copia la URL completa de la barra de direcciones y pégala aquí.',
            ),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 6),
          ),
        );
        return;
      }
      // Android/iOS: Dio sigue el redirect sin restricción CORS
      try {
        final dio = Dio(BaseOptions(
          headers: {'User-Agent': 'Mozilla/5.0'},
          followRedirects: true,
          maxRedirects: 6,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
        ));
        final resp = await dio.get<void>(
          raw,
          options: Options(validateStatus: (_) => true),
        );
        urlFinal = resp.realUri.toString();
      } catch (_) {
        urlFinal = raw;
      }
    }

    setState(() => _guardando = false);

    // Patrones de coordenadas en la URL expandida
    final patterns = [
      RegExp(r'/@(-?\d+\.\d+),(-?\d+\.\d+)'),
      RegExp(r'[?&]q=(-?\d+\.\d+),(-?\d+\.\d+)'),
      RegExp(r'[?&]ll=(-?\d+\.\d+),(-?\d+\.\d+)'),
      RegExp(r'maps\?q=(-?\d+\.\d+),(-?\d+\.\d+)'),
      RegExp(r'!3d(-?\d+\.\d+)!4d(-?\d+\.\d+)'),  // formato Places
      RegExp(r'(-?\d{1,3}\.\d{4,}),(-?\d{1,3}\.\d{4,})'),
    ];

    for (final p in patterns) {
      final m = p.firstMatch(urlFinal);
      if (m != null) {
        if (!mounted) return;
        setState(() {
          _ctrlLat.text = m.group(1)!;
          _ctrlLng.text = m.group(2)!;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Coords: ${m.group(1)}, ${m.group(2)}'),
            backgroundColor: Colors.green[700],
            duration: const Duration(seconds: 2),
          ),
        );
        return;
      }
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('No se pudo extraer coords. Pega el enlace de "Compartir" de Google Maps.'),
        backgroundColor: Colors.orange,
      ),
    );
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _guardando = true);

    final payload = <String, dynamic>{
      'tipo': _tipo,
      'zona': _zona,
      'nombre': _ctrlNombre.text.trim(),
      'activo': _activo,
      'numero': _tipo == 'FN' && _ctrlNumero.text.trim().isNotEmpty
          ? _ctrlNumero.text.trim()
          : null,
      'lat': _ctrlLat.text.isNotEmpty
          ? double.tryParse(_ctrlLat.text.trim())
          : null,
      'lng': _ctrlLng.text.isNotEmpty
          ? double.tryParse(_ctrlLng.text.trim())
          : null,
    };

    try {
      if (widget.sede == null) {
        await _db.from('fn_sedes').insert(payload);
      } else {
        await _db
            .from('fn_sedes')
            .update(payload)
            .eq('id', widget.sede!['id']);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'),
              backgroundColor: Colors.red[700]),
        );
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final esNueva = widget.sede == null;

    return AlertDialog(
      backgroundColor: const Color(0xFF1A1A1A),
      title: Text(
        esNueva ? 'Nueva sede' : 'Editar sede',
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Tipo
                _label('Tipo'),
                DropdownButtonFormField<String>(
                  value: _tipo,
                  dropdownColor: const Color(0xFF2A2A2A),
                  style: const TextStyle(color: Colors.white),
                  decoration: _inputDeco('Tipo de sede'),
                  items: const [
                    DropdownMenuItem(value: 'FN', child: Text('FN (Farmanorte)')),
                    DropdownMenuItem(
                        value: 'FARMACIA', child: Text('Farmacia externa')),
                    DropdownMenuItem(
                        value: 'DEPOSITO', child: Text('Depósito')),
                  ],
                  onChanged: (v) => setState(() => _tipo = v!),
                ),
                const SizedBox(height: 12),

                // Número (solo FN)
                if (_tipo == 'FN') ...[
                  _label('Número de sede FN'),
                  TextFormField(
                    controller: _ctrlNumero,
                    style: const TextStyle(color: Colors.white),
                    decoration: _inputDeco('Ej: 1, 2, 3...'),
                    keyboardType: TextInputType.number,
                    validator: (v) =>
                        _tipo == 'FN' && (v == null || v.trim().isEmpty)
                            ? 'Ingresa el número'
                            : null,
                  ),
                  const SizedBox(height: 12),
                ],

                // Nombre
                _label('Nombre / descripción'),
                TextFormField(
                  controller: _ctrlNombre,
                  style: const TextStyle(color: Colors.white),
                  decoration: _inputDeco('Ej: Farmanorte El Centro, Farmazur...'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Ingresa el nombre' : null,
                ),
                const SizedBox(height: 12),

                // Zona
                _label('Zona'),
                DropdownButtonFormField<String>(
                  value: _zona,
                  dropdownColor: const Color(0xFF2A2A2A),
                  style: const TextStyle(color: Colors.white),
                  decoration: _inputDeco('Zona'),
                  items: const [
                    DropdownMenuItem(value: 'CUCUTA', child: Text('Cúcuta')),
                    DropdownMenuItem(
                        value: 'LOS_PATIOS', child: Text('Los Patios')),
                    DropdownMenuItem(
                        value: 'V_ROSARIO', child: Text('Villa del Rosario')),
                  ],
                  onChanged: (v) => setState(() => _zona = v!),
                ),
                const SizedBox(height: 14),

                // Coords desde Google Maps URL
                _label('Coordenadas (pega enlace de Google Maps)'),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _ctrlMapsUrl,
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                        decoration:
                            _inputDeco('https://maps.google.com/...').copyWith(
                          hintStyle:
                              const TextStyle(color: Colors.white24, fontSize: 11),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _extraerCoordenadas,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigo[700],
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 14),
                      ),
                      child: const Icon(Icons.my_location,
                          color: Colors.white, size: 18),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Lat / Lng manuales
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _ctrlLat,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: _inputDeco('Latitud'),
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true, signed: true),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        controller: _ctrlLng,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: _inputDeco('Longitud'),
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true, signed: true),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Activo
                Row(
                  children: [
                    const Text('Activa',
                        style: TextStyle(color: Colors.white70)),
                    const Spacer(),
                    Switch(
                      value: _activo,
                      activeColor: Colors.green[400],
                      onChanged: (v) => setState(() => _activo = v),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar', style: TextStyle(color: Colors.white38)),
        ),
        ElevatedButton(
          onPressed: _guardando ? null : _guardar,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.indigo[700],
          ),
          child: _guardando
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : Text(esNueva ? 'Crear' : 'Guardar',
                  style: const TextStyle(color: Colors.white)),
        ),
      ],
    );
  }

  Widget _label(String texto) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(texto,
            style: const TextStyle(color: Colors.white54, fontSize: 12)),
      );

  InputDecoration _inputDeco(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white24),
        filled: true,
        fillColor: const Color(0xFF2A2A2A),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
      );
}

// ═══════════════════════════════════════════════════════════════════════════════
// PESTAÑA: MOTOS FN
// ═══════════════════════════════════════════════════════════════════════════════

class _MotosTab extends StatefulWidget {
  const _MotosTab();

  @override
  State<_MotosTab> createState() => _MotosTabState();
}

class _MotosTabState extends State<_MotosTab> {
  final _db = Supabase.instance.client;
  List<Map<String, dynamic>> _motos = [];
  List<Map<String, dynamic>> _filtradas = [];
  bool _cargando = true;
  final _busqueda = TextEditingController();

  @override
  void initState() {
    super.initState();
    _cargar();
    _busqueda.addListener(_filtrar);
  }

  @override
  void dispose() {
    _busqueda.removeListener(_filtrar);
    _busqueda.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final data = await _db
          .from('usuarios')
          .select('id, usuario, nombre, telefono, tiene_fn, fn_ignorados_hoy, fn_fecha_ignorados')
          .eq('rol', 'movil')
          .order('usuario');
      setState(() {
        _motos = List<Map<String, dynamic>>.from(data);
        _filtrar();
      });
    } catch (e) {
      _snack('Error: $e');
    } finally {
      setState(() => _cargando = false);
    }
  }

  void _filtrar() {
    final q = _busqueda.text.trim().toLowerCase();
    setState(() {
      _filtradas = q.isEmpty
          ? List.from(_motos)
          : _motos
              .where((m) =>
                  (m['nombre'] as String? ?? '')
                      .toLowerCase()
                      .contains(q) ||
                  (m['telefono'] as String? ?? '').contains(q))
              .toList();
    });
  }

  Future<void> _toggleFn(Map<String, dynamic> moto) async {
    final nuevo = !(moto['tiene_fn'] as bool? ?? false);
    try {
      await _db
          .from('usuarios')
          .update({'tiene_fn': nuevo})
          .eq('id', moto['id']);
      final i = _motos.indexWhere((m) => m['id'] == moto['id']);
      if (i >= 0) {
        setState(() => _motos[i] = {..._motos[i], 'tiene_fn': nuevo});
        _filtrar();
      }
    } catch (e) {
      _snack('Error: $e');
    }
  }

  Future<void> _resetIgnorados(Map<String, dynamic> moto) async {
    try {
      await _db.from('usuarios').update({
        'fn_ignorados_hoy': 0,
        'fn_fecha_ignorados': DateTime.now().toIso8601String().substring(0, 10),
      }).eq('id', moto['id']);
      final i = _motos.indexWhere((m) => m['id'] == moto['id']);
      if (i >= 0) {
        setState(() => _motos[i] = {
              ..._motos[i],
              'fn_ignorados_hoy': 0,
            });
        _filtrar();
      }
    } catch (e) {
      _snack('Error: $e');
    }
  }

  Future<void> _resetTodos() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Resetear todos'),
        content: const Text(
            '¿Resetear el contador de ignorados de todos los motos?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Resetear',
                  style: TextStyle(color: Colors.orange))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _db.from('usuarios').update({
        'fn_ignorados_hoy': 0,
        'fn_fecha_ignorados': DateTime.now().toIso8601String().substring(0, 10),
      }).eq('rol', 'movil');
      _cargar();
    } catch (e) {
      _snack('Error: $e');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) {
      return const Center(
          child: CircularProgressIndicator(color: Colors.indigo));
    }

    final totalFn = _motos.where((m) => m['tiene_fn'] == true).length;

    return Column(
      children: [
        // Header con stats y botón reset todos
        Container(
          color: const Color(0xFF111111),
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.indigo[900],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$totalFn moto${totalFn == 1 ? '' : 's'} FN',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13),
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _resetTodos,
                icon: const Icon(Icons.refresh,
                    color: Colors.orange, size: 16),
                label: const Text('Reset todos',
                    style: TextStyle(color: Colors.orange, fontSize: 12)),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                ),
              ),
            ],
          ),
        ),

        // Buscador
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: TextField(
            controller: _busqueda,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Buscar moto...',
              hintStyle: const TextStyle(color: Colors.white24),
              prefixIcon:
                  const Icon(Icons.search, color: Colors.white38),
              filled: true,
              fillColor: const Color(0xFF1A1A1A),
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),

        // Lista
        Expanded(
          child: _filtradas.isEmpty
              ? const Center(
                  child: Text('Sin resultados',
                      style: TextStyle(color: Colors.white38)))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 20),
                  itemCount: _filtradas.length,
                  itemBuilder: (_, i) => _MotoFnCard(
                    moto: _filtradas[i],
                    onToggleFn: () => _toggleFn(_filtradas[i]),
                    onResetIgnorados: () =>
                        _resetIgnorados(_filtradas[i]),
                  ),
                ),
        ),
      ],
    );
  }
}

// ─── Tarjeta de moto FN ───────────────────────────────────────────────────────

class _MotoFnCard extends StatelessWidget {
  final Map<String, dynamic> moto;
  final VoidCallback onToggleFn;
  final VoidCallback onResetIgnorados;

  const _MotoFnCard({
    required this.moto,
    required this.onToggleFn,
    required this.onResetIgnorados,
  });

  @override
  Widget build(BuildContext context) {
    final tieneFn = moto['tiene_fn'] as bool? ?? false;
    final ignorados = moto['fn_ignorados_hoy'] as int? ?? 0;
    final nombre = moto['nombre'] as String? ?? '—';
    final telefono = moto['telefono'] as String? ?? '';
    final usuario = moto['usuario']?.toString() ?? '';
    final numStr = RegExp(r'\d+').firstMatch(usuario)?.group(0) ?? '';

    return Card(
      color: const Color(0xFF1A1A1A),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            // Avatar con número
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: tieneFn
                    ? Colors.indigo[900]!.withValues(alpha: 0.6)
                    : const Color(0xFF2A2A2A),
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: numStr.isNotEmpty
                  ? Text(
                      '#$numStr',
                      style: TextStyle(
                          color: tieneFn
                              ? Colors.white
                              : Colors.white38,
                          fontWeight: FontWeight.bold,
                          fontSize: numStr.length > 2 ? 13 : 15),
                    )
                  : Icon(Icons.two_wheeler,
                      color:
                          tieneFn ? Colors.indigo[300] : Colors.white24,
                      size: 22),
            ),
            const SizedBox(width: 12),

            // Info: nombre primario, teléfono secundario
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    nombre,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14),
                  ),
                  if (telefono.isNotEmpty)
                    Text(telefono,
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 11)),
                ],
              ),
            ),

            // Ignorados hoy
            if (ignorados > 0)
              GestureDetector(
                onTap: onResetIgnorados,
                child: Container(
                  margin: const EdgeInsets.only(right: 10),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: ignorados >= 5
                        ? Colors.red[900]
                        : Colors.orange[900],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$ignorados',
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 15),
                      ),
                      const Text(
                        'ign.',
                        style: TextStyle(
                            color: Colors.white54, fontSize: 9),
                      ),
                    ],
                  ),
                ),
              ),

            // Toggle FN
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Switch(
                  value: tieneFn,
                  activeColor: Colors.indigo[300],
                  onChanged: (_) => onToggleFn(),
                ),
                Text(
                  tieneFn ? 'FN' : 'Off',
                  style: TextStyle(
                      color: tieneFn ? Colors.indigo[300] : Colors.white24,
                      fontSize: 10,
                      fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PESTAÑA: HISTORIAL FN
// ═══════════════════════════════════════════════════════════════════════════════

class _HistorialTab extends StatefulWidget {
  const _HistorialTab();

  @override
  State<_HistorialTab> createState() => _HistorialTabState();
}

class _HistorialTabState extends State<_HistorialTab> {
  final _db = Supabase.instance.client;
  List<Map<String, dynamic>> _servicios = [];
  Map<String, String> _nombreMoviles = {};
  bool _cargando = true;
  String _filtroEstado = 'todos';

  static const _filtros = [
    ('todos', 'Todos'),
    ('pendiente', 'Pendiente'),
    ('confirmado', 'Confirmado'),
    ('completado', 'Completado'),
    ('cancelado', 'Cancelado'),
    ('cotizacion', 'Cotización'),
  ];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final data = await _db
          .from('servicios')
          .select()
          .eq('tipo_fn', true)
          .order('id', ascending: false)
          .limit(300);

      final lista = List<Map<String, dynamic>>.from(data);

      // Cargar nombres de motos en lote
      final ids = lista
          .where((s) => s['movil_id'] != null)
          .map((s) => s['movil_id'].toString())
          .toSet()
          .toList();

      if (ids.isNotEmpty) {
        final motos = await _db
            .from('usuarios')
            .select('id, nombre, usuario')
            .inFilter('id', ids);
        _nombreMoviles = Map.fromEntries(
          List<Map<String, dynamic>>.from(motos).map((m) {
            final nombre = m['nombre'] as String? ?? '—';
            final usuario = m['usuario']?.toString() ?? '';
            final numStr = RegExp(r'\d+').firstMatch(usuario)?.group(0) ?? '';
            final display = numStr.isNotEmpty ? '#$numStr · $nombre' : nombre;
            return MapEntry(m['id'].toString(), display);
          }),
        );
      }

      setState(() => _servicios = lista);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error cargando historial: $e')));
      }
    } finally {
      setState(() => _cargando = false);
    }
  }

  static const _estadosConfirmado = {
    'en_ruta_origen', 'en_origen', 'en_ruta_destino',
  };

  List<Map<String, dynamic>> get _filtrados {
    if (_filtroEstado == 'todos') return _servicios;
    if (_filtroEstado == 'confirmado') {
      return _servicios.where((s) => _estadosConfirmado.contains(s['estado'])).toList();
    }
    if (_filtroEstado == 'completado') {
      return _servicios.where((s) => s['estado'] == 'finalizado' || s['estado'] == 'finalizado_con_problema').toList();
    }
    return _servicios.where((s) => s['estado'] == _filtroEstado).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── Chips de filtro ───────────────────────────────────────────
        Container(
          color: const Color(0xFF0F0F0F),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final (val, label) in _filtros)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(label,
                          style: TextStyle(
                            fontSize: 12,
                            color: _filtroEstado == val
                                ? Colors.white
                                : Colors.white54,
                          )),
                      selected: _filtroEstado == val,
                      onSelected: (_) =>
                          setState(() => _filtroEstado = val),
                      selectedColor: Colors.indigo[800],
                      backgroundColor: const Color(0xFF2A2A2A),
                      side: BorderSide.none,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                  ),
              ],
            ),
          ),
        ),

        // ── Lista ─────────────────────────────────────────────────────
        Expanded(
          child: _cargando
              ? const Center(
                  child: CircularProgressIndicator(color: Colors.indigo))
              : _filtrados.isEmpty
                  ? const Center(
                      child: Text('Sin servicios FN registrados',
                          style: TextStyle(color: Colors.white38)))
                  : RefreshIndicator(
                      onRefresh: _cargar,
                      color: Colors.indigo,
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        itemCount: _filtrados.length,
                        itemBuilder: (ctx, i) => _CardServicioFN(
                          servicio: _filtrados[i],
                          nombreMovil: _nombreMoviles[
                              _filtrados[i]['movil_id']?.toString()],
                        ),
                      ),
                    ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Card de servicio FN
// ─────────────────────────────────────────────────────────────────────────────

class _CardServicioFN extends StatelessWidget {
  final Map<String, dynamic> servicio;
  final String? nombreMovil;

  const _CardServicioFN({required this.servicio, this.nombreMovil});

  @override
  Widget build(BuildContext context) {
    final estado = servicio['estado'] as String? ?? '';
    final origen = servicio['origen'] as String? ?? '—';
    final destino = (servicio['destino'] as String? ?? '').trim();
    final tarifa = (servicio['tarifa'] as num?)?.toInt() ?? 0;
    final id = servicio['id'];

    DateTime? fecha;
    try {
      fecha =
          DateTime.parse(servicio['created_at'] as String? ?? '').toLocal();
    } catch (_) {}

    final recogidas = servicio['recogidas'];
    final recogidasList =
        recogidas is List ? recogidas : <dynamic>[];

    final color = _colorEstado(estado);

    return Card(
      color: const Color(0xFF1A1A1A),
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: color.withValues(alpha: 0.35), width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Encabezado: ID · estado · fecha ──────────────────────
            Row(
              children: [
                Text('#$id',
                    style: const TextStyle(
                        color: Colors.white38, fontSize: 11)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: color, width: 0.6),
                  ),
                  child: Text(
                    estado.toUpperCase(),
                    style: TextStyle(
                        color: color,
                        fontSize: 10,
                        fontWeight: FontWeight.bold),
                  ),
                ),
                const Spacer(),
                if (fecha != null)
                  Text(_formatFecha(fecha),
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 11)),
              ],
            ),
            const SizedBox(height: 8),

            // ── Sede origen ───────────────────────────────────────────
            Row(
              children: [
                Icon(Icons.local_pharmacy_outlined,
                    color: Colors.indigo[300], size: 14),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(origen,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 13),
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),

            // ── Destino ───────────────────────────────────────────────
            if (destino.isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.place_outlined,
                      color: Colors.white38, size: 14),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(destino,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12),
                        overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ],

            // ── Recogidas ─────────────────────────────────────────────
            if (recogidasList.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text('Rec:',
                      style:
                          TextStyle(color: Colors.white38, fontSize: 10)),
                  for (final r in recogidasList)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color:
                            Colors.indigo[900]!.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(_labelRecogida(r),
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 10)),
                    ),
                ],
              ),
            ],

            const SizedBox(height: 8),

            // ── Footer: tarifa · moto ─────────────────────────────────
            Row(
              children: [
                if (tarifa > 0) ...[
                  const Icon(Icons.attach_money,
                      color: Colors.green, size: 15),
                  Text(
                    '\$${_miles(tarifa)}',
                    style: const TextStyle(
                        color: Colors.green,
                        fontWeight: FontWeight.bold,
                        fontSize: 13),
                  ),
                ] else
                  const Text('Cotización',
                      style:
                          TextStyle(color: Colors.orange, fontSize: 12)),
                const Spacer(),
                if (nombreMovil != null) ...[
                  const Icon(Icons.two_wheeler,
                      color: Colors.white38, size: 14),
                  const SizedBox(width: 4),
                  Text(nombreMovil!,
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 11)),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _labelRecogida(dynamic r) {
    if (r is Map) {
      final tipo = r['tipo'] as String? ?? '';
      final num = r['numero'] as String?;
      final nombre = r['nombre'] as String? ?? '';
      if (tipo == 'FN' && num != null) return 'FN$num';
      return nombre.isNotEmpty ? nombre : tipo;
    }
    return r.toString();
  }

  Color _colorEstado(String estado) => switch (estado) {
        'pendiente' => Colors.orange,
        'confirmado' => Colors.blue,
        'completado' => Colors.green,
        'cancelado' => Colors.red,
        'cotizacion' => Colors.purple,
        _ => Colors.white38,
      };

  String _formatFecha(DateTime dt) {
    final now = DateTime.now();
    final hm =
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    if (dt.year == now.year &&
        dt.month == now.month &&
        dt.day == now.day) return hm;
    return '${dt.day}/${dt.month} $hm';
  }

  String _miles(int n) {
    final s = n.toString();
    if (s.length <= 3) return s;
    final pos = s.length - 3;
    return '${s.substring(0, pos)}.${s.substring(pos)}';
  }
}
