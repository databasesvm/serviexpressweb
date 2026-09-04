// Stubs sin-op para compilación web.
// flutter_foreground_task es Android/iOS únicamente — no compila en web.
// background_service.dart selecciona este archivo automáticamente en web.

// Constantes espejo — solo para que el código que las referencia en web compile.
const String kBgUserId             = 'bg_user_id';
const String kBgStartTime          = 'bg_start_time';
const String kBgProrroga           = 'bg_prorroga_time';
const String kBgAviso2h            = 'bg_aviso_2h';
const String kBgAviso4h            = 'bg_aviso_4h';
const String kBgMotivoDesconexion  = 'bg_motivo_desconexion';

Future<void> initBackgroundService() async {}
Future<void> startForegroundService(String userId) async {}
Future<void> stopForegroundService() async {}
Future<void> updateForegroundNotification(String texto) async {}
Future<void> resetBgInactivityTimer() async {}
void addBgDataCallback(void Function(Object) cb) {}
void removeBgDataCallback(void Function(Object) cb) {}
