// Stubs sin-op para compilación web.
// flutter_foreground_task es Android/iOS únicamente — no compila en web.
// background_service.dart selecciona este archivo automáticamente en web.

// Constante espejo — solo para que el código que la referencia en web compile.
const String kBgUserId = 'bg_user_id';

Future<void> initBackgroundService() async {}
Future<bool> startForegroundService(String userId) async => true;
Future<void> stopForegroundService() async {}
Future<void> updateForegroundNotification(String texto) async {}
Future<bool> asegurarServicioActivo(String userId) async => true;
Future<void> pedirExencionBateria() async {}
void addBgDataCallback(void Function(Object) cb) {}
void removeBgDataCallback(void Function(Object) cb) {}
