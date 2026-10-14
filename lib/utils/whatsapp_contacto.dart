// WhatsApp del cliente: puede ser un NÚMERO (3001234567, +57 300 123 4567)
// o un USUARIO de WhatsApp (@cryxusz). Todos los botones de WhatsApp de la
// app pasan por aquí para abrir el chat correcto.
//
//   número  → https://wa.me/573001234567?text=...
//   usuario → https://wa.me/cryxusz?text=...

import 'package:flutter/services.dart';

/// true si lo escrito es un usuario de WhatsApp (tiene letras o empieza con @).
bool esUsuarioWhatsApp(String? valor) {
  final v = (valor ?? '').trim();
  if (v.isEmpty) return false;
  return v.startsWith('@') || RegExp(r'[A-Za-z]').hasMatch(v);
}

/// Deja el dato limpio para guardarlo:
///   número  → igual que siempre (como se escribió), para que el historial
///             de direcciones del cliente siga encontrando los pedidos viejos
///   usuario → "@usuario" en minúsculas y sin espacios
String normalizarWhatsApp(String? valor) {
  final v = (valor ?? '').trim();
  if (v.isEmpty) return '';
  if (esUsuarioWhatsApp(v)) {
    final u = v.replaceAll('@', '').replaceAll(RegExp(r'\s'), '').toLowerCase();
    return u.isEmpty ? '' : '@$u';
  }
  return v;
}

/// ¿Ya se puede buscar el historial del cliente con lo escrito?
/// número: 10 dígitos o más · usuario: 3 letras o más.
bool whatsAppListoParaBuscar(String? valor) {
  final v = (valor ?? '').trim();
  if (esUsuarioWhatsApp(v)) return v.replaceAll('@', '').length >= 3;
  return v.replaceAll(RegExp(r'[^0-9]'), '').length >= 10;
}

/// Validación para formularios. Devuelve el texto de error o null si está bien.
/// [obligatorio] = el campo no puede quedar vacío.
String? validarWhatsApp(String? valor, {bool obligatorio = false}) {
  final v = (valor ?? '').trim();
  if (v.isEmpty) return obligatorio ? 'Escribe el número o el @usuario de WhatsApp' : null;
  if (esUsuarioWhatsApp(v)) {
    final u = v.replaceAll('@', '').replaceAll(RegExp(r'\s'), '');
    if (!RegExp(r'^[A-Za-z0-9._]{3,35}$').hasMatch(u)) {
      return 'Usuario no válido (solo letras, números, punto o guion bajo)';
    }
    return null;
  }
  final n = v.replaceAll(RegExp(r'[^0-9]'), '');
  if (n.length < 7) return 'Número muy corto';
  return null;
}

/// Filtro de teclado: deja escribir números, +, espacios, guiones, letras,
/// punto, guion bajo y @ (para usuarios de WhatsApp).
final List<TextInputFormatter> formatoWhatsApp = [
  FilteringTextInputFormatter.allow(RegExp(r'[0-9A-Za-z@._+\-\s]')),
  LengthLimitingTextInputFormatter(36),
];

/// Enlace que abre el chat de WhatsApp. null si no hay dato.
Uri? uriWhatsApp(String? valor, {String? texto}) {
  final v = (valor ?? '').trim();
  if (v.isEmpty) return null;
  final q = (texto != null && texto.isNotEmpty)
      ? '?text=${Uri.encodeComponent(texto)}'
      : '';
  if (esUsuarioWhatsApp(v)) {
    final u = v.replaceAll('@', '').replaceAll(RegExp(r'\s'), '');
    if (u.isEmpty) return null;
    return Uri.parse('https://wa.me/$u$q');
  }
  var n = v.replaceAll(RegExp(r'[^0-9]'), '');
  if (n.isEmpty) return null;
  if (n.length == 10) n = '57$n'; // celular colombiano sin indicativo
  return Uri.parse('https://wa.me/$n$q');
}

/// Para LLAMAR: solo sirve si es un número. Con un @usuario devuelve null.
Uri? uriLlamada(String? valor) {
  final v = (valor ?? '').trim();
  if (v.isEmpty || esUsuarioWhatsApp(v)) return null;
  final n = v.replaceAll(RegExp(r'[^0-9+]'), '');
  return n.isEmpty ? null : Uri.parse('tel:$n');
}
