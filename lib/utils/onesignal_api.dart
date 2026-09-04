// lib/utils/onesignal_api.dart
//
// CAMBIOS VS VERSIÓN ANTERIOR
// ============================
// [NUEVO] Parámetro `sonido` en las 4 funciones de disparo.
//   Antes: todas las notificaciones usaban 'alerta.mp3' hardcodeado.
//   Ahora: cada llamada puede especificar el sonido exacto a reproducir.
//   Compatibilidad: el default sigue siendo 'alerta' — nada en el
//   resto del código se rompe si no se pasa el parámetro.
//
// [NUEVO] Clase `Sonidos` con los 19 nombres de archivos como
//   constantes tipadas. Úsala en lugar de strings sueltos para
//   evitar typos: Sonidos.centralCotizacion, Sonidos.alerta, etc.
//
// NOTA ANDROID: android_channel_id sobreescribe el sonido en Android 8+.
//   - urgente: true  → usa _canalAlarmaId → sonido máximo del canal
//   - urgente: false → sin canal → android_sound controla el sonido
//   Para sonidos suaves de Central/Local, pasar urgente: false.

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

// =========================================================================
// MOTOR DE NOTIFICACIONES
// =========================================================================
// La clase Sonidos vive en sonido_manager.dart.
// Las pantallas usan Sonidos.* cuando llaman a estas funciones.
// Este archivo solo maneja el HTTP con la Edge Function — no necesita audio.
//
// SEGURIDAD: La OneSignal REST API Key vive como secret ONESIGNAL_REST_KEY
// en la Edge Function 'send-notification' de Supabase. Nunca en el APK.
class MotorNotificaciones {
  static const String _appId = '207d1d0a-0218-46e0-9f35-7d8d88f6765a';

  static const String _edgeFnUrl =
      'https://oukiofdtargjrclualgm.supabase.co/functions/v1/send-notification';

  // ── CANALES ANDROID (deben coincidir con ServiMotoApp.kt) ───────────────
  // Alertas de servicio (alerta.mp3) — T=0 para no-masters, paradero, cascada
  static const String _canalAlarmaId       = 'serviexpress_alerta_v2';
  // Pánico (panico.mp3)
  static const String canalPanicoId        = 'serviexpress_panico_v1';
  // Masters rango MASTER — sonido suave (master.mp3)
  static const String canalMasterId        = 'serviexpress_master_v1';
  // Inactividad 5h45min (movil_inactividad.mp3)
  static const String canalInactividadId   = 'serviexpress_inactividad_v1';
  // Chat hacia el móvil (movil_chat_central.mp3)
  static const String canalChatMovilId     = 'serviexpress_chat_movil_v1';
  // Chat hacia la central (central_chat.mp3)
  static const String canalChatCentralId   = 'serviexpress_chat_central_v1';
  // Chat hacia el local (local_chat.mp3)
  static const String canalChatLocalId     = 'serviexpress_chat_local_v1';
  // Central: nueva cotización (central_cotizacion.mp3)
  static const String canalCotizacionId    = 'serviexpress_cotizacion_v1';
  // Central: radar (central_radar.mp3)
  static const String canalRadarId         = 'serviexpress_radar_v1';
  // Central: demora (central_demora.mp3)
  static const String canalDemoraId        = 'serviexpress_demora_v1';
  // Central: problema (central_problema.mp3)
  static const String canalProblemaId      = 'serviexpress_problema_v1';
  // Central: caducado (central_caducado.mp3)
  static const String canalCaducadoId      = 'serviexpress_caducado_v1';
  // Central: cancelado (central_cancelado.mp3)
  static const String canalCanceladoId     = 'serviexpress_cancelado_v1';
  // FN / Local / Cliente: respuesta de cotización (fn_cotizacion.mp3)
  static const String canalFnCotizacionId  = 'serviexpress_fn_cotizacion_v1';

  // -----------------------------------------------------------------------
  // 1. RÁFAGA DE PRECISIÓN — A múltiples destinos de un golpe
  // -----------------------------------------------------------------------
  static Future<void> dispararRafa({
    required List<String> idsDestinos,
    required String titulo,
    required String mensaje,
    bool urgente = true,
    String sonido = 'alerta',
    /// Override del canal Android. Por defecto usa _canalAlarmaId.
    /// Usar _canalPanicoId para alertas de pánico.
    String? canalAndroidId,
    /// collapse_id de OneSignal: si hay una notif previa con el mismo ID,
    /// la reemplaza en lugar de apilar otra. Útil para activaciones.
    String? collapseId,
    /// data extra que llega a la app (additional_data en el payload).
    Map<String, dynamic>? data,
  }) async {
    if (idsDestinos.isEmpty) return;
    await _enviarPush(
      body: {
        'app_id': _appId,
        'include_external_user_ids': idsDestinos,
        'headings': {'en': titulo, 'es': titulo},
        'contents': {'en': mensaje, 'es': mensaje},
        'priority': 10,
        'android_sound': sonido,
        'ios_sound': '$sonido.mp3',
        if (urgente) 'existing_android_channel_id': canalAndroidId ?? _canalAlarmaId,
        if (collapseId != null) 'collapse_id': collapseId,
        if (data != null) 'data': data,
      },
    );
  }

  // -----------------------------------------------------------------------
  // 2. DISPARO DIRECTO — A un solo destino
  // -----------------------------------------------------------------------
  static Future<void> dispararMisil({
    required String idDestino,
    required String titulo,
    required String mensaje,
    bool urgente = true,
    String sonido = 'alerta',
    String? canalAndroidId,
  }) async {
    if (idDestino == 'null' || idDestino.isEmpty) return;
    await _enviarPush(
      body: {
        'app_id': _appId,
        'include_external_user_ids': [idDestino],
        'headings': {'en': titulo, 'es': titulo},
        'contents': {'en': mensaje, 'es': mensaje},
        'priority': 10,
        'android_sound': sonido,
        'ios_sound': '$sonido.mp3',
        if (urgente) 'existing_android_channel_id': canalAndroidId ?? _canalAlarmaId,
      },
    );
  }

  // -----------------------------------------------------------------------
  // 3. DISPARO A LA CENTRAL — Por filtro de tag rol=central
  // -----------------------------------------------------------------------
  // NOTA: CentralScreen registra OneSignal.User.addTagWithKey('rol', 'central')
  // para todos los usuarios master y central. Usamos filtro por tag en lugar de
  // included_segments para no depender de un segmento configurado en el dashboard.
  static Future<void> dispararACentral({
    required String titulo,
    required String mensaje,
    bool urgente = true,
    String sonido = 'alerta',
    String? canalAndroidId,
  }) async {
    await _enviarPush(
      body: {
        'app_id': _appId,
        'filters': [
          {'field': 'tag', 'key': 'rol', 'relation': '=', 'value': 'central'},
        ],
        'headings': {'en': titulo, 'es': titulo},
        'contents': {'en': mensaje, 'es': mensaje},
        'priority': 10,
        'android_sound': sonido,
        'ios_sound': '$sonido.mp3',
        if (urgente || canalAndroidId != null)
          'existing_android_channel_id': canalAndroidId ?? _canalAlarmaId,
      },
    );
  }

  // -----------------------------------------------------------------------
  // 4. DISPARO PROGRAMADO — Con retardo en minutos (reloj táctico)
  // -----------------------------------------------------------------------
  static Future<String?> programarMisilRetardado({
    required List<String> externalIds,
    required String titulo,
    required String mensaje,
    int minutosRetardo = 0,
    int segundosRetardo = 0,
    String sonido = 'alerta',
    /// Override del canal Android. Por defecto usa _canalAlarmaId.
    String? canalAndroidId,
  }) async {
    if (externalIds.isEmpty) return null;

    final fechaDisparo = DateTime.now().toUtc().add(
      Duration(minutes: minutosRetardo, seconds: segundosRetardo),
    );
    final formatGMT =
        '${fechaDisparo.year}-'
        '${fechaDisparo.month.toString().padLeft(2, '0')}-'
        '${fechaDisparo.day.toString().padLeft(2, '0')} '
        '${fechaDisparo.hour.toString().padLeft(2, '0')}:'
        '${fechaDisparo.minute.toString().padLeft(2, '0')}:'
        '${fechaDisparo.second.toString().padLeft(2, '0')} GMT';

    return await _enviarPush(
      body: {
        'app_id': _appId,
        'include_external_user_ids': externalIds,
        'headings': {'en': titulo, 'es': titulo},
        'contents': {'en': mensaje, 'es': mensaje},
        'priority': 10,
        'android_sound': sonido,
        'ios_sound': '$sonido.mp3',
        'existing_android_channel_id': canalAndroidId ?? _canalAlarmaId,
        'send_after': formatGMT,
      },
    );
  }

  // -----------------------------------------------------------------------
  // 5. CANCELAR MISIL PROGRAMADO — Aborta una notificación por su ID
  //    Llama a la Edge Function con action='cancel' (REST key server-side).
  // -----------------------------------------------------------------------
  static Future<void> cancelarMisil(String notificationId) async {
    try {
      final response = await http.post(
        Uri.parse(_edgeFnUrl),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
        body: jsonEncode({'action': 'cancel', 'notification_id': notificationId}),
      );
      debugPrint('💥 Misil $notificationId abortado → ${response.statusCode}');
    } catch (e) {
      debugPrint('MotorNotificaciones: error cancelando misil → $e');
    }
  }

  // -----------------------------------------------------------------------
  // MOTOR INTERNO — HTTP al API de OneSignal
  // -----------------------------------------------------------------------
  static Future<String?> _enviarPush({
    required Map<String, dynamic> body,
  }) async {
    try {
      // Llamamos la Edge Function — ella añade la Authorization de OneSignal
      // server-side, sin exponer la REST API Key en el APK.
      final url = Uri.parse(_edgeFnUrl);
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json; charset=utf-8'},
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(response.body);
        return jsonResponse['id'];
      } else {
        debugPrint('MotorNotificaciones: fallo push → ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('MotorNotificaciones: error de red → $e');
      return null;
    }
  }
}
