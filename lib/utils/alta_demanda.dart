// lib/utils/alta_demanda.dart
//
// ALTA DEMANDA (servicios SE)
// La central la enciende/apaga (config_sistema.alta_demanda_se). Mientras
// esté encendida, locales, clientes e invitados ven esta franja. Al apagarla
// desaparece sola (escucha en vivo una sola fila de config_sistema).

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AltaDemanda {
  static Stream<Map<String, dynamic>?>? _stream;

  /// Un solo canal en vivo para toda la app.
  static Stream<Map<String, dynamic>?> get estado {
    return _stream ??= Supabase.instance.client
        .from('config_sistema')
        .stream(primaryKey: ['id'])
        .eq('id', 1)
        .map((rows) => rows.isEmpty ? null : rows.first)
        .handleError((_) {})
        .asBroadcastStream();
  }
}

/// CENTRAL: encender / apagar alta demanda (con mensaje opcional).
/// Al encender, el servidor manda UNA notificación a los locales y a los
/// clientes con pedido en curso.
Future<void> abrirControlAltaDemanda(BuildContext context) async {
  final db = Supabase.instance.client;
  Map<String, dynamic>? cfg;
  try {
    cfg = await db
        .from('config_sistema')
        .select('alta_demanda_se, alta_demanda_mensaje')
        .eq('id', 1)
        .maybeSingle();
  } catch (_) {}
  if (!context.mounted) return;
  bool activa = cfg?['alta_demanda_se'] == true;
  final msgCtrl = TextEditingController(text: cfg?['alta_demanda_mensaje']?.toString() ?? '');
  final guardar = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) => AlertDialog(
        title: const Text('⚠️ Alta demanda', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: activa,
            activeColor: Colors.orange[800],
            onChanged: (v) => setD(() => activa = v),
            title: Text(activa ? 'ENCENDIDA' : 'Apagada',
                style: TextStyle(fontWeight: FontWeight.bold, color: activa ? Colors.orange[900] : Colors.black54)),
            subtitle: const Text(
              'Locales, clientes e invitados ven un aviso: los servicios se atienden en orden de llegada.',
              style: TextStyle(fontSize: 11),
            ),
          ),
          TextField(
            controller: msgCtrl,
            maxLength: 80,
            decoration: const InputDecoration(
              labelText: 'Mensaje adicional (opcional)',
              hintText: 'Ej: Tiempo de espera aprox. 30 min',
            ),
          ),
          if (activa && cfg?['alta_demanda_se'] != true)
            const Text('Al guardar se enviará una notificación SIN SONIDO a los locales y clientes con pedido en curso.',
                style: TextStyle(fontSize: 11, color: Colors.black45)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCELAR')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('GUARDAR')),
        ],
      ),
    ),
  );
  if (guardar != true) return;
  try {
    await db.rpc('fn_guardar_alta_demanda', params: {'p_activa': activa, 'p_mensaje': msgCtrl.text});
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(activa ? '⚠️ Alta demanda ENCENDIDA' : 'Alta demanda apagada'),
        backgroundColor: activa ? Colors.orange[800] : Colors.green[700],
      ));
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    }
  }
}

class BannerAltaDemanda extends StatelessWidget {
  final EdgeInsetsGeometry margin;
  const BannerAltaDemanda({super.key, this.margin = const EdgeInsets.only(bottom: 8)});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>?>(
      stream: AltaDemanda.estado,
      builder: (context, snap) {
        final cfg = snap.data;
        if (cfg == null || cfg['alta_demanda_se'] != true) return const SizedBox.shrink();
        final extra = (cfg['alta_demanda_mensaje'] ?? '').toString().trim();
        return Container(
          width: double.infinity,
          margin: margin,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF3E0),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.orange[700]!, width: 1.5),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('⚠️', style: TextStyle(fontSize: 18)),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('ALTA DEMANDA',
                    style: TextStyle(
                        color: Colors.orange[900], fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.5)),
                const SizedBox(height: 2),
                Text(
                  'Los servicios se atienden en el orden en que se solicitan. '
                  'Puede tardar más de lo normal. Gracias por tu paciencia.'
                  '${extra.isNotEmpty ? '\n$extra' : ''}',
                  style: TextStyle(color: Colors.orange[900], fontSize: 12, height: 1.3),
                ),
              ]),
            ),
          ]),
        );
      },
    );
  }
}
