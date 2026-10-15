import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:serviexpress_app/utils/paradero_objetivo.dart';
import 'package:serviexpress_app/utils/onesignal_api.dart'; // <-- RUTA CORREGIDA
import 'package:serviexpress_app/utils/invitado_comun.dart'; // GPS, errores claros + kit de diseño

class ClienteDeliveryForm extends StatefulWidget {
  final Map<String, dynamic> usuario;
  const ClienteDeliveryForm({super.key, required this.usuario});

  @override
  State<ClienteDeliveryForm> createState() => _ClienteDeliveryFormState();
}

class _ClienteDeliveryFormState extends State<ClienteDeliveryForm> {
  final _formKey = GlobalKey<FormState>();
  // "Rutas recientes": se consulta UNA vez al abrir (antes en cada redibujo)
  // y solo con las columnas que se usan.
  late final Future<List<Map<String, dynamic>>> _historialFuture =
      Supabase.instance.client
          .from('servicios')
          .select('origen, destino')
          .eq('cliente_id', widget.usuario['id'])
          .eq('estado', 'finalizado')
          .like('observacion', '%[ PAQUETERÍA ]%')
          .order('id', ascending: false)
          .limit(30);
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

  List<Map<String, dynamic>> _redDirecciones = [];
  List<Map<String, dynamic>> _sugerenciasDestino = [];
  String? _destinoBase;
  String? _sectorDestinoBase;

  @override
  void initState() {
    super.initState();
    _telOrigenCtrl.text = widget.usuario['telefono']?.toString() ?? '';
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
              _dirDestinoCtrl.text = '$nombre - ';
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

  // GPS: guarda la ubicación SIN borrar lo que el cliente escribió.
  Future<void> _capturarUbicacion(bool esOrigen) async {
    final pos = await gpsInvitado(context);
    if (pos == null || !mounted) return;
    setState(() {
      if (esOrigen) {
        _origenLat = pos.latitude;
        _origenLng = pos.longitude;
      } else {
        _destinoLat = pos.latitude;
        _destinoLng = pos.longitude;
      }
    });
  }

  // Si cambia la dirección escrita, el GPS guardado deja de servir.
  void _alEditarOrigen(String _) {
    if (_origenLat == null) return;
    setState(() {
      _origenLat = null;
      _origenLng = null;
    });
  }

  void _alEditarDestino(String texto) {
    if (_destinoLat != null) {
      setState(() {
        _destinoLat = null;
        _destinoLng = null;
      });
    }
    _onDestinoChanged(texto);
  }

  Future<void> _enviarPedido() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_requiereCotizacion && _tarifaSugerida <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Escribe cuánto cuesta, o elige "Que la Central me diga el precio".'),
        backgroundColor: Colors.red,
      ));
      return;
    }
    setState(() => _procesando = true);

    try {
      if (_dirOrigenCtrl.text.trim().isEmpty && _origenLat != null) {
        _dirOrigenCtrl.text = 'UBICACIÓN GPS DEL CLIENTE';
      }
      if (_dirDestinoCtrl.text.trim().isEmpty && _destinoLat != null) {
        _dirDestinoCtrl.text = 'UBICACIÓN GPS DEL CLIENTE';
      }
      String notaFinal =
          '[ PAQUETERÍA ] - PAGO: $_metodoPago | 📞 Envía: ${_telOrigenCtrl.text} | 📞 Recibe: ${_telDestinoCtrl.text}';

      // F2 SE: la resuelve el SERVIDOR (se_f2_huecos) → #1 del paradero más
      // cercano al origen o, si está vacío, el móvil más cercano (con filtros).
      final String? paraderoObjetivo =
          await paraderoMasCercano(_origenLat, _origenLng);

      // ---> INSERCIÓN EN BASE DE DATOS CON CANDADO VIP <---
      await Supabase.instance.client.from('servicios').insert({
        'cliente_id': widget.usuario['id'],
        'creador': widget.usuario['nombre'],
        'tipo_servicio': 'PAQUETERÍA',
        'origen': _dirOrigenCtrl.text.trim().toUpperCase(),
        'destino': _dirDestinoCtrl.text.trim().toUpperCase(),
        'origen_lat': _origenLat,
        'origen_lng': _origenLng,
        'destino_lat': _destinoLat,
        'destino_lng': _destinoLng,
        if (_destinoLat != null)
          'destino_gps_at': DateTime.now().toUtc().toIso8601String(),
        'tarifa': _requiereCotizacion ? 0.0 : _tarifaSugerida,
        'tarifa_detalle': {
          'total': _requiereCotizacion ? 0.0 : _tarifaSugerida,
          'base': _tarifaSugerida,
          'fuente': _requiereCotizacion ? 'cliente_cotizacion' : 'cliente_sugerida',
        },
        'observacion': notaFinal,
        'estado': _requiereCotizacion ? 'cotizacion' : 'pendiente',
        if (paraderoObjetivo != null) 'paradero_origen': paraderoObjetivo,
        'se_cascade_t0': DateTime.now().toUtc().toIso8601String(),
        // F1 (Masters) lo manda el servidor; si es cotización no envía nada.
        if (!_requiereCotizacion) 'se_f1_motivo': 'nuevo',
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

      // ---> CASCADA SE (F1 Masters T=0, F2 paradero T+30s; F3/F4 vía Edge Function) <---
      // F1 (T=0) Masters: servidor (trg_se_f1_servidor, se_f1_motivo).
      // F2 (T+30s): servidor (se_f2_huecos).
      // F3 y F4: se-notif-fase3/se-notif-fase4 vía se_cascade_t0.
      try {
        await MotorNotificaciones.dispararACentral(
          titulo: _requiereCotizacion
              ? '❓ NUEVA COTIZACIÓN (CLIENTE)'
              : '🚨 NUEVA PAQUETERÍA EN RADAR',
          mensaje: 'Paquetería desde ${_dirOrigenCtrl.text.trim().toUpperCase()}',
          urgente: true,
          sonido: _requiereCotizacion ? 'central_cotizacion' : 'central_radar',
          canalAndroidId: _requiereCotizacion
              ? MotorNotificaciones.canalCotizacionId
              : MotorNotificaciones.canalRadarId,
        );
      } catch (e) {
        debugPrint('Error OneSignal central: $e');
      }

      if (mounted) {
        // Directo a su pantalla de pedidos (radar del cliente)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_requiereCotizacion
                ? '✅ Pedido enviado. Aquí te avisamos cuando la Central te diga el precio.'
                : '✅ Pedido enviado. Ya estamos buscando un Móvil.'),
            backgroundColor: Colors.green[700],
            duration: const Duration(seconds: 5),
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorInvitado(e)), backgroundColor: Colors.red),
        );
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  static const _estilo = EstiloServicio.paqueteria;

  Widget _construirBloque({
    int? paso,
    required String titulo,
    required IconData icono,
    required List<Widget> hijos,
  }) =>
      BloqueSE(paso: paso, titulo: titulo, icono: icono, color: _estilo.color, hijos: hijos);

  Widget _construirHistorial() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _historialFuture,
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
                color: Colors.white60,
                fontSize: 12,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 8),
            ...rutas
                .map(
                  (ruta) => TarjetaSE(
                    acento: _estilo.color,
                    padding: EdgeInsets.zero,
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

  // Precio: "Que la Central me diga el precio" o "Ya sé cuánto cuesta".
  Widget _opcionPrecio() => OpcionPrecioSE(
        centralDicePrecio: _requiereCotizacion,
        color: _estilo.color,
        onCambio: (v) => setState(() => _requiereCotizacion = v),
        campoValor: TextFormField(
          initialValue: _tarifaSugerida > 0 ? _tarifaSugerida.toStringAsFixed(0) : '',
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: '¿Cuánto cuesta el envío?',
            prefixText: '\$ ',
          ),
          onChanged: (v) => setState(() => _tarifaSugerida = double.tryParse(v) ?? 0.0),
        ),
      );

  // Teléfono: se queda lleno (no se borra al tocarlo); la ✕ lo limpia.
  Widget _campoTelefonoCliente(TextEditingController ctrl, String label) => TextFormField(
        controller: ctrl,
        keyboardType: TextInputType.phone,
        decoration: InputDecoration(
          labelText: label,
          hintText: 'Ej: 3001234567',
          suffixIcon: IconButton(
            tooltip: 'Borrar',
            icon: const Icon(Icons.clear, size: 20, color: Colors.grey),
            onPressed: () => ctrl.clear(),
          ),
        ),
        validator: obligatorioSE('Escribe un teléfono para que el Móvil pueda llamar'),
      );

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
    return Form(
      key: _formKey,
      child: ScaffoldServicioSE(
        estilo: _estilo,
        procesando: _procesando,
        onEnviar: _enviarPedido,
        children: [
            _construirHistorial(),
            _construirBloque(
              paso: 1,
              titulo: '¿Dónde recogemos?',
              icono: Icons.storefront,
              hijos: [
                TextFormField(
                  controller: _dirOrigenCtrl,
                  onChanged: _alEditarOrigen,
                  decoration: const InputDecoration(
                    labelText: 'Dirección donde recogemos',
                    hintText: 'Ej: Calle 5 # 12-34, barrio Centro',
                  ),
                  validator: (v) => _origenLat != null
                      ? null
                      : obligatorioSE('Escribe dónde recogemos o toca "Recoger en mi ubicación actual"')(v),
                ),
                BotonUbicacionSE(
                  guardada: _origenLat != null,
                  color: _estilo.color,
                  texto: 'Recoger en mi ubicación actual',
                  onUsar: () => _capturarUbicacion(true),
                  onQuitar: () => setState(() {
                    _origenLat = null;
                    _origenLng = null;
                  }),
                ),
                const SizedBox(height: 12),
                _campoTelefonoCliente(_telOrigenCtrl, 'Teléfono de quien entrega'),
              ],
            ),
            _construirBloque(
              paso: 2,
              titulo: '¿Dónde entregamos?',
              icono: Icons.flag,
              hijos: [
                TextFormField(
                  controller: _dirDestinoCtrl,
                  onChanged: _alEditarDestino,
                  decoration: const InputDecoration(
                    labelText: 'Dirección donde entregamos',
                    hintText: 'Ej: Calle 5 # 12-34, barrio Centro',
                  ),
                  validator: (v) => _destinoLat != null
                      ? null
                      : obligatorioSE('Escribe a dónde lo llevamos o toca "Entregar en mi ubicación actual"')(v),
                ),
                _buildSugerenciasDestino(),
                BotonUbicacionSE(
                  guardada: _destinoLat != null,
                  color: _estilo.color,
                  texto: 'Entregar en mi ubicación actual',
                  onUsar: () => _capturarUbicacion(false),
                  onQuitar: () => setState(() {
                    _destinoLat = null;
                    _destinoLng = null;
                  }),
                ),
                const SizedBox(height: 12),
                _campoTelefonoCliente(_telDestinoCtrl, 'Teléfono de quien recibe'),
              ],
            ),
            _construirBloque(
              paso: 3,
              titulo: 'Precio y pago',
              icono: Icons.payments,
              hijos: [
                _opcionPrecio(),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _metodoPago,
                  decoration: const InputDecoration(labelText: '¿Cómo pagarás?'),
                  items: ['Efectivo', 'Transferencia']
                      .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                      .toList(),
                  onChanged: (val) => setState(() => _metodoPago = val!),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
