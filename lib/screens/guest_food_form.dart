import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:serviexpress_app/utils/onesignal_api.dart';
import 'package:serviexpress_app/utils/whatsapp_contacto.dart';
import 'package:serviexpress_app/utils/invitado_comun.dart';
import 'package:serviexpress_app/screens/guest_tracking_screen.dart';

class GuestFoodForm extends StatefulWidget {
  const GuestFoodForm({super.key});

  @override
  State<GuestFoodForm> createState() => _GuestFoodFormState();
}

class _GuestFoodFormState extends State<GuestFoodForm> {
  static const _estilo = EstiloServicio.comida;

  final _formKey = GlobalKey<FormState>();
  bool _procesando = false;

  final _nombreCtrl = TextEditingController();
  final _restauranteCtrl = TextEditingController();
  final _destinoCtrl = TextEditingController();
  final _pedidoCtrl = TextEditingController();
  final _telContactoCtrl = TextEditingController();

  // Ubicación GPS del destino (se borra si el invitado cambia la dirección)
  double? _destinoLat;
  double? _destinoLng;
  // Local registrado elegido en el origen (con su ubicación exacta)
  LocalRegistrado? _local;

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
        if (_telContactoCtrl.text.isEmpty) _telContactoCtrl.text = c.telefono ?? '';
        final origen = prefs.getString('guest_ultima_origen');
        if (origen != null && _restauranteCtrl.text.isEmpty) _restauranteCtrl.text = origen;
        final destino = prefs.getString('guest_ultimo_destino');
        if (destino != null && _destinoCtrl.text.isEmpty) {
          _destinoCtrl.text = destino;
          _destinoLat = prefs.getDouble('guest_ultimo_destino_lat');
          _destinoLng = prefs.getDouble('guest_ultimo_destino_lng');
        }
      });
    } catch (_) {}
  }

  // Si el invitado cambia la dirección escrita, el GPS guardado deja de servir
  void _alEditarDestino(String _) {
    if (_destinoLat == null) return;
    setState(() {
      _destinoLat = null;
      _destinoLng = null;
    });
  }

  Future<void> _capturarDestinoGps() async {
    final pos = await gpsInvitado(context);
    if (pos == null || !mounted) return;
    setState(() {
      _destinoLat = pos.latitude;
      _destinoLng = pos.longitude;
    });
  }

  Future<void> _enviarPedido() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _procesando = true);

    try {
      final tel = normalizarWhatsApp(_telContactoCtrl.text);
      final destino = _destinoCtrl.text.trim().isNotEmpty
          ? _destinoCtrl.text.trim().toUpperCase()
          : 'UBICACIÓN GPS DEL CLIENTE';
      final notaFinal =
          '⚠️ SOLICITA COTIZACIÓN | [ COMIDA ] - 🍔 PEDIDO:\n${_pedidoCtrl.text.trim()}\n---\n📞 Contacto: $tel | PAGO: $_metodoPago';

      // Nace como cotización. Al aprobarla el invitado (guest_tracking)
      // arranca la cascada SE completa.
      final response = await Supabase.instance.client
          .from('servicios')
          .insert({
            'creador': 'Invitado: ${_nombreCtrl.text.trim()}',
            'tipo_servicio': 'COMIDA',
            'origen': _restauranteCtrl.text.trim().toUpperCase(),
            if (_local?.lat != null) 'origen_lat': _local!.lat,
            if (_local?.lng != null) 'origen_lng': _local!.lng,
            'destino': destino,
            'destino_lat': _destinoLat,
            'destino_lng': _destinoLng,
            // GPS del invitado = ubicación exacta (VER MAPA para el móvil)
            if (_destinoLat != null)
              'destino_gps_at': DateTime.now().toUtc().toIso8601String(),
            // WhatsApp del cliente → botón "WA Cliente" en la tarjeta del móvil
            'telefono_receptor': tel,
            'tarifa': 0.0,
            'tarifa_detalle': {'total': 0.0, 'fuente': 'invitado'},
            'observacion': notaFinal,
            'estado': 'cotizacion',
          })
          .select('id')
          .single();

      // Recordar para el próximo pedido
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('ultimo_pedido_invitado', response['id']);
      prefs.setString('guest_ultima_origen', _restauranteCtrl.text.trim().toUpperCase());
      prefs.setString('guest_ultimo_destino', _destinoCtrl.text.trim().toUpperCase());
      if (_destinoLat != null) {
        prefs.setDouble('guest_ultimo_destino_lat', _destinoLat!);
        prefs.setDouble('guest_ultimo_destino_lng', _destinoLng!);
      } else {
        prefs.remove('guest_ultimo_destino_lat');
        prefs.remove('guest_ultimo_destino_lng');
      }
      await guardarContactoInvitado(_nombreCtrl.text, _telContactoCtrl.text);

      try {
        await MotorNotificaciones.dispararACentral(
          titulo: '🍔 COMIDA INVITADO',
          mensaje: '${_nombreCtrl.text.trim()} → ${_restauranteCtrl.text.trim().toUpperCase()}',
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
    _restauranteCtrl.dispose();
    _destinoCtrl.dispose();
    _pedidoCtrl.dispose();
    _telContactoCtrl.dispose();
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
                decoration: const InputDecoration(labelText: 'Tu nombre'),
                validator: obligatorioSE('Escribe tu nombre'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _telContactoCtrl,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                inputFormatters: formatoWhatsApp,
                decoration: const InputDecoration(
                  labelText: 'Tu WhatsApp / teléfono',
                  helperText: 'Ej: 3001234567 — el Móvil te escribe aquí',
                ),
                validator: validarTelefonoInvitado,
              ),
            ],
          ),
          BloqueSE(
            paso: 2,
            titulo: '¿Qué pedimos y dónde?',
            icono: Icons.restaurant,
            color: c,
            hijos: [
              CampoOrigenConLocales(
                controller: _restauranteCtrl,
                label: 'Restaurante',
                onLocal: (l) => _local = l,
                validator: obligatorioSE('Escribe el nombre del restaurante'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _pedidoCtrl,
                minLines: 3,
                maxLines: 6,
                decoration: const InputDecoration(
                  labelText: '¿Qué vas a pedir?',
                  hintText: 'Ej: 2 hamburguesas sencillas, 1 gaseosa 1.5L',
                  alignLabelWithHint: true,
                ),
                validator: obligatorioSE('Escribe qué vas a pedir'),
              ),
            ],
          ),
          BloqueSE(
            paso: 3,
            titulo: '¿Dónde lo entregamos?',
            icono: Icons.home_rounded,
            color: c,
            hijos: [
              TextFormField(
                controller: _destinoCtrl,
                onChanged: _alEditarDestino,
                decoration: const InputDecoration(
                  labelText: 'Dirección donde recibes',
                  hintText: 'Ej: Calle 5 # 12-34, barrio Centro',
                ),
                // Con GPS guardado la dirección escrita es opcional
                validator: (v) => _destinoLat != null
                    ? null
                    : obligatorioSE('Escribe la dirección o toca "Usar mi ubicación actual"')(v),
              ),
              BotonUbicacionSE(
                guardada: _destinoLat != null,
                color: c,
                onUsar: _capturarDestinoGps,
                onQuitar: () => setState(() {
                  _destinoLat = null;
                  _destinoLng = null;
                }),
              ),
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
