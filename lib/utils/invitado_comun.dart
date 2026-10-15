// Piezas comunes de los formularios del INVITADO (web sin registro):
// Envío, Comida, Compras y Mototaxi.

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'whatsapp_contacto.dart';
import 'alta_demanda.dart';

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
        'el conductor te llamará.');
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
          child: Text('Ubicación GPS guardada — el conductor llega exacto',
              style: TextStyle(fontSize: 11, color: Color(0xFF2E7D32), fontWeight: FontWeight.w600)),
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

// ── Estilo visual de los formularios del invitado ───────────────────────────
// Fondo negro + tarjetas claras. Cada servicio tiene su color de acento.

const Color kFondoInvitado = Color(0xFF0D0D0D);

class EstiloServicioInvitado {
  final Color color;
  final IconData icono;
  final String titulo;
  final String subtitulo;
  final String textoBoton;
  const EstiloServicioInvitado({
    required this.color,
    required this.icono,
    required this.titulo,
    required this.subtitulo,
    required this.textoBoton,
  });

  /// Texto legible encima del color (negro sobre verde, blanco sobre azul…)
  Color get sobreColor =>
      ThemeData.estimateBrightnessForColor(color) == Brightness.dark
          ? Colors.white
          : Colors.black;

  static const mototaxi = EstiloServicioInvitado(
    color: Color(0xFF3AF500),
    icono: Icons.two_wheeler,
    titulo: 'Pedir Mototaxi',
    subtitulo: 'Te recogemos donde estés',
    textoBoton: 'PEDIR MOTOTAXI',
  );
  static const paqueteria = EstiloServicioInvitado(
    color: Color(0xFF2F80ED),
    icono: Icons.inventory_2,
    titulo: 'Enviar un paquete',
    subtitulo: 'Lo recogemos y lo entregamos',
    textoBoton: 'SOLICITAR ENVÍO',
  );
  static const comida = EstiloServicioInvitado(
    color: Color(0xFFFF8A00),
    icono: Icons.restaurant,
    titulo: 'Pedir comida',
    subtitulo: 'Te la traemos a la puerta',
    textoBoton: 'PEDIR COMIDA',
  );
  static const compras = EstiloServicioInvitado(
    color: Color(0xFF9B51E0),
    icono: Icons.shopping_cart,
    titulo: 'Compras y mandados',
    subtitulo: 'Compramos por ti y te lo llevamos',
    textoBoton: 'SOLICITAR COMPRA',
  );
}

/// Pantalla común: fondo negro, encabezado del servicio, contenido centrado
/// (máx. 560 px en pantallas grandes) y botón fijo abajo. Responsive:
/// márgenes más pequeños en celulares angostos y el botón fijo se esconde
/// mientras el teclado está abierto (para no tapar los campos).
class ScaffoldInvitado extends StatelessWidget {
  final EstiloServicioInvitado estilo;
  final List<Widget> children;
  final bool procesando;
  final VoidCallback onEnviar;
  const ScaffoldInvitado({
    super.key,
    required this.estilo,
    required this.children,
    required this.procesando,
    required this.onEnviar,
  });

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final ancho = mq.size.width;
    final double margen = ancho < 380 ? 10 : 16;
    final bool teclado = mq.viewInsets.bottom > 0;
    final base = Theme.of(context);

    return Theme(
      data: base.copyWith(
        colorScheme: base.colorScheme.copyWith(primary: estilo.color),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF3F4F6),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: estilo.color, width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.red, width: 1.2),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.red, width: 2),
          ),
          labelStyle: const TextStyle(color: Colors.black54, fontSize: 14),
          floatingLabelStyle: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w600),
          helperStyle: const TextStyle(color: Colors.black45, fontSize: 11),
          helperMaxLines: 2,
          errorMaxLines: 2,
        ),
        textSelectionTheme: TextSelectionThemeData(cursorColor: estilo.color),
      ),
      child: Scaffold(
        backgroundColor: kFondoInvitado,
        appBar: AppBar(
          backgroundColor: kFondoInvitado,
          elevation: 0,
          scrolledUnderElevation: 0,
          iconTheme: const IconThemeData(color: Colors.white),
          title: const Text('ServiExpress',
              style: TextStyle(color: Colors.white70, fontSize: 15, fontWeight: FontWeight.w600)),
        ),
        body: SafeArea(
          bottom: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: ListView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.fromLTRB(margen, 4, margen, 24),
                children: [
                  _EncabezadoServicio(estilo: estilo, compacto: ancho < 380),
                  const SizedBox(height: 16),
                  const BannerAltaDemanda(margin: EdgeInsets.only(bottom: 12)),
                  ...children,
                ],
              ),
            ),
          ),
        ),
        bottomNavigationBar: teclado
            ? null
            : SafeArea(
                child: Center(
                  heightFactor: 1,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(margen, 8, margen, 12),
                      child: SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: estilo.color,
                            foregroundColor: estilo.sobreColor,
                            disabledBackgroundColor: estilo.color.withValues(alpha: 0.5),
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          onPressed: procesando ? null : onEnviar,
                          icon: procesando
                              ? SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2.5, color: estilo.sobreColor),
                                )
                              : const Icon(Icons.send_rounded, size: 20),
                          label: Text(
                            procesando ? 'ENVIANDO…' : estilo.textoBoton,
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 1),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

class _EncabezadoServicio extends StatelessWidget {
  final EstiloServicioInvitado estilo;
  final bool compacto;
  const _EncabezadoServicio({required this.estilo, required this.compacto});

  @override
  Widget build(BuildContext context) {
    final double lado = compacto ? 52 : 60;
    return Row(children: [
      Container(
        width: lado,
        height: lado,
        decoration: BoxDecoration(
          color: estilo.color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: estilo.color.withValues(alpha: 0.6)),
        ),
        child: Icon(estilo.icono, color: estilo.color, size: lado * 0.5),
      ),
      const SizedBox(width: 14),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(estilo.titulo,
              style: TextStyle(
                  color: Colors.white,
                  fontSize: compacto ? 21 : 24,
                  fontWeight: FontWeight.w800,
                  height: 1.1)),
          const SizedBox(height: 4),
          Text(estilo.subtitulo,
              style: const TextStyle(color: Colors.white60, fontSize: 13)),
        ]),
      ),
    ]);
  }
}

/// Tarjeta clara con número de paso, ícono y línea de color del servicio.
class BloqueInvitado extends StatelessWidget {
  final int paso;
  final String titulo;
  final IconData icono;
  final Color color;
  final List<Widget> hijos;
  const BloqueInvitado({
    super.key,
    required this.paso,
    required this.titulo,
    required this.icono,
    required this.color,
    required this.hijos,
  });

  @override
  Widget build(BuildContext context) {
    final bool angosto = MediaQuery.of(context).size.width < 380;
    final sobre = ThemeData.estimateBrightnessForColor(color) == Brightness.dark
        ? Colors.white
        : Colors.black;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
              color: color.withValues(alpha: 0.18), blurRadius: 18, offset: const Offset(0, 6)),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(angosto ? 14 : 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                child: Text('$paso',
                    style: TextStyle(color: sobre, fontWeight: FontWeight.w800, fontSize: 14)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(titulo,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 16, color: Colors.black87)),
              ),
              Icon(icono, color: color, size: 22),
            ]),
            Container(
              height: 3,
              width: 40,
              margin: const EdgeInsets.only(top: 10, bottom: 16, left: 38),
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
            ),
            ...hijos,
          ],
        ),
      ),
    );
  }
}

/// Aviso corto: la Central envía el precio antes de despachar.
class AvisoCotizacionInvitado extends StatelessWidget {
  const AvisoCotizacionInvitado({super.key});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF7E6),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(children: [
          Text('💬', style: TextStyle(fontSize: 18)),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'La Central te envía el precio antes de despachar al conductor.',
              style: TextStyle(fontSize: 12.5, color: Colors.black87, height: 1.3),
            ),
          ),
        ]),
      );
}

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
          borderRadius: BorderRadius.circular(8),
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
