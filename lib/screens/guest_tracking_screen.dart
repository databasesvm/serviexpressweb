import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:serviexpress_app/utils/onesignal_api.dart';
import 'package:serviexpress_app/utils/alta_demanda.dart';
import 'package:serviexpress_app/utils/paradero_objetivo.dart';
import 'package:serviexpress_app/utils/errores_servidor.dart';
import 'package:serviexpress_app/utils/tema_serviexpress.dart';
import 'package:serviexpress_app/utils/aviso_cotizacion.dart';
import 'package:serviexpress_app/utils/seguimiento_pedido.dart';
import 'package:serviexpress_app/screens/registro_screen.dart';
import 'package:serviexpress_app/screens/guest_mototaxi_form.dart';
import 'package:serviexpress_app/screens/guest_delivery_form.dart';
import 'package:serviexpress_app/screens/guest_food_form.dart';
import 'package:serviexpress_app/screens/guest_shopping_form.dart';

/// Seguimiento del INVITADO (sin cuenta): todos sus pedidos hechos desde
/// este navegador, con precio, pasos, Móvil (WhatsApp, llamar, pagos),
/// contacto con la Central, cancelar, pedir otra vez y beneficios de
/// registrarse.
class GuestTrackingScreen extends StatefulWidget {
  const GuestTrackingScreen({super.key});

  @override
  State<GuestTrackingScreen> createState() => _GuestTrackingScreenState();
}

class _GuestTrackingScreenState extends State<GuestTrackingScreen> {
  static const _kLista = 'pedidos_invitado';
  static const _kMax = 10;

  bool _cargando = true;
  List<int> _ids = [];
  List<Map<String, dynamic>> _resumenes = []; // para "Mis pedidos"
  int? _idPedido; // pedido que se está viendo
  Stream<List<Map<String, dynamic>>>? _streamServicio;

  // "¿ya califiqué?" por servicio (evita re-consultar en cada redibujo)
  final Map<dynamic, Future<List<Map<String, dynamic>>>> _futureCalifGst = {};

  // Aviso "La Central te respondió" (sonido, vibración, ventana con el precio)
  final VigiaCotizacion _vigiaCotizacion = VigiaCotizacion();

  @override
  void initState() {
    super.initState();
    _cargarPedidos();
  }

  // ── Mis pedidos (guardados en este navegador) ─────────────────────────
  Future<void> _cargarPedidos() async {
    final prefs = await SharedPreferences.getInstance();
    final lista = (prefs.getStringList(_kLista) ?? [])
        .map((e) => int.tryParse(e))
        .whereType<int>()
        .toList();
    final ultimo = prefs.getInt('ultimo_pedido_invitado');
    if (ultimo != null) {
      lista.remove(ultimo);
      lista.insert(0, ultimo);
    }
    final ids = lista.take(_kMax).toList();
    await prefs.setStringList(_kLista, ids.map((e) => '$e').toList());

    List<Map<String, dynamic>> res = [];
    if (ids.isNotEmpty) {
      try {
        res = List<Map<String, dynamic>>.from(await Supabase.instance.client
            .from('servicios')
            .select('id, tipo_servicio, estado, created_at, tarifa')
            .inFilter('id', ids)
            .order('id', ascending: false));
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _ids = ids;
      _resumenes = res;
      _cargando = false;
    });
    if (ids.isNotEmpty) _verPedido(ultimo ?? ids.first);
  }

  void _verPedido(int id) {
    setState(() {
      _idPedido = id;
      _streamServicio = Supabase.instance.client
          .from('servicios')
          .stream(primaryKey: ['id'])
          .eq('id', id)
          .limit(1);
    });
  }

  // ── Aprobar / rechazar el precio ──────────────────────────────────────
  Future<void> _procesarRespuestaCotizacion(
    Map<String, dynamic> servicio,
    bool aprobada,
  ) async {
    try {
      String notaAnterior = servicio['observacion'] ?? '';

      await Supabase.instance.client.from('servicios').update({
        'estado': aprobada ? 'pendiente' : 'cancelado',
        // Al aprobar, el reloj de fases arranca AHORA (tarjetas y servidor).
        if (aprobada) 'liberacion_at': DateTime.now().toUtc().toIso8601String(),
        'observacion': aprobada
            ? '$notaAnterior\n[ ✔️ APROBADA POR INVITADO ]'
            : '$notaAnterior\n[ ❌ RECHAZADA POR INVITADO ]',
      }).eq('id', servicio['id']);

      if (aprobada) {
        final int svcId = servicio['id'] as int;
        await MotorNotificaciones.dispararACentral(
          titulo: '✅ COTIZACIÓN APROBADA (INVITADO)',
          mensaje: 'Invitado aprobó cotización — revisa el radar.',
        );
        // F2 (T+30s) la resuelve el SERVIDOR (se_f2_huecos).
        final String? paraderoObjGst = await paraderoMasCercano(
          (servicio['origen_lat'] as num?)?.toDouble(),
          (servicio['origen_lng'] as num?)?.toDouble(),
        );
        // F1 Masters lo manda el servidor (se_f1_motivo); F3/F4 por se_cascade_t0.
        await Supabase.instance.client
            .from('servicios')
            .update({
              if (paraderoObjGst != null) 'paradero_origen': paraderoObjGst,
              'se_cascade_t0': DateTime.now().toUtc().toIso8601String(),
              'se_f3_enviado': false,
              'se_f4_enviado': false,
              'se_f1_motivo': 'nuevo',
            })
            .eq('id', svcId);
      }
    } catch (_) {}
  }

  // ── Cancelar (solo mientras ningún Móvil lo ha tomado) ────────────────
  Future<void> _cancelar(Map<String, dynamic> s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadioTarjetaSE)),
        title: const Text('¿Cancelar tu pedido?', style: TextStyle(fontWeight: FontWeight.w800)),
        content: const Text('Si lo cancelas, la Central y los Móviles dejan de buscarlo.',
            style: TextStyle(fontSize: 15)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('NO, SEGUIR', style: TextStyle(color: Colors.black54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red[700], foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('SÍ, CANCELAR', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Supabase.instance.client
          .from('servicios')
          .update({
            'estado': 'cancelado',
            'observacion': '${s['observacion'] ?? ''}\n[ ❌ CANCELADO POR INVITADO ]',
          })
          .eq('id', s['id'])
          .isFilter('movil_id', null); // si un Móvil ya lo tomó, no se cancela
      try {
        await MotorNotificaciones.dispararACentral(
          titulo: '❌ PEDIDO CANCELADO (INVITADO)',
          mensaje: 'El invitado canceló el pedido #${s['id']}.',
        );
      } catch (_) {}
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Pedido cancelado.'),
          backgroundColor: Colors.black87,
        ));
      }
      _refrescarResumen();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(textoError(e)),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  Future<void> _refrescarResumen() async {
    if (_ids.isEmpty) return;
    try {
      final res = List<Map<String, dynamic>>.from(await Supabase.instance.client
          .from('servicios')
          .select('id, tipo_servicio, estado, created_at, tarifa')
          .inFilter('id', _ids)
          .order('id', ascending: false));
      if (mounted) setState(() => _resumenes = res);
    } catch (_) {}
  }

  // ── Pedir otra vez lo mismo (formulario ya lleno) ─────────────────────
  Future<void> _pedirOtraVez(Map<String, dynamic> s) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('guest_ultima_origen', (s['origen'] ?? '').toString());
    await prefs.setString('guest_ultimo_destino', (s['destino'] ?? '').toString());
    final lat = (s['origen_lat'] as num?)?.toDouble();
    final lng = (s['origen_lng'] as num?)?.toDouble();
    if (lat != null && lng != null) {
      await prefs.setDouble('guest_ultima_origen_lat', lat);
      await prefs.setDouble('guest_ultima_origen_lng', lng);
    } else {
      await prefs.remove('guest_ultima_origen_lat');
      await prefs.remove('guest_ultima_origen_lng');
    }
    final dlat = (s['destino_lat'] as num?)?.toDouble();
    final dlng = (s['destino_lng'] as num?)?.toDouble();
    if (dlat != null && dlng != null) {
      await prefs.setDouble('guest_ultimo_destino_lat', dlat);
      await prefs.setDouble('guest_ultimo_destino_lng', dlng);
    } else {
      await prefs.remove('guest_ultimo_destino_lat');
      await prefs.remove('guest_ultimo_destino_lng');
    }
    if (!mounted) return;
    final tipo = (s['tipo_servicio'] ?? '').toString().toUpperCase();
    final Widget form = tipo.contains('MOTO')
        ? const GuestMototaxiForm()
        : tipo.contains('COMIDA')
            ? const GuestFoodForm()
            : tipo.contains('COMPRA')
                ? const GuestShoppingForm()
                : const GuestDeliveryForm();
    Navigator.push(context, MaterialPageRoute(builder: (_) => form));
  }

  void _irRegistro() =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => const RegistroScreen(soloCliente: true)));

  // ── Calificación (invitado: calificador_id = null) ────────────────────
  void _mostrarDialogoCalificacionInvitado(Map<String, dynamic> servicio) {
    int estrellas = 5;
    final comentarioCtrl = TextEditingController();
    bool procesando = false;

    final String nombreInvitado = () {
      final creador = servicio['creador']?.toString() ?? '';
      if (creador.toLowerCase().startsWith('invitado:')) {
        return creador.substring('invitado:'.length).trim();
      }
      return 'Invitado';
    }();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadioTarjetaSE)),
          title: const Text('¿Cómo estuvo tu servicio?',
              style: TextStyle(fontWeight: FontWeight.w800), textAlign: TextAlign.center),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (index) {
                  return IconButton(
                    iconSize: 40,
                    padding: EdgeInsets.zero,
                    icon: Icon(
                      index < estrellas ? Icons.star : Icons.star_border,
                      color: Colors.amber[600],
                    ),
                    onPressed: () => setDialogState(() => estrellas = index + 1),
                  );
                }),
              ),
              const SizedBox(height: 12),
              Theme(
                data: temaFormularioSE(ctx, kVerdeSE),
                child: TextField(
                  controller: comentarioCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Comentario (opcional)',
                    hintText: 'Ej: Muy rápido y amable',
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: procesando ? null : () => Navigator.pop(ctx),
              child: const Text('CERRAR', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: kVerdeSE, foregroundColor: Colors.black),
              onPressed: procesando
                  ? null
                  : () async {
                      setDialogState(() => procesando = true);
                      try {
                        final movilId = servicio['movil_id'];
                        await Supabase.instance.client.from('calificaciones').upsert({
                          'servicio_id': servicio['id'],
                          if (movilId != null) 'movil_id': movilId.toString(),
                          'calificador_tipo': 'invitado',
                          'calificador_id': null,
                          'calificador_nombre': nombreInvitado,
                          'estrellas': estrellas,
                          'comentario': comentarioCtrl.text.trim().isEmpty
                              ? null
                              : comentarioCtrl.text.trim(),
                        }, onConflict: 'servicio_id, calificador_tipo');
                        _futureCalifGst.remove(servicio['id']);
                        if (mounted) setState(() {});
                        if (movilId != null) {
                          await Supabase.instance.client.rpc(
                            'recalcular_puntuacion_movil',
                            params: {'p_movil_id': movilId.toString()},
                          );
                        }
                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('¡Gracias por tu calificación!'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      } catch (e) {
                        setDialogState(() => procesando = false);
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(content: Text(textoError(e))),
                          );
                        }
                      }
                    },
              child: procesando
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                  : const Text('ENVIAR', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  // ── Tarjeta del estado (mensaje claro + acciones) ─────────────────────
  Widget _estadoVisual(Map<String, dynamic> s) {
    final estado = s['estado']?.toString() ?? '';
    Color color = Colors.grey;
    String titulo = '';
    String desc = '';
    IconData icono = Icons.help_outline;
    Widget? acciones;

    switch (estado) {
      case 'cotizacion':
        color = Colors.orange[800]!;
        titulo = 'ESPERANDO EL PRECIO';
        desc = 'La Central está calculando el precio de tu pedido. Te avisamos aquí mismo.';
        icono = Icons.calculate_outlined;
        break;
      case 'cotizada':
        color = Colors.blue[800]!;
        titulo = '¡YA TIENES PRECIO!';
        desc = 'Precio: ${pesoSE(s['tarifa'])}. ¿Lo apruebas para enviar el Móvil?';
        icono = Icons.monetization_on_outlined;
        acciones = Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Column(children: [
            BotonPrincipalSE(
              texto: 'APROBAR Y PEDIR',
              icono: Icons.check_rounded,
              onPressed: () => _procesarRespuestaCotizacion(s, true),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red[700],
                  side: BorderSide(color: Colors.red[300]!),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () => _procesarRespuestaCotizacion(s, false),
                child: const Text('RECHAZAR', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ]),
        );
        break;
      case 'pendiente':
        final directo = (s['exclusivo_id']?.toString().trim() ?? '').isNotEmpty;
        color = directo ? Colors.blue[600]! : Colors.black54;
        titulo = directo ? 'MÓVIL ASIGNADO' : 'BUSCANDO TU MÓVIL';
        desc = directo
            ? 'Ya hay un Móvil asignado. Esperando que lo confirme…'
            : 'Tu pedido ya está en el radar. Buscando el Móvil más cercano…';
        icono = directo ? Icons.assignment_ind_rounded : Icons.radar;
        break;
      case 'en_ruta_origen':
        color = Colors.blue[600]!;
        titulo = 'MÓVIL EN CAMINO';
        desc = 'El Móvil va hacia el punto de recogida.';
        icono = Icons.two_wheeler;
        break;
      case 'en_origen':
        color = Colors.orange[600]!;
        titulo = 'EL MÓVIL LLEGÓ';
        desc = 'El Móvil está en el punto de recogida.';
        icono = Icons.storefront;
        break;
      case 'en_ruta_destino':
        color = kVerdeOscuroSE;
        titulo = 'EN CAMINO AL DESTINO';
        desc = '¡Todo listo! El Móvil va hacia la entrega.';
        icono = Icons.two_wheeler;
        break;
      case 'problema':
        color = Colors.red[800]!;
        titulo = 'HUBO UNA NOVEDAD';
        desc = 'Se presentó un retraso o inconveniente. Escríbele al Móvil o a la Central.';
        icono = Icons.warning_amber_rounded;
        break;
      case 'finalizado':
      case 'finalizado_por_demora':
      case 'finalizado_con_problema':
        color = Colors.green[700]!;
        titulo = '¡PEDIDO ENTREGADO!';
        desc = 'Gracias por confiar en ServiExpress.';
        icono = Icons.check_circle_outline;
        break;
      case 'cancelado':
      case 'caducado':
        color = Colors.grey[700]!;
        titulo = 'PEDIDO CERRADO';
        desc = 'Este pedido fue cancelado o venció.';
        icono = Icons.block_rounded;
        break;
    }

    final puedeCancelar = ['cotizacion', 'cotizada', 'pendiente'].contains(estado) &&
        (s['movil_id'] == null || s['movil_id'].toString().isEmpty);

    return TarjetaSE(
      acento: color,
      padding: const EdgeInsets.all(20),
      child: Column(children: [
        Container(
          width: 84,
          height: 84,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
          child: Icon(icono, size: 46, color: color),
        ),
        const SizedBox(height: 12),
        Text(titulo,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: color, letterSpacing: 0.5)),
        const SizedBox(height: 8),
        Text(desc,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 15, color: Colors.black54, height: 1.4)),
        if (acciones != null) acciones,
        if (puedeCancelar)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: TextButton(
              onPressed: () => _cancelar(s),
              style: TextButton.styleFrom(foregroundColor: Colors.red[700], minimumSize: const Size(48, 44)),
              child: const Text('Cancelar mi pedido',
                  style: TextStyle(fontSize: 14, decoration: TextDecoration.underline)),
            ),
          ),
      ]),
    );
  }

  // ── Calificar (solo finalizado con Móvil) ─────────────────────────────
  Widget _calificar(Map<String, dynamic> s) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _futureCalifGst[s['id']] ??= Supabase.instance.client
          .from('calificaciones')
          .select('estrellas')
          .eq('servicio_id', s['id'])
          .eq('calificador_tipo', 'invitado'),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) return const SizedBox.shrink();
        final ya = snap.hasData && snap.data!.isNotEmpty;
        if (ya) {
          final n = snap.data!.first['estrellas'] as int;
          return TarjetaSE(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(children: [
              const Text('Tu calificación:', style: TextStyle(fontWeight: FontWeight.w700)),
              const Spacer(),
              ...List.generate(5, (i) => Icon(i < n ? Icons.star : Icons.star_border,
                  color: Colors.amber, size: 22)),
            ]),
          );
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber[400],
                foregroundColor: Colors.black,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: () => _mostrarDialogoCalificacionInvitado(s),
              icon: const Icon(Icons.star_rate_rounded),
              label: const Text('CALIFICAR AL MÓVIL', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
        );
      },
    );
  }

  // ── "Mis pedidos" (chips para cambiar de pedido) ──────────────────────
  Widget _misPedidos() {
    if (_resumenes.length < 2) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('MIS PEDIDOS',
            style: TextStyle(color: Colors.white60, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1)),
        const SizedBox(height: 8),
        SizedBox(
          height: 64,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _resumenes.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final r = _resumenes[i];
              final id = (r['id'] as num).toInt();
              final activo = kEstadosActivosPedido.contains(r['estado']);
              final sel = id == _idPedido;
              final est = EstiloServicio.deTipo(r['tipo_servicio']?.toString());
              return InkWell(
                onTap: () => _verPedido(id),
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: sel ? Colors.white : const Color(0xFF161616),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: sel ? est.color : Colors.white24, width: sel ? 2 : 1),
                  ),
                  child: Row(children: [
                    Icon(est.icono, color: est.colorIcono, size: 22),
                    const SizedBox(width: 8),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text('#$id ${est.nombreCorto}',
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13,
                              color: sel ? Colors.black87 : Colors.white)),
                      Text(activo ? '● En curso' : (r['estado'] == 'cancelado' ? 'Cancelado' : 'Terminado'),
                          style: TextStyle(fontSize: 12,
                              color: activo ? const Color(0xFF2E7D32) : (sel ? Colors.black45 : Colors.white54))),
                    ]),
                  ]),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final margen = margenSE(context);
    return Scaffold(
      backgroundColor: kFondoSE,
      appBar: AppBar(
        backgroundColor: kFondoSE,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Mis pedidos',
            style: TextStyle(color: Colors.white70, fontSize: 15, fontWeight: FontWeight.w600)),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: kVerdeSE))
          : _idPedido == null
              ? ContenidoSE(
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(margen, 20, margen, 24),
                    children: [
                      const Icon(Icons.inbox_rounded, color: Colors.white24, size: 64),
                      const SizedBox(height: 12),
                      const Text('Todavía no tienes pedidos en este celular.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white70, fontSize: 16)),
                      const SizedBox(height: 24),
                      BeneficiosRegistroSE(onRegistrar: _irRegistro),
                    ],
                  ),
                )
              : StreamBuilder<List<Map<String, dynamic>>>(
                  stream: _streamServicio,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator(color: kVerdeSE));
                    }
                    if (!snapshot.hasData || snapshot.data!.isEmpty) {
                      return const Center(
                        child: Text('No encontramos este pedido.',
                            style: TextStyle(color: Colors.white60)),
                      );
                    }
                    final s = snapshot.data!.first;
                    final estado = s['estado']?.toString() ?? '';
                    final estilo = EstiloServicio.deTipo(s['tipo_servicio']?.toString());
                    final cerrado = kEstadosCerradosPedido.contains(estado);
                    final terminadoBien = estado.startsWith('finalizado');
                    final conMovil = (s['movil_id']?.toString() ?? '').isNotEmpty;

                    _vigiaCotizacion.revisar(context, [s], onResponder: _procesarRespuestaCotizacion);

                    return ContenidoSE(
                      child: RefreshIndicator(
                        color: kVerdeSE,
                        onRefresh: _refrescarResumen,
                        child: ListView(
                          padding: EdgeInsets.fromLTRB(margen, 4, margen, 28),
                          children: [
                            _misPedidos(),
                            EncabezadoSE(
                              icono: estilo.icono,
                              color: estilo.color,
                              titulo: estilo.nombreCorto,
                              subtitulo: 'Pedido #${s['id']}',
                            ),
                            const SizedBox(height: 16),
                            if (!cerrado) const BannerAltaDemanda(margin: EdgeInsets.only(bottom: 12)),
                            // 1) Estado con mensaje claro y acciones
                            _estadoVisual(s),
                            // 2) Precio siempre a la vista
                            if (estado != 'cancelado') PrecioPedidoSE(servicio: s),
                            // 3) El Móvil: WhatsApp, llamar, pagos, tiempo de llegada
                            if (conMovil && estado != 'cancelado') TarjetaMovilSE(servicio: s),
                            // 4) En qué va
                            LineaPasosSE(servicio: s),
                            // 5) Qué pidió
                            ResumenPedidoSE(servicio: s),
                            // Al terminar: calificar y pedir otra vez
                            if (terminadoBien && conMovil) _calificar(s),
                            if (cerrado)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 14),
                                child: BotonPrincipalSE(
                                  texto: 'PEDIR OTRA VEZ LO MISMO',
                                  color: estilo.color,
                                  icono: Icons.replay_rounded,
                                  onPressed: () => _pedirOtraVez(s),
                                ),
                              ),
                            // Ayuda de la Central
                            ContactoCentralSE(pedidoId: (s['id'] as num?)?.toInt()),
                            // Beneficios de crear cuenta (más grande al terminar)
                            BeneficiosRegistroSE(onRegistrar: _irRegistro, destacado: cerrado),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
