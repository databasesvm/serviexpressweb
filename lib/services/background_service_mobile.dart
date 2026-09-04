// ignore_for_file: discarded_futures
// ============================================================================
// OPCIÓN B2 — Implementación Android/iOS con flutter_foreground_task.
// Este archivo NO se compila en web — background_service.dart lo excluye
// mediante conditional export (dart.library.io).
//
// TIMEOUT DE INACTIVIDAD:
//   - A las 2 h sin servicio activo → aviso suave (in-app) sin prorroga
//   - A las 4 h sin servicio activo → segundo aviso suave (in-app)
//   - A las 6 h sin servicio activo → aviso en notificación + prorroga 5 min
//   - 5 min después (prorroga) → desconexión forzada sin contemplación
//   - Si el moto tiene servicio activo, nunca se auto-desconecta por tiempo
//   - Si el moto abre la app → el timer se reinicia
// ============================================================================

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Claves de SharedPreferences (públicas para que movil_screen pueda resetearlas)
const String kBgUserId = 'bg_user_id';
const String kBgStartTime = 'bg_start_time'; // epoch ms — inicio de sesión
const String kBgProrroga =
    'bg_prorroga_time'; // epoch ms — cuando se envió el aviso
const String kBgAviso2h = 'bg_aviso_2h'; // bool — ya se envió aviso 2h
const String kBgAviso4h = 'bg_aviso_4h'; // bool — ya se envió aviso 4h
const String kBgMotivoDesconexion =
    'bg_motivo_desconexion'; // String — razón de la última desconexión forzada

const int _kAvisoMinutos = 345; // 5h 45min → aviso push + diálogo in-app
const int _kProrrogaMinutos = 15; // minutos entre aviso y desconexión

Future<void> initBackgroundService() async {
  FlutterForegroundTask.initCommunicationPort();
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'servimoto_foreground',
      channelName: 'ServiExpress activo',
      channelDescription:
          'Mantiene la app activa mientras el moto está conectado',
      // NORMAL evita que fabricantes agresivos (Xiaomi, Samsung, etc.)
      // maten el servicio cuando la app está en segundo plano.
      channelImportance: NotificationChannelImportance.DEFAULT,
      priority: NotificationPriority.DEFAULT,
    ),
    iosNotificationOptions: const IOSNotificationOptions(
      showNotification: false,
      playSound: false,
    ),
    foregroundTaskOptions: ForegroundTaskOptions(
      eventAction: ForegroundTaskEventAction.repeat(15000),
      autoRunOnBoot: false,
      autoRunOnMyPackageReplaced: true, // reinicia tras actualización de la app
      allowWakeLock: true,
    ),
  );
}

Future<void> startForegroundService(String userId) async {
  if (await FlutterForegroundTask.isRunningService) return;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(kBgUserId, userId);
  await prefs.setInt(kBgStartTime, DateTime.now().millisecondsSinceEpoch);
  await prefs.remove(kBgProrroga);
  await prefs.remove(kBgAviso2h);
  await prefs.remove(kBgAviso4h);
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
  await prefs.remove(kBgStartTime);
  await prefs.remove(kBgProrroga);
  await prefs.remove(kBgAviso2h);
  await prefs.remove(kBgAviso4h);
}

Future<void> updateForegroundNotification(String texto) async {
  await FlutterForegroundTask.updateService(notificationText: texto);
}

void addBgDataCallback(void Function(Object) cb) {
  FlutterForegroundTask.addTaskDataCallback(cb);
}

void removeBgDataCallback(void Function(Object) cb) {
  FlutterForegroundTask.removeTaskDataCallback(cb);
}

/// Llamado desde movil_screen cuando el moto pulsa "SIGO ACTIVO" o vuelve a la app.
/// Reinicia el contador de inactividad para que las 6h cuenten desde ahora.
Future<void> resetBgInactivityTimer() async {
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getString(kBgUserId) == null) return;
  await prefs.setInt(kBgStartTime, DateTime.now().millisecondsSinceEpoch);
  await prefs.remove(kBgProrroga);
  await prefs.remove(kBgAviso2h);
  await prefs.remove(kBgAviso4h);
  await FlutterForegroundTask.updateService(
    notificationTitle: 'ServiExpress activo',
    notificationText: 'Conectado · recibiendo servicios',
  );
}

@pragma('vm:entry-point')
void _startCallback() {
  FlutterForegroundTask.setTaskHandler(_ServiMotoTaskHandler());
}

class _ServiMotoTaskHandler extends TaskHandler {
  bool _gpsEnProceso =
      false; // Evita solapamiento si getCurrentPosition tarda más de 15s

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
    // servicio en segundo plano (sin intención del usuario). Poner en_linea=false
    // aquí causa las desconexiones arbitrarias al minimizar la app.
    //
    // La desconexión real solo ocurre en dos casos:
    //   1. El usuario pulsa "Desconectarse" en la app (movil_screen lo hace).
    //   2. El cron de Supabase "limpiar_motos_zombis" detecta que ultimo_ping
    //      lleva más de 3 min sin actualizar (app cerrada a la fuerza).
    //
    // Solo limpiamos las preferencias locales para que el próximo inicio
    // arranque el servicio limpio.
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(kBgUserId);
      await prefs.remove(kBgStartTime);
      await prefs.remove(kBgProrroga);
      await prefs.remove(kBgAviso2h);
      await prefs.remove(kBgAviso4h);
    } catch (_) {}
  }

  void _tickServicio(DateTime ahora) async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString(kBgUserId);
    if (userId == null) return;

    // ── 1. Ping normal + GPS de respaldo ────────────────────────────────────
    // El stream GPS principal vive en el isolate de la app. Si ese isolate
    // fue restringido por el fabricante, el foreground service (este isolate
    // separado) sirve como último respaldo: actualiza latitud/longitud cada 60s.
    try {
      await Supabase.instance.client.from('usuarios').update(
          {'ultimo_ping': ahora.toUtc().toIso8601String()}).eq('id', userId);
    } catch (_) {}

    // GPS respaldo: solo actualiza posición si la app logra obtenerla.
    // En la práctica, el stream principal del isolate UI lo hace cada 1-3s;
    // este bloque actúa solo cuando ese stream está muerto o bloqueado.
    // El flag _gpsEnProceso evita solapamiento si getCurrentPosition tarda
    // más de 15s (el nuevo intervalo del tick).
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
                timeLimit: const Duration(seconds: 12),
              ),
            );
            await Supabase.instance.client.from('usuarios').update({
              'latitud': pos.latitude,
              'longitud': pos.longitude
            }).eq('id', userId);
          }
        }
      } catch (_) {
        // GPS no disponible o timeout — no es crítico, el stream principal
        // se encarga cuando el hardware vuelva a estar disponible.
      } finally {
        _gpsEnProceso = false;
      }
    }

    // ── 2. Prorroga activa → comprobar si ya pasaron los 5 min ─────────────
    final prorrogaMs = prefs.getInt(kBgProrroga);
    if (prorrogaMs != null) {
      final minutos = ahora
          .difference(DateTime.fromMillisecondsSinceEpoch(prorrogaMs))
          .inMinutes;
      if (minutos >= _kProrrogaMinutos) {
        await _desconectarForzado(userId, prefs);
      }
      return; // no evaluar timeout mientras la prorroga está activa
    }

    // ── 3. Verificar tiempo transcurrido ────────────────────────────────────
    final startMs = prefs.getInt(kBgStartTime);
    if (startMs == null) return;
    final minutos = ahora
        .difference(DateTime.fromMillisecondsSinceEpoch(startMs))
        .inMinutes;

    // Solo actuamos a partir de 2h (120 min)
    if (minutos < 120) return;

    // Referencia local para el bloque de aviso final
    const int kAviso = _kAvisoMinutos;

    // ── 4. Comprobar si tiene servicio activo o está en fila de paradero ───
    try {
      final activos = await Supabase.instance.client
          .from('servicios')
          .select('id')
          .eq('movil_id', userId)
          .inFilter('estado', [
        'en_ruta_origen',
        'en_origen',
        'en_ruta_destino',
        'problema',
      ]).limit(1);

      if (activos.isNotEmpty) {
        // Tiene servicio activo → reiniciar contador silenciosamente
        await prefs.setInt(kBgStartTime, ahora.millisecondsSinceEpoch);
        await prefs.remove(kBgAviso2h);
        await prefs.remove(kBgAviso4h);
        return;
      }

      // Verificar si está en fila de un paradero
      final usuario = await Supabase.instance.client
          .from('usuarios')
          .select('paradero_actual')
          .eq('id', userId)
          .maybeSingle();

      if (usuario != null && usuario['paradero_actual'] != null) {
        // Está en fila esperando → reiniciar contador silenciosamente
        await prefs.setInt(kBgStartTime, ahora.millisecondsSinceEpoch);
        await prefs.remove(kBgAviso2h);
        await prefs.remove(kBgAviso4h);
        return;
      }

      // ── 5. Sin servicio — evaluar umbrales ──────────────────────────────

      // 5h 45min (345 min) → aviso push suave + diálogo in-app + prorroga 15min
      // El push usa sonido suave (sin canal de alarma) para que el moto sepa
      // que debe abrir la app, pero sin confundirlo con un servicio nuevo.
      if (minutos >= kAviso) {
        await prefs.setInt(kBgProrroga, ahora.millisecondsSinceEpoch);
        await FlutterForegroundTask.updateService(
          notificationTitle: '⏱️ ServiExpress — Inactividad',
          notificationText:
              'Llevas 5h45min sin actividad. Serás desconectado en $_kProrrogaMinutos min.',
        );
        // Push con sonido suave (sin existing_android_channel_id → no alarma)
        try {
          await Supabase.instance.client.functions.invoke(
            'send-notification',
            body: {
              'include_external_user_ids': [userId],
              'headings': {'en': '⏱️ Inactividad', 'es': '⏱️ Inactividad'},
              'contents': {
                'en':
                    'Llevas 5h45min sin tomar servicios. Serás desconectado en $_kProrrogaMinutos min si no hay actividad.',
                'es':
                    'Llevas 5h45min sin tomar servicios. Serás desconectado en $_kProrrogaMinutos min si no hay actividad.',
              },
              'priority': 7,
              'android_sound': 'movil_inactividad',
              'ios_sound': 'movil_inactividad.mp3',
              'existing_android_channel_id': 'serviexpress_inactividad_v1',
              'data': {'tipo': 'aviso_inactividad_push'},
            },
          );
        } catch (_) {}
        FlutterForegroundTask.sendDataToMain({
          'tipo': 'aviso_desconexion',
          'minutos': _kProrrogaMinutos,
        });
        return;
      }

      // Los avisos de 2h y 4h fueron eliminados — solo existe el aviso final
      // a las 5h45min con push y diálogo in-app.
    } catch (_) {}
  }

  Future<void> _desconectarForzado(
      String userId, SharedPreferences prefs) async {
    // Avisar al isolate principal ANTES de cambiar la BD, para que el
    // _vigilanteDeConexion no interprete esto como un zombie-cleanup y
    // reafirme la conexión anulando la desconexión intencional.
    FlutterForegroundTask.sendDataToMain({
      'tipo': 'desconexion_forzada_inactividad',
    });
    // Pequeña pausa para que el mensaje llegue al main isolate
    await Future.delayed(const Duration(milliseconds: 500));
    // Guardar motivo para mostrarlo cuando el moto abra la app
    await prefs.setString(kBgMotivoDesconexion, 'inactividad_6h');
    try {
      await Supabase.instance.client.from('usuarios').update({
        'en_linea': false,
        'paradero_actual': null,
        'ingreso_fila': null,
      }).eq('id', userId);
    } catch (_) {}
    await prefs.remove(kBgUserId);
    await prefs.remove(kBgStartTime);
    await prefs.remove(kBgProrroga);
    await FlutterForegroundTask.stopService();
  }
}
