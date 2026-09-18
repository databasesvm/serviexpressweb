import 'package:flutter/material.dart';

/// OTA via APK deshabilitado — la app se distribuye por Google Play y
/// no puede instalar sus propios APKs (política de Play Store).
/// Todos los métodos son no-op para no romper los call sites existentes.
class OtaUpdater {
  static Future<void> verificar(BuildContext context) async {}
  static Future<void> verificarPendiente(BuildContext context) async {}
}
