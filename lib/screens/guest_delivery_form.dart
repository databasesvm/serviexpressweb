import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:serviexpress_app/utils/onesignal_api.dart'; // <-- RUTA CORREGIDA DE ONESIGNAL
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
  double? _destinoLat;
  double? _destinoLng;

  String _metodoPago = 'Efectivo';

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

  Future<void> _capturarUbicacion(bool esOrigen) async {
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
        if (esOrigen) {
          _origenLat = pos.latitude;
          _origenLng = pos.longitude;
          _dirOrigenCtrl.text = '📍 Mi Ubicación Actual';
        } else {
          _destinoLat = pos.latitude;
          _destinoLng = pos.longitude;
          _dirDestinoCtrl.text = '📍 Mi Ubicación Actual';
        }
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
          '[ PAQUETERÍA ] - PAGO: $_metodoPago | 📞 Envía: ${_telOrigenCtrl.text} | 📞 Recibe: ${_telDestinoCtrl.text}';

      // ---> ESCÁNER DE FILA INTELIGENTE (INVITADOS - PAQUETERÍA) <---
      String? idPilotoExclusivo;
      try {
        final serviciosPendientes = await Supabase.instance.client
            .from('servicios')
            .select('exclusivo_id')
            .eq('estado', 'pendiente')
            .not('exclusivo_id', 'is', null);
        List<String> ocupados = serviciosPendientes
            .map((s) => s['exclusivo_id'].toString())
            .toList();

        final movilesLibres = await Supabase.instance.client
            .from('usuarios')
            .select('id, latitud, longitud, paradero_actual, ingreso_fila')
            .eq('rol', 'movil')
            .eq('en_linea', true)
            .not('latitud', 'is', null);

        final Distance medidorDistancia = const Distance();
        Map<String, dynamic>? movilMasCercano;
        double distanciaMinima = 999999;
        String? paraderoCercano;

        for (var movil in movilesLibres) {
          if (movil['latitud'] == null ||
              movil['longitud'] == null ||
              _origenLat == null ||
              _origenLng == null)
            continue;
          double dist = medidorDistancia.as(
            LengthUnit.Meter,
            LatLng(_origenLat!, _origenLng!),
            LatLng(movil['latitud'], movil['longitud']),
          );
          if (dist < distanciaMinima) {
            distanciaMinima = dist;
            paraderoCercano = movil['paradero_actual'];
            if (!ocupados.contains(movil['id'].toString())) {
              movilMasCercano = movil;
            }
          }
        }

        if (paraderoCercano != null && paraderoCercano.isNotEmpty) {
          final fila = movilesLibres
              .where((m) => m['paradero_actual'] == paraderoCercano)
              .toList();
          fila.sort(
            (a, b) =>
                DateTime.parse(
                  a['ingreso_fila'] ?? DateTime.now().toIso8601String(),
                ).compareTo(
                  DateTime.parse(
                    b['ingreso_fila'] ?? DateTime.now().toIso8601String(),
                  ),
                ),
          );
          for (var candidato in fila) {
            if (!ocupados.contains(candidato['id'].toString())) {
              idPilotoExclusivo = candidato['id'].toString();
              break;
            }
          }
        }

        if (idPilotoExclusivo == null &&
            movilMasCercano != null &&
            distanciaMinima <= 1000) {
          idPilotoExclusivo = movilMasCercano['id'].toString();
        }
      } catch (e) {
        debugPrint('Error en escáner de fila invitado: $e');
      }

      // ---> INSERCIÓN EN BASE DE DATOS CON CANDADO VIP <---
      final response = await Supabase.instance.client
          .from('servicios')
          .insert({
            'creador': 'Invitado: ${_nombreCtrl.text.trim()}',
            'origen': _dirOrigenCtrl.text.trim().toUpperCase(),
            'destino': _dirDestinoCtrl.text.trim().toUpperCase(),
            'origen_lat': _origenLat,
            'origen_lng': _origenLng,
            'destino_lat': _destinoLat,
            'destino_lng': _destinoLng,
            'tarifa': 0.0,
            'tarifa_detalle': {'total': 0.0, 'fuente': 'invitado'},
            'observacion': notaFinal,
            'estado': 'cotizacion',
            'exclusivo_id': idPilotoExclusivo,
          })
          .select()
          .single();

      // Guardamos el ID del pedido para el Tracker del invitado
      // + origen/destino para próximos pedidos
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('ultimo_pedido_invitado', response['id']);
      prefs.setString('guest_ultima_origen', _dirOrigenCtrl.text.trim().toUpperCase());
      if (_origenLat != null) prefs.setDouble('guest_ultima_origen_lat', _origenLat!);
      if (_origenLng != null) prefs.setDouble('guest_ultima_origen_lng', _origenLng!);
      prefs.setString('guest_ultimo_destino', _dirDestinoCtrl.text.trim().toUpperCase());
      if (_destinoLat != null) prefs.setDouble('guest_ultimo_destino_lat', _destinoLat!);
      if (_destinoLng != null) prefs.setDouble('guest_ultimo_destino_lng', _destinoLng!);

      // ---> DISPARO DIRECTO A CENTRAL PARA COTIZAR <---
      try {
        final centralMaster = await Supabase.instance.client
            .from('usuarios')
            .select('id')
            .inFilter('rol', ['central', 'master']);

        List<String> objetivos = centralMaster
            .map((u) => u['id'].toString())
            .toList();

        if (objetivos.isNotEmpty) {
          await MotorNotificaciones.dispararRafa(
            idsDestinos: objetivos,
            titulo: '❓ NUEVA COTIZACIÓN (NO REGISTRADO)',
            mensaje:
                'Cliente no registrado solicita tarifa hacia: ${_dirDestinoCtrl.text.trim().toUpperCase()}',
            urgente: true,
          );
        }
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
    _telOrigenCtrl.dispose();
    _dirOrigenCtrl.dispose();
    _dirDestinoCtrl.dispose();
    _telDestinoCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5), // <-- COLOR BLINDADO
      appBar: AppBar(
        title: Text(
          'Solicitar Domicilio',
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
              titulo: 'Tus Datos',
              icono: Icons.person,
              hijos: [
                TextFormField(
                  controller: _nombreCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nombre y Apellido',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  validator: (v) => v == null || v.isEmpty
                      ? 'Requerido'
                      : null, // <-- BLINDAJE NULL SAFETY
                ),
              ],
            ),
            _construirBloque(
              titulo: '¿Dónde recogemos?',
              icono: Icons.storefront,
              hijos: [
                TextFormField(
                  controller: _dirOrigenCtrl,
                  decoration: InputDecoration(
                    labelText: 'Dirección o nombre del local',
                    border: const OutlineInputBorder(),
                    isDense: true,
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.my_location, color: Colors.blue),
                      onPressed: () => _capturarUbicacion(true),
                    ),
                  ),
                  validator: (v) => v == null || v.isEmpty ? 'Requerido' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _telOrigenCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Teléfono de quien entrega',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  validator: (v) => v == null || v.isEmpty ? 'Requerido' : null,
                ),
              ],
            ),
            _construirBloque(
              titulo: '¿Dónde entregamos?',
              icono: Icons.flag,
              hijos: [
                TextFormField(
                  controller: _dirDestinoCtrl,
                  decoration: InputDecoration(
                    labelText: 'Dirección de destino',
                    border: const OutlineInputBorder(),
                    isDense: true,
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.my_location, color: Colors.blue),
                      onPressed: () => _capturarUbicacion(false),
                    ),
                  ),
                  validator: (v) => v == null || v.isEmpty ? 'Requerido' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _telDestinoCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Teléfono de quien recibe',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  validator: (v) => v == null || v.isEmpty ? 'Requerido' : null,
                ),
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
            const SizedBox(height: 20),
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
                        'SOLICITAR MÓVIL AHORA',
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
