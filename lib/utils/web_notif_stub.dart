// lib/utils/web_notif_stub.dart
// Implementación vacía para Android, iOS y Desktop.
// No hace nada — las notificaciones del SO van por OneSignal en esas plataformas.
class WebAlertaManager {
  static Future<void> pedirPermiso() async {}
  static Future<void> pedirPermisoConToque() async {}
  static void mostrar({required String titulo, String cuerpo = '', int segundos = 6}) {}
  static bool pestanaOculta() => false;
  static void ponerTitulo(String titulo) {}
  static void restaurarTitulo() {}
  static void vibrar(List<int> patron) {}
  static void pushPermiso() {}
  static void pushLogin(String id) {}
  static void pushTag(String clave, String valor) {}
}
