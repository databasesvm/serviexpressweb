// Stubs sin-op para compilación web.
// flutter_foreground_task es Android/iOS únicamente — no compila en web.
// background_service.dart selecciona este archivo automáticamente en web.

Future<void> initBackgroundService() async {}
Future<void> startForegroundService(String userId) async {}
Future<void> stopForegroundService() async {}
Future<void> updateForegroundNotification(String texto) async {}
Future<void> resetBgInactivityTimer() async {}
void addBgDataCallback(void Function(Object) cb) {}
void removeBgDataCallback(void Function(Object) cb) {}
