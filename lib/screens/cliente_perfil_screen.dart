import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
      ctrl.addListener(() => setState(() => _cambios = true));
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
      final updated = await _db
          .from('usuarios')
          .update({
            'nombre': nombre,
            'telefono': telefono,
            'cedula': cedula.isEmpty ? null : cedula,
            'direcciones_guardadas': _direcciones,
          })
          .eq('id', widget.usuario['id'])
          .select()
          .single();

      // Actualizar sesión local
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
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Nueva dirección',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        content: TextField(
          controller: _nuevaDirCtrl,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            hintText: 'Ej: Calle 5 # 12-34, Barrio Los Pinos',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.black),
            onPressed: () =>
                Navigator.pop(ctx, _nuevaDirCtrl.text.trim()),
            child: const Text('Agregar',
                style: TextStyle(color: Color(0xff3AF500))),
          ),
        ],
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
        ? _nombreCtrl.text.trim().split(' ').map((p) => p[0]).take(2).join()
        : '?';

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Mi Perfil',
            style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (_cambios)
            TextButton(
              onPressed: _guardando ? null : _guardar,
              child: _guardando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Color(0xff3AF500)))
                  : const Text('GUARDAR',
                      style: TextStyle(
                          color: Color(0xff3AF500),
                          fontWeight: FontWeight.bold)),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Avatar ─────────────────────────────────────────────
          Center(
            child: CircleAvatar(
              radius: 42,
              backgroundColor: Colors.black,
              child: Text(
                iniciales.toUpperCase(),
                style: const TextStyle(
                    color: Color(0xff3AF500),
                    fontSize: 28,
                    fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text(
              widget.usuario['usuario']?.toString() ?? '',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ),
          const SizedBox(height: 20),

          // ── Datos editables ────────────────────────────────────
          _seccion('DATOS PERSONALES'),
          const SizedBox(height: 8),
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
          const SizedBox(height: 20),

          // ── Datos solo lectura ─────────────────────────────────
          _seccion('CUENTA'),
          const SizedBox(height: 8),
          _campoReadonly(
              label: 'Correo electrónico',
              valor: _correo,
              icon: Icons.email_outlined),
          const SizedBox(height: 10),
          _campoReadonly(
              label: 'Fecha de nacimiento',
              valor: _fechaNac,
              icon: Icons.cake_outlined),
          const SizedBox(height: 20),

          // ── Direcciones guardadas ──────────────────────────────
          Row(
            children: [
              Expanded(child: _seccion('DIRECCIONES GUARDADAS')),
              TextButton.icon(
                onPressed:
                    _direcciones.length >= 5 ? null : _agregarDireccion,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Agregar',
                    style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(
                    foregroundColor: Colors.black,
                    padding: EdgeInsets.zero),
              ),
            ],
          ),
          if (_direcciones.isEmpty)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border:
                      Border.all(color: Colors.grey.shade200)),
              child: Text('Sin direcciones guardadas',
                  style: TextStyle(
                      color: Colors.grey[500], fontSize: 13)),
            )
          else
            ...List.generate(_direcciones.length, (i) {
              final dir = _direcciones[i];
              final esPredeterminada = i == 0;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: esPredeterminada
                          ? const Color(0xff3AF500).withValues(alpha: 0.5)
                          : Colors.grey.shade200),
                ),
                child: ListTile(
                  dense: true,
                  leading: Icon(
                    esPredeterminada
                        ? Icons.home
                        : Icons.location_on_outlined,
                    color: esPredeterminada
                        ? const Color(0xff2aaa00)
                        : Colors.grey[500],
                    size: 20,
                  ),
                  title: Text(dir,
                      style: const TextStyle(fontSize: 13)),
                  subtitle: esPredeterminada
                      ? const Text('Predeterminada',
                          style: TextStyle(
                              fontSize: 10,
                              color: Color(0xff2aaa00),
                              fontWeight: FontWeight.w600))
                      : null,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!esPredeterminada)
                        IconButton(
                          icon: const Icon(Icons.arrow_upward,
                              size: 18),
                          tooltip: 'Hacer predeterminada',
                          onPressed: () => _subirDireccion(i),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      const SizedBox(width: 4),
                      IconButton(
                        icon: Icon(Icons.delete_outline,
                            size: 18, color: Colors.red[300]),
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
          const SizedBox(height: 8),
          Text(
            'La primera dirección se pre-llena automáticamente al pedir un domicilio.',
            style: TextStyle(fontSize: 11, color: Colors.grey[500]),
          ),
          const SizedBox(height: 30),

          // ── Botón guardar principal ────────────────────────────
          if (_cambios)
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10))),
                onPressed: _guardando ? null : _guardar,
                child: _guardando
                    ? const CircularProgressIndicator(
                        color: Color(0xff3AF500), strokeWidth: 2)
                    : const Text('GUARDAR CAMBIOS',
                        style: TextStyle(
                            color: Color(0xff3AF500),
                            fontWeight: FontWeight.bold,
                            fontSize: 15)),
              ),
            ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _seccion(String titulo) => Text(
        titulo,
        style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
            color: Colors.black54),
      );

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
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.grey.shade300)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.grey.shade300)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Colors.black, width: 1.5)),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      ),
    );
  }

  Widget _campoReadonly({
    required String label,
    required String valor,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey[500]),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 11, color: Colors.grey[500])),
                const SizedBox(height: 2),
                Text(valor,
                    style: const TextStyle(
                        fontSize: 14, color: Colors.black54)),
              ],
            ),
          ),
          Icon(Icons.lock_outline, size: 14, color: Colors.grey[400]),
        ],
      ),
    );
  }
}
