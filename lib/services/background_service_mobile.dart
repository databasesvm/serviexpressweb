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
      // Si el teléfono se reinicia estando conectado, el servicio arranca
      // solo. onStart decide si reconecta (reinicio rápido) o no.
      autoRunOnBoot: true,
      autoRunOnMyPackageReplaced: true,
      allowWakeLock: true,
    ),
  );
}

/// Arranca el servicio en segundo plano. Devuelve true si quedó corriendo.
/// Antes fallaba en silencio (faltaba declararlo en AndroidManifest.xml) y
/// nadie se enteraba: ahora la app puede avisarle al móvil.
Future<bool> startForegroundService(String userId) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kBgUserId, userId);
    if (await FlutterForegroundTask.isRunningService) return true;
    await FlutterForegroundTask.startService(
      notificationTitle: 'ServiExpress activo',
      notificationText: 'Conectado · recibiendo servicios',
      callback: _startCallback,
    );
  } catch (_) {}
  try {
    return await FlutterForegroundTask.isRunningService;
  } catch (_) {
    return false;
  }
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
Future<bool> asegurarServicioActivo(String userId) async {
  try {
    if (await FlutterForegroundTask.isRunningService) return true;
    return await startForegroundService(userId);
  } catch (_) {
    return false;
  }
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
  // Geocerca anti-falsos: 2 lecturas confiables seguidas fuera del paradero.
  int _lecturasFueraParadero = 0;
  // Última orden de GPS forzado ya atendida (usuarios.gps_forzado_at).
  // Así el "Reportar ausente" funciona aunque la app esté cerrada de recientes.
  String? _gpsForzadoAtendido;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    try {
      await Supabase.initialize(
        url: 'https://oukiofdtargjrclualgm.supabase.co',
        publishableKey: 'sb_publishable_rWZ5Ti_oNMnkrwZL8Wp1Sw_YGoSPK0D',
      );
    } catch (_) {}

    // Arranque por reinicio del teléfono: solo se reconecta si fue un
    // reinicio rápido (última señal hace menos de 15 min). Si el teléfono
    // estuvo apagado más tiempo (p. ej. terminó el turno sin desconectarse),
    // NO se pone en línea solo: se detiene el servicio.
    if (starter == TaskStarter.system) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final userId = prefs.getString(kBgUserId);
        if (userId == null) {
          await FlutterForegroundTask.stopService();
          return;
        }
        final u = await Supabase.instance.client
            .from('usuarios')
            .select('ultimo_ping, suspendido')
            .eq('id', userId)
            .maybeSingle();
        final ping = DateTime.tryParse(u?['ultimo_ping']?.toString() ?? '');
        final reciente = ping != null &&
            DateTime.now().toUtc().difference(ping.toUtc()).inMinutes < 15;
        if (reciente && u?['suspendido'] != true) {
          await Supabase.instance.client.from('usuarios').update({
            'en_linea': true,
            'ultimo_ping': DateTime.now().toUtc().toIso8601String(),
          }).eq('id', userId);
        } else {
          await prefs.remove(kBgUserId);
          await FlutterForegroundTask.stopService();
        }
      } catch (_) {}
    }
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
      // Si ultima_ubicacion_at tiene menos de 25s, el stream UI está activo
      // y enviando posición → omitimos getCurrentPosition para no duplicar
      // el consumo del chip GPS.
      if (!_gpsEnProceso) {
        _gpsEnProceso = true;
        try {
          // Guard: skip GPS si el stream UI ya actualizó en los últimos 25s,
          // SALVO que haya una orden de GPS forzado nueva (reporte de ausencia
          // o la central): esa se atiende siempre, aunque la app esté cerrada.
          bool streamUiActivo = false;
          bool forzado = false;
          try {
            final perfilPing = await Supabase.instance.client
                .from('usuarios')
                .select('ultima_ubicacion_at, gps_forzado_at')
                .eq('id', userId)
                .maybeSingle();
            final ubiStr = perfilPing?['ultima_ubicacion_at'] as String?;
            if (ubiStr != null) {
              final ubiAt = DateTime.tryParse(ubiStr);
              if (ubiAt != null &&
                  DateTime.now().toUtc().difference(ubiAt).inSeconds < 25) {
                streamUiActivo = true;
              }
            }
            final gf = perfilPing?['gps_forzado_at'] as String?;
            if (gf != null && gf != _gpsForzadoAtendido) {
              final gfAt = DateTime.tryParse(gf);
              // Orden reciente y posterior a la última ubicación enviada
              final ubiAt = ubiStr != null ? DateTime.tryParse(ubiStr) : null;
              if (gfAt != null &&
                  DateTime.now().toUtc().difference(gfAt.toUtc()).inMinutes < 2 &&
                  (ubiAt == null || ubiAt.isBefore(gfAt))) {
                forzado = true;
              }
              _gpsForzadoAtendido = gf;
            }
          } catch (_) {}

          final serviceEnabled = await Geolocator.isLocationServiceEnabled();
          if ((forzado || !streamUiActivo) && serviceEnabled) {
            final permission = await Geolocator.checkPermission();
            if (permission == LocationPermission.always ||
                permission == LocationPermission.whileInUse) {
              // Si el GPS no responde en 10 s, usar la última ubicación
              // conocida del teléfono (si tiene menos de 3 min) para no
              // perder la "ubicación reciente" que usa la cascada.
              Position? posLeida;
              try {
                posLeida = await Geolocator.getCurrentPosition(
                  locationSettings: AndroidSettings(
                    accuracy: LocationAccuracy.high,
                    timeLimit: const Duration(seconds: 10),
                    intervalDuration: const Duration(seconds: 5),
                  ),
                );
              } catch (_) {
                final ultima = await Geolocator.getLastKnownPosition();
                if (ultima != null &&
                    DateTime.now().difference(ultima.timestamp).inMinutes < 3) {
                  posLeida = ultima;
                }
              }
              if (posLeida == null) return;
              final pos = posLeida;
              await Supabase.instance.client.from('usuarios').update({
                'latitud': pos.latitude,
                'longitud': pos.longitude,
                // Hora real de la lectura del GPS (una posición guardada
                // trae su hora vieja → la central ve que el GPS no actualiza)
                'gps_fix_at': pos.timestamp.toUtc().toIso8601String(),
                'ultima_ubicacion_at': ahora.toUtc().toIso8601String(),
              }).eq('id', userId);

              // ── 3. Geofence de paradero en background ────────────────────
              // Si el móvil está registrado en un paradero, verificar si
              // sigue dentro del radio. Si salió, limpiar la fila desde
              // el foreground service — sin depender del isolate UI.
              try {
                final perfil = await Supabase.instance.client
                    .from('usuarios')
                    .select('paradero_actual')
                    .eq('id', userId)
                    .maybeSingle();
                final paraderoActual = perfil?['paradero_actual'] as String?;
                if (paraderoActual == null || paraderoActual.isEmpty) {
                  _lecturasFueraParadero = 0; // fuera de fila → conteo limpio
                }
                if (paraderoActual != null && paraderoActual.isNotEmpty) {
                  final paraderoData = await Supabase.instance.client
                      .from('paraderos')
                      .select('latitud, longitud, radio_metros')
                      .eq('nombre', paraderoActual)
                      .eq('activo', true)
                      .maybeSingle();
                  if (paraderoData != null) {
                    final pLat = (paraderoData['latitud'] as num).toDouble();
                    final pLng = (paraderoData['longitud'] as num).toDouble();
                    final radio = ((paraderoData['radio_metros'] as num?) ?? 150).toDouble();
                    final dist = Geolocator.distanceBetween(
                      pos.latitude, pos.longitude, pLat, pLng,
                    );
                    // Precisión ≤ 50 m y 2 lecturas seguidas fuera — una sola
                    // lectura mala de GPS ya no saca al móvil de la fila.
                    if (pos.accuracy <= 50) {
                      if (dist > radio + 50) {
                        _lecturasFueraParadero++;
                        if (_lecturasFueraParadero >= 2) {
                          _lecturasFueraParadero = 0;
                          await Supabase.instance.client
                              .from('usuarios')
                              .update({'paradero_actual': null, 'ingreso_fila': null})
                              .eq('id', userId);
                        }
                      } else {
                        _lecturasFueraParadero = 0;
                      }
                    }
                  }
                }
              } catch (_) {}
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
