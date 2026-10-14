// lib/utils/sesion_segura.dart
//
// La sesión guardada en el teléfono (SharedPreferences / localStorage en web)
// y el mapa `usuario` que viaja por las pantallas NUNCA deben llevar datos
// sensibles: contraseña cifrada, cédula, foto del documento ni códigos de
// recuperación. Esos datos viven en el servidor (usuarios_privado).

const Set<String> _camposSensibles = {
  'contrasena',
  'cedula',
  'doc_cedula_url',
  'reset_token',
  'reset_token_exp',
};

/// Copia del usuario sin los campos sensibles.
Map<String, dynamic> sinDatosSensibles(Map<String, dynamic> usuario) {
  final limpio = Map<String, dynamic>.from(usuario);
  limpio.removeWhere((k, _) => _camposSensibles.contains(k));
  return limpio;
}
