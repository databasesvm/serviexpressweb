// lib/utils/web_notif_web.dart
// Notificaciones del navegador (Windows/Android/macOS toast) via Web Notifications API.
// Solo se compila en web — el stub cubre Android/iOS nativos.
//
// FLUJO:
//   1. La app llama pedirPermiso() una sola vez al iniciar (via SonidoManager).
//   2. El navegador muestra el diálogo "¿Permitir notificaciones?".
//   3. Cuando ocurre un evento (nueva cotización, radar, etc.) se llama mostrar().
//   4. El SO muestra un toast de Windows/Android con título y cuerpo.
//
// NOTA: Los sonidos van por audioplayers (HTML Audio API) — esta clase solo
// maneja el toast visual. Ambos se disparan juntos desde SonidoManager.

// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

class WebAlertaManager {
  static bool _permisoPedido = false;

  /// Solicita permiso al navegador. Llama una sola vez (SonidoManager lo hace
  /// al crear el singleton). El navegador recuerda la respuesta entre sesiones.
  static Future<void> pedirPermiso() async {
    if (_permisoPedido) return;
    _permisoPedido = true;
    try {
      await html.Notification.requestPermission();
    } catch (_) {}
  }

  /// Muestra una notificación del SO (toast de Windows, Android, macOS).
  /// Solo actúa si el usuario ya concedió permiso.
  static void mostrar({required String titulo, String cuerpo = ''}) {
    try {
      if (html.Notification.supported &&
          html.Notification.permission == 'granted') {
        final n = html.Notification(titulo, body: cuerpo);
        // Cierra automáticamente a los 6 segundos para no acumular en la bandeja
        Future.delayed(const Duration(seconds: 6), n.close);
      }
    } catch (_) {}
  }
}
