import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:serviexpress_app/utils/onesignal_api.dart'; // <-- RUTA CORREGIDA DE ONESIGNAL
import 'package:serviexpress_app/screens/guest_tracking_screen.dart';
import 'package:serviexpress_app/utils/paradero_objetivo.dart';
import 'package:serviexpress_app/utils/textos_push.dart';

class GuestFoodForm extends StatefulWidget {
  const GuestFoodForm({super.key});

  @override
  State<GuestFoodForm> createState() => _GuestFoodFormState();
}

class _GuestFoodFormState extends State<GuestFoodForm> {
  final _formKey = GlobalKey<FormState>();
  bool _procesando = false;

  final _nombreCtrl = TextEditingController();
  final _restauranteCtrl = TextEditingController();
  final _destinoCtrl = TextEditingController();
  final _pedidoCtrl = TextEditingController();
  final _telContactoCtrl = TextEditingController();

  double? _destinoLat;
  double? _destinoLng;

  String _metodoPago = 'Efectivo';
  final bool _requiereCotizacion = true;

  @override
  void initState() {
    super.initState();
    _precargarUbicaciones();
  }

  Future<void> _precargarUbicaciones() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        final origen = prefs.getString('guest_ultima_origen');
        if (origen != null && _restauranteCtrl.text.isEmpty)
          _restauranteCtrl.text = origen;
        final destino = prefs.getString('guest_ultimo_destino');
        if (destino != null && _destinoCtrl.text.isEmpty) {
          _destinoCtrl.text = destino;
          _destinoLat = prefs.getDouble('guest_ultimo_destino_lat');
          _destinoLng = prefs.getDouble('guest_ultimo_destino_lng');
        }
      });
    } catch (_) {}
  }

  Future<void> _capturarDestinoGps() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ Activa el GPS de tu celular.'),
            backgroundColor: Colors.red,
          ),
        );
      return;
    }
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever)
        return;
    }

    try {
      Position pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      setState(() {
        _destinoLat = pos.latitude;
        _destinoLng = pos.longitude;
        _destinoCtrl.text = '📍 Mi Ubicación Actual';
      });
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Fallo satelital: $e')));
    }
  }

  Future<void> _enviarPedido() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _procesando = true);

    try {
      String notaFinal =
          '[ COMIDA ] - 🍔 PEDIDO:\n${_pedidoCtrl.text.trim()}\n---\n📞 Contacto: ${_telContactoCtrl.text} | PAGO: $_metodoPago';

      // Cascada SE completa (antes el #1 recibía el pedido como exclusivo y
      // nunca pasaba por F1/F2/F3/F4): F1 Masters aquí, F2 la resuelve el
      // SERVIDOR (se_f2_huecos, #1 de paradero o el más cercano) y F3/F4 los
      // edge functions desde se_cascade_t0.

      // ---> INSERCIÓN EN BASE DE DATOS CON CANDADO VIP <---
      final response = await Supabase.instance.client
          .from('servicios')
          .insert({
            'creador': 'Invitado: ${_nombreCtrl.text.trim()}',
            'origen': _restauranteCtrl.text.trim().toUpperCase(),
            'destino': _destinoCtrl.text.trim().toUpperCase(),
            'destino_lat': _destinoLat,
            'destino_lng': _destinoLng,
            'tarifa': 0.0,
            'tarifa_detalle': {'total': 0.0, 'fuente': 'invitado'},
            'observacion': notaFinal,
            'estado': _requiereCotizacion ? 'cotizacion' : 'pendiente',
            if (!_requiereCotizacion)
              'se_cascade_t0': DateTime.now().toUtc().toIso8601String(),
          })
          .select()
          .single();

      // Guardamos el ID del pedido + origen/destino para próximos pedidos
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('ultimo_pedido_invitado', response['id']);
      prefs.setString('guest_ultima_origen', _restauranteCtrl.text.trim().toUpperCase());
      prefs.setString('guest_ultimo_destino', _destinoCtrl.text.trim().toUpperCase());
      if (_destinoLat != null) prefs.setDouble('guest_ultimo_destino_lat', _destinoLat!);
      if (_destinoLng != null) prefs.setDouble('guest_ultimo_destino_lng', _destinoLng!);

      // ---> DISPARO A CENTRAL POR SEGMENTO (más confiable que por IDs) <---
      try {
        await MotorNotificaciones.dispararACentral(
          titulo: '🍔 COMIDA INVITADO',
          mensaje: '${_nombreCtrl.text.trim()} → ${_restauranteCtrl.text.trim().toUpperCase()}',
          urgente: true,
        );
      } catch (e) {
        debugPrint('Error OneSignal: $e');
      }

      // F1 (T=0): Masters en línea con SE
      if (!_requiereCotizacion) {
        await notificarMastersF1Invitado(
          'Comida (invitado): ${TextosPush.ruta(_restauranteCtrl.text, _destinoCtrl.text)}',
        );
      }

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const GuestTrackingScreen()),
        );
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
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
            Row(
              children: [
                Icon(icono, color: Colors.black54, size: 20),
                const SizedBox(width: 8),
                Text(
                  titulo,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
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
    _restauranteCtrl.dispose();
    _destinoCtrl.dispose();
    _pedidoCtrl.dispose();
    _telContactoCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5), // FIX #6: grey[1] era casi negro, debe ser grey[100]
      appBar: AppBar(
        title: Text(
          'Pedir Comida',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.black,
        iconTheme: IconThemeData(color: Colors.white),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _construirBloque(
              titulo: 'Identificación',
              icono: Icons.person,
              hijos: [
                TextFormField(
                  controller: _nombreCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Tu nombre',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  validator: (v) => v == null || v.isEmpty
                      ? 'Requerido'
                      : null, // <-- BLINDAJE NULL SAFETY
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _telContactoCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Teléfono de contacto',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  validator: (v) => v == null || v.isEmpty ? 'Requerido' : null,
                ),
              ],
            ),
            _construirBloque(
              titulo: '¿Dónde buscamos?',
              icono: Icons.restaurant,
              hijos: [
                TextFormField(
                  controller: _restauranteCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nombre del Restaurante',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  validator: (v) => v == null || v.isEmpty ? 'Requerido' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _pedidoCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: '¿Qué vas a pedir? (Ej: 2 hamburguesas)',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => v == null || v.isEmpty ? 'Requerido' : null,
                ),
              ],
            ),
            _construirBloque(
              titulo: 'Punto de Entrega',
              icono: Icons.home,
              hijos: [
                TextFormField(
                  controller: _destinoCtrl,
                  decoration: InputDecoration(
                    labelText: 'Dirección donde recibes',
                    border: const OutlineInputBorder(),
                    isDense: true,
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.my_location, color: Colors.blue),
                      onPressed: _capturarDestinoGps,
                    ),
                  ),
                  validator: (v) => v == null || v.isEmpty ? 'Requerido' : null,
                ),
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
                  onChanged: (val) => setState(
                    () => _metodoPago = val ?? 'Efectivo',
                  ), // <-- BLINDAJE NULL SAFETY
                ),
                const SizedBox(height: 16),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.orange[50], // Fondo suave
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange[300]!),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: Colors.orange,
                            size: 20,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Cotización Obligatoria',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: Colors.orange,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Para garantizar un cobro justo, la Central revisará tu solicitud y te enviará la tarifa exacta antes de despachar al conductor.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.black87,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 55,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xff3AF500),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _procesando ? null : _enviarPedido,
                child: _procesando
                    ? const CircularProgressIndicator(color: Colors.black)
                    : const Text(
                        'PEDIR COMIDA AHORA',
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
}
