// lib/utils/auth_helper.dart
//
// UTILIDAD DE SEGURIDAD — MANEJO DE CONTRASEÑAS
// ================================================
// Centraliza el hash de contraseñas para que ninguna pantalla
// guarde o compare texto plano. Importa este archivo en lugar
// de manejar crypto directamente en cada widget.
//
// INSTALACIÓN REQUERIDA en pubspec.yaml:
//   dependencies:
//     crypto: ^3.0.3

import 'package:crypto/crypto.dart';
import 'dart:convert';

/// Convierte una contraseña en texto plano a su hash SHA-256.
///
/// Úsalo SIEMPRE antes de:
///   - Guardar en Supabase (`insert` o `update`)
///   - Comparar en el login (`.eq('contrasena', hashContrasena(clave))`)
///   - Guardar en SharedPreferences
///
/// NUNCA almacenes ni compares [contrasena] en texto plano.
String hashContrasena(String contrasena) {
  final bytes = utf8.encode(contrasena.trim());
  return sha256.convert(bytes).toString();
}
