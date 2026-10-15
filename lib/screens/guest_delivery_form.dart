import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:serviexpress_app/utils/onesignal_api.dart';
import 'package:serviexpress_app/utils/alta_demanda.dart';
import 'package:serviexpress_app/utils/whatsapp_contacto.dart';
import 'package:serviexpress_app/utils/invitado_comun.dart';
import 'package:serviexpress_app/screens/guest_tracking_screen.dart';

class GuestDeliveryForm extends StatefulWidget {
  const GuestDeliveryForm({super.key});

  @override
  State<GuestDeliveryForm> createState() => _GuestDeliveryFormState();
}

class _GuestDeliveryFormState extends State<GuestDeliveryForm> {
  final _formKey = GlobalKey<FormState>();
  bool _procesando = false;

  final _nombreCtrl = TextEditingController();
  final _telOrigenCtrl = TextEditingController();
  final _dirOrigenCtrl = TextEditingController();
  final _dirDestinoCtrl = TextEditingController();
  final _telDestinoCtrl = TextEditingController();

  double? _origenLat;
  double? _origenLng;
  bool _origenEsLocal = false; // la ubicación del origen viene de un local registrado
  double? _destinoLat;
  double? _destinoLng;

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
        if (_telOrigenCtrl.text.isEmpty) _telOrigenCtrl.text = c.telefono ?? '';
        final origen = prefs.getString('guest_ultima_origen');
        if (origen != null && _dirOrigenCtrl.text.isEmpty) {
          _dirOrigenCtrl.text = origen;
          _origenLat = prefs.getDouble('guest_ultima_origen_lat');
          _origenLng = prefs.getDouble('guest_ultima_origen_lng');
        }
        final destino = prefs.getString('guest_ultimo_destino');
        if (destino != null && _dirDestinoCtrl.text.isEmpty) {
          _dirDestinoCtrl.text = destino;
          _destinoLat = prefs.getDouble('guest_ultimo_destino_lat');
          _destinoLng = prefs.getDouble('guest_ultimo_destino_lng');
        }
      });
    } catch (_) {}
  }

  // Origen: local registrado elegido (con su ubicación) o texto libre (null)
  void _alElegirLocal(LocalRegistrado? l) {
    if (l == null) {
      if (_origenLat == null) return;
      setState(() {
        _origenLat = null;
        _origenLng = null;
        _origenEsLocal = false;
      });
      return;
    }
    setState(() {
      _origenLat = l.lat;
      _origenLng = l.lng;
      _origenEsLocal = l.lat != null;
    });
  }

  void _alEditarDestino(String _) {
    if (_destinoLat == null) return;
    setState(() {
      _destinoLat = null;
      _destinoLng = null;
    });
  }

  Future<void> _capturarUbicacion(bool esOrigen) async {
    final pos = await gpsInvitado(context);
    if (pos == null || !mounted) return;
    setState(() {
      if (esOrigen) {
        _origenLat = pos.latitude;
        _origenLng = pos.longitude;
        _origenEsLocal = false;
      } else {
        _destinoLat = pos.latitude;
        _destinoLng = pos.longitude;
      }
    });
  }

  String _textoODefecto(TextEditingController c) =>
      c.text.trim().isNotEmpty ? c.text.trim().toUpperCase() : 'UBICACIÓN GPS DEL CLIENTE';

  Future<void> _enviarPedido() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _procesando = true);

    try {
      final telEnvia = normalizarWhatsApp(_telOrigenCtrl.text);
      final telRecibe = normalizarWhatsApp(_telDestinoCtrl.text);
      final origen = _textoODefecto(_dirOrigenCtrl);
      final destino = _textoODefecto(_dirDestinoCtrl);
      final notaFinal =
          '⚠️ SOLICITA COTIZACIÓN | [ PAQUETERÍA ] - PAGO: $_metodoPago | 📞 Envía: $telEnvia | 📞 Recibe: $telRecibe';

      // Siempre nace como cotización. Al aprobarla el invitado
      // (guest_tracking_screen.dart) arranca la cascada SE completa.
      final response = await Supabase.instance.client
          .from('servicios')
          .insert({
            'creador': 'Invitado: ${_nombreCtrl.text.trim()}',
            'tipo_servicio': 'PAQUETERÍA',
            'origen': origen,
            'destino': destino,
            'origen_lat': _origenLat,
            'origen_lng': _origenLng,
            'destino_lat': _destinoLat,
            'destino_lng': _destinoLng,
            if (_destinoLat != null)
              'destino_gps_at': DateTime.now().toUtc().toIso8601String(),
            // Quien recibe → botón "WA Cliente" en la tarjeta del móvil
            'telefono_receptor': telRecibe,
            'tarifa': 0.0,
            'tarifa_detalle': {'total': 0.0, 'fuente': 'invitado'},
            'observacion': notaFinal,
            'estado': 'cotizacion',
          })
          .select('id')
          .single();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('ultimo_pedido_invitado', response['id']);
      prefs.setString('guest_ultima_origen', _dirOrigenCtrl.text.trim().toUpperCase());
      if (_origenLat != null) {
        prefs.setDouble('guest_ultima_origen_lat', _origenLat!);
        prefs.setDouble('guest_ultima_origen_lng', _origenLng!);
      } else {
        prefs.remove('guest_ultima_origen_lat');
        prefs.remove('guest_ultima_origen_lng');
      }
      prefs.setString('guest_ultimo_destino', _dirDestinoCtrl.text.trim().toUpperCase());
      if (_destinoLat != null) {
        prefs.setDouble('guest_ultimo_destino_lat', _destinoLat!);
        prefs.setDouble('guest_ultimo_destino_lng', _destinoLng!);
      } else {
        prefs.remove('guest_ultimo_destino_lat');
        prefs.remove('guest_ultimo_destino_lng');
      }
      await guardarContactoInvitado(_nombreCtrl.text, _telOrigenCtrl.text);

      try {
        await MotorNotificaciones.dispararACentral(
          titulo: '📦 DOMICILIO INVITADO',
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

  Widget _campoTelefono(TextEditingController c, String label) => TextFormField(
        controller: c,
        keyboardType: TextInputType.phone,
        inputFormatters: formatoWhatsApp,
        decoration: InputDecoration(
          labelText: label,
          helperText: 'Ej: 3001234567',
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        validator: validarTelefonoInvitado,
      );

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _telOrigenCtrl.dispose();
    _dirOrigenCtrl.dispose();
    _dirDestinoCtrl.dispose();
    _telDestinoCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('Solicitar Domicilio',
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
              titulo: 'Tus Datos',
              icono: Icons.person,
              hijos: [
                TextFormField(
                  controller: _nombreCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Nombre y Apellido',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  validator: validarRequerido,
                ),
              ],
            ),
            _construirBloque(
              titulo: '¿Dónde recogemos?',
              icono: Icons.storefront,
              hijos: [
                CampoOrigenConLocales(
                  controller: _dirOrigenCtrl,
                  label: 'Dirección o nombre del local',
                  onLocal: _alElegirLocal,
                  validator: (v) => _origenLat != null ? null : validarRequerido(v),
                  suffixIcon: IconButton(
                    tooltip: 'Usar mi ubicación actual',
                    icon: const Icon(Icons.my_location, color: Colors.blue),
                    onPressed: () => _capturarUbicacion(true),
                  ),
                ),
                if (_origenLat != null && !_origenEsLocal)
                  chipGpsGuardado(onQuitar: () => setState(() {
                        _origenLat = null;
                        _origenLng = null;
                      })),
                const SizedBox(height: 12),
                _campoTelefono(_telOrigenCtrl, 'WhatsApp / teléfono de quien entrega'),
              ],
            ),
            _construirBloque(
              titulo: '¿Dónde entregamos?',
              icono: Icons.flag,
              hijos: [
                TextFormField(
                  controller: _dirDestinoCtrl,
                  onChanged: _alEditarDestino,
                  decoration: InputDecoration(
                    labelText: 'Dirección de destino',
                    border: const OutlineInputBorder(),
                    isDense: true,
                    suffixIcon: IconButton(
                      tooltip: 'Usar mi ubicación actual',
                      icon: const Icon(Icons.my_location, color: Colors.blue),
                      onPressed: () => _capturarUbicacion(false),
                    ),
                  ),
                  validator: (v) => _destinoLat != null ? null : validarRequerido(v),
                ),
                if (_destinoLat != null)
                  chipGpsGuardado(onQuitar: () => setState(() {
                        _destinoLat = null;
                        _destinoLng = null;
                      })),
                const SizedBox(height: 12),
                _campoTelefono(_telDestinoCtrl, 'WhatsApp / teléfono de quien recibe'),
              ],
            ),
            _construirBloque(
              titulo: 'Detalles Finales',
              icono: Icons.payments,
              hijos: [
                DropdownButtonFormField<String>(
                  initialValue: _metodoPago,
                  decoration: const InputDecoration(
                    labelText: 'Método de Pago',
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
            const SizedBox(height: 20),
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
                    : const Text('SOLICITAR MÓVIL AHORA',
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
