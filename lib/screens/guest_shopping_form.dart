import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:serviexpress_app/utils/onesignal_api.dart';
import 'package:serviexpress_app/utils/alta_demanda.dart';
import 'package:serviexpress_app/utils/whatsapp_contacto.dart';
import 'package:serviexpress_app/utils/invitado_comun.dart';
import 'package:serviexpress_app/screens/guest_tracking_screen.dart';

class GuestShoppingForm extends StatefulWidget {
  const GuestShoppingForm({super.key});

  @override
  State<GuestShoppingForm> createState() => _GuestShoppingFormState();
}

class _GuestShoppingFormState extends State<GuestShoppingForm> {
  final _formKey = GlobalKey<FormState>();
  bool _procesando = false;

  final _nombreCtrl = TextEditingController();
  final _tiendaCtrl = TextEditingController();
  final _destinoCtrl = TextEditingController();
  final _listaCtrl = TextEditingController();
  final _telContactoCtrl = TextEditingController();

  double? _destinoLat;
  double? _destinoLng;
  LocalRegistrado? _local;

  String _metodoPago = 'Efectivo';

  @override
  void initState() {
    super.initState();
    _precargar();
  }

  Future<void> _precargar() async {
    try {
      final c = await cargarContactoInvitado();
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        if (_nombreCtrl.text.isEmpty) _nombreCtrl.text = c.nombre ?? '';
        if (_telContactoCtrl.text.isEmpty) _telContactoCtrl.text = c.telefono ?? '';
        final origen = prefs.getString('guest_ultima_origen');
        if (origen != null && _tiendaCtrl.text.isEmpty) _tiendaCtrl.text = origen;
        final destino = prefs.getString('guest_ultimo_destino');
        if (destino != null && _destinoCtrl.text.isEmpty) {
          _destinoCtrl.text = destino;
          _destinoLat = prefs.getDouble('guest_ultimo_destino_lat');
          _destinoLng = prefs.getDouble('guest_ultimo_destino_lng');
        }
      });
    } catch (_) {}
  }

  void _alEditarDestino(String _) {
    if (_destinoLat == null) return;
    setState(() {
      _destinoLat = null;
      _destinoLng = null;
    });
  }

  Future<void> _capturarDestinoGps() async {
    final pos = await gpsInvitado(context);
    if (pos == null || !mounted) return;
    setState(() {
      _destinoLat = pos.latitude;
      _destinoLng = pos.longitude;
    });
  }

  Future<void> _enviarPedido() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _procesando = true);

    try {
      final tel = normalizarWhatsApp(_telContactoCtrl.text);
      final destino = _destinoCtrl.text.trim().isNotEmpty
          ? _destinoCtrl.text.trim().toUpperCase()
          : 'UBICACIÓN GPS DEL CLIENTE';
      final notaFinal =
          '⚠️ SOLICITA COTIZACIÓN | [ COMPRAS ] - 🛒 LISTA:\n${_listaCtrl.text.trim()}\n---\n📞 Contacto: $tel | PAGO: $_metodoPago';

      final response = await Supabase.instance.client
          .from('servicios')
          .insert({
            'creador': 'Invitado: ${_nombreCtrl.text.trim()}',
            'tipo_servicio': 'COMPRAS',
            'origen': _tiendaCtrl.text.trim().toUpperCase(),
            if (_local?.lat != null) 'origen_lat': _local!.lat,
            if (_local?.lng != null) 'origen_lng': _local!.lng,
            'destino': destino,
            'destino_lat': _destinoLat,
            'destino_lng': _destinoLng,
            if (_destinoLat != null)
              'destino_gps_at': DateTime.now().toUtc().toIso8601String(),
            'telefono_receptor': tel,
            'tarifa': 0.0,
            'tarifa_detalle': {'total': 0.0, 'fuente': 'invitado'},
            'observacion': notaFinal,
            'estado': 'cotizacion',
          })
          .select('id')
          .single();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('ultimo_pedido_invitado', response['id']);
      prefs.setString('guest_ultima_origen', _tiendaCtrl.text.trim().toUpperCase());
      prefs.setString('guest_ultimo_destino', _destinoCtrl.text.trim().toUpperCase());
      if (_destinoLat != null) {
        prefs.setDouble('guest_ultimo_destino_lat', _destinoLat!);
        prefs.setDouble('guest_ultimo_destino_lng', _destinoLng!);
      } else {
        prefs.remove('guest_ultimo_destino_lat');
        prefs.remove('guest_ultimo_destino_lng');
      }
      await guardarContactoInvitado(_nombreCtrl.text, _telContactoCtrl.text);

      try {
        await MotorNotificaciones.dispararACentral(
          titulo: '🛒 COMPRAS INVITADO',
          mensaje: '${_nombreCtrl.text.trim()} → $destino',
          urgente: true,
        );
      } catch (e) {
        debugPrint('Error OneSignal: $e');
      }

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const GuestTrackingScreen()),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorInvitado(e)), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  Widget _construirBloque({
    required String titulo,
    required IconData icono,
    required List<Widget> hijos,
  }) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icono, color: Colors.black54, size: 20),
              const SizedBox(width: 8),
              Text(titulo,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87)),
            ]),
            const Divider(height: 24),
            ...hijos,
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _tiendaCtrl.dispose();
    _destinoCtrl.dispose();
    _listaCtrl.dispose();
    _telContactoCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('Compras y Mandados',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const BannerAltaDemanda(),
            _construirBloque(
              titulo: 'Identificación',
              icono: Icons.person,
              hijos: [
                TextFormField(
                  controller: _nombreCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Tu nombre',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  validator: validarRequerido,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _telContactoCtrl,
                  keyboardType: TextInputType.phone,
                  inputFormatters: formatoWhatsApp,
                  decoration: const InputDecoration(
                    labelText: 'Tu WhatsApp / teléfono',
                    helperText: 'Ej: 3001234567 — el conductor te escribe aquí',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  validator: validarTelefonoInvitado,
                ),
              ],
            ),
            _construirBloque(
              titulo: '¿Qué y dónde compramos?',
              icono: Icons.shopping_cart,
              hijos: [
                CampoOrigenConLocales(
                  controller: _tiendaCtrl,
                  label: 'Lugar de compra (Ej: Éxito, Farmacia X)',
                  onLocal: (l) => _local = l,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _listaCtrl,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    labelText: 'Lista de productos',
                    alignLabelWithHint: true,
                    hintText: 'Ej: 2 leches Colanta deslactosada 1L,\n1 Arroz Roa 5kg...',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'La lista no puede estar vacía' : null,
                ),
              ],
            ),
            _construirBloque(
              titulo: 'Punto de Entrega',
              icono: Icons.home,
              hijos: [
                TextFormField(
                  controller: _destinoCtrl,
                  onChanged: _alEditarDestino,
                  decoration: InputDecoration(
                    labelText: 'Dirección donde recibes',
                    helperText: _destinoLat == null
                        ? 'Toca 📍 para enviar tu ubicación exacta'
                        : null,
                    border: const OutlineInputBorder(),
                    isDense: true,
                    suffixIcon: IconButton(
                      tooltip: 'Usar mi ubicación actual',
                      icon: const Icon(Icons.my_location, color: Colors.blue),
                      onPressed: _capturarDestinoGps,
                    ),
                  ),
                  validator: (v) => _destinoLat != null ? null : validarRequerido(v),
                ),
                if (_destinoLat != null)
                  chipGpsGuardado(onQuitar: () => setState(() {
                        _destinoLat = null;
                        _destinoLng = null;
                      })),
              ],
            ),
            _construirBloque(
              titulo: 'Pago y Cotización',
              icono: Icons.payments,
              hijos: [
                DropdownButtonFormField<String>(
                  initialValue: _metodoPago,
                  decoration: const InputDecoration(
                    labelText: '¿Cómo pagarás el servicio?',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: ['Efectivo', 'Transferencia']
                      .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                      .toList(),
                  onChanged: (val) => setState(() => _metodoPago = val ?? 'Efectivo'),
                ),
                const SizedBox(height: 16),
                const AvisoCotizacionInvitado(),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 55,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xff3AF500),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _procesando ? null : _enviarPedido,
                child: _procesando
                    ? const CircularProgressIndicator(color: Colors.black)
                    : const Text('SOLICITAR COMPRA AHORA',
                        style: TextStyle(
                            color: Colors.black,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1)),
              ),
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
}
