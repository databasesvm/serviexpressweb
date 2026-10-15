import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:serviexpress_app/utils/onesignal_api.dart';
import 'package:serviexpress_app/utils/whatsapp_contacto.dart';
import 'package:serviexpress_app/utils/invitado_comun.dart';
import 'package:serviexpress_app/screens/guest_tracking_screen.dart';

class GuestDeliveryForm extends StatefulWidget {
  const GuestDeliveryForm({super.key});

  @override
  State<GuestDeliveryForm> createState() => _GuestDeliveryFormState();
}

class _GuestDeliveryFormState extends State<GuestDeliveryForm> {
  static const _estilo = EstiloServicio.paqueteria;

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
    prepararAvisoRespuesta(); // permiso de notificaciones (avisar el precio)
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
      registrarPedidoInvitadoParaAviso((response['id'] as num).toInt());
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

  Widget _campoTelefono(TextEditingController c, String label) => TextFormField(
        controller: c,
        keyboardType: TextInputType.phone,
        textInputAction: TextInputAction.next,
        inputFormatters: formatoWhatsApp,
        decoration: InputDecoration(labelText: label, hintText: 'Ej: 3001234567'),
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
    final c = _estilo.color;
    return Form(
      key: _formKey,
      child: ScaffoldServicioSE(
        estilo: _estilo,
        procesando: _procesando,
        onEnviar: _enviarPedido,
        children: [
          BloqueSE(
            paso: 1,
            titulo: 'Tus datos',
            icono: Icons.person,
            color: c,
            hijos: [
              TextFormField(
                controller: _nombreCtrl,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Nombre y apellido'),
                validator: obligatorioSE('Escribe tu nombre'),
              ),
            ],
          ),
          BloqueSE(
            paso: 2,
            titulo: '¿Dónde recogemos?',
            icono: Icons.storefront,
            color: c,
            hijos: [
              CampoOrigenConLocales(
                controller: _dirOrigenCtrl,
                label: 'Dirección o nombre del local',
                onLocal: _alElegirLocal,
                validator: (v) => _origenLat != null
                    ? null
                    : obligatorioSE('Escribe dónde recogemos o toca "Usar mi ubicación actual"')(v),
              ),
              if (!_origenEsLocal)
                BotonUbicacionSE(
                  guardada: _origenLat != null,
                  color: c,
                  texto: 'Recoger en mi ubicación actual',
                  onUsar: () => _capturarUbicacion(true),
                  onQuitar: () => setState(() {
                    _origenLat = null;
                    _origenLng = null;
                  }),
                ),
              const SizedBox(height: 12),
              _campoTelefono(_telOrigenCtrl, 'WhatsApp / teléfono de quien entrega'),
            ],
          ),
          BloqueSE(
            paso: 3,
            titulo: '¿Dónde entregamos?',
            icono: Icons.flag_rounded,
            color: c,
            hijos: [
              TextFormField(
                controller: _dirDestinoCtrl,
                onChanged: _alEditarDestino,
                decoration: const InputDecoration(
                  labelText: 'Dirección de destino',
                  hintText: 'Ej: Calle 5 # 12-34, barrio Centro',
                ),
                validator: (v) => _destinoLat != null
                    ? null
                    : obligatorioSE('Escribe a dónde lo llevamos o toca "Entregar en mi ubicación actual"')(v),
              ),
              BotonUbicacionSE(
                guardada: _destinoLat != null,
                color: c,
                texto: 'Entregar en mi ubicación actual',
                onUsar: () => _capturarUbicacion(false),
                onQuitar: () => setState(() {
                  _destinoLat = null;
                  _destinoLng = null;
                }),
              ),
              const SizedBox(height: 12),
              _campoTelefono(_telDestinoCtrl, 'WhatsApp / teléfono de quien recibe'),
            ],
          ),
          BloqueSE(
            paso: 4,
            titulo: 'Pago',
            icono: Icons.payments_rounded,
            color: c,
            hijos: [
              DropdownButtonFormField<String>(
                initialValue: _metodoPago,
                decoration: const InputDecoration(labelText: '¿Cómo pagarás?'),
                items: ['Efectivo', 'Transferencia']
                    .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                    .toList(),
                onChanged: (val) => setState(() => _metodoPago = val ?? 'Efectivo'),
              ),
              const SizedBox(height: 12),
              const AvisoCotizacionSE(),
            ],
          ),
        ],
      ),
    );
  }
}
