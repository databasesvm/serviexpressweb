import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:serviexpress_app/utils/onesignal_api.dart'; // <-- RUTA CORREGIDA

class ClienteShoppingForm extends StatefulWidget {
  final Map<String, dynamic> usuario;
  const ClienteShoppingForm({super.key, required this.usuario});

  @override
  State<ClienteShoppingForm> createState() => _ClienteShoppingFormState();
}

class _ClienteShoppingFormState extends State<ClienteShoppingForm> {
  final _formKey = GlobalKey<FormState>();
  bool _procesando = false;

  final _tiendaCtrl = TextEditingController();
  final _destinoCtrl = TextEditingController();
  final _listaCtrl = TextEditingController();
  final _telContactoCtrl = TextEditingController();

  double? _destinoLat;
  double? _destinoLng;

  String _metodoPago = 'Efectivo';
  bool _requiereCotizacion = true;
  double _tarifaSugerida = 0.0;

  List<Map<String, dynamic>> _redDirecciones = [];
  List<Map<String, dynamic>> _sugerenciasDestino = [];
  String? _destinoBase;
  String? _sectorDestinoBase;

  @override
  void initState() {
    super.initState();
    _telContactoCtrl.text = widget.usuario['telefono']?.toString() ?? '';
    _precargarUbicaciones();
    _cargarRedDirecciones();
  }

  Future<void> _cargarRedDirecciones() async {
    try {
      final data = await Supabase.instance.client
          .from('red_dir_se')
          .select('id, nombre, municipio, sector_id, precio')
          .eq('usuario_id', widget.usuario['id'])
          .eq('activo', true)
          .order('nombre');
      if (mounted) setState(() => _redDirecciones = List<Map<String, dynamic>>.from(data));
    } catch (_) {}
  }

  void _onDestinoChanged(String texto) {
    if (_destinoBase != null && texto.toUpperCase().startsWith(_destinoBase!)) {
      if (_sugerenciasDestino.isNotEmpty) setState(() => _sugerenciasDestino = []);
      return;
    }
    if (_sectorDestinoBase != null && texto.toLowerCase().contains(_sectorDestinoBase!.toLowerCase())) {
      if (_sugerenciasDestino.isNotEmpty) setState(() => _sugerenciasDestino = []);
      return;
    }
    _destinoBase = null; _sectorDestinoBase = null;
    if (texto.length < 2) { if (_sugerenciasDestino.isNotEmpty) setState(() => _sugerenciasDestino = []); return; }
    final t = texto.toLowerCase();
    final palabras = t.split(RegExp(r'\s+')).where((w) => w.length > 2).toList();
    final List<Map<String, dynamic>> enc = [];
    for (final d in _redDirecciones) {
      final n = (d['nombre'] ?? '').toString().toLowerCase();
      final ok = n.contains(t) || palabras.any((w) => n.contains(w));
      if (!ok) continue;
      final int? precio = d['precio'] as int?;
      enc.add({'id': d['id'], 'nombre': d['nombre'].toString().toUpperCase(), 'precio': precio});
      if (enc.length >= 5) break;
    }
    setState(() => _sugerenciasDestino = enc);
  }

  Widget _buildSugerenciasDestino() {
    if (_sugerenciasDestino.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Wrap(
        spacing: 8, runSpacing: 6,
        children: _sugerenciasDestino.map((sug) {
          final nombre = sug['nombre'].toString();
          final int? precio = sug['precio'] as int?;
          String? precioStr;
          if (precio != null) {
            String r = ''; int c = 0; final s = precio.toString();
            for (int i = s.length - 1; i >= 0; i--) { r = s[i] + r; c++; if (c == 3 && i > 0) { r = '.$r'; c = 0; } }
            precioStr = '\$$r';
          }
          return InkWell(
            onTap: () {
              _destinoBase = nombre; _sectorDestinoBase = null;
              _destinoCtrl.text = '$nombre - ';
              if (precio != null) { _tarifaSugerida = precio.toDouble(); _requiereCotizacion = false; }
              setState(() => _sugerenciasDestino = []);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: precio != null ? Colors.blue[50] : Colors.grey[100],
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: precio != null ? Colors.blue[200]! : Colors.grey[300]!),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.location_city, color: precio != null ? Colors.blue[700] : Colors.grey[600], size: 13),
                const SizedBox(width: 4),
                Text(precioStr != null ? '$nombre ($precioStr)' : nombre,
                  style: TextStyle(color: precio != null ? Colors.blue[900] : Colors.grey[700], fontSize: 11, fontWeight: FontWeight.w600)),
              ]),
            ),
          );
        }).toList(),
      ),
    );
  }

  Future<void> _precargarUbicaciones() async {
    try {
      final data = await Supabase.instance.client
          .from('usuarios')
          .select('ultima_origen, ultimo_destino, ultimo_destino_lat, ultimo_destino_lng')
          .eq('id', widget.usuario['id'])
          .single();
      if (!mounted) return;
      setState(() {
        if (data['ultima_origen'] != null && _tiendaCtrl.text.isEmpty)
          _tiendaCtrl.text = data['ultima_origen'].toString();
        if (data['ultimo_destino'] != null && _destinoCtrl.text.isEmpty) {
          _destinoCtrl.text = data['ultimo_destino'].toString();
          _destinoLat = (data['ultimo_destino_lat'] as num?)?.toDouble();
          _destinoLng = (data['ultimo_destino_lng'] as num?)?.toDouble();
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
          '[ COMPRAS ] - 🛒 LISTA:\n${_listaCtrl.text.trim()}\n---\n📞 Tel: ${_telContactoCtrl.text} | PAGO: $_metodoPago';

      // F2 SE (#1 de paradero o, si no hay, el más cercano) la resuelve el
      // SERVIDOR (se_f2_huecos). La app ya no elige móvil ni manda ese push.

      // ---> INSERCIÓN EN BASE DE DATOS CON CANDADO VIP <---
      await Supabase.instance.client.from('servicios').insert({
        'cliente_id': widget.usuario['id'],
        'creador': widget.usuario['nombre'],
        'tipo_servicio': 'COMPRAS',
        'origen': _tiendaCtrl.text.trim().toUpperCase(),
        'destino': _destinoCtrl.text.trim().toUpperCase(),
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
        'se_cascade_t0': DateTime.now().toUtc().toIso8601String(),
        // F1 (Masters) lo manda el servidor; si es cotización no envía nada.
        if (!_requiereCotizacion) 'se_f1_motivo': 'nuevo',
      });

      // ---> GUARDAR ORIGEN/DESTINO PARA PRÓXIMOS PEDIDOS <---
      Supabase.instance.client.from('usuarios').update({
        'ultima_origen': _tiendaCtrl.text.trim().toUpperCase(),
        'ultimo_destino': _destinoCtrl.text.trim().toUpperCase(),
        'ultimo_destino_lat': _destinoLat,
        'ultimo_destino_lng': _destinoLng,
      }).eq('id', widget.usuario['id']).then((_) {}).catchError((_) {});

      // ---> CASCADA SE (F1 Masters T=0, F2 paradero T+30s; F3/F4 vía Edge Function) <---
      // F1 (T=0) Masters: servidor (trg_se_f1_servidor, se_f1_motivo).
      // F2 (T+30s): servidor (se_f2_huecos).
      // F3 y F4: se-notif-fase3/se-notif-fase4 vía se_cascade_t0.
      // ---> DISPARO A CENTRAL POR SEGMENTO (más confiable que por IDs) <---
      try {
        await MotorNotificaciones.dispararACentral(
          titulo: _requiereCotizacion
              ? '❓ NUEVA COTIZACIÓN (CLIENTE)'
              : '🛒 NUEVA LISTA DE COMPRAS',
          mensaje: 'Cliente solicita domicilio de compras: ${_destinoCtrl.text.trim().toUpperCase()}',
          urgente: true,
          sonido: _requiereCotizacion ? 'central_cotizacion' : 'central_radar',
          canalAndroidId: _requiereCotizacion
              ? MotorNotificaciones.canalCotizacionId
              : MotorNotificaciones.canalRadarId,
        );
      } catch (e) {
        debugPrint('Error OneSignal: $e');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('¡Lista enviada a Central con éxito!'),
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
          .like('observacion', '%[ COMPRAS ]%')
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
              'COMPRAS FRECUENTES',
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
                        'Toca para repetir esta compra',
                        style: TextStyle(color: Colors.grey, fontSize: 11),
                      ),
                      trailing: const Icon(
                        Icons.touch_app,
                        size: 16,
                        color: Color(0xff3AF500),
                      ),
                      onTap: () {
                        setState(() {
                          _tiendaCtrl.text = ruta['origen'];
                          _destinoCtrl.text = ruta['destino'];
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
        title: Text(
          'Encargos y Compras',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _construirHistorial(),
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
                  validator: (v) => v!.isEmpty ? 'Requerido' : null,
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
                  validator: (v) =>
                      v!.isEmpty ? 'La lista no puede estar vacía' : null,
                ),
              ],
            ),
            _construirBloque(
              titulo: 'Punto de Entrega',
              icono: Icons.home,
              hijos: [
                TextFormField(
                  controller: _destinoCtrl,
                  onChanged: _onDestinoChanged,
                  decoration: InputDecoration(
                    labelText: 'Dirección donde recibes',
                    border: const OutlineInputBorder(),
                    isDense: true,
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.my_location, color: Colors.blue),
                      onPressed: _capturarDestinoGps,
                    ),
                  ),
                  validator: (v) => v!.isEmpty ? 'Requerido' : null,
                ),
                _buildSugerenciasDestino(),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _telContactoCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: 'Teléfono de Contacto',
                    border: const OutlineInputBorder(),
                    isDense: true,
                    suffixIcon: IconButton(
                      icon: const Icon(
                        Icons.clear,
                        size: 18,
                        color: Colors.grey,
                      ),
                      onPressed: () => _telContactoCtrl.clear(),
                    ),
                  ),
                  onTap: () {
                    // Vaciado inteligente
                    if (_telContactoCtrl.text ==
                        widget.usuario['telefono']?.toString()) {
                      _telContactoCtrl.clear();
                    }
                  },
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
                    labelText: '¿Cómo pagarás el servicio?',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: ['Efectivo', 'Transferencia']
                      .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                      .toList(),
                  onChanged: (val) => setState(() => _metodoPago = val!),
                ),
                const SizedBox(height: 16),
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
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    subtitle: const Text(
                      'Si no conoces la tarifa, la Central te enviará el costo del domicilio antes de despachar.',
                      style: TextStyle(fontSize: 11),
                    ),
                    value: _requiereCotizacion,
                    activeThumbColor: Colors.orange,
                    onChanged: (val) => setState(() {
                      _requiereCotizacion = val;
                      if (val) _tarifaSugerida = 0;
                    }),
                    contentPadding: EdgeInsets.zero,
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
