// ignore_for_file: discarded_futures
// ============================================================================
// OPCIÓN B2 — Implementación Android/iOS con flutter_foreground_task.
// Este archivo NO se compila en web — background_service.dart lo excluye
// mediante conditional export (dart.library.io).
//
// El foreground service hace dos cosas únicamente:
//   1. Actualiza ultimo_ping cada 15s para que el cron zombi no desconecte.
//   2. Actualiza latitud/longitud como respaldo al stream GPS del isolate UI.
//
// La desconexión es SIEMPRE manual: el moto pulsa "Desconectarse".
// No hay auto-desconexión por tiempo, avisos de inactividad ni nada similar.
// ============================================================================

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Clave de SharedPreferences — pública para que movil_screen pueda leerla.
const String kBgUserId = 'bg_user_id';

Future<void> initBackgroundService() async {
  FlutterForegroundTask.initCommunicationPort();
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'servimoto_foreground',
      channelName: 'ServiExpress activo',
      channelDescription:
          'Mantiene la app activa mientras el moto está conectado',
      // HIGH reduce la probabilidad de que ROMs agresivos (Xiaomi, Samsung,
      // Huawei) maten el servicio cuando la app está en segundo plano.
      channelImportance: NotificationChannelImportance.HIGH,
      priority: NotificationPriority.HIGH,
    ),
    iosNotificationOptions: const IOSNotificationOptions(
      showNotification: false,
      playSound: false,
    ),
    foregroundTaskOptions: ForegroundTaskOptions(
      eventAction: ForegroundTaskEventAction.repeat(15000),
      autoRunOnBoot: false,
      autoRunOnMyPackageReplaced: true,
      allowWakeLock: true,
    ),
  );
}

Future<void> startForegroundService(String userId) async {
  if (await FlutterForegroundTask.isRunningService) return;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(kBgUserId, userId);
  await FlutterForegroundTask.startService(
    notificationTitle: 'ServiExpress activo',
    notificationText: 'Conectado · recibiendo servicios',
    callback: _startCallback,
  );
}

Future<void> stopForegroundService() async {
  await FlutterForegroundTask.stopService();
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(kBgUserId);
}

Future<void> updateForegroundNotification(String texto) async {
  await FlutterForegroundTask.updateService(notificationText: texto);
}

/// Relanza el foreground service si Android lo mató mientras el moto
/// estaba "en línea". Llámalo en AppLifecycleState.resumed para recuperación
/// silenciosa sin acción del moto. No hace nada si el servicio ya corre.
Future<void> asegurarServicioActivo(String userId) async {
  try {
    if (await FlutterForegroundTask.isRunningService) return;
    await startForegroundService(userId);
  } catch (_) {}
}

/// Solicita al OS que exima la app de la optimización de batería.
/// Solo muestra el diálogo si aún NO está exenta (una sola vez efectiva).
Future<void> pedirExencionBateria() async {
  try {
    final exenta = await FlutterForegroundTask.isIgnoringBatteryOptimizations;
    if (!exenta) {
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    }
  } catch (_) {}
}

void addBgDataCallback(void Function(Object) cb) {
  FlutterForegroundTask.addTaskDataCallback(cb);
}

void removeBgDataCallback(void Function(Object) cb) {
  FlutterForegroundTask.removeTaskDataCallback(cb);
}

@pragma('vm:entry-point')
void _startCallback() {
  FlutterForegroundTask.setTaskHandler(_ServiMotoTaskHandler());
}

class _ServiMotoTaskHandler extends TaskHandler {
  bool _gpsEnProceso = false;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    try {
      await Supabase.initialize(
        url: 'https://oukiofdtargjrclualgm.supabase.co',
        publishableKey: 'sb_publishable_rWZ5Ti_oNMnkrwZL8Wp1Sw_YGoSPK0D',
      );
    } catch (_) {}
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    _tickServicio(timestamp);
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    // NO desconectamos aquí: onDestroy se dispara cuando Android mata el
    // servicio en segundo plano. La desconexión real solo ocurre cuando:
    //   1. El moto pulsa "Desconectarse" en la app.
    //   2. El cron "limpiar_motos_zombis" detecta que ultimo_ping lleva
    //      más de 3 min sin actualizar.
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(kBgUserId);
    } catch (_) {}
  }

  void _tickServicio(DateTime ahora) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString(kBgUserId);
      if (userId == null) return;

      // ── 1. Ping ──────────────────────────────────────────────────────────
      try {
        await Supabase.instance.client.from('usuarios').update(
            {'ultimo_ping': ahora.toUtc().toIso8601String()}).eq('id', userId);
      } catch (_) {}

      // ── 2. GPS de respaldo ───────────────────────────────────────────────
      // El stream GPS principal vive en el isolate UI. Este bloque actúa
      // solo cuando ese stream está muerto o bloqueado por el fabricante.
      if (!_gpsEnProceso) {
        _gpsEnProceso = true;
        try {
          final serviceEnabled = await Geolocator.isLocationServiceEnabled();
          if (serviceEnabled) {
            final permission = await Geolocator.checkPermission();
            if (permission == LocationPermission.always ||
                permission == LocationPermission.whileInUse) {
              final pos = await Geolocator.getCurrentPosition(
                locationSettings: AndroidSettings(
                  accuracy: LocationAccuracy.high,
                  timeLimit: const Duration(seconds: 10),
                  intervalDuration: const Duration(seconds: 5),
                ),
              );
              await Supabase.instance.client.from('usuarios').update({
                'latitud': pos.latitude,
                'longitud': pos.longitude,
              }).eq('id', userId);
            }
          }
        } catch (_) {
        } finally {
          _gpsEnProceso = false;
        }
      }
    } catch (_) {} // guard: ninguna excepción escapa como Future no manejado
  }
}
