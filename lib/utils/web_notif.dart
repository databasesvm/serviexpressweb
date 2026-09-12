// lib/utils/web_notif.dart
// Exportación condicional: en web usa dart:html, en móvil usa el stub vacío.
export 'web_notif_stub.dart' if (dart.library.html) 'web_notif_web.dart';
