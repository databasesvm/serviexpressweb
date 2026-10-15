import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:serviexpress_app/utils/sesion_segura.dart';
import 'package:serviexpress_app/utils/tema_serviexpress.dart';

class ClientePerfilScreen extends StatefulWidget {
  final Map<String, dynamic> usuario;
  const ClientePerfilScreen({super.key, required this.usuario});

  @override
  State<ClientePerfilScreen> createState() => _ClientePerfilScreenState();
}

class _ClientePerfilScreenState extends State<ClientePerfilScreen> {
  final _db = Supabase.instance.client;

  late final TextEditingController _nombreCtrl;
  late final TextEditingController _telefonoCtrl;
  late final TextEditingController _cedulaCtrl;
  final _nuevaDirCtrl = TextEditingController();

  late List<String> _direcciones;
  bool _guardando = false;
  bool _cambios = false;

  // Datos solo lectura
  String get _correo => widget.usuario['correo']?.toString() ?? '—';
  String get _fechaNac {
    final raw = widget.usuario['fecha_nacimiento']?.toString();
    if (raw == null || raw.isEmpty) return '—';
    try {
      final dt = DateTime.parse(raw);
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
    } catch (_) {
      return raw;
    }
  }

  @override
  void initState() {
    super.initState();
    _nombreCtrl = TextEditingController(
        text: widget.usuario['nombre']?.toString() ?? '');
    _telefonoCtrl = TextEditingController(
        text: widget.usuario['telefono']?.toString() ?? '');
    _cedulaCtrl = TextEditingController(
        text: widget.usuario['cedula']?.toString() ?? '');

    final raw = widget.usuario['direcciones_guardadas'];
    if (raw is List) {
      _direcciones = raw.map((d) => d.toString()).toList();
    } else if (raw is String && raw.isNotEmpty && raw != '[]') {
      try {
        _direcciones =
            (jsonDecode(raw) as List).map((d) => d.toString()).toList();
      } catch (_) {
        _direcciones = [];
      }
    } else {
      _direcciones = [];
    }

    for (final ctrl in [_nombreCtrl, _telefonoCtrl, _cedulaCtrl]) {
      ctrl.addListener(() {
        if (_cargandoCedula) return;
        setState(() => _cambios = true);
      });
    }
    _cargarCedula();
  }

  // La cédula es dato privado: no viaja en la sesión, se pide al servidor.
  bool _cargandoCedula = false;
  Future<void> _cargarCedula() async {
    try {
      final r = await _db.rpc('fn_leer_mi_cedula',
          params: {'p_usuario_id': widget.usuario['id']});
      if (!mounted || r == null) return;
      _cargandoCedula = true;
      _cedulaCtrl.text = r.toString();
      _cargandoCedula = false;
    } catch (_) {
      _cargandoCedula = false;
    }
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _telefonoCtrl.dispose();
    _cedulaCtrl.dispose();
    _nuevaDirCtrl.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    final nombre = _nombreCtrl.text.trim().toUpperCase();
    final telefono = _telefonoCtrl.text.trim();
    final cedula = _cedulaCtrl.text.trim();

    if (nombre.isEmpty) {
      _snack('El nombre no puede estar vacío', Colors.red);
      return;
    }
    if (telefono.isEmpty) {
      _snack('El teléfono no puede estar vacío', Colors.red);
      return;
    }

    setState(() => _guardando = true);
    try {
      final updatedRaw = await _db
          .from('usuarios')
          .update({
            'nombre': nombre,
            'telefono': telefono,
            'direcciones_guardadas': _direcciones,
          })
          .eq('id', widget.usuario['id'])
          .select()
          .single();
      final updated = sinDatosSensibles(updatedRaw);

      // Cédula: se guarda en el servidor (tabla protegida)
      await _db.rpc('fn_guardar_mi_cedula', params: {
        'p_usuario_id': widget.usuario['id'],
        'p_cedula': cedula,
      });

      // Actualizar sesión local (sin datos sensibles)
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('sesion_usuario_json', jsonEncode(updated));

      setState(() {
        _cambios = false;
        _nombreCtrl.text = updated['nombre'] ?? nombre;
      });

      _snack('Perfil actualizado', Colors.green);
      if (mounted) Navigator.pop(context, updated);
    } catch (e) {
      _snack('Error al guardar: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: color));
  }

  Future<void> _agregarDireccion() async {
    _nuevaDirCtrl.clear();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => Theme(
        data: temaFormularioSE(ctx, kVerdeSE),
        child: AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(kRadioTarjetaSE)),
          title: const Text('Nueva dirección',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          content: TextField(
            controller: _nuevaDirCtrl,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'Ej: Calle 5 # 12-34, Barrio Los Pinos',
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar', style: TextStyle(color: Colors.black54))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: kVerdeSE,
                  foregroundColor: Colors.black,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              onPressed: () =>
                  Navigator.pop(ctx, _nuevaDirCtrl.text.trim()),
              child: const Text('Agregar', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
    if (result == null || result.isEmpty) return;
    if (_direcciones.contains(result)) {
      _snack('Esa dirección ya está guardada', Colors.orange);
      return;
    }
    setState(() {
      _direcciones = [result, ..._direcciones].take(5).toList();
      _cambios = true;
    });
  }

  void _eliminarDireccion(int idx) {
    setState(() {
      _direcciones.removeAt(idx);
      _cambios = true;
    });
  }

  void _subirDireccion(int idx) {
    if (idx == 0) return;
    setState(() {
      final tmp = _direcciones[idx];
      _direcciones[idx] = _direcciones[idx - 1];
      _direcciones[idx - 1] = tmp;
      _cambios = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final iniciales = _nombreCtrl.text.isNotEmpty
        ? _nombreCtrl.text.trim().split(' ').where((p) => p.isNotEmpty).map((p) => p[0]).take(2).join()
        : '?';
    final margen = margenSE(context);
    final teclado = MediaQuery.of(context).viewInsets.bottom > 0;

    return Theme(
      data: temaFormularioSE(context, kVerdeSE),
      child: Scaffold(
        backgroundColor: kFondoSE,
        appBar: AppBar(
          backgroundColor: kFondoSE,
          elevation: 0,
          scrolledUnderElevation: 0,
          iconTheme: const IconThemeData(color: Colors.white),
          title: const Text('Mi perfil',
              style: TextStyle(color: Colors.white70, fontSize: 15, fontWeight: FontWeight.w600)),
        ),
        body: SafeArea(
          bottom: false,
          child: ContenidoSE(
            child: ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(margen, 4, margen, 24),
              children: [
                // ── Encabezado con avatar ────────────────────────────
                Row(children: [
                  Container(
                    width: 64,
                    height: 64,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: kVerdeSE.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                      border: Border.all(color: kVerdeSE.withValues(alpha: 0.6)),
                    ),
                    child: Text(
                      iniciales.toUpperCase(),
                      style: const TextStyle(
                          color: kVerdeSE, fontSize: 24, fontWeight: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(
                        _nombreCtrl.text.isNotEmpty ? _nombreCtrl.text : 'Mi perfil',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800, height: 1.1),
                      ),
                      const SizedBox(height: 4),
                      Text('@${widget.usuario['usuario']?.toString() ?? ''}',
                          style: const TextStyle(color: Colors.white60, fontSize: 13)),
                    ]),
                  ),
                ]),
                const SizedBox(height: 18),

                // ── Datos editables ──────────────────────────────────
                BloqueSE(
                  titulo: 'Datos personales',
                  icono: Icons.person_outline,
                  color: kVerdeSE,
                  hijos: [
                    _campo(
                      controller: _nombreCtrl,
                      label: 'Nombre completo',
                      icon: Icons.person_outline,
                      caps: TextCapitalization.characters,
                    ),
                    const SizedBox(height: 10),
                    _campo(
                      controller: _telefonoCtrl,
                      label: 'Teléfono',
                      icon: Icons.phone_outlined,
                      tipo: TextInputType.phone,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    ),
                    const SizedBox(height: 10),
                    _campo(
                      controller: _cedulaCtrl,
                      label: 'Cédula / Documento',
                      icon: Icons.badge_outlined,
                      tipo: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      hint: 'Opcional — para facturación y seguridad',
                    ),
                  ],
                ),

                // ── Datos solo lectura ───────────────────────────────
                BloqueSE(
                  titulo: 'Cuenta',
                  icono: Icons.lock_outline,
                  color: kVerdeSE,
                  hijos: [
                    _campoReadonly(
                        label: 'Correo electrónico',
                        valor: _correo,
                        icon: Icons.email_outlined),
                    const SizedBox(height: 10),
                    _campoReadonly(
                        label: 'Fecha de nacimiento',
                        valor: _fechaNac,
                        icon: Icons.cake_outlined),
                  ],
                ),

                // ── Direcciones guardadas ────────────────────────────
                BloqueSE(
                  titulo: 'Direcciones guardadas',
                  icono: Icons.home_outlined,
                  color: kVerdeSE,
                  hijos: [
                    if (_direcciones.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                            color: kCampoSE,
                            borderRadius: BorderRadius.circular(kRadioCampoSE)),
                        child: const Text('Sin direcciones guardadas',
                            style: TextStyle(color: Colors.black45, fontSize: 13)),
                      )
                    else
                      ...List.generate(_direcciones.length, (i) {
                        final dir = _direcciones[i];
                        final esPredeterminada = i == 0;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: esPredeterminada
                                ? kVerdeSE.withValues(alpha: 0.10)
                                : kCampoSE,
                            borderRadius: BorderRadius.circular(kRadioCampoSE),
                            border: esPredeterminada
                                ? Border.all(color: kVerdeSE.withValues(alpha: 0.5))
                                : null,
                          ),
                          child: ListTile(
                            dense: true,
                            leading: Icon(
                              esPredeterminada ? Icons.home : Icons.location_on_outlined,
                              color: esPredeterminada ? kVerdeOscuroSE : Colors.grey[500],
                              size: 20,
                            ),
                            title: Text(dir, style: const TextStyle(fontSize: 13)),
                            subtitle: esPredeterminada
                                ? const Text('Predeterminada',
                                    style: TextStyle(
                                        fontSize: 10,
                                        color: kVerdeOscuroSE,
                                        fontWeight: FontWeight.w600))
                                : null,
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (!esPredeterminada)
                                  IconButton(
                                    icon: const Icon(Icons.arrow_upward, size: 18),
                                    tooltip: 'Hacer predeterminada',
                                    onPressed: () => _subirDireccion(i),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                  ),
                                const SizedBox(width: 4),
                                IconButton(
                                  icon: Icon(Icons.delete_outline, size: 18, color: Colors.red[300]),
                                  tooltip: 'Eliminar',
                                  onPressed: () => _eliminarDireccion(i),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                    const SizedBox(height: 4),
                    Row(children: [
                      const Expanded(
                        child: Text(
                          'La primera se pre-llena al pedir un domicilio.',
                          style: TextStyle(fontSize: 11, color: Colors.black45),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _direcciones.length >= 5 ? null : _agregarDireccion,
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Agregar', style: TextStyle(fontSize: 12)),
                        style: TextButton.styleFrom(foregroundColor: kVerdeOscuroSE),
                      ),
                    ]),
                  ],
                ),
              ],
            ),
          ),
        ),
        // ── Botón guardar fijo abajo (solo si hay cambios) ───────────
        bottomNavigationBar: (!_cambios || teclado)
            ? null
            : SafeArea(
                child: ContenidoSE(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(margen, 8, margen, 12),
                    child: BotonPrincipalSE(
                      texto: 'GUARDAR CAMBIOS',
                      icono: Icons.check_rounded,
                      textoCargando: 'GUARDANDO…',
                      cargando: _guardando,
                      onPressed: _guardar,
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _campo({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType tipo = TextInputType.text,
    TextCapitalization caps = TextCapitalization.none,
    List<TextInputFormatter>? inputFormatters,
    String? hint,
  }) {
    return TextField(
      controller: controller,
      keyboardType: tipo,
      textCapitalization: caps,
      inputFormatters: inputFormatters,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, size: 20),
      ),
    );
  }

  Widget _campoReadonly({
    required String label,
    required String valor,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: kCampoSE,
        borderRadius: BorderRadius.circular(kRadioCampoSE),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey[500]),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                const SizedBox(height: 2),
                Text(valor, style: const TextStyle(fontSize: 14, color: Colors.black54)),
              ],
            ),
          ),
          Icon(Icons.lock_outline, size: 14, color: Colors.grey[400]),
        ],
      ),
    );
  }
}
