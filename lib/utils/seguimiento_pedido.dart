// ═══════════════════════════════════════════════════════════════════════════
// SEGUIMIENTO DEL PEDIDO — piezas compartidas (invitado y cliente)
// Diseño oficial (tema_serviexpress.dart). Solo muestran datos; las acciones
// (aprobar, cancelar…) las pasa cada pantalla.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'tema_serviexpress.dart';
import 'whatsapp_contacto.dart';

const List<String> kEstadosActivosPedido = [
  'cotizacion', 'cotizada', 'pendiente', 'en_ruta_origen', 'en_origen',
  'en_ruta_destino', 'problema',
];
const List<String> kEstadosCerradosPedido = [
  'finalizado', 'finalizado_por_demora', 'finalizado_con_problema',
  'cancelado', 'caducado',
];

String pesoSE(dynamic v) {
  final n = (v is num) ? v.toDouble() : double.tryParse('$v') ?? 0;
  return PrecioServicioSE.formatoPeso(n);
}

DateTime? _fecha(dynamic v) =>
    v == null ? null : DateTime.tryParse(v.toString())?.toLocal();

String horaSE(dynamic v) {
  final d = _fecha(v);
  if (d == null) return '';
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final m = d.minute.toString().padLeft(2, '0');
  return '$h:$m ${d.hour < 12 ? 'am' : 'pm'}';
}

/// Texto del pedido sin las marcas internas (⚠️ SOLICITA COTIZACIÓN, tags…).
String detallePedidoSE(Map<String, dynamic> s) {
  var t = (s['observacion'] ?? '').toString();
  t = t.replaceAll('⚠️ SOLICITA COTIZACIÓN | ', '');
  t = t.replaceAll(RegExp(r'\n?\[ ?[✔❌️ ]*(APROBADA|RECHAZADA) POR [A-Z]+ ?\]'), '');
  t = t.replaceAll(RegExp(r'^\[ [A-ZÁÉÍÓÚÑ ]+ \] - ?'), '');
  t = t.replaceAll(RegExp(r'Cotización (aprobada|rechazada) por cliente\.?'), '');
  return t.trim();
}

/// Método de pago escrito en la nota ("PAGO: Efectivo") o en metodo_pago.
String? pagoPedidoSE(Map<String, dynamic> s) {
  final m = RegExp(r'PAGO:\s*([A-Za-záéíóúÁÉÍÓÚ]+)').firstMatch((s['observacion'] ?? '').toString());
  return m?.group(1) ?? s['metodo_pago']?.toString();
}

// ── Precio grande ───────────────────────────────────────────────────────────
class PrecioPedidoSE extends StatelessWidget {
  final Map<String, dynamic> servicio;
  const PrecioPedidoSE({super.key, required this.servicio});

  @override
  Widget build(BuildContext context) {
    final tarifa = (servicio['tarifa'] as num?)?.toDouble() ?? 0;
    final estado = servicio['estado']?.toString() ?? '';
    final esperando = tarifa <= 0 && estado == 'cotizacion';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF161616),
        borderRadius: BorderRadius.circular(kRadioTarjetaSE),
        border: Border.all(color: kVerdeSE.withValues(alpha: 0.45)),
      ),
      child: Row(children: [
        const Text('💵', style: TextStyle(fontSize: 26)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Precio del servicio',
                style: TextStyle(color: Colors.white60, fontSize: 13)),
            Text(
              esperando
                  ? 'La Central te lo dice en un momento…'
                  : (tarifa > 0 ? pesoSE(tarifa) : 'Por definir'),
              style: TextStyle(
                color: Colors.white,
                fontSize: esperando ? 16 : 26,
                fontWeight: FontWeight.w800,
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

// ── Resumen del pedido ──────────────────────────────────────────────────────
class ResumenPedidoSE extends StatelessWidget {
  final Map<String, dynamic> servicio;
  const ResumenPedidoSE({super.key, required this.servicio});

  @override
  Widget build(BuildContext context) {
    final s = servicio;
    final estilo = EstiloServicio.deTipo(s['tipo_servicio']?.toString());
    final detalle = detallePedidoSE(s);
    final pago = pagoPedidoSE(s);
    Widget fila(IconData ic, Color c, String texto, {bool fuerte = false}) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(ic, size: 18, color: c),
            const SizedBox(width: 8),
            Expanded(
              child: Text(texto,
                  style: TextStyle(
                      fontSize: 14,
                      color: Colors.black87,
                      fontWeight: fuerte ? FontWeight.w700 : FontWeight.w400,
                      height: 1.3)),
            ),
          ]),
        );
    return TarjetaSE(
      acento: estilo.color,
      franja: true,
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          EtiquetaSE(estilo.nombreCorto.toUpperCase(), estilo.color),
          const Spacer(),
          if (horaSE(s['created_at']).isNotEmpty)
            Text('Pedido a las ${horaSE(s['created_at'])}',
                style: const TextStyle(fontSize: 12, color: Colors.black45)),
        ]),
        const SizedBox(height: 10),
        fila(Icons.radio_button_checked, estilo.colorIcono, '${s['origen'] ?? ''}'),
        fila(Icons.location_on_rounded, Colors.black45, '${s['destino'] ?? ''}', fuerte: true),
        if (detalle.isNotEmpty) ...[
          const Divider(height: 14),
          fila(Icons.receipt_long_rounded, Colors.black45, detalle),
        ],
        if (pago != null && pago.isNotEmpty)
          fila(Icons.payments_rounded, Colors.black45, 'Pagas en: $pago'),
      ]),
    );
  }
}

// ── Línea de pasos con hora ─────────────────────────────────────────────────
class LineaPasosSE extends StatelessWidget {
  final Map<String, dynamic> servicio;
  const LineaPasosSE({super.key, required this.servicio});

  @override
  Widget build(BuildContext context) {
    final s = servicio;
    final estado = s['estado']?.toString() ?? '';
    final obs = (s['observacion'] ?? '').toString().toUpperCase();
    final fue = (s['tarifa_detalle'] is Map) ? (s['tarifa_detalle']['fuente'] ?? '').toString() : '';
    final pasoPorCotizacion = estado == 'cotizacion' ||
        estado == 'cotizada' ||
        obs.contains('COTIZACIÓN') ||
        fue.contains('cotizacion');
    final cancelado = estado == 'cancelado' || estado == 'caducado';

    // Orden de avance de cada estado
    const orden = {
      'cotizacion': 1, 'cotizada': 2, 'pendiente': 3, 'en_ruta_origen': 4,
      'en_origen': 5, 'en_ruta_destino': 6, 'problema': 6,
      'finalizado': 7, 'finalizado_por_demora': 7, 'finalizado_con_problema': 7,
    };
    final nivel = orden[estado] ?? 0;

    final pasos = <(String, String, int, dynamic)>[
      ('📨', 'Pedido enviado', 0, s['created_at']),
      if (pasoPorCotizacion) ('💬', 'La Central te dio el precio', 2, null),
      if (pasoPorCotizacion) ('👍', 'Aprobaste el precio', 3, s['liberacion_at']),
      if (!pasoPorCotizacion) ('📡', 'Buscando un Móvil', 3, null),
      ('🛵', 'Un Móvil tomó tu pedido', 4, s['accepted_at']),
      ('📍', 'El Móvil llegó al punto de recogida', 5, s['llegada_origen_at']),
      ('🚀', 'En camino al destino', 6, s['picked_up_at']),
      ('🏁', 'Entregado', 7, s['finalizado_at']),
    ];

    return TarjetaSE(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('¿En qué va tu pedido?',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.black87)),
        const SizedBox(height: 10),
        for (int i = 0; i < pasos.length; i++)
          _paso(pasos[i], hecho: !cancelado && nivel >= pasos[i].$3,
              actual: !cancelado && _esActual(pasos, i, nivel),
              ultimo: i == pasos.length - 1),
        if (cancelado)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              const Text('❌', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 10),
              Text(estado == 'caducado' ? 'El pedido venció' : 'Pedido cancelado',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.red)),
            ]),
          ),
      ]),
    );
  }

  bool _esActual(List<(String, String, int, dynamic)> pasos, int i, int nivel) {
    // El paso "actual" es el último ya alcanzado
    if (nivel < pasos[i].$3) return false;
    for (int j = i + 1; j < pasos.length; j++) {
      if (nivel >= pasos[j].$3) return false;
    }
    return nivel < 7;
  }

  Widget _paso((String, String, int, dynamic) p,
      {required bool hecho, required bool actual, required bool ultimo}) {
    final color = hecho ? const Color(0xFF2E7D32) : Colors.black26;
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: 28,
          child: Column(children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: hecho ? const Color(0xFFE8F5E9) : const Color(0xFFF3F4F6),
                shape: BoxShape.circle,
                border: Border.all(color: color, width: actual ? 2.5 : 1.5),
              ),
              child: hecho
                  ? const Icon(Icons.check, size: 14, color: Color(0xFF2E7D32))
                  : null,
            ),
            if (!ultimo)
              Expanded(child: Container(width: 2, color: hecho ? const Color(0xFF81C784) : Colors.black12)),
          ]),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(children: [
              Text(p.$1, style: TextStyle(fontSize: 16, color: hecho ? null : Colors.black26)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(p.$2,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: actual ? FontWeight.w800 : FontWeight.w500,
                      color: hecho ? Colors.black87 : Colors.black38,
                    )),
              ),
              if (hecho && horaSE(p.$4).isNotEmpty)
                Text(horaSE(p.$4), style: const TextStyle(fontSize: 12, color: Colors.black45)),
            ]),
          ),
        ),
      ]),
    );
  }
}

// ── Tarjeta del Móvil: contacto, pagos, tiempo de llegada ───────────────────
class TarjetaMovilSE extends StatefulWidget {
  final Map<String, dynamic> servicio;
  const TarjetaMovilSE({super.key, required this.servicio});

  @override
  State<TarjetaMovilSE> createState() => _TarjetaMovilSEState();
}

class _TarjetaMovilSEState extends State<TarjetaMovilSE> {
  Future<Map<String, dynamic>?>? _futMovil;
  String? _movilCargado;

  Future<Map<String, dynamic>?> _cargar(String movilId) async {
    try {
      final r = await Supabase.instance.client
          .from('usuarios')
          .select('usuario, numero_movil, telefono, puntuacion, rango_movil, '
              'pago_nequi, pago_daviplata, pago_bancolombia, pago_llave')
          .eq('id', movilId)
          .maybeSingle();
      return r;
    } catch (_) {
      return null;
    }
  }

  void _copiar(String app, String valor) {
    Clipboard.setData(ClipboardData(text: valor));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('✅ $app copiado: $valor'),
      duration: const Duration(seconds: 2),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.servicio;
    final movilId = s['movil_id']?.toString();
    if (movilId == null || movilId.isEmpty) return const SizedBox.shrink();
    if (_movilCargado != movilId) {
      _movilCargado = movilId;
      _futMovil = _cargar(movilId);
    }
    final enCurso = ['en_ruta_origen', 'en_origen', 'en_ruta_destino', 'problema']
        .contains(s['estado']?.toString());

    return FutureBuilder<Map<String, dynamic>?>(
      future: _futMovil,
      builder: (context, snap) {
        final m = snap.data;
        if (m == null) {
          return const TarjetaSE(
            padding: EdgeInsets.all(16),
            child: Text('Cargando datos del Móvil…', style: TextStyle(color: Colors.black54)),
          );
        }
        final numero = m['numero_movil']?.toString() ??
            (m['usuario']?.toString() ?? '').replaceAll(RegExp(r'[^0-9]'), '');
        final tel = m['telefono']?.toString() ?? '';
        final punt = (m['puntuacion'] as num?)?.toDouble();
        final rango = m['rango_movil']?.toString();
        final pagos = <(String, Color, Color, String)>[
          if ((m['pago_nequi'] ?? '').toString().trim().isNotEmpty)
            ('Nequi', const Color(0xFFE5007D), Colors.white, m['pago_nequi'].toString().trim()),
          if ((m['pago_daviplata'] ?? '').toString().trim().isNotEmpty)
            ('Daviplata', const Color(0xFFEE2A24), Colors.white, m['pago_daviplata'].toString().trim()),
          if ((m['pago_bancolombia'] ?? '').toString().trim().isNotEmpty)
            ('Bancolombia', const Color(0xFFFFCC00), Colors.black, m['pago_bancolombia'].toString().trim()),
          if ((m['pago_llave'] ?? '').toString().trim().isNotEmpty)
            ('Llave', const Color(0xFF1B5E20), Colors.white, m['pago_llave'].toString().trim()),
        ];

        // Tiempo estimado de llegada (solo mientras va hacia la recogida)
        String? eta;
        final acc = _fecha(s['accepted_at']);
        final mins = (s['tiempo_estimado_minutos'] as num?)?.toInt();
        if (s['estado'] == 'en_ruta_origen' && acc != null && mins != null && mins > 0) {
          final faltan = acc.add(Duration(minutes: mins)).difference(DateTime.now()).inMinutes;
          eta = faltan > 1 ? 'Llega en ~$faltan min' : 'Está por llegar';
        }

        return TarjetaSE(
          acento: kVerdeSE,
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: kVerdeSE.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  border: Border.all(color: kVerdeOscuroSE.withValues(alpha: 0.5)),
                ),
                child: const Icon(Icons.two_wheeler, color: kVerdeOscuroSE, size: 28),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(numero.isNotEmpty ? 'Móvil $numero' : 'Tu Móvil',
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.black87)),
                  Row(children: [
                    if (punt != null) ...[
                      const Icon(Icons.star_rounded, color: Colors.amber, size: 18),
                      Text(' ${punt.toStringAsFixed(1)}',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                      const SizedBox(width: 8),
                    ],
                    if (rango != null && rango.isNotEmpty)
                      Text(rango, style: const TextStyle(fontSize: 12, color: Colors.black54)),
                  ]),
                ]),
              ),
            ]),
            if (eta != null) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFE3EEFC),
                  borderRadius: BorderRadius.circular(kRadioCampoSE),
                ),
                child: Text('⏱️ $eta',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF174A8C))),
              ),
            ],
            if (tel.isNotEmpty && enCurso) ...[
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF25D366),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => abrirChatWhatsApp(tel,
                          texto: 'Hola Móvil $numero, te escribo por el pedido #${s['id']} de ServiExpress.'),
                      icon: const Icon(Icons.chat_rounded, size: 20),
                      label: const Text('WhatsApp', style: TextStyle(fontWeight: FontWeight.w800)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: kVerdeOscuroSE,
                        side: const BorderSide(color: kVerdeOscuroSE, width: 1.5),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () {
                        final u = uriLlamada(tel);
                        if (u != null) launchUrl(u);
                      },
                      icon: const Icon(Icons.phone_rounded, size: 20),
                      label: const Text('Llamar', style: TextStyle(fontWeight: FontWeight.w800)),
                    ),
                  ),
                ),
              ]),
            ],
            if (pagos.isNotEmpty) ...[
              const SizedBox(height: 14),
              const Text('Si pagas por transferencia, págale al Móvil aquí:',
                  style: TextStyle(fontSize: 13, color: Colors.black54)),
              const SizedBox(height: 8),
              for (final p in pagos)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    onTap: () => _copiar(p.$1, p.$4),
                    borderRadius: BorderRadius.circular(kRadioCampoSE),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: kCampoSE,
                        borderRadius: BorderRadius.circular(kRadioCampoSE),
                      ),
                      child: Row(children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(color: p.$2, borderRadius: BorderRadius.circular(6)),
                          child: Text(p.$1,
                              style: TextStyle(color: p.$3, fontWeight: FontWeight.bold, fontSize: 12)),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(p.$4,
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                        ),
                        const Icon(Icons.copy_rounded, size: 18, color: Colors.black45),
                        const SizedBox(width: 4),
                        const Text('Copiar', style: TextStyle(fontSize: 12, color: Colors.black54)),
                      ]),
                    ),
                  ),
                ),
              if (tel.isNotEmpty)
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: const Color(0xFF128C7E)),
                    onPressed: () => abrirChatWhatsApp(tel,
                        texto: 'Hola, te envío el comprobante de pago del pedido #${s['id']} de ServiExpress.'),
                    icon: const Icon(Icons.camera_alt_outlined, size: 20),
                    label: const Text('Enviar comprobante por WhatsApp',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
            ],
          ]),
        );
      },
    );
  }
}

// ── Contacto con la Central ─────────────────────────────────────────────────
class ContactoCentralSE extends StatefulWidget {
  final int? pedidoId;
  const ContactoCentralSE({super.key, this.pedidoId});

  @override
  State<ContactoCentralSE> createState() => _ContactoCentralSEState();
}

class _ContactoCentralSEState extends State<ContactoCentralSE> {
  static Future<String?>? _futTel;

  @override
  void initState() {
    super.initState();
    _futTel ??= () async {
      try {
        final r = await Supabase.instance.client.rpc('fn_contacto_central');
        final t = r?.toString() ?? '';
        return t.isEmpty ? null : t;
      } catch (_) {
        return null;
      }
    }();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _futTel,
      builder: (context, snap) {
        final tel = snap.data;
        if (tel == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white38),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: () => abrirChatWhatsApp(tel,
                  texto: widget.pedidoId != null
                      ? 'Hola Central, te escribo por mi pedido #${widget.pedidoId}.'
                      : 'Hola Central, necesito ayuda con un pedido.'),
              icon: const Icon(Icons.support_agent_rounded, size: 20),
              label: const Text('Hablar con la Central (WhatsApp)',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        );
      },
    );
  }
}

// ── Beneficios de registrarse (para el invitado) ────────────────────────────
class BeneficiosRegistroSE extends StatelessWidget {
  final VoidCallback onRegistrar;
  final bool destacado; // true: más grande (al terminar un pedido)
  const BeneficiosRegistroSE({super.key, required this.onRegistrar, this.destacado = false});

  @override
  Widget build(BuildContext context) {
    Widget item(String emoji, String texto) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(emoji, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(texto,
                  style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.3)),
            ),
          ]),
        );
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: EdgeInsets.all(destacado ? 18 : 16),
      decoration: BoxDecoration(
        color: const Color(0xFF13210F),
        borderRadius: BorderRadius.circular(kRadioTarjetaSE),
        border: Border.all(color: kVerdeSE, width: destacado ? 2 : 1.2),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('🎁', style: TextStyle(fontSize: 26)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              destacado ? '¿Te gustó? Crea tu cuenta GRATIS' : 'Pide más fácil con tu cuenta GRATIS',
              style: TextStyle(
                  color: kVerdeSE, fontSize: destacado ? 20 : 17, fontWeight: FontWeight.w900),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        item('📲', 'Te avisamos en tu celular cuando la Central te dé el precio y cuando el Móvil llegue.'),
        item('🏠', 'Guarda tus direcciones y pide en segundos, sin escribir todo otra vez.'),
        item('🍔', 'Pide directo del menú de los restaurantes y locales de ServiExpress.'),
        item('🧾', 'Todo tu historial de pedidos y el chat con la Central en un solo lugar.'),
        item('⚡', 'Precios ya guardados para tus direcciones de siempre.'),
        const SizedBox(height: 6),
        BotonPrincipalSE(
          texto: 'CREAR MI CUENTA GRATIS',
          icono: Icons.person_add_rounded,
          onPressed: onRegistrar,
        ),
      ]),
    );
  }
}
