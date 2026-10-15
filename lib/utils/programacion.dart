// Servicios PROGRAMADOS a una hora exacta (central y local).
//
// El servicio se guarda con estado 'programado' y liberacion_at = la hora
// elegida. A esa hora EXACTA el servidor (se_liberar_programados) lo pasa a
// 'pendiente' y arranca la cascada normal (F1 Masters → #1 paradero → 1 km →
// todos). Quien programa calcula con cuánto tiempo de anticipación ponerlo.

import 'package:flutter/material.dart';

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
              const Text('¿A qué hora sale a los móviles?',
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
                    : 'Sale a los móviles exactamente ${textoProgramado(elegido)}. '
                        'Calcula el tiempo que necesita el móvil para llegar.',
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
