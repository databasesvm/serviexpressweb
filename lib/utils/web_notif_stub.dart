// lib/utils/web_notif_stub.dart
// Implementación vacía para Android, iOS y Desktop.
// No hace nada — las notificaciones del SO van por OneSignal en esas plataformas.
class WebAlertaManager {
  static Future<void> pedirPermiso() async {}
  static void mostrar({required String titulo, String cuerpo = ''}) {}
}
