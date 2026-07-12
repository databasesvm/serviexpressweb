import 'package:flutter/material.dart';

/// Stub para plataformas no-Android (Web, iOS).
/// OTA via APK solo aplica en Android — en otras plataformas no hace nada.
class OtaUpdater {
  static Future<void> verificar(BuildContext context) async {}
}
