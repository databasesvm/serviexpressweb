// ignore_for_file: discarded_futures
// ============================================================================
// OPCIÓN B2 — Implementación Android/iOS con flutter_foreground_task.
// Este archivo NO se compila en web — background_service.dart lo excluye
// mediante conditional export (dart.library.io).
//
// TIMEOUT DE INACTIVIDAD:
//   - A las 2 h sin servicio activo → aviso en notificación + mensaje a la app
//   - 5 min después (prorroga) → desconexión forzada sin contemplación
//   - Si el moto tiene servicio activo, nunca se auto-desconecta por tiempo
//   - Si el moto abre la app → el timer se reinicia
// ============================================================================

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Claves de SharedPreferences (públicas para que movil_screen pueda resetearlas)
const String kBgUserId    = 'bg_user_id';
const String kBgStartTime = 'bg_start_time';    // epoch ms — inicio de sesión
const String kBgProrroga  = 'bg_prorroga_time'; // epoch ms — cuando se envió el aviso

const int _kMaxHorasConectado = 2; // horas sin servicio → aviso
const int _kProrrogaMinutos   = 5; // minutos de gracia tras el aviso

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
      eventAction: ForegroundTaskEventAction.repeat(60000),
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

/// Llamado desde movil_screen cuando el moto vuelve a la app.
/// Reinicia el contador de inactividad para que las 2h cuenten desde ahora.
Future<void> resetBgInactivityTimer() async {
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getString(kBgUserId) == null) return;
  await prefs.setInt(kBgStartTime, DateTime.now().millisecondsSinceEpoch);
  await prefs.remove(kBgProrroga);
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
    } catch (_) {}
  }

  void _tickServicio(DateTime ahora) async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString(kBgUserId);
    if (userId == null) return;

    // ── 1. Ping normal ──────────────────────────────────────────────────────
    try {
      await Supabase.instance.client
          .from('usuarios')
          .update({'ultimo_ping': ahora.toUtc().toIso8601String()})
          .eq('id', userId);
    } catch (_) {}

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

    // ── 3. Verificar si superó las 2 horas ─────────────────────────────────
    final startMs = prefs.getInt(kBgStartTime);
    if (startMs == null) return;
    final horas = ahora
        .difference(DateTime.fromMillisecondsSinceEpoch(startMs))
        .inHours;
    if (horas < _kMaxHorasConectado) return;

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
          ])
          .limit(1);

      if ((activos as List).isNotEmpty) {
        // Tiene servicio activo → reiniciar contador silenciosamente
        await prefs.setInt(kBgStartTime, ahora.millisecondsSinceEpoch);
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
        return;
      }

      // ── 5. Sin servicio → avisar y arrancar prorroga ────────────────────
      await prefs.setInt(kBgProrroga, ahora.millisecondsSinceEpoch);

      await FlutterForegroundTask.updateService(
        notificationTitle: '⚠️ ServiExpress — Inactividad',
        notificationText:
            'Serás desconectado en $_kProrrogaMinutos min. Abre la app para continuar.',
      );

      FlutterForegroundTask.sendDataToMain({
        'tipo': 'aviso_desconexion',
        'minutos': _kProrrogaMinutos,
      });
    } catch (_) {}
  }

  Future<void> _desconectarForzado(
      String userId, SharedPreferences prefs) async {
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
