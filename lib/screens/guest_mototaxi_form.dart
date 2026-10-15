import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:serviexpress_app/utils/onesignal_api.dart';
import 'package:serviexpress_app/utils/whatsapp_contacto.dart';
import 'package:serviexpress_app/utils/invitado_comun.dart';
import 'package:serviexpress_app/screens/guest_tracking_screen.dart';
import 'package:serviexpress_app/utils/paradero_objetivo.dart';

class GuestMototaxiForm extends StatefulWidget {
  const GuestMototaxiForm({super.key});

  @override
  State<GuestMototaxiForm> createState() => _GuestMototaxiFormState();
}

class _GuestMototaxiFormState extends State<GuestMototaxiForm> {
  static const _estilo = EstiloServicioInvitado.mototaxi;

  final _formKey = GlobalKey<FormState>();
  bool _procesando = false;

  final _nombreCtrl = TextEditingController();
  final _telPasajeroCtrl = TextEditingController();
  final _origenCtrl = TextEditingController();
  final _destinoCtrl = TextEditingController();

  double? _origenLat;
  double? _origenLng;
  bool _origenEsLocal = false;

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
        if (_telPasajeroCtrl.text.isEmpty) _telPasajeroCtrl.text = c.telefono ?? '';
        final origen = prefs.getString('guest_ultima_origen');
        if (origen != null && _origenCtrl.text.isEmpty) {
          _origenCtrl.text = origen;
          _origenLat = prefs.getDouble('guest_ultima_origen_lat');
          _origenLng = prefs.getDouble('guest_ultima_origen_lng');
        }
        final destino = prefs.getString('guest_ultimo_destino');
        if (destino != null && _destinoCtrl.text.isEmpty) _destinoCtrl.text = destino;
      });
    } catch (_) {}
  }

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

  Future<void> _capturarUbicacion() async {
    final pos = await gpsInvitado(context);
    if (pos == null || !mounted) return;
    setState(() {
      _origenLat = pos.latitude;
      _origenLng = pos.longitude;
      _origenEsLocal = false;
    });
  }

  Future<void> _enviarPedido() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _procesando = true);

    try {
      final tel = normalizarWhatsApp(_telPasajeroCtrl.text);
      final origen = _origenCtrl.text.trim().isNotEmpty
          ? _origenCtrl.text.trim().toUpperCase()
          : 'UBICACIÓN GPS DEL CLIENTE';
      final notaFinal =
          '⚠️ SOLICITA COTIZACIÓN | [ MOTOTAXI ] - PAGO: $_metodoPago | 📱 Pasajero: $tel';

      // Paradero más cercano al punto de recogida (para la F2 cuando se apruebe)
      final String? paraderoObjetivo = await paraderoMasCercano(_origenLat, _origenLng);

      // Igual que los demás formularios: nace como COTIZACIÓN. Al aprobarla
      // el invitado (guest_tracking) arranca la cascada SE completa.
      final response = await Supabase.instance.client
          .from('servicios')
          .insert({
            'creador': 'Invitado: ${_nombreCtrl.text.trim()}',
            'tipo_servicio': 'MOTOTAXI',
            'origen': origen,
            'destino': _destinoCtrl.text.trim().toUpperCase(),
            'origen_lat': _origenLat,
            'origen_lng': _origenLng,
            // El pasajero → botón "WA Cliente" en la tarjeta del móvil
            'telefono_receptor': tel,
            'tarifa': 0.0,
            'tarifa_detalle': {'total': 0.0, 'fuente': 'invitado_cotizacion'},
            'observacion': notaFinal,
            'estado': 'cotizacion',
            if (paraderoObjetivo != null) 'paradero_origen': paraderoObjetivo,
          })
          .select('id')
          .single();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('ultimo_pedido_invitado', response['id']);
      prefs.setString('guest_ultima_origen', _origenCtrl.text.trim().toUpperCase());
      if (_origenLat != null) {
        prefs.setDouble('guest_ultima_origen_lat', _origenLat!);
        prefs.setDouble('guest_ultima_origen_lng', _origenLng!);
      } else {
        prefs.remove('guest_ultima_origen_lat');
        prefs.remove('guest_ultima_origen_lng');
      }
      prefs.setString('guest_ultimo_destino', _destinoCtrl.text.trim().toUpperCase());
      await guardarContactoInvitado(_nombreCtrl.text, _telPasajeroCtrl.text);

      try {
        await MotorNotificaciones.dispararACentral(
          titulo: '🛵 MOTOTAXI INVITADO',
          mensaje: '${_nombreCtrl.text.trim()} → ${_destinoCtrl.text.trim().toUpperCase()}',
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
    final c = _estilo.color;
    // El verde de la marca es muy claro para íconos sobre blanco: se usa un
    // verde más oscuro solo para el ícono del GPS.
    const iconoGps = Color(0xFF1E8E00);
    return Form(
      key: _formKey,
      child: ScaffoldInvitado(
        estilo: _estilo,
        procesando: _procesando,
        onEnviar: _enviarPedido,
        children: [
          BloqueInvitado(
            paso: 1,
            titulo: 'Datos del pasajero',
            icono: Icons.person,
            color: c,
            hijos: [
              TextFormField(
                controller: _nombreCtrl,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Nombre y apellido'),
                validator: validarRequerido,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _telPasajeroCtrl,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                inputFormatters: formatoWhatsApp,
                decoration: const InputDecoration(
                  labelText: 'Tu WhatsApp / teléfono',
                  helperText: 'Ej: 3001234567 — el conductor te escribe aquí',
                ),
                validator: validarTelefonoInvitado,
              ),
            ],
          ),
          BloqueInvitado(
            paso: 2,
            titulo: 'Ruta del viaje',
            icono: Icons.route_rounded,
            color: c,
            hijos: [
              CampoOrigenConLocales(
                controller: _origenCtrl,
                label: 'Punto de recogida',
                onLocal: _alElegirLocal,
                // Con GPS guardado la dirección escrita es opcional
                validator: (v) => _origenLat != null ? null : validarRequerido(v),
                suffixIcon: IconButton(
                  tooltip: 'Usar mi ubicación actual',
                  icon: const Icon(Icons.my_location, color: iconoGps),
                  onPressed: _capturarUbicacion,
                ),
              ),
              if (_origenLat != null && !_origenEsLocal)
                chipGpsGuardado(onQuitar: () => setState(() {
                      _origenLat = null;
                      _origenLng = null;
                    })),
              const SizedBox(height: 12),
              TextFormField(
                controller: _destinoCtrl,
                decoration: const InputDecoration(labelText: 'Punto de destino'),
                validator: validarRequerido,
              ),
            ],
          ),
          BloqueInvitado(
            paso: 3,
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
              const AvisoCotizacionInvitado(),
            ],
          ),
        ],
      ),
    );
  }
}
