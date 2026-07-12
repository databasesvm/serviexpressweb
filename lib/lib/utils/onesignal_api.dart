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

  // v2: ID nuevo — canal fresco con alerta.mp3 (ver ServiMotoApp.kt)
  // El ID viejo (a26379a9) quedó sin sonido porque Android bloquea cambios en canales existentes.
  // CHANNEL_ZONA_ID (serviexpress_zona_v2) solo lo usa el cron SQL — no se referencia aquí.
  static const String _canalAlarmaId = 'serviexpress_alerta_v2';
  // Canal exclusivo de pánico — reproduce panico.mp3 con IMPORTANCIA MÁXIMA
  static const String canalPanicoId = 'serviexpress_panico_v1';

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
        if (urgente) 'existing_android_channel_id': _canalAlarmaId,
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
        'existing_android_channel_id': _canalAlarmaId,
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
