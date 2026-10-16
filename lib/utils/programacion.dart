// Servicios PROGRAMADOS a una hora exacta (central y local).
//
// El servicio se guarda con estado 'programado' y liberacion_at = la hora
// elegida. A esa hora EXACTA el servidor (se_liberar_programados) lo pasa a
// 'pendiente' y arranca la cascada normal (F1 Masters → #1 paradero → 1 km →
// todos). Quien programa calcula con cuánto tiempo de anticipación ponerlo.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:serviexpress_app/utils/hora_servidor.dart';

/// Diálogo: elegir Hoy / Mañana y la hora. Devuelve la fecha-hora LOCAL
/// elegida, o null si se cancela. No deja elegir una hora ya pasada.
Future<DateTime?> elegirHoraProgramada(BuildContext context,
    {DateTime? inicial}) async {
  final ahora = DateTime.now();
  bool manana = inicial != null &&
      DateTime(inicial.year, inicial.month, inicial.day)
          .isAfter(DateTime(ahora.year, ahora.month, ahora.day));
  TimeOfDay hora = inicial != null
      ? TimeOfDay.fromDateTime(inicial)
      : TimeOfDay.fromDateTime(ahora.add(const Duration(minutes: 30)));

  DateTime armar() {
    final base = manana ? ahora.add(const Duration(days: 1)) : ahora;
    return DateTime(base.year, base.month, base.day, hora.hour, hora.minute);
  }

  return showDialog<DateTime>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) {
        final elegido = armar();
        final pasada = !elegido.isAfter(DateTime.now());
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: const Text('📅 Programar servicio',
              style: TextStyle(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('¿Qué día?',
                  style: TextStyle(fontSize: 12, color: Colors.black54)),
              const SizedBox(height: 6),
              Row(children: [
                ChoiceChip(
                  label: const Text('Hoy'),
                  selected: !manana,
                  onSelected: (_) => setD(() => manana = false),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Mañana'),
                  selected: manana,
                  onSelected: (_) => setD(() => manana = true),
                ),
              ]),
              const SizedBox(height: 14),
              const Text('¿A qué hora se envía al radar?',
                  style: TextStyle(fontSize: 12, color: Colors.black54)),
              const SizedBox(height: 6),
              OutlinedButton.icon(
                icon: const Icon(Icons.access_time),
                label: Text(hora.format(ctx),
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
                onPressed: () async {
                  final t =
                      await showTimePicker(context: ctx, initialTime: hora);
                  if (t != null) setD(() => hora = t);
                },
              ),
              const SizedBox(height: 10),
              Text(
                pasada
                    ? '⚠️ Esa hora ya pasó. Elige una hora más tarde.'
                    : 'Se envía al radar ${textoProgramado(elegido)}.',
                style: TextStyle(
                    fontSize: 11,
                    color: pasada ? Colors.red[700] : Colors.black54),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: pasada ? null : () => Navigator.pop(ctx, elegido),
              child: const Text('PROGRAMAR'),
            ),
          ],
        );
      },
    ),
  );
}

/// "hoy 3:00 pm" · "mañana 7:15 am" · "18/10 9:00 am".
/// Acepta la hora en UTC o local (se convierte a local).
String textoProgramado(DateTime fecha) {
  final f = fecha.toLocal();
  final ahora = DateTime.now();
  final hoy = DateTime(ahora.year, ahora.month, ahora.day);
  final dia = DateTime(f.year, f.month, f.day);
  final h12 = f.hour % 12 == 0 ? 12 : f.hour % 12;
  final hora = '$h12:${f.minute.toString().padLeft(2, '0')} '
      '${f.hour < 12 ? 'am' : 'pm'}';
  final diff = dia.difference(hoy).inDays;
  if (diff == 0) return 'hoy $hora';
  if (diff == 1) return 'mañana $hora';
  return '${f.day.toString().padLeft(2, '0')}/${f.month.toString().padLeft(2, '0')} $hora';
}

/// Texto para la tarjeta de un servicio programado, o null si no aplica.
String? etiquetaProgramado(Map<String, dynamic> servicio) {
  if (servicio['estado'] != 'programado') return null;
  final lib = DateTime.tryParse(servicio['liberacion_at']?.toString() ?? '');
  if (lib == null) return '📅 Programado';
  return '📅 Programado: ${textoProgramado(lib)}';
}

/// "12:34" (menos de 1 h) · "1 h 05 min" (más de 1 h).
String _faltaTexto(Duration d) {
  if (d.inHours >= 1) {
    return '${d.inHours} h ${(d.inMinutes % 60).toString().padLeft(2, '0')} min';
  }
  return '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
}

/// Cuenta regresiva en vivo (cada segundo) hasta que el servicio sale al radar.
/// "Sale al radar en 12:34" · al llegar a cero: "Enviando al radar…".
class CuentaRegresivaRadar extends StatefulWidget {
  final dynamic liberacionAt; // String ISO o DateTime
  final Color color;
  final double tamano;
  final bool compacto; // true: una sola línea corta (monitor de la central)
  const CuentaRegresivaRadar({
    super.key,
    required this.liberacionAt,
    this.color = const Color(0xFF1565C0),
    this.tamano = 14,
    this.compacto = false,
  });

  @override
  State<CuentaRegresivaRadar> createState() => _CuentaRegresivaRadarState();
}

class _CuentaRegresivaRadarState extends State<CuentaRegresivaRadar> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.liberacionAt;
    final DateTime? lib = v is DateTime
        ? v.toUtc()
        : DateTime.tryParse(v?.toString() ?? '')?.toUtc();
    if (lib == null) return const SizedBox.shrink();
    final falta = lib.difference(HoraServidor.ahoraUtc());
    final String texto;
    if (falta.inSeconds <= 0) {
      texto = 'Enviando al radar…';
    } else if (widget.compacto) {
      texto = 'Sale en ${_faltaTexto(falta)}';
    } else if (falta.inHours >= 1) {
      texto = 'Sale al radar ${textoProgramado(lib)} · faltan ${_faltaTexto(falta)}';
    } else {
      texto = 'Sale al radar en ${_faltaTexto(falta)}';
    }
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.timer_outlined, size: widget.tamano + 2, color: widget.color),
      const SizedBox(width: 4),
      Flexible(
        child: Text(texto,
            style: TextStyle(
                fontSize: widget.tamano,
                fontWeight: FontWeight.bold,
                color: widget.color,
                fontFeatures: const [FontFeature.tabularFigures()])),
      ),
    ]);
  }
}

/// "Enviar ya": adelanta un servicio programado al radar. Pide confirmación.
/// [localId] solo lo pasa el local (la central no lo necesita).
Future<void> enviarProgramadoYa(BuildContext context, dynamic servicioId,
    {dynamic localId}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('¿Enviar al radar ahora?',
          style: TextStyle(fontWeight: FontWeight.bold)),
      content: const Text(
          'El servicio deja de estar programado y los móviles lo ven de una vez.'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No, esperar')),
        ElevatedButton.icon(
          icon: const Icon(Icons.send),
          label: const Text('Sí, enviar ya'),
          onPressed: () => Navigator.pop(ctx, true),
        ),
      ],
    ),
  );
  if (ok != true) return;
  try {
    final res = await Supabase.instance.client.rpc('fn_enviar_programado_ya',
        params: {
          'p_id': int.tryParse(servicioId.toString()),
          if (localId != null) 'p_local': int.tryParse(localId.toString()),
        });
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(res == true
          ? '✅ Listo: el servicio ya está en el radar.'
          : 'Este servicio ya no estaba programado.'),
      backgroundColor: res == true ? Colors.green[700] : Colors.orange[800],
    ));
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text(
          'No se pudo enviar. Revisa tu internet e inténtalo otra vez.'),
      backgroundColor: Colors.red[700],
    ));
  }
}

/// Botón "Enviar ya" (48 px, con texto) para la tarjeta de un programado.
class BotonEnviarYa extends StatelessWidget {
  final dynamic servicioId;
  final dynamic localId;
  const BotonEnviarYa({super.key, required this.servicioId, this.localId});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: OutlinedButton.icon(
        icon: const Icon(Icons.send_rounded, size: 18),
        label: const Text('Enviar ya',
            style: TextStyle(fontWeight: FontWeight.bold)),
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF1565C0),
          side: const BorderSide(color: Color(0xFF1565C0)),
        ),
        onPressed: () =>
            enviarProgramadoYa(context, servicioId, localId: localId),
      ),
    );
  }
}
