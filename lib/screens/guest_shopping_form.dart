import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:serviexpress_app/utils/onesignal_api.dart'; // <-- RUTA CORREGIDA DE ONESIGNAL
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
        if (origen != null && _tiendaCtrl.text.isEmpty)
          _tiendaCtrl.text = origen;
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
          '[ COMPRAS ] - 🛒 LISTA:\n${_listaCtrl.text.trim()}\n---\n📞 Contacto: ${_telContactoCtrl.text} | PAGO: $_metodoPago';
      if (_requiereCotizacion)
        notaFinal = '⚠️ SOLICITA COTIZACIÓN | $notaFinal';

      // Cascada SE completa: F1 Masters aquí, F2 la resuelve el SERVIDOR
      // (se_f2_huecos) y F3/F4 los edge functions desde se_cascade_t0.
      // (Antes el #1 quedaba como exclusivo y el pedido nunca hacía cascada.)

      // ---> INSERCIÓN EN BASE DE DATOS CON CANDADO VIP <---
      final response = await Supabase.instance.client
          .from('servicios')
          .insert({
            'creador': 'Invitado: ${_nombreCtrl.text.trim()}',
            'tipo_servicio': 'COMPRAS',
            'origen': _tiendaCtrl.text.trim().toUpperCase(),
            'destino': _destinoCtrl.text.trim().toUpperCase(),
            'destino_lat': _destinoLat,
            'destino_lng': _destinoLng,
            'tarifa': 0.0,
            'tarifa_detalle': {'total': 0.0, 'fuente': 'invitado'},
            'observacion': notaFinal,
            'estado': _requiereCotizacion ? 'cotizacion' : 'pendiente',
            if (!_requiereCotizacion)
              'se_cascade_t0': DateTime.now().toUtc().toIso8601String(),
            // F1 (Masters) lo manda el servidor (trg_se_f1_servidor)
            if (!_requiereCotizacion) 'se_f1_motivo': 'nuevo',
          })
          .select('id') // solo se usa el id para el seguimiento
          .single();

      // Guardamos el ID del pedido + origen/destino para próximos pedidos
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('ultimo_pedido_invitado', response['id']);
      prefs.setString('guest_ultima_origen', _tiendaCtrl.text.trim().toUpperCase());
      prefs.setString('guest_ultimo_destino', _destinoCtrl.text.trim().toUpperCase());
      if (_destinoLat != null) prefs.setDouble('guest_ultimo_destino_lat', _destinoLat!);
      if (_destinoLng != null) prefs.setDouble('guest_ultimo_destino_lng', _destinoLng!);

      // ---> DISPARO A CENTRAL POR SEGMENTO (más confiable que por IDs) <---
      try {
        await MotorNotificaciones.dispararACentral(
          titulo: '🛒 COMPRAS INVITADO',
          mensaje: '${_nombreCtrl.text.trim()} → ${_destinoCtrl.text.trim().toUpperCase()}',
          urgente: true,
        );
      } catch (e) {
        debugPrint('Error OneSignal: $e');
      }

      // F1 (T=0): Masters → lo manda el servidor (se_f1_motivo en el insert).

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
    _tiendaCtrl.dispose();
    _destinoCtrl.dispose();
    _listaCtrl.dispose();
    _telContactoCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5), // dark theme
      appBar: AppBar(
        title: Text(
          'Compras y Mandados',
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
              titulo: '¿Qué y dónde compramos?',
              icono: Icons.shopping_cart,
              hijos: [
                TextFormField(
                  controller: _tiendaCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Lugar de compra (Ej: Éxito, Farmacia X)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  validator: (v) => v == null || v.isEmpty ? 'Requerido' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _listaCtrl,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    labelText: 'Lista de productos',
                    alignLabelWithHint: true,
                    hintText:
                        'Ej: 2 leches Colanta deslactosada 1L,\n1 Arroz Roa 5kg...',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => v == null || v.isEmpty
                      ? 'La lista no puede estar vacía'
                      : null,
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
                        'SOLICITAR COMPRA AHORA',
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
