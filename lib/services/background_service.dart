// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ─── IDs de notificación y canal ────────────────────────────────────────────
const int kFgNotifId = 8881;
const String kFgChannelId = 'servimoto_foreground';

// ─── Claves de SharedPreferences usadas por el servicio ─────────────────────
const String kPrefUserId = 'bg_user_id';

// ============================================================================
// INICIALIZACIÓN — llamar una sola vez en main() antes de runApp()
// ============================================================================
Future<void> initBackgroundService() async {
  final service = FlutterBackgroundService();

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: _onStart,
      autoStart: false, // el moto decide cuándo conectarse
      isForegroundMode: true,
      notificationChannelId: kFgChannelId,
      initialNotificationTitle: 'ServiExpress',
      initialNotificationContent: 'Conectado · recibiendo servicios',
      foregroundServiceNotificationId: kFgNotifId,
      // Sin tipo de foregroundServiceType aquí porque el paquete
      // lo inyecta en el manifest; el permiso FOREGROUND_SERVICE_LOCATION
      // ya está declarado en AndroidManifest.xml
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: _onStart,
      onBackground: _onIosBackground,
    ),
  );
}

// ─── Entry-point del isolate de segundo plano ────────────────────────────────
@pragma('vm:entry-point')
void _onStart(ServiceInstance service) async {
  // Necesario para plugins en isolates secundarios
  DartPluginRegistrant.ensureInitialized();

  // Inicializar Supabase en el isolate del servicio
  try {
    await Supabase.initialize(
      url: 'https://oukiofdtargjrclualgm.supabase.co',
      publishableKey:
          'sb_publishable_rWZ5Ti_oNMnkrwZL8Wp1Sw_YGoSPK0D',
    );
  } catch (_) {
    // Si ya estaba inicializado (raro en isolate separado, pero seguro)
  }

  // Escucha comandos desde el isolate principal
  service.on('stopService').listen((_) {
    service.stopSelf();
  });

  service.on('updateStatus').listen((data) async {
    if (service is AndroidServiceInstance) {
      final texto = data?['texto'] as String? ?? 'Conectado';
      service.setForegroundNotificationInfo(
        title: 'ServiExpress activo',
        content: texto,
      );
    }
  });

  // Ping cada 60 segundos mientras el servicio esté activo
  Timer.periodic(const Duration(seconds: 60), (_) async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString(kPrefUserId);
    if (userId == null) return;

    try {
      await Supabase.instance.client
          .from('usuarios')
          .update({
            'ultimo_ping': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', userId);
    } catch (e) {
      print('[BgService] ping error: $e');
    }
  });
}

// ─── iOS: background fetch (requiere background modes en Info.plist) ─────────
@pragma('vm:entry-point')
Future<bool> _onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  return true;
}

// ============================================================================
// API PÚBLICA — usada desde movil_screen.dart
// ============================================================================

/// Arranca el foreground service y guarda el userId en prefs para el isolate.
Future<void> startForegroundService(String userId) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(kPrefUserId, userId);

  final service = FlutterBackgroundService();
  await service.startService();
}

/// Detiene el foreground service y limpia el userId.
Future<void> stopForegroundService() async {
  final service = FlutterBackgroundService();
  service.invoke('stopService');

  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(kPrefUserId);
}

/// Actualiza el texto de la notificación persistente.
void updateForegroundNotification(String texto) {
  FlutterBackgroundService().invoke('updateStatus', {'texto': texto});
}
