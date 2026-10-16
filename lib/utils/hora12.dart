// ═══════════════════════════════════════════════════════════════════════════
// HORA EN FORMATO 12 HORAS (am / pm) — en TODA la app
// "3:05 pm", "11:40 am". Nunca 15:05 (formato 24 h).
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

String _armar(int hora24, int minuto) {
  final h = hora24 % 12 == 0 ? 12 : hora24 % 12;
  final m = minuto.toString().padLeft(2, '0');
  return '$h:$m ${hora24 < 12 ? 'am' : 'pm'}';
}

/// DateTime (UTC o local) → "3:05 pm" en hora local.
String hora12(DateTime fecha) {
  final f = fecha.toLocal();
  return _armar(f.hour, f.minute);
}

/// Texto ISO de la base de datos → "3:05 pm" ('' si no se puede leer).
String hora12Iso(dynamic iso) {
  final d = DateTime.tryParse(iso?.toString() ?? '');
  return d == null ? '' : hora12(d);
}

/// "dd/MM 3:05 pm"
String fechaHora12(DateTime fecha, {bool conAnio = false}) {
  final f = fecha.toLocal();
  final dia = '${f.day.toString().padLeft(2, '0')}/${f.month.toString().padLeft(2, '0')}'
      '${conAnio ? '/${f.year}' : ''}';
  return '$dia ${_armar(f.hour, f.minute)}';
}

/// Hora guardada como texto "18:00" o "18:00:00" → "6:00 pm".
String horaTexto12(String? hhmm) {
  if (hhmm == null) return '';
  final p = hhmm.split(':');
  if (p.length < 2) return hhmm;
  final h = int.tryParse(p[0]);
  final m = int.tryParse(p[1]);
  if (h == null || m == null) return hhmm;
  return _armar(h, m);
}

/// TimeOfDay → "6:00 pm"
String horaDia12(TimeOfDay t) => _armar(t.hour, t.minute);

/// Selector de hora ESCRITA en formato 12 h con am / pm (el usuario teclea
/// la hora y los minutos y elige am o pm). Devuelve null si cancela.
Future<TimeOfDay?> elegirHora12(BuildContext context, TimeOfDay inicial,
    {String titulo = 'Escribe la hora'}) {
  return showTimePicker(
    context: context,
    initialTime: inicial,
    initialEntryMode: TimePickerEntryMode.inputOnly,
    helpText: titulo,
    hourLabelText: 'Hora',
    minuteLabelText: 'Minutos',
    cancelText: 'Cancelar',
    confirmText: 'Listo',
    errorInvalidText: 'Escribe una hora válida (1 a 12) y minutos (0 a 59)',
    builder: (ctx, child) => MediaQuery(
      // Siempre 12 horas con am / pm, sin importar la configuración del teléfono
      data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: false),
      child: child ?? const SizedBox.shrink(),
    ),
  );
}
