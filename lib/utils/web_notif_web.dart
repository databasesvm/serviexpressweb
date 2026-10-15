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
// dart:js_util ya no existe en esta versión de Flutter → js_interop
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

class WebAlertaManager {
  static bool _permisoPedido = false;
  static String? _tituloOriginal;

  /// Solicita permiso al navegador. Llama una sola vez (SonidoManager lo hace
  /// al crear el singleton). El navegador recuerda la respuesta entre sesiones.
  static Future<void> pedirPermiso() async {
    if (_permisoPedido) return;
    _permisoPedido = true;
    try {
      await html.Notification.requestPermission();
    } catch (_) {}
  }

  /// Pide el permiso desde un toque del usuario (ej. al enviar el pedido).
  /// Muchos navegadores (Chrome móvil, Safari) solo muestran el diálogo si
  /// viene de un toque. Solo pregunta si todavía no ha respondido.
  static Future<void> pedirPermisoConToque() async {
    try {
      if (html.Notification.supported && html.Notification.permission == 'default') {
        await html.Notification.requestPermission();
      }
    } catch (_) {}
  }

  /// Muestra una notificación del SO (toast de Windows, Android, macOS).
  /// Solo actúa si el usuario ya concedió permiso.
  static void mostrar({required String titulo, String cuerpo = '', int segundos = 6}) {
    try {
      if (html.Notification.supported &&
          html.Notification.permission == 'granted') {
        final n = html.Notification(titulo, body: cuerpo);
        n.onClick.listen((_) {
          try {
            // Traer la pestaña al frente al tocar la notificación
            n.close();
          } catch (_) {}
        });
        // Cierra automáticamente para no acumular en la bandeja
        Future.delayed(Duration(seconds: segundos), n.close);
      }
    } catch (_) {}
  }

  /// ¿La pestaña está oculta (el usuario mira otra pestaña/app)?
  static bool pestanaOculta() {
    try {
      return html.document.hidden ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Cambia el título de la pestaña (ej. "(1) 💬 Precio listo").
  static void ponerTitulo(String titulo) {
    try {
      _tituloOriginal ??= html.document.title;
      html.document.title = titulo;
    } catch (_) {}
  }

  /// Devuelve el título original de la pestaña.
  static void restaurarTitulo() {
    try {
      if (_tituloOriginal != null) html.document.title = _tituloOriginal!;
      _tituloOriginal = null;
    } catch (_) {}
  }

  // ── Web Push de OneSignal (avisos con la página cerrada) ──────────────
  // Llaman a los puentes definidos en web/index.html.
  static void _llamar(String fn, List<String> args) {
    try {
      if (!globalContext.has(fn)) return;
      final a = args.map((e) => e.toJS).toList();
      switch (a.length) {
        case 0:
          globalContext.callMethod<JSAny?>(fn.toJS);
          break;
        case 1:
          globalContext.callMethod<JSAny?>(fn.toJS, a[0]);
          break;
        default:
          globalContext.callMethod<JSAny?>(fn.toJS, a[0], a[1]);
      }
    } catch (_) {}
  }

  /// Pide permiso de notificaciones vía OneSignal (crea la suscripción web).
  static void pushPermiso() => _llamar('sePushPermiso', []);

  /// Identifica al cliente registrado en OneSignal (external_id = usuarios.id).
  static void pushLogin(String id) => _llamar('sePushLogin', [id]);

  /// Etiqueta (ej. pedido del invitado) para enviarle el aviso a él.
  static void pushTag(String clave, String valor) => _llamar('sePushTag', [clave, valor]);

  /// Vibra el celular (Android/Chrome; iPhone no lo permite en el navegador).
  static void vibrar(List<int> patron) {
    // dart:html no trae vibrate(): se llama directo al navigator.vibrate de JS
    try {
      final nav = globalContext['navigator'] as JSObject?;
      if (nav != null && nav.has('vibrate')) {
        nav.callMethod<JSAny?>('vibrate'.toJS, patron.map((e) => e.toJS).toList().toJS);
      }
    } catch (_) {}
  }
}
