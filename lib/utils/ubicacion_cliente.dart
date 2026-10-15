// lib/utils/ubicacion_cliente.dart
//
// "Pedir ubicación por WhatsApp": el cliente abre un enlace (con código
// secreto por servicio), comparte su GPS y queda guardado en el servicio
// (destino_lat/lng + precisión). Aquí están:
//   • pedirUbicacionCliente(): abre WhatsApp (directo al teléfono del
//     servicio si lo hay) y marca que se pidió (destino_gps_pedido_at).
//   • IndicadorUbicacionCliente: etiqueta "esperando / exacta / aproximada /
//     poco precisa" para el local, la central y el móvil.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'whatsapp_contacto.dart';

const String _urlCaptura =
    'https://oukiofdtargjrclualgm.supabase.co/functions/v1/capturar-ubicacion';

/// WhatsApp del cliente (receptor o cliente): número "57..." o usuario
/// "@usuario". Null si no hay.
String? telefonoWhatsAppServicio(Map<String, dynamic> servicio) {
  for (final campo in ['telefono_receptor', 'numero_cliente']) {
    final crudo = servicio[campo]?.toString().trim() ?? '';
    if (esUsuarioWhatsApp(crudo) && crudo != 'null') return crudo;
    final d = crudo.replaceAll(RegExp(r'[^0-9]'), '');
    if (d.length == 10 && d.startsWith('3')) return '57$d';
    if (d.length == 12 && d.startsWith('57')) return d;
  }
  return null;
}

Future<void> pedirUbicacionCliente(Map<String, dynamic> servicio) async {
  final id = servicio['id'];
  String? token = servicio['ubicacion_token']?.toString();
  final db = Supabase.instance.client;
  if (token == null || token.isEmpty) {
    try {
      final r = await db
          .from('servicios')
          .select('ubicacion_token')
          .eq('id', id)
          .maybeSingle();
      token = r?['ubicacion_token']?.toString();
    } catch (_) {}
  }
  if (token == null || token.isEmpty) return;

  final link = '$_urlCaptura?id=$id&t=$token';
  final texto = 'Hola 👋 Para que el conductor llegue exactamente donde estás, '
      'activa el GPS de tu teléfono, toca este enlace y luego el botón verde '
      '(solo tarda unos segundos):\n$link';
  final tel = telefonoWhatsAppServicio(servicio);
  final uri = uriWhatsApp(tel, texto: texto) ??
      Uri.parse('https://wa.me/?text=${Uri.encodeComponent(texto)}');

  // Marca que se pidió → el card muestra "Esperando ubicación del cliente…"
  try {
    await db
        .from('servicios')
        .update({'destino_gps_pedido_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', id);
  } catch (_) {}

  // Con número/@usuario: en computador abre WhatsApp Web en la pestaña de
  // ServiExpress. Sin número: el selector de chats de WhatsApp.
  if (tel != null) {
    await abrirChatWhatsApp(tel, texto: texto);
  } else if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

/// Etiqueta del estado de la ubicación del cliente. No dibuja nada si nunca
/// se pidió ni se recibió.
class IndicadorUbicacionCliente extends StatelessWidget {
  final Map<String, dynamic> servicio;
  final bool oscuro; // fondo oscuro (app del móvil / central)
  final VoidCallback? onVerMapa;
  const IndicadorUbicacionCliente(this.servicio,
      {super.key, this.oscuro = false, this.onVerMapa});

  @override
  Widget build(BuildContext context) {
    final recibida = servicio['destino_gps_at'] != null ||
        servicio['destino_gps_guardada'] == true;
    final pedida = servicio['destino_gps_pedido_at'] != null;
    if (!recibida && !pedida) return const SizedBox.shrink();

    late final Color color;
    late final IconData icono;
    late final String texto;
    if (!recibida) {
      color = Colors.blueGrey;
      icono = Icons.hourglass_top_rounded;
      texto = 'Esperando ubicación del cliente…';
    } else {
      final p = (servicio['destino_gps_precision'] as num?)?.toInt();
      if (servicio['destino_gps_guardada'] == true) {
        // Tomada de un pedido anterior del mismo cliente a la misma dirección
        color = const Color(0xFF2E7D32);
        icono = Icons.bookmark_added_rounded;
        texto = 'Ubicación GUARDADA del cliente${p != null ? ' ±$p m' : ''} (pedido anterior)';
      } else if (p == null) {
        color = Colors.orange;
        icono = Icons.location_on;
        texto = 'Ubicación del cliente recibida (precisión desconocida)';
      } else if (p <= 50) {
        color = const Color(0xFF2E7D32);
        icono = Icons.location_on;
        texto = 'Ubicación del cliente: EXACTA ±$p m';
      } else if (p <= 150) {
        color = Colors.orange[800]!;
        icono = Icons.location_on;
        texto = 'Ubicación del cliente: APROXIMADA ±$p m';
      } else {
        color = Colors.red[700]!;
        icono = Icons.warning_amber_rounded;
        texto = 'Ubicación POCO PRECISA ±$p m — confírmala por llamada';
      }
    }
    final Color fg = oscuro ? Color.lerp(color, Colors.white, 0.35)! : color;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: oscuro ? 0.18 : 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(children: [
        Icon(icono, size: 16, color: fg),
        const SizedBox(width: 6),
        Expanded(
          child: Text(texto,
              style: TextStyle(
                  color: fg, fontSize: 11.5, fontWeight: FontWeight.bold)),
        ),
        if (recibida && onVerMapa != null)
          InkWell(
            onTap: onVerMapa,
            child: Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Text('VER MAPA',
                  style: TextStyle(
                      color: fg,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      decoration: TextDecoration.underline)),
            ),
          ),
      ]),
    );
  }
}
