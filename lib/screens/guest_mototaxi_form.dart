import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:serviexpress_app/utils/onesignal_api.dart'; // <-- RUTA CORREGIDA DE ONESIGNAL

class GuestMototaxiForm extends StatefulWidget {
  const GuestMototaxiForm({super.key});

  @override
  State<GuestMototaxiForm> createState() => _GuestMototaxiFormState();
}

class _GuestMototaxiFormState extends State<GuestMototaxiForm> {
  final _formKey = GlobalKey<FormState>();
  bool _procesando = false;

  final _nombreCtrl = TextEditingController();
  final _telPasajeroCtrl = TextEditingController();
  final _origenCtrl = TextEditingController();
  final _destinoCtrl = TextEditingController();

  double? _origenLat;
  double? _origenLng;

  String _metodoPago = 'Efectivo';
  bool _requiereCotizacion = false;
  double _tarifaSugerida = 0.0;

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
        if (origen != null && _origenCtrl.text.isEmpty) {
          _origenCtrl.text = origen;
          _origenLat = prefs.getDouble('guest_ultima_origen_lat');
          _origenLng = prefs.getDouble('guest_ultima_origen_lng');
        }
        final destino = prefs.getString('guest_ultimo_destino');
        if (destino != null && _destinoCtrl.text.isEmpty)
          _destinoCtrl.text = destino;
      });
    } catch (_) {}
  }

  Future<void> _capturarUbicacion() async {
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
        _origenLat = pos.latitude;
        _origenLng = pos.longitude;
        _origenCtrl.text = '📍 Mi Ubicación Actual';
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
          '[ MOTOTAXI ] - PAGO: $_metodoPago | 📱 Pasajero: ${_telPasajeroCtrl.text}';

      // ---> ESCÁNER DE FILA INTELIGENTE (INVITADOS - MOTOTAXI) <---
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
            'origen': _origenCtrl.text.trim().toUpperCase(),
            'destino': _destinoCtrl.text.trim().toUpperCase(),
            'origen_lat': _origenLat,
            'origen_lng': _origenLng,
            'tarifa': _requiereCotizacion ? 0.0 : _tarifaSugerida,
            'tarifa_detalle': {
              'total': _requiereCotizacion ? 0.0 : _tarifaSugerida,
              'base': _tarifaSugerida,
              'fuente': _requiereCotizacion ? 'invitado_cotizacion' : 'invitado_sugerida',
            },
            'observacion': notaFinal,
            'estado': _requiereCotizacion ? 'cotizacion' : 'pendiente',
            'exclusivo_id': idPilotoExclusivo,
          })
          .select()
          .single();

      // Guardamos el ID del pedido + origen/destino para próximos pedidos
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('ultimo_pedido_invitado', response['id']);
      prefs.setString('guest_ultima_origen', _origenCtrl.text.trim().toUpperCase());
      if (_origenLat != null) prefs.setDouble('guest_ultima_origen_lat', _origenLat!);
      if (_origenLng != null) prefs.setDouble('guest_ultima_origen_lng', _origenLng!);
      prefs.setString('guest_ultimo_destino', _destinoCtrl.text.trim().toUpperCase());

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
                'Cliente no registrado solicita tarifa hacia: ${_destinoCtrl.text.trim().toUpperCase()}',
            urgente: true,
          );
        }
      } catch (e) {
        debugPrint('Error OneSignal: $e');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('¡Mototaxi solicitado con éxito!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
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
    _telPasajeroCtrl.dispose();
    _origenCtrl.dispose();
    _destinoCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:
          const Color(0xFF0D0D0D), // dark themeINDADO (Sin índices extraños)
      appBar: AppBar(
        title: Text(
          'Pedir Mototaxi',
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
              titulo: 'Datos del Pasajero',
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
                      : null, // <-- CERO PANTALLAS ROJAS
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _telPasajeroCtrl,
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
              titulo: 'Ruta del Viaje',
              icono: Icons.map,
              hijos: [
                TextFormField(
                  controller: _origenCtrl,
                  decoration: InputDecoration(
                    labelText: 'Punto de recogida',
                    border: const OutlineInputBorder(),
                    isDense: true,
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.my_location, color: Colors.blue),
                      onPressed: _capturarUbicacion,
                    ),
                  ),
                  validator: (v) => v == null || v.isEmpty ? 'Requerido' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _destinoCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Punto de destino',
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
                  onChanged: (val) =>
                      setState(() => _metodoPago = val ?? 'Efectivo'),
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
                        'PEDIR MOTOTAXI AHORA',
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
