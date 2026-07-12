// Selección de implementación en compile time:
//   Web        → background_service_stub.dart   (no-ops)
//   Android/iOS → background_service_mobile.dart (flutter_foreground_task)
//
// dart.library.io está disponible en Dart VM (Android/iOS) pero NO en web.
// dart.library.html está disponible en web pero NO en Dart VM.

export 'background_service_stub.dart'
    if (dart.library.io) 'background_service_mobile.dart';

