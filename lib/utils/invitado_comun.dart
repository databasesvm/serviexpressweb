// Piezas comunes de los formularios del INVITADO (web sin registro) y del
// cliente: GPS, teléfono, recordar datos, errores y locales registrados.
// Lo VISUAL vive en tema_serviexpress.dart (diseño oficial de la app).

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'whatsapp_contacto.dart';

export 'tema_serviexpress.dart';
export 'aviso_cotizacion.dart' show prepararAvisoRespuesta, registrarPedidoInvitadoParaAviso;

// ── GPS ─────────────────────────────────────────────────────────────────────

/// Pide la ubicación del teléfono (pensado para el navegador, también
/// Safari/iPhone): alta precisión con 15 s de espera y, si no responde,
/// un segundo intento de precisión media. Muestra avisos claros.
Future<Position?> gpsInvitado(BuildContext context) async {
  void aviso(String t) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t), backgroundColor: Colors.red[700]));
    }
  }

  try {
    if (!await Geolocator.isLocationServiceEnabled()) {
      aviso('⚠️ Activa la ubicación (GPS) de tu celular.');
      return null;
    }
    var permiso = await Geolocator.checkPermission();
    if (permiso == LocationPermission.denied) {
      permiso = await Geolocator.requestPermission();
    }
    if (permiso == LocationPermission.denied ||
        permiso == LocationPermission.deniedForever) {
      aviso('⚠️ Permite el acceso a tu ubicación en el navegador '
          '(en iPhone: Ajustes › Safari › Ubicación).');
      return null;
    }
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
    } catch (_) {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 15),
        ),
      );
    }
  } catch (_) {
    aviso('No pudimos leer tu ubicación. Escribe la dirección y '
        'el Móvil te llamará.');
    return null;
  }
}

/// Chip debajo de una dirección: "✅ Ubicación GPS guardada" (con quitar).
Widget chipGpsGuardado({required VoidCallback onQuitar}) => Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(children: [
        const Icon(Icons.check_circle, size: 16, color: Color(0xFF2E7D32)),
        const SizedBox(width: 4),
        const Expanded(
          child: Text('Ubicación guardada — el Móvil llega exacto',
              style: TextStyle(fontSize: 13, color: Color(0xFF2E7D32), fontWeight: FontWeight.w600)),
        ),
        InkWell(
          onTap: onQuitar,
          child: const Padding(
            padding: EdgeInsets.all(4),
            child: Text('Quitar', style: TextStyle(fontSize: 11, color: Colors.black45)),
          ),
        ),
      ]),
    );

// ── Teléfono / WhatsApp ─────────────────────────────────────────────────────

/// Teléfono obligatorio del invitado: celular (7+ dígitos) o @usuario.
String? validarTelefonoInvitado(String? v) =>
    validarWhatsApp(v, obligatorio: true);

String? validarRequerido(String? v) =>
    (v == null || v.trim().isEmpty) ? 'Requerido' : null;

// ── Recordar nombre y teléfono ──────────────────────────────────────────────

Future<({String? nombre, String? telefono})> cargarContactoInvitado() async {
  try {
    final p = await SharedPreferences.getInstance();
    return (nombre: p.getString('guest_nombre'), telefono: p.getString('guest_telefono'));
  } catch (_) {
    return (nombre: null, telefono: null);
  }
}

Future<void> guardarContactoInvitado(String nombre, String telefono) async {
  try {
    final p = await SharedPreferences.getInstance();
    if (nombre.trim().isNotEmpty) await p.setString('guest_nombre', nombre.trim());
    if (telefono.trim().isNotEmpty) await p.setString('guest_telefono', telefono.trim());
  } catch (_) {}
}

// ── Errores entendibles ─────────────────────────────────────────────────────

String errorInvitado(Object e) {
  final t = e.toString();
  if (t.contains('demasiadas_cotizaciones')) {
    return 'Ya tienes 3 pedidos pendientes. Espera a que la Central responda '
        'o revisa "Rastrear mi pedido".';
  }
  if (t.contains('SocketException') || t.contains('Failed host lookup') ||
      t.contains('XMLHttpRequest') || t.contains('ClientException') ||
      t.contains('TimeoutException')) {
    return 'No pudimos enviar tu pedido. Revisa tu conexión a internet e intenta de nuevo.';
  }
  return 'No pudimos enviar tu pedido. Intenta de nuevo en un momento.';
}

// ── Locales registrados (autocompletar el origen) ───────────────────────────

class LocalRegistrado {
  final int id;
  final String nombre;
  final double? lat;
  final double? lng;
  const LocalRegistrado(this.id, this.nombre, this.lat, this.lng);
}

List<LocalRegistrado>? _cacheLocales;

Future<List<LocalRegistrado>> cargarLocalesRegistrados() async {
  if (_cacheLocales != null) return _cacheLocales!;
  try {
    final rows = await Supabase.instance.client
        .from('usuarios')
        .select('id, nombre, lat_fija, lng_fija')
        .eq('rol', 'local')
        .eq('activo', true)
        .not('eliminado', 'is', true)
        .order('nombre', ascending: true);
    _cacheLocales = List<Map<String, dynamic>>.from(rows)
        .where((r) => (r['nombre']?.toString() ?? '').trim().isNotEmpty)
        .map((r) => LocalRegistrado(
              (r['id'] as num).toInt(),
              r['nombre'].toString().trim(),
              (r['lat_fija'] as num?)?.toDouble(),
              (r['lng_fija'] as num?)?.toDouble(),
            ))
        .toList();
  } catch (_) {
    _cacheLocales = [];
  }
  return _cacheLocales!;
}

/// Campo de texto con sugerencias de locales registrados. Si el invitado
/// elige uno, [onLocal] recibe el local (con su ubicación); si escribe otra
/// cosa, [onLocal] recibe null.
class CampoOrigenConLocales extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final IconData? icono;
  final Widget? suffixIcon;
  final void Function(LocalRegistrado? local) onLocal;
  final String? Function(String?)? validator;
  const CampoOrigenConLocales({
    super.key,
    required this.controller,
    required this.label,
    required this.onLocal,
    this.icono,
    this.suffixIcon,
    this.validator,
  });

  @override
  State<CampoOrigenConLocales> createState() => _CampoOrigenConLocalesState();
}

class _CampoOrigenConLocalesState extends State<CampoOrigenConLocales> {
  List<LocalRegistrado> _locales = [];
  final FocusNode _foco = FocusNode();

  @override
  void initState() {
    super.initState();
    cargarLocalesRegistrados().then((l) {
      if (mounted) setState(() => _locales = l);
    });
  }

  @override
  void dispose() {
    _foco.dispose();
    super.dispose();
  }

  String _norm(String s) => s
      .toLowerCase()
      .replaceAll(RegExp('[áà]'), 'a')
      .replaceAll(RegExp('[éè]'), 'e')
      .replaceAll(RegExp('[íì]'), 'i')
      .replaceAll(RegExp('[óò]'), 'o')
      .replaceAll(RegExp('[úùü]'), 'u');

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<LocalRegistrado>(
      textEditingController: widget.controller,
      focusNode: _foco,
      displayStringForOption: (l) => l.nombre.toUpperCase(),
      optionsBuilder: (v) {
        final q = _norm(v.text.trim());
        if (q.length < 2) return const Iterable<LocalRegistrado>.empty();
        return _locales.where((l) => _norm(l.nombre).contains(q)).take(6);
      },
      onSelected: (l) => widget.onLocal(l),
      fieldViewBuilder: (ctx, ctrl, focus, onSubmit) => TextFormField(
        controller: ctrl,
        focusNode: focus,
        textCapitalization: TextCapitalization.characters,
        onChanged: (_) => widget.onLocal(null), // escribió otra cosa
        decoration: InputDecoration(
          labelText: widget.label,
          prefixIcon: widget.icono != null ? Icon(widget.icono, size: 18) : null,
          suffixIcon: widget.suffixIcon,
        ),
        validator: widget.validator ?? validarRequerido,
      ),
      optionsViewBuilder: (ctx, onSel, opciones) => Align(
        alignment: Alignment.topLeft,
        child: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 240, maxWidth: 420),
            child: ListView(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              children: opciones
                  .map((l) => ListTile(
                        dense: true,
                        leading: const Icon(Icons.storefront, size: 18),
                        title: Text(l.nombre.toUpperCase(),
                            style: const TextStyle(fontSize: 13)),
                        subtitle: l.lat != null
                            ? const Text('Local registrado · ubicación exacta',
                                style: TextStyle(fontSize: 10))
                            : null,
                        onTap: () => onSel(l),
                      ))
                  .toList(),
            ),
          ),
        ),
      ),
    );
  }
}
