import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:serviexpress_app/utils/onesignal_api.dart'; // <-- RUTA CORREGIDA

class ClienteDeliveryForm extends StatefulWidget {
  final Map<String, dynamic> usuario;
  const ClienteDeliveryForm({super.key, required this.usuario});

  @override
  State<ClienteDeliveryForm> createState() => _ClienteDeliveryFormState();
}

class _ClienteDeliveryFormState extends State<ClienteDeliveryForm> {
  final _formKey = GlobalKey<FormState>();
  bool _procesando = false;

  final _telOrigenCtrl = TextEditingController();
  final _dirOrigenCtrl = TextEditingController();
  final _dirDestinoCtrl = TextEditingController();
  final _telDestinoCtrl = TextEditingController();

  double? _origenLat;
  double? _origenLng;
  double? _destinoLat;
  double? _destinoLng;

  String _metodoPago = 'Efectivo';
  bool _requiereCotizacion = true;
  double _tarifaSugerida = 0.0;

  @override
  void initState() {
    super.initState();
    _telOrigenCtrl.text = widget.usuario['telefono']?.toString() ?? '';
    _precargarUbicaciones();
  }

  Future<void> _precargarUbicaciones() async {
    try {
      final data = await Supabase.instance.client
          .from('usuarios')
          .select(
            'ultima_origen, ultima_origen_lat, ultima_origen_lng, '
            'ultimo_destino, ultimo_destino_lat, ultimo_destino_lng',
          )
          .eq('id', widget.usuario['id'])
          .single();
      if (!mounted) return;
      setState(() {
        if (data['ultima_origen'] != null && _dirOrigenCtrl.text.isEmpty) {
          _dirOrigenCtrl.text = data['ultima_origen'].toString();
          _origenLat = (data['ultima_origen_lat'] as num?)?.toDouble();
          _origenLng = (data['ultima_origen_lng'] as num?)?.toDouble();
        }
        if (data['ultimo_destino'] != null && _dirDestinoCtrl.text.isEmpty) {
          _dirDestinoCtrl.text = data['ultimo_destino'].toString();
          _destinoLat = (data['ultimo_destino_lat'] as num?)?.toDouble();
          _destinoLng = (data['ultimo_destino_lng'] as num?)?.toDouble();
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

      // ---> ESCÁNER DE FILA INTELIGENTE Y PARADEROS <---
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
        debugPrint('Error en el escáner táctico de paquetería: $e');
      }

      // ---> INSERCIÓN EN BASE DE DATOS CON CANDADO VIP <---
      await Supabase.instance.client.from('servicios').insert({
        'cliente_id': widget.usuario['id'],
        'creador': widget.usuario['nombre'],
        'origen': _dirOrigenCtrl.text.trim().toUpperCase(),
        'destino': _dirDestinoCtrl.text.trim().toUpperCase(),
        'origen_lat': _origenLat,
        'origen_lng': _origenLng,
        'destino_lat': _destinoLat,
        'destino_lng': _destinoLng,
        'tarifa': _requiereCotizacion ? 0.0 : _tarifaSugerida,
        'tarifa_detalle': {
          'total': _requiereCotizacion ? 0.0 : _tarifaSugerida,
          'base': _tarifaSugerida,
          'fuente': _requiereCotizacion ? 'cliente_cotizacion' : 'cliente_sugerida',
        },
        'observacion': notaFinal,
        'estado': _requiereCotizacion ? 'cotizacion' : 'pendiente',
        'exclusivo_id': idPilotoExclusivo,
      });

      // ---> GUARDAR ORIGEN/DESTINO PARA PRÓXIMOS PEDIDOS <---
      Supabase.instance.client.from('usuarios').update({
        'ultima_origen': _dirOrigenCtrl.text.trim().toUpperCase(),
        'ultima_origen_lat': _origenLat,
        'ultima_origen_lng': _origenLng,
        'ultimo_destino': _dirDestinoCtrl.text.trim().toUpperCase(),
        'ultimo_destino_lat': _destinoLat,
        'ultimo_destino_lng': _destinoLng,
      }).eq('id', widget.usuario['id']).then((_) {}).catchError((_) {});

      // ---> CASCADA 4 FASES (T=0 Masters, T+1min 1km, T+2min todos) <---
      if (!_requiereCotizacion) {
        try {
          final String origenNotif = _dirOrigenCtrl.text.trim().toUpperCase();
          if (idPilotoExclusivo != null) {
            await MotorNotificaciones.dispararMisil(
              idDestino: idPilotoExclusivo,
              titulo: '🎯 TU TURNO EXCLUSIVO',
              mensaje: 'Nueva PAQUETERÍA desde $origenNotif',
              urgente: true,
            );
          } else {
            // T=0: Masters
            final masters = await Supabase.instance.client
                .from('usuarios').select('id')
                .or('rol.eq.central,rol.eq.master,rango_movil.eq.MASTER')
                .neq('suspendido', true);
            final masterIds = masters.map((u) => u['id'].toString()).toList();
            if (masterIds.isNotEmpty) {
              await MotorNotificaciones.dispararRafa(
                idsDestinos: masterIds,
                titulo: '👑 NUEVA PAQUETERÍA',
                mensaje: 'Cliente solicita PAQUETERÍA desde $origenNotif',
                urgente: true,
              );
            }
            // T+1min: motos en radio 1km
            final candidatos = await Supabase.instance.client
                .from('usuarios').select('id, latitud, longitud')
                .eq('rol', 'movil').eq('en_linea', true).neq('suspendido', true)
                .not('rango_movil', 'in', '("MASTER")');
            final idsZonales = (candidatos as List).where((u) {
              if (masterIds.contains(u['id'].toString())) return false;
              if (_origenLat == null || _origenLng == null) return true;
              final uLat = (u['latitud'] as num?)?.toDouble();
              final uLng = (u['longitud'] as num?)?.toDouble();
              if (uLat == null || uLng == null) return false;
              return const Distance().as(
                    LengthUnit.Meter,
                    LatLng(uLat, uLng),
                    LatLng(_origenLat!, _origenLng!),
                  ) <= 1000;
            }).map((u) => u['id'].toString()).toList();
            if (idsZonales.isNotEmpty) {
              await MotorNotificaciones.programarMisilRetardado(
                externalIds: idsZonales,
                titulo: '📡 PAQUETERÍA CERCA (1km)',
                mensaje: 'PAQUETERÍA desde $origenNotif — revisa el radar.',
                minutosRetardo: 1,
              );
            }
            // T+2min: todos
            final todosData = await Supabase.instance.client
                .from('usuarios').select('id')
                .eq('rol', 'movil').eq('en_linea', true).neq('suspendido', true);
            final todosIds = (todosData as List)
                .map((u) => u['id'].toString())
                .where((id) => !masterIds.contains(id))
                .toList();
            if (todosIds.isNotEmpty) {
              await MotorNotificaciones.programarMisilRetardado(
                externalIds: todosIds,
                titulo: '🚨 SERVICIO SIN TOMAR',
                mensaje: 'PAQUETERÍA sin asignar desde $origenNotif.',
                minutosRetardo: 2,
              );
            }
          }
        } catch (e) {
          debugPrint('Error OneSignal: $e');
        }
      }
      try {
        await MotorNotificaciones.dispararACentral(
          titulo: _requiereCotizacion
              ? '❓ NUEVA COTIZACIÓN (CLIENTE)'
              : '🚨 NUEVA PAQUETERÍA EN RADAR',
          mensaje: 'Paquetería desde ${_dirOrigenCtrl.text.trim().toUpperCase()}',
          urgente: true,
          sonido: _requiereCotizacion ? 'central_cotizacion' : 'central_radar',
        );
      } catch (e) {
        debugPrint('Error OneSignal central: $e');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('¡Domicilio solicitado con éxito!'),
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

  Widget _construirHistorial() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: Supabase.instance.client
          .from('servicios')
          .select()
          .eq('cliente_id', widget.usuario['id'])
          .eq('estado', 'finalizado')
          .like('observacion', '%[ PAQUETERÍA ]%')
          .order('id', ascending: false)
          .limit(30),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isEmpty)
          return const SizedBox.shrink();

        final rutasUnicas = <String, Map<String, dynamic>>{};
        for (var h in snapshot.data!) {
          final clave = '${h['origen']}->${h['destino']}';
          if (!rutasUnicas.containsKey(clave)) rutasUnicas[clave] = h;
        }
        final rutas = rutasUnicas.values.take(3).toList();
        if (rutas.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'TUS RUTAS FRECUENTES',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 8),
            ...rutas
                .map(
                  (ruta) => Card(
                    elevation: 1,
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: const Icon(Icons.history, color: Colors.black45),
                      title: Text(
                        '${ruta['origen']} ➔ ${ruta['destino']}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                      subtitle: const Text(
                        'Toca para repetir esta ruta',
                        style: TextStyle(color: Colors.grey, fontSize: 11),
                      ),
                      trailing: const Icon(
                        Icons.touch_app,
                        size: 16,
                        color: Color(0xff3AF500),
                      ),
                      onTap: () {
                        setState(() {
                          _dirOrigenCtrl.text = ruta['origen'];
                          _dirDestinoCtrl.text = ruta['destino'];
                          _origenLat = null;
                          _origenLng = null;
                          _destinoLat = null;
                          _destinoLng = null;
                        });
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Ruta cargada.')),
                        );
                      },
                    ),
                  ),
                )
                ,
            const SizedBox(height: 20),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
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
        title: Text(
          'Envío de Paquetes',
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
            _construirHistorial(),
            _construirBloque(
              titulo: '¿Dónde recogemos?',
              icono: Icons.storefront,
              hijos: [
                TextFormField(
                  controller: _dirOrigenCtrl,
                  decoration: InputDecoration(
                    labelText: 'Dirección de Recogida',
                    border: const OutlineInputBorder(),
                    isDense: true,
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.my_location, color: Colors.blue),
                      onPressed: () => _capturarUbicacion(true),
                    ),
                  ),
                  validator: (v) => v!.isEmpty ? 'Requerido' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _telOrigenCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: 'Teléfono de quien entrega',
                    border: const OutlineInputBorder(),
                    isDense: true,
                    suffixIcon: IconButton(
                      icon: const Icon(
                        Icons.clear,
                        size: 18,
                        color: Colors.grey,
                      ),
                      onPressed: () => _telOrigenCtrl.clear(),
                    ),
                  ),
                  onTap: () {
                    // Vaciado inteligente
                    if (_telOrigenCtrl.text ==
                        widget.usuario['telefono']?.toString()) {
                      _telOrigenCtrl.clear();
                    }
                  },
                  validator: (v) => v!.isEmpty ? 'Requerido' : null,
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
                    labelText: 'Dirección de Destino',
                    border: const OutlineInputBorder(),
                    isDense: true,
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.my_location, color: Colors.blue),
                      onPressed: () => _capturarUbicacion(false),
                    ),
                  ),
                  validator: (v) => v!.isEmpty ? 'Requerido' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _telDestinoCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: 'Teléfono de quien recibe',
                    border: const OutlineInputBorder(),
                    isDense: true,
                    suffixIcon: IconButton(
                      icon: const Icon(
                        Icons.clear,
                        size: 18,
                        color: Colors.grey,
                      ),
                      onPressed: () => _telDestinoCtrl.clear(),
                    ),
                  ),
                  validator: (v) => v!.isEmpty ? 'Requerido' : null,
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
                    labelText: 'Método de Pago',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: ['Efectivo', 'Transferencia']
                      .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                      .toList(),
                  onChanged: (val) => setState(() => _metodoPago = val!),
                ),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange[200]!),
                  ),
                  child: SwitchListTile(
                    title: const Text(
                      'Solicitar cotización previa',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    subtitle: const Text(
                      'Marca esto si no conoces la tarifa y quieres que la Central te dé el precio antes de enviar la moto.',
                      style: TextStyle(fontSize: 11),
                    ),
                    value: _requiereCotizacion,
                    activeThumbColor: Colors.orange,
                    onChanged: (v) => setState(() => _requiereCotizacion = v),
                  ),
                ),
                if (!_requiereCotizacion) ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    initialValue: _tarifaSugerida > 0 ? _tarifaSugerida.toStringAsFixed(0) : '',
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Tarifa sugerida (\$)',
                      border: OutlineInputBorder(),
                      isDense: true,
                      prefixText: '\$ ',
                    ),
                    onChanged: (v) => setState(() => _tarifaSugerida = double.tryParse(v) ?? 0.0),
                  ),
                ],
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
                        'ENVIAR PAQUETE AHORA',
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
